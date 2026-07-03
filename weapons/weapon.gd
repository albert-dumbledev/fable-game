class_name Weapon
extends Node3D
## Base class for anything the player attacks with. Spells later implement
## the same interface (a spell is a weapon with a cast time and a payload).

## Where the viewmodel tucks while stowed (both hands busy casting).
const STOW_OFFSET := Vector3(0.0, -0.55, 0.3)

@export var weapon_data: WeaponData

var stats: StatBlock
## Who swings this weapon (the AttackInfo source). Explicit because weapons
## are instanced into the mount at runtime, so scene `owner` is never set.
var wielder: Node3D
var is_blocking := false
var is_stowed := false

var _cooldown := 0.0
var _secondary_cooldown := 0.0
var _stow_tween: Tween


func setup(stat_block: StatBlock, wielder_node: Node3D) -> void:
	stats = stat_block
	wielder = wielder_node


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_secondary_cooldown = maxf(0.0, _secondary_cooldown - delta)


func try_attack() -> void:
	if is_stowed or _cooldown > 0.0 or stats == null or weapon_data == null:
		return
	var duration := weapon_data.swing_time / maxf(0.1, stats.get_stat(Stats.ATTACK_SPEED))
	_cooldown = duration
	AudioManager.play(_swing_sound())
	_do_attack(duration)


## RMB ability for weapons that can't block (the shield owns RMB otherwise).
func try_secondary() -> void:
	if is_stowed or _secondary_cooldown > 0.0 or stats == null or weapon_data == null:
		return
	_do_secondary()


func get_secondary_cooldown() -> float:
	return _secondary_cooldown


func set_blocking(value: bool) -> void:
	if value and (is_stowed or weapon_data == null or not weapon_data.can_block):
		return
	if is_blocking == value:
		return
	is_blocking = value
	_on_blocking_changed()


## Tucks the whole viewmodel down out of frame (casting uses both hands).
func set_stowed(value: bool) -> void:
	if is_stowed == value:
		return
	is_stowed = value
	if is_stowed:
		set_blocking(false)
	if _stow_tween != null:
		_stow_tween.kill()
	_stow_tween = create_tween()
	_stow_tween.tween_property(
		self, "position", STOW_OFFSET if is_stowed else Vector3.ZERO, 0.18
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Override: perform the attack. `duration` is the attack-speed-scaled swing time.
func _do_attack(_duration: float) -> void:
	pass


## Override: the sound try_attack fires (swings differ per weapon).
func _swing_sound() -> StringName:
	return &"swing"


## Override: the RMB secondary. Set `_secondary_cooldown` when it fires.
func _do_secondary() -> void:
	pass


## Override: react to block starting/stopping.
func _on_blocking_changed() -> void:
	pass


## Override: feedback when this weapon successfully blocks a hit.
func notify_block_success(_perfect: bool = false) -> void:
	pass
