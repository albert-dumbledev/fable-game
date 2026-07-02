class_name EnemyBase
extends CharacterBody3D
## Melee chaser with a Chase -> Windup -> Attack -> Recover state machine.
## Ranged/boss variants override state behavior, not the plumbing.
## All numbers come from an EnemyData resource, scaled by the spawner.

enum State { CHASE, WINDUP, ATTACK, RECOVER, DEAD }

const ATTACK_ACTIVE_TIME := 0.25
const WINDUP_COLOR := Color(1.0, 0.55, 0.35)

@onready var health: HealthComponent = $Health
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var hitbox: HitboxComponent = $AttackHitbox
@onready var mesh: MeshInstance3D = $Mesh

var data: EnemyData
var state: State = State.CHASE

var _state_time := 0.0
var _hp_mult := 1.0
var _dmg_mult := 1.0
var _target: Node3D
var _material: StandardMaterial3D
var _base_color := Color.WHITE
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


## Must be called before adding to the tree.
func setup(enemy_data: EnemyData, hp_mult: float, dmg_mult: float) -> void:
	data = enemy_data
	_hp_mult = hp_mult
	_dmg_mult = dmg_mult


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
	_face_target()
	match state:
		State.CHASE:
			_chase()
		State.WINDUP:
			_hold_still()
			if _state_time >= data.windup_time:
				_begin_attack()
		State.ATTACK:
			_hold_still()
			if _state_time >= ATTACK_ACTIVE_TIME:
				_set_state(State.RECOVER)
		State.RECOVER:
			_hold_still()
			if _state_time >= data.recover_time:
				_set_state(State.CHASE)
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
		var tween := create_tween()
		tween.tween_property(_material, "albedo_color", WINDUP_COLOR, data.windup_time)


func _begin_attack() -> void:
	_set_state(State.ATTACK)
	if _material != null:
		_material.albedo_color = _base_color
	hitbox.activate(AttackInfo.new(self, data.damage * _dmg_mult), ATTACK_ACTIVE_TIME)


func _on_damaged(_info: AttackInfo) -> void:
	mesh.scale = Vector3.ONE * 1.18
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.12)


func _on_died() -> void:
	_set_state(State.DEAD)
	remove_from_group(&"enemies")
	collision_layer = 0
	hitbox.deactivate()
	hurtbox.set_deferred(&"monitorable", false)
	EventBus.enemy_killed.emit(data, global_position)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.22)
	tween.tween_callback(queue_free)
