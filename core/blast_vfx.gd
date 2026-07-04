class_name BlastVfx
extends RefCounted
## Fire-and-forget expanding blast sphere for AoE effects (fireball
## explosion, hammer shockwave, frost nova).
## `flatten` squashes the sphere vertically (1.0 = sphere, ~0.15 = ground ring).
## Thin front: the node/material come from the shared VfxPool, so heavy
## combat doesn't allocate a mesh + material per blast.


static func spawn(parent: Node, position: Vector3, radius: float, color: Color,
		flatten: float = 1.0, duration: float = 0.25) -> void:
	if parent == null:
		return
	var pool := VfxPool.instance()
	if pool != null:
		pool.blast(position, radius, color, flatten, duration)
