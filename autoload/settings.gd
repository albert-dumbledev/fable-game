extends Node
## User options, persisted to their own file so wiping a save never wipes
## preferences. Gameplay reads live multipliers from here (sensitivity,
## shake); apply() pushes the rest (window mode, bus volumes) to the engine.
##
## Loads after AudioManager so the SFX bus exists before volumes are applied.

const SETTINGS_PATH := "user://settings.json"
const DEFAULT_FOV := 75.0
## Quality presets: selecting one writes these values into the individual
## graphics settings below. Hand-tuning any of them flips the preset to
## &"custom". The web build starts on medium the first time it runs.
const GRAPHICS_PRESETS: Dictionary = {
	&"high": {
		render_scale = 1.0, shadows_enabled = true, glow_enabled = true,
		torch_lights = true, vfx_density = 1.0,
	},
	&"medium": {
		render_scale = 0.85, shadows_enabled = true, glow_enabled = true,
		torch_lights = false, vfx_density = 0.7,
	},
	&"low": {
		render_scale = 0.7, shadows_enabled = false, glow_enabled = false,
		torch_lights = false, vfx_density = 0.4,
	},
}
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
## Which quality preset the graphics values came from; bookkeeping only —
## systems read the individual settings below, never this.
var graphics_preset := &"high"
## 3D resolution scale (UI stays native). The biggest lever on web GPUs.
var render_scale := 1.0
var shadows_enabled := true
var glow_enabled := true
## Arena torch omni lights; the emissive flames stay lit either way.
var torch_lights := true
## Multiplier on cosmetic particle counts (shards, trails, embers).
var vfx_density := 1.0
var damage_numbers := true

var _cheat_buffer := ""


func _ready() -> void:
	# First run on web (no settings file yet): start from the medium preset —
	# full quality is the desktop default but a common source of web lag.
	if OS.has_feature("web") and not FileAccess.file_exists(SETTINGS_PATH):
		apply_graphics_preset(&"medium")
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
	var root := get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = render_scale
	changed.emit()


## Copies a preset's values into the individual graphics settings.
## No-op for &"custom" (or anything unknown) — custom IS the current values.
func apply_graphics_preset(preset_name: StringName) -> void:
	if not GRAPHICS_PRESETS.has(preset_name):
		return
	var preset: Dictionary = GRAPHICS_PRESETS[preset_name]
	graphics_preset = preset_name
	render_scale = preset["render_scale"]
	shadows_enabled = preset["shadows_enabled"]
	glow_enabled = preset["glow_enabled"]
	torch_lights = preset["torch_lights"]
	vfx_density = preset["vfx_density"]


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
		"graphics_preset": String(graphics_preset),
		"render_scale": render_scale,
		"shadows_enabled": shadows_enabled,
		"glow_enabled": glow_enabled,
		"torch_lights": torch_lights,
		"vfx_density": vfx_density,
		"damage_numbers": damage_numbers,
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
	render_scale = clampf(_get_float(data, "render_scale", 1.0), 0.5, 1.0)
	vfx_density = clampf(_get_float(data, "vfx_density", 1.0), 0.25, 1.0)
	shadows_enabled = data.get("shadows_enabled", true) == true
	glow_enabled = data.get("glow_enabled", true) == true
	torch_lights = data.get("torch_lights", true) == true
	damage_numbers = data.get("damage_numbers", true) == true
	var preset_raw: Variant = data.get("graphics_preset", "high")
	graphics_preset = StringName(preset_raw) if preset_raw is String else &"high"
	if graphics_preset != &"custom" and not GRAPHICS_PRESETS.has(graphics_preset):
		graphics_preset = &"high"


func _get_float(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key, fallback)
	return float(value) if value is float or value is int else fallback
