class_name DamageNumber
extends RefCounted
## Floating world-space damage popups, built entirely in code.
## Bigger hits print bigger; kill blows go gold and largest of all.


static func spawn(parent: Node, position: Vector3, amount: float,
		kill_blow: bool = false) -> void:
	if parent == null:
		return
	var label := Label3D.new()
	label.text = str(int(round(amount)))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	var font_size := clampi(30 + int(amount * 0.55), 32, 64)
	if kill_blow:
		font_size = mini(font_size + 10, 72)
	label.font_size = font_size
	label.outline_size = int(font_size * 0.24)
	label.pixel_size = 0.007
	label.modulate = Color(1.0, 0.82, 0.25) if kill_blow else Color(0.98, 0.95, 0.82)
	parent.add_child(label)
	label.global_position = position
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)
