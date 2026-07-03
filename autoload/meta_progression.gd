extends Node
## Persistent meta-progression: currency balances and purchased upgrade levels.
## Currencies are keyed by id so new currencies (XP, prestige shards) are data,
## not new systems — this is the prestige hook.

const SAVE_PATH: String = "user://save.json"
const REGISTRY_PATH: String = "res://data/upgrades/registry.tres"

var currencies: Dictionary[StringName, int] = {}
var upgrade_levels: Dictionary[StringName, int] = {}
var registry: UpgradeRegistry


func _ready() -> void:
	registry = load(REGISTRY_PATH) as UpgradeRegistry
	if registry == null:
		push_error("Failed to load upgrade registry: %s" % REGISTRY_PATH)
	load_game()


## Ability flags granted by owned upgrades (spell unlocks etc.).
func get_granted_abilities() -> Array[StringName]:
	var abilities: Array[StringName] = []
	if registry == null:
		return abilities
	for upgrade: UpgradeData in registry.upgrades:
		if upgrade.grants_ability != &"" and get_upgrade_level(upgrade.id) > 0:
			abilities.append(upgrade.grants_ability)
	return abilities


## Every modifier granted by purchased upgrades; applied by the player on spawn.
func get_stat_modifiers() -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	if registry == null:
		return modifiers
	for upgrade: UpgradeData in registry.upgrades:
		var level := get_upgrade_level(upgrade.id)
		for i: int in level:
			modifiers.append_array(upgrade.modifiers)
	return modifiers


func get_currency(id: StringName) -> int:
	return currencies.get(id, 0)


func add_currency(id: StringName, amount: int) -> void:
	currencies[id] = get_currency(id) + amount
	EventBus.currency_changed.emit(id, currencies[id])


## Returns true and deducts if the balance covers `amount`; false otherwise.
func try_spend(id: StringName, amount: int) -> bool:
	if get_currency(id) < amount:
		return false
	add_currency(id, -amount)
	return true


func get_upgrade_level(id: StringName) -> int:
	return upgrade_levels.get(id, 0)


func increment_upgrade(id: StringName) -> void:
	upgrade_levels[id] = get_upgrade_level(id) + 1


func save_game() -> void:
	var data: Dictionary = {
		"currencies": _to_string_keys(currencies),
		"upgrade_levels": _to_string_keys(upgrade_levels),
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save file for writing: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file for reading: %s" % SAVE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Save file is corrupt, starting fresh: %s" % SAVE_PATH)
		return
	var data: Dictionary = parsed
	currencies = _to_int_values(data.get("currencies", {}))
	upgrade_levels = _to_int_values(data.get("upgrade_levels", {}))


## JSON keys must be String and numbers come back as float; convert both ways.
func _to_string_keys(source: Dictionary[StringName, int]) -> Dictionary:
	var result: Dictionary = {}
	for key: StringName in source:
		result[String(key)] = source[key]
	return result


func _to_int_values(source: Variant) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if source is not Dictionary:
		return result
	var dict: Dictionary = source
	for key: Variant in dict:
		if key is String and dict[key] is float:
			result[StringName(key)] = int(dict[key])
	return result
