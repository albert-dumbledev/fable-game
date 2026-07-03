class_name BlastVfx
extends RefCounted
## Fire-and-forget expanding blast sphere for AoE effects (fireball
## explosion, hammer shockwave, frost nova), built entirely in code.
## `flatten` squashes the sphere vertically (1.0 = sphere, ~0.15 = ground ring).


static func spawn(parent: Node, position: Vector3, radius: float, color: Color,
		flatten: float = 1.0, duration: float = 0.25) -> void:
	if parent == null:
		return
	var blast := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 3.0
	sphere.material = material
	blast.mesh = sphere
	parent.add_child(blast)
	blast.global_position = position
	blast.scale = Vector3(0.3, 0.3 * flatten, 0.3)
	var tween := blast.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		blast, "scale", Vector3(radius, radius * flatten, radius), duration * 0.88) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(blast.queue_free)
