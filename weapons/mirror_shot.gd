class_name MirrorShot
extends Node3D
## Mirror Ward (duelist Aspect): the return shot from a perfect-blocked
## projectile. Homes to the shooter and detonates on impact in a radial blast
## that damages enemies through their hurtboxes — the AoE is resolved by
## sweeping EnemyBase.alive (mirroring _parry_nova / _sweep_hit), so this needs
## no collision layers of its own and can never tag the player. Built in code,
## no scene.

const SPEED := 22.0
const LIFETIME := 2.0
## Detonate once this close to the tracked shooter.
const IMPACT_DIST := 0.7
const ORB_COLOR := Color(1.0, 0.85, 0.35)
const BLAST_COLOR := Color(1.0, 0.85, 0.35, 0.55)

var _dir := Vector3.FORWARD
var _target: Node3D
var _damage := 0.0
var _radius := 4.0
var _source: Node3D
var _age := 0.0
var _detonated := false


## Fling a return shot from `origin` toward `target` (the shooter). `source` is
## the player, so the blast's AttackInfo credits them. A null/dead target lets
## the shot fly straight and detonate at the end of its life.
static func spawn(parent: Node, origin: Vector3, target: Node3D, damage: float,
		radius: float, source: Node3D) -> void:
	if parent == null:
		return
	var shot := MirrorShot.new()
	shot._target = target
	shot._damage = damage
	shot._radius = radius
	shot._source = source
	var aim := Vector3.FORWARD
	if target != null and is_instance_valid(target):
		aim = target.global_position - origin
	shot._dir = aim.normalized() if aim.length() > 0.01 else Vector3.FORWARD
	parent.add_child(shot)
	shot.global_position = origin


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	var material := StandardMaterial3D.new()
	material.albedo_color = ORB_COLOR
	material.emission_enabled = true
	material.emission = ORB_COLOR
	material.emission_energy_multiplier = 3.0
	mesh.mesh = sphere
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_age += delta
	if _age >= LIFETIME:
		_detonate()
		return
	# Home onto the shooter while it lives; otherwise keep the last heading.
	if _target != null and is_instance_valid(_target):
		var to_target := _target.global_position + Vector3(0.0, 1.0, 0.0) - global_position
		if to_target.length() <= IMPACT_DIST:
			_detonate()
			return
		_dir = _dir.slerp(to_target.normalized(), clampf(8.0 * delta, 0.0, 1.0))
	global_position += _dir * SPEED * delta


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	var scene := get_tree().current_scene
	# Radial damage, resolved manually against every alive enemy so the blast
	# never needs to collide with (and so can never hurt) the player.
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > _radius:
			continue
		var enemy_hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if enemy_hurtbox != null:
			enemy_hurtbox.receive_hit(AttackInfo.new(_source, _damage))
	AudioManager.play_at(&"explosion", global_position)
	BlastVfx.spawn(scene, global_position, _radius, BLAST_COLOR, 1.0, 0.3)
	ShardBurst.spawn(scene, global_position, ORB_COLOR, 10, 6.0, 0.1, 0.6)
	queue_free()
