class_name EnemyFireball
extends Area3D
## The Caster's fireball: flies straight (deliberately slow and dodgeable),
## then explodes on player-hurtbox contact / wall / timeout, hitting the player
## through the hurtbox and shoving minions clear. Violet so ownership reads.
## Built in code, no scene.

const LIFETIME := 4.0
const EXPLOSION_RADIUS := 3.0
const MINION_SHOVE := 8.0
const SPEED := 10.0
const ORB_COLOR := Color(0.6, 0.4, 1.0)
const BLAST_COLOR := Color(0.55, 0.35, 1.0, 0.7)

var _info: AttackInfo
var _dir := Vector3.FORWARD
var _age := 0.0
var _exploded := false


static func spawn(parent: Node, position: Vector3, direction: Vector3, info: AttackInfo) -> void:
	if parent == null:
		return
	var fb := EnemyFireball.new()
	fb._info = info
	# Mark the hit as ranged so a perfect block can single it out (Mirror Ward).
	fb._info.projectile = true
	fb._dir = direction.normalized()
	parent.add_child(fb)
	fb.global_position = position


func _ready() -> void:
	collision_layer = 0
	collision_mask = 9  # world (1) + player hurtbox (8)
	monitorable = false
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	col.shape = shape
	add_child(col)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	var material := StandardMaterial3D.new()
	material.albedo_color = ORB_COLOR
	material.emission_enabled = true
	material.emission = Color(0.5, 0.3, 1.0)
	material.emission_energy_multiplier = 2.0
	mesh.mesh = sphere
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	# Violet ember trail (mirror of the player fireball's, recoloured). Deferred
	# emit by one frame so no stray ember spawns at the world origin.
	var trail := CPUParticles3D.new()
	trail.amount = maxi(1, roundi(22.0 * Settings.vfx_density))
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.gravity = Vector3(0.0, 1.0, 0.0)
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 1.0
	trail.scale_amount_min = 0.5
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.08
	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color = ORB_COLOR
	trail_mat.emission_enabled = true
	trail_mat.emission = Color(0.5, 0.3, 1.0)
	trail_mat.emission_energy_multiplier = 2.0
	box.material = trail_mat
	trail.mesh = box
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.emitting = false
	trail.set_deferred(&"emitting", true)
	add_child(trail)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	if _age >= LIFETIME:
		_explode()
		return
	global_position += _dir * SPEED * delta


func _on_area_entered(area: Area3D) -> void:
	if area is HurtboxComponent:
		_explode()


func _on_body_entered(_body: Node3D) -> void:
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player != null:
		var pd := player.global_position - global_position
		pd.y = 0.0
		if pd.length() <= EXPLOSION_RADIUS:
			var hurtbox := player.get_node_or_null(^"Hurtbox") as HurtboxComponent
			if hurtbox != null:
				hurtbox.receive_hit(_info)
	for minion: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(minion) or minion == _info.source or not minion.is_inside_tree():
			continue
		var off := minion.global_position - global_position
		off.y = 0.0
		if off.length() <= EXPLOSION_RADIUS and off.length() > 0.01:
			minion.apply_shove(off.normalized() * MINION_SHOVE)
	AudioManager.play_at(&"explosion", global_position)
	BlastVfx.spawn(get_tree().current_scene, global_position, EXPLOSION_RADIUS, BLAST_COLOR, 1.0, 0.25)
	ShardBurst.spawn(get_tree().current_scene, global_position, ORB_COLOR, 12, 7.0, 0.1, 0.7)
	queue_free()
