class_name AspectScreen
extends CanvasLayer
## Aspect pick overlay (Phase 9 M2): when the player walks onto an Aspect relic,
## pause the run and offer a pick-1-of-2 of build-warping Aspects. Modeled on the
## claim screen's pause + deferred-show handling (the relic claim fires
## mid-physics), but renders boon cards like the level-up screen.
##
## Scarcer than the level-up screen's 3-of-N: no reroll, no skip, no continue —
## picking a card is the only action, and that scarcity is the point.
## Runs with PROCESS_MODE_ALWAYS so it works while the tree is paused.

## Above-unique tier signalled by a distinct gold-teal card color.
const ASPECT_COLOR := Color(0.35, 0.95, 0.85)
const CHOICE_COUNT := 2
const CARD_SIZE := Vector2(260, 170)

@onready var title: Label = $Center/Box/Title
@onready var card_row: HBoxContainer = $Center/Box/CardRow


func _ready() -> void:
	EventBus.aspect_relic_claimed.connect(_on_relic_claimed)


func _on_relic_claimed() -> void:
	# aspect_relic_claimed fires mid-physics (pickup collection); defer the pause
	# so we don't pause the tree inside that callback stack (mirrors claim_screen).
	_show.call_deferred()


## Aspects offered per relic: the base 2, plus one for Wider Fate (Reliquary QoL,
## docs/DEPTHS.md Lane 2) once owned — a leveled read, universal so no gating.
func _choice_count() -> int:
	return CHOICE_COUNT + (1 if MetaProgression.get_upgrade_level(&"wider_fate") > 0 else 0)


func _show() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var aspects := AspectPool.roll(player, _choice_count())
	# Defensive: RunDirector only spawns the relic when the pool is non-empty, so
	# this shouldn't happen — but if it does, resume without pausing rather than
	# stranding the player in an empty modal.
	if aspects.is_empty():
		_resume(player)
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	title.text = "CHOOSE AN ASPECT"
	_populate(aspects, player)
	AudioManager.play(&"boon")


func _populate(aspects: Array[BoonData], player: Player) -> void:
	for child: Node in card_row.get_children():
		child.queue_free()
	for aspect: BoonData in aspects:
		var button := Button.new()
		button.custom_minimum_size = CARD_SIZE
		button.text = "[ASPECT]\n%s\n\n%s" % [aspect.display_name, aspect.describe()]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_color_override(&"font_color", ASPECT_COLOR)
		button.add_theme_color_override(&"font_hover_color", ASPECT_COLOR.lightened(0.3))
		button.pressed.connect(_on_pick.bind(aspect, player))
		card_row.add_child(button)


func _on_pick(aspect: BoonData, player: Player) -> void:
	AudioManager.play(&"boon")
	if player != null:
		player.apply_boon(aspect)
	EventBus.wave_announcement.emit("ASPECT CLAIMED — %s" % aspect.display_name.to_upper())
	EventBus.aspect_picked.emit({"id": aspect.id, "name": aspect.display_name})
	_resume(player)


## Hide, unpause, recapture the mouse, and tell RunDirector the pick is done so
## it can resume boss-paused spawning. Keeping resume on the *pick* (not the
## relic touch) is what lets elite relics sit unclaimed without pausing the run.
func _resume(_player: Player) -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var director := get_tree().get_first_node_in_group(&"run_director") as RunDirector
	if director != null:
		director.resume_from_aspect()
