class_name BossEnemy
extends EnemyBase
## Boss: keeps the base melee slam, and periodically telegraphs a long
## charge — freezing bright, then rushing the player's position at high
## speed with its hitbox live. A perfect block still stuns it, which
## cancels the charge (the parry reward stays the answer to everything).

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

## Death spectacle: slow-mo while the boss flashes white-hot and swells,
## then a detonation and three radial waves of loot. All timings are
## real-time seconds (the choreography tween ignores Engine.time_scale,
## otherwise the slow-mo would stretch its own animation).
const DEATH_SLOWMO_SCALE := 0.3
const DEATH_SLOWMO_TIME := 0.55
const DEATH_SWELL := 1.35
const DEATH_SWELL_TIME := 0.45
const DEATH_FLASH_COLOR := Color(1.0, 0.95, 0.8)
const DEATH_BURST_COLOR := Color(1.0, 0.7, 0.25, 0.5)
## Same total reward as before, just split into far more pieces across
## three fountains — spectacle, not inflation.
const LOOT_WAVES := 3
const LOOT_WAVE_INTERVAL := 0.4
const LOOT_GOLD_PIECES := 12
const LOOT_XP_PIECES := 8
const LOOT_BURST_SPEED := 1.6
const LOOT_LIFETIME := 60.0
const LOOT_MAGNET_RADIUS := 6.5
const LOOT_RING_COLOR := Color(1.0, 0.8, 0.3, 0.6)

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
			_shove_minions()
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
	# Eyes stay lit through the rush — reset in _end_charge.
	_flash_eyes(CHARGE_WINDUP)
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
	_tween_fist(FIST_REST, 0.3)
	velocity.x = 0.0
	velocity.z = 0.0


## Fling nearby minions sideways out of the charge path — pure flavor,
## no damage. Side is whichever one they're already leaning toward, with
## a little forward carry so they tumble along the rush.
func _shove_minions() -> void:
	var side := _charge_dir.cross(Vector3.UP)
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var minion := node as EnemyBase
		if minion == null or minion == self or not minion.is_inside_tree():
			continue
		var offset := minion.global_position - global_position
		offset.y = 0.0
		if offset.length() > SHOVE_RADIUS:
			continue
		var lateral := side if offset.dot(side) >= 0.0 else -side
		var impulse := (lateral * 0.9 + _charge_dir * 0.35).normalized() * SHOVE_FORCE
		minion.apply_shove(impulse)


## A parry cancels the charge entirely and restarts its cooldown.
func stun(duration: float) -> void:
	if _charge_phase != ChargePhase.NONE:
		_end_charge()
	super(duration)


## Bosses don't just shrink away — the world slows, the body flashes
## white-hot and swells, then detonates into shards and three fountains
## of loot. Replaces EnemyBase._on_died entirely (same bookkeeping up
## front, different exit).
func _on_died() -> void:
	_set_state(State.DEAD)
	remove_from_group(&"enemies")
	if _charge_phase != ChargePhase.NONE:
		_end_charge()
	collision_layer = 0
	hitbox.deactivate()
	hurtbox.set_deferred(&"monitorable", false)
	EventBus.enemy_killed.emit(data, global_position)
	AudioManager.play(&"boss_death")
	FreezeFrame.slow_motion(DEATH_SLOWMO_SCALE, DEATH_SLOWMO_TIME)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.add_shake(0.8)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = DEATH_FLASH_COLOR
		_material.emission_enabled = true
		_material.emission = Color(1.0, 0.85, 0.5)
		_material.emission_energy_multiplier = 2.0
	var seq := create_tween()
	seq.set_ignore_time_scale(true)
	seq.tween_property(mesh, "scale", Vector3.ONE * DEATH_SWELL, DEATH_SWELL_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	seq.tween_callback(_death_burst)
	for wave: int in LOOT_WAVES:
		seq.tween_callback(_spawn_loot_wave.bind(wave))
		seq.tween_interval(LOOT_WAVE_INTERVAL)
	seq.tween_callback(queue_free)


## The detonation: hide the body, ring the arena, throw color-matched
## shards. The node stays alive (invisible) to anchor the loot waves.
func _death_burst() -> void:
	if not is_inside_tree():
		return
	visible = false
	var scene := get_tree().current_scene
	var center := global_position + Vector3(0.0, 1.2, 0.0)
	BlastVfx.spawn(scene, center, 7.0, LOOT_RING_COLOR, 0.5, 0.45)
	BlastVfx.spawn(scene, global_position + Vector3(0.0, 0.15, 0.0), 9.0,
			DEATH_BURST_COLOR, 0.08, 0.5)
	ShardBurst.spawn(scene, center, _base_color, 36, 12.0, 0.22, 1.0)


func _spawn_loot_wave(wave: int) -> void:
	if not is_inside_tree():
		return
	var gold_total := int(round(data.gold_reward * _reward_mult))
	var xp_total := int(round(data.xp_reward * _reward_mult))
	_spawn_pickup_pieces(&"gold", _wave_share(gold_total, wave), LOOT_GOLD_PIECES,
			LOOT_BURST_SPEED, true, LOOT_LIFETIME, LOOT_MAGNET_RADIUS)
	_spawn_pickup_pieces(&"xp", _wave_share(xp_total, wave), LOOT_XP_PIECES,
			LOOT_BURST_SPEED, true, LOOT_LIFETIME, LOOT_MAGNET_RADIUS)
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.2, 0.0), 3.5, LOOT_RING_COLOR, 0.1, 0.3)


## Even split of the total across the waves, remainder to the early ones.
func _wave_share(total: int, wave: int) -> int:
	@warning_ignore("integer_division")
	var base := total / LOOT_WAVES
	return base + (1 if wave < total % LOOT_WAVES else 0)
