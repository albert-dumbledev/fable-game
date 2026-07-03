class_name Pickup
extends Node3D
## Collectable dropped by dying enemies. Bursts outward ballistically,
## bounces to rest, then magnets to the player once they come near.
## No physics body — manual motion keeps hundreds of these cheap.

const MAGNET_RADIUS := 4.5
const MAGNET_SPEED := 13.0
const MAGNET_ACCEL := 50.0
const COLLECT_RADIUS := 0.85
const LIFETIME := 30.0
const GRAVITY := 18.0
const REST_Y := 0.3
const SPIN_SPEED := 3.0
const ARENA_HALF := 19.0

var kind: StringName = &"gold"
var value := 1

var _velocity := Vector3.ZERO
var _age := 0.0
var _target: Node3D

@onready var gold_mesh: MeshInstance3D = $GoldMesh
@onready var xp_mesh: MeshInstance3D = $XpMesh


## Call before adding to the tree.
func setup(p_kind: StringName, p_value: int, burst_velocity: Vector3) -> void:
	kind = p_kind
	value = p_value
	_velocity = burst_velocity


func _ready() -> void:
	gold_mesh.visible = kind == &"gold"
	xp_mesh.visible = kind == &"xp"
	_target = get_tree().get_first_node_in_group(&"player") as Node3D


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	rotate_y(SPIN_SPEED * delta)
	if _target != null and is_instance_valid(_target) and _target.is_inside_tree():
		var to_player := _target.global_position + Vector3(0.0, 0.9, 0.0) - global_position
		var dist := to_player.length()
		if dist <= COLLECT_RADIUS:
			EventBus.pickup_collected.emit(kind, value)
			queue_free()
			return
		if dist <= MAGNET_RADIUS:
			_velocity = _velocity.move_toward(to_player / dist * MAGNET_SPEED, MAGNET_ACCEL * delta)
			global_position += _velocity * delta
			return
	# Ballistic scatter: gravity, then a damped bounce on the floor.
	_velocity.y -= GRAVITY * delta
	global_position += _velocity * delta
	global_position.x = clampf(global_position.x, -ARENA_HALF, ARENA_HALF)
	global_position.z = clampf(global_position.z, -ARENA_HALF, ARENA_HALF)
	if global_position.y <= REST_Y and _velocity.y < 0.0:
		global_position.y = REST_Y
		_velocity.y *= -0.35
		_velocity.x *= 0.6
		_velocity.z *= 0.6
		if absf(_velocity.y) < 0.8:
			_velocity = Vector3.ZERO
