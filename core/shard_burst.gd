class_name ShardBurst
extends RefCounted
## Fire-and-forget one-shot burst of small emissive cubes, built in code —
## kill pops, boss detonations, fireball embers. CPUParticles3D (not GPU)
## for web-export reliability; the node frees itself when the burst ends.


static func spawn(parent: Node, position: Vector3, color: Color,
		amount: int = 10, speed: float = 6.0, size: float = 0.12,
		particle_lifetime: float = 0.55) -> void:
	if parent == null:
		return
	var shards := CPUParticles3D.new()
	shards.one_shot = true
	shards.amount = amount
	shards.lifetime = particle_lifetime
	shards.explosiveness = 1.0
	shards.direction = Vector3.UP
	shards.spread = 80.0
	shards.gravity = Vector3(0.0, -16.0, 0.0)
	shards.initial_velocity_min = speed * 0.5
	shards.initial_velocity_max = speed
	shards.angular_velocity_min = -300.0
	shards.angular_velocity_max = 300.0
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	box.material = material
	shards.mesh = box
	shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# emitting defaults to true, which starts the burst at the origin the
	# moment add_child runs — hold it until the node is actually positioned.
	shards.emitting = false
	parent.add_child(shards)
	shards.global_position = position
	shards.restart()
	shards.finished.connect(shards.queue_free)
