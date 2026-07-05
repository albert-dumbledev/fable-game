class_name BossEnemy
extends BossBase
## Boss: keeps the base melee slam, periodically telegraphs a long charge —
## freezing bright, then rushing the player's position at high speed with its
## hitbox live — and lobs a ranged boulder mortar at a committed landing point
## when the player camps outside slam range. A perfect block still stuns it,
## which cancels the charge or the boulder windup (the parry reward stays the
## answer to everything).

const CHARGE_INTERVAL := 5.5
const CHARGE_WINDUP := 0.7
const CHARGE_TIME := 1.5
const CHARGE_SPEED := 24.0
const CHARGE_DAMAGE_MULT := 1.5
const CHARGE_KNOCKBACK := 18.0
const CHARGE_MIN_RANGE := 4.0
const CHARGE_COLOR := Color(1.0, 0.9, 0.2)
## World only — the rush phases through the player AND minions so nothing
## bodily blocks it; the hitbox handles the player, _shove_minions() the rest.
const CHARGE_COLLISION_MASK := 1
const NORMAL_COLLISION_MASK := 7
const SHOVE_RADIUS := 2.8
const SHOVE_FORCE := 14.0

const SLAM_RANGE := 4.5
## Hammer slam: routes through the base WINDUP->ATTACK->RECOVER path
## (data.windup_time=0.9, recover_time=1.0). Boss-sized mirror of the player's
## warhammer slam, delivered to the player hurtbox so block/parry work.
const SLAM_IMPACT_DISTANCE := 3.2
const SLAM_INNER_RADIUS := 3.0
const SLAM_OUTER_RADIUS := 5.5
const SLAM_INNER_KNOCKBACK := 14.0
const SLAM_SPLASH_MULT := 0.4
## Boss-local hammer poses (FistPivot positions; the scene default is REST).
const BOSS_FIST_REST := Vector3(1.0, 2.5, -0.9)
const BOSS_FIST_SLAM_WINDUP := Vector3(0.6, 4.3, 0.4)
const BOSS_FIST_SLAM_DOWN := Vector3(0.35, 1.2, -2.3)

## Boulder throw — the ranged default when the player is beyond SLAM_RANGE.
## Modelled like the charge: its own phase, own const timings.
const BOULDER_WINDUP := 1.0
const BOULDER_FLIGHT := 0.9
const BOULDER_COOLDOWN := 3.5
const BOULDER_IMPACT_RADIUS := 2.8
const BOULDER_DAMAGE_MULT := 0.75
const BOULDER_KNOCKBACK := 8.0
const BOULDER_LEAD_MAX := 6.0
const BOULDER_ARENA_HALF := 18.5
const BOSS_FIST_THROW_WINDUP := Vector3(1.5, 3.0, 1.4)  # arm cocked back
const BOSS_FIST_THROW := Vector3(0.2, 2.8, -2.2)        # arm snapped forward

enum ChargePhase { NONE, WINDUP, RUSH }
enum BoulderPhase { NONE, WINDUP }

var _charge_phase := ChargePhase.NONE
var _charge_cooldown := CHARGE_INTERVAL
var _charge_time := 0.0
var _charge_dir := Vector3.ZERO
var _slam_locked := false
var _slam_point := Vector3.ZERO
var _boulder_phase := BoulderPhase.NONE
var _boulder_cooldown := BOULDER_COOLDOWN
var _boulder_time := 0.0
var _boulder_landing := Vector3.ZERO


func _chase() -> void:
	var delta := get_physics_process_delta_time()
	match _charge_phase:
		ChargePhase.NONE:
			if _boulder_phase == BoulderPhase.WINDUP:
				_tick_boulder(delta)
				return
			_slam_locked = false  # back to chasing — release the facing lock
			_charge_cooldown -= delta
			_boulder_cooldown -= delta
			var to_target := _target.global_position - global_position
			to_target.y = 0.0
			var dist := to_target.length()
			if _charge_cooldown <= 0.0 and dist >= CHARGE_MIN_RANGE:
				_begin_charge_windup()
				return
			if dist <= SLAM_RANGE:
				_begin_windup()  # base WINDUP path == the slam
				return
			if _boulder_cooldown <= 0.0:
				_begin_boulder_windup()
				return
			# Between throws it keeps advancing — the boulder suppresses camping,
			# the walk keeps the pressure.
			var dir := to_target.normalized()
			velocity.x = dir.x * move_speed()
			velocity.z = dir.z * move_speed()
		ChargePhase.WINDUP:
			_hold_still()
			_charge_time += delta
			if _charge_time >= CHARGE_WINDUP:
				_begin_charge_rush()
		ChargePhase.RUSH:
			_charge_time += delta
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
			_shove_minions()
			if _charge_time >= CHARGE_TIME or is_on_wall():
				_end_charge()


func _face_target() -> void:
	if _slam_locked:
		return
	super()


func _begin_windup() -> void:
	_slam_locked = true
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	_slam_point = global_position + forward * SLAM_IMPACT_DISTANCE
	_slam_point.y = 0.05
	GroundTelegraph.spawn(get_tree().current_scene, _slam_point,
			SLAM_INNER_RADIUS, data.windup_time)
	super()  # colour tween + eye ignite + FIST_WINDUP pose...
	_tween_fist(BOSS_FIST_SLAM_WINDUP, data.windup_time)  # ...overridden to overhead raise


func _begin_attack() -> void:
	_set_state(State.ATTACK)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _resting_color()
	_reset_eyes()
	_tween_fist(BOSS_FIST_SLAM_DOWN, 0.12)
	_slam_impact()


func _begin_recover() -> void:
	_set_state(State.RECOVER)
	_tween_fist(BOSS_FIST_REST, 0.3)


## The slam lands as a ground AoE, not a hitbox — VFX and minion shoves land
## first, the player hit lands last (a perfect block can synchronously stun
## us mid receive_hit(), so hitting the player last means a parry can't skip
## the rest of the feedback).
func _slam_impact() -> void:
	AudioManager.play(&"hammer_slam")  # placeholder cue; a dedicated one lands in the SFX pass
	BlastVfx.spawn(get_tree().current_scene, _slam_point, SLAM_OUTER_RADIUS,
			GroundTelegraph.ENEMY_COLOR, 0.12, 0.3)
	ShardBurst.spawn(get_tree().current_scene, _slam_point + Vector3(0.0, 0.2, 0.0),
			Color(0.4, 0.35, 0.32), 12, 7.0, 0.14)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.add_shake(0.4)
	# Shove minions caught in the inner radius (flavour, no damage).
	for minion: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(minion) or minion == self or not minion.is_inside_tree():
			continue
		var off := minion.global_position - _slam_point
		off.y = 0.0
		if off.length() <= SLAM_INNER_RADIUS and off.length() > 0.01:
			minion.apply_shove(off.normalized() * SLAM_INNER_KNOCKBACK)
	# Player hit last — full damage + knockback inside, splash outside.
	if player != null:
		var pd := player.global_position - _slam_point
		pd.y = 0.0
		var d := pd.length()
		if d <= SLAM_OUTER_RADIUS:
			var full := data.damage * _dmg_mult
			var dmg := full if d <= SLAM_INNER_RADIUS else full * SLAM_SPLASH_MULT
			var kb := SLAM_INNER_KNOCKBACK if d <= SLAM_INNER_RADIUS else 0.0
			var hurtbox := player.get_node_or_null(^"Hurtbox") as HurtboxComponent
			if hurtbox != null:
				hurtbox.receive_hit(AttackInfo.new(self, dmg, kb))


func _begin_charge_windup() -> void:
	_charge_phase = ChargePhase.WINDUP
	_charge_time = 0.0
	_hold_still()
	if _material != null:
		_kill_color_tween()
		_color_tween = create_tween()
		_color_tween.tween_property(_material, "albedo_color", CHARGE_COLOR, CHARGE_WINDUP)
	# Eyes stay lit through the rush — reset in _end_charge.
	_flash_eyes(CHARGE_WINDUP)
	_tween_fist(BOSS_FIST_SLAM_WINDUP, CHARGE_WINDUP)


func _begin_charge_rush() -> void:
	_charge_phase = ChargePhase.RUSH
	_charge_time = 0.0
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _base_color
	_charge_dir = _target.global_position - global_position
	_charge_dir.y = 0.0
	_charge_dir = _charge_dir.normalized()
	_tween_fist(BOSS_FIST_SLAM_DOWN, 0.15)
	collision_mask = CHARGE_COLLISION_MASK
	hitbox.activate(
		AttackInfo.new(self, data.damage * _dmg_mult * CHARGE_DAMAGE_MULT, CHARGE_KNOCKBACK),
		CHARGE_TIME)


func _end_charge() -> void:
	_charge_phase = ChargePhase.NONE
	_charge_cooldown = CHARGE_INTERVAL
	collision_mask = NORMAL_COLLISION_MASK
	_reset_eyes()
	hitbox.deactivate()
	_tween_fist(BOSS_FIST_REST, 0.3)
	velocity.x = 0.0
	velocity.z = 0.0


## Commit the landing point up front: lead the player's horizontal velocity over
## the whole windup+flight, clamped to a lead cap and the arena — an honest "spot
## in front of you". The telegraph then covers the full threat window.
func _begin_boulder_windup() -> void:
	_boulder_phase = BoulderPhase.WINDUP
	_boulder_time = 0.0
	_hold_still()
	var lead_time := BOULDER_WINDUP + BOULDER_FLIGHT
	var target_vel := Vector3.ZERO
	if _target is CharacterBody3D:
		target_vel = (_target as CharacterBody3D).velocity
	var lead := target_vel
	lead.y = 0.0
	lead *= lead_time
	if lead.length() > BOULDER_LEAD_MAX:
		lead = lead.normalized() * BOULDER_LEAD_MAX
	_boulder_landing = _target.global_position + lead
	_boulder_landing.x = clampf(_boulder_landing.x, -BOULDER_ARENA_HALF, BOULDER_ARENA_HALF)
	_boulder_landing.z = clampf(_boulder_landing.z, -BOULDER_ARENA_HALF, BOULDER_ARENA_HALF)
	_boulder_landing.y = 0.05
	GroundTelegraph.spawn(get_tree().current_scene, _boulder_landing,
			BOULDER_IMPACT_RADIUS, lead_time)
	# Standard windup tells + an arm-back throw pose.
	if _material != null:
		_kill_color_tween()
		_color_tween = create_tween()
		_color_tween.tween_property(_material, "albedo_color", WINDUP_COLOR, BOULDER_WINDUP)
	_flash_eyes(BOULDER_WINDUP)
	_tween_fist(BOSS_FIST_THROW_WINDUP, BOULDER_WINDUP)


func _tick_boulder(delta: float) -> void:
	_hold_still()
	_boulder_time += delta
	if _boulder_time >= BOULDER_WINDUP:
		_throw_boulder()


func _throw_boulder() -> void:
	_boulder_phase = BoulderPhase.NONE
	_boulder_cooldown = BOULDER_COOLDOWN
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _resting_color()
	_reset_eyes()
	# Snap the arm forward, then settle back to rest over the next beat.
	if _fist_tween != null:
		_fist_tween.kill()
	_fist_tween = create_tween()
	_fist_tween.tween_property(fist_pivot, "position", BOSS_FIST_THROW, 0.12) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fist_tween.tween_property(fist_pivot, "position", BOSS_FIST_REST, 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var info := AttackInfo.new(self, data.damage * _dmg_mult * BOULDER_DAMAGE_MULT, BOULDER_KNOCKBACK)
	BoulderProjectile.spawn(get_tree().current_scene, fist_pivot.global_position,
			_boulder_landing, BOULDER_FLIGHT, BOULDER_IMPACT_RADIUS, info)


## Fling nearby minions sideways out of the charge path — pure flavor,
## no damage. Side is whichever one they're already leaning toward, with
## a little forward carry so they tumble along the rush.
func _shove_minions() -> void:
	var side := _charge_dir.cross(Vector3.UP)
	for minion: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(minion) or minion == self or not minion.is_inside_tree():
			continue
		var offset := minion.global_position - global_position
		offset.y = 0.0
		if offset.length() > SHOVE_RADIUS:
			continue
		var lateral := side if offset.dot(side) >= 0.0 else -side
		var impulse := (lateral * 0.9 + _charge_dir * 0.35).normalized() * SHOVE_FORCE
		minion.apply_shove(impulse)


## A parry cancels the charge entirely and restarts its cooldown, and
## releases the slam's facing lock so a stunned boss can be walked around.
func stun(duration: float) -> void:
	if _charge_phase != ChargePhase.NONE:
		_end_charge()
	if _boulder_phase != BoulderPhase.NONE:
		_boulder_phase = BoulderPhase.NONE
		_boulder_cooldown = BOULDER_COOLDOWN
	_slam_locked = false
	super(duration)
	_tween_fist(BOSS_FIST_REST, 0.2)


## Cancel an in-progress charge (so its collision mask / live hitbox don't
## linger on the corpse), then hand off to the shared boss death spectacle.
func _on_died() -> void:
	if _charge_phase != ChargePhase.NONE:
		_end_charge()
	super()
