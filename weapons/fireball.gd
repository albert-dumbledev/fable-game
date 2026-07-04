class_name Fireball
extends Area3D
## Charged player spell: flies straight, then explodes on ANY contact
## (enemy, wall, or end of life), damaging and shoving every enemy in a
## sphere. Damage flows through hurtboxes so numbers/drops work as usual.

const LIFETIME := 4.0
const EXPLOSION_RADIUS := 4.0
const EXPLOSION_SHOVE := 10.0
const BLAST_DURATION := 0.25
## Scorched Earth (unique boon): the blast leaves burning ground behind.
const BURN_DAMAGE_MULT := 0.2
const BURN_RADIUS_MULT := 0.55

@export var speed := 18.0

var _info: AttackInfo
var _dir := Vector3.FORWARD
var _age := 0.0
var _exploded := false
var _radius := EXPLOSION_RADIUS
var _burning_ground := false


func setup(info: AttackInfo, direction: Vector3, radius_mult: float = 1.0,
		burning_ground: bool = false) -> void:
	_info = info
	_dir = direction.normalized()
	_radius = EXPLOSION_RADIUS * radius_mult
	_burning_ground = burning_ground


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	# Ember trail: world-space particles shed behind the flight path.
	var trail := CPUParticles3D.new()
	trail.amount = maxi(1, roundi(26.0 * Settings.vfx_density))
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.gravity = Vector3(0.0, 1.2, 0.0)
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 1.0
	trail.scale_amount_min = 0.5
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.08
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.12)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.1)
	material.emission_energy_multiplier = 2.0
	box.material = material
	trail.mesh = box
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The ball is positioned after add_child; a frame-zero emission would
	# drop a stray ember at the world origin. Defer the start one frame.
	trail.emitting = false
	trail.set_deferred(&"emitting", true)
	add_child(trail)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	if _age >= LIFETIME:
		_explode()
		return
	global_position += _dir * speed * delta


func _on_area_entered(area: Area3D) -> void:
	if area is HurtboxComponent:
		_explode()


func _on_body_entered(_body: Node3D) -> void:
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - global_position
		if offset.length() > _radius:
			continue
		var hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if hurtbox != null:
			hurtbox.receive_hit(AttackInfo.new(_info.source, _info.damage))
		offset.y = 0.0
		if offset.length() > 0.01:
			enemy.apply_shove(offset.normalized() * EXPLOSION_SHOVE)
	if _burning_ground:
		FlamePatch.spawn(get_tree().current_scene,
				Vector3(global_position.x, 0.05, global_position.z),
				AttackInfo.new(_info.source, _info.damage * BURN_DAMAGE_MULT),
				_radius * BURN_RADIUS_MULT)
	AudioManager.play_at(&"explosion", global_position)
	BlastVfx.spawn(get_tree().current_scene, global_position, _radius,
			Color(1.0, 0.5, 0.1, 0.7), 1.0, BLAST_DURATION)
	ShardBurst.spawn(get_tree().current_scene, global_position,
			Color(1.0, 0.55, 0.15), 12, 7.0, 0.1, 0.7)
	# Nearby blasts rattle the camera a little.
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null and player.global_position.distance_to(global_position) < 9.0:
		player.add_shake(0.3)
	queue_free()
