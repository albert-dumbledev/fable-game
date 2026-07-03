class_name RunDirector
extends Node
## Owns one run: elapsed time, kill/gold tally, spawner pacing, and the
## death -> stats handoff to GameManager.

@onready var spawner: Spawner = $Spawner

const XP_BASE := 20
const XP_PER_LEVEL := 15

var elapsed := 0.0
var kills := 0
var gold_earned := 0
var xp := 0
var level := 0

var _run_active := true
var _event_index := 0


func _ready() -> void:
	GameManager.state = GameManager.State.IN_RUN
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.player_died.connect(_on_player_died)
	EventBus.run_started.emit()
	# Deferred so the HUD (readied after us) catches the initial state.
	EventBus.xp_changed.emit.call_deferred(xp, _xp_required(level), level)


func _physics_process(delta: float) -> void:
	if not _run_active:
		return
	elapsed += delta
	spawner.tick(elapsed, delta)
	_fire_due_events()


## Scheduled spawns (bosses, ambushes) from the WaveTable, in time order.
func _fire_due_events() -> void:
	var table := spawner.wave_table
	if table == null:
		return
	while _event_index < table.events.size() and elapsed >= table.events[_event_index].time:
		var event := table.events[_event_index]
		_event_index += 1
		if event.announcement != "":
			EventBus.wave_announcement.emit(event.announcement)
		for i: int in event.count:
			var enemy := spawner.spawn_enemy(event.enemy, elapsed)
			if enemy != null and event.enemy.tags.has(&"boss"):
				EventBus.boss_spawned.emit(enemy)


func _on_enemy_killed(_enemy_data: Resource, _position: Vector3) -> void:
	if not _run_active:
		return
	kills += 1
	# Gold/XP are no longer granted here — enemies drop collectable
	# pickups, and rewards land in _on_pickup_collected.


func _on_pickup_collected(kind: StringName, value: int) -> void:
	if not _run_active:
		return
	match kind:
		&"gold":
			gold_earned += value
			MetaProgression.add_currency(&"gold", value)
		&"xp":
			_grant_xp(value)


func _grant_xp(amount: int) -> void:
	xp += amount
	while xp >= _xp_required(level):
		xp -= _xp_required(level)
		level += 1
		EventBus.level_up.emit(level)
	EventBus.xp_changed.emit(xp, _xp_required(level), level)


func _xp_required(current_level: int) -> int:
	return XP_BASE + current_level * XP_PER_LEVEL


func _on_player_died() -> void:
	if not _run_active:
		return
	_run_active = false
	MetaProgression.save_game()
	# Deferred: player_died fires mid-physics-frame; changing scene immediately
	# would yank nodes out of the tree while they still get processed this frame.
	GameManager.end_run.call_deferred({"time": elapsed, "kills": kills, "gold": gold_earned})
