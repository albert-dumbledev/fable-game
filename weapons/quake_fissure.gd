class_name QuakeFissure
extends Node3D
## Fault Line (Aspect): a quaking crack left in the Seismic wave's wake. It
## lingers along the wave's path and staggers any enemy standing on it, and each
## unique enemy it catches refunds a slice of the slam's cooldown. Built entirely
## in code, no scene — the same lightweight approach as GroundShockwave.
##
## Rendering mirrors GroundTelegraph's LANE decal, but the danger semantics are
## inverted: this is warm-orange (the player's quake), not enemy red — it hurts
## *them*, so it reassures rather than warns.

const FAULT_LINE_DURATION := 4.0
const FAULT_LINE_STAGGER := 0.3
## Warm orange, distinct from GroundTelegraph.ENEMY_COLOR's red.
const COLOR := Color(1.0, 0.6, 0.25, 0.45)
## The strip visibly settles over its last moments before it closes up.
const FADE_TIME := 0.6

var _weapon: Weapon
var _forward := Vector3.FORWARD
## Perpendicular (rightward) axis, for the strip's half-width test.
var _right := Vector3.RIGHT
var _origin := Vector3.ZERO
var _length := 1.0
var _half_width := 1.0
var _time := 0.0
var _fill_material: StandardMaterial3D
## Enemies already caught, so each refunds the cooldown at most once.
var _caught: Dictionary[int, bool] = {}


## Lay a fissure from `origin` running `length` along `forward`, `width` wide.
## `weapon` receives the per-enemy cooldown refund (null = no refund).
static func spawn(parent: Node, origin: Vector3, forward: Vector3, length: float,
		width: float, weapon: Weapon = null) -> void:
	if parent == null:
		return
	var fissure := QuakeFissure.new()
	fissure._weapon = weapon
	fissure._forward = forward.normalized()
	fissure._right = Vector3(fissure._forward.z, 0.0, -fissure._forward.x)
	fissure._origin = origin
	fissure._length = length
	fissure._half_width = width * 0.5
	parent.add_child(fissure)
	# Centre the decal at the strip's midpoint, oriented so local +Z runs along
	# the fissure (same convention as GroundTelegraph.spawn_line).
	var centre := origin + fissure._forward * (length * 0.5)
	centre.y = 0.1
	fissure.global_position = centre
	fissure.rotation.y = atan2(-fissure._forward.x, -fissure._forward.z)


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	_fill_material = StandardMaterial3D.new()
	_fill_material.albedo_color = COLOR
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.emission_enabled = true
	_fill_material.emission = Color(COLOR.r, COLOR.g, COLOR.b)
	_fill_material.emission_energy_multiplier = 1.8
	mesh.mesh = VfxPool.unit_sphere()
	mesh.material_override = _fill_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.position.y = 0.02
	mesh.scale = Vector3(_half_width * 2.0, 0.05, _length)
	# Quake pulse: a steady tremor in the emission so the crack reads as alive.
	var tween := mesh.create_tween().set_loops()
	tween.tween_property(_fill_material, "emission_energy_multiplier", 3.2, 0.35)
	tween.tween_property(_fill_material, "emission_energy_multiplier", 1.8, 0.35)


func _physics_process(delta: float) -> void:
	_time += delta
	if _time >= FAULT_LINE_DURATION:
		queue_free()
		return
	# Settle the crack shut over its final moments.
	var remaining := FAULT_LINE_DURATION - _time
	if remaining < FADE_TIME and _fill_material != null:
		_fill_material.albedo_color.a = COLOR.a * (remaining / FADE_TIME)
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - _origin
		offset.y = 0.0
		var along := _forward.dot(offset)
		if along < 0.0 or along > _length:
			continue
		if absf(_right.dot(offset)) > _half_width:
			continue
		# Gather-stun guard: only stagger an enemy that isn't already stunned or
		# dead, so the fissure never chains a permanent stun-lock.
		if enemy.state != EnemyBase.State.STUNNED and enemy.state != EnemyBase.State.DEAD:
			enemy.stun(FAULT_LINE_STAGGER)
		# Cooldown refund: once per unique enemy the fissure catches.
		var id := enemy.get_instance_id()
		if not _caught.get(id, false):
			_caught[id] = true
			if _weapon != null:
				_weapon.refund_secondary(Warhammer.FAULT_LINE_REFUND)
