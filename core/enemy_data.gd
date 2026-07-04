class_name EnemyData
extends Resource
## Data definition for one enemy type. New enemies are new .tres files.

@export var display_name := ""
@export var scene: PackedScene
@export var max_health := 25.0
@export var move_speed := 4.5
@export var damage := 10.0
@export var attack_range := 1.8
@export var windup_time := 0.4
@export var recover_time := 0.8
## Impulse shoving the player on a landed hit.
@export var knockback := 5.0
@export var gold_reward := 5
@export var xp_reward := 3
@export var spawn_weight := 1.0
## Run time (seconds) before this enemy can appear in the spawn pool.
@export var min_elapsed := 0.0
@export var weight_ramp_duration := 0.0
@export var tags: Array[StringName] = []
## Ordered ability flags; on boss death the first one the player doesn't own
## drops as a weapon relic.
@export var unlock_drops: Array[StringName] = []
