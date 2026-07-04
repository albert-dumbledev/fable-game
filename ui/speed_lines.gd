class_name SpeedLines
extends ColorRect
## Full-screen dash streak overlay. Spikes the shader's intensity when the
## player dashes, holds through the blink, then fades out over the tail so
## the burst reads longer than the 0.12s dash itself.

const PEAK := 0.85
const FADE_IN := 0.04
const HOLD := 0.08
const FADE_OUT := 0.25

var _tween: Tween


func _ready() -> void:
	# Assign the uniform once: a ShaderMaterial reports null for parameters
	# that were never set (the default lives in the shader), and tweening a
	# null-valued property returns a null tweener.
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter(&"intensity", 0.0)
	EventBus.player_dashed.connect(_on_player_dashed)


func _on_player_dashed() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(
		shader_material, "shader_parameter/intensity", PEAK, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_property(
		shader_material, "shader_parameter/intensity", 0.0, FADE_OUT) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
