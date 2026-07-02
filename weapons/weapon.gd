class_name Weapon
extends Node3D
## Base class for anything the player attacks with. Spells later implement
## the same interface (a spell is a weapon with a cast time and a payload).

@export var weapon_data: WeaponData

var stats: StatBlock
var is_blocking := false

var _cooldown := 0.0


func setup(stat_block: StatBlock) -> void:
	stats = stat_block


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func try_attack() -> void:
	if _cooldown > 0.0 or stats == null or weapon_data == null:
		return
	var duration := weapon_data.swing_time / maxf(0.1, stats.get_stat(Stats.ATTACK_SPEED))
	_cooldown = duration
	_do_attack(duration)


func set_blocking(value: bool) -> void:
	if is_blocking == value:
		return
	is_blocking = value
	_on_blocking_changed()


## Override: perform the attack. `duration` is the attack-speed-scaled swing time.
func _do_attack(_duration: float) -> void:
	pass


## Override: react to block starting/stopping.
func _on_blocking_changed() -> void:
	pass


## Override: feedback when this weapon successfully blocks a hit.
func notify_block_success(_perfect: bool = false) -> void:
	pass
