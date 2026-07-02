class_name StatModifier
extends Resource
## A single change to one stat. Upgrades, boons, weapon bonuses, and future
## prestige multipliers are all just lists of these.

enum Kind { FLAT, PERCENT_ADD, PERCENT_MULT }

@export var stat: StringName
@export var kind: Kind = Kind.FLAT
@export var value: float = 0.0
