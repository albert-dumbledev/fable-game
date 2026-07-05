class_name BoulderProjectile
extends Node3D
## The Juggernaut's mortar: a stone sphere lobbed on a fixed ballistic arc to a
## committed landing point (the GroundTelegraph shows it during flight), then a
## ground AoE on impact. No mid-flight collision — the landing zone is the truth,
## so dashing through the arc is safe. Built in code, no scene.

const ARC_HEIGHT := 6.0
const SPHERE_RADIUS := 0.85
const STONE_COLOR := Color(0.4, 0.37, 0.34)
## Minions caught in the blast are shoved clear (flavour, no damage).
const MINION_SHOVE := 11.0

var _start := Vector3.ZERO
var _landing := Vector3.ZERO
var _flight := 0.9
var _radius := 2.8
var _info: AttackInfo
var _time := 0.0
var _spin := Vector3.ZERO
var _mesh: MeshInstance3D


static func spawn(parent: Node, start: Vector3, landing: Vector3, flight: float,
		radius: float, info: AttackInfo) -> void:
	if parent == null:
		return
	var boulder := BoulderProjectile.new()
	boulder._start = start
	boulder._landing = landing
	boulder._flight = flight
	boulder._radius = radius
	boulder._info = info
	parent.add_child(boulder)
	boulder.global_position = start


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = SPHERE_RADIUS
	sphere.height = SPHERE_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = STONE_COLOR
	material.roughness = 1.0
	_mesh.mesh = sphere
	_mesh.material_override = material
	add_child(_mesh)
	# Slow random tumble for flavour.
	_spin = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
			.normalized() * randf_range(2.0, 4.0)


func _physics_process(delta: float) -> void:
	_time += delta
	var t := clampf(_time / _flight, 0.0, 1.0)
	var pos := _start.lerp(_landing, t)
	pos.y += ARC_HEIGHT * sin(PI * t)  # parabolic hop over the straight interpolation
	global_position = pos
	_mesh.rotation += _spin * delta
	if t >= 1.0:
		_impact()


func _impact() -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	# Player hit — only if inside the landing radius (horizontal). Routes through
	# the hurtbox so block/dash/parry all apply; a perfect block stuns the boss.
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player != null:
		var pd := player.global_position - _landing
		pd.y = 0.0
		if pd.length() <= _radius:
			var hurtbox := player.get_node_or_null(^"Hurtbox") as HurtboxComponent
			if hurtbox != null:
				hurtbox.receive_hit(_info)
		if player is Player and player.global_position.distance_to(_landing) < 12.0:
			(player as Player).add_shake(0.35)
	# Shove minions clear (no damage), skipping the caster itself.
	for minion: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(minion) or minion == _info.source or not minion.is_inside_tree():
			continue
		var off := minion.global_position - _landing
		off.y = 0.0
		if off.length() <= _radius and off.length() > 0.01:
			minion.apply_shove(off.normalized() * MINION_SHOVE)
	AudioManager.play_at(&"hammer_slam", _landing)  # placeholder thud until the M4 SFX pass
	BlastVfx.spawn(scene, _landing, _radius, GroundTelegraph.ENEMY_COLOR, 0.12, 0.3)
	ShardBurst.spawn(scene, _landing + Vector3(0.0, 0.2, 0.0), STONE_COLOR, 14, 8.0, 0.16)
	queue_free()
