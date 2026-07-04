class_name SettingsPanel
extends Control
## Reusable options panel, embedded by both the main menu and the pause menu.
## Rows are generated in code from the Settings autoload; every change
## applies immediately, and values persist on release/close.

signal closed

@onready var rows: VBoxContainer = $Center/Panel/Margin/Box/Rows
@onready var back_button: Button = $Center/Panel/Margin/Box/BackButton


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


func _add_slider(label_text: String, min_value: float, max_value: float,
		step: float, value: float, setter: Callable, formatter: Callable) -> void:
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


func _fmt_mult(value: float) -> String:
	return "%.2f×" % value


func _fmt_degrees(value: float) -> String:
	return "%d°" % int(value)


func _fmt_percent(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))
