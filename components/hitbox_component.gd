class_name HitboxComponent
extends Area3D
## Deals damage while active. Activate with an AttackInfo and a duration;
## each overlapped hurtbox is hit at most once per activation.
##
## Monitoring stays on permanently: targets already inside when the attack
## starts are swept via get_overlapping_areas(), which toggling `monitoring`
## at activation time would miss.

var _info: AttackInfo
var _remaining := 0.0
var _already_hit: Array[HurtboxComponent] = []


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func activate(info: AttackInfo, duration: float) -> void:
	_info = info
	_remaining = duration
	_already_hit.clear()
	for area: Area3D in get_overlapping_areas():
		_try_hit(area)


func deactivate() -> void:
	_remaining = 0.0
	_info = null


func _physics_process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		deactivate()


func _on_area_entered(area: Area3D) -> void:
	_try_hit(area)


func _try_hit(area: Area3D) -> void:
	if _info == null:
		return
	var hurtbox := area as HurtboxComponent
	if hurtbox == null or hurtbox in _already_hit:
		return
	_already_hit.append(hurtbox)
	hurtbox.receive_hit(_info)
