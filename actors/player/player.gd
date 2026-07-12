class_name Player
extends CharacterBody3D
## First-person controller: mouse look, WASD, jump, attack, block.
## Stats come from base values plus MetaProgression's purchased upgrades.

const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT := deg_to_rad(89.0)
const BLOCK_HALF_ANGLE_DEG := 60.0
const BLOCK_SPEED_MULT := 0.5
## Guard: blocking is a depleting resource, not a wall to hide behind.
## Holding the shield drains it and every blocked hit costs extra
## (perfect blocks are free — the parry stays skill-expressive). Emptying
## it breaks the block: no blocking until it refills completely.
const GUARD_MAX := 3.0
const GUARD_REGEN := 1.0
const GUARD_HIT_COST := 0.5
const JUMP_VELOCITY := 4.8
## Raising the block within this window before a hit lands is a perfect
## block: the attack is negated and the attacker is stunned.
const PERFECT_BLOCK_WINDOW := 0.2
const PERFECT_BLOCK_STUN := 1.5
## Duelist's Focus (sword unique boon) widens the parry window by this much.
const LONG_PARRY_BONUS := 0.15
## Riposte (sword core): a perfect block primes a window; the next sword swing
## deals RIPOSTE_BASE_BONUS more damage to everything it hits, scaled by the
## riposte_damage stat, then the prime is consumed. Priming again only
## refreshes the window — there is never more than one riposte buffered.
const RIPOSTE_BASE_BONUS := 0.75
const RIPOSTE_WINDOW := 2.0
## Crescendo (duelist Aspect, riposte_chain): a riposte swing that kills refreshes
## the prime instead of consuming it, and each successive riposte in the chain
## deals this much more. Stacks reset when the window finally lapses.
const CRESCENDO_STACK_BONUS := 0.25
## Mirror Ward (duelist Aspect): AoE radius of the reflected projectile's blast.
const MIRROR_WARD_RADIUS := 4.0
## THE PATIENT DARK (Depth II forged Aspect, docs/DEPTHS.md Lane 2): this long
## without taking damage primes a full riposte on the next swing (all riposte
## boons apply — Crescendo chains, Twin Court echoes). Reuses the parry-primed
## swing path; the clock resets whenever the player takes damage.
const PATIENT_DARK_PRIME_TIME := 6.0
## Dash: a fixed-distance blink — traveled, not teleported — with full
## intangibility (no enemy collision, no damage, projectiles pass through).
const DASH_DISTANCE := 6.0
const DASH_DURATION := 0.12
const DASH_COOLDOWN := 2.0
const DASH_FOV_PUNCH := 14.0
const DASH_RING_COLOR := Color(0.7, 0.85, 1.0, 0.5)
const DASH_DUST_COLOR := Color(0.65, 0.6, 0.55, 0.4)
## Viewmodel tilt into the dash direction (degrees at full lateral/forward).
const DASH_KICK_ROLL := 6.0
const DASH_KICK_PITCH := 4.0
## Shield Dash (unique boon): blinking through an enemy within this radius of
## the blink line staggers it for SHIELD_DASH_STUN seconds (scaled by
## parry_stun) and primes a riposte.
const SHIELD_DASH_RADIUS := 1.3
const SHIELD_DASH_STUN := 0.8
## Wider radial catch centered on the dash's landing point, so ending a blink
## in a cluster staggers the whole group and primes a riposte even when they
## sit beside the blink line rather than on it.
const SHIELD_DASH_END_RADIUS := 2.0
## Crashing Leap (Earthshaker Shift): a two-phase skyfall — launch straight up
## and hold a locked hover at the apex to aim (slow-mo + ground indicator),
## then crash down in a fixed-time dive that ends in the warhammer's 360°
## slam. Not an escape: the whole trip returns you to ground within ~1.6s.
## The hurtbox stays live for ASCEND/AIM (projectiles can still tag the
## hover, same anti-roof-camp rule as Levitate) — only the dive itself goes
## intangible, mirroring the dash. Cooldown arms on launch, same as before.
const LEAP_ASCEND_HEIGHT := 10.0
const LEAP_ASCEND_TIME := 0.4
const LEAP_ASCEND_SPEED := LEAP_ASCEND_HEIGHT / LEAP_ASCEND_TIME
## Real-time aim window at the apex before the crash auto-fires. Measured via
## Time.get_ticks_msec() (not accumulated delta) since the aim slow-mo scales
## delta and would otherwise make this drag to ~2s of wall-clock time.
const LEAP_AIM_TIME := 1.0
const LEAP_AIM_SLOW_SCALE := 0.5
## Dive is fixed-duration, not fixed-speed: every crash — near or far — lands
## in the same beat, and speed scales with distance instead.
const LEAP_DIVE_TIME := 0.22
## Max targeting range from the takeoff point, on top of the arena clamp.
const LEAP_MAX_RANGE := 14.0
const LEAP_PITCH_BIAS_DEG := 55.0
const LEAP_FOV_WIDEN := 10.0
const LEAP_COOLDOWN := 5.0
## Landing shake stacks on top of leap_slam's own 0.6 (add_shake clamps the
## total), so the impact reads bigger than the old hop's.
const LEAP_LANDING_SHAKE := 0.35
## Indicator ring: dim by default, brighter/pulsing when a living enemy sits
## inside it (the "yes, fire" confirm). Reuses the dash dust/ring color family.
const LEAP_INDICATOR_DIM_ENERGY := 1.4
const LEAP_INDICATOR_CONFIRM_ENERGY := 3.5
const LEAP_INDICATOR_DIM_ALPHA := 0.45
const LEAP_INDICATOR_CONFIRM_ALPHA := 0.75
## THE OPEN GRAVE (Depth III forged Aspect, docs/DEPTHS.md Lane 2): during the
## Crashing Leap crash phase, living enemies within OPEN_GRAVE_RADIUS of the landing
## marker are dragged toward it at OPEN_GRAVE_PULL m/s — the grave opens before you
## land. Reuses EnemyBase.apply_shove as a per-frame pull: the shove is re-set each
## tick (not accumulated), so a steady inward velocity reads as a continuous pull.
const OPEN_GRAVE_RADIUS := 6.0
const OPEN_GRAVE_PULL := 4.0
## Levitate (Arcanist Shift): rise into a timed hover and rain spells. PURE
## timer — no mana cost, no intangibility, so spitter/caster/boss projectiles
## still connect; melee simply can't reach. Short duration + a long cooldown
## that only starts on landing keep it a power moment, not a roof camp.
const LEVITATE_DURATION := 2.5
const LEVITATE_COOLDOWN := 8.0
## Stormcaller (Arcanist Aspect): with the flag owned, Levitate stops being a
## fixed-timer hover and becomes a mana-funded flight stance — it drains this
## much mana per second and drops when the pool empties, so landing bolt hits
## (which refund mana) are what keep the player aloft. Base Levitate is untouched.
const LEVITATE_MANA_DRAIN := 30.0
const LEVITATE_RISE_SPEED := 8.0
const LEVITATE_HOVER_DAMP := 6.0
const LEVITATE_STRAFE_MULT := 0.8
const LEVITATE_FOV_LIFT := 8.0
## Degrees of downward view bias while hovering, so aiming at the ground reads
## as intended.
const LEVITATE_TILT := 8.0
## Real-time freeze frame on a perfect block — the parry should feel like
## the world flinches.
const PARRY_HIT_PAUSE := 0.09
const NORMAL_COLLISION_MASK := 5
const DASH_COLLISION_MASK := 1
const THORNS_DAMAGE := 15.0
const VAMPIRE_HEAL := 2.0
const KNOCKBACK_DECAY := 25.0
const FIREBALL_SCENE := preload("res://weapons/Fireball.tscn")
const FIREBALL_BASE_DAMAGE := 45.0
const FIREBALL_COOLDOWN := 3.0
## Casting locks out the sword and shield while the orb charges.
const FIREBALL_CHARGE_TIME := 0.8
## Frost Nova: instant icy burst around the player — no charge, no stow —
## that chills everything caught to a crawl. The defensive panic button.
const FROST_NOVA_RADIUS := 6.0
const FROST_NOVA_DAMAGE := 8.0
const FROST_NOVA_SLOW_MULT := 0.35
const FROST_NOVA_SLOW_TIME := 3.5
const FROST_NOVA_COOLDOWN := 8.0
const FROST_NOVA_COLOR := Color(0.55, 0.85, 1.0, 0.6)
## Staff mana economy: spells spend mana, Arcane Bolt hits refund it. These
## fields are only meaningful while the staff is mounted (like the frost-nova
## gate). Mana starts full so a fight can open with a banked cast.
const MANA_MAX := 100.0
const MANA_REGEN := 4.0
const BOLT_MANA_RESTORE := 8.0
const FIREBALL_MANA_COST := 40.0
const FROST_NOVA_MANA_COST := 30.0
## Blood Pact (Arcanist Aspect): a spell cast without enough mana pays the
## shortfall in health at this rate (0.5 HP per missing mana). A cast whose HP
## price would drop the player to 0 is refused outright — see _spend_mana.
const BLOOD_PACT_HP_PER_MANA := 0.5
## Echo Nova (unique boon): a second, weaker pulse after the first.
const NOVA_ECHO_DELAY := 1.0
const NOVA_ECHO_DAMAGE_MULT := 0.5
const NOVA_ECHO_SLOW_MULT := 0.6
const NOVA_ECHO_SLOW_TIME := 2.0
## Glacial Wave (unique boon): novas also shove everything caught.
const NOVA_PUSH_FORCE := 12.0
## Retribution (parry_nova): perfect-block pulse.
const PARRY_NOVA_RADIUS := 3.0
const PARRY_NOVA_DAMAGE_MULT := 0.5
const PARRY_NOVA_SHOVE := 8.0
const PARRY_NOVA_COLOR := Color(1.0, 0.85, 0.3, 0.55)
## Second Wind (parry_heal): a perfect block primes lifesteal on the next
## swing instead of healing outright — the sword pays it back on the punish.
const PARRY_GUARD_REFUND := 0.5
## Reflex Guard (omni_block): for a beat after raising the block it guards all
## directions, then goes on cooldown so it can't be spammed by re-tapping block.
const OMNI_BLOCK_WINDOW := 0.15
const OMNI_BLOCK_COOLDOWN := 0.5
## Undying Will (universal Aspect, undying_will): once per run a lethal blow is
## refused — HP is restored to this fraction of max, the parry-nova pulse clears
## the killing crowd, and a brief grace window follows where nothing lands.
const UNDYING_REVIVE_PCT := 0.30
const UNDYING_GRACE := 1.0
## Slipstream (universal Aspect, slipstream): cuts the leap/levitate cooldown to
## this fraction. The blink's benefit is instead a +1 charge (a dash_charges
## modifier the Aspect carries), so DASH_COOLDOWN is deliberately left untouched.
const SLIPSTREAM_COOLDOWN_MULT := 0.8

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var health: HealthComponent = $Health
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var weapon_mount: Node3D = $CameraRig/Camera3D/WeaponMount

## Instanced from the loadout choice (MetaProgression.get_selected_weapon).
var weapon: Weapon

var stats := StatBlock.new()

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw := 0.0
var _pitch := 0.0
var _eye_offset := Vector3.ZERO
var _dead := false
var _block_started_ms := -10000
var _omni_window_end_ms := -10000
var _omni_next_ms := 0
## ticks_msec deadline for the primed riposte; 0.0 = not primed.
var _riposte_until := 0.0
## Crescendo (riposte_chain): consecutive riposte kills escalate the bonus.
## Reset to 0 when the riposte window lapses (checked in consume_riposte).
var _riposte_chain_stacks := 0
## THE PATIENT DARK (patient_dark): seconds elapsed without taking damage, and a
## latch marking that the dark has primed a riposte that persists until a swing
## spends it. Run-scoped (a fresh Player is built each run). Reset by _on_damaged.
var _patient_dark_charge := 0.0
var _patient_dark_primed := false
## Second Wind (parry_heal): a perfect block primes lifesteal on the next swing.
var _lifesteal_pending := false
var _guard := GUARD_MAX
var _guard_broken := false
var _shake := 0.0
var _abilities: Dictionary[StringName, bool] = {}
var _dash_time := 0.0
var _dash_charges := 1
## Crashing Leap state machine: NONE (grounded), ASCEND (launching up), AIM
## (locked hover, targeting), CRASH (diving to the target).
enum LeapPhase { NONE, ASCEND, AIM, CRASH }
var _leap_phase: LeapPhase = LeapPhase.NONE
var _leap_apex_y := 0.0
var _leap_takeoff := Vector3.ZERO
## ticks_msec deadline for the AIM window's auto-fire.
var _leap_aim_deadline_ms := 0
## Ground-plane point the indicator is currently tracking (arena/range clamped).
var _leap_indicator_point := Vector3.ZERO
var _leap_dive_time := 0.0
var _leap_dive_velocity := Vector3.ZERO
## THE OPEN GRAVE: the landing marker the crash dives to, cached so the pull has a
## target while diving (the dive velocity alone doesn't retain the destination).
var _leap_crash_marker := Vector3.ZERO
var _leap_indicator: MeshInstance3D
var _leap_indicator_material: StandardMaterial3D
var _leap_pitch_tween: Tween
var _leap_fov_tween: Tween
var _levitating := false
var _levitate_descending := false
var _levitate_time := 0.0
var _levitate_can_cancel := false
var _view_pitch_bias := 0.0
var _levitate_fov_tween: Tween
var _levitate_tilt_tween: Tween
var _mobility_cooldown := 0.0
var _dash_dir := Vector3.ZERO
var _dash_fov_tween: Tween
var _dash_kick_tween: Tween
var _cast_cooldown := 0.0
var _fireball_charges := 1
var _nova_cooldown := 0.0
var _mana := MANA_MAX
var _charging := false
var _charge_time := 0.0
var _charge_duration := FIREBALL_CHARGE_TIME
var _charge_orb: MeshInstance3D
var _knockback := Vector3.ZERO
## Undying Will: the once-per-run lethal save is spent (resets naturally — a
## fresh Player is built each run) plus the post-save grace deadline (ticks_msec).
var _undying_used := false
var _grace_until := 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = Settings.fov
	# Mouse look can't live on the physics-interpolated body: per-frame
	# rotations would get smoothed and trail the mouse. The rig is detached,
	# rotated instantly each frame, and follows the body's interpolated
	# position; the body itself only syncs its yaw at physics ticks.
	_eye_offset = camera_rig.position
	camera_rig.top_level = true
	camera_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_update_camera_rig()
	Settings.changed.connect(_on_settings_changed)
	# 80: a fresh run should feel 4-5 early hits from death; in-run health
	# boons (Bulwark) are the intended survivability investment.
	stats.set_base(Stats.MAX_HEALTH, 100.0)
	stats.set_base(Stats.MOVE_SPEED, 6.0)
	stats.set_base(Stats.DAMAGE, 0.0)
	stats.set_base(Stats.ATTACK_SPEED, 1.0)
	stats.set_base(Stats.SPELL_COOLDOWN, 1.0)
	stats.set_base(Stats.CAST_TIME, 1.0)
	stats.set_base(Stats.FIREBALL_AOE, 1.0)
	stats.set_base(Stats.FIREBALL_CHARGES, 1.0)
	stats.set_base(Stats.HAMMER_AOE, 1.0)
	stats.set_base(Stats.RIPOSTE_DAMAGE, 1.0)
	stats.set_base(Stats.PARRY_STUN, 1.0)
	stats.set_base(Stats.HAMMER_SHOVE, 1.0)
	stats.set_base(Stats.SPELL_DAMAGE, 1.0)
	stats.set_base(Stats.DASH_CHARGES, 1.0)
	for modifier: StatModifier in MetaProgression.get_stat_modifiers():
		stats.add_modifier(modifier)
	health.set_max_health(stats.get_stat(Stats.MAX_HEALTH), true)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	_mount_weapon(MetaProgression.get_selected_weapon())
	for ability: StringName in MetaProgression.get_granted_abilities():
		grant_ability(ability)


func _mount_weapon(data: WeaponData) -> void:
	if data == null or data.scene_path == "":
		push_error("No usable weapon selected; loadout is broken.")
		return
	var packed := load(data.scene_path) as PackedScene
	if packed == null:
		push_error("Failed to load weapon scene: %s" % data.scene_path)
		return
	weapon = packed.instantiate() as Weapon
	weapon.weapon_data = data
	weapon_mount.add_child(weapon)
	weapon.setup(stats, self)
	for ability: StringName in data.grants_abilities:
		grant_ability(ability)


func _unhandled_input(event: InputEvent) -> void:
	# Esc (pause) belongs to the PauseMenu, not the player.
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENSITIVITY * Settings.mouse_sensitivity
		_yaw -= motion.relative.x * sensitivity
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, -PITCH_LIMIT, PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	# Movement basis and block-facing math read the body's yaw, so keep it
	# in step with the view once per tick.
	rotation.y = _yaw
	if not is_on_floor() and not _levitating and _leap_phase == LeapPhase.NONE:
		velocity.y -= _gravity * delta
	# Crashing Leap owns the whole frame while airborne: movement, attacks,
	# block and casting are all locked out (mouse look still lives in
	# _unhandled_input, untouched here). Mirrors the dash's early-return shape.
	if _leap_phase != LeapPhase.NONE:
		_process_leap(delta)
		return
	_tick_patient_dark(delta)
	# Fireball charges refill one at a time through the cooldown.
	if _fireball_charges < _max_fireball_charges():
		_cast_cooldown = maxf(0.0, _cast_cooldown - delta)
		if _cast_cooldown <= 0.0:
			_fireball_charges += 1
			if _fireball_charges < _max_fireball_charges():
				_cast_cooldown = _spell_cooldown(FIREBALL_COOLDOWN)
	_nova_cooldown = maxf(0.0, _nova_cooldown - delta)
	# Mana only ticks up for the staff loadout; other weapons ignore it.
	if weapon is Staff:
		_mana = minf(MANA_MAX, _mana + MANA_REGEN * delta)
	if weapon != null and weapon.is_blocking:
		_drain_guard(delta)
	else:
		_guard = minf(GUARD_MAX, _guard + GUARD_REGEN * delta)
		if _guard_broken and _guard >= GUARD_MAX:
			_guard_broken = false
	if _charging:
		# Committed cast: sword and shield are locked out while the orb
		# charges, then the fireball releases automatically.
		weapon.set_blocking(false)
		_charge_time += delta
		if _charge_orb != null:
			var t := clampf(_charge_time / _charge_duration, 0.0, 1.0)
			_charge_orb.scale = Vector3.ONE * lerpf(0.4, 1.8, t)
		if _charge_time >= _charge_duration:
			_finish_cast()
	else:
		var block_held := Input.is_action_pressed("block") \
				and not _guard_broken and _guard > 0.0
		if block_held and not weapon.is_blocking:
			_block_started_ms = Time.get_ticks_msec()
			if has_ability(&"omni_block") and Time.get_ticks_msec() >= _omni_next_ms:
				_omni_window_end_ms = Time.get_ticks_msec() + int(OMNI_BLOCK_WINDOW * 1000.0)
				_omni_next_ms = Time.get_ticks_msec() + int(OMNI_BLOCK_COOLDOWN * 1000.0)
		weapon.set_blocking(block_held)
		# On weapons with no shield, RMB is the weapon's secondary ability.
		if not weapon.weapon_data.can_block \
				and Input.is_action_just_pressed("block"):
			weapon.try_secondary()
		if Input.is_action_pressed("attack"):
			weapon.try_attack()
		if weapon is Staff and has_ability(&"frost_nova") \
				and Input.is_action_just_pressed("cast_2") and _nova_cooldown <= 0.0:
			if _spend_mana(FROST_NOVA_MANA_COST):
				_cast_frost_nova()

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Mobility (Phantom Step): the loadout's Shift move. Charges refill one at a
	# time through the cooldown, same pattern as fireball charges — most
	# loadouts have a single charge; the duelist can bank more (dash_charges).
	if _dash_charges < _max_dash_charges() and not _levitating and not _levitate_descending:
		_mobility_cooldown = maxf(0.0, _mobility_cooldown - delta)
		if _mobility_cooldown <= 0.0:
			_dash_charges += 1
			if _dash_charges < _max_dash_charges():
				_mobility_cooldown = DASH_COOLDOWN
	if has_ability(&"dash") and Input.is_action_just_pressed("dash") \
			and _dash_charges > 0 and _dash_time <= 0.0 and _leap_phase == LeapPhase.NONE:
		_begin_mobility(direction)
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_dir * (DASH_DISTANCE / DASH_DURATION)
		velocity.y = 0.0
		move_and_slide()
		if _dash_time <= 0.0:
			_end_dash()
		return

	if _levitating:
		# Require a Shift release before a second press can end flight, so the
		# takeoff press doesn't cancel on the same frame it launched.
		if not Input.is_action_pressed("dash"):
			_levitate_can_cancel = true
		var recast := _levitate_can_cancel and Input.is_action_just_pressed("dash")
		# Stormcaller (Aspect) reroutes flight to the mana pool: drain while aloft
		# and drop when it empties, so bolt hits (which refund mana) sustain the
		# hover. Without the flag, the base LEVITATE_DURATION countdown below runs
		# exactly as before — one decrement per frame, ending at <= 0.
		var flight_over := false
		if has_ability(&"stormcaller"):
			_mana = maxf(0.0, _mana - LEVITATE_MANA_DRAIN * delta)
			flight_over = _mana <= 0.0
		else:
			_levitate_time -= delta
			flight_over = _levitate_time <= 0.0
		if flight_over or recast:
			_end_levitate()
		else:
			# Hover: coast up from the takeoff boost then settle; WASD air-strafe
			# at reduced speed. Casting is handled above, so spells still fire.
			velocity.y = move_toward(velocity.y, 0.0, LEVITATE_HOVER_DAMP * delta)
			var air_speed := stats.get_stat(Stats.MOVE_SPEED) * LEVITATE_STRAFE_MULT
			if direction != Vector3.ZERO:
				velocity.x = direction.x * air_speed
				velocity.z = direction.z * air_speed
			else:
				velocity.x = move_toward(velocity.x, 0.0, air_speed * 10.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, air_speed * 10.0 * delta)
			move_and_slide()
			# The arena walls are only WallN/S/E/W-height (4m) tall and Levitate
			# rises well above that, so move_and_slide no longer collides with
			# anything horizontally. Clamp to the same play-area bound the
			# spawner uses so hovering can't drift outside the arena.
			global_position.x = clampf(global_position.x, -Spawner.ARENA_HALF, Spawner.ARENA_HALF)
			global_position.z = clampf(global_position.z, -Spawner.ARENA_HALF, Spawner.ARENA_HALF)
			return

	var speed := stats.get_stat(Stats.MOVE_SPEED)
	if weapon.is_blocking:
		speed *= BLOCK_SPEED_MULT
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 10.0 * delta)
	# Hit knockback rides on top of normal movement and bleeds off.
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	move_and_slide()
	if _levitate_descending and is_on_floor():
		_land_levitate()


## Called by HurtboxComponent before damage lands. Returning null blocks fully.
func mitigate_hit(info: AttackInfo) -> AttackInfo:
	# Belt-and-braces with the disabled hurtbox: nothing lands mid-dash.
	if _dash_time > 0.0:
		return null
	# Undying Will grace: for a beat after the once-per-run save, nothing lands —
	# so the same swarm that just killed you can't immediately re-kill.
	if Time.get_ticks_msec() < _grace_until:
		return null
	if weapon.is_blocking and info.source != null and is_instance_valid(info.source):
		var to_attacker := info.source.global_position - global_position
		to_attacker.y = 0.0
		var forward := -global_transform.basis.z
		forward.y = 0.0
		var in_cone := rad_to_deg(forward.angle_to(to_attacker)) <= BLOCK_HALF_ANGLE_DEG
		var omni := Time.get_ticks_msec() <= _omni_window_end_ms
		if to_attacker.length() > 0.01 and (in_cone or omni):
			var since_raise := (Time.get_ticks_msec() - _block_started_ms) / 1000.0
			var window := PERFECT_BLOCK_WINDOW \
					+ (LONG_PARRY_BONUS if has_ability(&"long_parry") else 0.0)
			var perfect := since_raise <= window
			weapon.notify_block_success(perfect)
			# Thorns (unique boon): blocked melee hits wound the attacker.
			if has_ability(&"thorns"):
				var attacker_hurtbox := info.source.get_node_or_null(^"Hurtbox") \
						as HurtboxComponent
				if attacker_hurtbox != null:
					attacker_hurtbox.receive_hit(AttackInfo.new(self, THORNS_DAMAGE))
			if perfect:
				EventBus.perfect_block.emit()
				FreezeFrame.hit_pause(PARRY_HIT_PAUSE)
				# A fresh parry after the riposte window lapsed starts a new
				# Crescendo chain; a parry landed mid-window lets the running
				# chain stand (a killing riposte, not a re-parry, sustains it).
				# Without this a stale chain would leak its inflated bonus into
				# the next unrelated parry.
				if _riposte_until <= 0.0 or float(Time.get_ticks_msec()) > _riposte_until:
					_riposte_chain_stacks = 0
				_prime_riposte()
				var stun_dur := PERFECT_BLOCK_STUN * stats.get_stat(Stats.PARRY_STUN)
				if info.source.has_method(&"stun"):
					info.source.call(&"stun", stun_dur)
				if has_ability(&"exposing_parry") and info.source is EnemyBase:
					(info.source as EnemyBase).mark_vulnerable(stun_dur)
				if has_ability(&"parry_nova"):
					_parry_nova()
				# Mirror Ward: a perfect-blocked projectile is hurled back at
				# the shooter to detonate on impact (melee hits are ignored).
				if has_ability(&"mirror_ward") and info.projectile:
					_mirror_ward_return(info.source)
				if has_ability(&"parry_heal"):
					_lifesteal_pending = true
					_guard = minf(GUARD_MAX, _guard + PARRY_GUARD_REFUND)
			else:
				EventBus.attack_blocked.emit()
				_drain_guard(GUARD_HIT_COST)
			return null
	# Undying Will (universal Aspect): a blow that would kill is refused once per
	# run — restore to a sliver, clear the crowd, and open the grace window. This
	# sits on the non-blocked path, right where the hit would otherwise land full.
	if has_ability(&"undying_will") and not _undying_used \
			and info.damage >= health.current:
		_trigger_undying()
		return null
	return info


## Undying Will: the once-per-run lethal save. Restore to a sliver of max HP
## (set_current, since heal() would no-op if is_dead had been set), fire the
## parry-nova pulse as the hard 3m clearing shockwave, and open a grace window.
func _trigger_undying() -> void:
	_undying_used = true
	health.set_current(stats.get_stat(Stats.MAX_HEALTH) * UNDYING_REVIVE_PCT)
	_parry_nova()
	_grace_until = Time.get_ticks_msec() + int(UNDYING_GRACE * 1000.0)
	AudioManager.play(&"unlock_claim")
	add_shake(0.6)


func _process(delta: float) -> void:
	_update_camera_rig()
	# Trauma-style camera shake: quadratic falloff, jitter on the camera
	# node so the viewmodel shakes with the view.
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 1.8, 0.0)
		var strength := _shake * _shake * 0.1 * Settings.screen_shake
		camera.position = Vector3(
			randf_range(-strength, strength), randf_range(-strength, strength), 0.0)
	elif camera.position != Vector3.ZERO:
		camera.position = Vector3.ZERO


## The rig renders at the body's interpolated position (smooth even when
## render and physics rates diverge) with this frame's look angles applied
## raw, so aiming never lags the mouse.
func _update_camera_rig() -> void:
	camera_rig.global_position = get_global_transform_interpolated().origin + _eye_offset
	camera_rig.rotation = Vector3(_pitch + _view_pitch_bias, _yaw, 0.0)


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


## Physically fling the player with no damage — mirror of EnemyBase.apply_shove.
## Used by boss pushes (Caster repulse, eruption rifts). A well-timed dash still
## escapes it (_begin_dash zeroes _knockback).
func apply_shove(impulse: Vector3) -> void:
	_knockback = impulse
	velocity.y += minf(impulse.length() * 0.15, 3.0)


## FOV applies live from the settings panel; skip mid-dash so the punch
## tween finishes on its own values.
func _on_settings_changed() -> void:
	if _dash_time <= 0.0 and not _levitating and _leap_phase == LeapPhase.NONE:
		camera.fov = Settings.fov


## Applies a run-scoped level-up boon, with modifier values scaled by the
## rarity rolled at offer time. Max-health gains also heal the gained
## amount so the boon never feels like an empty bar extension.
func apply_boon(boon: BoonData, value_mult: float = 1.0) -> void:
	var old_max := stats.get_stat(Stats.MAX_HEALTH)
	for modifier: StatModifier in boon.modifiers:
		var scaled := modifier.duplicate() as StatModifier
		scaled.value = modifier.value * value_mult
		stats.add_modifier(scaled)
	if boon.grants_ability != &"":
		grant_ability(boon.grants_ability)
	var new_max := stats.get_stat(Stats.MAX_HEALTH)
	if new_max != old_max:
		health.set_max_health(new_max)
		if new_max > old_max:
			health.heal(new_max - old_max)


## Shift: dispatch to the mounted loadout's movement art. Phantom Step unlocks
## the &"dash" ability flag for all three loadouts; which move it becomes is the
## weapon's mobility_id(). For now only the blink exists; leap and levitate are
## added with their weapons.
func _begin_mobility(direction: Vector3) -> void:
	match weapon.mobility_id() if weapon != null else &"dash":
		&"hammer_leap":
			_begin_leap(direction)
		&"levitate":
			_begin_levitate(direction)
		_:
			_begin_dash(direction)


func _begin_dash(direction: Vector3) -> void:
	_dash_dir = direction
	if _dash_dir == Vector3.ZERO:
		_dash_dir = -global_transform.basis.z
		_dash_dir.y = 0.0
		_dash_dir = _dash_dir.normalized()
	_dash_time = DASH_DURATION
	_dash_charges -= 1
	if _mobility_cooldown <= 0.0:
		_mobility_cooldown = DASH_COOLDOWN
	_knockback = Vector3.ZERO
	AudioManager.play(&"dash")
	EventBus.player_dashed.emit()
	# Departure mark: a ground ring left behind at the launch point.
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.1, 0.0), 1.6, DASH_RING_COLOR, 0.1, 0.3)
	# Intangible: pass through enemies (walls still stop the dash) and
	# turn the hurtbox dark so nothing — melee or projectile — connects.
	collision_mask = DASH_COLLISION_MASK
	hurtbox.set_deferred(&"monitorable", false)
	# FOV punch sells the burst: overshoot fast, settle slow.
	if _dash_fov_tween != null:
		_dash_fov_tween.kill()
	_dash_fov_tween = create_tween()
	_dash_fov_tween.tween_property(
		camera, "fov", Settings.fov + DASH_FOV_PUNCH, DASH_DURATION * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dash_fov_tween.tween_property(camera, "fov", Settings.fov, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Viewmodel kick: tilt the weapon into the dash direction and ease back.
	var local_dir := global_transform.basis.inverse() * _dash_dir
	var kick := Vector3(
		local_dir.z * DASH_KICK_PITCH, 0.0, -local_dir.x * DASH_KICK_ROLL)
	if _dash_kick_tween != null:
		_dash_kick_tween.kill()
	_dash_kick_tween = create_tween()
	_dash_kick_tween.tween_property(
		weapon_mount, "rotation_degrees", kick, DASH_DURATION * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dash_kick_tween.tween_property(weapon_mount, "rotation_degrees", Vector3.ZERO, 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Shield Dash (stun + prime) and Blade Waltz (damage) both ride this sweep;
	# owning either arms it, owning both stacks the dash-weave fantasy.
	if has_ability(&"shield_dash") or has_ability(&"blade_waltz"):
		_shield_dash_sweep()


## Shield Dash: blinking through enemies staggers them and primes a riposte, so
## it composes with the sword's parry line (Ruthless Riposte, Blade Cyclone,
## Second Wind). Sweeps the blink segment against every alive enemy using the
## same flattened closest-point math the seismic wave uses.
func _shield_dash_sweep() -> void:
	var start := global_position
	start.y = 0.0
	var end := start + _dash_dir * DASH_DISTANCE
	var stun := SHIELD_DASH_STUN * stats.get_stat(Stats.PARRY_STUN)
	# Which effects the sweep carries this blink (either flag arms it).
	var stagger := has_ability(&"shield_dash")
	var waltz := has_ability(&"blade_waltz")
	var waltz_damage := _riposte_scaled_damage() if waltz else 0.0
	var caught := false
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var flat := enemy.global_position
		flat.y = 0.0
		var nearest := Geometry3D.get_closest_point_to_segment(flat, start, end)
		# Catch enemies on the blink line as before, or clustered around the
		# landing point even if they sit off to the side of the line.
		var on_path := flat.distance_to(nearest) <= SHIELD_DASH_RADIUS
		var at_end := flat.distance_to(end) <= SHIELD_DASH_END_RADIUS
		if not on_path and not at_end:
			continue
		# Shield Dash staggers; Blade Waltz turns the blink into a slash. Both
		# owned means the enemy is stunned and cut in the same pass.
		if stagger:
			enemy.stun(stun)
		if waltz:
			var enemy_hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
			if enemy_hurtbox != null:
				enemy_hurtbox.receive_hit(AttackInfo.new(self, waltz_damage))
		BlastVfx.spawn(get_tree().current_scene,
				enemy.global_position + Vector3(0.0, 0.1, 0.0), 1.0,
				DASH_RING_COLOR, 0.12, 0.2)
		caught = true
	if caught:
		# Telegraph the landing AoE with a subtle ring on the endpoint itself.
		BlastVfx.spawn(get_tree().current_scene,
				end + Vector3(0.0, 0.1, 0.0), SHIELD_DASH_END_RADIUS,
				DASH_RING_COLOR, 0.1, 0.18)
		# Only Shield Dash primes a riposte — Blade Waltz's blink *is* the strike.
		if stagger:
			_prime_riposte()
		AudioManager.play(&"parry")


func _end_dash() -> void:
	collision_mask = NORMAL_COLLISION_MASK
	hurtbox.set_deferred(&"monitorable", true)
	# Kill most momentum so the blink stops crisply.
	velocity.x *= 0.2
	velocity.z *= 0.2
	# Arrival: dust ring underfoot and a nudge of shake so the stop has weight.
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.1, 0.0), 1.2, DASH_DUST_COLOR, 0.12, 0.25)
	add_shake(0.12)


## Crashing Leap takeoff: launch straight up toward the ASCEND apex. The
## dive target is aimed later at the apex (see _process_leap_aim), so facing
## at launch no longer matters — direction is ignored.
func _begin_leap(_direction: Vector3) -> void:
	_leap_phase = LeapPhase.ASCEND
	_leap_takeoff = global_position
	_leap_apex_y = global_position.y + LEAP_ASCEND_HEIGHT
	_dash_charges -= 1
	if _mobility_cooldown <= 0.0:
		_mobility_cooldown = LEAP_COOLDOWN * _mobility_cooldown_mult()
	_knockback = Vector3.ZERO
	velocity = Vector3.ZERO
	AudioManager.play(&"hammer_leap")
	add_shake(0.15)
	# Takeoff dust ring underfoot.
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.1, 0.0), 1.4, DASH_DUST_COLOR, 0.1, 0.25)
	# Haul the hammer overhead now; it stays cocked through ASCEND + AIM and
	# crashes down on landing. Duration just needs to outlast the raise tween
	# (0.6× of it) — the pose holds until leap_slam() resets it.
	if weapon is Warhammer:
		(weapon as Warhammer).leap_windup(LEAP_ASCEND_TIME + LEAP_AIM_TIME)
	# Auto-pitch the camera down to the arena so the player arrives already
	# looking where they're about to aim; slight FOV widen sells the apex.
	_tween_leap_pitch(deg_to_rad(-LEAP_PITCH_BIAS_DEG), LEAP_ASCEND_TIME)
	_tween_leap_fov(Settings.fov + LEAP_FOV_WIDEN, LEAP_ASCEND_TIME)


## Per-frame dispatch for the three leap phases. Called instead of the normal
## movement/attack/cast handling while airborne (see the early return in
## _physics_process).
func _process_leap(delta: float) -> void:
	match _leap_phase:
		LeapPhase.ASCEND:
			_process_leap_ascend(delta)
		LeapPhase.AIM:
			_process_leap_aim(delta)
		LeapPhase.CRASH:
			_process_leap_crash(delta)


## Straight-up launch: move position toward the apex at a fixed speed (no
## gravity, no air control — punchy, not floaty). Reaching the apex hands
## off to the aim hover.
func _process_leap_ascend(_delta: float) -> void:
	velocity = Vector3.ZERO
	global_position.y = move_toward(global_position.y, _leap_apex_y, LEAP_ASCEND_SPEED * _delta)
	# global_position.y is single-precision (Vector3), _leap_apex_y is a
	# double — move_toward's exact-arrival value truncates on assignment and
	# can land a hair under the target, so a bare >= would never trip. A
	# small tolerance absorbs that without affecting the punchy ascent feel.
	if global_position.y >= _leap_apex_y - 0.01:
		global_position.y = _leap_apex_y
		_enter_leap_aim()


## Apex reached: lock into a hover, start the aim-window slow-mo, and spawn
## the ground-circle indicator. The 1s window is measured in real time via
## ticks_msec (see LEAP_AIM_TIME's doc comment).
func _enter_leap_aim() -> void:
	_leap_phase = LeapPhase.AIM
	_leap_aim_deadline_ms = Time.get_ticks_msec() + int(LEAP_AIM_TIME * 1000.0)
	# Duration is just a safety net — _begin_leap_crash cancels this early the
	# instant the crash triggers, so clicking early snaps back to full speed.
	FreezeFrame.slow_motion(LEAP_AIM_SLOW_SCALE, LEAP_AIM_TIME + 0.5)
	_spawn_leap_indicator()


## Locked hover: hurtbox stays live (no invincibility), knockback is zeroed
## every frame so a stray hit can't shove the hover, and the indicator tracks
## the camera-center ray against the ground. Crashes on click (attack or a
## Shift re-press) or when the real-time aim window elapses.
func _process_leap_aim(_delta: float) -> void:
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_leap_indicator_point = _clamp_leap_target(_leap_ray_ground_point())
	_update_leap_indicator()
	if Input.is_action_just_pressed(&"attack") or Input.is_action_just_pressed(&"dash") \
			or Time.get_ticks_msec() >= _leap_aim_deadline_ms:
		_begin_leap_crash(_leap_indicator_point)


## Camera-center ray intersected with the ground plane (y=0). Guards against
## a near-horizontal or upward-pointing ray by pushing the point far out —
## the arena/range clamp reins it back in immediately after.
func _leap_ray_ground_point() -> Vector3:
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var t := LEAP_MAX_RANGE * 4.0
	if dir.y < -0.05:
		t = maxf(0.0, (0.0 - origin.y) / dir.y)
	var point := origin + dir * t
	point.y = 0.0
	return point


## Arena bounds, then a max radius from the takeoff point — generous range
## without a free full-arena teleport, and never past the walls.
func _clamp_leap_target(point: Vector3) -> Vector3:
	point.x = clampf(point.x, -Spawner.ARENA_HALF, Spawner.ARENA_HALF)
	point.z = clampf(point.z, -Spawner.ARENA_HALF, Spawner.ARENA_HALF)
	var takeoff_flat := _leap_takeoff
	takeoff_flat.y = 0.0
	var offset := point - takeoff_flat
	offset.y = 0.0
	if offset.length() > LEAP_MAX_RANGE:
		point = takeoff_flat + offset.normalized() * LEAP_MAX_RANGE
	point.x = clampf(point.x, -Spawner.ARENA_HALF, Spawner.ARENA_HALF)
	point.z = clampf(point.z, -Spawner.ARENA_HALF, Spawner.ARENA_HALF)
	point.y = 0.0
	return point


## Crash trigger fired (click or timeout): cancel the aim slow-mo immediately,
## commit to a fixed-time dive at the target, and go intangible for the drop
## (mirrors the dash's collision-mask + monitorable trick).
func _begin_leap_crash(target: Vector3) -> void:
	_leap_phase = LeapPhase.CRASH
	_leap_crash_marker = target
	FreezeFrame.clear_slow_motion()
	_hide_leap_indicator()
	_leap_dive_time = LEAP_DIVE_TIME
	_leap_dive_velocity = (target - global_position) / LEAP_DIVE_TIME
	collision_mask = DASH_COLLISION_MASK
	hurtbox.set_deferred(&"monitorable", false)
	AudioManager.play(&"leap_dive")


## Fixed ~0.22s dive regardless of distance — speed scales with distance, so
## every crash hits like a meteor. Ends on the timer or on floor contact.
func _process_leap_crash(delta: float) -> void:
	_leap_dive_time -= delta
	velocity = _leap_dive_velocity
	# THE OPEN GRAVE: drag enemies toward the marker while the crash is in flight.
	if has_ability(&"open_grave"):
		_open_grave_pull()
	move_and_slide()
	if _leap_dive_time <= 0.0 or is_on_floor():
		_land_leap_crash()


## THE OPEN GRAVE: rake every living enemy near the landing marker inward. Iterates
## a snapshot; the per-frame apply_shove is re-set (not accumulated) so it reads as
## a steady pull rather than a compounding fling. Dead enemies are skipped.
func _open_grave_pull() -> void:
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		if enemy.state == EnemyBase.State.DEAD:
			continue
		var to_marker := _leap_crash_marker - enemy.global_position
		to_marker.y = 0.0
		var d := to_marker.length()
		if d > OPEN_GRAVE_RADIUS or d < 0.1:
			continue
		enemy.apply_shove(to_marker / d * OPEN_GRAVE_PULL)


## Touchdown: restore tangibility/camera, let the warhammer crash its 360°
## slam (Epicenter's waves ride along unchanged), and layer the extra landing
## juice on top of what leap_slam already does.
func _land_leap_crash() -> void:
	_leap_phase = LeapPhase.NONE
	collision_mask = NORMAL_COLLISION_MASK
	hurtbox.set_deferred(&"monitorable", true)
	velocity = Vector3.ZERO
	_tween_leap_pitch(0.0, 0.25)
	_tween_leap_fov(Settings.fov, 0.25)
	_hide_leap_indicator()
	if weapon is Warhammer:
		(weapon as Warhammer).leap_slam()
	add_shake(LEAP_LANDING_SHAKE)
	AudioManager.play(&"leap_impact")
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.1, 0.0), 2.2, DASH_DUST_COLOR, 0.1, 0.35)


func _tween_leap_pitch(target: float, duration: float) -> void:
	if _leap_pitch_tween != null:
		_leap_pitch_tween.kill()
	_leap_pitch_tween = create_tween()
	_leap_pitch_tween.tween_property(self, "_view_pitch_bias", target, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _tween_leap_fov(target: float, duration: float) -> void:
	if _leap_fov_tween != null:
		_leap_fov_tween.kill()
	_leap_fov_tween = create_tween()
	_leap_fov_tween.tween_property(camera, "fov", target, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Lazily built unshaded ring mesh — reuses the dash dust/ring color family.
## Created fresh each AIM entry and freed on crash/land (simpler than
## reparenting a cached instance, and avoids the lazy add-to-root gotcha
## since this only ever happens mid-gameplay, never during scene setup).
func _spawn_leap_indicator() -> void:
	_leap_indicator = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 6
	torus.ring_segments = 24
	_leap_indicator_material = StandardMaterial3D.new()
	_leap_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_leap_indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_leap_indicator_material.albedo_color = DASH_RING_COLOR
	_leap_indicator_material.emission_enabled = true
	_leap_indicator_material.emission = Color(DASH_RING_COLOR.r, DASH_RING_COLOR.g, DASH_RING_COLOR.b)
	_leap_indicator_material.emission_energy_multiplier = LEAP_INDICATOR_DIM_ENERGY
	_leap_indicator.mesh = torus
	_leap_indicator.material_override = _leap_indicator_material
	_leap_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(_leap_indicator)
	_leap_indicator.position.y = 0.1


## Radius = the slam's real OUTER_RADIUS × aoe_mult, so what you see is
## exactly what dies. Brightens/pulses when a living enemy sits inside it —
## the "yes, fire" confirm.
func _update_leap_indicator() -> void:
	if _leap_indicator == null:
		return
	var radius := Warhammer.OUTER_RADIUS * stats.get_stat(Stats.HAMMER_AOE)
	_leap_indicator.global_position = _leap_indicator_point + Vector3(0.0, 0.1, 0.0)
	_leap_indicator.scale = Vector3(radius, 1.0, radius)
	var confirm := _leap_target_has_enemy(_leap_indicator_point, radius)
	_leap_indicator_material.emission_energy_multiplier = \
			LEAP_INDICATOR_CONFIRM_ENERGY if confirm else LEAP_INDICATOR_DIM_ENERGY
	_leap_indicator_material.albedo_color.a = \
			LEAP_INDICATOR_CONFIRM_ALPHA if confirm else LEAP_INDICATOR_DIM_ALPHA


func _leap_target_has_enemy(point: Vector3, radius: float) -> bool:
	for enemy: EnemyBase in EnemyBase.alive:
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var flat := enemy.global_position
		flat.y = 0.0
		if flat.distance_to(point) <= radius:
			return true
	return false


func _hide_leap_indicator() -> void:
	if _leap_indicator != null:
		_leap_indicator.queue_free()
		_leap_indicator = null
		_leap_indicator_material = null


## Levitate: rise into a timed hover. Gravity is suspended while _levitating;
## an upward boost lifts ~5m and then settles. Pure timer — cooldown is armed on
## landing, not here.
func _begin_levitate(_direction: Vector3) -> void:
	_levitating = true
	_levitate_descending = false
	_levitate_can_cancel = false
	_levitate_time = LEVITATE_DURATION
	_dash_charges -= 1
	_knockback = Vector3.ZERO
	velocity.y = LEVITATE_RISE_SPEED
	AudioManager.play(&"levitate")
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.1, 0.0), 1.6, DASH_DUST_COLOR, 0.12, 0.3)
	_levitate_view(true)


## Timer up or Shift re-pressed: stop hovering and let gravity take over. The
## body is not returned here, so the descent starts this same frame.
func _end_levitate() -> void:
	_levitating = false
	_levitate_descending = true
	_levitate_view(false)


## Touchdown after a Levitate: arm the cooldown (it starts on landing) and puff
## a landing ring.
func _land_levitate() -> void:
	_levitate_descending = false
	_mobility_cooldown = LEVITATE_COOLDOWN * _mobility_cooldown_mult()
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.1, 0.0), 1.4, DASH_DUST_COLOR, 0.1, 0.25)
	add_shake(0.1)


## FOV lift + a slight downward pitch bias while hovering, eased in on takeoff
## and back out on landing, so aiming at the ground feels intended.
func _levitate_view(rising: bool) -> void:
	if _levitate_fov_tween != null:
		_levitate_fov_tween.kill()
	_levitate_fov_tween = create_tween()
	_levitate_fov_tween.tween_property(camera, "fov",
			Settings.fov + (LEVITATE_FOV_LIFT if rising else 0.0), 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _levitate_tilt_tween != null:
		_levitate_tilt_tween.kill()
	_levitate_tilt_tween = create_tween()
	_levitate_tilt_tween.tween_property(self, "_view_pitch_bias",
			deg_to_rad(-LEVITATE_TILT) if rising else 0.0, 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _begin_cast() -> void:
	_charging = true
	_charge_time = 0.0
	_charge_duration = FIREBALL_CHARGE_TIME * maxf(0.2, stats.get_stat(Stats.CAST_TIME))
	# Growing orb in front of the camera telegraphs the charge.
	_charge_orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.1)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.1)
	material.emission_energy_multiplier = 2.5
	sphere.material = material
	_charge_orb.mesh = sphere
	camera.add_child(_charge_orb)
	_charge_orb.position = Vector3(0.0, -0.18, -0.7)
	_charge_orb.scale = Vector3.ONE * 0.4


func _finish_cast() -> void:
	_charging = false
	if _charge_orb != null:
		_charge_orb.queue_free()
		_charge_orb = null
	_fireball_charges -= 1
	if _cast_cooldown <= 0.0:
		_cast_cooldown = _spell_cooldown(FIREBALL_COOLDOWN)
	AudioManager.play(&"fireball_shoot")
	var ball := FIREBALL_SCENE.instantiate() as Fireball
	var dir := -camera.global_transform.basis.z
	var ball_damage := (FIREBALL_BASE_DAMAGE + stats.get_stat(Stats.DAMAGE) * 1.5) \
			* stats.get_stat(Stats.SPELL_DAMAGE)
	ball.setup(
		AttackInfo.new(self, ball_damage),
		dir, stats.get_stat(Stats.FIREBALL_AOE), has_ability(&"burning_ground"))
	get_tree().current_scene.add_child(ball)
	ball.global_position = camera.global_position + dir * 0.8


func _cast_frost_nova() -> void:
	_nova_cooldown = _spell_cooldown(FROST_NOVA_COOLDOWN)
	_do_nova(1.0, FROST_NOVA_SLOW_MULT, FROST_NOVA_SLOW_TIME)
	if has_ability(&"nova_echo"):
		get_tree().create_timer(NOVA_ECHO_DELAY, false).timeout.connect(_nova_echo)


func _nova_echo() -> void:
	if _dead or not is_inside_tree():
		return
	_do_nova(NOVA_ECHO_DAMAGE_MULT, NOVA_ECHO_SLOW_MULT, NOVA_ECHO_SLOW_TIME)


func _do_nova(damage_mult: float, slow_mult: float, slow_time: float) -> void:
	var damage := (FROST_NOVA_DAMAGE + stats.get_stat(Stats.DAMAGE) * 0.4) * damage_mult \
			* stats.get_stat(Stats.SPELL_DAMAGE)
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > FROST_NOVA_RADIUS:
			continue
		var enemy_hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if enemy_hurtbox != null:
			enemy_hurtbox.receive_hit(AttackInfo.new(self, damage))
		enemy.apply_slow(slow_mult, slow_time)
		if has_ability(&"nova_push") and offset.length() > 0.01:
			enemy.apply_shove(offset.normalized() * NOVA_PUSH_FORCE)
	BlastVfx.spawn(get_tree().current_scene, global_position, FROST_NOVA_RADIUS,
			FROST_NOVA_COLOR, 0.35, 0.4)
	# Lingering frost skim across the ground where the nova passed.
	BlastVfx.spawn(get_tree().current_scene, global_position, FROST_NOVA_RADIUS,
			Color(0.7, 0.9, 1.0, 0.35), 0.04, 1.1)
	AudioManager.play(&"frost_nova")
	add_shake(0.2)


## Retribution: a radial pulse on a perfect block — 50% weapon damage and a
## shove to everything in PARRY_NOVA_RADIUS. Reuses the frost-nova pattern.
func _parry_nova() -> void:
	if weapon == null or weapon.weapon_data == null:
		return
	var damage := (weapon.weapon_data.damage + stats.get_stat(Stats.DAMAGE)) \
			* PARRY_NOVA_DAMAGE_MULT
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > PARRY_NOVA_RADIUS:
			continue
		var enemy_hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if enemy_hurtbox != null:
			enemy_hurtbox.receive_hit(AttackInfo.new(self, damage))
		if offset.length() > 0.01:
			enemy.apply_shove(offset.normalized() * PARRY_NOVA_SHOVE)
	BlastVfx.spawn(get_tree().current_scene, global_position, PARRY_NOVA_RADIUS,
			PARRY_NOVA_COLOR, 0.3, 0.35)
	add_shake(0.15)


## Spell cooldowns scale with the spell_cooldown stat (clamped so stacked
## reduction can never zero a cooldown out).
func _spell_cooldown(base: float) -> float:
	return base * maxf(0.5, stats.get_stat(Stats.SPELL_COOLDOWN))


func _drain_guard(amount: float) -> void:
	_guard = maxf(0.0, _guard - amount)
	if _guard <= 0.0 and not _guard_broken:
		_guard_broken = true
		weapon.set_blocking(false)
		AudioManager.play(&"guard_break")
		add_shake(0.3)


func _max_fireball_charges() -> int:
	return maxi(1, int(round(stats.get_stat(Stats.FIREBALL_CHARGES))))


## Total banked Shift charges, capped at 4 (Phantom Reserves stacks toward it,
## and Slipstream's dash_charges modifier lifts it for the blink).
func _max_dash_charges() -> int:
	return clampi(int(round(stats.get_stat(Stats.DASH_CHARGES))), 1, 4)


## Slipstream (universal Aspect): the leap/levitate cooldown multiplier. The
## blink instead gets +1 charge (via the Aspect's dash_charges modifier), so
## DASH_COOLDOWN is untouched — only the two long-cooldown Shifts read this.
func _mobility_cooldown_mult() -> float:
	return SLIPSTREAM_COOLDOWN_MULT if has_ability(&"slipstream") else 1.0


func get_cooldown_remaining(id: StringName) -> float:
	match id:
		&"dash":
			# A banked charge means dashable now, whatever the refill timer says.
			return 0.0 if _dash_charges > 0 else _mobility_cooldown
		&"hammer_leap":
			return 0.0 if _dash_charges > 0 else _mobility_cooldown
		&"levitate":
			return 0.0 if _dash_charges > 0 else _mobility_cooldown
		&"firebolt":
			# A banked charge means castable now, whatever the refill timer says.
			return 0.0 if _fireball_charges > 0 else _cast_cooldown
		&"frost_nova":
			return _nova_cooldown
		&"block":
			# The slot reads as a recharge bar: full overlay right after a
			# guard break, draining away as the meter refills.
			return (GUARD_MAX - _guard) / GUARD_REGEN
		&"hammer_wave":
			return weapon.get_secondary_cooldown() if weapon != null else 0.0
	return 0.0


func get_cooldown_max(id: StringName) -> float:
	match id:
		&"dash":
			return DASH_COOLDOWN
		&"hammer_leap":
			return LEAP_COOLDOWN * _mobility_cooldown_mult()
		&"levitate":
			return LEVITATE_COOLDOWN * _mobility_cooldown_mult()
		&"firebolt":
			return _spell_cooldown(FIREBALL_COOLDOWN)
		&"frost_nova":
			return _spell_cooldown(FROST_NOVA_COOLDOWN)
		&"block":
			return GUARD_MAX / GUARD_REGEN
		&"hammer_wave":
			return Warhammer.WAVE_COOLDOWN
	return 0.0


## Fired by the staff's RMB (try_secondary). Spells are the staff's alone, so
## the fireball trigger lives here rather than on a global key.
func try_cast_fireball() -> void:
	if _charging or _fireball_charges <= 0:
		return
	if not _spend_mana(FIREBALL_MANA_COST):
		return
	_begin_cast()


## Single gate for every staff spell's mana cost. Normally subtracts `cost` from
## the pool and returns true. With Blood Pact (Aspect), a shortfall is paid in
## health at BLOOD_PACT_HP_PER_MANA per missing mana — but a payment that would
## kill the caster is refused (a lethal cast is never allowed). Returns whether
## the caller may proceed with the cast; a refusal has already thunked via
## _deny_cast, so no cooldown/charge is consumed upstream.
func _spend_mana(cost: float) -> bool:
	if _mana >= cost:
		_mana -= cost
		return true
	if has_ability(&"blood_pact"):
		var deficit := cost - _mana
		var hp_cost := deficit * BLOOD_PACT_HP_PER_MANA
		if hp_cost >= health.current:
			_deny_cast()
			return false
		_mana = 0.0
		# Route the HP price through the health component so the bar, Bulwark
		# scaling, and damage feedback all apply; the guard above keeps it
		# non-lethal. The mana bar flashes red for the burned portion.
		health.take_damage(AttackInfo.new(self, hp_cost))
		EventBus.mana_burned.emit(hp_cost)
		return true
	_deny_cast()
	return false


## A spell was triggered without the mana to pay for it: a dull thunk and a
## mana-bar flash. Crucially no cooldown or charge is consumed — the input is
## simply refused.
func _deny_cast() -> void:
	AudioManager.play(&"mana_empty")
	EventBus.mana_cast_denied.emit()


## Refund mana into the pool. Arcane Bolt enemy hits call this through a
## shared per-volley BoltManaBudget (which enforces the per-trigger cap), so
## scatter + split can't print mana. Only the staff loadout ever calls it.
func restore_mana(amount: float) -> void:
	_mana = minf(MANA_MAX, _mana + amount)


func get_mana() -> float:
	return _mana


func get_mana_max() -> float:
	return MANA_MAX


## Mana cost for a HUD spell-slot id (0 if that skill doesn't cost mana).
func get_mana_cost(id: StringName) -> float:
	match id:
		&"firebolt":
			return FIREBALL_MANA_COST
		&"frost_nova":
			return FROST_NOVA_MANA_COST
	return 0.0


## Aim ray for staff projectiles — the camera's world position and forward.
func aim_origin() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func get_charges(id: StringName) -> int:
	match id:
		&"firebolt":
			return _fireball_charges
		&"dash":
			return _dash_charges
	return -1


func get_max_charges(id: StringName) -> int:
	match id:
		&"firebolt":
			return _max_fireball_charges()
		&"dash":
			return _max_dash_charges()
	return 1


func grant_ability(id: StringName) -> void:
	if _abilities.get(id, false):
		return
	_abilities[id] = true
	if id == &"vampire":
		EventBus.enemy_killed.connect(_on_vampire_kill)


func has_ability(id: StringName) -> bool:
	return _abilities.get(id, false)


## Whether the player is currently in a Levitate hover — read by the staff so
## Stormcaller's bolt fork only fires while aloft.
func is_levitating() -> bool:
	return _levitating


## THE PATIENT DARK: run-scoped patience clock. With the Aspect owned, standing
## PATIENT_DARK_PRIME_TIME seconds without taking damage primes a full riposte by
## driving the SAME parry path (_prime_riposte), so every riposte-keyed effect —
## Crescendo, Twin Court, Vanishing Stair — fires unchanged. The prime must PERSIST
## until a swing spends it (unlike a parry's 2s window), so once primed the riposte
## deadline is silently refreshed each tick (no repeated tell); when consume_riposte
## clears it the dark is spent and the 6s clock restarts. Reset on damage taken.
func _tick_patient_dark(delta: float) -> void:
	if not has_ability(&"patient_dark"):
		return
	if _patient_dark_primed:
		# A swing (consume_riposte) drops the deadline to 0 — that is the spend.
		if _riposte_until <= 0.0 or float(Time.get_ticks_msec()) > _riposte_until:
			_patient_dark_primed = false
			_patient_dark_charge = 0.0
		else:
			_riposte_until = float(Time.get_ticks_msec()) + RIPOSTE_WINDOW * 1000.0
		return
	_patient_dark_charge += delta
	if _patient_dark_charge >= PATIENT_DARK_PRIME_TIME:
		_patient_dark_primed = true
		_prime_riposte()
		# Subtle prime tell: the blade already lit via _prime_riposte's
		# notify_riposte_primed; layer a quiet parry cue so it also reads by ear.
		AudioManager.play(&"parry", -12.0)


## A perfect block primes/refreshes the riposte window and lights the blade.
func _prime_riposte() -> void:
	_riposte_until = float(Time.get_ticks_msec()) + RIPOSTE_WINDOW * 1000.0
	weapon.notify_riposte_primed(RIPOSTE_WINDOW)


## Consumed by the sword at swing start: the riposte damage bonus (0.0 if not
## primed), base +75% scaled by the riposte_damage stat. Clears the prime, so
## exactly one swing is buffed per parry. With Crescendo (riposte_chain) the
## bonus is further scaled by the current chain length; the prime is only
## re-armed (not cleared) by a killing riposte, so the escalation persists.
func consume_riposte() -> float:
	if _riposte_until <= 0.0 or float(Time.get_ticks_msec()) > _riposte_until:
		# Window lapsed: any Crescendo chain ends here.
		_riposte_chain_stacks = 0
		return 0.0
	_riposte_until = 0.0
	var bonus := RIPOSTE_BASE_BONUS * stats.get_stat(Stats.RIPOSTE_DAMAGE)
	if has_ability(&"riposte_chain"):
		bonus *= 1.0 + CRESCENDO_STACK_BONUS * float(_riposte_chain_stacks)
	return bonus


## A riposte swing landed a killing blow. Routes the two duelist kill-Aspects from
## the sword's single detection: Crescendo (riposte_chain) refreshes the prime and
## grows the chain so the next swing hits even harder (re-firing the primed tell);
## THE VANISHING STAIR (vanishing_stair) hands back a blink charge.
func notify_riposte_kill() -> void:
	if has_ability(&"riposte_chain"):
		_riposte_chain_stacks += 1
		_prime_riposte()
	if has_ability(&"vanishing_stair"):
		_refund_dash_charge()


## THE VANISHING STAIR (Depth IV forged Aspect, docs/DEPTHS.md Lane 2): a riposte
## kill instantly refunds one blink charge into the 8C dash pool, capped at the
## loadout max. A quiet reuse of the dash blip marks the refund; no-op at the cap.
func _refund_dash_charge() -> void:
	if _dash_charges >= _max_dash_charges():
		return
	_dash_charges += 1
	AudioManager.play(&"dash", -6.0)


## Weapon base damage scaled by the riposte_damage stat — the shared strike
## figure for the duelist Aspects that deal damage outside the normal swing
## (Mirror Ward's return blast, Blade Waltz's blink slash).
func _riposte_scaled_damage() -> float:
	if weapon == null or weapon.weapon_data == null:
		return 0.0
	return (weapon.weapon_data.damage + stats.get_stat(Stats.DAMAGE)) \
			* stats.get_stat(Stats.RIPOSTE_DAMAGE)


## Mirror Ward: fling a perfect-blocked projectile back at its shooter. The
## return shot homes to `shooter` and detonates in a MIRROR_WARD_RADIUS blast
## for riposte-scaled weapon damage. A dead/gone shooter lets it fly straight
## and detonate at the end of its life.
func _mirror_ward_return(shooter: Node3D) -> void:
	MirrorShot.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 1.0, 0.0), shooter,
			_riposte_scaled_damage(), MIRROR_WARD_RADIUS, self)


## Consumed by the sword at swing start: whether the next swing should steal
## life (primed by a Second Wind perfect block). Clears the prime.
func consume_lifesteal() -> bool:
	if not _lifesteal_pending:
		return false
	_lifesteal_pending = false
	return true


## Heal helper for weapon-driven effects (lifesteal).
func heal(amount: float) -> void:
	health.heal(amount)


## THE REVENANT'S HOUR (universal forged Aspect, docs/DEPTHS.md): a boss horn
## restores the player in full — health, mana, every cooldown, and every charge
## pool. RunDirector calls this on each boss-wave start (finale included) when the
## flag is owned; the ability gate lives at the call site. Idempotent: safe to
## call more than once per wave (a two-Juggernaut wave horns twice). set_current
## (not heal) so a full bar lands even at the ceiling, and the guard/cast/mobility
## timers and both charge pools reset to their maxima so nothing is mid-cooldown.
func full_restore() -> void:
	health.set_current(stats.get_stat(Stats.MAX_HEALTH))
	_mana = MANA_MAX
	_cast_cooldown = 0.0
	_fireball_charges = _max_fireball_charges()
	_nova_cooldown = 0.0
	_mobility_cooldown = 0.0
	_dash_charges = _max_dash_charges()
	_guard = GUARD_MAX
	_guard_broken = false
	AudioManager.play(&"unlock_claim")
	add_shake(0.2)


func _on_vampire_kill(_enemy_data: Resource, _position: Vector3) -> void:
	health.heal(VAMPIRE_HEAL)


func _on_damaged(info: AttackInfo) -> void:
	add_shake(0.4)
	if info.knockback > 0.0 and info.source != null and is_instance_valid(info.source):
		var away := global_position - info.source.global_position
		away.y = 0.0
		if away.length() > 0.01:
			_knockback = away.normalized() * info.knockback
			# Small pop so big hits read as being launched, not slid.
			velocity.y += minf(info.knockback * 0.15, 3.0)
	# THE PATIENT DARK: any blow landed breaks patience — restart the clock and
	# drop the primed latch (a live riposte window is left to lapse on its own so
	# a parry-earned riposte isn't clobbered by an unrelated chip of damage).
	_patient_dark_charge = 0.0
	_patient_dark_primed = false
	EventBus.player_damaged.emit(info.damage)
	EventBus.player_hit.emit(info)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	EventBus.player_died.emit()


## Health pickups heal a percentage of current max health (scales with
## Bulwark/Vitality stacking rather than a flat amount).
func _on_pickup_collected(kind: StringName, value: int) -> void:
	if kind == &"health":
		health.heal(stats.get_stat(Stats.MAX_HEALTH) * float(value) / 100.0)
