class_name FlamePatch
extends Node3D
## Burning ground left where a Scorched Earth fireball explodes: ticks
## damage to enemies standing in it, then burns out. Built entirely in
## code, no scene.

const RADIUS := 1.3
const TICK_INTERVAL := 0.4
const LIFETIME := 3.0
const FADE_TIME := 0.4

var _info: AttackInfo
var _radius := RADIUS
var _age := 0.0
var _tick := 0.0
var _fading := false


static func spawn(parent: Node, position: Vector3, info: AttackInfo,
		radius: float = RADIUS) -> void:
	if parent == null:
		return
	var patch := FlamePatch.new()
	patch._info = info
	patch._radius = radius
	parent.add_child(patch)
	patch.global_position = position


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.45, 0.1, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.4, 0.05)
	material.emission_energy_multiplier = 2.0
	sphere.material = material
	mesh.mesh = sphere
	add_child(mesh)
	mesh.scale = Vector3(_radius, 0.18, _radius)
	# Flicker sells fire without particles.
	var tween := mesh.create_tween().set_loops()
	tween.tween_property(mesh, "scale:y", 0.26, 0.12)
	tween.tween_property(mesh, "scale:y", 0.18, 0.12)
	# Ember sparks drifting up off the patch rim.
	var embers := CPUParticles3D.new()
	embers.amount = 14
	embers.lifetime = 0.9
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	embers.emission_ring_axis = Vector3.UP
	embers.emission_ring_radius = _radius * 0.8
	embers.emission_ring_inner_radius = 0.1
	embers.emission_ring_height = 0.05
	embers.direction = Vector3.UP
	embers.spread = 12.0
	embers.gravity = Vector3(0.0, 1.6, 0.0)
	embers.initial_velocity_min = 0.4
	embers.initial_velocity_max = 1.1
	var spark := BoxMesh.new()
	spark.size = Vector3.ONE * 0.06
	var spark_material := StandardMaterial3D.new()
	spark_material.albedo_color = Color(1.0, 0.55, 0.12)
	spark_material.emission_enabled = true
	spark_material.emission = Color(1.0, 0.5, 0.1)
	spark_material.emission_energy_multiplier = 2.5
	spark.material = spark_material
	embers.mesh = spark
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The patch is positioned after add_child (spawn()); starting emission
	# now would put frame-zero sparks at the world origin. Defer one frame.
	embers.emitting = false
	embers.set_deferred(&"emitting", true)
	add_child(embers)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		if not _fading:
			_fading = true
			var tween := create_tween()
			tween.tween_property(self, "scale", Vector3.ONE * 0.05, FADE_TIME)
			tween.tween_callback(queue_free)
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_INTERVAL
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as EnemyBase
		if enemy == null or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > _radius:
			continue
		var hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if hurtbox != null:
			hurtbox.receive_hit(AttackInfo.new(_info.source, _info.damage))
