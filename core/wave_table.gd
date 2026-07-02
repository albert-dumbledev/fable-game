class_name WaveTable
extends Resource
## Difficulty schedule for a run: spawn pacing, stat scaling, and the enemy
## pool. Bosses later become scheduled entries here.

@export var enemies: Array[EnemyData] = []
@export var start_interval := 2.5
@export var min_interval := 0.4
@export var interval_ramp_time := 240.0
@export var hp_growth_per_min := 0.5
@export var dmg_growth_per_min := 0.25
@export var max_alive_start := 15
@export var max_alive_end := 60
@export var max_alive_ramp_time := 300.0


func spawn_interval_at(elapsed: float) -> float:
	return lerpf(start_interval, min_interval, clampf(elapsed / interval_ramp_time, 0.0, 1.0))


func hp_mult_at(elapsed: float) -> float:
	return 1.0 + hp_growth_per_min * elapsed / 60.0


func dmg_mult_at(elapsed: float) -> float:
	return 1.0 + dmg_growth_per_min * elapsed / 60.0


func max_alive_at(elapsed: float) -> int:
	var t := clampf(elapsed / max_alive_ramp_time, 0.0, 1.0)
	return int(round(lerpf(float(max_alive_start), float(max_alive_end), t)))


func pick_enemy() -> EnemyData:
	if enemies.is_empty():
		return null
	var total := 0.0
	for data: EnemyData in enemies:
		total += data.spawn_weight
	var roll := randf() * total
	for data: EnemyData in enemies:
		roll -= data.spawn_weight
		if roll <= 0.0:
			return data
	return enemies[-1]
