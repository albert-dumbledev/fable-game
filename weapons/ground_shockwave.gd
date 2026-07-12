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
## Riptide (wave_drag): enemies are dragged harder along the wave and left in a
## briefly staggered clump when it dissipates.
const DRAG_SHOVE_MULT := 1.6
const DRAG_STUN := 0.5
## Implosion (slam_pull) on the Seismic Slam: instead of carrying enemies
## forward, the wave rakes them back toward the cast origin and staggers them
## there — a gather, not a scatter. Distance-scaled so they converge and settle
## near the centre instead of being flung past it.
const PULL_STUN := 0.5
const PULL_STRENGTH := 9.0
const PULL_MAX := 22.0
## HOLLOW EARTH (Depth IV forged Aspect, docs/DEPTHS.md Lane 2): an enemy the wave
## kills erupts a fresh shockwave from its corpse at this fraction of the wave's
## damage and range. Single generation only — the erupted wave carries `_no_erupt`
## so its own kills don't cascade, mirroring the Mass Driver / Shatterflux stance.
const HOLLOW_EARTH_MULT := 0.5

var _info: AttackInfo
var _dir := Vector3.FORWARD
var _radius := HIT_RADIUS
var _traveled := 0.0
var _range := RANGE
var _hit: Dictionary[int, bool] = {}
var _shove := SHOVE
var _drag := false
## Enemies caught while dragging, staggered as a clump when the wave ends.
var _dragged: Array[EnemyBase] = []
var _pull := false
var _origin := Vector3.ZERO
## HOLLOW EARTH: resolved from the caster's ability; false on erupted child waves
## so the effect stops at a single generation (set via `no_erupt` at spawn).
var _hollow_earth := false
var _no_erupt := false
## Fault Line (Aspect): the spawning weapon, so each caught enemy can refund a
## slice of its secondary cooldown. Null when the caster lacks the aspect.
var _weapon: Weapon
var _fault_line := false
## Mass Driver (Aspect): the shove carries a wall-slam payload and drives caught
## enemies through their neighbours (both = BONE_BREAKER_MULT of the wave damage).
var _wall_damage := 0.0
var _through_damage := 0.0


static func spawn(parent: Node, position: Vector3, info: AttackInfo,
		direction: Vector3, radius_mult: float = 1.0, shove: float = SHOVE,
		drag: bool = false, pull: bool = false, range_dist: float = RANGE,
		weapon: Weapon = null, no_erupt: bool = false) -> void:
	if parent == null:
		return
	var wave := GroundShockwave.new()
	wave._info = info
	wave._dir = direction.normalized()
	wave._radius = HIT_RADIUS * radius_mult
	wave._shove = shove
	wave._drag = drag
	wave._pull = pull
	wave._range = range_dist
	wave._origin = position
	wave._weapon = weapon
	wave._no_erupt = no_erupt
	parent.add_child(wave)
	wave.global_position = position


func _ready() -> void:
	# Aspect payloads, resolved once from the caster: Fault Line refunds the
	# secondary per unique enemy caught; Mass Driver adds a Bone Breaker wall-slam
	# payload and drives enemies through their neighbours.
	var player := _info.source as Player
	_fault_line = _weapon != null and player != null and player.has_ability(&"fault_line")
	# HOLLOW EARTH: only the first generation erupts; child waves spawn with
	# `_no_erupt` set, so their kills never cascade another eruption.
	_hollow_earth = not _no_erupt and player != null and player.has_ability(&"hollow_earth")
	if player != null and player.has_ability(&"mass_driver"):
		_wall_damage = _info.damage * Warhammer.BONE_BREAKER_MULT
		_through_damage = _info.damage * Warhammer.BONE_BREAKER_MULT
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
		# Fault Line: the wave paying for the next slam, one enemy at a time.
		if _fault_line:
			_weapon.refund_secondary(Warhammer.FAULT_LINE_REFUND)
		var hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if hurtbox != null:
			hurtbox.receive_hit(AttackInfo.new(_info.source, _info.damage))
			# HOLLOW EARTH: a wave-kill erupts a half-strength shockwave from the
			# corpse. Single generation (`_hollow_earth` is false on erupted waves).
			if _hollow_earth and enemy.health != null and enemy.health.current <= 0.0:
				_erupt_hollow_earth(enemy.global_position)
		# Pull (Implosion) rakes enemies back to the cast origin and staggers
		# them; Riptide (drag) carries them forward; otherwise a plain carry.
		# Every shove carries the Mass Driver payload (0 unless owned).
		if _pull:
			var to_origin := _origin - enemy.global_position
			to_origin.y = 0.0
			var d := to_origin.length()
			if d > 0.1:
				enemy.apply_shove(to_origin / d * minf(PULL_MAX, d * PULL_STRENGTH),
						_wall_damage, _info.source, _through_damage)
			if enemy.state != EnemyBase.State.STUNNED and enemy.state != EnemyBase.State.DEAD:
				enemy.stun(PULL_STUN)
		elif _drag:
			enemy.apply_shove(_dir * _shove * DRAG_SHOVE_MULT,
					_wall_damage, _info.source, _through_damage)
			_dragged.append(enemy)
		else:
			enemy.apply_shove(_dir * _shove, _wall_damage, _info.source, _through_damage)
	if _traveled >= _range:
		if _drag:
			_stagger_dragged()
		queue_free()


## HOLLOW EARTH: erupt a half-strength shockwave from a corpse, travelling the same
## direction as this wave. Spawned with `no_erupt = true` so this child is the last
## generation — its own kills can't erupt again (the anti-cascade stance shared with
## Mass Driver's through-sweep and Shatterflux's mini-nova). Plain wave: no drag/
## pull/Fault Line inherited, so the eruption reads as a clean secondary quake.
func _erupt_hollow_earth(corpse: Vector3) -> void:
	if not is_inside_tree():
		return
	corpse.y = 0.1
	GroundShockwave.spawn(get_tree().current_scene, corpse,
			AttackInfo.new(_info.source, _info.damage * HOLLOW_EARTH_MULT), _dir,
			_radius / HIT_RADIUS, SHOVE, false, false, _range * HOLLOW_EARTH_MULT,
			null, true)


## Riptide payoff: the dragged clump is left briefly staggered at the end of
## the line. Guarded against re-stunning an already-stunned enemy.
func _stagger_dragged() -> void:
	for enemy: EnemyBase in _dragged:
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		if enemy.state != EnemyBase.State.STUNNED and enemy.state != EnemyBase.State.DEAD:
			enemy.stun(DRAG_STUN)
