class_name RunDirector
extends Node
## Owns one run: elapsed time, kill/gold tally, spawner pacing, and the
## death -> stats handoff to GameManager.

@onready var spawner: Spawner = $Spawner


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

## Lateral gap between multiple boss-wave Aspect relics (docs/DEPTHS.md M3) so a
## Depth III+ double drop reads as two pickups, not one flickering on the spot.
const RELIC_SPREAD := 2.0

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
## The run's event schedule: the WaveTable's events plus the Depth's extra_events
## (docs/DEPTHS.md M3 — e.g. the Twin Court's second Juggernaut), built once and
## cached locally. NEVER the WaveTable's own array, which is shared across runs;
## rebuilt only if its size drifts from the source (mirrors the resize guard).
var _combined_events: Array[WaveEvent] = []
## Depth pinned-Legendary once-flag (docs/DEPTHS.md): the first boon screen past
## 3:00 on a pin_legendary Depth forces one Legendary offer, then sets this so no
## later screen re-pins. Lives on the director because BoonScreen is per-level-up.
var depth_legendary_pinned := false

## Boss-wave coordination: the relic drops (and the arena clears + spawns pause)
## only once EVERY boss of the wave is dead — the 2nd wave has two juggernauts.
var _spawning_paused := false
## Boss-wave Aspect relics still awaiting a pick (docs/DEPTHS.md M3): a Depth III+
## boss wave drops several, and spawning stays paused until the LAST one resolves.
var _pending_relic_claims := 0
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
	# Windup compression is a run-scoped static that outlives the scene, so it is
	# set EVERY run — 0.85 at THE QUICKENING, back to 1.0 on Surface so a Depth run
	# never leaves faster telegraphs bleeding into the next Surface run.
	EnemyBase.depth_time_scale = depth.windup_mult if depth != null else 1.0
	# Defensive reset of the Dead Weight chain guard: it self-clears within each
	# chain call, but a static that outlives the scene is reset every run anyway.
	EnemyBase.dead_weight_chaining = false
	# Subtle arena mood tint (display-only); Surface runs render untouched.
	if depth != null:
		_apply_ambient_tint()
	_stats_tracker = RunStats.new()
	add_child(_stats_tracker)
	# Deep Cache (Reliquary QoL): begin a run with a magnet already primed. Deferred
	# so the player node is up before we place it (same reason as the emits below).
	_prime_deep_cache.call_deferred()
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


## Nudge the arena ambient toward the Depth's tint (docs/DEPTHS.md M3) — a subtle
## component-wise multiply, display-only, no gameplay effect. The Environment is a
## scene sub-resource shared across every Arena instance (Godot caches them), so it
## is DUPLICATED before tinting; otherwise the shift would bleed into later Surface
## runs. Only depth runs call this, so Surface renders byte-identical to today.
func _apply_ambient_tint() -> void:
	var world_env := _find_world_environment()
	if world_env == null or world_env.environment == null:
		return
	var tinted := world_env.environment.duplicate() as Environment
	tinted.ambient_light_color = tinted.ambient_light_color * depth.ambient_tint
	world_env.environment = tinted


## The arena's WorldEnvironment — a sibling under the Arena root. Searched rather
## than pathed so it survives node renames; nulls out gracefully in bare test
## scenes with no environment.
func _find_world_environment() -> WorldEnvironment:
	var parent := get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
	return null


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


## Scheduled spawns (bosses, ambushes, repeating swarms) from the WaveTable plus
## the Depth's extra_events (docs/DEPTHS.md M3). Iterates the local combined list
## so the WaveTable resource is never mutated.
func _fire_due_events() -> void:
	var table := spawner.wave_table
	if table == null:
		return
	var events := _combined_event_list(table)
	if _next_event_at.size() != events.size():
		_next_event_at.resize(events.size())
		for i: int in events.size():
			# The finale (THE REVENANT, tagged &"finale") arms earlier at a Depth
			# with a negative finale_time_shift — Depth V hunts you at 6:45.
			var at := events[i].time
			if depth != null and events[i].enemy != null \
					and events[i].enemy.tags.has(&"finale"):
				at += depth.finale_time_shift
			_next_event_at[i] = at
	for i: int in events.size():
		if elapsed < _next_event_at[i]:
			continue
		var event := events[i]
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
				# THE REVENANT'S HOUR (universal forged Aspect, docs/DEPTHS.md):
				# every boss horn restores the player fully. The finale (THE
				# REVENANT) is tagged boss too, so it hits this path as well.
				_restore_on_boss_horn()


## The run's event schedule, cached: the WaveTable's events plus the Depth's
## extra_events, in that order (Surface = just the table's). Built into a fresh
## local Array so the shared WaveTable is never touched; rebuilt only when its
## expected size drifts — for the run's lifetime, that's exactly once.
func _combined_event_list(table: WaveTable) -> Array[WaveEvent]:
	var expected := table.events.size()
	if depth != null:
		expected += depth.extra_events.size()
	if _combined_events.size() != expected:
		_combined_events = []
		_combined_events.append_array(table.events)
		if depth != null:
			_combined_events.append_array(depth.extra_events)
	return _combined_events


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


## THE REVENANT'S HOUR (universal forged Aspect, docs/DEPTHS.md): when the flag
## is owned, a boss horn restores the player fully. Called from the boss-spawn
## path (finale included). No-ops without the flag or without a live player.
func _restore_on_boss_horn() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null and player.has_ability(&"revenants_hour"):
		player.full_restore()


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
	# Attempts pay (docs/DEPTHS.md Lane 2): every boss kill on a depth run banks
	# depth.level shards on the spot, kept on death/abandon/quit — so this saves
	# immediately, same rationale as grant_meta_ability. Surface banks nothing.
	_bank_boss_shards()
	_alive_bosses.erase(boss)
	if is_instance_valid(boss):
		_last_boss_pos = boss.global_position
	if _alive_bosses.is_empty():
		_on_boss_wave_cleared()


## The last boss of a wave just died. A weapon relic takes priority: if one is
## owed, clear the remaining minions, pause spawning, and drop it where the boss
## fell (always a single relic — weapon unlocks are untouched by Depth). Once
## every weapon is owned, Aspect relics drop instead via the same arena-clear +
## spawn-pause spectacle (M2). A Depth III+ boss wave drops boss_relic_count of
## them (docs/DEPTHS.md M3), capped at what the pool can actually back, and
## spawning stays paused until the LAST one's pick resolves. If neither weapon
## nor Aspect has anything to give, nothing drops.
func _on_boss_wave_cleared() -> void:
	var ability := _next_unlock_drop(_last_boss_data)
	if ability != &"":
		_clear_for_relic()
		_spawn_relic(ability, _last_boss_pos)
		return
	# No weapon owed — offer an Aspect if the pool still has candidates.
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var available := AspectPool.available(player).size()
	if available <= 0:
		return
	_clear_for_relic()
	# Skip any relic the pool can't back so a claim never opens an empty modal.
	var wanted := depth.boss_relic_count if depth != null else 1
	var count := clampi(wanted, 1, available)
	_pending_relic_claims = count
	# Fan multiple relics laterally so they don't z-fight on the boss's spot.
	for i: int in count:
		var offset := Vector3((float(i) - float(count - 1) * 0.5) * RELIC_SPREAD, 0.0, 0.0)
		_spawn_aspect_relic(_last_boss_pos + offset, true)


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
	var relic := Pickup.make()
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
	# Deep runs are more generous with Aspects (docs/DEPTHS.md M3): the elite budget
	# reads the Depth's cap; Surface keeps the const.
	var cap := depth.aspect_elite_cap if depth != null else ASPECT_ELITE_CAP
	if _elite_kills <= cap and not AspectPool.available(player).is_empty():
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
	var relic := Pickup.make()
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
	var pickup := Pickup.make()
	var burst := Vector3(randf_range(-1.5, 1.5), randf_range(6.0, 9.0), randf_range(-1.5, 1.5))
	pickup.setup(kind, value, burst)
	if lifetime > 0.0:
		pickup.lifetime = lifetime
	scene.add_child(pickup)
	pickup.global_position = position + Vector3(0.0, 1.2, 0.0)


## An Aspect was picked from the relic modal — resume boss-paused spawning once
## the LAST owed relic has resolved (a Depth III+ boss wave drops several). Mirrors
## _on_unlock_claimed; called by AspectScreen after the pick (not on the relic
## touch), so elite relics never pause the run while they sit unclaimed. The
## AspectScreen also calls this when the pool has since gone empty (a touched relic
## with nothing to offer), so counting down here is what keeps that case from
## wedging the run paused. Stray calls with nothing pending just leave it running.
func resume_from_aspect() -> void:
	if _pending_relic_claims > 0:
		_pending_relic_claims -= 1
	if _pending_relic_claims <= 0:
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
	# The finale is a boss kill too (docs/DEPTHS.md Lane 2): bank its depth.level
	# shards immediately (the +2×level clear bonus lands separately in
	# finish_victory), so even a player who somehow dies in the victory-delay window
	# keeps the Revenant's shards.
	_bank_boss_shards()
	get_tree().create_timer(FINALE_VICTORY_DELAY, false).timeout.connect(finish_victory)


## The finale-boss-kill win (see _on_finale_boss_died): bank the run and hand
## off to the victory screen. Deferred + idempotent so it's safe to fire from
## a timer callback or mid-physics-frame.
func finish_victory() -> void:
	if not _run_active:
		return
	_run_active = false
	# Clearing a Depth pays a +2×level bonus (docs/DEPTHS.md Lane 2) on top of the
	# boss-kill income already banked. _final_stats' record_run + save_game write
	# right after, so this lands in the same save.
	if depth != null:
		MetaProgression.add_currency(&"shards", 2 * depth.level)
	GameManager.end_run.call_deferred(_final_stats({"victory": true}))


## Bank a single boss kill's shards on a depth run (docs/DEPTHS.md Lane 2):
## depth.level shards, saved immediately so they survive a death/abandon/quit in
## the seconds after the kill. Surface runs (null depth) bank nothing.
func _bank_boss_shards() -> void:
	if depth == null:
		return
	MetaProgression.add_currency(&"shards", depth.level)
	MetaProgression.save_game()


## Deep Cache (Reliquary QoL, docs/DEPTHS.md): when the node is owned, start the
## run with a magnet pickup already primed in the arena — reusing the elite-bounty
## magnet spawn path, so there is no duplicate magnet logic and collecting it later
## runs the exact same arena-wide vacuum any magnet does. Not gated on Depth: it is
## a universal QoL node, so it primes on Surface runs too.
func _prime_deep_cache() -> void:
	if MetaProgression.get_upgrade_level(&"deep_cache") <= 0:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var pos := player.global_position if player != null else Vector3.ZERO
	_spawn_utility_pickup(&"magnet", 1, EnemyBase.MAGNET_LIFETIME, pos)
