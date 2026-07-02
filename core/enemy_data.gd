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
@export var gold_reward := 5
@export var spawn_weight := 1.0
@export var tags: Array[StringName] = []
