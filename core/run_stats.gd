class_name RunStats
extends Node
## Per-run recap accumulator — the "real RunStats class" PLAN.md §3.5 promised.
## Created in code by RunDirector as a child node (dies with the run scene, so
## EventBus connections clean themselves up). Listens only to EventBus; nothing
## in the combat path knows it exists. to_dict() rides GameManager.end_run()
## as stats["recap"] and feeds the death-screen recap panel.
## Full design: docs/RUN_RECAP.md.

## Attribution id for self-inflicted damage (Blood Pact pays spells in HP).
const SELF_ID := &"self"
const SELF_NAME := "Blood Pact"
const UNKNOWN_NAME := "Unknown"

## enemy id -> {name: String, count: int}
var kills_by_enemy: Dictionary[StringName, Dictionary] = {}
## Bosses felled, in kill order: [{name: String, t: float}]
var bosses: Array[Dictionary] = []
## enemy id -> {name: String, dmg: float, hits: int}
var damage_taken: Dictionary[StringName, Dictionary] = {}
## Boons picked, in pick order: [{id, name, rarity, color, mult}]
var boons: Array[Dictionary] = []
## Aspects claimed, in claim order: [{id, name}]
var aspects: Array[Dictionary] = []

var _last_hit_id: StringName = &""
var _last_hit_name := ""
var _killer_id: StringName = &""
var _killer_name := ""


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.player_died.connect(_on_player_died)
	EventBus.boon_picked.connect(_on_boon_picked)
	EventBus.aspect_picked.connect(_on_aspect_picked)


func to_dict() -> Dictionary:
	var dmg_total := 0.0
	var hits_total := 0
	for id: StringName in damage_taken:
		dmg_total += float(damage_taken[id]["dmg"])
		hits_total += int(damage_taken[id]["hits"])
	return {
		"kills_by_enemy": kills_by_enemy.duplicate(true),
		"bosses": bosses.duplicate(true),
		"damage_taken": damage_taken.duplicate(true),
		"damage_taken_total": dmg_total,
		"hits_taken": hits_total,
		"killer_id": _killer_id,
		"killer_name": _killer_name,
		"boons": boons.duplicate(true),
		"aspects": aspects.duplicate(true),
	}


func _on_enemy_killed(enemy_data: Resource, _position: Vector3) -> void:
	var data := enemy_data as EnemyData
	if data == null:
		return
	var id := _enemy_id(data)
	var name := data.display_name if data.display_name != "" else String(id)
	if kills_by_enemy.has(id):
		kills_by_enemy[id]["count"] = int(kills_by_enemy[id]["count"]) + 1
	else:
		kills_by_enemy[id] = {"name": name, "count": 1}
	if data.tags.has(&"boss"):
		bosses.append({"name": name, "t": _elapsed()})


func _on_player_hit(info: AttackInfo) -> void:
	var id := SELF_ID
	var name := SELF_NAME
	# A delayed hit (projectile, flame patch) can land after its source enemy
	# was freed, and a freed object can't be cast or type-checked — fall through
	# to the &"unknown" bucket instead. typeof() is the freed-vs-null test:
	# a freed object compares == null, but its Variant is still TYPE_OBJECT.
	var source: Node3D = info.source if is_instance_valid(info.source) else null
	var enemy := source as EnemyBase
	if enemy != null and enemy.data != null:
		id = _enemy_id(enemy.data)
		name = enemy.data.display_name if enemy.data.display_name != "" else String(id)
	elif typeof(info.source) == TYPE_OBJECT and source is not Player:
		id = &"unknown"
		name = UNKNOWN_NAME
	if damage_taken.has(id):
		damage_taken[id]["dmg"] = float(damage_taken[id]["dmg"]) + info.damage
		damage_taken[id]["hits"] = int(damage_taken[id]["hits"]) + 1
	else:
		damage_taken[id] = {"name": name, "dmg": info.damage, "hits": 1}
	_last_hit_id = id
	_last_hit_name = name


func _on_player_died() -> void:
	_killer_id = _last_hit_id
	_killer_name = _last_hit_name


func _on_boon_picked(ctx: Dictionary) -> void:
	boons.append(ctx.duplicate())


func _on_aspect_picked(ctx: Dictionary) -> void:
	aspects.append(ctx.duplicate())


## Stable content id from the resource file name (chaser, caster, revenant, …) —
## EnemyData has no id field; this is the rule GAMEPLAY_TELEMETRY.md verified.
func _enemy_id(data: EnemyData) -> StringName:
	if data.resource_path == "":
		return &"unknown"
	return StringName(data.resource_path.get_file().get_basename())


func _elapsed() -> float:
	var director := get_parent() as RunDirector
	return director.elapsed if director != null else 0.0
