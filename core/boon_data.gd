class_name BoonData
extends Resource
## A temporary, run-scoped power-up offered on level-up. Same StatModifier
## machinery as permanent upgrades — only the lifetime differs.
##
## Regular boons get their modifier values scaled by the rarity rolled at
## offer time. Unique boons grant an ability flag instead, never scale,
## and are offered at most once per run.

@export var id: StringName
@export var display_name := ""
## Hand-written flavor text. Used verbatim for unique boons; regular
## boons auto-generate their description from modifiers so the numbers
## always match the rolled rarity.
@export var description := ""
@export var weight := 1.0
@export var modifiers: Array[StatModifier] = []
@export var unique := false
## Ability flag granted to the player on pick (e.g. &"dash").
@export var grants_ability: StringName = &""
## Only offered while this weapon is mounted (WeaponData id; empty = any).
@export var requires_weapon: StringName = &""
## Only offered if the player owns at least one of these ability flags
## (e.g. spell boons gated on the spell being unlocked). Empty = no gate.
@export var requires_any_ability: Array[StringName] = []
## Optional per-rarity value multiplier override (indexed COMMON, RARE, EPIC,
## LEGENDARY). Empty = use the global rarity mults. Lets a boon scale on its
## own curve instead of the shared one.
@export var rarity_mults: Array[float] = []


func describe(value_mult: float = 1.0) -> String:
	if unique or modifiers.is_empty():
		return description
	var parts: Array[String] = []
	for modifier: StatModifier in modifiers:
		var value := modifier.value * value_mult
		var stat_name := Stats.display_name(modifier.stat)
		match modifier.kind:
			StatModifier.Kind.FLAT:
				parts.append("+%s %s" % [_format_number(value), stat_name])
			StatModifier.Kind.PERCENT_ADD:
				# Signed so reductions (e.g. -12% spell cooldown) read right.
				parts.append("%+d%% %s" % [int(round(value * 100.0)), stat_name])
			StatModifier.Kind.PERCENT_MULT:
				parts.append("x%.2f %s" % [1.0 + value, stat_name])
	return ", ".join(parts)


static func _format_number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value
