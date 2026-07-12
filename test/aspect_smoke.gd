extends Node
## Headless smoke harness for the Aspect Drops feature (Phase 9, M1-M2 chain plus
## the M6 claim path). Boots the Arena, force-spawns an elite, kills it, and
## asserts the elite -> elite_died -> RunDirector -> Aspect relic chain fired;
## then directly exercises a claim (roll -> apply_boon -> flag granted). Run with:
##   Godot --headless --quit-after 60 res://test/AspectSmoke.tscn
## Not shipped — lives under test/ purely for milestone verification.

## A basic melee mob eligible for the elite roll (no boss/finale/broodling tag).
const ELITE_ENEMY := "res://data/enemies/chaser.tres"
## Expected Aspect registry size. Was 12 through Phase 9; the Depths M5 forge lane
## (docs/DEPTHS.md Lane 2) added 3 forged Aspects, bringing it to 15; Forge wave 2
## adds the remaining 11 (4 universal + 7 loadout-themed), bringing it to 26.
## Asserted deliberately so a dropped registry entry fails the smoke quietly.
const EXPECTED_ASPECT_COUNT := 26

var _failed := false


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
		_fail("no spawner")
		_finish()
		return
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		_fail("no player")
		_finish()
		return

	await _test_elite_relic(spawner)
	await _test_claim(player)

	# The forged-Aspect additions must actually land in the registry.
	var count := AspectPool.ASPECT_REGISTRY.boons.size()
	if count != EXPECTED_ASPECT_COUNT:
		_fail("expected %d aspects registered, got %d" % [EXPECTED_ASPECT_COUNT, count])

	if _failed:
		print("SMOKE FAIL")
	else:
		print("SMOKE OK — %d aspects registered" % count)
	_finish()


## Force-spawns an elite, confirms the flag, kills it, then asserts an &"aspect"
## relic appeared — proving elite_died -> RunDirector -> relic fires (the registry
## has aspects, so the first elite of the run drops a relic rather than a bounty).
func _test_elite_relic(spawner: Spawner) -> void:
	if not ResourceLoader.exists(ELITE_ENEMY):
		_fail("elite enemy data missing: %s" % ELITE_ENEMY)
		return
	var data: EnemyData = load(ELITE_ENEMY)
	var elite := spawner.spawn_enemy(data, 300.0, true)
	if elite == null:
		_fail("elite spawn returned null")
		return
	if not elite.is_elite:
		_fail("spawned enemy is not flagged elite")
		return
	print("SMOKE: elite spawned (%s), is_elite=%s" % [data.display_name, elite.is_elite])
	elite.health.take_damage(AttackInfo.new(null, 99999.0))
	for i in 20:
		await get_tree().physics_frame
	if _find_aspect_relic() != null:
		print("SMOKE: aspect relic present after elite death")
	else:
		_fail("no aspect relic spawned after elite death")


## Directly exercises the claim: roll two Aspects, apply one, confirm its flag
## landed on the player (has_ability doubles as the taken-this-run tracker).
func _test_claim(player: Player) -> void:
	var picks := AspectPool.roll(player, 2)
	if picks.is_empty():
		_fail("AspectPool.roll returned no candidates")
		return
	print("SMOKE: rolled %d aspect candidate(s)" % picks.size())
	var pick := picks[0]
	player.apply_boon(pick)
	if player.has_ability(pick.grants_ability):
		print("SMOKE: claimed '%s' — flag '%s' granted" % [pick.display_name, pick.grants_ability])
	else:
		_fail("claim did not grant flag '%s'" % pick.grants_ability)


func _find_aspect_relic() -> Pickup:
	for node: Pickup in get_tree().get_nodes_in_group(&"pickups"):
		if is_instance_valid(node) and node.kind == &"aspect":
			return node
	return null


func _find_spawner() -> Spawner:
	var rd := get_tree().get_first_node_in_group(&"run_director")
	if rd == null:
		return null
	return rd.get_node_or_null(^"Spawner") as Spawner


func _fail(reason: String) -> void:
	_failed = true
	print("SMOKE: FAIL — %s" % reason)


func _finish() -> void:
	get_tree().quit()
