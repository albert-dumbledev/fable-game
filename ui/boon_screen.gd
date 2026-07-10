extends CanvasLayer
## Level-up overlay: pauses the run and offers a choice of 3 boons, each
## with a rolled rarity that scales its power. Skipping pays gold;
## rerolling costs gold (doubling per use each run). Unique boons appear
## at most once per run and never scale.
## Runs with PROCESS_MODE_ALWAYS so it works while the tree is paused.

const REGISTRY_PATH := "res://data/boons/registry.tres"
const CHOICE_COUNT := 3
const BASE_REROLL_COST := 10
const SKIP_GOLD_BASE := 15
const SKIP_GOLD_PER_LEVEL := 5
const UNIQUE_COLOR := Color(1.0, 0.5, 0.15)

## Rolled per offer slot; mult scales the boon's modifier values.
const RARITIES: Array[Dictionary] = [
	{"tag": "COMMON", "chance": 0.58, "mult": 1.0, "color": Color(0.85, 0.85, 0.85)},
	{"tag": "RARE", "chance": 0.27, "mult": 1.4, "color": Color(0.4, 0.65, 1.0)},
	{"tag": "EPIC", "chance": 0.13, "mult": 1.9, "color": Color(0.8, 0.45, 1.0)},
	{"tag": "LEGENDARY", "chance": 0.02, "mult": 3.5, "color": Color(1.0, 0.78, 0.2)},
]


class Offer:
	extends RefCounted
	var boon: BoonData
	var mult := 1.0
	var tag := "COMMON"
	var color := Color(0.85, 0.85, 0.85)


@onready var title: Label = $Center/Box/Title
@onready var gold_label: Label = $Center/Box/GoldLabel
@onready var choice_row: HBoxContainer = $Center/Box/ChoiceRow
@onready var reroll_button: Button = $Center/Box/ActionRow/RerollButton
@onready var skip_button: Button = $Center/Box/ActionRow/SkipButton

var _registry: BoonRegistry
var _pending := 0
var _current_level := 0
var _reroll_cost := BASE_REROLL_COST
var _taken_uniques: Array[StringName] = []


func _ready() -> void:
	_registry = load(REGISTRY_PATH) as BoonRegistry
	if _registry == null:
		push_error("Failed to load boon registry: %s" % REGISTRY_PATH)
	reroll_button.pressed.connect(_on_reroll)
	skip_button.pressed.connect(_on_skip)
	EventBus.level_up.connect(_on_level_up)


func _on_level_up(new_level: int) -> void:
	_pending += 1
	_current_level = new_level
	if not visible:
		# Deferred: level_up fires mid-physics (kill -> xp); don't pause
		# the tree inside that callback stack.
		_show_choices.call_deferred()


func _show_choices() -> void:
	if _registry == null or _registry.boons.is_empty():
		_pending = 0
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	title.text = "LEVEL %d!" % _current_level
	_populate()


func _populate() -> void:
	for child: Node in choice_row.get_children():
		child.queue_free()
	for offer: Offer in _roll_offers(CHOICE_COUNT):
		var button := Button.new()
		button.custom_minimum_size = Vector2(230, 150)
		button.text = "[%s]\n%s\n\n%s" % [
			offer.tag, offer.boon.display_name, offer.boon.describe(offer.mult)]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_color_override(&"font_color", offer.color)
		button.add_theme_color_override(&"font_hover_color", offer.color.lightened(0.3))
		button.pressed.connect(_on_pick.bind(offer))
		choice_row.add_child(button)
	_refresh_actions()


func _refresh_actions() -> void:
	var gold := MetaProgression.get_currency(&"gold")
	gold_label.text = "Gold: %d" % gold
	reroll_button.text = "Reroll (-%d gold)" % _reroll_cost
	reroll_button.disabled = gold < _reroll_cost
	skip_button.text = "Skip (+%d gold)" % _skip_gold()


func _skip_gold() -> int:
	return SKIP_GOLD_BASE + SKIP_GOLD_PER_LEVEL * _current_level


func _roll_offers(count: int) -> Array[Offer]:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var director := get_tree().get_first_node_in_group(&"run_director")
	var elapsed := director.elapsed if director != null else 0.0
	var pool: Array[BoonData] = []
	for boon: BoonData in _registry.boons:
		if _is_offerable(boon, player):
			pool.append(boon)
	var offers: Array[Offer] = []
	while offers.size() < count and not pool.is_empty():
		var total := 0.0
		for boon: BoonData in pool:
			total += boon.weight
		var roll := randf() * total
		var picked := pool.size() - 1
		for i: int in pool.size():
			roll -= pool[i].weight
			if roll <= 0.0:
				picked = i
				break
		var offer := Offer.new()
		offer.boon = pool[picked]
		pool.remove_at(picked)
		if offer.boon.unique:
			offer.tag = "UNIQUE"
			offer.color = UNIQUE_COLOR
		else:
			var ri := _roll_rarity_index(elapsed)
			var rarity: Dictionary = RARITIES[ri]
			offer.tag = rarity["tag"]
			offer.color = rarity["color"]
			if offer.boon.rarity_mults.is_empty():
				offer.mult = rarity["mult"]
			else:
				offer.mult = offer.boon.rarity_mults[clampi(ri, 0, offer.boon.rarity_mults.size() - 1)]
		offers.append(offer)
	return offers


## Loadout/build gating: weapon-specific boons only appear with their weapon
## mounted, spell boons only once the spell is owned.
func _is_offerable(boon: BoonData, player: Player) -> bool:
	if boon.unique and boon.id in _taken_uniques:
		return false
	if player == null:
		return true
	if boon.requires_weapon != &"" and (player.weapon == null
			or player.weapon.weapon_data == null
			or player.weapon.weapon_data.id != boon.requires_weapon):
		return false
	if not boon.requires_any_ability.is_empty():
		var owns_one := false
		for ability: StringName in boon.requires_any_ability:
			if player.has_ability(ability):
				owns_one = true
				break
		if not owns_one:
			return false
	return true


## The rolled rarity's index into RARITIES, weighted by chance. Weight
## shifts from COMMON toward RARE/EPIC as the run goes on (t=0 -> t=1 over
## a 7:30 run) so late level-ups stay exciting as enemies harden, without
## touching the fixed LEGENDARY jackpot rate.
const RARITY_CHANCE_LATE: Array[float] = [0.40, 0.36, 0.22, 0.02]
const RARITY_RAMP_DURATION := 450.0


func _roll_rarity_index(elapsed: float) -> int:
	var t := clampf(elapsed / RARITY_RAMP_DURATION, 0.0, 1.0)
	var roll := randf()
	for i: int in RARITIES.size():
		var base_chance: float = RARITIES[i]["chance"]
		var chance := lerpf(base_chance, RARITY_CHANCE_LATE[i], t)
		if roll < chance:
			return i
		roll -= chance
	return 0


func _on_pick(offer: Offer) -> void:
	AudioManager.play(&"boon")
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.apply_boon(offer.boon, offer.mult)
	if offer.boon.unique:
		_taken_uniques.append(offer.boon.id)
	_advance()


func _on_reroll() -> void:
	if not MetaProgression.try_spend(&"gold", _reroll_cost):
		return
	AudioManager.play(&"click")
	_reroll_cost *= 2
	_populate()


func _on_skip() -> void:
	# Routed through pickup_collected so RunDirector counts it as
	# gold earned this run, same as a dropped coin.
	EventBus.pickup_collected.emit(&"gold", _skip_gold())
	_advance()


func _advance() -> void:
	_pending -= 1
	if _pending > 0:
		title.text = "LEVEL %d!" % _current_level
		_populate()
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
