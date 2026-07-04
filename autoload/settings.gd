extends Node
## User options, persisted to their own file so wiping a save never wipes
## preferences. Gameplay reads live multipliers from here (sensitivity,
## shake); apply() pushes the rest (window mode, bus volumes) to the engine.
##
## Loads after AudioManager so the SFX bus exists before volumes are applied.

const SETTINGS_PATH := "user://settings.json"
const DEFAULT_FOV := 75.0
## Easter egg: type this anywhere in-game to toggle the post-it shield and
## pencil sword viewmodels. Dedicated to the critic who said the shield
## "looks like a post-it note".
const CHEAT_WORD := "postit"

## Emitted after apply(); the player uses it to refresh camera FOV live.
signal changed

## Multiplier on the base look sensitivity.
var mouse_sensitivity := 1.0
var fov := DEFAULT_FOV
## Multiplier on trauma shake strength; 0 disables shake entirely.
var screen_shake := 1.0
## Accessibility: disables freeze frames, slow-mo, and dash speed lines.
var reduced_flash := false
var master_volume := 1.0
var sfx_volume := 1.0
var fullscreen := false
## Post-it/pencil viewmodel easter egg; persisted like any other setting.
var postit_mode := false

var _cheat_buffer := ""


func _ready() -> void:
	_load()
	apply()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.unicode <= 0:
		return
	_cheat_buffer += char(key.unicode).to_lower()
	if _cheat_buffer.length() > CHEAT_WORD.length():
		_cheat_buffer = _cheat_buffer.right(CHEAT_WORD.length())
	if _cheat_buffer == CHEAT_WORD:
		_cheat_buffer = ""
		postit_mode = not postit_mode
		AudioManager.play(&"level_up" if postit_mode else &"click")
		save_settings()
		changed.emit()


func apply() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
			else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	_apply_volume(0, master_volume)
	_apply_volume(AudioServer.get_bus_index("SFX"), sfx_volume)
	changed.emit()


func save_settings() -> void:
	var data: Dictionary = {
		"mouse_sensitivity": mouse_sensitivity,
		"fov": fov,
		"screen_shake": screen_shake,
		"reduced_flash": reduced_flash,
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"postit_mode": postit_mode,
	}
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open settings file for writing: %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))


func _apply_volume(bus_index: int, linear: float) -> void:
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(bus_index, linear <= 0.001)


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return
	var data: Dictionary = parsed
	mouse_sensitivity = clampf(_get_float(data, "mouse_sensitivity", 1.0), 0.1, 5.0)
	fov = clampf(_get_float(data, "fov", DEFAULT_FOV), 60.0, 110.0)
	screen_shake = clampf(_get_float(data, "screen_shake", 1.0), 0.0, 2.0)
	master_volume = clampf(_get_float(data, "master_volume", 1.0), 0.0, 1.0)
	sfx_volume = clampf(_get_float(data, "sfx_volume", 1.0), 0.0, 1.0)
	fullscreen = data.get("fullscreen", false) == true
	postit_mode = data.get("postit_mode", false) == true
	reduced_flash = data.get("reduced_flash", false) == true


func _get_float(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key, fallback)
	return float(value) if value is float or value is int else fallback
