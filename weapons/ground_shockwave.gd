class_name GroundShockwave
extends Node3D
## Seismic Slam wave: travels forward along the ground in a straight line,
## damaging each enemy it passes at most once and carrying it along with a
## shove. Built entirely in code, no scene.

const SPEED := 14.0
const RANGE := 16.0
const HIT_RADIUS := 2.2
const SHOVE := 12.0
const COLOR := Color(1.0, 0.7, 0.3, 0.6)

var _info: AttackInfo
var _dir := Vector3.FORWARD
var _radius := HIT_RADIUS
var _traveled := 0.0
var _hit: Dictionary[int, bool] = {}


static func spawn(parent: Node, position: Vector3, info: AttackInfo,
		direction: Vector3, radius_mult: float = 1.0) -> void:
	if parent == null:
		return
	var wave := GroundShockwave.new()
	wave._info = info
	wave._dir = direction.normalized()
	wave._radius = HIT_RADIUS * radius_mult
	parent.add_child(wave)
	wave.global_position = position


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(COLOR.r, COLOR.g, COLOR.b)
	material.emission_energy_multiplier = 2.5
	mesh.mesh = VfxPool.unit_sphere()
	mesh.material_override = material
	add_child(mesh)
	mesh.scale = Vector3(_radius, 0.35, _radius)
	# Rolling churn: the wave pulses as it travels.
	var tween := mesh.create_tween().set_loops()
	tween.tween_property(mesh, "scale:y", 0.5, 0.1)
	tween.tween_property(mesh, "scale:y", 0.35, 0.1)


func _physics_process(delta: float) -> void:
	global_position += _dir * SPEED * delta
	_traveled += SPEED * delta
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var id := enemy.get_instance_id()
		if _hit.get(id, false):
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > _radius:
			continue
		_hit[id] = true
		var hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if hurtbox != null:
			hurtbox.receive_hit(AttackInfo.new(_info.source, _info.damage))
		# Carried along the wave, not scattered radially.
		enemy.apply_shove(_dir * SHOVE)
	if _traveled >= RANGE:
		queue_free()
