class_name BossEnemy
extends EnemyBase
## Boss: keeps the base melee slam, and periodically telegraphs a long
## charge — freezing bright, then rushing the player's position at high
## speed with its hitbox live. A perfect block still stuns it, which
## cancels the charge (the parry reward stays the answer to everything).

const CHARGE_INTERVAL := 9.0
const CHARGE_WINDUP := 0.9
const CHARGE_TIME := 1.1
const CHARGE_SPEED := 14.0
const CHARGE_DAMAGE_MULT := 1.5
const CHARGE_MIN_RANGE := 5.0
const CHARGE_COLOR := Color(1.0, 0.9, 0.2)

enum ChargePhase { NONE, WINDUP, RUSH }

var _charge_phase := ChargePhase.NONE
var _charge_cooldown := CHARGE_INTERVAL
var _charge_time := 0.0
var _charge_dir := Vector3.ZERO


func _chase() -> void:
	var delta := get_physics_process_delta_time()
	match _charge_phase:
		ChargePhase.NONE:
			_charge_cooldown -= delta
			var to_target := _target.global_position - global_position
			to_target.y = 0.0
			if _charge_cooldown <= 0.0 and to_target.length() >= CHARGE_MIN_RANGE:
				_begin_charge_windup()
				return
			super()
		ChargePhase.WINDUP:
			_hold_still()
			_charge_time += delta
			if _charge_time >= CHARGE_WINDUP:
				_begin_charge_rush()
		ChargePhase.RUSH:
			_charge_time += delta
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
			if _charge_time >= CHARGE_TIME or is_on_wall():
				_end_charge()


func _begin_charge_windup() -> void:
	_charge_phase = ChargePhase.WINDUP
	_charge_time = 0.0
	_hold_still()
	if _material != null:
		_kill_color_tween()
		_color_tween = create_tween()
		_color_tween.tween_property(_material, "albedo_color", CHARGE_COLOR, CHARGE_WINDUP)
	_tween_fist(FIST_WINDUP, CHARGE_WINDUP)


func _begin_charge_rush() -> void:
	_charge_phase = ChargePhase.RUSH
	_charge_time = 0.0
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _base_color
	_charge_dir = _target.global_position - global_position
	_charge_dir.y = 0.0
	_charge_dir = _charge_dir.normalized()
	_tween_fist(FIST_PUNCH, 0.15)
	hitbox.activate(AttackInfo.new(self, data.damage * _dmg_mult * CHARGE_DAMAGE_MULT),
			CHARGE_TIME)


func _end_charge() -> void:
	_charge_phase = ChargePhase.NONE
	_charge_cooldown = CHARGE_INTERVAL
	hitbox.deactivate()
	_tween_fist(FIST_REST, 0.3)
	velocity.x = 0.0
	velocity.z = 0.0


## A parry cancels the charge entirely and restarts its cooldown.
func stun(duration: float) -> void:
	if _charge_phase != ChargePhase.NONE:
		_end_charge()
	super(duration)
