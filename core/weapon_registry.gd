class_name WeaponRegistry
extends Resource
## Single registry resource listing every playable weapon (the loadout pool),
## so nothing scans directories (which breaks in exported builds).

@export var weapons: Array[WeaponData] = []
