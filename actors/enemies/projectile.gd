class_name Projectile
extends Area3D
## Straight-line projectile. Damage flows through the same hurtbox pipeline
## as melee, so shields (and mitigate_hit) work against it unchanged.

const LIFETIME := 4.0

@export var speed := 12.0

var _info: AttackInfo
var _dir := Vector3.FORWARD
var _age := 0.0


func setup(info: AttackInfo, direction: Vector3) -> void:
	_info = info
	_dir = direction.normalized()


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
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
	queue_free()


func _on_body_entered(_body: Node3D) -> void:
	queue_free()
