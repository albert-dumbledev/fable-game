class_name ArcaneBolt
extends Area3D
## The staff's spammable primary: a fast straight bolt that hits the first
## enemy it touches (or a wall) and pops with a small flash. Damage flows
## through the hurtbox pipeline so numbers/drops/vulnerability all apply.

const LIFETIME := 3.0
const IMPACT_COLOR := Color(0.6, 0.5, 1.0, 0.6)

@export var speed := 24.0

var _info: AttackInfo
var _dir := Vector3.FORWARD
var _age := 0.0
var _done := false


func setup(info: AttackInfo, direction: Vector3) -> void:
	_info = info
	_dir = direction.normalized()


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	global_position += _dir * speed * delta


func _on_area_entered(area: Area3D) -> void:
	var hurtbox := area as HurtboxComponent
	if hurtbox == null or _info == null:
		return
	hurtbox.receive_hit(_info)
	_impact()


func _on_body_entered(_body: Node3D) -> void:
	_impact()


func _impact() -> void:
	if _done:
		return
	_done = true
	BlastVfx.spawn(get_tree().current_scene, global_position, 0.8, IMPACT_COLOR, 0.4, 0.15)
	queue_free()
