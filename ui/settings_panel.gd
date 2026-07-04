class_name SettingsPanel
extends Control
## Reusable options panel, embedded by both the main menu and the pause menu.
## Rows are generated in code from the Settings autoload; every change
## applies immediately, and values persist on release/close.

signal closed

## Dropdown order; &"custom" is display-only (selecting it changes nothing).
const PRESET_KEYS: Array[StringName] = [&"high", &"medium", &"low", &"custom"]

@onready var rows: VBoxContainer = $Center/Panel/Margin/Box/Scroll/Rows
@onready var back_button: Button = $Center/Panel/Margin/Box/BackButton

var _preset_option: OptionButton
var _scale_slider: HSlider
var _vfx_slider: HSlider
var _shadows_check: CheckButton
var _glow_check: CheckButton
var _torch_check: CheckButton
## True while a preset is being written into the controls, so their change
## signals don't bounce the preset back to "custom".
var _syncing := false


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_add_slider("Mouse sensitivity", 0.2, 3.0, 0.05,
			Settings.mouse_sensitivity, _set_sensitivity, _fmt_mult)
	_add_slider("Field of view", 60.0, 110.0, 1.0,
			Settings.fov, _set_fov, _fmt_degrees)
	_add_slider("Screen shake", 0.0, 2.0, 0.1,
			Settings.screen_shake, _set_shake, _fmt_percent)
	_add_slider("Master volume", 0.0, 1.0, 0.05,
			Settings.master_volume, _set_master, _fmt_percent)
	_add_slider("SFX volume", 0.0, 1.0, 0.05,
			Settings.sfx_volume, _set_sfx, _fmt_percent)
	_add_graphics_section()
	var check := CheckButton.new()
	check.text = "Fullscreen"
	check.button_pressed = Settings.fullscreen
	check.toggled.connect(_on_fullscreen_toggled)
	rows.add_child(check)
	var flash_check := CheckButton.new()
	flash_check.text = "Reduced flash (no freeze frames / slow-mo)"
	flash_check.button_pressed = Settings.reduced_flash
	flash_check.toggled.connect(_on_reduced_flash_toggled)
	rows.add_child(flash_check)


func _add_graphics_section() -> void:
	rows.add_child(HSeparator.new())
	var header := Label.new()
	header.text = "Graphics"
	rows.add_child(header)
	_add_preset_row()
	_scale_slider = _add_slider("Render scale", 0.5, 1.0, 0.05,
			Settings.render_scale, _set_render_scale, _fmt_percent)
	_vfx_slider = _add_slider("Effect density", 0.25, 1.0, 0.05,
			Settings.vfx_density, _set_vfx_density, _fmt_percent)
	_shadows_check = _add_graphics_check("Shadows",
			Settings.shadows_enabled, &"shadows_enabled")
	_glow_check = _add_graphics_check("Glow / bloom",
			Settings.glow_enabled, &"glow_enabled")
	_torch_check = _add_graphics_check("Torch lights",
			Settings.torch_lights, &"torch_lights")
	var numbers_check := CheckButton.new()
	numbers_check.text = "Damage numbers"
	numbers_check.button_pressed = Settings.damage_numbers
	numbers_check.toggled.connect(_on_damage_numbers_toggled)
	rows.add_child(numbers_check)


func _add_preset_row() -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Quality preset"
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	_preset_option = OptionButton.new()
	for key: StringName in PRESET_KEYS:
		_preset_option.add_item(String(key).capitalize())
	_preset_option.select(maxi(0, PRESET_KEYS.find(Settings.graphics_preset)))
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_option.item_selected.connect(_on_preset_selected)
	row.add_child(_preset_option)
	rows.add_child(row)


func _add_graphics_check(text: String, pressed: bool,
		property: StringName) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = pressed
	check.toggled.connect(_on_graphics_check_toggled.bind(property))
	rows.add_child(check)
	return check


func _on_preset_selected(index: int) -> void:
	var key := PRESET_KEYS[index]
	if key != &"custom":
		Settings.apply_graphics_preset(key)
		Settings.apply()
		_refresh_graphics_controls()
	Settings.save_settings()
	AudioManager.play(&"click")


## Writes the current Settings values back into the graphics controls after
## a preset was applied. Sliders fire their change signals (harmless: the
## setters re-store the same values); _syncing keeps them from flipping the
## preset to custom.
func _refresh_graphics_controls() -> void:
	_syncing = true
	_scale_slider.value = Settings.render_scale
	_vfx_slider.value = Settings.vfx_density
	_shadows_check.set_pressed_no_signal(Settings.shadows_enabled)
	_glow_check.set_pressed_no_signal(Settings.glow_enabled)
	_torch_check.set_pressed_no_signal(Settings.torch_lights)
	_syncing = false


func _mark_custom() -> void:
	if _syncing:
		return
	Settings.graphics_preset = &"custom"
	if _preset_option != null:
		_preset_option.select(PRESET_KEYS.find(&"custom"))


func _on_graphics_check_toggled(pressed: bool, property: StringName) -> void:
	Settings.set(property, pressed)
	_mark_custom()
	Settings.apply()
	Settings.save_settings()
	AudioManager.play(&"click")


func _on_damage_numbers_toggled(pressed: bool) -> void:
	Settings.damage_numbers = pressed
	Settings.save_settings()
	AudioManager.play(&"click")


func _add_slider(label_text: String, min_value: float, max_value: float,
		step: float, value: float, setter: Callable, formatter: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = String(formatter.call(value))
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(_on_slider_changed.bind(setter, value_label, formatter))
	slider.drag_ended.connect(_on_slider_released)
	rows.add_child(row)
	return slider


func _on_slider_changed(value: float, setter: Callable, value_label: Label,
		formatter: Callable) -> void:
	setter.call(value)
	value_label.text = String(formatter.call(value))
	Settings.apply()


func _on_slider_released(_value_changed: bool) -> void:
	Settings.save_settings()
	AudioManager.play(&"click")


func _on_fullscreen_toggled(pressed: bool) -> void:
	Settings.fullscreen = pressed
	Settings.apply()
	Settings.save_settings()
	AudioManager.play(&"click")


func _on_reduced_flash_toggled(pressed: bool) -> void:
	Settings.reduced_flash = pressed
	Settings.save_settings()
	AudioManager.play(&"click")


func _on_back() -> void:
	Settings.save_settings()
	AudioManager.play(&"click")
	visible = false
	closed.emit()


func _set_sensitivity(value: float) -> void:
	Settings.mouse_sensitivity = value


func _set_fov(value: float) -> void:
	Settings.fov = value


func _set_shake(value: float) -> void:
	Settings.screen_shake = value


func _set_master(value: float) -> void:
	Settings.master_volume = value


func _set_sfx(value: float) -> void:
	Settings.sfx_volume = value


func _set_render_scale(value: float) -> void:
	Settings.render_scale = value
	_mark_custom()


func _set_vfx_density(value: float) -> void:
	Settings.vfx_density = value
	_mark_custom()


func _fmt_mult(value: float) -> String:
	return "%.2f×" % value


func _fmt_degrees(value: float) -> String:
	return "%d°" % int(value)


func _fmt_percent(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))
