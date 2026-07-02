class_name HealthComponent
extends Node
## Shared health pool for player and monsters.

signal health_changed(current: float, max_health: float)
signal damaged(info: AttackInfo)
signal died

@export var max_health := 50.0

var current := 0.0
var is_dead := false


func _ready() -> void:
	current = max_health
	health_changed.emit(current, max_health)


func set_max_health(value: float, refill: bool = false) -> void:
	max_health = value
	if refill:
		current = value
	current = minf(current, max_health)
	health_changed.emit(current, max_health)


func take_damage(info: AttackInfo) -> void:
	if is_dead:
		return
	current = maxf(0.0, current - info.damage)
	health_changed.emit(current, max_health)
	damaged.emit(info)
	if current <= 0.0:
		is_dead = true
		died.emit()
