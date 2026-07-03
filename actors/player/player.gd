class_name Player
extends CharacterBody3D
## First-person controller: mouse look, WASD, sprint, attack, block.
## Stats come from base values plus MetaProgression's purchased upgrades.

const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT := deg_to_rad(89.0)
const BLOCK_HALF_ANGLE_DEG := 60.0
const BLOCK_SPEED_MULT := 0.5
const SPRINT_MULT := 1.4
## Raising the block within this window before a hit lands is a perfect
## block: the attack is negated and the attacker is stunned.
const PERFECT_BLOCK_WINDOW := 0.2
const PERFECT_BLOCK_STUN := 1.5
const DASH_SPEED := 18.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 2.0
const THORNS_DAMAGE := 15.0
const VAMPIRE_HEAL := 2.0

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var health: HealthComponent = $Health
@onready var weapon: Weapon = $CameraRig/Camera3D/WeaponMount/SwordAndShield

var stats := StatBlock.new()

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dead := false
var _block_started_ms := -10000
var _shake := 0.0
var _abilities: Dictionary[StringName, bool] = {}
var _dash_time := 0.0
var _dash_cooldown := 0.0
var _dash_dir := Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stats.set_base(Stats.MAX_HEALTH, 100.0)
	stats.set_base(Stats.MOVE_SPEED, 6.0)
	stats.set_base(Stats.DAMAGE, 0.0)
	stats.set_base(Stats.ATTACK_SPEED, 1.0)
	for modifier: StatModifier in MetaProgression.get_stat_modifiers():
		stats.add_modifier(modifier)
	health.set_max_health(stats.get_stat(Stats.MAX_HEALTH), true)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	weapon.setup(stats)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		camera_rig.rotate_x(-motion.relative.y * MOUSE_SENSITIVITY)
		camera_rig.rotation.x = clampf(camera_rig.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var block_held := Input.is_action_pressed("block")
	if block_held and not weapon.is_blocking:
		_block_started_ms = Time.get_ticks_msec()
	weapon.set_blocking(block_held)
	if Input.is_action_pressed("attack"):
		weapon.try_attack()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Dash (unique boon): burst of speed in the move direction, or facing
	# if standing still. Overrides normal movement while active.
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	if has_ability(&"dash") and Input.is_action_just_pressed("dash") \
			and _dash_cooldown <= 0.0:
		_dash_dir = direction
		if _dash_dir == Vector3.ZERO:
			_dash_dir = -global_transform.basis.z
			_dash_dir.y = 0.0
			_dash_dir = _dash_dir.normalized()
		_dash_time = DASH_TIME
		_dash_cooldown = DASH_COOLDOWN
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
		move_and_slide()
		return

	var speed := stats.get_stat(Stats.MOVE_SPEED)
	if weapon.is_blocking:
		speed *= BLOCK_SPEED_MULT
	elif Input.is_action_pressed("sprint"):
		speed *= SPRINT_MULT
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 10.0 * delta)
	move_and_slide()


## Called by HurtboxComponent before damage lands. Returning null blocks fully.
func mitigate_hit(info: AttackInfo) -> AttackInfo:
	if weapon.is_blocking and info.source != null and is_instance_valid(info.source):
		var to_attacker := info.source.global_position - global_position
		to_attacker.y = 0.0
		var forward := -global_transform.basis.z
		forward.y = 0.0
		if to_attacker.length() > 0.01 \
				and rad_to_deg(forward.angle_to(to_attacker)) <= BLOCK_HALF_ANGLE_DEG:
			var since_raise := (Time.get_ticks_msec() - _block_started_ms) / 1000.0
			var perfect := since_raise <= PERFECT_BLOCK_WINDOW
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
			return null
	return info


func _process(delta: float) -> void:
	# Trauma-style camera shake: quadratic falloff, jitter on the camera
	# node so the viewmodel shakes with the view.
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 1.8, 0.0)
		var strength := _shake * _shake * 0.1
		camera.position = Vector3(
			randf_range(-strength, strength), randf_range(-strength, strength), 0.0)
	elif camera.position != Vector3.ZERO:
		camera.position = Vector3.ZERO


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


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
	EventBus.player_damaged.emit(info.damage)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	EventBus.player_died.emit()
