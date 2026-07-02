class_name SwordAndShield
extends Weapon
## Starting weapon: melee arc in front of the camera plus a raiseable shield.
## The block *rule* (frontal cone) lives in Player.mitigate_hit; this class
## only owns the swing hitbox and viewmodel motion.

const SHIELD_REST_POS := Vector3(-0.35, 0.0, 0.0)
const SHIELD_BLOCK_POS := Vector3(-0.08, 0.1, -0.15)

@onready var hitbox: HitboxComponent = $Hitbox
@onready var sword_pivot: Node3D = $SwordPivot
@onready var shield_pivot: Node3D = $ShieldPivot

var _swing_tween: Tween
var _shield_tween: Tween


func _do_attack(duration: float) -> void:
	var damage := weapon_data.damage + stats.get_stat(Stats.DAMAGE)
	hitbox.activate(AttackInfo.new(owner as Node3D, damage), duration * 0.5)
	if _swing_tween != null:
		_swing_tween.kill()
	sword_pivot.rotation_degrees = Vector3.ZERO
	_swing_tween = create_tween()
	_swing_tween.tween_property(
		sword_pivot, "rotation_degrees", Vector3(-70.0, -20.0, 0.0), duration * 0.35
	).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(
		sword_pivot, "rotation_degrees", Vector3.ZERO, duration * 0.55
	).set_ease(Tween.EASE_IN_OUT)


func _on_blocking_changed() -> void:
	if _shield_tween != null:
		_shield_tween.kill()
	var target := SHIELD_BLOCK_POS if is_blocking else SHIELD_REST_POS
	_shield_tween = create_tween()
	_shield_tween.tween_property(shield_pivot, "position", target, 0.12)
