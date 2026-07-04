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
const SLOW_COLOR := Color(0.55, 0.85, 1.0)
const STUN_TILT_DEG := 14.0
const FIST_REST := Vector3(0.35, 1.05, -0.35)
const FIST_WINDUP := FIST_REST + Vector3(0.05, 0.05, 0.35)
const FIST_PUNCH := FIST_REST + Vector3(-0.15, -0.1, -0.95)
const LUNGE_SPEED_MULT := 1.8
const SHOVE_DECAY := 18.0

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
var _eyes: Array[MeshInstance3D] = []
var _eye_material: StandardMaterial3D
var _eye_tween: Tween
var _stun_duration := 0.0
var _shove := Vector3.ZERO
var _slow_mult := 1.0
var _slow_time := 0.0
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
	# Shared per-enemy eye material so windups can ignite the eyes — the
	# tell that reads through a crowd better than body tint alone.
	for path: NodePath in [^"Mesh/EyeL", ^"Mesh/EyeR"]:
		var eye := get_node_or_null(path) as MeshInstance3D
		if eye != null:
			_eyes.append(eye)
	if not _eyes.is_empty():
		_eye_material = StandardMaterial3D.new()
		_eye_material.albedo_color = Color(0.9, 0.9, 0.9)
		_eye_material.emission_enabled = true
		_eye_material.emission = Color(1.0, 0.25, 0.1)
		_eye_material.emission_energy_multiplier = 0.0
		for eye: MeshInstance3D in _eyes:
			eye.material_override = _eye_material


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
	if _slow_time > 0.0:
		_slow_time -= delta
		if _slow_time <= 0.0:
			_slow_mult = 1.0
			_refresh_resting_color()
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
	# External shoves (boss charge plowing) ride on top of state movement.
	if _shove != Vector3.ZERO:
		velocity.x += _shove.x
		velocity.z += _shove.z
		_shove = _shove.move_toward(Vector3.ZERO, SHOVE_DECAY * delta)
	move_and_slide()


## Physically fling this enemy (no damage). Impulse decays over ~a second.
func apply_shove(impulse: Vector3) -> void:
	_shove = impulse


## Chill (frost nova): scales all movement — chasing, kiting, lunges — but
## not attack timings. Reapplying overwrites the previous slow.
func apply_slow(mult: float, duration: float) -> void:
	if state == State.DEAD:
		return
	_slow_mult = mult
	_slow_time = duration
	_refresh_resting_color()


## data.move_speed with the current slow applied. All steering — base and
## variant overrides — must route through this.
func move_speed() -> float:
	return data.move_speed * _slow_mult


func _chase() -> void:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= data.attack_range:
		_begin_windup()
		return
	var direction := to_target.normalized()
	velocity.x = direction.x * move_speed()
	velocity.z = direction.z * move_speed()


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
	_flash_eyes(data.windup_time)
	# Cock the fist back so the incoming punch is readable.
	_tween_fist(FIST_WINDUP, data.windup_time)


func _begin_attack() -> void:
	_set_state(State.ATTACK)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _resting_color()
	_reset_eyes()
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
	velocity.x = dir.x * move_speed() * LUNGE_SPEED_MULT
	velocity.z = dir.z * move_speed() * LUNGE_SPEED_MULT


## Perfect-block reward: freeze in place, visibly dazed, attack cancelled.
## Called dynamically (e.g. from Player.mitigate_hit); bosses can override.
func stun(duration: float) -> void:
	if state == State.DEAD:
		return
	_set_state(State.STUNNED)
	_stun_duration = duration
	velocity.x = 0.0
	velocity.z = 0.0
	_reset_eyes()
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
		_material.albedo_color = _resting_color()
	var tween := create_tween()
	tween.tween_property(mesh, "rotation_degrees:z", 0.0, 0.15)
	_set_state(State.CHASE)


## Albedo for states that don't own the color: base, tinted icy while slowed.
func _resting_color() -> Color:
	return _base_color.lerp(SLOW_COLOR, 0.65) if _slow_time > 0.0 else _base_color


## Retint now — unless windup/stun owns the color; those reset on their own.
func _refresh_resting_color() -> void:
	if _material == null or state == State.WINDUP or state == State.STUNNED:
		return
	_material.albedo_color = _resting_color()


func _kill_color_tween() -> void:
	if _color_tween != null:
		_color_tween.kill()
		_color_tween = null


## Windup tell: the eyes ignite over the windup duration.
func _flash_eyes(duration: float) -> void:
	if _eye_material == null:
		return
	if _eye_tween != null:
		_eye_tween.kill()
	_eye_tween = create_tween()
	_eye_tween.tween_property(_eye_material, "emission_energy_multiplier", 3.5, duration)


func _reset_eyes() -> void:
	if _eye_material == null:
		return
	if _eye_tween != null:
		_eye_tween.kill()
		_eye_tween = null
	_eye_material.emission_energy_multiplier = 0.0


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
	AudioManager.play_at(info.hit_sound, global_position)
	mesh.scale = Vector3.ONE * 1.18
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.12)
	DamageNumber.spawn(
		get_tree().current_scene,
		global_position + Vector3(randf_range(-0.25, 0.25), 2.0, randf_range(-0.25, 0.25)),
		info.damage, health.current <= 0.0)


func _on_died() -> void:
	_set_state(State.DEAD)
	remove_from_group(&"enemies")
	collision_layer = 0
	hitbox.deactivate()
	hurtbox.set_deferred(&"monitorable", false)
	EventBus.enemy_killed.emit(data, global_position)
	_reset_eyes()
	# Kill pop: color-matched shards and a brief ground ring under the
	# shrinking corpse.
	ShardBurst.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.9, 0.0), _base_color, 9, 5.5, 0.12)
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.1, 0.0), 1.1,
			Color(_base_color.r, _base_color.g, _base_color.b, 0.4), 0.1, 0.25)
	_spawn_pickups(&"gold", int(round(data.gold_reward * _reward_mult)))
	_spawn_pickups(&"xp", int(round(data.xp_reward * _reward_mult)))
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.22)
	tween.tween_callback(queue_free)


## Explode the reward outward as collectable pieces.
func _spawn_pickups(kind: StringName, total: int) -> void:
	_spawn_pickup_pieces(kind, total, MAX_PICKUP_PIECES)


## Split `total` reward into up to `pieces_cap` pickups and burst them out.
## `speed_mult` scales the launch (horizontal fully, vertical half-way so
## fountains spread wide without leaving orbit); `ring` spaces the pieces
## evenly around the circle for deliberate boss fountains. `lifetime` and
## `magnet_radius` override the pickup defaults when > 0.
func _spawn_pickup_pieces(kind: StringName, total: int, pieces_cap: int,
		speed_mult: float = 1.0, ring: bool = false,
		lifetime: float = 0.0, magnet_radius: float = 0.0) -> void:
	if total <= 0:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var pieces := clampi(total, 1, pieces_cap)
	var base_value := int(floor(float(total) / float(pieces)))
	var remainder := total - base_value * pieces
	var vertical_mult := (1.0 + speed_mult) * 0.5
	for i: int in pieces:
		var piece_value := base_value + (1 if i < remainder else 0)
		if piece_value <= 0:
			continue
		var pickup := PICKUP_SCENE.instantiate() as Pickup
		var angle := randf() * TAU
		if ring:
			angle = (float(i) + randf_range(-0.3, 0.3)) * TAU / float(pieces)
		var burst := Vector3(
			cos(angle) * randf_range(3.0, 6.5) * speed_mult,
			randf_range(7.0, 11.0) * vertical_mult,
			sin(angle) * randf_range(3.0, 6.5) * speed_mult)
		pickup.setup(kind, piece_value, burst)
		if lifetime > 0.0:
			pickup.lifetime = lifetime
		if magnet_radius > 0.0:
			pickup.magnet_radius = magnet_radius
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(0.0, 1.2, 0.0)
