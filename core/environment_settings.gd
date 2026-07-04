extends WorldEnvironment
## Pushes the graphics settings that live on scene nodes — glow on the
## environment, shadows on the sun — and keeps them live on Settings.changed.
## MenuBackdrop builds its environment in code and applies the same flags
## itself; keep the two in sync.

@export var sun: DirectionalLight3D


func _ready() -> void:
	Settings.changed.connect(_apply)
	_apply()


func _apply() -> void:
	if environment != null:
		environment.glow_enabled = Settings.glow_enabled
	if sun != null:
		sun.shadow_enabled = Settings.shadows_enabled
