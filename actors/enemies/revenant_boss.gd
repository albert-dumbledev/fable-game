class_name RevenantBoss
extends BossBase
## THE REVENANT: the 7:30 finale boss. A stalker-type that orbits at range,
## blinks in on a telegraphed lane, runs a melee combo, opens a brief
## vulnerable window, then blinks back out to range. Killing it wins the run.
##
## M3: the real 3-hit Cadence Combo (Slash -> Backhand -> Overhead finisher)
## replaces the M2 placeholder. Driven as a sub-phase machine that stays in
## State.CHASE the whole time (Juggernaut-charge precedent, BossEnemy._chase)
## rather than the base WINDUP->ATTACK->RECOVER auto-transitions, since those
## only allow one shared data.windup_time/recover_time and mutating the
## shared EnemyData resource per hit is forbidden.
##
## M4: the Boomerang Cross-Slash (Phase.VOLLEY) answers pure kiting — a
## spinning BladeCrescent thrown out along a telegraphed lane and back, fired
## from STALK when the player sits beyond VOLLEY_MIN_RANGE and the engage
## cadence isn't due. A low-HP enrage (_cadence_mult) tightens every windup/
## recover/cooldown once health drops under ENRAGE_HP_FRACTION, and burns the
## teal TrimRing brighter as the readable tell.

enum Phase { STALK, ENGAGE_WINDUP, COMBO, RECOVER_VULN, DISENGAGE, VOLLEY }
## Per-hit sub-state within Phase.COMBO.
enum ComboBeat { WINDUP, STRIKE, RECOVER }

const ORBIT_RANGE := 10.0
const ARENA_HALF := 18.5
## Past this fraction of the half-extent, orbiting/fleeing blends in a
## wall-slide so the boss doesn't corner itself (CasterBoss._flee precedent).
const EDGE := ARENA_HALF * 0.85
const ENGAGE_COOLDOWN := 4.0
const ENGAGE_WINDUP_TIME := 0.4
## Blink lands this far in front of the player; the strike lunge closes the
## rest so the blade reaches without the boss popping on top of the player.
const COMBO_RANGE := 2.6
const RECOVER_VULN_TIME := 0.9
const DISENGAGE_DIST := 10.0
## Chip hits landed during STALK before it bails early instead of engaging.
const EARLY_DISENGAGE_HITS := 2
const BLINK_COLOR := Color(0.3, 0.9, 0.95, 0.6)
const BLINK_RADIUS := 1.4
const BLINK_LANE_WIDTH := 1.5

## Boomerang Cross-Slash (M4): the anti-kite answer. Fired from STALK only,
## subordinate to the engage cadence (engage always wins if it's ready).
const VOLLEY_MIN_RANGE := 9.0
const VOLLEY_COOLDOWN := 6.0
const VOLLEY_WINDUP_TIME := 0.5
const VOLLEY_LANE_WIDTH := 1.8
const VOLLEY_OUT_SPEED := 15.0
const CRESCENT_DMG_MULT := 0.7
const CRESCENT_KNOCKBACK := 4.0
## Boss-local cocked-blade pose held during the volley windup.
const BOSS_FIST_VOLLEY_WINDUP := Vector3(0.9, 2.4, 0.9)

## Low-HP enrage (M4): a pure timing ramp — cadence tightens, damage untouched.
const ENRAGE_HP_FRACTION := 0.35
const ENRAGE_CADENCE_MULT := 0.75
const ENRAGE_TRIM_EMISSION := 5.0

## The Cadence Combo: three fixed, metronomic beats the player learns to
## parry/dodge on rhythm. Index 0/1 are quick melee slashes; index 2 is the
## overhead finisher (ground AoE). Recovers are uniform; windups are not —
## the tighter beat on the backhand and the long overhead telegraph are the
## whole point of the "cadence".
const COMBO_WINDUPS: Array[float] = [0.45, 0.35, 0.70]
const COMBO_RECOVERS: Array[float] = [0.30, 0.30, 0.30]
const COMBO_HIT_COUNT := 3
## Melee hits (0/1) lunge toward the player on strike so the blade reaches —
## the blink lands the boss a couple metres out.
const COMBO_LUNGE_MULT := 1.6
const OVERHEAD_DMG_MULT := 1.6
const OVERHEAD_KNOCKBACK := 12.0
const OVERHEAD_INNER_RADIUS := 2.2
const OVERHEAD_OUTER_RADIUS := 3.6
const OVERHEAD_SPLASH_MULT := 0.4
## Overhead impact point committed this far in front of the locked facing —
## mirrors BossEnemy._slam_point.
const OVERHEAD_IMPACT_DISTANCE := 2.6
## Boss-local blade poses (FistPivot positions; the scene default is REST).
const BOSS_FIST_REST := Vector3(0.5, 2.2, -0.6)
const BOSS_FIST_WINDUP := Vector3(0.2, 2.9, 0.5)
const BOSS_FIST_STRIKE := Vector3(0.7, 1.3, -1.8)
const BOSS_FIST_OVERHEAD_WINDUP := Vector3(0.0, 3.6, 0.7)
const BOSS_FIST_OVERHEAD_STRIKE := Vector3(0.3, 0.9, -2.1)

var _phase := Phase.STALK
var _engage_cooldown := ENGAGE_COOLDOWN
var _chip_hits := 0
var _engage_landing := Vector3.ZERO
var _face_locked := false
## Set by stun(); the next _chase after _end_stun routes straight to a
## disengage blink instead of resuming whatever phase was interrupted.
var _disengage_after_stun := false

var _combo_index := 0
var _combo_beat := ComboBeat.WINDUP
var _combo_timer := 0.0
## Overhead finisher's committed impact point (mirrors BossEnemy._slam_point).
var _overhead_point := Vector3.ZERO

## Boomerang Cross-Slash (M4) state.
var _volley_cooldown := VOLLEY_COOLDOWN
var _volley_apex := Vector3.ZERO

## Low-HP enrage (M4) state.
var _enraged := false
var _trim_material: StandardMaterial3D


## Duplicate the TrimRing material so the enrage brightening is per-instance
## (CasterBoss._orb_material precedent), not a shared-resource mutation.
func _ready() -> void:
	super()
	var trim := get_node_or_null(^"Mesh/TrimRing") as MeshInstance3D
	if trim != null:
		var mat := trim.get_active_material(0)
		if mat != null:
			_trim_material = mat.duplicate() as StandardMaterial3D
			trim.material_override = _trim_material


## Enrage is a pure timing ramp: every windup/recover/cooldown site multiplies
## by this. Damage is untouched.
func _cadence_mult() -> float:
	return ENRAGE_CADENCE_MULT if _enraged else 1.0


func _chase() -> void:
	var delta := get_physics_process_delta_time()
	match _phase:
		Phase.STALK:
			_stalk(delta)
		Phase.ENGAGE_WINDUP:
			_hold_still()
		Phase.RECOVER_VULN:
			_hold_still()
		Phase.DISENGAGE:
			_hold_still()
		Phase.COMBO:
			_tick_combo(delta)
		Phase.VOLLEY:
			_hold_still()


## Orbit the player at ~ORBIT_RANGE, watching (eyes lit) until the engage
## cooldown expires or the player has chipped it enough to warrant bailing.
## Cross-slash volley is subordinate to the engage cadence: engage always
## wins if it's ready, so the volley can never starve the melee combo.
func _stalk(delta: float) -> void:
	_engage_cooldown -= delta
	_volley_cooldown -= delta
	if _eye_material != null:
		_eye_material.emission_energy_multiplier = StalkerEnemy.WATCH_GLOW
	if _chip_hits >= EARLY_DISENGAGE_HITS:
		_chip_hits = 0
		_begin_disengage()
		return
	if _engage_cooldown <= 0.0:
		_begin_engage_windup()
		return
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if _volley_cooldown <= 0.0 and dist > VOLLEY_MIN_RANGE:
		_begin_volley_windup()
		return
	var toward := to_target.normalized() if dist > 0.01 else Vector3(0.0, 0.0, 1.0)
	var tangent := Vector3(-toward.z, 0.0, toward.x)
	var dir := tangent
	if dist < ORBIT_RANGE:
		dir = (-toward + tangent * 0.5).normalized()
	elif dist > ORBIT_RANGE:
		dir = (toward + tangent * 0.5).normalized()
	dir = _wall_slide(dir)
	velocity.x = dir.x * move_speed()
	velocity.z = dir.z * move_speed()


## Commit the crescent's outgoing apex up front (telegraph honesty), hold
## still with a cocked-blade tell + eye flash, draw the outgoing lane, then
## hand off to _finish_volley_windup after the windup.
func _begin_volley_windup() -> void:
	_phase = Phase.VOLLEY
	var wind_time := VOLLEY_WINDUP_TIME * _cadence_mult()
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var toward := to_target.normalized() if to_target.length() > 0.01 else -global_transform.basis.z
	_volley_apex = _target.global_position + toward * 1.0
	_volley_apex.x = clampf(_volley_apex.x, -ARENA_HALF, ARENA_HALF)
	_volley_apex.z = clampf(_volley_apex.z, -ARENA_HALF, ARENA_HALF)
	_volley_apex.y = global_position.y
	GroundTelegraph.spawn_line(get_tree().current_scene, global_position, _volley_apex,
			VOLLEY_LANE_WIDTH, wind_time, BLINK_COLOR)
	_flash_eyes(wind_time)
	_tween_fist(BOSS_FIST_VOLLEY_WINDUP, wind_time)
	get_tree().create_timer(wind_time, false).timeout.connect(_finish_volley_windup)


func _finish_volley_windup() -> void:
	if not is_inside_tree() or state == State.DEAD or _phase != Phase.VOLLEY:
		return
	_reset_eyes()
	_tween_fist(BOSS_FIST_REST, 0.2)
	var origin := global_position + Vector3(0.0, 1.4, 0.0)
	var apex := _volley_apex + Vector3(0.0, 1.4, 0.0)
	var info := AttackInfo.new(self, data.damage * _dmg_mult * CRESCENT_DMG_MULT,
			CRESCENT_KNOCKBACK)
	BladeCrescent.spawn(get_tree().current_scene, origin, apex,
			VOLLEY_OUT_SPEED * _cadence_mult(), info, self)
	AudioManager.play_at(&"arcane_bolt", global_position)  # placeholder; revenant_crescent cue lands in M5
	_volley_cooldown = VOLLEY_COOLDOWN * _cadence_mult()
	_phase = Phase.STALK


## Wall-slide steering shared by the orbit and the disengage pick — blends out
## the into-wall component near the arena edge (CasterBoss._flee precedent),
## falling back to a tangential run along the wall if fully cornered.
func _wall_slide(dir: Vector3) -> Vector3:
	var into_wall := Vector3.ZERO
	if global_position.x > EDGE and dir.x > 0.0:
		into_wall.x = 1.0
	elif global_position.x < -EDGE and dir.x < 0.0:
		into_wall.x = -1.0
	if global_position.z > EDGE and dir.z > 0.0:
		into_wall.z = 1.0
	elif global_position.z < -EDGE and dir.z < 0.0:
		into_wall.z = -1.0
	if into_wall == Vector3.ZERO:
		return dir
	var wall := into_wall.normalized()
	var slide := dir - dir.project(wall)
	if slide.length() < 0.15:
		var tangent := Vector3(-wall.z, 0.0, wall.x)
		if tangent.dot(dir) < 0.0:
			tangent = -tangent
		slide = tangent
	return slide.normalized()


## Commit the landing point, telegraph the blink lane, hold still and flash
## eyes for the windup, then blink in and kick off the Cadence Combo.
func _begin_engage_windup() -> void:
	_phase = Phase.ENGAGE_WINDUP
	# state is already CHASE (called from _stalk) — the phase alone drives
	# motion here, the base FSM stays parked in CHASE throughout the windup.
	var wind_time := ENGAGE_WINDUP_TIME * _cadence_mult()
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var toward := to_target.normalized() if to_target.length() > 0.01 else -global_transform.basis.z
	_engage_landing = _target.global_position - toward * COMBO_RANGE
	_engage_landing.x = clampf(_engage_landing.x, -ARENA_HALF, ARENA_HALF)
	_engage_landing.z = clampf(_engage_landing.z, -ARENA_HALF, ARENA_HALF)
	_engage_landing.y = global_position.y
	GroundTelegraph.spawn_line(get_tree().current_scene, global_position, _engage_landing,
			BLINK_LANE_WIDTH, wind_time, BLINK_COLOR)
	_flash_eyes(wind_time)
	get_tree().create_timer(wind_time, false).timeout.connect(_finish_engage_windup)


func _finish_engage_windup() -> void:
	if not is_inside_tree() or state == State.DEAD or _phase != Phase.ENGAGE_WINDUP:
		return
	_reset_eyes()
	_blink_to(_engage_landing)
	_phase = Phase.COMBO
	_combo_index = 0
	_begin_combo_windup()


## RECOVER_VULN: hold still for the guaranteed punish window, then disengage.
func _begin_recover_vuln() -> void:
	_phase = Phase.RECOVER_VULN
	_state_time = 0.0
	get_tree().create_timer(RECOVER_VULN_TIME * _cadence_mult(), false).timeout.connect(_finish_recover_vuln)


func _finish_recover_vuln() -> void:
	if not is_inside_tree() or state == State.DEAD or _phase != Phase.RECOVER_VULN:
		return
	_begin_disengage()


## Pick a mid-range disengage point away from the player, wall-slid and
## clamped to the arena, blink there, and reset for another stalk cycle.
func _begin_disengage() -> void:
	_phase = Phase.DISENGAGE
	# state is already CHASE at every call site (from _stalk, from the vuln
	# timer, or from _end_stun) — no base state transition needed here.
	var away := global_position - _target.global_position
	away.y = 0.0
	var away_dir := away.normalized() if away.length() > 0.01 else Vector3(0.0, 0.0, 1.0)
	away_dir = _wall_slide(away_dir)
	var dest := _target.global_position + away_dir * DISENGAGE_DIST
	_blink_to(dest)
	_engage_cooldown = ENGAGE_COOLDOWN * _cadence_mult()
	_chip_hits = 0
	_phase = Phase.STALK
	_reset_combo()


## The Cadence Combo: three fixed beats (Slash, Backhand, Overhead finisher)
## driven as a sub-phase machine that stays in State.CHASE the whole time
## (Juggernaut-charge precedent — BossEnemy._chase / ChargePhase), since the
## base WINDUP->ATTACK->RECOVER auto-transitions only allow one shared
## data.windup_time/recover_time and mutating the shared EnemyData resource
## per hit is forbidden.
func _tick_combo(delta: float) -> void:
	_combo_timer += delta
	match _combo_beat:
		ComboBeat.WINDUP:
			_hold_still()
			if _combo_timer >= COMBO_WINDUPS[_combo_index] * _cadence_mult():
				_begin_combo_strike()
		ComboBeat.STRIKE:
			# Melee strikes ride a short lunge (like the base ATTACK state), then
			# hand off to recover; the overhead skips this beat (it advances to
			# RECOVER on impact from _begin_combo_strike).
			velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
			if _combo_timer >= ATTACK_ACTIVE_TIME:
				_begin_combo_recover()
		ComboBeat.RECOVER:
			_hold_still()
			if _combo_timer >= COMBO_RECOVERS[_combo_index] * _cadence_mult():
				_advance_combo()


## Lock facing, commit the strike, and play the windup tell for the current
## hit. Hit 2 (overhead finisher) additionally commits its impact point and
## telegraphs the ground AoE up front.
func _begin_combo_windup() -> void:
	_combo_beat = ComboBeat.WINDUP
	_combo_timer = 0.0
	_face_locked = true
	var wind_time: float = COMBO_WINDUPS[_combo_index] * _cadence_mult()
	if _material != null:
		_kill_color_tween()
		_color_tween = create_tween()
		_color_tween.tween_property(_material, "albedo_color", WINDUP_COLOR, wind_time)
	_flash_eyes(wind_time)
	if _combo_index == 2:
		var forward := -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		_overhead_point = global_position + forward * OVERHEAD_IMPACT_DISTANCE
		_overhead_point.y = 0.05
		GroundTelegraph.spawn(get_tree().current_scene, _overhead_point,
				OVERHEAD_INNER_RADIUS, wind_time)
		_tween_fist(BOSS_FIST_OVERHEAD_WINDUP, wind_time)
	else:
		_tween_fist(BOSS_FIST_WINDUP, wind_time)


func _begin_combo_strike() -> void:
	_combo_beat = ComboBeat.STRIKE
	_combo_timer = 0.0
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _resting_color()
	_reset_eyes()
	if _combo_index == 2:
		# Overhead finisher: instantaneous ground AoE, straight to recover.
		_tween_fist(BOSS_FIST_OVERHEAD_STRIKE, 0.1)
		_overhead_impact()
		_begin_combo_recover()
		return
	# Melee slash: live hitbox + a forward lunge so the blade reaches (the
	# blink lands the boss a couple metres out). The STRIKE beat runs for
	# ATTACK_ACTIVE_TIME carrying the lunge before _tick_combo hands to recover.
	hitbox.activate(
		AttackInfo.new(self, data.damage * _dmg_mult, data.knockback), ATTACK_ACTIVE_TIME)
	# A perfect block inside activate() can stun us synchronously — bail so a
	# parried melee hit doesn't lunge (stun() already reset the combo).
	if state != State.CHASE:
		return
	_tween_fist(BOSS_FIST_STRIKE, ATTACK_ACTIVE_TIME * 0.5)
	var dir := _target.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
		velocity.x = dir.x * move_speed() * COMBO_LUNGE_MULT
		velocity.z = dir.z * move_speed() * COMBO_LUNGE_MULT


## The overhead finisher lands as a ground AoE through the player hurtbox,
## not a hitbox — mirrors BossEnemy._slam_impact exactly in ordering: VFX and
## minion shove land first, the player hit lands last (a perfect block can
## synchronously stun us mid receive_hit(), so hitting the player last means
## a parry can't skip the rest of the feedback).
func _overhead_impact() -> void:
	AudioManager.play(&"hammer_slam")  # placeholder; revenant_overhead cue lands in M5
	BlastVfx.spawn(get_tree().current_scene, _overhead_point, OVERHEAD_OUTER_RADIUS,
			GroundTelegraph.ENEMY_COLOR, 0.12, 0.3)
	ShardBurst.spawn(get_tree().current_scene, _overhead_point + Vector3(0.0, 0.2, 0.0),
			Color(BLINK_COLOR.r, BLINK_COLOR.g, BLINK_COLOR.b), 12, 7.0, 0.14)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.add_shake(0.4)
	for minion: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(minion) or minion == self or not minion.is_inside_tree():
			continue
		var off := minion.global_position - _overhead_point
		off.y = 0.0
		if off.length() <= OVERHEAD_INNER_RADIUS and off.length() > 0.01:
			minion.apply_shove(off.normalized() * OVERHEAD_KNOCKBACK)
	# Player hit last — full damage + knockback inside, splash outside.
	if player != null:
		var pd := player.global_position - _overhead_point
		pd.y = 0.0
		var d := pd.length()
		if d <= OVERHEAD_OUTER_RADIUS:
			var full := data.damage * _dmg_mult * OVERHEAD_DMG_MULT
			var dmg := full if d <= OVERHEAD_INNER_RADIUS else full * OVERHEAD_SPLASH_MULT
			var kb := OVERHEAD_KNOCKBACK if d <= OVERHEAD_INNER_RADIUS else 0.0
			var hurtbox := player.get_node_or_null(^"Hurtbox") as HurtboxComponent
			if hurtbox != null:
				hurtbox.receive_hit(AttackInfo.new(self, dmg, kb))


## Unlock facing so the player can reposition between hits, and decay the
## blade pose back toward rest for the recover beat.
func _begin_combo_recover() -> void:
	_combo_beat = ComboBeat.RECOVER
	_combo_timer = 0.0
	_face_locked = false
	_hold_still()
	_tween_fist(BOSS_FIST_REST, COMBO_RECOVERS[_combo_index] * _cadence_mult())


## Advance to the next hit, or — after the 3rd — hand off to the existing
## vulnerable window.
func _advance_combo() -> void:
	_combo_index += 1
	if _combo_index >= COMBO_HIT_COUNT:
		_reset_combo()
		_begin_recover_vuln()
		return
	_begin_combo_windup()


## Reset the combo sub-state — called whenever the combo is abandoned
## (stun, disengage) or completed, so the next engage always starts at hit 0.
func _reset_combo() -> void:
	_combo_index = 0
	_combo_beat = ComboBeat.WINDUP
	_combo_timer = 0.0
	_face_locked = false
	_tween_fist(BOSS_FIST_REST, 0.2)


## Teal blink: clamp to the arena, VFX at both ends, teleport, placeholder SFX.
func _blink_to(dest: Vector3) -> void:
	dest.x = clampf(dest.x, -ARENA_HALF, ARENA_HALF)
	dest.z = clampf(dest.z, -ARENA_HALF, ARENA_HALF)
	dest.y = global_position.y
	var scene := get_tree().current_scene
	var origin := global_position
	BlastVfx.spawn(scene, origin + Vector3(0.0, 1.0, 0.0), BLINK_RADIUS, BLINK_COLOR, 0.6, 0.25)
	ShardBurst.spawn(scene, origin + Vector3(0.0, 1.0, 0.0), Color(BLINK_COLOR.r, BLINK_COLOR.g, BLINK_COLOR.b), 10, 6.0, 0.12)
	global_position = dest
	BlastVfx.spawn(scene, dest + Vector3(0.0, 1.0, 0.0), BLINK_RADIUS, BLINK_COLOR, 0.6, 0.25)
	ShardBurst.spawn(scene, dest + Vector3(0.0, 1.0, 0.0), Color(BLINK_COLOR.r, BLINK_COLOR.g, BLINK_COLOR.b), 10, 6.0, 0.12)
	AudioManager.play_at(&"dash", global_position)  # placeholder; revenant_blink cue lands in M5


func _face_target() -> void:
	if _face_locked:
		return
	super()


func _on_damaged(info: AttackInfo) -> void:
	super(info)
	if state == State.DEAD:
		return
	_chip_hits += 1
	if not _enraged and health.current / health.max_health <= ENRAGE_HP_FRACTION:
		_enrage()


## Low-HP finale climax: a pure timing ramp (see _cadence_mult), one-shot —
## the teal trim burns brighter for the rest of the fight as the readable tell.
func _enrage() -> void:
	_enraged = true
	if _trim_material != null:
		var tween := create_tween()
		tween.tween_property(_trim_material, "emission_energy_multiplier",
				ENRAGE_TRIM_EMISSION, 0.4)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.add_shake(0.5)


## A parry-stun is itself a punish window: clean up any pending blink/facing
## lock and combo sub-state, let the base stun play out, then disengage once
## it ends rather than resuming whatever phase was interrupted.
func stun(duration: float) -> void:
	if _phase == Phase.COMBO:
		_reset_combo()
	_face_locked = false
	_disengage_after_stun = true
	super(duration)
	_tween_fist(BOSS_FIST_REST, 0.2)  # base stun() tweens the base FIST_REST pose; override it


func _end_stun() -> void:
	super()
	if _disengage_after_stun:
		_disengage_after_stun = false
		_begin_disengage()


## Cancel any pending blink/hitbox/combo state before handing off to the
## shared boss death spectacle.
func _on_died() -> void:
	_reset_combo()
	hitbox.deactivate()
	super()
