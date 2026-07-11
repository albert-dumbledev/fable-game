class_name Warhammer
extends Weapon
## Two-handed slam weapon: no shield and no block (can_block=false in the
## data). LMB hauls the head up as a telegraph, then crashes it down in
## front of the player — everything near the impact point takes full damage,
## a wider ring takes splash damage, and the whole pack gets shoved.

const REST_POS := Vector3(0.35, -0.25, 0.0)
const REST_ROT := Vector3(25.0, -12.0, 6.0)
const RAISED_POS := Vector3(0.12, 0.28, 0.15)
const RAISED_ROT := Vector3(80.0, 0.0, 0.0)
const SLAM_POS := Vector3(0.0, -0.5, -0.35)
const SLAM_ROT := Vector3(-75.0, 0.0, 0.0)
## Where the head lands: this far in front of the player, at ground level.
const IMPACT_DISTANCE := 2.2
const INNER_RADIUS := 1.6
const OUTER_RADIUS := 3.6
## Primary slam covers a 210° frontal arc (this is the half-angle), so there
## is a ~150° blind wedge directly behind the player to punish careless facing.
const SLAM_ARC_HALF_DEG := 105.0
## The outer ring deals no damage — it only shoves, at reduced force, to
## create space rather than pile on damage.
const OUTER_SHOVE_MULT := 0.6
const SHOVE_FORCE := 9.0
const SHOCKWAVE_COLOR := Color(1.0, 0.75, 0.35, 0.55)
const DUST_COLOR := Color(0.7, 0.62, 0.52, 0.32)
## Aftershock (unique boon): a second, weaker shock at the same spot.
const AFTERSHOCK_DELAY := 0.45
const AFTERSHOCK_DAMAGE_MULT := 0.4
const AFTERSHOCK_AOE_MULT := 0.7
const AFTERSHOCK_SHOVE_MULT := 0.6
## Bone Breaker (unique boon): fraction of slam damage dealt when a shoved
## enemy slams into a wall.
const BONE_BREAKER_MULT := 0.3
## Seismic Slam (RMB): a long committed overhead windup, then a slam that
## sends a GroundShockwave forward in a straight line.
const WAVE_WINDUP := 0.6
const WAVE_SLAM_TIME := 0.15
const WAVE_SETTLE_TIME := 0.35
const WAVE_COOLDOWN := 6.0
const WAVE_DAMAGE_MULT := 1.2
## The Seismic wave (and its Fault Line fissure) run the full length of the arena.
const WAVE_RANGE := 40.0
const WAVE_RAISED_POS := Vector3(0.05, 0.45, 0.2)
const WAVE_RAISED_ROT := Vector3(95.0, 0.0, 0.0)
## Real-time freeze frame when the slam actually catches something —
## longer than the sword's: this is the heavy weapon.
const HIT_PAUSE := 0.05
## Crashing Leap (Shift mobility): the landing slam hits a full 360° circle for
## a fraction of the primary's damage — it is an attack, not an escape. Core
## enemies are briefly staggered so leaping into a pack is not a suicide of
## instant retaliation windups (same lesson as the Phase 5 gather-stun guards).
const LEAP_DAMAGE_MULT := 0.8
const LEAP_STAGGER := 0.3
## Fault Line (Aspect): seconds shaved off the 6s Seismic cooldown per unique
## enemy the wave or its fissure catches. Read by GroundShockwave and QuakeFissure.
const FAULT_LINE_REFUND := 0.75
## Epicenter (Aspect): the four Crashing Leap waves each deal this fraction of
## the Seismic wave's damage, so the aimed RMB stays the higher-value cast.
const EPICENTER_WAVE_MULT := 0.75

@onready var hammer_pivot: Node3D = $HammerPivot
@onready var handle_mesh: MeshInstance3D = $HammerPivot/HandleMesh

var _swing_tween: Tween


func _swing_sound() -> StringName:
	return &"hammer_swing"


func mobility_id() -> StringName:
	return &"hammer_leap"


func _ready() -> void:
	hammer_pivot.position = REST_POS
	hammer_pivot.rotation_degrees = REST_ROT
	# Cylinder axis is Y; lay the handle along the pivot's -Z reach.
	handle_mesh.rotation_degrees.x = 90.0


func _do_attack(duration: float) -> void:
	var damage := weapon_data.damage + stats.get_stat(Stats.DAMAGE)
	if _swing_tween != null:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_parallel(true)
	# 1) Haul the hammer up overhead — the telegraph.
	_swing_tween.tween_property(hammer_pivot, "position", RAISED_POS, duration * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", RAISED_ROT, duration * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2) Crash down fast; damage lands the moment the head hits the ground.
	_swing_tween.chain().tween_property(hammer_pivot, "position", SLAM_POS, duration * 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", SLAM_ROT, duration * 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.chain().tween_callback(_impact.bind(damage))
	# 3) Drag it back up to the ready stance.
	_swing_tween.chain().tween_property(hammer_pivot, "position", REST_POS, duration * 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", REST_ROT, duration * 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _do_secondary() -> void:
	_secondary_cooldown = WAVE_COOLDOWN
	# The whole committed animation locks the primary slam out.
	_cooldown = maxf(_cooldown, WAVE_WINDUP + WAVE_SLAM_TIME + WAVE_SETTLE_TIME)
	var damage := (weapon_data.damage + stats.get_stat(Stats.DAMAGE)) * WAVE_DAMAGE_MULT
	if _swing_tween != null:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_parallel(true)
	# 1) Slow haul high overhead — a much longer telegraph than the primary.
	_swing_tween.tween_property(hammer_pivot, "position", WAVE_RAISED_POS, WAVE_WINDUP) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(
		hammer_pivot, "rotation_degrees", WAVE_RAISED_ROT, WAVE_WINDUP
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# 2) Crash down.
	_swing_tween.chain().tween_property(
		hammer_pivot, "position", SLAM_POS, WAVE_SLAM_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", SLAM_ROT, WAVE_SLAM_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.chain().tween_callback(_wave_impact.bind(damage))
	# 3) Settle back to ready.
	_swing_tween.chain().tween_property(
		hammer_pivot, "position", REST_POS, WAVE_SETTLE_TIME
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(
		hammer_pivot, "rotation_degrees", REST_ROT, WAVE_SETTLE_TIME
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _wave_impact(damage: float) -> void:
	if wielder == null or not is_inside_tree():
		return
	var forward := -wielder.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var origin := wielder.global_position + forward * 1.2
	origin.y = 0.1
	AudioManager.play(&"hammer_slam")
	var wave_shove := GroundShockwave.SHOVE * stats.get_stat(Stats.HAMMER_SHOVE)
	var wave_player := wielder as Player
	var wave_drag := wave_player != null and wave_player.has_ability(&"wave_drag")
	var wave_pull := wave_player != null and wave_player.has_ability(&"slam_pull")
	var aoe := stats.get_stat(Stats.HAMMER_AOE)
	# Pass self so Fault Line can refund the cooldown per enemy the wave catches.
	GroundShockwave.spawn(get_tree().current_scene, origin,
			AttackInfo.new(wielder, damage), forward, aoe,
			wave_shove, wave_drag, wave_pull, WAVE_RANGE, self)
	# Fault Line: lay a lingering fissure along the wave's corridor. Its width
	# matches the wave's swept diameter so the crack tracks where the wave passed.
	if wave_player != null and wave_player.has_ability(&"fault_line"):
		var fissure_width := GroundShockwave.HIT_RADIUS * 2.0 * aoe
		QuakeFissure.spawn(get_tree().current_scene, origin, forward,
				WAVE_RANGE, fissure_width, self)
	BlastVfx.spawn(get_tree().current_scene, origin, 1.6, SHOCKWAVE_COLOR, 0.15, 0.2)
	var player := wielder as Player
	if player != null:
		player.add_shake(0.6)


## Crashing Leap windup: haul the hammer overhead so it is cocked and ready
## through the ascent + aim hover, crashing down the instant the earthshaker
## lands. Called by Player._begin_leap at takeoff with a duration comfortably
## longer than the raise tween needs — the pose just holds until leap_slam().
func leap_windup(airtime: float) -> void:
	if _swing_tween != null:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_parallel(true)
	_swing_tween.tween_property(hammer_pivot, "position", RAISED_POS, airtime * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", RAISED_ROT, airtime * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Crashing Leap payoff: on landing, a 360° slam centered on the player — 0.8×
## primary damage across the WHOLE radius (full-damage circle, no dead outer
## ring), full shove, and a brief stagger on everything caught.
## Called by Player._land_leap_crash once the aimed dive touches down.
func leap_slam() -> void:
	if wielder == null or not is_inside_tree():
		return
	var forward := -wielder.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var point := wielder.global_position
	point.y = 0.1
	var damage := (weapon_data.damage + stats.get_stat(Stats.DAMAGE)) * LEAP_DAMAGE_MULT
	var aoe := stats.get_stat(Stats.HAMMER_AOE)
	var shove := SHOVE_FORCE * stats.get_stat(Stats.HAMMER_SHOVE)
	AudioManager.play(&"hammer_slam")
	# Full-damage circle: the leap is a committed nuke, so the whole radius
	# deals damage (full_damage=true), not the primary slam's inner-core-only split.
	if _slam(point, forward, damage, aoe, shove, 180.0, LEAP_STAGGER, true) > 0:
		FreezeFrame.hit_pause(HIT_PAUSE)
	var player := wielder as Player
	if player != null:
		player.add_shake(0.6)
		# Epicenter: the landing also fires a four-way Seismic volley.
		if player.has_ability(&"leap_epicenter"):
			_erupt_epicenter(point, forward, player)
	# Crash the hammer down from the windup pose, then recover to ready.
	if _swing_tween != null:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_parallel(true)
	_swing_tween.tween_property(hammer_pivot, "position", SLAM_POS, 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", SLAM_ROT, 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.chain().tween_property(hammer_pivot, "position", REST_POS, 0.35) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(hammer_pivot, "rotation_degrees", REST_ROT, 0.35) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## Epicenter (Aspect): the Crashing Leap landing erupts four Seismic waves out
## the cardinal points of facing — forward, back, and the two perpendiculars —
## each at a fraction of the aimed wave's damage. Full wave boons ride along
## (Riptide drags, Implosion pulls), and self is passed so Fault Line refunds the
## RMB for free when both aspects are owned.
func _erupt_epicenter(origin: Vector3, forward: Vector3, player: Player) -> void:
	var wave_damage := (weapon_data.damage + stats.get_stat(Stats.DAMAGE)) \
			* WAVE_DAMAGE_MULT * EPICENTER_WAVE_MULT
	var wave_shove := GroundShockwave.SHOVE * stats.get_stat(Stats.HAMMER_SHOVE)
	var aoe := stats.get_stat(Stats.HAMMER_AOE)
	var drag := player.has_ability(&"wave_drag")
	var pull := player.has_ability(&"slam_pull")
	# Rightward perpendicular of the horizontal facing; left is its negation.
	var right := Vector3(forward.z, 0.0, -forward.x)
	for dir: Vector3 in [forward, -forward, right, -right]:
		GroundShockwave.spawn(get_tree().current_scene, origin,
				AttackInfo.new(wielder, wave_damage), dir, aoe,
				wave_shove, drag, pull, WAVE_RANGE, self)


## The slam is a ground AoE, not a hitbox sweep: full damage inside
## INNER_RADIUS of the impact point, splash out to OUTER_RADIUS, and a
## radial shove for everything caught. Damage flows through hurtboxes so
## numbers, drops, and mitigation all work as usual. Radii scale with the
## hammer_aoe stat (Wide Tremor boon).
func _impact(damage: float) -> void:
	if wielder == null or not is_inside_tree():
		return
	var forward := -wielder.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var point := wielder.global_position + forward * IMPACT_DISTANCE
	var aoe := stats.get_stat(Stats.HAMMER_AOE)
	var shove := SHOVE_FORCE * stats.get_stat(Stats.HAMMER_SHOVE)
	AudioManager.play(&"hammer_slam")
	if _slam(point, forward, damage, aoe, shove) > 0:
		FreezeFrame.hit_pause(HIT_PAUSE)
	var player := wielder as Player
	if player != null:
		player.add_shake(0.5)
		if player.has_ability(&"aftershock"):
			get_tree().create_timer(AFTERSHOCK_DELAY, false).timeout.connect(
					_aftershock.bind(point, forward, damage, aoe, shove))


func _aftershock(point: Vector3, forward: Vector3, damage: float, aoe: float,
		shove: float) -> void:
	if not is_inside_tree():
		return
	_slam(point, forward, damage * AFTERSHOCK_DAMAGE_MULT, aoe * AFTERSHOCK_AOE_MULT,
			shove * AFTERSHOCK_SHOVE_MULT)


## Returns how many enemies took damage, so callers can gate impact
## feedback on the slam actually catching something.
## `full_damage` collapses the inner/outer split so the whole radius out to
## OUTER_RADIUS deals full damage + full shove (used by the Crashing Leap).
func _slam(point: Vector3, forward: Vector3, damage: float, aoe_mult: float,
		shove: float, arc_half_deg: float = SLAM_ARC_HALF_DEG,
		stagger: float = 0.0, full_damage: bool = false) -> int:
	var inner := INNER_RADIUS * aoe_mult
	var outer := OUTER_RADIUS * aoe_mult
	var hit_count := 0
	var player := wielder as Player
	var mass_driver := player != null and player.has_ability(&"mass_driver")
	# Bone Breaker wall-slams on shove_impact; Mass Driver also wall-slams (walls
	# included) and additionally drives enemies through their neighbours.
	var wall_damage := damage * BONE_BREAKER_MULT \
			if (player != null and player.has_ability(&"shove_impact")) or mass_driver else 0.0
	var through_damage := damage * BONE_BREAKER_MULT if mass_driver else 0.0
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - point
		offset.y = 0.0
		var dist := offset.length()
		if dist > outer:
			continue
		# 210° frontal arc, measured from the player so the blind wedge sits at
		# your back. Enemies right on top of you (tiny vector) always count.
		var to_enemy := enemy.global_position - wielder.global_position
		to_enemy.y = 0.0
		if to_enemy.length() > 0.1 \
				and rad_to_deg(forward.angle_to(to_enemy)) > arc_half_deg:
			continue
		if dist <= inner or full_damage:
			# Damage core: full damage, meaty contact sound, full-force shove.
			var hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
			if hurtbox != null:
				var info := AttackInfo.new(wielder, damage)
				info.hit_sound = &"melee_hit"
				hurtbox.receive_hit(info)
				hit_count += 1
			if dist > 0.01:
				enemy.apply_shove(offset.normalized() * shove, wall_damage, wielder,
						through_damage)
			if stagger > 0.0:
				enemy.stun(stagger)
		else:
			# Outer control ring: no damage, shove only, at reduced force.
			# Bone Breaker's wall_damage still applies here — that's the
			# intended way to convert control into damage.
			if dist > 0.01:
				enemy.apply_shove(offset.normalized() * shove * OUTER_SHOVE_MULT,
						wall_damage, wielder, through_damage)
	# Hot core flash for the damage ring, dusty ripple for the control ring.
	BlastVfx.spawn(get_tree().current_scene, point, inner, SHOCKWAVE_COLOR, 0.12, 0.22)
	BlastVfx.spawn(get_tree().current_scene, point, outer, DUST_COLOR, 0.05, 0.4)
	return hit_count
