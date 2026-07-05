class_name StalkerEnemy
extends EnemyBase
## Evasive skirmisher (jackal): curves onto the player's flank, lands one fast
## strike, then disengages to orbit range for a few seconds before re-engaging.
## It never stands still in melee to be punished — the counterplay is a parry
## (base WINDUP/ATTACK means a perfect block stuns it mid-strike) and, at 18 HP,
## a riposte deletes it. Frost slow collapses the disengage for free (move_speed).

enum Mode { ENGAGE, DISENGAGE }

## While further out than this, the approach blends in a tangential component so
## the Stalker curves onto the flank instead of joining the conga line.
const ARC_UNTIL := 4.0
const ARC_BLEND := 0.6
## Orbit distance held during the disengage.
const ORBIT_RANGE := 8.0
const DISENGAGE_MIN := 2.5
const DISENGAGE_MAX := 3.5
## Steady eye glow while disengaged — the "I'm still watching you" tell.
const WATCH_GLOW := 2.0

var _mode: Mode = Mode.ENGAGE
var _disengage_time := 0.0
## +1 / -1 so different Stalkers curve to opposite flanks.
var _arc_sign := 1.0


func _ready() -> void:
	super()
	_arc_sign = 1.0 if randf() < 0.5 else -1.0


func _chase() -> void:
	var delta := get_physics_process_delta_time()
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var toward := to_target.normalized() if dist > 0.01 else -global_transform.basis.z
	var tangent := Vector3(-toward.z, 0.0, toward.x) * _arc_sign
	if _mode == Mode.DISENGAGE:
		_disengage(delta, dist, toward, tangent)
		return
	# ENGAGE: strike when in range, else curve in.
	if dist <= data.attack_range:
		_reset_eyes()
		_begin_windup()
		return
	var dir := toward
	if dist > ARC_UNTIL:
		dir = (toward + tangent * ARC_BLEND).normalized()
	velocity.x = dir.x * move_speed()
	velocity.z = dir.z * move_speed()


## Back off to orbit range with lateral drift, watching, until the timer runs
## out; then swing back to ENGAGE.
func _disengage(delta: float, dist: float, toward: Vector3, tangent: Vector3) -> void:
	_disengage_time -= delta
	if _disengage_time <= 0.0:
		_mode = Mode.ENGAGE
		_reset_eyes()
		return
	if _eye_material != null:
		_eye_material.emission_energy_multiplier = WATCH_GLOW
	var dir := tangent
	if dist < ORBIT_RANGE:
		dir = (-toward + tangent * 0.5).normalized()
	velocity.x = dir.x * move_speed()
	velocity.z = dir.z * move_speed()


## After a strike's recover, bolt back out rather than lingering in melee.
func _begin_recover() -> void:
	super()
	_mode = Mode.DISENGAGE
	_disengage_time = randf_range(DISENGAGE_MIN, DISENGAGE_MAX)
	AudioManager.play_at(&"stalker_disengage", global_position)
