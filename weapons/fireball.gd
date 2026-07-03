class_name Fireball
extends Area3D
## Charged player spell: flies straight, then explodes on ANY contact
## (enemy, wall, or end of life), damaging and shoving every enemy in a
## sphere. Damage flows through hurtboxes so numbers/drops work as usual.

const LIFETIME := 4.0
const EXPLOSION_RADIUS := 4.0
const EXPLOSION_SHOVE := 10.0
const BLAST_DURATION := 0.25

@export var speed := 18.0

var _info: AttackInfo
var _dir := Vector3.FORWARD
var _age := 0.0
var _exploded := false


func setup(info: AttackInfo, direction: Vector3) -> void:
	_info = info
	_dir = direction.normalized()


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	if _age >= LIFETIME:
		_explode()
		return
	global_position += _dir * speed * delta


func _on_area_entered(area: Area3D) -> void:
	if area is HurtboxComponent:
		_explode()


func _on_body_entered(_body: Node3D) -> void:
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as EnemyBase
		if enemy == null or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - global_position
		if offset.length() > EXPLOSION_RADIUS:
			continue
		var hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if hurtbox != null:
			hurtbox.receive_hit(AttackInfo.new(_info.source, _info.damage))
		offset.y = 0.0
		if offset.length() > 0.01:
			enemy.apply_shove(offset.normalized() * EXPLOSION_SHOVE)
	_spawn_blast()
	# Nearby blasts rattle the camera a little.
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null and player.global_position.distance_to(global_position) < 9.0:
		player.add_shake(0.3)
	queue_free()


func _spawn_blast() -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	var blast := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.1, 0.7)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.1)
	material.emission_energy_multiplier = 3.0
	sphere.material = material
	blast.mesh = sphere
	parent.add_child(blast)
	blast.global_position = global_position
	blast.scale = Vector3.ONE * 0.3
	var tween := blast.create_tween()
	tween.set_parallel(true)
	tween.tween_property(blast, "scale", Vector3.ONE * EXPLOSION_RADIUS, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, BLAST_DURATION)
	tween.chain().tween_callback(blast.queue_free)
