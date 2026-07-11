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

var _ok := true
var _save_existed := false
var _save_contents := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_snapshot_save()

	_test_selection_clamping()
	_test_save_round_trip()
	await _test_depth_run()
	await _test_surface_control()

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


## Instantiate a fresh Arena, front it, and free the previous scene (a spent
## death screen, never this harness node). Mirrors recap_smoke's boot.
func _boot_arena() -> Node:
	var prev := get_tree().current_scene
	var arena: Node = load("res://levels/Arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	if prev != null and prev != self and is_instance_valid(prev):
		prev.queue_free()
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
