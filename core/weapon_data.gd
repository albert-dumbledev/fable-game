class_name WeaponData
extends Resource
## Data definition for one weapon. Behavior lives in a Weapon subclass scene,
## referenced by path (not PackedScene) so the .tres and the .tscn that uses
## it never form a resource load cycle.

@export var id: StringName
@export var display_name := ""
@export var description := ""
@export var damage := 10.0
@export var swing_time := 0.45
## False for two-handed weapons: RMB is ignored and no block mitigation runs.
@export var can_block := true
## Scene instanced into the player's WeaponMount on spawn.
@export_file("*.tscn") var scene_path := ""
## Ability flag that unlocks this weapon in the loadout (empty = always available).
@export var unlock_ability: StringName = &""
## Ability flags granted to the player while this weapon is mounted (e.g. the
## staff grants &"firebolt"). This keeps spell flags as the single mechanism —
## the spell arrives from the mount instead of the shop.
@export var grants_abilities: Array[StringName] = []
