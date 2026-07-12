class_name CasterBoss
extends BossBase
## THE HIEROPHANT: a slow, kiting caster boss. It backs away when the player
## closes, sliding along the arena walls rather than pinning itself into a
## corner, and casts from range. Kiting + Arcane Bolt filler + Triple Fireball
## + the repulse anti-melee retaliation + Arcane Eruption are all wired.

const RETREAT_RANGE := 13.0
const ARENA_HALF := 18.5
## Past this fraction of the half-extent, fleeing blends in a wall-slide.
const EDGE := ARENA_HALF * 0.85
## Minimum gap between any two casts, on top of per-spell cooldowns.
const CAST_LOCKOUT := 1.2
const ORB_FLARE := 5.0
## Arcane Bolt — cheap constant pressure so the player can't just stroll in.
const BOLT_COOLDOWN := 2.5
const BOLT_SPEED := 16.0
const BOLT_DAMAGE_MULT := 0.6
const PROJECTILE_SCENE := preload("res://actors/enemies/Projectile.tscn")
## Triple Fireball — the main spell: a horizontal fan centred on the player.
const FIREBALL_COOLDOWN := 7.0
const FIREBALL_KNOCKBACK := 10.0
const FIREBALL_FAN_DEG := 14.0
## Light lead so the centre ball threatens where the player is going, not where
## they were — kept small because the fireballs are deliberately slow.
const FIREBALL_LEAD := 0.4
## Repulse — the anti-melee retaliation. The first hit taken arms a fuse; when
## it elapses the player is flung clear (0 damage). Not blockable/parryable
## (direct shove, not a hurtbox hit); a dash still escapes it. The fuse only
## ticks while not stunned, so a remote parry-stun stretches the burst window.
const REPULSE_FUSE := 1.5
const REPULSE_IMPULSE := 26.0
## Arcane Eruption — the repositioning challenge: three chained rifts, each
## telegraphed then erupting where the player stood when that rift began. Forces
## constant movement and combos with the repulse (getting shoved into a rift).
const ERUPTION_COOLDOWN := 10.0
const ERUPTION_RIFTS := 3
const ERUPTION_RIFT_INTERVAL := 0.55
const ERUPTION_TELEGRAPH := 0.8
const ERUPTION_RADIUS := 2.6
const ERUPTION_DAMAGE_MULT := 1.2
const ERUPTION_SHOVE := 18.0
const ERUPTION_COLOR := Color(0.7, 0.35, 1.0, 0.5)  # violet rift, distinct from the red slam/boulder telegraph

enum Spell { NONE, BOLT, FIREBALL, ERUPTION }

var _cast_lockout := 0.0
var _bolt_cd := 0.0
var _fireball_cd := 0.0
var _eruption_cd := 0.0
var _pending_spell := Spell.NONE
var _orb_material: StandardMaterial3D
var _staff_rest := Vector3.ZERO
var _fuse_armed := false
var _fuse_remaining := 0.0


func _ready() -> void:
	super()
	_staff_rest = fist_pivot.position
	var orb := get_node_or_null(^"FistPivot/Orb") as MeshInstance3D
	if orb != null:
		var mat := orb.get_active_material(0)
		if mat != null:
			_orb_material = mat.duplicate() as StandardMaterial3D
			orb.material_override = _orb_material


func _chase() -> void:
	var delta := get_physics_process_delta_time()
	_cast_lockout = maxf(0.0, _cast_lockout - delta)
	_bolt_cd = maxf(0.0, _bolt_cd - delta)
	_fireball_cd = maxf(0.0, _fireball_cd - delta)
	_eruption_cd = maxf(0.0, _eruption_cd - delta)
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	# Kite: back away when the player closes inside RETREAT_RANGE.
	if dist < RETREAT_RANGE:
		_flee(to_target, dist)
		return
	# Far enough — hold and cast from range.
	_hold_still()
	if dist <= data.attack_range and _cast_lockout <= 0.0:
		var spell := _choose_spell()
		if spell != Spell.NONE:
			_pending_spell = spell
			_begin_windup()


## Flee directly away, but near a wall blend in a tangential slide so the boss
## runs along it instead of pinning into a corner. Cornered (the away vector is
## almost fully into the wall) → commit to the lateral direction that leads
## away from the player.
func _flee(to_target: Vector3, dist: float) -> void:
	var away := (-to_target / dist) if dist > 0.01 else Vector3(0.0, 0.0, 1.0)
	var into_wall := Vector3.ZERO
	if global_position.x > EDGE and away.x > 0.0:
		into_wall.x = 1.0
	elif global_position.x < -EDGE and away.x < 0.0:
		into_wall.x = -1.0
	if global_position.z > EDGE and away.z > 0.0:
		into_wall.z = 1.0
	elif global_position.z < -EDGE and away.z < 0.0:
		into_wall.z = -1.0
	var move_dir := away
	if into_wall != Vector3.ZERO:
		var wall := into_wall.normalized()
		var slide := away - away.project(wall)  # strip the into-wall component
		if slide.length() < 0.15:
			# Cornered: run along the wall, away-from-player side.
			var tangent := Vector3(-wall.z, 0.0, wall.x)
			if tangent.dot(away) < 0.0:
				tangent = -tangent
			slide = tangent
		move_dir = slide.normalized()
	velocity.x = move_dir.x * move_speed()
	velocity.z = move_dir.z * move_speed()


## Cast priority: Eruption > Fireball > Bolt.
func _choose_spell() -> Spell:
	if _eruption_cd <= 0.0:
		return Spell.ERUPTION
	if _fireball_cd <= 0.0:
		return Spell.FIREBALL
	if _bolt_cd <= 0.0:
		return Spell.BOLT
	return Spell.NONE


## Reuse the base WINDUP colour/eye tell, but NOT its fist pose — the staff is
## boss-scale and its own rest is elsewhere, so we leave it put and let the orb
## flare be the cast tell.
func _begin_windup() -> void:
	_set_state(State.WINDUP)
	if _material != null:
		_kill_color_tween()
		_color_tween = create_tween()
		_color_tween.tween_property(_material, "albedo_color", WINDUP_COLOR, windup_time())
	_flash_eyes(windup_time())


func _begin_attack() -> void:
	_set_state(State.ATTACK)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _resting_color()
	_reset_eyes()
	_cast_lockout = CAST_LOCKOUT
	_orb_flare()
	match _pending_spell:
		Spell.BOLT:
			_cast_bolt()
		Spell.FIREBALL:
			_cast_fireball()
		Spell.ERUPTION:
			_cast_eruption()
	_pending_spell = Spell.NONE


func _begin_recover() -> void:
	_set_state(State.RECOVER)  # no fist tween — staff stays at its rest


func _cast_bolt() -> void:
	_bolt_cd = BOLT_COOLDOWN
	if _target == null:
		return
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	if proj == null:
		return
	proj.speed = BOLT_SPEED
	var spawn_pos := _staff_muzzle()
	var aim := _target.global_position + Vector3(0.0, 1.0, 0.0) - spawn_pos
	proj.setup(AttackInfo.new(self, data.damage * BOLT_DAMAGE_MULT, data.knockback), aim)
	get_tree().current_scene.add_child(proj)
	proj.global_position = spawn_pos
	AudioManager.play_at(&"arcane_bolt", global_position)


func _cast_fireball() -> void:
	_fireball_cd = FIREBALL_COOLDOWN
	if _target == null:
		return
	var muzzle := _staff_muzzle()
	var target_vel := Vector3.ZERO
	if _target is CharacterBody3D:
		target_vel = (_target as CharacterBody3D).velocity
	var predicted := _target.global_position + Vector3(0.0, 1.0, 0.0) + target_vel * FIREBALL_LEAD
	var center := predicted - muzzle
	if center.length() < 0.01:
		center = -global_transform.basis.z
	# Fan the three balls horizontally around the aim: centre on the player,
	# flankers ±FIREBALL_FAN_DEG. Sidestepping the centre walks toward a flanker.
	for angle_deg: float in [-FIREBALL_FAN_DEG, 0.0, FIREBALL_FAN_DEG]:
		var dir := center.rotated(Vector3.UP, deg_to_rad(angle_deg))
		EnemyFireball.spawn(get_tree().current_scene, muzzle, dir,
				AttackInfo.new(self, data.damage * _dmg_mult, FIREBALL_KNOCKBACK))
	AudioManager.play_at(&"fireball_shoot", global_position)


## Kick off the chained rifts. Each rift is scheduled independently; the whole
## sequence runs on its own timers, outliving this cast's RECOVER, so the caster
## resumes kiting/casting while the rifts play out. A rift captured the player's
## position at ITS start, so standing still eats rift two.
func _cast_eruption() -> void:
	_eruption_cd = ERUPTION_COOLDOWN
	for i: int in ERUPTION_RIFTS:
		get_tree().create_timer(i * ERUPTION_RIFT_INTERVAL, false).timeout.connect(_spawn_rift)


func _spawn_rift() -> void:
	if not is_inside_tree() or state == State.DEAD or _target == null:
		return
	var pos := _target.global_position
	pos.y = 0.05
	GroundTelegraph.spawn(get_tree().current_scene, pos, ERUPTION_RADIUS,
			ERUPTION_TELEGRAPH, ERUPTION_COLOR)
	get_tree().create_timer(ERUPTION_TELEGRAPH, false).timeout.connect(_erupt.bind(pos))


## The rift blows: damage the player through the hurtbox (knockback 0 — the pop
## comes from apply_shove instead) and launch them up-and-out. Shoves minions too.
func _erupt(pos: Vector3) -> void:
	if not is_inside_tree() or state == State.DEAD:
		return
	var scene := get_tree().current_scene
	AudioManager.play_at(&"eruption", pos)
	BlastVfx.spawn(scene, pos, ERUPTION_RADIUS, ERUPTION_COLOR, 0.5, 0.35)
	ShardBurst.spawn(scene, pos + Vector3(0.0, 0.2, 0.0), Color(0.6, 0.4, 1.0), 12, 8.0, 0.14)
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player != null:
		var off := player.global_position - pos
		off.y = 0.0
		if off.length() <= ERUPTION_RADIUS:
			var hurtbox := player.get_node_or_null(^"Hurtbox") as HurtboxComponent
			if hurtbox != null:
				hurtbox.receive_hit(AttackInfo.new(self,
						data.damage * _dmg_mult * ERUPTION_DAMAGE_MULT, 0.0))
			# Up-and-out pop (mostly vertical). Only the real Player has apply_shove.
			if player is Player:
				var out := off.normalized() if off.length() > 0.01 else Vector3.ZERO
				(player as Player).apply_shove(out * 7.0 + Vector3.UP * ERUPTION_SHOVE)
	for minion: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(minion) or minion == self or not minion.is_inside_tree():
			continue
		var moff := minion.global_position - pos
		moff.y = 0.0
		if moff.length() <= ERUPTION_RADIUS and moff.length() > 0.01:
			minion.apply_shove(moff.normalized() * 8.0)


func _staff_muzzle() -> Vector3:
	var orb := get_node_or_null(^"FistPivot/Orb") as Node3D
	return orb.global_position if orb != null else global_position + Vector3(0.0, 2.0, 0.0)


func _orb_flare() -> void:
	if _orb_material == null:
		return
	_orb_material.emission_energy_multiplier = ORB_FLARE
	var tween := create_tween()
	tween.tween_property(_orb_material, "emission_energy_multiplier", 1.5, 0.3)


## Repulse: the first hit taken arms the fuse. Later hits while armed don't
## reset/extend it — the base flash/damage-number handling runs first.
func _on_damaged(info: AttackInfo) -> void:
	super(info)
	if state == State.DEAD or _fuse_armed:
		return
	_fuse_armed = true
	_fuse_remaining = REPULSE_FUSE


## Ticks the repulse fuse in every live state except STUNNED — the base
## _chase only runs in CHASE, but the fuse must keep counting through a
## WINDUP/RECOVER cast too.
func _physics_process(delta: float) -> void:
	super(delta)
	if _fuse_armed and state != State.STUNNED and state != State.DEAD:
		_tick_fuse(delta)


func _tick_fuse(delta: float) -> void:
	_fuse_remaining -= delta
	# Tell: the orb brightens as the fuse fills, and pauses when the fuse does
	# (a parry-stun freezes the whole thing).
	if _orb_material != null:
		var fill := 1.0 - clampf(_fuse_remaining / REPULSE_FUSE, 0.0, 1.0)
		_orb_material.emission_energy_multiplier = lerpf(1.5, ORB_FLARE, fill)
	if _fuse_remaining <= 0.0:
		_fire_repulse()


## The pop: fling the player straight out (0 damage, unblockable) — unless they
## already left, in which case just disarm. Re-arms on the next hit taken.
func _fire_repulse() -> void:
	_fuse_armed = false
	if _orb_material != null:
		_orb_material.emission_energy_multiplier = 1.5
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist >= RETREAT_RANGE:
		return  # already gone — no point yeeting someone who left
	var away := to_player.normalized() if dist > 0.01 else Vector3(0.0, 0.0, 1.0)
	player.apply_shove(away * REPULSE_IMPULSE)
	player.add_shake(0.3)
	AudioManager.play_at(&"repulse", global_position)
	BlastVfx.spawn(get_tree().current_scene, global_position + Vector3(0.0, 0.5, 0.0),
			6.0, Color(0.6, 0.4, 1.0, 0.6), 0.5, 0.4)


## The base stun tweens the fist toward its small-enemy FIST_REST; restore the
## staff to its actual rest afterwards, and drop any queued cast.
func stun(duration: float) -> void:
	_pending_spell = Spell.NONE
	super(duration)
	_tween_fist(_staff_rest, 0.2)
