class_name Stats
extends RefCounted
## Canonical stat ids. Every StatBlock key and StatModifier target uses these.
##
## The *_MULT-style stats (spell_cooldown, cast_time, fireball_aoe,
## hammer_aoe) have base 1.0 and act as multipliers on their base numbers;
## boons move them with PERCENT_ADD modifiers (negative = reduction).

const MAX_HEALTH := &"max_health"
const DAMAGE := &"damage"
const ATTACK_SPEED := &"attack_speed"
const MOVE_SPEED := &"move_speed"
const SPELL_COOLDOWN := &"spell_cooldown"
const CAST_TIME := &"cast_time"
const FIREBALL_AOE := &"fireball_aoe"
const FIREBALL_CHARGES := &"fireball_charges"
const HAMMER_AOE := &"hammer_aoe"


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
		SPELL_COOLDOWN:
			return "spell cooldown"
		CAST_TIME:
			return "cast time"
		FIREBALL_AOE:
			return "fireball blast size"
		FIREBALL_CHARGES:
			return "fireball charge"
		HAMMER_AOE:
			return "slam size"
	return String(stat)
