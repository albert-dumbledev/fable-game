class_name UpgradeData
extends Resource
## One purchasable meta upgrade. The death-screen shop is generated from these.

@export var id: StringName
@export var display_name := ""
@export var description := ""
@export var base_cost := 10
@export var cost_growth := 1.4
## 0 means no cap.
@export var max_level := 0
## Modifiers granted per level purchased.
@export var modifiers: Array[StatModifier] = []
## Ability flag granted to the player while owned (e.g. &"firebolt").
## Pair with max_level = 1 for one-time unlocks.
@export var grants_ability: StringName = &""
## Which shop branch this sits in (&"might", &"vigor", &"arcana"). The
## death-screen tree renders one column per branch, in registry order.
@export var branch: StringName = &"might"
## Tree gate: locked until the named upgrade reaches requires_level.
## Empty = a branch root, always available.
@export var requires_upgrade: StringName = &""
@export var requires_level := 1
## Hidden entirely from the shop until this ability flag is owned (weapon
## subtrees appear only after their boss drop). Empty = always visible.
@export var requires_ability: StringName = &""
## The loadout this upgrade belongs to (a weapon id). Only applies and only
## shows in the shop while that loadout is selected. Empty = universal.
@export var loadout: StringName = &""
## Which currency the shop charges and reads for this node (docs/DEPTHS.md Lane 2).
## Default &"gold" keeps every existing node on the run economy; the Reliquary
## branch sets &"shards" so its balance is charged/greyed against that pool and
## shown beside the branch header.
@export var currency: StringName = &"gold"
## Depth gate (docs/DEPTHS.md): hidden entirely from the shop until the player's
## deepest clear reaches this Depth (records.best_depth >= requires_depth) — the
## same hide-entirely idiom as requires_ability, so the Reliquary reads as a map
## of the descent. 0 = no Depth gate (visible as soon as its branch is).
@export var requires_depth := 0


func cost_at(level: int) -> int:
	return int(round(base_cost * pow(cost_growth, level)))
