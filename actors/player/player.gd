class_name Player
extends CharacterBody3D
## First-person controller: mouse look, WASD, sprint, attack, block.
## Stats come from base values plus MetaProgression's purchased upgrades.

const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT := deg_to_rad(89.0)
const BLOCK_HALF_ANGLE_DEG := 60.0
const BLOCK_SPEED_MULT := 0.5
const SPRINT_MULT := 1.4

@onready var camera_rig: Node3D = $CameraRig
@onready var health: HealthComponent = $Health
@onready var weapon: Weapon = $CameraRig/Camera3D/WeaponMount/SwordAndShield

var stats := StatBlock.new()

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dead := false


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
	weapon.set_blocking(Input.is_action_pressed("block"))
	if Input.is_action_pressed("attack"):
		weapon.try_attack()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
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
			weapon.notify_block_success()
			EventBus.attack_blocked.emit()
			return null
	return info


func _on_damaged(info: AttackInfo) -> void:
	EventBus.player_damaged.emit(info.damage)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	EventBus.player_died.emit()
