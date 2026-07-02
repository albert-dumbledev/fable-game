class_name StatBlock
extends RefCounted
## Base stat values plus a modifier list. Resolution order:
## base -> +sum(flat) -> *(1 + sum(percent_add)) -> *product(1 + percent_mult).

var _base: Dictionary[StringName, float] = {}
var _modifiers: Array[StatModifier] = []
var _cache: Dictionary[StringName, float] = {}


func set_base(stat: StringName, value: float) -> void:
	_base[stat] = value
	_cache.erase(stat)


func add_modifier(modifier: StatModifier) -> void:
	_modifiers.append(modifier)
	_cache.erase(modifier.stat)


func get_stat(stat: StringName) -> float:
	if _cache.has(stat):
		return _cache[stat]
	var value: float = _base.get(stat, 0.0)
	var flat := 0.0
	var percent_add := 0.0
	var percent_mult := 1.0
	for modifier: StatModifier in _modifiers:
		if modifier.stat != stat:
			continue
		match modifier.kind:
			StatModifier.Kind.FLAT:
				flat += modifier.value
			StatModifier.Kind.PERCENT_ADD:
				percent_add += modifier.value
			StatModifier.Kind.PERCENT_MULT:
				percent_mult *= 1.0 + modifier.value
	value = (value + flat) * (1.0 + percent_add) * percent_mult
	_cache[stat] = value
	return value
