class_name CasterBoss
extends BossBase
## THE HIEROPHANT: a slow, kiting caster boss. It backs away when the player
## closes, sliding along the arena walls rather than pinning itself into a
## corner, and casts from range. This milestone wires kiting + a filler Arcane
## Bolt; the repulse retaliation and Triple Fireball land next.

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

enum Spell { NONE, BOLT }

var _cast_lockout := 0.0
var _bolt_cd := 0.0
var _pending_spell := Spell.NONE
var _orb_material: StandardMaterial3D
var _staff_rest := Vector3.ZERO


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


## Cast priority (Eruption > Fireball > Bolt) — only the Bolt exists this
## milestone; the others slot in ahead of it later.
func _choose_spell() -> Spell:
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
		_color_tween.tween_property(_material, "albedo_color", WINDUP_COLOR, data.windup_time)
	_flash_eyes(data.windup_time)


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


func _staff_muzzle() -> Vector3:
	var orb := get_node_or_null(^"FistPivot/Orb") as Node3D
	return orb.global_position if orb != null else global_position + Vector3(0.0, 2.0, 0.0)


func _orb_flare() -> void:
	if _orb_material == null:
		return
	_orb_material.emission_energy_multiplier = ORB_FLARE
	var tween := create_tween()
	tween.tween_property(_orb_material, "emission_energy_multiplier", 1.5, 0.3)


## The base stun tweens the fist toward its small-enemy FIST_REST; restore the
## staff to its actual rest afterwards, and drop any queued cast.
func stun(duration: float) -> void:
	_pending_spell = Spell.NONE
	super(duration)
	_tween_fist(_staff_rest, 0.2)
