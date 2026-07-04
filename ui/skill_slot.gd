class_name SkillSlot
extends VBoxContainer
## One skill square on the HUD: key cap, cooldown darken-overlay that
## drains top-to-bottom as the skill recovers, and a seconds readout.
## Built entirely in code — call setup() right after instancing.

const SLOT_SIZE := Vector2(56.0, 56.0)

var skill_id: StringName

var _overlay: ColorRect
var _cooldown_label: Label
var _charges_label: Label
var _was_cooling := false
var _ping_tween: Tween


func setup(id: StringName, key_text: String, display_name: String) -> void:
	skill_id = id
	alignment = BoxContainer.ALIGNMENT_CENTER

	var panel := Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	add_child(panel)

	var key_label := Label.new()
	key_label.text = key_text
	key_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override(&"font_size", 18)
	panel.add_child(key_label)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	panel.add_child(_overlay)

	_cooldown_label = Label.new()
	_cooldown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_cooldown_label.add_theme_font_size_override(&"font_size", 13)
	_cooldown_label.visible = false
	panel.add_child(_cooldown_label)

	# Charge count (top-right), shown only for multi-charge skills.
	_charges_label = Label.new()
	_charges_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_charges_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_charges_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_charges_label.add_theme_font_size_override(&"font_size", 13)
	_charges_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.4))
	_charges_label.visible = false
	panel.add_child(_charges_label)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override(&"font_size", 12)
	name_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	add_child(name_label)


func update_cooldown(remaining: float, max_value: float) -> void:
	var fraction := 0.0
	if max_value > 0.0:
		fraction = clampf(remaining / max_value, 0.0, 1.0)
	var cooling := fraction > 0.0
	if _was_cooling and not cooling:
		_ready_ping()
	_was_cooling = cooling
	_overlay.visible = cooling
	_overlay.anchor_top = 0.0
	_overlay.anchor_bottom = fraction
	_cooldown_label.visible = remaining > 0.05
	_cooldown_label.text = "%.1f" % maxf(remaining, 0.0)


## Flash + pop the frame a cooldown completes, so "ready again" registers
## without looking down. The guard meter is exempt — it cycles constantly
## while blocking and would blink nonstop.
func _ready_ping() -> void:
	if skill_id == &"block":
		return
	pivot_offset = size * 0.5
	scale = Vector2(1.18, 1.18)
	modulate = Color(1.8, 1.7, 1.3)
	if _ping_tween != null:
		_ping_tween.kill()
	_ping_tween = create_tween()
	_ping_tween.set_parallel(true)
	_ping_tween.tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ping_tween.tween_property(self, "modulate", Color.WHITE, 0.3)
	AudioManager.play(&"click")


func update_charges(current: int, maximum: int) -> void:
	_charges_label.visible = maximum > 1
	_charges_label.text = str(current)
