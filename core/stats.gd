class_name Stats
extends RefCounted
## Canonical stat ids. Every StatBlock key and StatModifier target uses these.

const MAX_HEALTH := &"max_health"
const DAMAGE := &"damage"
const ATTACK_SPEED := &"attack_speed"
const MOVE_SPEED := &"move_speed"


static func display_name(stat: StringName) -> String:
	match stat:
		MAX_HEALTH:
			return "max health"
		DAMAGE:
			return "damage"
		ATTACK_SPEED:
			return "attack speed"
		MOVE_SPEED:
			return "move speed"
	return String(stat)
