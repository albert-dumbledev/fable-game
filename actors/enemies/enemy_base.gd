class_name EnemyBase
extends CharacterBody3D
## Melee chaser with a Chase -> Windup -> Attack -> Recover state machine.
## Ranged/boss variants override state behavior, not the plumbing.
## All numbers come from an EnemyData resource, scaled by the spawner.

enum State { CHASE, WINDUP, ATTACK, RECOVER, STUNNED, DEAD }

const PICKUP_SCENE := preload("res://actors/pickups/Pickup.tscn")
const MAX_PICKUP_PIECES := 8

const ATTACK_ACTIVE_TIME := 0.25
const WINDUP_COLOR := Color(1.0, 0.55, 0.35)
const STUN_COLOR := Color(0.55, 0.7, 1.0)
const STUN_TILT_DEG := 14.0
const FIST_REST := Vector3(0.35, 1.05, -0.35)
const FIST_WINDUP := FIST_REST + Vector3(0.05, 0.05, 0.35)
const FIST_PUNCH := FIST_REST + Vector3(-0.15, -0.1, -0.95)
const LUNGE_SPEED_MULT := 1.8

@onready var health: HealthComponent = $Health
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var hitbox: HitboxComponent = $AttackHitbox
@onready var mesh: MeshInstance3D = $Mesh
@onready var fist_pivot: Node3D = $FistPivot

var data: EnemyData
var state: State = State.CHASE

var _state_time := 0.0
var _hp_mult := 1.0
var _dmg_mult := 1.0
var _reward_mult := 1.0
var _target: Node3D
var _material: StandardMaterial3D
var _base_color := Color.WHITE
var _fist_tween: Tween
var _color_tween: Tween
var _stun_duration := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


## Must be called before adding to the tree.
func setup(enemy_data: EnemyData, hp_mult: float, dmg_mult: float,
		reward_mult: float = 1.0) -> void:
	data = enemy_data
	_hp_mult = hp_mult
	_dmg_mult = dmg_mult
	_reward_mult = reward_mult


func _ready() -> void:
	add_to_group(&"enemies")
	if data == null:
		push_error("EnemyBase spawned without EnemyData; call setup() first.")
		data = EnemyData.new()
	health.set_max_health(data.max_health * _hp_mult, true)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_target = get_tree().get_first_node_in_group(&"player") as Node3D
	var base_material := mesh.get_active_material(0)
	if base_material != null:
		_material = base_material.duplicate() as StandardMaterial3D
		mesh.material_override = _material
		_base_color = _material.albedo_color


func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if state == State.DEAD:
		move_and_slide()
		return
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	_state_time += delta
	if state != State.STUNNED:
		_face_target()
	match state:
		State.CHASE:
			_chase()
		State.WINDUP:
			_hold_still()
			if _state_time >= data.windup_time:
				_begin_attack()
		State.ATTACK:
			# Lunge momentum from _begin_attack, bleeding off quickly.
			velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
			if _state_time >= ATTACK_ACTIVE_TIME:
				_begin_recover()
		State.RECOVER:
			_hold_still()
			if _state_time >= data.recover_time:
				_set_state(State.CHASE)
		State.STUNNED:
			_hold_still()
			if _state_time >= _stun_duration:
				_end_stun()
	move_and_slide()


func _chase() -> void:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= data.attack_range:
		_begin_windup()
		return
	var direction := to_target.normalized()
	velocity.x = direction.x * data.move_speed
	velocity.z = direction.z * data.move_speed


func _hold_still() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face_target() -> void:
	var to_target := _target.global_position - global_position
	rotation.y = atan2(-to_target.x, -to_target.z)


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


func _begin_windup() -> void:
	_set_state(State.WINDUP)
	if _material != null:
		_kill_color_tween()
		_color_tween = create_tween()
		_color_tween.tween_property(_material, "albedo_color", WINDUP_COLOR, data.windup_time)
	# Cock the fist back so the incoming punch is readable.
	_tween_fist(FIST_WINDUP, data.windup_time)


func _begin_attack() -> void:
	_set_state(State.ATTACK)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _base_color
	hitbox.activate(
		AttackInfo.new(self, data.damage * _dmg_mult, data.knockback), ATTACK_ACTIVE_TIME)
	# A perfect block inside activate() can stun us synchronously — if so,
	# skip the punch and lunge.
	if state != State.ATTACK:
		return
	# Punch toward the player with a short lunge for readability.
	_tween_fist(FIST_PUNCH, ATTACK_ACTIVE_TIME * 0.5)
	var dir := _target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * data.move_speed * LUNGE_SPEED_MULT
	velocity.z = dir.z * data.move_speed * LUNGE_SPEED_MULT


## Perfect-block reward: freeze in place, visibly dazed, attack cancelled.
## Called dynamically (e.g. from Player.mitigate_hit); bosses can override.
func stun(duration: float) -> void:
	if state == State.DEAD:
		return
	_set_state(State.STUNNED)
	_stun_duration = duration
	velocity.x = 0.0
	velocity.z = 0.0
	hitbox.deactivate()
	_tween_fist(FIST_REST, 0.2)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = STUN_COLOR
	var tween := create_tween()
	tween.tween_property(mesh, "rotation_degrees:z", STUN_TILT_DEG, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _end_stun() -> void:
	if _material != null:
		_material.albedo_color = _base_color
	var tween := create_tween()
	tween.tween_property(mesh, "rotation_degrees:z", 0.0, 0.15)
	_set_state(State.CHASE)


func _kill_color_tween() -> void:
	if _color_tween != null:
		_color_tween.kill()
		_color_tween = null


func _begin_recover() -> void:
	_set_state(State.RECOVER)
	_tween_fist(FIST_REST, 0.3)


func _tween_fist(target: Vector3, duration: float) -> void:
	if _fist_tween != null:
		_fist_tween.kill()
	_fist_tween = create_tween()
	_fist_tween.tween_property(fist_pivot, "position", target, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_damaged(info: AttackInfo) -> void:
	mesh.scale = Vector3.ONE * 1.18
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.12)
	DamageNumber.spawn(
		get_tree().current_scene,
		global_position + Vector3(randf_range(-0.25, 0.25), 2.0, randf_range(-0.25, 0.25)),
		info.damage)


func _on_died() -> void:
	_set_state(State.DEAD)
	remove_from_group(&"enemies")
	collision_layer = 0
	hitbox.deactivate()
	hurtbox.set_deferred(&"monitorable", false)
	EventBus.enemy_killed.emit(data, global_position)
	_spawn_pickups(&"gold", int(round(data.gold_reward * _reward_mult)))
	_spawn_pickups(&"xp", int(round(data.xp_reward * _reward_mult)))
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.22)
	tween.tween_callback(queue_free)


## Explode the reward outward as collectable pieces.
func _spawn_pickups(kind: StringName, total: int) -> void:
	if total <= 0:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var pieces := clampi(total, 1, MAX_PICKUP_PIECES)
	var base_value := int(floor(float(total) / float(pieces)))
	var remainder := total - base_value * pieces
	for i: int in pieces:
		var piece_value := base_value + (1 if i < remainder else 0)
		if piece_value <= 0:
			continue
		var pickup := PICKUP_SCENE.instantiate() as Pickup
		var angle := randf() * TAU
		var burst := Vector3(
			cos(angle) * randf_range(3.0, 6.5),
			randf_range(7.0, 11.0),
			sin(angle) * randf_range(3.0, 6.5))
		pickup.setup(kind, piece_value, burst)
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(0.0, 1.2, 0.0)
