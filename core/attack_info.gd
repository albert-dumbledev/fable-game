class_name AttackInfo
extends RefCounted
## Every damage event flows through one of these. Crits, elements, lifesteal,
## and damage numbers all hook in here later.

var source: Node3D
var damage: float
## Impulse strength pushing the victim away from `source` on hit.
var knockback: float


func _init(p_source: Node3D = null, p_damage: float = 0.0, p_knockback: float = 0.0) -> void:
	source = p_source
	damage = p_damage
	knockback = p_knockback
