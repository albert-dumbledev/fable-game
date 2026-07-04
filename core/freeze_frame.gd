class_name FreezeFrame
extends RefCounted
## Owns Engine.time_scale for juice: hit_pause (near-freeze for tens of
## milliseconds) and slow_motion (celebration slow-mo, e.g. boss deaths).
## All durations are real-time seconds. The two coordinate instead of
## fighting: a hit pause landing during slow-mo freezes, then restores to
## the slow-mo scale — never to full speed early.

const FREEZE_SCALE := 0.05

static var _pause_active := false
## What "normal speed" currently means: 1.0, or the slow-mo scale while
## one is running.
static var _slow_scale := 1.0
## Latest slow_motion call wins; stale timers check their token and bail.
static var _slow_token := 0


static func hit_pause(duration: float) -> void:
	if _pause_active or duration <= 0.0:
		return
	var tree := _tree()
	if tree == null:
		return
	_pause_active = true
	Engine.time_scale = FREEZE_SCALE
	# ignore_time_scale so the freeze times itself out in real time, and
	# process_always so opening the pause menu mid-freeze can't strand the
	# game at 5% speed.
	tree.create_timer(duration, true, false, true).timeout.connect(_end_pause)


static func slow_motion(time_scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var tree := _tree()
	if tree == null:
		return
	_slow_token += 1
	_slow_scale = time_scale
	if not _pause_active:
		Engine.time_scale = time_scale
	tree.create_timer(duration, true, false, true).timeout.connect(
			_end_slow.bind(_slow_token))


static func _end_pause() -> void:
	_pause_active = false
	Engine.time_scale = _slow_scale


static func _end_slow(token: int) -> void:
	if token != _slow_token:
		return
	_slow_scale = 1.0
	if not _pause_active:
		Engine.time_scale = 1.0


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
