class_name WaveTable
extends Resource
## Difficulty schedule for a run: spawn pacing, stat scaling, and the enemy
## pool. Bosses later become scheduled entries here.

@export var enemies: Array[EnemyData] = []
## Scheduled one-shot spawns (bosses, ambushes), sorted by time.
@export var events: Array[WaveEvent] = []
@export var start_interval := 2.5
@export var min_interval := 0.4
@export var interval_ramp_time := 240.0
@export var hp_growth_per_min := 0.5
@export var dmg_growth_per_min := 0.25
## Gold/XP drops scale alongside enemy strength.
@export var reward_growth_per_min := 0.3
@export var max_alive_start := 15
@export var max_alive_end := 60
@export var max_alive_ramp_time := 300.0


func spawn_interval_at(elapsed: float) -> float:
	return lerpf(start_interval, min_interval, clampf(elapsed / interval_ramp_time, 0.0, 1.0))


func hp_mult_at(elapsed: float) -> float:
	return 1.0 + hp_growth_per_min * elapsed / 60.0


func dmg_mult_at(elapsed: float) -> float:
	return 1.0 + dmg_growth_per_min * elapsed / 60.0


func reward_mult_at(elapsed: float) -> float:
	return 1.0 + reward_growth_per_min * elapsed / 60.0


func max_alive_at(elapsed: float) -> int:
	var t := clampf(elapsed / max_alive_ramp_time, 0.0, 1.0)
	return int(round(lerpf(float(max_alive_start), float(max_alive_end), t)))


func pick_enemy(elapsed: float) -> EnemyData:
	var total := 0.0
	for data: EnemyData in enemies:
		if elapsed >= data.min_elapsed:
			total += data.spawn_weight
	if total <= 0.0:
		return null
	var roll := randf() * total
	var last: EnemyData = null
	for data: EnemyData in enemies:
		if elapsed < data.min_elapsed:
			continue
		last = data
		roll -= data.spawn_weight
		if roll <= 0.0:
			return data
	return last
