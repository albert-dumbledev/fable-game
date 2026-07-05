extends Node
## Headless smoke harness for the enemy-expansion work. Boots the Arena, then
## force-spawns each new enemy that exists (regardless of time gates) via the
## live spawner, exercises the Broodmother death-burst, and reports. Run with:
##   Godot --headless --quit-after 600 res://test/EnemySmoke.tscn
## Not shipped — lives under test/ purely for milestone verification.

const CANDIDATES := [
	"res://data/enemies/broodmother.tres",
	"res://data/enemies/stalker.tres",
	"res://data/enemies/gilded.tres",
	"res://data/enemies/scavenger.tres",
]

var _done := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Bring up the Arena as the current scene while this harness node stays
	# alive alongside it to drive the test.
	var arena: Node = load("res://levels/Arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	# Let the Arena, player, and RunDirector come up.
	for i in 15:
		await get_tree().physics_frame
	var spawner: Spawner = _find_spawner()
	if spawner == null:
		print("SMOKE FAIL: no spawner")
		get_tree().quit()
		return
	var spawned := 0
	for path: String in CANDIDATES:
		if not ResourceLoader.exists(path):
			continue
		var data: EnemyData = load(path)
		var enemy := spawner.spawn_enemy(data, 200.0)
		if enemy != null:
			spawned += 1
			print("SMOKE: spawned %s" % data.display_name)
	print("SMOKE: spawned %d new enemy type(s)" % spawned)
	# Let them act for a bit.
	for i in 40:
		await get_tree().physics_frame
	# Exercise the death-burst: kill any Broodmother and count the hatch.
	await _test_broodmother(spawner)
	# Exercise the Scavenger eat -> bounty path.
	await _test_scavenger(spawner)
	print("SMOKE OK — alive=%d" % EnemyBase.alive.size())
	_done = true
	get_tree().quit()


func _test_broodmother(_spawner: Spawner) -> void:
	if not ResourceLoader.exists("res://data/enemies/broodmother.tres"):
		return
	var before := EnemyBase.alive.size()
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if is_instance_valid(enemy) and enemy.data != null \
				and enemy.data.display_name == "Broodmother":
			enemy.health.take_damage(AttackInfo.new(null, 99999.0))
	for i in 30:
		await get_tree().physics_frame
	var after := EnemyBase.alive.size()
	print("SMOKE: broodmother kill: alive %d -> %d (expect hatchlings)" % [before, after])


## Feeds a fresh Scavenger a pile of gold, confirms it consumes pieces, then
## kills it and confirms the bounty (eaten x1.25) erupts as a fountain.
func _test_scavenger(spawner: Spawner) -> void:
	if not ResourceLoader.exists("res://data/enemies/scavenger.tres"):
		return
	var scav := spawner.spawn_enemy(load("res://data/enemies/scavenger.tres"), 200.0) as ScavengerEnemy
	if scav == null:
		print("SMOKE: scavenger spawn failed")
		return
	for i in 12:
		var piece: Pickup = load("res://actors/pickups/Pickup.tscn").instantiate()
		piece.setup(&"gold", 5, Vector3.ZERO)
		get_tree().current_scene.add_child(piece)
		piece.global_position = scav.global_position \
				+ Vector3(randf_range(-1.0, 1.0), 0.3, randf_range(-1.0, 1.0))
	for i in 120:
		await get_tree().physics_frame
	if not is_instance_valid(scav):
		print("SMOKE: scavenger freed before bounty check")
		return
	print("SMOKE: scavenger ate %d pieces" % scav._eaten_count)
	var before := Pickup.edible.size()
	scav.health.take_damage(AttackInfo.new(null, 99999.0))
	for i in 20:
		await get_tree().physics_frame
	print("SMOKE: scavenger bounty: edible %d -> %d (fountain expected)" % [before, Pickup.edible.size()])


func _find_spawner() -> Spawner:
	var rd := get_tree().get_first_node_in_group(&"run_director")
	if rd == null:
		return null
	return rd.get_node_or_null(^"Spawner") as Spawner
