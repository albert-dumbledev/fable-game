class_name WaveEvent
extends Resource
## A scheduled spawn in a WaveTable — bosses, ambush packs, etc.
## Fires once when the run clock crosses `time`; ignores the alive cap.

@export var time := 120.0
@export var enemy: EnemyData
@export var count := 1
## Shown as a HUD banner when the event fires. Empty = silent.
@export var announcement := ""
