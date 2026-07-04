class_name DamageNumber
extends RefCounted
## Floating world-space damage popups. Bigger hits print bigger; kill blows
## go gold and largest of all. Thin front: Label3D nodes are recycled
## through the shared VfxPool (regenerating glyphs is unavoidable, but node
## and material churn isn't), and the popups respect Settings.damage_numbers.


static func spawn(parent: Node, position: Vector3, amount: float,
		kill_blow: bool = false) -> void:
	if parent == null:
		return
	var pool := VfxPool.instance()
	if pool != null:
		pool.damage_number(position, amount, kill_blow)
