extends Node
## Headless smoke harness for the Depths feature M1+M2 (docs/DEPTHS.md).
## Exercises the MetaProgression selection/validation math, then boots the
## Arena twice — once at Depth I (asserting the spawner folds in the Depth
## mults, the HUD depth chip shows, and a faked finale kill records the clear
## and produces the right death-screen picker/records-line/banner) and once at
## Surface (asserting today's numbers, and the hidden HUD chip, are untouched).
## Run with:
##   Godot --headless --path . res://test/DepthSmoke.tscn --quit-after 900
## Not shipped — lives under test/ purely for milestone verification.

const SAVE_PATH := "user://save.json"
const KNOWN_ELAPSED := 100.0
## The arena's authored ambient light color (levels/Arena.tscn) — the Surface
## control must render exactly this, and a Depth run must nudge away from it.
const AUTHORED_AMBIENT := Color(0.31, 0.29, 0.4)

var _ok := true
var _save_existed := false
var _save_contents := ""
## The Depth-V run's tinted ambient, captured so the Surface control can prove it
## differs (docs/DEPTHS.md M3 ambient tint).
var _depth_v_ambient := Color.WHITE


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_snapshot_save()

	_test_selection_clamping()
	_test_save_round_trip()
	await _test_depth_run()
	await _test_depth_v_run()
	await _test_surface_control()
	await _test_status_lane()

	_restore_save()
	print("SMOKE OK — depth" if _ok else "SMOKE FAIL — depth")
	get_tree().quit()


## Pure MetaProgression math: the picker opens one Depth past the deepest clear,
## clamps an over-reaching selection down, and shuts entirely without a victory.
func _test_selection_clamping() -> void:
	MetaProgression.records = {"victories": 1, "best_depth": 1}
	MetaProgression.selected_depth = 5
	var data := MetaProgression.get_selected_depth_data()
	_check(data != null and data.level == 2,
			"selected_depth 5 clamps to level 2 (best_depth 1)")

	MetaProgression.records = {"victories": 0, "best_depth": 1}
	_check(MetaProgression.get_selected_depth_data() == null,
			"no victory -> Surface (null)")


## The raw selection persists through a save/load cycle independent of clamping.
func _test_save_round_trip() -> void:
	MetaProgression.selected_depth = 2
	MetaProgression.save_game()
	MetaProgression.selected_depth = 99
	MetaProgression.load_game()
	_check(MetaProgression.selected_depth == 2, "selected_depth round-trips save/load")


## Boot the Arena at Depth I: the director resolves the Depth, the spawner scales
## a spawn by it, and a faked finale kill banks the clear into records.
func _test_depth_run() -> void:
	MetaProgression.records = {"victories": 1}
	MetaProgression.selected_depth = 1

	var arena := await _boot_arena()
	if arena == null:
		return
	var rd := get_tree().get_first_node_in_group(&"run_director") as RunDirector
	var spawner := _find_spawner()
	if rd == null or spawner == null:
		_check(false, "depth run: found run_director + spawner")
		return

	_check(rd.depth != null and rd.depth.level == 1, "run_director resolved Depth I")
	_check(spawner.depth == rd.depth, "spawner received the same Depth instance")

	# M2: the HUD depth chip (docs/DEPTHS.md) exists and reads visible on a
	# depth run — the announcement is emitted deferred, but the chip itself is
	# set synchronously in HUD._ready, well before this point.
	var hud := arena.get_node_or_null(^"HUD")
	var chip := hud.find_child("DepthChip", true, false) if hud != null else null
	_check(chip != null and (chip as CanvasItem).visible,
			"HUD depth chip exists and is visible on a Depth I run")

	var chaser_data: EnemyData = load("res://data/enemies/chaser.tres")
	var wt := spawner.wave_table
	var enemy := spawner.spawn_enemy(chaser_data, KNOWN_ELAPSED)
	if enemy == null:
		_check(false, "depth run: chaser spawned")
		return
	var expected_hp := chaser_data.max_health * wt.hp_mult_at(KNOWN_ELAPSED) * 1.3
	_check(is_equal_approx(enemy.health.max_health, expected_hp),
			"depth enemy HP carries the x1.3 factor (%.2f == %.2f)"
			% [enemy.health.max_health, expected_hp])
	var expected_reward := wt.reward_mult_at(KNOWN_ELAPSED) * 1.25
	_check(is_equal_approx(enemy._reward_mult, expected_reward),
			"depth enemy reward carries the x1.25 factor (%.4f == %.4f)"
			% [enemy._reward_mult, expected_reward])

	# Fake the finale kill: seed the clock and take the victory handoff directly.
	rd.elapsed = 300.0
	var loadout := String(MetaProgression.selected_weapon)
	rd.finish_victory()
	for i in 10:
		await get_tree().physics_frame

	_check(int(MetaProgression.records.get("best_depth", 0)) == 1,
			"records.best_depth == 1 after the clear")
	var wins: Dictionary = MetaProgression.records.get("depth_wins", {})
	var entry: Dictionary = wins.get("1", {})
	_check(entry.has("fastest") and float(entry["fastest"]) > 0.0,
			"depth_wins['1'] has a fastest time")
	_check((entry.get("loadouts", []) as Array).has(loadout),
			"depth_wins['1'] recorded the loadout %s" % loadout)
	var new_records: Array = GameManager.last_run_stats.get("new_records", [])
	_check(new_records.has("best_depth"), "new_records contains 'best_depth'")
	_check(int(GameManager.last_run_stats.get("depth", -1)) == 1,
			"victory stats.depth == 1")

	# M2: finish_victory's end_run() call already swapped current_scene to the
	# real DeathScreen (deferred, but well within the waits above) — assert its
	# picker/records-line/banner against this exact state (victories 1,
	# best_depth 1 -> max_selectable_depth 2).
	_test_death_screen_depth_clear()


## The Depth picker shows exactly SURFACE/I/II, the records line carries
## "Deepest", and the depth-clear banner reads the exact house-voice line.
func _test_death_screen_depth_clear() -> void:
	var screen := get_tree().current_scene
	if screen == null:
		_check(false, "death screen: current_scene exists after the clear")
		return

	var picker := screen.get_node_or_null(^"Scroll/Center/Box/DepthPicker")
	var button_texts: Array[String] = []
	if picker != null:
		for child: Node in picker.get_children():
			if child is Button:
				button_texts.append((child as Button).text)
	_check(button_texts == ["SURFACE", "I", "II"],
			"death screen depth picker shows exactly SURFACE, I, II (got %s)" % [button_texts])

	var has_deepest := false
	for text: String in _collect_label_texts(screen):
		if text.find("Deepest") != -1:
			has_deepest = true
			break
	_check(has_deepest, "death screen records line text contains 'Deepest'")

	var banner := screen.get_node_or_null(^"Scroll/Center/Box/VictoryBanner")
	var banner_text: String = (banner as Label).text if banner != null else ""
	_check(banner_text == "DEPTH I CLEARED — DEPTH II UNLOCKED",
			"death screen depth-clear banner text (got '%s')" % banner_text)


## Recursively collects every Label's text under `node` — used to find the
## records line without depending on its exact container structure.
func _collect_label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node is Label:
		texts.append((node as Label).text)
	for child: Node in node.get_children():
		texts.append_array(_collect_label_texts(child))
	return texts


## M3 (docs/DEPTHS.md): boot a Depth-V run with best_depth faked to 4 so V is
## selectable, then assert the identity twists structurally — combined events +
## finale shift, the windup static, elite overrides, the rarity helper, the
## pinned Legendary once-flag, the double boss relics, and the ambient tint.
func _test_depth_v_run() -> void:
	MetaProgression.records = {"victories": 1, "best_depth": 4}
	MetaProgression.selected_depth = 5

	var arena := await _boot_arena()
	if arena == null:
		return
	var rd := get_tree().get_first_node_in_group(&"run_director") as RunDirector
	var spawner := _find_spawner()
	if rd == null or spawner == null:
		_check(false, "depth V run: found run_director + spawner")
		return
	_check(rd.depth != null and rd.depth.level == 5, "run_director resolved Depth V")

	# --- Combined event array + finale_time_shift ---
	var wt := spawner.wave_table
	var events := rd._combined_event_list(wt)
	_check(events.size() == wt.events.size() + rd.depth.extra_events.size(),
			"combined events == table.events + extra_events (%d == %d + %d)"
			% [events.size(), wt.events.size(), rd.depth.extra_events.size()])
	var finale_idx := -1
	for i: int in events.size():
		if events[i].enemy != null and events[i].enemy.tags.has(&"finale"):
			finale_idx = i
			break
	if finale_idx == -1 or finale_idx >= rd._next_event_at.size():
		_check(false, "combined events include the finale event with an initialized clock")
	else:
		var expected_clock := events[finale_idx].time - 45.0
		_check(is_equal_approx(rd._next_event_at[finale_idx], expected_clock),
				"finale next-fire clock is authored - 45 (%.1f == %.1f)"
				% [rd._next_event_at[finale_idx], expected_clock])

	# --- Windup static ---
	_check(is_equal_approx(EnemyBase.depth_time_scale, 0.85),
			"EnemyBase.depth_time_scale == 0.85 during the Depth V run (%.3f)"
			% EnemyBase.depth_time_scale)

	# --- Elite overrides (structural handles the spawner exposes) ---
	_check(is_equal_approx(spawner._elite_min_elapsed(), 180.0),
			"spawner effective elite min-elapsed == 180 on Depth V")
	_check(spawner._elite_max_alive() == 2,
			"spawner effective elite max-alive == 2 on Depth V")

	# --- Rarity clock helper (pure; the roll itself is random) ---
	var boon_screen: BoonScreen = load("res://ui/BoonScreen.tscn").instantiate() as BoonScreen
	arena.add_child(boon_screen)
	_check(is_equal_approx(boon_screen._effective_rarity_elapsed(KNOWN_ELAPSED, rd.depth),
			KNOWN_ELAPSED + 300.0), "rarity elapsed adds +300 at Depth V")
	_check(is_equal_approx(boon_screen._effective_rarity_elapsed(KNOWN_ELAPSED, null),
			KNOWN_ELAPSED), "rarity elapsed adds +0 on Surface (null depth)")

	# --- Pinned Legendary (once per run, first screen past 3:00) ---
	rd.elapsed = 200.0
	rd.depth_legendary_pinned = false
	seed(90210)  # deterministic so the two non-pinned slots roll no stray Legendary
	var offers: Array[BoonScreen.Offer] = boon_screen._roll_offers(3)
	var legendary := 0
	for offer: BoonScreen.Offer in offers:
		if offer.tag == "LEGENDARY":
			legendary += 1
	_check(legendary == 1, "exactly one offer pinned Legendary on Depth V past 3:00 (got %d)"
			% legendary)
	_check(rd.depth_legendary_pinned, "director depth_legendary_pinned flag consumed")
	# A second screen must not force another pin — the flag stays consumed (any
	# Legendary now would be a natural roll, so we assert the flag, not tag counts).
	boon_screen._roll_offers(3)
	_check(rd.depth_legendary_pinned,
			"depth_legendary_pinned stays consumed after a second boon screen")
	seed(randi())  # restore a fresh sequence for the remaining spawns
	boon_screen.queue_free()

	# --- Double boss relics (Depth III+) ---
	var player := get_tree().get_first_node_in_group(&"player") as Player
	# A boss with no unlock_drops forces the Aspect path (weapon relics are single).
	rd._last_boss_data = EnemyData.new()
	rd._last_boss_pos = Vector3(0.0, 1.0, 0.0)
	var available := AspectPool.available(player).size()
	_check(available >= 2, "aspect pool backs >= 2 relics for the double-drop test (%d)"
			% available)
	var before := _count_aspect_pickups()
	rd._on_boss_wave_cleared()
	_check(_count_aspect_pickups() - before == 2,
			"Depth V boss wave spawned 2 aspect relics (got %d)"
			% (_count_aspect_pickups() - before))
	_check(rd._spawning_paused, "spawning paused after the double boss relic drop")
	rd.resume_from_aspect()
	_check(rd._spawning_paused, "spawning still paused after only the first relic pick")
	rd.resume_from_aspect()
	_check(not rd._spawning_paused, "spawning resumes after the second (last) relic pick")

	# --- Ambient tint ---
	var world_env := rd._find_world_environment()
	if world_env == null or world_env.environment == null:
		_check(false, "depth V run: found the arena WorldEnvironment")
	else:
		_depth_v_ambient = world_env.environment.ambient_light_color
		var expected_tint := AUTHORED_AMBIENT * rd.depth.ambient_tint
		_check(_depth_v_ambient.is_equal_approx(expected_tint),
				"depth V ambient is the authored color times the Depth tint")
		_check(not _depth_v_ambient.is_equal_approx(AUTHORED_AMBIENT),
				"depth V ambient differs from the authored value")

	# Quiesce this run so its dying frames don't fire an event storm at elapsed 200
	# once the Surface boot frees it.
	rd._run_active = false


## Every Aspect relic currently on the arena floor — the double-drop count check.
func _count_aspect_pickups() -> int:
	var n := 0
	for node: Node in get_tree().get_nodes_in_group(&"pickups"):
		if node is Pickup and (node as Pickup).kind == &"aspect":
			n += 1
	return n


## Surface control: no Depth selected -> the director's depth is null and a spawn
## reads the WaveTable numbers exactly, with stats.depth == 0.
func _test_surface_control() -> void:
	MetaProgression.selected_depth = 0

	var arena := await _boot_arena()
	if arena == null:
		return
	var rd := get_tree().get_first_node_in_group(&"run_director") as RunDirector
	var spawner := _find_spawner()
	if rd == null or spawner == null:
		_check(false, "surface run: found run_director + spawner")
		return

	_check(rd.depth == null, "surface run: run_director.depth is null")
	_check(spawner.depth == null, "surface run: spawner.depth is null")

	# M3: the windup static was reset by this Surface run's _ready — a prior Depth
	# run must never leave 0.85 bleeding into Surface telegraphs.
	_check(is_equal_approx(EnemyBase.depth_time_scale, 1.0),
			"EnemyBase.depth_time_scale reset to 1.0 on the Surface run (%.3f)"
			% EnemyBase.depth_time_scale)

	# M3: the elite gate reads today's defaults on Surface (null depth).
	_check(is_equal_approx(spawner._elite_min_elapsed(), 240.0),
			"surface elite min-elapsed is the default 240")
	_check(spawner._elite_max_alive() == 1, "surface elite max-alive is 1 (today's gate)")

	# M3: the ambient tint never touches Surface — the environment renders exactly
	# the authored .tres color, and that differs from the Depth V run's tint.
	var world_env := rd._find_world_environment()
	if world_env == null or world_env.environment == null:
		_check(false, "surface run: found the arena WorldEnvironment")
	else:
		var s_ambient := world_env.environment.ambient_light_color
		_check(s_ambient.is_equal_approx(AUTHORED_AMBIENT),
				"surface ambient equals the authored .tres value")
		_check(not s_ambient.is_equal_approx(_depth_v_ambient),
				"surface ambient differs from the Depth V tint")

	# M2: the HUD depth chip node still exists (it's created unconditionally in
	# HUD._ready) but stays hidden on a Surface run.
	var hud := arena.get_node_or_null(^"HUD")
	var chip := hud.find_child("DepthChip", true, false) if hud != null else null
	_check(chip != null and not (chip as CanvasItem).visible,
			"HUD depth chip exists but is hidden on a Surface run")

	var chaser_data: EnemyData = load("res://data/enemies/chaser.tres")
	var wt := spawner.wave_table
	var enemy := spawner.spawn_enemy(chaser_data, KNOWN_ELAPSED)
	if enemy == null:
		_check(false, "surface run: chaser spawned")
		return
	var expected_hp := chaser_data.max_health * wt.hp_mult_at(KNOWN_ELAPSED)
	_check(is_equal_approx(enemy.health.max_health, expected_hp),
			"surface enemy HP is unscaled (%.2f == %.2f)"
			% [enemy.health.max_health, expected_hp])
	_check(is_equal_approx(enemy._reward_mult, wt.reward_mult_at(KNOWN_ELAPSED)),
			"surface enemy reward is unscaled")

	var stats := rd._final_stats({})
	_check(int(stats.get("depth", -1)) == 0, "surface stats.depth == 0")


## M4 (docs/DEPTHS.md Lane 3): badge grid, per-Depth fastest NEW BEST,
## the title line, and weapon trim. Fabricates a richer save state directly
## rather than driving a second full arena run — the death screen only reads
## MetaProgression.records and GameManager.last_run_stats, so mounting those
## and instancing a fresh DeathScreen is the cleaner seam. Scenario: the
## current loadout (sword_and_shield) just freshly cleared Depth III, and a
## second unlocked loadout (warhammer) already has an older Depth I clear —
## two loadouts x uneven depths exercises the grid's rows/cleared-cell math
## and the title's "OF THE THIRD" in one fabricated snapshot.
func _test_status_lane() -> void:
	MetaProgression.unlocked_abilities = [&"weapon_warhammer"]
	MetaProgression.selected_weapon = &"sword_and_shield"
	MetaProgression.records = {
		"victories": 1,
		"best_depth": 3,
		"depth_wins": {
			"3": {"fastest": 400.0, "loadouts": ["sword_and_shield"]},
			"1": {"fastest": 200.0, "loadouts": ["warhammer"]},
		},
	}
	GameManager.last_run_stats = {
		"victory": true,
		"time": 400.0,
		"depth": 3,
		"new_records": ["best_depth", "depth_fastest_3"],
	}

	var screen := await _boot_death_screen()
	if screen == null:
		return

	# --- Badge grid: rows = unlocked loadouts, cols = authored max Depth ---
	var grid := screen.get_node_or_null(^"Scroll/Center/Box/DepthGrid")
	_check(grid != null and grid.visible, "status lane: badge grid exists and is visible")
	if grid != null:
		var max_level := MetaProgression.depth_registry.max_level() \
				if MetaProgression.depth_registry != null else 0
		var unlocked := MetaProgression.get_unlocked_weapons().size()
		_check(grid.get_child_count() == unlocked,
				"status lane: badge grid has %d rows == unlocked loadouts (%d)"
				% [grid.get_child_count(), unlocked])
		var total_cells := 0
		for row: Node in grid.get_children():
			total_cells += row.get_child_count() - 1  # minus the row's loadout label
		_check(total_cells == unlocked * max_level,
				"status lane: badge grid has %d cells == %d loadouts x %d Depths"
				% [total_cells, unlocked, max_level])

		_check(_cell_cleared(grid, &"sword_and_shield", 3),
				"status lane: sword_and_shield's Depth III cell reads cleared")
		_check(not _cell_cleared(grid, &"sword_and_shield", 2),
				"status lane: sword_and_shield's Depth II cell reads uncleared")
		_check(_cell_cleared(grid, &"warhammer", 1),
				"status lane: warhammer's Depth I cell reads cleared")
		_check(not _cell_cleared(grid, &"warhammer", 3),
				"status lane: warhammer's Depth III cell reads uncleared")

	# --- Title line: "DUELIST OF THE THIRD" from the same deepest-clear lookup ---
	var banner := screen.get_node_or_null(^"Scroll/Center/Box/LoadoutBanner") as Label
	var banner_text := banner.text if banner != null else ""
	_check(banner_text.find("OF THE THIRD") != -1,
			"status lane: loadout banner title reads 'OF THE THIRD' (got '%s')" % banner_text)

	# --- NEW BEST label mapping: depth_fastest_3 -> "FASTEST — DEPTH III" ---
	var found_label := false
	for text: String in _collect_label_texts(screen):
		if text.find("FASTEST") != -1 and text.find("DEPTH III") != -1:
			found_label = true
			break
	_check(found_label, "status lane: records line carries the FASTEST — DEPTH III NEW BEST label")

	_test_weapon_trim()


## Whether the grid's cell for `loadout`/`level` reads cleared, via the
## `cleared` meta _make_grid_cell stamps on every cell (structural handle so
## this doesn't have to depend on cell layout/order).
func _cell_cleared(grid: Node, loadout: StringName, level: int) -> bool:
	var cell := grid.find_child("Cell_%s_%d" % [loadout, level], true, false)
	if cell == null:
		_check(false, "status lane: cell Cell_%s_%d exists" % [loadout, level])
		return false
	return bool(cell.get_meta(&"cleared", false))


## Weapon trim (docs/DEPTHS.md Lane 3): mounts SwordAndShield directly the way
## Player._mount_weapon does (weapon_data then setup()), off the status-lane
## records fabricated above — sword_and_shield's Depth III clear should light
## the trim in Depth III's theme_color. Then strips that loadout's win from
## depth_wins and remounts fresh (trim reads records at mount) to prove the
## trim goes hidden at deepest clear 0.
func _test_weapon_trim() -> void:
	var packed: PackedScene = load("res://weapons/SwordAndShield.tscn")
	var data: WeaponData = load("res://data/weapons/sword.tres")

	var weapon := packed.instantiate() as Weapon
	weapon.weapon_data = data
	weapon.setup(StatBlock.new(), null)
	var trim := weapon.find_child("DepthTrim", true, false) as MeshInstance3D
	_check(trim != null and trim.visible,
			"weapon trim: DepthTrim visible after mounting at deepest clear 3")
	if trim != null:
		var mat := trim.get_active_material(0) as StandardMaterial3D
		var expected := MetaProgression.depth_registry.get_depth(3).theme_color
		_check(mat != null and mat.emission.is_equal_approx(expected),
				"weapon trim: emission matches Depth III theme_color (%s == %s)"
				% [mat.emission if mat != null else "null", expected])
	weapon.free()

	# Strip sword_and_shield's Depth III win, keep warhammer's Depth I intact.
	var wins: Dictionary = MetaProgression.records.get("depth_wins", {})
	var entry: Dictionary = wins.get("3", {})
	var loadouts: Array = entry.get("loadouts", [])
	loadouts.erase("sword_and_shield")
	entry["loadouts"] = loadouts
	wins["3"] = entry
	MetaProgression.records["depth_wins"] = wins

	var weapon2 := packed.instantiate() as Weapon
	weapon2.weapon_data = data
	weapon2.setup(StatBlock.new(), null)
	var trim2 := weapon2.find_child("DepthTrim", true, false) as MeshInstance3D
	_check(trim2 != null and not trim2.visible,
			"weapon trim: hidden once records no longer credit this loadout with a clear")
	weapon2.free()


## Instantiate a fresh DeathScreen directly (not via a run's victory/death
## handoff), front it, and free the previous scene — same free-before-ready
## rule as _boot_arena, since the death screen's _ready() also does group
## lookups (none here, but keeping the two boots symmetric avoids surprises).
func _boot_death_screen() -> Node:
	var prev := get_tree().current_scene
	if prev != null and prev != self and is_instance_valid(prev):
		prev.queue_free()
		for i in 2:
			await get_tree().physics_frame
	var screen: Node = load("res://ui/DeathScreen.tscn").instantiate()
	get_tree().root.add_child(screen)
	get_tree().current_scene = screen
	for i in 5:
		await get_tree().physics_frame
	return screen


## Instantiate a fresh Arena, front it, and free the previous scene (a spent
## death screen or arena, never this harness node). The previous scene must be
## fully OUT of the tree before the new one readies — the real game never has
## two run directors alive, and the HUD's group lookups would find the stale
## one first. Mirrors recap_smoke's boot otherwise.
func _boot_arena() -> Node:
	var prev := get_tree().current_scene
	if prev != null and prev != self and is_instance_valid(prev):
		prev.queue_free()
		for i in 2:
			await get_tree().physics_frame
	var arena: Node = load("res://levels/Arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	for i in 15:
		await get_tree().physics_frame
	return arena


func _find_spawner() -> Spawner:
	var rd := get_tree().get_first_node_in_group(&"run_director")
	if rd == null:
		return null
	return rd.get_node_or_null(^"Spawner") as Spawner


func _check(condition: bool, label: String) -> void:
	if condition:
		print("SMOKE OK: %s" % label)
	else:
		print("SMOKE FAIL: %s" % label)
		_ok = false


## user://save.json gets overwritten by the real end-run path; snapshot it
## before the run and put it back once every assertion has run.
func _snapshot_save() -> void:
	_save_existed = FileAccess.file_exists(SAVE_PATH)
	if _save_existed:
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file != null:
			_save_contents = file.get_as_text()


func _restore_save() -> void:
	if _save_existed:
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_save_contents)
	else:
		DirAccess.open("user://").remove("save.json")
