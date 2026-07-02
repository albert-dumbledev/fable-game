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


func cost_at(level: int) -> int:
	return int(round(base_cost * pow(cost_growth, level)))
