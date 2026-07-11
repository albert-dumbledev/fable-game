class_name AttackInfo
extends RefCounted
## Every damage event flows through one of these. Crits, elements, lifesteal,
## and damage numbers all hook in here later.

var source: Node3D
var damage: float
## Impulse strength pushing the victim away from `source` on hit.
var knockback: float
## SFX the victim plays when this lands; direct melee contact overrides it
## with the meatier &"melee_hit".
var hit_sound: StringName = &"hit"
## True when this hit is delivered by an in-flight enemy projectile (Spitter
## bolt, Caster/Hierophant fireball) rather than melee. Lets a perfect block
## tell melee from ranged — Mirror Ward only reflects the latter. Boulders
## never set it (the mortar has no mid-flight collision to block).
var projectile := false


func _init(p_source: Node3D = null, p_damage: float = 0.0, p_knockback: float = 0.0) -> void:
	source = p_source
	damage = p_damage
	knockback = p_knockback
