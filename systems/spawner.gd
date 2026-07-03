class_name Spawner
extends Node
## Places enemies in a ring around the player, outside melee range but inside
## the arena. Pacing and scaling come from the WaveTable; RunDirector drives it.

const ARENA_HALF := 18.5
const RING_MIN := 14.0
const RING_MAX := 22.0
const SPAWN_HEIGHT := 1.0

@export var wave_table: WaveTable

var _spawn_timer := 0.0


func tick(elapsed: float, delta: float) -> void:
	if wave_table == null:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = wave_table.spawn_interval_at(elapsed)
	if get_tree().get_nodes_in_group(&"enemies").size() >= wave_table.max_alive_at(elapsed):
		return
	_spawn(elapsed)


func _spawn(elapsed: float) -> void:
	var target := get_tree().get_first_node_in_group(&"player") as Node3D
	if target == null:
		return
	var data := wave_table.pick_enemy(elapsed)
	if data == null or data.scene == null:
		return
	var enemy := data.scene.instantiate() as EnemyBase
	if enemy == null:
		return
	enemy.setup(data, wave_table.hp_mult_at(elapsed), wave_table.dmg_mult_at(elapsed))
	var angle := randf() * TAU
	var radius := randf_range(RING_MIN, RING_MAX)
	var pos := target.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	pos.x = clampf(pos.x, -ARENA_HALF, ARENA_HALF)
	pos.z = clampf(pos.z, -ARENA_HALF, ARENA_HALF)
	pos.y = SPAWN_HEIGHT
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = pos
