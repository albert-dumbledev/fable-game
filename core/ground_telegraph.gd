class_name GroundTelegraph
extends Node3D
## Display-only ground danger-zone decal: a rim marks the threatened area
## while an inner fill sweeps outward from centre to rim over the windup.
## The attacker owns all timing and damage — this is pure VFX, no collision,
## no callback. Built entirely in code, no scene.

## Windup red for enemy telegraphs — distinct from the player's warm-orange
## hammer shockwave (Color(1.0, 0.75, 0.35, 0.55)) by leaning toward red.
const ENEMY_COLOR := Color(1.0, 0.25, 0.15, 0.5)
const FLASH_TIME := 0.08

var _radius := 1.0
var _duration := 1.0
var _color := ENEMY_COLOR
var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D


static func spawn(parent: Node, position: Vector3, radius: float, duration: float,
		color: Color = ENEMY_COLOR) -> GroundTelegraph:
	if parent == null:
		return null
	var telegraph := GroundTelegraph.new()
	telegraph._radius = radius
	telegraph._duration = duration
	telegraph._color = color
	parent.add_child(telegraph)
	telegraph.global_position = position
	return telegraph


func _ready() -> void:
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
