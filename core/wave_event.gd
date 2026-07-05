class_name WaveEvent
extends Resource
## A scheduled spawn in a WaveTable — bosses, ambush packs, swarms.
## Fires when the run clock crosses `time`; ignores the alive cap.

@export var time := 120.0
@export var enemy: EnemyData
@export var count := 1
## Shown as a HUD banner when the event fires. Empty = silent.
@export var announcement := ""
## 0 = fire once. Otherwise the event re-fires this many seconds after
## each firing, forever (swarms that keep coming).
@export var repeat_every := 0.0
## Chance to actually fire when the clock crosses `time` (and on each repeat).
## 1.0 = always. `repeat_every` re-arms regardless of the roll — a miss just
## waits for the next window. Used for rare random events (the Gilded One).
@export var chance := 1.0
