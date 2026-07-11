extends Node
## Headless smoke harness for the Phase 8C loadout-mobility rework. For each
## loadout it boots a fresh Arena, grants the mobility unlock, fires the Shift
## move directly, and asserts the state transitions: a charge is spent, the
## duelist blinks and re-arms, the earthshaker leaps and lands (slam fires), and
## the arcanist hovers then ends on its timer and lands. Not shipped — lives
## under test/ purely for milestone verification. Run with:
##   Godot --headless --quit-after 3000 res://test/MobilitySmoke.tscn

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("SMOKE OK: %s" % label)
	else:
		_fails += 1
		print("SMOKE FAIL: %s" % label)


func _run() -> void:
	# Pretend both boss-drop weapons are unlocked so each loadout can be mounted.
	MetaProgression.unlocked_abilities = [&"weapon_warhammer", &"weapon_staff"]
	await _test_loadout(&"sword_and_shield", &"dash", "Duelist")
	await _test_loadout(&"warhammer", &"hammer_leap", "Earthshaker")
	await _test_loadout(&"battle_staff", &"levitate", "Arcanist")
	print("SMOKE DONE — failures=%d" % _fails)
	get_tree().quit(_fails)


func _test_loadout(weapon_id: StringName, expect_mobility: StringName, label: String) -> void:
	MetaProgression.selected_weapon = weapon_id
	var arena: Node = load("res://levels/Arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	# Let the player spawn and settle onto the floor.
	for i in 20:
		await get_tree().physics_frame
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		_check(false, "%s: player spawned" % label)
		arena.queue_free()
		await get_tree().physics_frame
		return
	_check(player.weapon != null and player.weapon.mobility_id() == expect_mobility,
			"%s: mobility_id == %s" % [label, expect_mobility])
	player.grant_ability(&"dash")
	var before: int = player._dash_charges
	player._begin_mobility(-player.global_transform.basis.z)
	_check(player._dash_charges == before - 1, "%s: charge spent" % label)
	match expect_mobility:
		&"dash":
			await _assert_dash(player, label)
		&"hammer_leap":
			await _assert_leap(player, label)
		&"levitate":
			await _assert_levitate(player, label)
	arena.queue_free()
	await get_tree().physics_frame


## Blink is intangible and brief; it should end within a few frames and leave a
## cooldown ticking behind it.
func _assert_dash(player: Player, label: String) -> void:
	_check(player._dash_time > 0.0, "%s: blink active" % label)
	for i in 20:
		await get_tree().physics_frame
	_check(player._dash_time <= 0.0, "%s: blink ended" % label)
	_check(player._mobility_cooldown > 0.0, "%s: cooldown armed" % label)


## The leap is now a three-phase skyfall (ASCEND -> AIM -> CRASH -> NONE).
## No input is driven here, so the AIM window's real-time 1s deadline is what
## eventually fires the crash — this exercises the auto-fire path. Slow-mo
## during AIM sets Engine.time_scale=0.5 (physics_frame still ticks, so the
## await loop doesn't hang), but the deadline is measured via ticks_msec so
## it still elapses in real time regardless of the scale.
func _assert_leap(player: Player, label: String) -> void:
	_check(player._leap_phase == Player.LeapPhase.ASCEND, "%s: ascending" % label)
	_check(player._mobility_cooldown > 0.0, "%s: cooldown armed at launch" % label)
	var reached_aim := false
	for i in 60:
		await get_tree().physics_frame
		if player._leap_phase == Player.LeapPhase.AIM:
			reached_aim = true
			break
	_check(reached_aim, "%s: reached aim hover" % label)
	var crashed := false
	for i in 100:
		await get_tree().physics_frame
		if player._leap_phase == Player.LeapPhase.CRASH:
			crashed = true
			break
	_check(crashed, "%s: aim auto-fired into crash" % label)
	var landed := false
	for i in 60:
		await get_tree().physics_frame
		if player._leap_phase == Player.LeapPhase.NONE:
			landed = true
			break
	_check(landed, "%s: landed (slam fired)" % label)


## Levitate holds a hover, ends on its 2.5s timer into a descent, then lands and
## arms its cooldown.
func _assert_levitate(player: Player, label: String) -> void:
	_check(player._levitating, "%s: hovering" % label)
	var ended := false
	for i in 240:
		await get_tree().physics_frame
		if not player._levitating:
			ended = true
			break
	_check(ended, "%s: hover ended on timer" % label)
	var landed := false
	for i in 240:
		await get_tree().physics_frame
		if not player._levitate_descending and player._mobility_cooldown > 0.0:
			landed = true
			break
	_check(landed, "%s: landed + cooldown armed" % label)
