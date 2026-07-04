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
## Dash: a fixed-distance blink — traveled, not teleported — with full
## intangibility (no enemy collision, no damage, projectiles pass through).
const DASH_DISTANCE := 6.0
const DASH_DURATION := 0.12
const DASH_COOLDOWN := 2.0
const NORMAL_COLLISION_MASK := 5
const DASH_COLLISION_MASK := 1
const THORNS_DAMAGE := 15.0
const VAMPIRE_HEAL := 2.0
const KNOCKBACK_DECAY := 25.0
const FIREBALL_SCENE := preload("res://weapons/Fireball.tscn")
const FIREBALL_BASE_DAMAGE := 30.0
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
## Echo Nova (unique boon): a second, weaker pulse after the first.
const NOVA_ECHO_DELAY := 1.0
const NOVA_ECHO_DAMAGE_MULT := 0.5
const NOVA_ECHO_SLOW_MULT := 0.6
const NOVA_ECHO_SLOW_TIME := 2.0
## Glacial Wave (unique boon): novas also shove everything caught.
const NOVA_PUSH_FORCE := 12.0

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
var _guard := GUARD_MAX
var _guard_broken := false
var _shake := 0.0
var _abilities: Dictionary[StringName, bool] = {}
var _dash_time := 0.0
var _dash_cooldown := 0.0
var _dash_dir := Vector3.ZERO
var _cast_cooldown := 0.0
var _fireball_charges := 1
var _nova_cooldown := 0.0
var _charging := false
var _charge_time := 0.0
var _charge_duration := FIREBALL_CHARGE_TIME
var _charge_orb: MeshInstance3D
var _knockback := Vector3.ZERO


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
	stats.set_base(Stats.MAX_HEALTH, 80.0)
	stats.set_base(Stats.MOVE_SPEED, 6.0)
	stats.set_base(Stats.DAMAGE, 0.0)
	stats.set_base(Stats.ATTACK_SPEED, 1.0)
	stats.set_base(Stats.SPELL_COOLDOWN, 1.0)
	stats.set_base(Stats.CAST_TIME, 1.0)
	stats.set_base(Stats.FIREBALL_AOE, 1.0)
	stats.set_base(Stats.FIREBALL_CHARGES, 1.0)
	stats.set_base(Stats.HAMMER_AOE, 1.0)
	for modifier: StatModifier in MetaProgression.get_stat_modifiers():
		stats.add_modifier(modifier)
	health.set_max_health(stats.get_stat(Stats.MAX_HEALTH), true)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
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
	if not is_on_floor():
		velocity.y -= _gravity * delta
	# Fireball charges refill one at a time through the cooldown.
	if _fireball_charges < _max_fireball_charges():
		_cast_cooldown = maxf(0.0, _cast_cooldown - delta)
		if _cast_cooldown <= 0.0:
			_fireball_charges += 1
			if _fireball_charges < _max_fireball_charges():
				_cast_cooldown = _spell_cooldown(FIREBALL_COOLDOWN)
	_nova_cooldown = maxf(0.0, _nova_cooldown - delta)
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
		weapon.set_blocking(block_held)
		# On weapons with no shield, RMB is the weapon's secondary ability.
		if not weapon.weapon_data.can_block \
				and Input.is_action_just_pressed("block"):
			weapon.try_secondary()
		if Input.is_action_pressed("attack"):
			weapon.try_attack()
		if has_ability(&"firebolt") and Input.is_action_just_pressed("cast") \
				and _fireball_charges > 0:
			_begin_cast()
		if has_ability(&"frost_nova") and Input.is_action_just_pressed("cast_2") \
				and _nova_cooldown <= 0.0:
			_cast_frost_nova()

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Dash (unique boon): blink a fixed distance in the move direction, or
	# facing if standing still. Intangible while dashing.
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	if has_ability(&"dash") and Input.is_action_just_pressed("dash") \
			and _dash_cooldown <= 0.0:
		_begin_dash(direction)
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_dir * (DASH_DISTANCE / DASH_DURATION)
		velocity.y = 0.0
		move_and_slide()
		if _dash_time <= 0.0:
			_end_dash()
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


## Called by HurtboxComponent before damage lands. Returning null blocks fully.
func mitigate_hit(info: AttackInfo) -> AttackInfo:
	# Belt-and-braces with the disabled hurtbox: nothing lands mid-dash.
	if _dash_time > 0.0:
		return null
	if weapon.is_blocking and info.source != null and is_instance_valid(info.source):
		var to_attacker := info.source.global_position - global_position
		to_attacker.y = 0.0
		var forward := -global_transform.basis.z
		forward.y = 0.0
		if to_attacker.length() > 0.01 \
				and rad_to_deg(forward.angle_to(to_attacker)) <= BLOCK_HALF_ANGLE_DEG:
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
				if info.source.has_method(&"stun"):
					info.source.call(&"stun", PERFECT_BLOCK_STUN)
			else:
				EventBus.attack_blocked.emit()
				_drain_guard(GUARD_HIT_COST)
			return null
	return info


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
	camera_rig.rotation = Vector3(_pitch, _yaw, 0.0)


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


## FOV applies live from the settings panel; skip mid-dash so the punch
## tween finishes on its own values.
func _on_settings_changed() -> void:
	if _dash_time <= 0.0:
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


func _begin_dash(direction: Vector3) -> void:
	_dash_dir = direction
	if _dash_dir == Vector3.ZERO:
		_dash_dir = -global_transform.basis.z
		_dash_dir.y = 0.0
		_dash_dir = _dash_dir.normalized()
	_dash_time = DASH_DURATION
	_dash_cooldown = DASH_COOLDOWN
	_knockback = Vector3.ZERO
	AudioManager.play(&"dash")
	# Intangible: pass through enemies (walls still stop the dash) and
	# turn the hurtbox dark so nothing — melee or projectile — connects.
	collision_mask = DASH_COLLISION_MASK
	hurtbox.set_deferred(&"monitorable", false)
	# FOV punch sells the burst.
	var tween := create_tween()
	tween.tween_property(camera, "fov", Settings.fov + 9.0, DASH_DURATION * 0.6)
	tween.tween_property(camera, "fov", Settings.fov, 0.18)


func _end_dash() -> void:
	collision_mask = NORMAL_COLLISION_MASK
	hurtbox.set_deferred(&"monitorable", true)
	# Kill most momentum so the blink stops crisply.
	velocity.x *= 0.2
	velocity.z *= 0.2


func _begin_cast() -> void:
	_charging = true
	_charge_time = 0.0
	_charge_duration = FIREBALL_CHARGE_TIME * maxf(0.2, stats.get_stat(Stats.CAST_TIME))
	weapon.set_stowed(true)
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
	weapon.set_stowed(false)
	if _charge_orb != null:
		_charge_orb.queue_free()
		_charge_orb = null
	_fireball_charges -= 1
	if _cast_cooldown <= 0.0:
		_cast_cooldown = _spell_cooldown(FIREBALL_COOLDOWN)
	AudioManager.play(&"fireball_shoot")
	var ball := FIREBALL_SCENE.instantiate() as Fireball
	var dir := -camera.global_transform.basis.z
	ball.setup(
		AttackInfo.new(self, FIREBALL_BASE_DAMAGE + stats.get_stat(Stats.DAMAGE) * 1.5),
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
	var damage := (FROST_NOVA_DAMAGE + stats.get_stat(Stats.DAMAGE) * 0.4) * damage_mult
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as EnemyBase
		if enemy == null or not enemy.is_inside_tree():
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
	AudioManager.play(&"frost_nova")
	add_shake(0.2)


## Spell cooldowns scale with the spell_cooldown stat (clamped so stacked
## reduction can never zero a cooldown out).
func _spell_cooldown(base: float) -> float:
	return base * maxf(0.25, stats.get_stat(Stats.SPELL_COOLDOWN))


func _drain_guard(amount: float) -> void:
	_guard = maxf(0.0, _guard - amount)
	if _guard <= 0.0 and not _guard_broken:
		_guard_broken = true
		weapon.set_blocking(false)
		AudioManager.play(&"guard_break")
		add_shake(0.3)


func _max_fireball_charges() -> int:
	return maxi(1, int(round(stats.get_stat(Stats.FIREBALL_CHARGES))))


func get_cooldown_remaining(id: StringName) -> float:
	match id:
		&"dash":
			return _dash_cooldown
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
		&"firebolt":
			return _spell_cooldown(FIREBALL_COOLDOWN)
		&"frost_nova":
			return _spell_cooldown(FROST_NOVA_COOLDOWN)
		&"block":
			return GUARD_MAX / GUARD_REGEN
		&"hammer_wave":
			return Warhammer.WAVE_COOLDOWN
	return 0.0


func get_charges(id: StringName) -> int:
	return _fireball_charges if id == &"firebolt" else -1


func get_max_charges(id: StringName) -> int:
	return _max_fireball_charges() if id == &"firebolt" else 1


func grant_ability(id: StringName) -> void:
	if _abilities.get(id, false):
		return
	_abilities[id] = true
	if id == &"vampire":
		EventBus.enemy_killed.connect(_on_vampire_kill)


func has_ability(id: StringName) -> bool:
	return _abilities.get(id, false)


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
	EventBus.player_damaged.emit(info.damage)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	EventBus.player_died.emit()
