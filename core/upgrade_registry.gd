class_name UpgradeRegistry
extends Resource
## Single registry resource listing every purchasable upgrade, so the shop and
## MetaProgression never scan directories (which breaks in exported builds).

@export var upgrades: Array[UpgradeData] = []
