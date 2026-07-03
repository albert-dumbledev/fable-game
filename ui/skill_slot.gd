class_name SkillSlot
extends VBoxContainer
## One skill square on the HUD: key cap, cooldown darken-overlay that
## drains top-to-bottom as the skill recovers, and a seconds readout.
## Built entirely in code — call setup() right after instancing.

const SLOT_SIZE := Vector2(56.0, 56.0)

var skill_id: StringName

var _overlay: ColorRect
var _cooldown_label: Label


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
	_overlay.visible = fraction > 0.0
	_overlay.anchor_top = 0.0
	_overlay.anchor_bottom = fraction
	_cooldown_label.visible = remaining > 0.05
	_cooldown_label.text = "%.1f" % maxf(remaining, 0.0)
