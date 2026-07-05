class_name GildedEnemy
extends EnemyBase
## The Gilded One: a rare fleeing jackpot that never attacks — it positions you.
## It flees the player, biased toward the densest nearby enemy cluster and
## wall-sliding at the arena edge, so chasing it drags you into packs and
## corners. Catch it (dash / Frost Nova / prediction / ranged) within 30s or it
## despawns in a mocking shimmer. Killing it bursts a wide gold/XP jackpot ring
## where it fell — usually inside the pack it led you into.

const CLUSTER_N := 5
const CLUSTER_WEIGHT := 0.8
const JITTER_INTERVAL := 1.2
const JITTER_STRENGTH := 0.5
const DESPAWN_TIME := 30.0
const ARENA_HALF := 18.5
## Past this fraction of the half-extent, fleeing blends in a wall-slide.
const EDGE := ARENA_HALF * 0.85
const TRAIL_INTERVAL := 0.2
const GOLD_COLOR := Color(1.0, 0.82, 0.2)

var _jitter := Vector3.ZERO
var _cluster_bias := Vector3.ZERO
var _jitter_time := 0.0
var _trail_time := 0.0


func _ready() -> void:
	super()
	AudioManager.play_at(&"gilded_glimmer", global_position)
	get_tree().create_timer(DESPAWN_TIME, false).timeout.connect(_despawn)


## Flee the player, biased toward the nearest enemy cluster, wall-sliding at the
## edge, with a re-rolled jitter so straight-line prediction isn't free.
func _chase() -> void:
	var delta := get_physics_process_delta_time()
	_jitter_time -= delta
	if _jitter_time <= 0.0:
		_jitter_time = JITTER_INTERVAL
		_reroll()
	var to_player := _target.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var away := (-to_player / dist) if dist > 0.01 else Vector3(0.0, 0.0, 1.0)
	var dir := away + _cluster_bias * CLUSTER_WEIGHT + _jitter
	if dir.length() < 0.01:
		dir = away
	dir = _wall_slide(dir.normalized())
	velocity.x = dir.x * move_speed()
	velocity.z = dir.z * move_speed()


## Re-roll the wander jitter and recompute the cluster bias (cheap here because
## it only runs on the JITTER_INTERVAL cadence, not every frame).
func _reroll() -> void:
	var a := randf() * TAU
	_jitter = Vector3(cos(a), 0.0, sin(a)) * JITTER_STRENGTH
	_cluster_bias = _cluster_dir()


## Direction toward the average position of the CLUSTER_N closest other enemies.
func _cluster_dir() -> Vector3:
	var others: Array[EnemyBase] = []
	for enemy: EnemyBase in EnemyBase.alive:
		if enemy == self or not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		others.append(enemy)
	if others.is_empty():
		return Vector3.ZERO
	others.sort_custom(_closer)
	var n := mini(CLUSTER_N, others.size())
	var avg := Vector3.ZERO
	for i: int in n:
		avg += others[i].global_position
	avg /= float(n)
	var to_cluster := avg - global_position
	to_cluster.y = 0.0
	return to_cluster.normalized() if to_cluster.length() > 0.01 else Vector3.ZERO


func _closer(a: EnemyBase, b: EnemyBase) -> bool:
	return global_position.distance_squared_to(a.global_position) \
			< global_position.distance_squared_to(b.global_position)


## Blend a wall-slide into the flee direction near the arena edge so the Gilded
## runs along the wall instead of pinning into a corner (mirrors CasterBoss).
func _wall_slide(dir: Vector3) -> Vector3:
	var into_wall := Vector3.ZERO
	if global_position.x > EDGE and dir.x > 0.0:
		into_wall.x = 1.0
	elif global_position.x < -EDGE and dir.x < 0.0:
		into_wall.x = -1.0
	if global_position.z > EDGE and dir.z > 0.0:
		into_wall.z = 1.0
	elif global_position.z < -EDGE and dir.z < 0.0:
		into_wall.z = -1.0
	if into_wall == Vector3.ZERO:
		return dir
	var wall := into_wall.normalized()
	var slide := dir - dir.project(wall)
	if slide.length() < 0.15:
		slide = Vector3(-wall.z, 0.0, wall.x)
	return slide.normalized()


func _physics_process(delta: float) -> void:
	super(delta)
	if state == State.DEAD or not is_inside_tree():
		return
	_trail_time -= delta
	if _trail_time <= 0.0:
		_trail_time = TRAIL_INTERVAL
		ShardBurst.spawn(get_tree().current_scene, global_position + Vector3(0.0, 1.0, 0.0),
				GOLD_COLOR, 2, 2.0, 0.08, 0.4)


## Uncaught: vanish in a mocking gold shimmer, dropping nothing (it escaped).
func _despawn() -> void:
	if not is_inside_tree() or state == State.DEAD:
		return
	var scene := get_tree().current_scene
	AudioManager.play_at(&"gilded_glimmer", global_position)
	ShardBurst.spawn(scene, global_position + Vector3(0.0, 1.0, 0.0), GOLD_COLOR, 16, 7.0, 0.14)
	BlastVfx.spawn(scene, global_position + Vector3(0.0, 0.2, 0.0), 1.6,
			Color(1.0, 0.85, 0.2, 0.5), 0.2, 0.3)
	queue_free()


## Killed: a deep jackpot thunk under the coin fountain, then the base death
## (which routes gold/XP through the wide ring via the _spawn_pickups override).
func _on_died() -> void:
	AudioManager.play_at(&"gilded_jackpot", global_position)
	super()


## The jackpot bursts WIDE and evenly (ring) rather than the default tight pop —
## the payout scatters across the pack the Gilded led you into.
func _spawn_pickups(kind: StringName, total: int) -> void:
	_spawn_pickup_pieces(kind, total, MAX_PICKUP_PIECES, 1.6, true)
