class_name RunDirector
extends Node
## Owns one run: elapsed time, kill/gold tally, spawner pacing, and the
## death -> stats handoff to GameManager.

@onready var spawner: Spawner = $Spawner

const PICKUP_SCENE := preload("res://actors/pickups/Pickup.tscn")

# Level cadence target ~10-30s. A gentle geometric curve keeps that roughly
# constant as XP income ramps, while big chunks (swarms, bosses) still pop
# multiple levels at once via the while-loop in _grant_xp.
const XP_BASE := 14.0
const XP_GROWTH := 1.14

var elapsed := 0.0
var kills := 0
var gold_earned := 0
var xp := 0
var level := 0

var _run_active := true
## Per-event next-fire clock (repeating events re-arm; one-shots go INF).
var _next_event_at: PackedFloat64Array = []

## Boss-wave coordination: the relic drops (and the arena clears + spawns pause)
## only once EVERY boss of the wave is dead — the 2nd wave has two juggernauts.
var _spawning_paused := false
var _alive_bosses: Array[EnemyBase] = []
var _last_boss_data: EnemyData
var _last_boss_pos := Vector3.ZERO


func _ready() -> void:
	GameManager.state = GameManager.State.IN_RUN
	add_to_group(&"run_director")
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.player_died.connect(_on_player_died)
	EventBus.unlock_claimed.connect(_on_unlock_claimed)
	EventBus.run_started.emit()
	# Deferred so the HUD (readied after us) catches the initial state.
	EventBus.xp_changed.emit.call_deferred(xp, _xp_required(level), level)


func _physics_process(delta: float) -> void:
	if not _run_active:
		return
	elapsed += delta
	# Spawning pauses after a boss wave clears, so the player can collect the
	# relic in peace; the run timer keeps advancing.
	if _spawning_paused:
		return
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
				_track_boss(enemy, event.enemy)


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
	return int(round(XP_BASE * pow(XP_GROWTH, current_level)))


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


## Register a spawned boss so the wave can tell when the last one falls.
func _track_boss(boss: EnemyBase, boss_data: EnemyData) -> void:
	_alive_bosses.append(boss)
	_last_boss_data = boss_data
	boss.health.died.connect(_on_boss_died.bind(boss))


func _on_boss_died(boss: EnemyBase) -> void:
	_alive_bosses.erase(boss)
	if is_instance_valid(boss):
		_last_boss_pos = boss.global_position
	if _alive_bosses.is_empty():
		_on_boss_wave_cleared()


## The last boss of a wave just died. If a weapon relic is owed, clear the
## remaining minions and pause spawning so the player can walk to it in peace,
## then drop the relic where the boss fell. Nothing special if all owned.
func _on_boss_wave_cleared() -> void:
	var ability := _next_unlock_drop(_last_boss_data)
	if ability == &"":
		return
	_spawning_paused = true
	# Clear minions (but let the dying bosses finish their loot choreography).
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if is_instance_valid(enemy) and not (enemy is BossEnemy):
			enemy.queue_free()
	_spawn_relic(ability, _last_boss_pos)


func _next_unlock_drop(boss_data: EnemyData) -> StringName:
	if boss_data == null:
		return &""
	var owned := MetaProgression.get_granted_abilities()
	for ability: StringName in boss_data.unlock_drops:
		if not owned.has(ability):
			return ability
	return &""


func _spawn_relic(ability: StringName, position: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var relic := PICKUP_SCENE.instantiate() as Pickup
	relic.ability = ability
	relic.setup(&"unlock", 1, Vector3(0.0, 6.0, 0.0))
	scene.add_child(relic)
	relic.global_position = position + Vector3(0.0, 1.2, 0.0)


## The relic was claimed. The staff is the run-ending prize — leave spawning
## paused and let the ClaimScreen's "RUN COMPLETE" acknowledgement drive the
## victory handoff (finish_victory), so an immediate scene change can't yank the
## overlay away. Any other relic just resumes the wave.
func _on_unlock_claimed(ability: StringName) -> void:
	if ability == &"weapon_staff":
		return
	_spawning_paused = false


## Called by the ClaimScreen's Continue on the staff claim: bank the run and hand
## off to the victory screen. The arena is already cleared and spawning paused,
## so nothing can kill the player in between. Idempotent against a double-press.
func finish_victory() -> void:
	if not _run_active:
		return
	_run_active = false
	MetaProgression.save_game()
	GameManager.end_run({"time": elapsed, "kills": kills, "gold": gold_earned, "victory": true})
