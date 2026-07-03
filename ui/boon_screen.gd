extends CanvasLayer
## Level-up overlay: pauses the run and offers a choice of 3 boons.
## Runs with PROCESS_MODE_ALWAYS so it works while the tree is paused.

const REGISTRY_PATH := "res://data/boons/registry.tres"
const CHOICE_COUNT := 3

@onready var title: Label = $Center/Box/Title
@onready var choice_row: HBoxContainer = $Center/Box/ChoiceRow

var _registry: BoonRegistry
var _pending := 0


func _ready() -> void:
	_registry = load(REGISTRY_PATH) as BoonRegistry
	if _registry == null:
		push_error("Failed to load boon registry: %s" % REGISTRY_PATH)
	EventBus.level_up.connect(_on_level_up)


func _on_level_up(new_level: int) -> void:
	_pending += 1
	title.text = "LEVEL %d!" % new_level
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
	for child: Node in choice_row.get_children():
		child.queue_free()
	for boon: BoonData in _roll(CHOICE_COUNT):
		var button := Button.new()
		button.custom_minimum_size = Vector2(230, 140)
		button.text = "%s\n\n%s" % [boon.display_name, boon.description]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_pick.bind(boon))
		choice_row.add_child(button)


## Weighted sample without replacement.
func _roll(count: int) -> Array[BoonData]:
	var pool: Array[BoonData] = _registry.boons.duplicate()
	var result: Array[BoonData] = []
	while result.size() < count and not pool.is_empty():
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
		result.append(pool[picked])
		pool.remove_at(picked)
	return result


func _on_pick(boon: BoonData) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.apply_boon(boon)
	_pending -= 1
	if _pending > 0:
		_show_choices()
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
