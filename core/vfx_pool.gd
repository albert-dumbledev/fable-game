class_name VfxPool
extends Node
## Recycles the fire-and-forget combat VFX nodes — blast spheres, shard
## bursts, damage numbers — instead of building fresh meshes and materials
## per effect. That allocation churn (10-20 effects/sec in combat) is one of
## the main frame costs on the single-threaded web export.
##
## Registered as the "VfxPoolHost" autoload (the entry can't share the
## class_name); code always goes through VfxPool.instance(). Meshes are
## shared; materials are per pooled node because each effect tweens its own
## color/alpha. All effects respect Settings.vfx_density and
## Settings.damage_numbers.

const MAX_BLASTS := 16
const MAX_SHARD_BURSTS := 16
const MAX_LABELS := 24

static var _instance: VfxPool
static var _unit_sphere: SphereMesh

var _blast_free: Array[MeshInstance3D] = []
var _blast_active: Array[MeshInstance3D] = []
var _shard_free: Array[CPUParticles3D] = []
var _shard_active: Array[CPUParticles3D] = []
var _label_free: Array[Label3D] = []
var _label_active: Array[Label3D] = []
var _tweens: Dictionary[Node, Tween] = {}


static func instance() -> VfxPool:
	return _instance


## Unit sphere (radius 1, so effects size via node scale), shared by every
## blast and also by GroundShockwave/FlamePatch's hand-built meshes.
static func unit_sphere() -> SphereMesh:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 1.0
		_unit_sphere.height = 2.0
	return _unit_sphere


func _enter_tree() -> void:
	_instance = self


func _ready() -> void:
	# Effects are sub-second; anything still alive at a run boundary is
	# stale (the arena is gone), so drop it rather than let it linger.
	EventBus.run_started.connect(_release_all)
	EventBus.run_ended.connect(func(_stats: Dictionary) -> void: _release_all())


## Expanding blast sphere; mirrors the old BlastVfx.spawn behavior exactly.
func blast(position: Vector3, radius: float, color: Color,
		flatten: float, duration: float) -> void:
	var node := _acquire_blast()
	if node == null:
		return
	var material := node.material_override as StandardMaterial3D
	material.albedo_color = color
	material.emission = Color(color.r, color.g, color.b)
	node.global_position = position
	node.scale = Vector3(0.3, 0.3 * flatten, 0.3)
	node.visible = true
	var tween := node.create_tween()
	_tweens[node] = tween
	tween.set_parallel(true)
	tween.tween_property(
		node, "scale", Vector3(radius, radius * flatten, radius), duration * 0.88) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(_release_blast.bind(node))


## One-shot burst of emissive cubes; amount is scaled by vfx_density here so
## every caller benefits.
func shards(position: Vector3, color: Color, amount: int, speed: float,
		size: float, particle_lifetime: float) -> void:
	var node := _acquire_shards()
	if node == null:
		return
	var scaled := maxi(1, roundi(float(amount) * Settings.vfx_density))
	if node.amount != scaled:
		node.amount = scaled
	node.lifetime = particle_lifetime
	node.initial_velocity_min = speed * 0.5
	node.initial_velocity_max = speed
	node.scale_amount_min = size
	node.scale_amount_max = size
	var material := node.mesh.surface_get_material(0) as StandardMaterial3D
	material.albedo_color = color
	material.emission = color
	node.global_position = position
	node.visible = true
	node.restart()


## Floating damage popup; honors the damage-numbers toggle.
func damage_number(position: Vector3, amount: float, kill_blow: bool) -> void:
	if not Settings.damage_numbers:
		return
	var label := _acquire_label()
	if label == null:
		return
	label.text = str(int(round(amount)))
	var font_size := clampi(30 + int(amount * 0.55), 32, 64)
	if kill_blow:
		font_size = mini(font_size + 10, 72)
	label.font_size = font_size
	label.outline_size = int(font_size * 0.24)
	label.modulate = Color(1.0, 0.82, 0.25) if kill_blow else Color(0.98, 0.95, 0.82)
	label.global_position = position
	label.visible = true
	var tween := label.create_tween()
	_tweens[label] = tween
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.2)
	tween.chain().tween_callback(_release_label.bind(label))


func _acquire_blast() -> MeshInstance3D:
	if _blast_free.is_empty():
		if _blast_active.size() >= MAX_BLASTS:
			_release_blast(_blast_active[0])
		else:
			_blast_free.append(_make_blast())
	var node: MeshInstance3D = _blast_free.pop_back()
	_blast_active.append(node)
	return node


func _make_blast() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = unit_sphere()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission_energy_multiplier = 3.0
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	return node


func _release_blast(node: MeshInstance3D) -> void:
	if not _blast_active.has(node):
		return
	_kill_tween(node)
	node.visible = false
	_blast_active.erase(node)
	_blast_free.append(node)


func _acquire_shards() -> CPUParticles3D:
	if _shard_free.is_empty():
		if _shard_active.size() >= MAX_SHARD_BURSTS:
			_release_shards(_shard_active[0])
		else:
			_shard_free.append(_make_shards())
	var node: CPUParticles3D = _shard_free.pop_back()
	_shard_active.append(node)
	return node


func _make_shards() -> CPUParticles3D:
	var node := CPUParticles3D.new()
	node.one_shot = true
	node.explosiveness = 1.0
	node.direction = Vector3.UP
	node.spread = 80.0
	node.gravity = Vector3(0.0, -16.0, 0.0)
	node.angular_velocity_min = -300.0
	node.angular_velocity_max = 300.0
	# Per-node mesh (color changes per burst) but unit-sized: the per-burst
	# cube size rides on scale_amount instead of a mesh rebuild.
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission_energy_multiplier = 1.2
	box.material = material
	node.mesh = box
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.emitting = false
	node.visible = false
	node.finished.connect(_release_shards.bind(node))
	add_child(node)
	return node


func _release_shards(node: CPUParticles3D) -> void:
	if not _shard_active.has(node):
		return
	node.emitting = false
	node.visible = false
	_shard_active.erase(node)
	_shard_free.append(node)


func _acquire_label() -> Label3D:
	if _label_free.is_empty():
		if _label_active.size() >= MAX_LABELS:
			_release_label(_label_active[0])
		else:
			_label_free.append(_make_label())
	var label: Label3D = _label_free.pop_back()
	_label_active.append(label)
	return label


func _make_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.007
	label.visible = false
	add_child(label)
	return label


func _release_label(label: Label3D) -> void:
	if not _label_active.has(label):
		return
	_kill_tween(label)
	label.visible = false
	_label_active.erase(label)
	_label_free.append(label)


func _kill_tween(node: Node) -> void:
	var tween: Tween = _tweens.get(node)
	if tween != null:
		tween.kill()
	_tweens.erase(node)


func _release_all() -> void:
	while not _blast_active.is_empty():
		_release_blast(_blast_active[0])
	while not _shard_active.is_empty():
		_release_shards(_shard_active[0])
	while not _label_active.is_empty():
		_release_label(_label_active[0])
