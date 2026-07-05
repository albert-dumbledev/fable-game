extends Node
## Persistent meta-progression: currency balances and purchased upgrade levels.
## Currencies are keyed by id so new currencies (XP, prestige shards) are data,
## not new systems — this is the prestige hook.

const SAVE_PATH: String = "user://save.json"
const REGISTRY_PATH: String = "res://data/upgrades/registry.tres"
const WEAPON_REGISTRY_PATH: String = "res://data/weapons/registry.tres"
const DEFAULT_WEAPON: StringName = &"sword_and_shield"
const SAVE_VERSION := 2

var currencies: Dictionary[StringName, int] = {}
var upgrade_levels: Dictionary[StringName, int] = {}
var registry: UpgradeRegistry
var weapon_registry: WeaponRegistry
## Loadout: the weapon the player spawns with, chosen pre-run. Persisted.
var selected_weapon: StringName = DEFAULT_WEAPON
## Permanent abilities granted by boss drops (weapon unlocks). Persisted
## separately from shop upgrades; unioned into get_granted_abilities().
var unlocked_abilities: Array[StringName] = []


func _ready() -> void:
	registry = load(REGISTRY_PATH) as UpgradeRegistry
	if registry == null:
		push_error("Failed to load upgrade registry: %s" % REGISTRY_PATH)
	weapon_registry = load(WEAPON_REGISTRY_PATH) as WeaponRegistry
	if weapon_registry == null:
		push_error("Failed to load weapon registry: %s" % WEAPON_REGISTRY_PATH)
	load_game()


## Ability flags granted by owned upgrades (spells) unioned with boss-drop
## weapon unlocks. This one function is what is_weapon_unlocked, the loadout
## picker, and boon gating all read.
func get_granted_abilities() -> Array[StringName]:
	var abilities: Array[StringName] = []
	if registry != null:
		for upgrade: UpgradeData in registry.upgrades:
			if upgrade.loadout != &"" and upgrade.loadout != selected_weapon:
				continue
			if upgrade.grants_ability != &"" and get_upgrade_level(upgrade.id) > 0:
				abilities.append(upgrade.grants_ability)
	for ability: StringName in unlocked_abilities:
		if not abilities.has(ability):
			abilities.append(ability)
	return abilities


## Grants a permanent ability from a boss drop and saves immediately — dying
## seconds after the pickup must not eat the unlock.
func grant_meta_ability(ability: StringName) -> void:
	if ability == &"" or unlocked_abilities.has(ability):
		return
	unlocked_abilities.append(ability)
	save_game()


## Every modifier granted by purchased upgrades; applied by the player on spawn.
func get_stat_modifiers() -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	if registry == null:
		return modifiers
	for upgrade: UpgradeData in registry.upgrades:
		if upgrade.loadout != &"" and upgrade.loadout != selected_weapon:
			continue
		var level := get_upgrade_level(upgrade.id)
		for i: int in level:
			modifiers.append_array(upgrade.modifiers)
	return modifiers


## Unlocked = no gate, or the gating ability flag is owned (weapon unlocks
## are ability-granting upgrades, same as spells).
func is_weapon_unlocked(weapon: WeaponData) -> bool:
	return weapon.unlock_ability == &"" \
			or get_granted_abilities().has(weapon.unlock_ability)


func get_unlocked_weapons() -> Array[WeaponData]:
	var unlocked: Array[WeaponData] = []
	if weapon_registry == null:
		return unlocked
	for weapon: WeaponData in weapon_registry.weapons:
		if is_weapon_unlocked(weapon):
			unlocked.append(weapon)
	return unlocked


func select_weapon(id: StringName) -> void:
	selected_weapon = id


## The loadout choice, validated: falls back to the first unlocked weapon if
## the saved id is unknown or (e.g. via an edited save) no longer unlocked.
func get_selected_weapon() -> WeaponData:
	var fallback: WeaponData = null
	for weapon: WeaponData in get_unlocked_weapons():
		if fallback == null:
			fallback = weapon
		if weapon.id == selected_weapon:
			return weapon
	return fallback


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
		"save_version": SAVE_VERSION,
		"currencies": _to_string_keys(currencies),
		"upgrade_levels": _to_string_keys(upgrade_levels),
		"unlocked_abilities": _abilities_to_array(unlocked_abilities),
		"selected_weapon": String(selected_weapon),
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
	unlocked_abilities = _to_abilities(data.get("unlocked_abilities", []))
	var weapon_id: Variant = data.get("selected_weapon", String(DEFAULT_WEAPON))
	if weapon_id is String:
		selected_weapon = StringName(weapon_id)
	# Legacy-data migration: keyed on pre-rework upgrade keys and self-erasing,
	# so it runs once per save and stays correct even after the version bumps
	# (a save migrated by an earlier milestone still gets later steps).
	if _migrate_legacy_unlocks():
		save_game()


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


## Weapon unlocks moved from the gold shop to boss drops. Keyed on the legacy
## upgrade entries and self-erasing. Returns true if anything changed.
func _migrate_legacy_unlocks() -> bool:
	var changed := false
	# Warhammer: a veteran who bought it keeps the weapon (moved to
	# unlocked_abilities) and is refunded the 250 gold; the boss drop then
	# gates fresh saves only.
	if upgrade_levels.has(&"warhammer_unlock"):
		if upgrade_levels[&"warhammer_unlock"] > 0:
			if not unlocked_abilities.has(&"weapon_warhammer"):
				unlocked_abilities.append(&"weapon_warhammer")
			add_currency(&"gold", 250)
		upgrade_levels.erase(&"warhammer_unlock")
		changed = true
	# Staff split (v1 -> v2): fireball is now built into the staff and Frost
	# Nova is a staff-gated Arcana purchase. A veteran who bought fireball keeps
	# the caster fantasy (gets the staff) and is refunded the 150 gold, since
	# fireball no longer costs a shop slot.
	if upgrade_levels.has(&"firebolt"):
		if upgrade_levels[&"firebolt"] > 0:
			if not unlocked_abilities.has(&"weapon_staff"):
				unlocked_abilities.append(&"weapon_staff")
			add_currency(&"gold", 150)
		upgrade_levels.erase(&"firebolt")
		changed = true
	# Frost Nova stays a valid purchase (level kept, not refunded), just re-gated
	# behind the staff they now own — so grant the staff without erasing it.
	if upgrade_levels.get(&"frost_nova", 0) > 0 and not unlocked_abilities.has(&"weapon_staff"):
		unlocked_abilities.append(&"weapon_staff")
		changed = true
	return changed


## StringName array -> plain String array for JSON.
func _abilities_to_array(source: Array[StringName]) -> Array:
	var result: Array = []
	for ability: StringName in source:
		result.append(String(ability))
	return result


## JSON array (of String) -> typed StringName array.
func _to_abilities(source: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if source is not Array:
		return result
	for value: Variant in source:
		if value is String:
			result.append(StringName(value))
	return result
