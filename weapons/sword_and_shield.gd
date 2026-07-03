class_name SwordAndShield
extends Weapon
## Starting weapon: melee arc in front of the camera plus a raiseable shield.
## The block *rule* (frontal cone) lives in Player.mitigate_hit; this class
## only owns the swing hitbox and viewmodel motion.

## Held low at the bottom-right, tip angled up-inward — a ready stance
## mirroring the shield's tucked idle rather than floating mid-screen.
const SWORD_REST_POS := Vector3(0.4, -0.28, 0.05)
const SWORD_REST_ROT := Vector3(35.0, 15.0, 10.0)
## Virtual shoulder the sword orbits during a slash. Handle and blade are
## rigidly locked to one arm direction from here, so the tip sweeps
## (ARM_LENGTH + blade) / ARM_LENGTH ≈ 3.5x further than the base.
const SHOULDER := Vector3(0.0, -0.45, -0.05)
const ARM_LENGTH := 0.4
## How far past the arc start the windup pulls back (radians), opposite
## the swing direction.
const WINDUP_ANGLE := 0.55
## Tucked low into the corner so it barely covers the screen when idle.
const SHIELD_REST_POS := Vector3(-0.55, -0.3, 0.1)
const SHIELD_REST_ROT := Vector3(-30.0, 35.0, 10.0)
const SHIELD_BLOCK_POS := Vector3(-0.08, 0.08, -0.12)
const SHIELD_BLOCK_ROT := Vector3.ZERO

@onready var hitbox: HitboxComponent = $Hitbox
@onready var sword_pivot: Node3D = $SwordPivot
@onready var shield_pivot: Node3D = $ShieldPivot
@onready var shield_mesh: MeshInstance3D = $ShieldPivot/ShieldMesh

var _swing_tween: Tween
var _shield_tween: Tween
var _flash_tween: Tween
var _swing_flip := false
var _shield_material: StandardMaterial3D


func _ready() -> void:
	sword_pivot.position = SWORD_REST_POS
	sword_pivot.rotation_degrees = SWORD_REST_ROT
	shield_pivot.position = SHIELD_REST_POS
	shield_pivot.rotation_degrees = SHIELD_REST_ROT
	# Per-instance material so the block flash can animate emission.
	var material := shield_mesh.get_active_material(0)
	if material != null:
		_shield_material = material.duplicate() as StandardMaterial3D
		_shield_material.emission_enabled = true
		_shield_material.emission = Color(1.0, 1.0, 1.0)
		_shield_material.emission_energy_multiplier = 0.0
		shield_mesh.material_override = _shield_material


func _do_attack(duration: float) -> void:
	var damage := weapon_data.damage + stats.get_stat(Stats.DAMAGE)
	var info := AttackInfo.new(wielder, damage)
	_swing_flip = not _swing_flip
	var side := 1.0 if _swing_flip else -1.0
	# Rigid arm-swing: the sword orbits the virtual SHOULDER. `dir` is the
	# arm direction; the handle sits ARM_LENGTH along it and the blade
	# points straight out along the same line, so base and tip share one
	# angular sweep — no independent translation to fight the rotation.
	var dir_start := Vector3(0.55 * side, 0.85, -0.25).normalized()
	var dir_end := Vector3(-0.6 * side, -0.35, -0.55).normalized()
	var axis := dir_start.cross(dir_end).normalized()
	# Windup cocks the arm back past the arc start, opposite the swing;
	# the attack then sweeps from there through to dir_end in one cut.
	var dir_windup := dir_start.rotated(axis, -WINDUP_ANGLE)
	var total_sweep := WINDUP_ANGLE + dir_start.angle_to(dir_end)
	var windup_pos := SHOULDER + dir_windup * ARM_LENGTH
	var windup_quat := Basis.looking_at(dir_windup, axis).get_rotation_quaternion()
	if _swing_tween != null:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_parallel(true)
	# 1) Windup: pull back over the shoulder, away from the swing direction.
	_swing_tween.tween_property(sword_pivot, "position", windup_pos, duration * 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(sword_pivot, "quaternion", windup_quat, duration * 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2) Attack: fast sweep through the whole arc. The damage window opens
	# here so hits land with the visible cut, not the windup.
	_swing_tween.chain().tween_callback(hitbox.activate.bind(info, duration * 0.35))
	_swing_tween.tween_method(
		func(t: float) -> void:
			var dir := dir_windup.rotated(axis, total_sweep * t)
			sword_pivot.position = SHOULDER + dir * ARM_LENGTH
			sword_pivot.basis = Basis.looking_at(dir, axis),
		0.0, 1.0, duration * 0.3
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 3) Backswing: settle back to the ready stance.
	_swing_tween.chain().tween_property(
		sword_pivot, "position", SWORD_REST_POS, duration * 0.45
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(
		sword_pivot, "rotation_degrees", SWORD_REST_ROT, duration * 0.45
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _on_blocking_changed() -> void:
	if _shield_tween != null:
		_shield_tween.kill()
	var target_pos := SHIELD_BLOCK_POS if is_blocking else SHIELD_REST_POS
	var target_rot := SHIELD_BLOCK_ROT if is_blocking else SHIELD_REST_ROT
	_shield_tween = create_tween().set_parallel(true)
	_shield_tween.tween_property(shield_pivot, "position", target_pos, 0.12)
	_shield_tween.tween_property(shield_pivot, "rotation_degrees", target_rot, 0.12)


func notify_block_success(perfect: bool = false) -> void:
	# Emission flash on the shield face: white for a block, brighter gold
	# for a perfect block.
	if _shield_material != null:
		if _flash_tween != null:
			_flash_tween.kill()
		_shield_material.emission = Color(1.0, 0.8, 0.25) if perfect else Color(1.0, 1.0, 1.0)
		_shield_material.emission_energy_multiplier = 5.0 if perfect else 2.5
		_flash_tween = create_tween()
		_flash_tween.tween_property(
			_shield_material, "emission_energy_multiplier", 0.0, 0.4 if perfect else 0.25)
	# Impact kick: shield knocked back toward the camera, then re-settles.
	# A perfect block rebounds outward instead — a confident punch-back.
	if _shield_tween != null:
		_shield_tween.kill()
	var kick := Vector3(0.0, 0.02, -0.15) if perfect else Vector3(0.0, -0.03, 0.12)
	shield_pivot.position = SHIELD_BLOCK_POS + kick
	_shield_tween = create_tween()
	_shield_tween.tween_property(shield_pivot, "position", SHIELD_BLOCK_POS, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
