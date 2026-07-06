class_name GroundTelegraph
extends Node3D
## Display-only ground danger-zone decal: a rim marks the threatened area
## while an inner fill sweeps outward from centre to rim over the windup.
## The attacker owns all timing and damage — this is pure VFX, no collision,
## no callback. Built entirely in code, no scene.
##
## Two shapes share the same rim+fill+flash structure: a filling DISC (radial,
## for area attacks) and a filling LANE (linear, for dashes/boomerangs).

## Windup red for enemy telegraphs — distinct from the player's warm-orange
## hammer shockwave (Color(1.0, 0.75, 0.35, 0.55)) by leaning toward red.
const ENEMY_COLOR := Color(1.0, 0.25, 0.15, 0.5)
const FLASH_TIME := 0.08

enum Mode { DISC, LINE }

var _mode := Mode.DISC
var _radius := 1.0
var _duration := 1.0
var _color := ENEMY_COLOR
var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D

# LINE-only state.
var _lane_width := 1.0
var _lane_length := 1.0
var _fill_pivot: Node3D


static func spawn(parent: Node, position: Vector3, radius: float, duration: float,
		color: Color = ENEMY_COLOR) -> GroundTelegraph:
	if parent == null:
		return null
	var telegraph := GroundTelegraph.new()
	telegraph._mode = Mode.DISC
	telegraph._radius = radius
	telegraph._duration = duration
	telegraph._color = color
	parent.add_child(telegraph)
	telegraph.global_position = position
	return telegraph


## Rectangular danger lane from `from` to `to`, `width` wide. The fill sweeps
## from the `from` end to the `to` end over `duration` — the hit lands when
## the fill reaches the far end. Used by dashing attacks and boomerang paths.
static func spawn_line(parent: Node, from: Vector3, to: Vector3, width: float,
		duration: float, color: Color = ENEMY_COLOR) -> GroundTelegraph:
	if parent == null:
		return null
	var telegraph := GroundTelegraph.new()
	telegraph._mode = Mode.LINE
	telegraph._lane_width = width
	telegraph._lane_length = from.distance_to(to)
	telegraph._duration = duration
	telegraph._color = color
	parent.add_child(telegraph)
	telegraph.global_position = (from + to) * 0.5
	var dir := to - from
	telegraph.rotation.y = atan2(-dir.x, -dir.z)
	return telegraph


func _ready() -> void:
	match _mode:
		Mode.LINE:
			_build_line()
		_:
			_build_disc()


func _build_disc() -> void:
	# Outer ring: marks the full threatened radius for the whole windup.
	var ring := MeshInstance3D.new()
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(_color.r, _color.g, _color.b, _color.a * 0.5)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.emission_enabled = true
	ring_material.emission = Color(_color.r, _color.g, _color.b)
	ring_material.emission_energy_multiplier = 1.5
	ring.mesh = VfxPool.unit_sphere()
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position.y = 0.03
	ring.scale = Vector3(_radius, 0.05, _radius)

	# Inner fill: sweeps from centre to rim over the windup, the hit lands
	# when it reaches the edge.
	_fill = MeshInstance3D.new()
	_fill_material = StandardMaterial3D.new()
	_fill_material.albedo_color = _color
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.emission_enabled = true
	_fill_material.emission = Color(_color.r, _color.g, _color.b)
	_fill_material.emission_energy_multiplier = 2.0
	_fill.mesh = VfxPool.unit_sphere()
	_fill.material_override = _fill_material
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)
	_fill.position.y = 0.05
	_fill.scale = Vector3(0.001, 0.05, 0.001)

	var tween := create_tween()
	tween.tween_property(_fill, "scale", Vector3(_radius, 0.05, _radius), _duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Flash as the fill reaches the rim, then the telegraph has done its job.
	tween.tween_property(_fill_material, "emission_energy_multiplier", 5.0, FLASH_TIME)
	tween.tween_callback(queue_free)


func _build_line() -> void:
	# Outer rim: marks the full lane (from→to) for the whole windup. Built in
	# local space with local +Z pointing from the `from` end to the `to` end
	# (telegraph node itself is already oriented and centred by spawn_line).
	var rim := MeshInstance3D.new()
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(_color.r, _color.g, _color.b, _color.a * 0.5)
	rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_material.emission_enabled = true
	rim_material.emission = Color(_color.r, _color.g, _color.b)
	rim_material.emission_energy_multiplier = 1.5
	rim.mesh = VfxPool.unit_sphere()
	rim.material_override = rim_material
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	rim.position.y = 0.03
	rim.scale = Vector3(_lane_width, 0.05, _lane_length)

	# Inner fill: sweeps from the `from` end to the `to` end over the windup,
	# the hit lands when it reaches the far end. A centred box scales about
	# its centre, so the fill mesh lives under a pivot pinned to the `from`
	# end (local Z = -length / 2); the mesh is offset by half its own length
	# so its near edge stays glued to the pivot as it grows.
	_fill_pivot = Node3D.new()
	add_child(_fill_pivot)
	_fill_pivot.position = Vector3(0.0, 0.0, -_lane_length * 0.5)

	_fill = MeshInstance3D.new()
	_fill_material = StandardMaterial3D.new()
	_fill_material.albedo_color = _color
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.emission_enabled = true
	_fill_material.emission = Color(_color.r, _color.g, _color.b)
	_fill_material.emission_energy_multiplier = 2.0
	_fill.mesh = VfxPool.unit_sphere()
	_fill.material_override = _fill_material
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill_pivot.add_child(_fill)
	_fill.position.y = 0.05
	_fill.scale = Vector3(_lane_width, 0.05, 0.001)
	_update_fill_length(0.001)

	var tween := create_tween()
	tween.tween_method(_update_fill_length, 0.001, _lane_length, _duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Flash as the fill reaches the far end, then the telegraph has done its job.
	tween.tween_property(_fill_material, "emission_energy_multiplier", 5.0, FLASH_TIME)
	tween.tween_callback(queue_free)


## Grows the fill lane's length while keeping its near edge glued to the
## pivot (which sits at the `from` end), since a box scales about its centre.
func _update_fill_length(length: float) -> void:
	_fill.scale.z = length
	_fill.position.z = length * 0.5
