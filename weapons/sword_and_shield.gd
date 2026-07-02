class_name SwordAndShield
extends Weapon
## Starting weapon: melee arc in front of the camera plus a raiseable shield.
## The block *rule* (frontal cone) lives in Player.mitigate_hit; this class
## only owns the swing hitbox and viewmodel motion.

const SWORD_REST_POS := Vector3(0.3, 0.0, 0.0)
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
	hitbox.activate(AttackInfo.new(owner as Node3D, damage), duration * 0.5)
	# Alternate diagonal slashes: snap to a raised side pose, sweep across
	# the screen to the opposite side, then settle back to rest.
	_swing_flip = not _swing_flip
	var side := 1.0 if _swing_flip else -1.0
	if _swing_tween != null:
		_swing_tween.kill()
	sword_pivot.position = SWORD_REST_POS + Vector3(0.12 * side, 0.1, 0.08)
	sword_pivot.rotation_degrees = Vector3(30.0, 45.0 * side, 35.0 * side)
	_swing_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_swing_tween.set_parallel(true)
	_swing_tween.tween_property(
		sword_pivot, "rotation_degrees",
		Vector3(-50.0, -40.0 * side, -30.0 * side), duration * 0.3)
	_swing_tween.tween_property(
		sword_pivot, "position",
		SWORD_REST_POS + Vector3(-0.18 * side, -0.12, -0.3), duration * 0.3)
	_swing_tween.chain().tween_property(
		sword_pivot, "rotation_degrees", Vector3.ZERO, duration * 0.6
	).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.parallel().tween_property(
		sword_pivot, "position", SWORD_REST_POS, duration * 0.6
	).set_ease(Tween.EASE_IN_OUT)


func _on_blocking_changed() -> void:
	if _shield_tween != null:
		_shield_tween.kill()
	var target_pos := SHIELD_BLOCK_POS if is_blocking else SHIELD_REST_POS
	var target_rot := SHIELD_BLOCK_ROT if is_blocking else SHIELD_REST_ROT
	_shield_tween = create_tween().set_parallel(true)
	_shield_tween.tween_property(shield_pivot, "position", target_pos, 0.12)
	_shield_tween.tween_property(shield_pivot, "rotation_degrees", target_rot, 0.12)


func notify_block_success() -> void:
	# White emission flash on the shield face.
	if _shield_material != null:
		if _flash_tween != null:
			_flash_tween.kill()
		_shield_material.emission_energy_multiplier = 2.5
		_flash_tween = create_tween()
		_flash_tween.tween_property(
			_shield_material, "emission_energy_multiplier", 0.0, 0.25)
	# Impact kick: shield knocked back toward the camera, then re-settles.
	if _shield_tween != null:
		_shield_tween.kill()
	shield_pivot.position = SHIELD_BLOCK_POS + Vector3(0.0, -0.03, 0.12)
	_shield_tween = create_tween()
	_shield_tween.tween_property(shield_pivot, "position", SHIELD_BLOCK_POS, 0.15) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
