class_name Spawner
extends Node
## Places enemies in a ring around the player, outside melee range but inside
## the arena. Pacing and scaling come from the WaveTable; RunDirector drives it.

const ARENA_HALF := 18.5
const RING_MIN := 14.0
const RING_MAX := 22.0
const SPAWN_HEIGHT := 1.0

## Elite variants (Aspect Drops M1). Only regular-cadence pool spawns past
## ELITE_MIN_ELAPSED roll for elites. The raw 3% is ~7/min at late spawn
## cadence — far too hot — so the roll is gated to one elite alive at a time
## with a cooldown between spawns; both must pass before the dice are rolled.
const ELITE_MIN_ELAPSED := 240.0
const ELITE_CHANCE := 0.03
const ELITE_COOLDOWN := 50.0

@export var wave_table: WaveTable

## The active Depth (docs/DEPTHS.md), set by RunDirector. null = Surface: every
## code path below reads it as identity so Surface runs are byte-identical.
var depth: DepthData

var _spawn_timer := 0.0
var _elite_cooldown := 0.0


func tick(elapsed: float, delta: float) -> void:
	if wave_table == null:
		return
	_elite_cooldown = maxf(0.0, _elite_cooldown - delta)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	var interval := wave_table.spawn_interval_at(elapsed)
	var cap := wave_table.max_alive_at(elapsed)
	if depth != null:
		interval *= depth.interval_mult
		cap += depth.alive_cap_bonus
	_spawn_timer = interval
	if EnemyBase.alive.size() >= cap:
		return
	_spawn(elapsed)


func _spawn(elapsed: float) -> void:
	var data := wave_table.pick_enemy(elapsed)
	if _should_make_elite(elapsed, data):
		if spawn_enemy(data, elapsed, true) != null:
			_elite_cooldown = ELITE_COOLDOWN
			AudioManager.play(&"elite_spawn")
		return
	spawn_enemy(data, elapsed)


## Elite gate for pool spawns: past the time lock, off cooldown, under the alive
## cap, and not a boss/finale (those never reach _spawn, but guard anyway). Only
## when all of those hold does the ELITE_CHANCE roll happen. Deep runs both open
## the window earlier and allow more elites at once (docs/DEPTHS.md M3).
func _should_make_elite(elapsed: float, data: EnemyData) -> bool:
	if elapsed < _elite_min_elapsed() or _elite_cooldown > 0.0:
		return false
	if data == null or data.tags.has(&"boss") or data.tags.has(&"finale"):
		return false
	if _elite_alive():
		return false
	return randf() < ELITE_CHANCE


## The elite time lock: the Depth's override when it sets one (>= 0), else the
## Spawner default. Surface (null depth) always reads the default.
func _elite_min_elapsed() -> float:
	if depth != null and depth.elite_min_elapsed >= 0.0:
		return depth.elite_min_elapsed
	return ELITE_MIN_ELAPSED


## The concurrent-elite cap: the Depth's when on a depth run, else 1 (Surface's
## today-behavior). Read as a structural handle by the smoke.
func _elite_max_alive() -> int:
	return depth.elite_max_alive if depth != null else 1


## True once the concurrent-elite cap is reached — a count check against
## _elite_max_alive (Surface: 1, i.e. today's one-at-a-time gate).
func _elite_alive() -> bool:
	var cap := _elite_max_alive()
	var count := 0
	for enemy: EnemyBase in EnemyBase.alive:
		if is_instance_valid(enemy) and enemy.is_elite:
			count += 1
			if count >= cap:
				return true
	return false


## Spawns a specific enemy in the ring around the player, with time-scaled
## stats. Used by both the regular cadence and scheduled wave events. `elite`
## promotes the spawn (pool cadence only — wave events pass the default false).
func spawn_enemy(data: EnemyData, elapsed: float, elite: bool = false) -> EnemyBase:
	if data == null or data.scene == null:
		return null
	var target := get_tree().get_first_node_in_group(&"player") as Node3D
	if target == null:
		return null
	var enemy := data.scene.instantiate() as EnemyBase
	if enemy == null:
		return null
	# Depth folds its flat mults on top of the WaveTable's time scaling; this one
	# site covers pool spawns, scheduled events, and death-spawned Broodlings
	# (children inherit the parent's mults in EnemyBase._spawn_death_spawns).
	var hp := wave_table.hp_mult_at(elapsed)
	var dmg := wave_table.dmg_mult_at(elapsed)
	var reward := wave_table.reward_mult_at(elapsed)
	if depth != null:
		hp *= depth.hp_mult
		dmg *= depth.dmg_mult
		reward *= depth.reward_mult
	enemy.setup(data, hp, dmg, reward)
	# make_elite folds the ×4 HP into _hp_mult, which _ready reads — so it must
	# land before add_child (which triggers _ready).
	if elite:
		enemy.make_elite()
	var angle := randf() * TAU
	var radius := randf_range(RING_MIN, RING_MAX)
	var pos := target.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	pos.x = clampf(pos.x, -ARENA_HALF, ARENA_HALF)
	pos.z = clampf(pos.z, -ARENA_HALF, ARENA_HALF)
	pos.y = SPAWN_HEIGHT
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = pos
	return enemy
