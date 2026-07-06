class_name BladeCrescent
extends Area3D
## The Revenant's Boomerang Cross-Slash: a spinning crescent blade thrown out
## along a committed lane (GroundTelegraph shows the outgoing path), then
## reversed back toward the boss — two timed danger passes to weave around.
## The anti-kite answer to pure running: distinct from the Caster's volley
## spam (a single returning blade, not a fan). Built in code, no scene.

const OUT_SPEED := 15.0
const RETURN_SPEED_MULT := 1.15
const MAX_LIFETIME := 3.0
const HIT_RADIUS := 0.9
const MINION_SHOVE := 8.0
const SPIN_SPEED := 18.0
const CRESCENT_COLOR := Color(0.3, 0.9, 0.95)

var _origin := Vector3.ZERO
var _apex := Vector3.ZERO
var _out_speed := OUT_SPEED
var _info: AttackInfo
var _boss: Node3D
var _returning := false
var _age := 0.0
var _hit_this_pass := false
var _mesh: MeshInstance3D


## `origin`/`apex` are the committed outgoing lane (telegraphed up front —
## honesty). `boss` is who the return pass homes toward (falls back to
## `origin` if the boss is gone by the time the return starts).
static func spawn(scene: Node, origin: Vector3, apex: Vector3, out_speed: float,
		info: AttackInfo, boss: Node3D = null) -> BladeCrescent:
	if scene == null:
		return null
	var blade := BladeCrescent.new()
	blade._origin = origin
	blade._apex = apex
	blade._out_speed = out_speed
	blade._info = info
	blade._boss = boss
	scene.add_child(blade)
	blade.global_position = origin
	return blade


func _ready() -> void:
	collision_layer = 0
	collision_mask = 9  # world (1) + player hurtbox (8)
	monitorable = false
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = HIT_RADIUS * 0.5
	col.shape = shape
	add_child(col)
	_mesh = MeshInstance3D.new()
	var crescent := TorusMesh.new()
	crescent.inner_radius = 0.35
	crescent.outer_radius = 0.7
	crescent.rings = 6
	crescent.ring_segments = 16
	var material := StandardMaterial3D.new()
	material.albedo_color = CRESCENT_COLOR
	material.emission_enabled = true
	material.emission = CRESCENT_COLOR
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.mesh = crescent
	_mesh.material_override = material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.rotation.x = PI * 0.5  # face the ring flat-on along the flight direction
	add_child(_mesh)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	_mesh.rotate_z(SPIN_SPEED * delta)
	if _age >= MAX_LIFETIME:
		queue_free()
		return
	var target := _apex if not _returning else _return_target()
	var to_target := target - global_position
	to_target.y = 0.0
	var speed := _out_speed if not _returning else _out_speed * RETURN_SPEED_MULT
	var step := speed * delta
	if to_target.length() <= step:
		global_position = target
		if not _returning:
			_returning = true
			_hit_this_pass = false  # second pass gets its own chance to hit
		else:
			queue_free()
		return
	global_position += to_target.normalized() * step


func _return_target() -> Vector3:
	if _boss != null and is_instance_valid(_boss) and _boss.is_inside_tree():
		return _boss.global_position
	return _origin


func _on_area_entered(area: Area3D) -> void:
	if area is HurtboxComponent:
		_hit_player(area as HurtboxComponent)


func _on_body_entered(_body: Node3D) -> void:
	queue_free()  # wall — the pass ends here


## At most one hit per pass (out and return are two separate chances).
func _hit_player(hurtbox: HurtboxComponent) -> void:
	if _hit_this_pass:
		return
	_hit_this_pass = true
	hurtbox.receive_hit(_info)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.add_shake(0.25)
	AudioManager.play_at(&"arcane_bolt", global_position)  # placeholder; revenant_crescent cue lands in M5
	for minion: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(minion) or minion == _info.source or not minion.is_inside_tree():
			continue
		var off := minion.global_position - global_position
		off.y = 0.0
		if off.length() <= HIT_RADIUS * 2.0 and off.length() > 0.01:
			minion.apply_shove(off.normalized() * MINION_SHOVE)
