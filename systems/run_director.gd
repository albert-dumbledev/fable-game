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
## Per-event next-fire clock (repeating events re-arm; one-shots go INF).
var _next_event_at: PackedFloat64Array = []


func _ready() -> void:
	GameManager.state = GameManager.State.IN_RUN
	add_to_group(&"run_director")
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


## Scheduled spawns (bosses, ambushes, repeating swarms) from the WaveTable.
func _fire_due_events() -> void:
	var table := spawner.wave_table
	if table == null:
		return
	if _next_event_at.size() != table.events.size():
		_next_event_at.resize(table.events.size())
		for i: int in table.events.size():
			_next_event_at[i] = table.events[i].time
	for i: int in table.events.size():
		if elapsed < _next_event_at[i]:
			continue
		var event := table.events[i]
		_next_event_at[i] = elapsed + event.repeat_every if event.repeat_every > 0.0 else INF
		if event.announcement != "":
			EventBus.wave_announcement.emit(event.announcement)
		for j: int in event.count:
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


## Quit from the pause menu: bank progress and take the same handoff as
## dying (stats + shop), minus the death itself.
func abandon_run() -> void:
	if not _run_active:
		return
	_run_active = false
	MetaProgression.save_game()
	GameManager.end_run.call_deferred(
			{"time": elapsed, "kills": kills, "gold": gold_earned, "abandoned": true})
