class_name FrostRune
extends Node3D
## THE WAITING COLD (Depth III forged Aspect, docs/DEPTHS.md Lane 2): the rune a
## Frost Nova cast plants at the caster's feet. It arms after ARM_TIME, then the
## first living enemy inside TRIGGER_RADIUS detonates it — the very first armed
## frame checks occupancy, so enemies already standing on it when it arms trip it
## immediately (preserving the nova's panic-button use). Untriggered, it auto-fires
## when LIFETIME runs out. Detonation routes back through the player's shared nova
## routine (Player.detonate_frost_rune) at 1.5×, so every nova boon still applies.
## Built entirely in code, no scene — same pattern as FlamePatch, with a
## GroundTelegraph disc sweeping the arm window.

const ARM_TIME := 0.5
const LIFETIME := 6.0
## Tread radius — deliberately tighter than the nova's 6m blast, so the rune is a
## trap that must be stepped on, not a delayed copy of the instant cast.
const TRIGGER_RADIUS := 1.6
## Matches Player.FROST_NOVA_COLOR so the rune reads as frost at a glance.
const RUNE_COLOR := Color(0.55, 0.85, 1.0, 0.6)
const DIM_ENERGY := 1.2
const ARMED_ENERGY := 2.8

var _player: Player
var _age := 0.0
var _armed := false
var _detonated := false
var _material: StandardMaterial3D


static func spawn(parent: Node, position: Vector3, player: Player) -> FrostRune:
	if parent == null:
		return null
	var rune := FrostRune.new()
	rune._player = player
	parent.add_child(rune)
	rune.global_position = Vector3(position.x, 0.0, position.z)
	return rune


func _ready() -> void:
	# Standing marker: a flat icy disc, dim while arming, brightening on arm.
	var mesh := MeshInstance3D.new()
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(RUNE_COLOR.r, RUNE_COLOR.g, RUNE_COLOR.b, RUNE_COLOR.a * 0.6)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	_material.emission = Color(RUNE_COLOR.r, RUNE_COLOR.g, RUNE_COLOR.b)
	_material.emission_energy_multiplier = DIM_ENERGY
	mesh.mesh = VfxPool.unit_sphere()
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.position.y = 0.04
	mesh.scale = Vector3(TRIGGER_RADIUS, 0.06, TRIGGER_RADIUS)
	# Arm-window sweep: the telegraph's fill reaching the rim IS the arm moment.
	GroundTelegraph.spawn(self, global_position, TRIGGER_RADIUS, ARM_TIME, RUNE_COLOR)


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_age += delta
	if _age >= LIFETIME:
		_detonate()
		return
	if not _armed:
		if _age < ARM_TIME:
			return
		# Armed: brighten the marker. The occupancy check below runs THIS frame,
		# so anything already standing in the circle trips the rune immediately.
		_armed = true
		_material.emission_energy_multiplier = ARMED_ENERGY
		_material.albedo_color.a = RUNE_COLOR.a
	for enemy: EnemyBase in EnemyBase.alive:
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		if enemy.state == EnemyBase.State.DEAD:
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() <= TRIGGER_RADIUS:
			_detonate()
			return


## Fire the 1.5× nova through the player's shared routine and expire. An orphaned
## rune (player dead/freed) just fizzles — freeing without a pulse.
func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	if is_instance_valid(_player) and _player.is_inside_tree():
		_player.detonate_frost_rune(global_position)
	queue_free()
