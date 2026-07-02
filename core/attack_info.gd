class_name AttackInfo
extends RefCounted
## Every damage event flows through one of these. Crits, elements, lifesteal,
## and damage numbers all hook in here later.

var source: Node3D
var damage: float


func _init(p_source: Node3D = null, p_damage: float = 0.0) -> void:
	source = p_source
	damage = p_damage
