class_name Warhammer
extends Weapon
## Two-handed slam weapon: no shield and no block (can_block=false in the
## data). LMB hauls the head up as a telegraph, then crashes it down in
## front of the player — everything near the impact point takes full damage,
## a wider ring takes splash damage, and the whole pack gets shoved.

const REST_POS := Vector3(0.35, -0.25, 0.0)
const REST_ROT := Vector3(25.0, -12.0, 6.0)
const RAISED_POS := Vector3(0.12, 0.28, 0.15)
const RAISED_ROT := Vector3(80.0, 0.0, 0.0)
const SLAM_POS := Vector3(0.0, -0.5, -0.35)
const SLAM_ROT := Vector3(-75.0, 0.0, 0.0)
## Where the head lands: this far in front of the player, at ground level.
const IMPACT_DISTANCE := 2.2
const INNER_RADIUS := 2.4
const OUTER_RADIUS := 4.2
const SPLASH_DAMAGE_MULT := 0.4
const SHOVE_FORCE := 9.0
const SHOCKWAVE_COLOR := Color(1.0, 0.75, 0.35, 0.55)

@onready var hammer_pivot: Node3D = $HammerPivot
@onready var handle_mesh: MeshInstance3D = $HammerPivot/HandleMesh

var _swing_tween: Tween


func _ready() -> void:
	hammer_pivot.position = REST_POS
	hammer_pivot.rotation_degrees = REST_ROT
	# Cylinder axis is Y; lay the handle along the pivot's -Z reach.
	handle_mesh.rotation_degrees.x = 90.0


func _do_attack(duration: float) -> void:
	var damage := weapon_data.damage + stats.get_stat(Stats.DAMAGE)
	if _swing_tween != null:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_parallel(true)
	# 1) Haul the hammer up overhead — the telegraph.
	_swing_tween.tween_property(hammer_pivot, "position", RAISED_POS, duration * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", RAISED_ROT, duration * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2) Crash down fast; damage lands the moment the head hits the ground.
	_swing_tween.chain().tween_property(hammer_pivot, "position", SLAM_POS, duration * 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", SLAM_ROT, duration * 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.chain().tween_callback(_impact.bind(damage))
	# 3) Drag it back up to the ready stance.
	_swing_tween.chain().tween_property(hammer_pivot, "position", REST_POS, duration * 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", REST_ROT, duration * 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## The slam is a ground AoE, not a hitbox sweep: full damage inside
## INNER_RADIUS of the impact point, splash out to OUTER_RADIUS, and a
## radial shove for everything caught. Damage flows through hurtboxes so
## numbers, drops, and mitigation all work as usual.
func _impact(damage: float) -> void:
	if wielder == null or not is_inside_tree():
		return
	var forward := -wielder.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var point := wielder.global_position + forward * IMPACT_DISTANCE
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as EnemyBase
		if enemy == null or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - point
		offset.y = 0.0
		var dist := offset.length()
		if dist > OUTER_RADIUS:
			continue
		var hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if hurtbox != null:
			var dealt := damage if dist <= INNER_RADIUS else damage * SPLASH_DAMAGE_MULT
			hurtbox.receive_hit(AttackInfo.new(wielder, dealt))
		if dist > 0.01:
			enemy.apply_shove(offset.normalized() * SHOVE_FORCE)
	BlastVfx.spawn(get_tree().current_scene, point, OUTER_RADIUS, SHOCKWAVE_COLOR, 0.12, 0.3)
	var player := wielder as Player
	if player != null:
		player.add_shake(0.5)
