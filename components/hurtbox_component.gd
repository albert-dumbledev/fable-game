class_name HurtboxComponent
extends Area3D
## Receives hits and routes them into a HealthComponent. If the scene root
## defines mitigate_hit(info) -> AttackInfo (or null to fully block), it runs
## first — this is where the player's shield check lives.

@export var health: HealthComponent


func receive_hit(info: AttackInfo) -> void:
	var final_info: AttackInfo = info
	var root := owner
	if root != null and root.has_method(&"mitigate_hit"):
		var result: Variant = root.call(&"mitigate_hit", info)
		if result == null:
			return
		final_info = result
	if health != null:
		health.take_damage(final_info)
