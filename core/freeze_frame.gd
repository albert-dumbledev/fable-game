class_name FreezeFrame
extends RefCounted
## Coalescing hit-pause: drops Engine.time_scale to near-zero for a few
## dozen milliseconds so impacts land with weight. `duration` is real-time
## seconds. Calls while a pause is active are dropped — never stacked or
## extended — so a sweep through a pack can't stutter-lock the game.

const FREEZE_SCALE := 0.05

static var _active := false


static func hit_pause(duration: float) -> void:
	if _active or duration <= 0.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_active = true
	Engine.time_scale = FREEZE_SCALE
	# ignore_time_scale so the freeze times itself out in real time, and
	# process_always so opening the pause menu mid-freeze can't strand the
	# game at 5% speed.
	tree.create_timer(duration, true, false, true).timeout.connect(_restore)


static func _restore() -> void:
	Engine.time_scale = 1.0
	_active = false
