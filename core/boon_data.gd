class_name BoonData
extends Resource
## A temporary, run-scoped power-up offered on level-up. Same StatModifier
## machinery as permanent upgrades — only the lifetime differs.

@export var id: StringName
@export var display_name := ""
@export var description := ""
@export var weight := 1.0
@export var modifiers: Array[StatModifier] = []
