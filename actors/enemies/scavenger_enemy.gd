class_name ScavengerEnemy
extends EnemyBase
## The loot-eater (fat burrowing rat): ignores the player entirely and eats
## uncollected gold/XP off the ground. Each meal fattens its belly and grows the
## bounty (eaten x1.25). After 12 pieces or 18s it burrows out and the loot is
## GONE — kill it first and the bounty erupts as a fountain: your loot, with
## interest. Its whole threat is economic; it never attacks.

enum Mode { SEEK, EAT, BURROW }

const EAT_RANGE := 1.3
const EAT_TIME := 0.35
const SATED_COUNT := 6
const SATED_SPEED := 5.8
const BURROW_COUNT := 12
const BURROW_TIME := 18.0
const BURROW_TELEGRAPH := 0.9
const BURROW_RADIUS := 1.4
const BOUNTY_MULT := 1.25
const GOLD_TINT := Color(1.0, 0.82, 0.25)
const DUST_COLOR := Color(0.55, 0.45, 0.3, 0.5)

var _mode: Mode = Mode.SEEK
var _eat_timer := 0.0
var _alive_time := 0.0
var _eaten_count := 0
var _eaten_gold := 0
var _eaten_xp := 0
var _sated := false
var _target_pickup: Pickup


## Ignores the player: seek nearest ground loot, eat it, then burrow out. All
## logic lives in CHASE (it never winds up or attacks).
func _chase() -> void:
	if _mode == Mode.BURROW:
		_hold_still()
		return
	var delta := get_physics_process_delta_time()
	_alive_time += delta
	if _eaten_count >= BURROW_COUNT or _alive_time >= BURROW_TIME:
		_begin_burrow()
		return
	match _mode:
		Mode.SEEK:
			_seek()
		Mode.EAT:
			_eat(delta)


func _seek() -> void:
	_target_pickup = _nearest_edible()
	if _target_pickup == null:
		_hold_still()
		return
	var to_food := _target_pickup.global_position - global_position
	to_food.y = 0.0
	if to_food.length() <= EAT_RANGE:
		_mode = Mode.EAT
		_eat_timer = EAT_TIME
		_hold_still()
		return
	var dir := to_food.normalized()
	velocity.x = dir.x * move_speed()
	velocity.z = dir.z * move_speed()


func _eat(delta: float) -> void:
	if _target_pickup == null or not is_instance_valid(_target_pickup) \
			or not _target_pickup.is_inside_tree():
		_mode = Mode.SEEK
		return
	if global_position.distance_to(_target_pickup.global_position) > EAT_RANGE * 1.4:
		_mode = Mode.SEEK  # it drifted off (magnet) — chase again
		return
	_hold_still()
	_eat_timer -= delta
	if _eat_timer <= 0.0:
		_devour(_target_pickup)
		_target_pickup = null
		_mode = Mode.SEEK


func _devour(pickup: Pickup) -> void:
	var kind := pickup.kind
	var v := pickup.consume()
	if kind == &"gold":
		_eaten_gold += v
	else:
		_eaten_xp += v
	_eaten_count += 1
	if _eaten_count >= SATED_COUNT:
		_sated = true
	AudioManager.play_at(&"scavenger_gulp", global_position)
	_update_belly()


## Belly inflates and gold-tints as it fills — the visible bounty.
func _update_belly() -> void:
	var t := clampf(float(_eaten_count) / float(BURROW_COUNT), 0.0, 1.0)
	if _material != null:
		_material.albedo_color = _base_color.lerp(GOLD_TINT, t * 0.7)
	mesh.scale = Vector3(1.0 + t * 0.5, 1.0, 1.0 + t * 0.5)


func _nearest_edible() -> Pickup:
	var best: Pickup = null
	var best_d := INF
	for pickup: Pickup in Pickup.edible:
		if not is_instance_valid(pickup) or not pickup.is_inside_tree():
			continue
		var d := global_position.distance_squared_to(pickup.global_position)
		if d < best_d:
			best_d = d
			best = pickup
	return best


## Stop and telegraph the dig-out; if not killed in BURROW_TELEGRAPH it escapes
## with the loot (queue_free, no fountain).
func _begin_burrow() -> void:
	if _mode == Mode.BURROW:
		return
	_mode = Mode.BURROW
	_hold_still()
	var scene := get_tree().current_scene
	GroundTelegraph.spawn(scene, Vector3(global_position.x, 0.05, global_position.z),
			BURROW_RADIUS, BURROW_TELEGRAPH, DUST_COLOR)
	AudioManager.play_at(&"scavenger_burrow", global_position)
	get_tree().create_timer(BURROW_TELEGRAPH, false).timeout.connect(_finish_burrow)


func _finish_burrow() -> void:
	if not is_inside_tree() or state == State.DEAD:
		return
	ShardBurst.spawn(get_tree().current_scene, global_position, DUST_COLOR, 12, 5.0, 0.12)
	queue_free()


## Faster once its belly is full — it scurries to grab the rest before bolting.
func move_speed() -> float:
	return (SATED_SPEED if _sated else data.move_speed) * _slow_mult


## It ignores the player, so face the food instead of the player.
func _face_target() -> void:
	if _target_pickup == null or not is_instance_valid(_target_pickup):
		return
	var to_food := _target_pickup.global_position - global_position
	if to_food.length() < 0.01:
		return
	rotation.y = atan2(-to_food.x, -to_food.z)


## Killed before it burrows: refund the bounty (eaten x1.25) as gold/XP
## fountains via the base death flow. Nothing eaten -> no fountain.
func _spawn_pickups(kind: StringName, _total: int) -> void:
	var bounty := int(ceil(_eaten_gold * BOUNTY_MULT)) if kind == &"gold" \
			else int(ceil(_eaten_xp * BOUNTY_MULT))
	_spawn_pickup_pieces(kind, bounty, MAX_PICKUP_PIECES, 1.5, true)
