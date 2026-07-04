class_name ShardBurst
extends RefCounted
## Fire-and-forget one-shot burst of small emissive cubes — kill pops, boss
## detonations, fireball embers. CPUParticles3D (not GPU) for web-export
## reliability. Thin front: nodes are recycled through the shared VfxPool,
## and `amount` is scaled by Settings.vfx_density there.


static func spawn(parent: Node, position: Vector3, color: Color,
		amount: int = 10, speed: float = 6.0, size: float = 0.12,
		particle_lifetime: float = 0.55) -> void:
	if parent == null:
		return
	var pool := VfxPool.instance()
	if pool != null:
		pool.shards(position, color, amount, speed, size, particle_lifetime)
