class_name RunDirector
extends Node
## Owns one run: elapsed time, kill/gold tally, spawner pacing, and the
## death -> stats handoff to GameManager.

@onready var spawner: Spawner = $Spawner

const PICKUP_SCENE := preload("res://actors/pickups/Pickup.tscn")

# Level cadence target ~10-30s. A gentle geometric curve keeps that roughly
# constant as XP income ramps, while big chunks (swarms, bosses) still pop
# multiple levels at once via the while-loop in _grant_xp.
const XP_BASE := 14.0
const XP_GROWTH := 1.14

## Loot-eater: spawned reactively when the arena floor is carpeted with loot,
## not from the pool. See _maybe_spawn_scavenger.
const SCAVENGER_DATA := preload("res://data/enemies/scavenger.tres")
const SCAVENGER_LOOT_THRESHOLD := 20
const SCAVENGER_COOLDOWN := 25.0

## Aspect drops (Phase 9 M2): only the first elites per run reward an Aspect
## relic — later elites fall back to the M1 magnet-or-health bounty. Cutting
## this to 1 is the first lever if runs feel Aspect-flooded (see BOON_DROPS.md).
const ASPECT_ELITE_CAP := 2

## The finale boss (THE REVENANT, tagged &"finale") spawns at this clock time
## (see data/waves/default.tres); kept here as the reference for that spawn
## time, no longer an auto-win. The win now fires on the finale boss's death
## (see _track_boss / _on_finale_boss_died) — see finish_victory().
const VICTORY_TIME := 450.0
## Lets the boss death spectacle (slow-mo, detonation, 3 loot waves — ~2s,
## see BossBase._on_died) play out before the victory handoff cuts the scene.
const FINALE_VICTORY_DELAY := 2.5

var elapsed := 0.0
var kills := 0
var gold_earned := 0
var xp := 0
var level := 0
var _scavenger_cooldown := 0.0

var _run_active := true
## The active Depth (docs/DEPTHS.md), resolved from the save in _ready and handed
## to the spawner. null = Surface — every consumer treats null as today's run.
var depth: DepthData
## Recap accumulator (docs/RUN_RECAP.md) — a child node so it dies with the run.
var _stats_tracker: RunStats
## Per-event next-fire clock (repeating events re-arm; one-shots go INF).
var _next_event_at: PackedFloat64Array = []

## Boss-wave coordination: the relic drops (and the arena clears + spawns pause)
## only once EVERY boss of the wave is dead — the 2nd wave has two juggernauts.
var _spawning_paused := false
var _alive_bosses: Array[EnemyBase] = []
var _last_boss_data: EnemyData
var _last_boss_pos := Vector3.ZERO

## Elite Aspect budget: counts elite kills so only the first ASPECT_ELITE_CAP
## reward a relic (later elites use the bounty fallback).
var _elite_kills := 0


func _ready() -> void:
	GameManager.state = GameManager.State.IN_RUN
	add_to_group(&"run_director")
	# Resolve the chosen Depth once and hand it to the spawner (null = Surface).
	depth = MetaProgression.get_selected_depth_data()
	spawner.depth = depth
	_stats_tracker = RunStats.new()
	add_child(_stats_tracker)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.player_died.connect(_on_player_died)
	EventBus.unlock_claimed.connect(_on_unlock_claimed)
	EventBus.elite_died.connect(_on_elite_died)
	EventBus.run_started.emit()
	# Deferred so the HUD (readied after us) catches the initial state.
	EventBus.xp_changed.emit.call_deferred(xp, _xp_required(level), level)
	if depth != null:
		# Deferred for the same reason as the xp_changed emit above — the HUD's
		# announce label isn't ready yet on this frame.
		_announce_depth.call_deferred()


## Depth run-start announcement + stinger (docs/DEPTHS.md M2): the existing
## wave-announcement banner path carries the Depth's numeral + name, and a low
## descend stinger plays alongside it — Surface runs (depth == null) get
## neither, so today's run-start is untouched.
func _announce_depth() -> void:
	EventBus.wave_announcement.emit(
			"DEPTH %s — %s" % [DepthData.numeral(depth.level), depth.display_name])
	AudioManager.play(&"descend")


func _physics_process(delta: float) -> void:
	if not _run_active:
		return
	elapsed += delta
	# Spawning pauses after a boss wave clears, so the player can collect the
	# relic in peace; the run timer keeps advancing.
	if _spawning_paused:
		return
	spawner.tick(elapsed, delta)
	_fire_due_events()
	_maybe_spawn_scavenger(delta)


## Scheduled spawns (bosses, ambushes, repeating swarms) from the WaveTable.
func _fire_due_events() -> void:
	var table := spawner.wave_table
	if table == null:
		return
	if _next_event_at.size() != table.events.size():
		_next_event_at.resize(table.events.size())
		for i: int in table.events.size():
			_next_event_at[i] = table.events[i].time
	for i: int in table.events.size():
		if elapsed < _next_event_at[i]:
			continue
		var event := table.events[i]
		_next_event_at[i] = elapsed + event.repeat_every if event.repeat_every > 0.0 else INF
		# Chance events (the Gilded One) roll each fire; the re-arm above already
		# happened, so a miss just waits for the next window.
		if event.chance < 1.0 and randf() >= event.chance:
			continue
		# Rare bounty enemies (gold minimap blip) cap at one alive at a time.
		if event.enemy != null and event.enemy.tags.has(&"rare") and _rare_alive():
			continue
		if event.announcement != "":
			EventBus.wave_announcement.emit(event.announcement)
		# Depth swarms come thicker: scale repeating-event counts only, so
		# bosses and one-shots stay exactly as authored.
		var count := event.count
		if event.repeat_every > 0.0 and depth != null:
			count = int(round(count * depth.swarm_count_mult))
		for j: int in count:
			var enemy := spawner.spawn_enemy(event.enemy, elapsed)
			if enemy != null and event.enemy.tags.has(&"boss"):
				EventBus.boss_spawned.emit(enemy)
				_track_boss(enemy, event.enemy)


func _rare_alive() -> bool:
	for enemy: EnemyBase in EnemyBase.alive:
		if is_instance_valid(enemy) and enemy.data != null and enemy.data.tags.has(&"rare"):
			return true
	return false


## Spawn a Scavenger reactively when uncollected ground loot piles up — at most
## one alive, on a cooldown, and only past its time gate. It appears precisely
## when the player is leaving money on the floor (the post-swarm carpet).
func _maybe_spawn_scavenger(delta: float) -> void:
	_scavenger_cooldown = maxf(0.0, _scavenger_cooldown - delta)
	if _scavenger_cooldown > 0.0 or elapsed < SCAVENGER_DATA.min_elapsed:
		return
	if Pickup.edible.size() < SCAVENGER_LOOT_THRESHOLD or _scavenger_alive():
		return
	if spawner.spawn_enemy(SCAVENGER_DATA, elapsed) != null:
		_scavenger_cooldown = SCAVENGER_COOLDOWN


func _scavenger_alive() -> bool:
	for enemy: EnemyBase in EnemyBase.alive:
		if is_instance_valid(enemy) and enemy is ScavengerEnemy:
			return true
	return false


func _on_enemy_killed(_enemy_data: Resource, _position: Vector3) -> void:
	if not _run_active:
		return
	kills += 1
	# Gold/XP are no longer granted here — enemies drop collectable
	# pickups, and rewards land in _on_pickup_collected.


func _on_pickup_collected(kind: StringName, value: int) -> void:
	if not _run_active:
		return
	match kind:
		&"gold":
			gold_earned += value
			MetaProgression.add_currency(&"gold", value)
		&"xp":
			_grant_xp(value)


func _grant_xp(amount: int) -> void:
	xp += amount
	while xp >= _xp_required(level):
		xp -= _xp_required(level)
		level += 1
		EventBus.level_up.emit(level)
	EventBus.xp_changed.emit(xp, _xp_required(level), level)


func _xp_required(current_level: int) -> int:
	return int(round(XP_BASE * pow(XP_GROWTH, current_level)))


func _on_player_died() -> void:
	if not _run_active:
		return
	_run_active = false
	# Deferred: player_died fires mid-physics-frame; changing scene immediately
	# would yank nodes out of the tree while they still get processed this frame.
	GameManager.end_run.call_deferred(_final_stats({}))


## Quit from the pause menu: bank progress and take the same handoff as
## dying (stats + shop), minus the death itself.
func abandon_run() -> void:
	if not _run_active:
		return
	_run_active = false
	GameManager.end_run.call_deferred(_final_stats({"abandoned": true}))


## The end-of-run stats dict, shared by all three end paths: base tallies +
## the recap payload + which lifetime records this run set. record_run must
## precede save_game so the new bests land in the same write.
func _final_stats(extra: Dictionary) -> Dictionary:
	var stats := {"time": elapsed, "kills": kills, "gold": gold_earned, "level": level}
	stats.merge(extra)
	# The Depth this run was played at (0 = Surface); record_run keys the
	# depth-scoped bests off it.
	stats["depth"] = depth.level if depth != null else 0
	if _stats_tracker != null:
		stats["recap"] = _stats_tracker.to_dict()
	stats["new_records"] = MetaProgression.record_run(stats)
	MetaProgression.save_game()
	return stats


## Register a spawned boss so the wave can tell when the last one falls. The
## finale boss (tagged &"finale") wins the run on death instead of joining the
## normal wave-clear/relic tracking.
func _track_boss(boss: EnemyBase, boss_data: EnemyData) -> void:
	if boss_data.tags.has(&"finale"):
		boss.health.died.connect(_on_finale_boss_died)
		return
	_alive_bosses.append(boss)
	_last_boss_data = boss_data
	boss.health.died.connect(_on_boss_died.bind(boss))


func _on_boss_died(boss: EnemyBase) -> void:
	_alive_bosses.erase(boss)
	if is_instance_valid(boss):
		_last_boss_pos = boss.global_position
	if _alive_bosses.is_empty():
		_on_boss_wave_cleared()


## The last boss of a wave just died. A weapon relic takes priority: if one is
## owed, clear the remaining minions, pause spawning, and drop it where the boss
## fell. Once every weapon is owned, an Aspect relic drops instead via the same
## arena-clear + spawn-pause spectacle (M2) — the progression arc is weapons
## first, Aspects after. If neither has anything to give, nothing drops.
func _on_boss_wave_cleared() -> void:
	var ability := _next_unlock_drop(_last_boss_data)
	if ability != &"":
		_clear_for_relic()
		_spawn_relic(ability, _last_boss_pos)
		return
	# No weapon owed — offer an Aspect if the pool still has candidates.
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if AspectPool.available(player).is_empty():
		return
	_clear_for_relic()
	_spawn_aspect_relic(_last_boss_pos, true)


## Pause spawning and clear the remaining minions so the player can collect a
## boss relic in peace (the dying bosses still finish their loot choreography).
func _clear_for_relic() -> void:
	_spawning_paused = true
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if is_instance_valid(enemy) and not (enemy is BossEnemy):
			enemy.queue_free()


func _next_unlock_drop(boss_data: EnemyData) -> StringName:
	if boss_data == null:
		return &""
	var owned := MetaProgression.get_granted_abilities()
	for ability: StringName in boss_data.unlock_drops:
		if not owned.has(ability):
			return ability
	return &""


func _spawn_relic(ability: StringName, position: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var relic := PICKUP_SCENE.instantiate() as Pickup
	relic.ability = ability
	relic.setup(&"unlock", 1, Vector3(0.0, 6.0, 0.0))
	scene.add_child(relic)
	relic.global_position = position + Vector3(0.0, 1.2, 0.0)


## An elite just died (Aspect Drops M2). The first ASPECT_ELITE_CAP elites per
## run drop an Aspect relic (when the pool still has candidates); later elites,
## or an exhausted pool, fall back to the M1 magnet-or-health bounty. Elite
## relics never pause spawning or clear the arena — walking to one is the
## decision, so it can sit unclaimed while the fight continues.
func _on_elite_died(position: Vector3) -> void:
	if not _run_active:
		return
	_elite_kills += 1
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if _elite_kills <= ASPECT_ELITE_CAP and not AspectPool.available(player).is_empty():
		_spawn_aspect_relic(position, false)
	elif Pickup.magnets.is_empty():
		_spawn_utility_pickup(&"magnet", 1, EnemyBase.MAGNET_LIFETIME, position)
	else:
		_spawn_utility_pickup(&"health", EnemyBase.HEALTH_HEAL_PCT, 0.0, position)


## Drop an Aspect relic where an elite/boss fell. The relic carries no ability —
## the AspectScreen decides which Aspect on claim. `paused` documents the boss
## path (the caller already set _spawning_paused + cleared minions); the elite
## path passes false and leaves spawning running.
func _spawn_aspect_relic(position: Vector3, _paused: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var relic := PICKUP_SCENE.instantiate() as Pickup
	relic.setup(&"aspect", 1, Vector3(0.0, 6.0, 0.0))
	scene.add_child(relic)
	relic.global_position = position + Vector3(0.0, 1.2, 0.0)


## The elite bounty fallback: one utility pickup (magnet or health) with a gentle
## upward burst, mirroring EnemyBase._spawn_single_pickup. `lifetime` overrides
## the pickup default when > 0.
func _spawn_utility_pickup(kind: StringName, value: int, lifetime: float, position: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var pickup := PICKUP_SCENE.instantiate() as Pickup
	var burst := Vector3(randf_range(-1.5, 1.5), randf_range(6.0, 9.0), randf_range(-1.5, 1.5))
	pickup.setup(kind, value, burst)
	if lifetime > 0.0:
		pickup.lifetime = lifetime
	scene.add_child(pickup)
	pickup.global_position = position + Vector3(0.0, 1.2, 0.0)


## An Aspect was picked from the relic modal — resume boss-paused spawning.
## Mirrors _on_unlock_claimed; called by AspectScreen after the pick (not on the
## relic touch), so elite relics never pause the run while they sit unclaimed.
func resume_from_aspect() -> void:
	_spawning_paused = false


## A relic was claimed — resume the wave. Every relic (including the staff, which
## is now a normal weapon unlock rather than the run-ender) just continues the
## run; victory is the finale boss kill (finish_victory), not a weapon drop.
func _on_unlock_claimed(_ability: StringName) -> void:
	_spawning_paused = false


## The finale boss (THE REVENANT) just died — let its death spectacle and loot
## fountain play out (BossBase._on_died runs ~2s of slow-mo/detonation/3 loot
## waves before queue_free) before cutting to the victory screen.
## finish_victory() guards on _run_active, so this is safe even if the player
## also dies in the same window (whichever handoff lands first wins).
func _on_finale_boss_died() -> void:
	get_tree().create_timer(FINALE_VICTORY_DELAY, false).timeout.connect(finish_victory)


## The finale-boss-kill win (see _on_finale_boss_died): bank the run and hand
## off to the victory screen. Deferred + idempotent so it's safe to fire from
## a timer callback or mid-physics-frame.
func finish_victory() -> void:
	if not _run_active:
		return
	_run_active = false
	GameManager.end_run.call_deferred(_final_stats({"victory": true}))
