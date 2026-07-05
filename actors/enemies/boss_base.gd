class_name BossBase
extends EnemyBase
## Shared boss plumbing: the death spectacle (slow-mo, white-hot swell,
## detonation) and the three-fountain loot wave. Both the Juggernaut
## (`BossEnemy`) and the Caster (`CasterBoss`) extend this — they share none
## of each other's combat kit, only the way a boss dies and pays out.

## Death spectacle: slow-mo while the boss flashes white-hot and swells,
## then a detonation and three radial waves of loot. All timings are
## real-time seconds (the choreography tween ignores Engine.time_scale,
## otherwise the slow-mo would stretch its own animation).
const DEATH_SLOWMO_SCALE := 0.3
const DEATH_SLOWMO_TIME := 0.55
const DEATH_SWELL := 1.35
const DEATH_SWELL_TIME := 0.45
const DEATH_FLASH_COLOR := Color(1.0, 0.95, 0.8)
const DEATH_BURST_COLOR := Color(1.0, 0.7, 0.25, 0.5)
## Same total reward as a normal kill, just split into far more pieces across
## three fountains — spectacle, not inflation.
const LOOT_WAVES := 3
const LOOT_WAVE_INTERVAL := 0.4
const LOOT_GOLD_PIECES := 12
const LOOT_XP_PIECES := 8
const LOOT_BURST_SPEED := 1.6
const LOOT_LIFETIME := 60.0
const LOOT_MAGNET_RADIUS := 6.5
const LOOT_RING_COLOR := Color(1.0, 0.8, 0.3, 0.6)


## Bosses don't just shrink away — the world slows, the body flashes
## white-hot and swells, then detonates into shards and three fountains
## of loot. Replaces EnemyBase._on_died entirely (same bookkeeping up
## front, different exit). Subclasses override to cancel their own attack
## state first, then call super().
func _on_died() -> void:
	_set_state(State.DEAD)
	remove_from_group(&"enemies")
	collision_layer = 0
	hitbox.deactivate()
	hurtbox.set_deferred(&"monitorable", false)
	EventBus.enemy_killed.emit(data, global_position)
	AudioManager.play(&"boss_death")
	FreezeFrame.slow_motion(DEATH_SLOWMO_SCALE, DEATH_SLOWMO_TIME)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.add_shake(0.8)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = DEATH_FLASH_COLOR
		_material.emission_enabled = true
		_material.emission = Color(1.0, 0.85, 0.5)
		_material.emission_energy_multiplier = 2.0
	var seq := create_tween()
	seq.set_ignore_time_scale(true)
	seq.tween_property(mesh, "scale", Vector3.ONE * DEATH_SWELL, DEATH_SWELL_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	seq.tween_callback(_death_burst)
	for wave: int in LOOT_WAVES:
		seq.tween_callback(_spawn_loot_wave.bind(wave))
		seq.tween_interval(LOOT_WAVE_INTERVAL)
	seq.tween_callback(queue_free)


## The detonation: hide the body, ring the arena, throw color-matched
## shards. The node stays alive (invisible) to anchor the loot waves.
func _death_burst() -> void:
	if not is_inside_tree():
		return
	visible = false
	var scene := get_tree().current_scene
	var center := global_position + Vector3(0.0, 1.2, 0.0)
	BlastVfx.spawn(scene, center, 7.0, LOOT_RING_COLOR, 0.5, 0.45)
	BlastVfx.spawn(scene, global_position + Vector3(0.0, 0.15, 0.0), 9.0,
			DEATH_BURST_COLOR, 0.08, 0.5)
	ShardBurst.spawn(scene, center, _base_color, 36, 12.0, 0.22, 1.0)


func _spawn_loot_wave(wave: int) -> void:
	if not is_inside_tree():
		return
	var gold_total := int(round(data.gold_reward * _reward_mult))
	var xp_total := int(round(data.xp_reward * _reward_mult))
	_spawn_pickup_pieces(&"gold", _wave_share(gold_total, wave), LOOT_GOLD_PIECES,
			LOOT_BURST_SPEED, true, LOOT_LIFETIME, LOOT_MAGNET_RADIUS)
	_spawn_pickup_pieces(&"xp", _wave_share(xp_total, wave), LOOT_XP_PIECES,
			LOOT_BURST_SPEED, true, LOOT_LIFETIME, LOOT_MAGNET_RADIUS)
	# The fight is where you bled for it — the first loot wave always
	# carries a guaranteed heal.
	if wave == 0:
		_spawn_single_pickup(&"health", EnemyBase.HEALTH_HEAL_PCT, 0.0)
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.2, 0.0), 3.5, LOOT_RING_COLOR, 0.1, 0.3)


## Even split of the total across the waves, remainder to the early ones.
func _wave_share(total: int, wave: int) -> int:
	@warning_ignore("integer_division")
	var base := total / LOOT_WAVES
	return base + (1 if wave < total % LOOT_WAVES else 0)
