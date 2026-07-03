class_name DamageNumber
extends RefCounted
## Floating world-space damage popups, built entirely in code.


static func spawn(parent: Node, position: Vector3, amount: float) -> void:
	if parent == null:
		return
	var label := Label3D.new()
	label.text = str(int(round(amount)))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 42
	label.outline_size = 10
	label.pixel_size = 0.007
	label.modulate = Color(1.0, 0.9, 0.35)
	parent.add_child(label)
	label.global_position = position
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)
