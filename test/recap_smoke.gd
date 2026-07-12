extends Node
## Headless smoke harness for the Run Recap feature (docs/RUN_RECAP.md). Boots
## the Arena, spawns a chaser, routes attributed damage to the player, kills
## the chaser, emits a synthetic boon pick, then kills the player and asserts
## GameManager.last_run_stats.recap + MetaProgression.records landed correctly.
## Run with:
##   Godot --headless --path . res://test/RecapSmoke.tscn --quit-after 2000
## Not shipped — lives under test/ purely for milestone verification.

const SAVE_PATH := "user://save.json"

var _done := false
var _save_existed := false
var _save_contents := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_snapshot_save()

	var arena: Node = load("res://levels/Arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	for i in 15:
		await get_tree().physics_frame

	var spawner: Spawner = _find_spawner()
	if spawner == null:
		print("SMOKE FAIL: no spawner")
		_restore_save()
		get_tree().quit()
		return

	var chaser_data: EnemyData = load("res://data/enemies/chaser.tres")
	var chaser := spawner.spawn_enemy(chaser_data, 0.0) as EnemyBase
	var ok := true
	if chaser == null:
		print("SMOKE FAIL: chaser spawn")
		ok = false
	else:
		print("SMOKE OK: chaser spawn")

	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		print("SMOKE FAIL: no player")
		_restore_save()
		get_tree().quit()
		return
	# Keep the player alive through the ambient wave spawns leading up to the
	# scripted death at the end of the test.
	player.health.set_max_health(10000.0, true)

	if chaser != null:
		player.health.take_damage(AttackInfo.new(chaser, 7.0))
	for i in 5:
		await get_tree().physics_frame

	if chaser != null:
		chaser.health.take_damage(AttackInfo.new(null, 99999.0))
	for i in 10:
		await get_tree().physics_frame

	EventBus.boon_picked.emit({
		"id": &"test_boon",
		"name": "Test Boon",
		"rarity": "RARE",
		"color": Color(0.4, 0.65, 1.0),
		"mult": 1.4,
	})

	var runs_before := int(MetaProgression.records.get("runs", 0))

	var chaser2 := spawner.spawn_enemy(chaser_data, 0.0) as EnemyBase
	if chaser2 == null:
		print("SMOKE FAIL: chaser2 spawn")
		ok = false
	else:
		print("SMOKE OK: chaser2 spawn")
		player.health.take_damage(AttackInfo.new(chaser2, 99999.0))
	for i in 30:
		await get_tree().physics_frame

	var stats: Dictionary = GameManager.last_run_stats
	if not stats.has("recap"):
		print("SMOKE FAIL: last_run_stats has recap")
		ok = false
	else:
		print("SMOKE OK: last_run_stats has recap")
	var recap: Dictionary = stats.get("recap", {})

	var kills_by_enemy: Dictionary = recap.get("kills_by_enemy", {})
	if kills_by_enemy.has(&"chaser") and int(kills_by_enemy[&"chaser"]["count"]) >= 1:
		print("SMOKE OK: kills_by_enemy has chaser >= 1")
	else:
		print("SMOKE FAIL: kills_by_enemy has chaser >= 1")
		ok = false

	var damage_taken: Dictionary = recap.get("damage_taken", {})
	if damage_taken.has(&"chaser") and float(damage_taken[&"chaser"]["dmg"]) >= 7.0 \
			and int(damage_taken[&"chaser"]["hits"]) >= 1:
		print("SMOKE OK: damage_taken chaser dmg >= 7.0 and hits >= 1")
	else:
		print("SMOKE FAIL: damage_taken chaser dmg >= 7.0 and hits >= 1")
		ok = false

	var expected_killer_name: String = chaser_data.display_name
	if recap.get("killer_id", &"") == &"chaser" \
			and recap.get("killer_name", "") == expected_killer_name:
		print("SMOKE OK: killer_id/killer_name == chaser/%s" % expected_killer_name)
	else:
		print("SMOKE FAIL: killer_id/killer_name == chaser/%s" % expected_killer_name)
		ok = false

	var boons: Array = recap.get("boons", [])
	if boons.size() == 1 and boons[0].get("id", &"") == &"test_boon":
		print("SMOKE OK: boons has 1 entry with id test_boon")
	else:
		print("SMOKE FAIL: boons has 1 entry with id test_boon")
		ok = false

	if stats.get("new_records") is Array:
		print("SMOKE OK: new_records is an Array")
	else:
		print("SMOKE FAIL: new_records is an Array")
		ok = false

	if int(MetaProgression.records.get("runs", 0)) == runs_before + 1:
		print("SMOKE OK: MetaProgression.records[runs] incremented")
	else:
		print("SMOKE FAIL: MetaProgression.records[runs] incremented")
		ok = false

	_restore_save()
	print("SMOKE OK — recap" if ok else "SMOKE FAIL — recap")
	_done = true
	get_tree().quit()


func _find_spawner() -> Spawner:
	var rd := get_tree().get_first_node_in_group(&"run_director")
	if rd == null:
		return null
	return rd.get_node_or_null(^"Spawner") as Spawner


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
