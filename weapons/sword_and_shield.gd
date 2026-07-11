class_name SwordAndShield
extends Weapon
## Starting weapon: melee arc in front of the camera plus a raiseable shield.
## The block *rule* (frontal cone) lives in Player.mitigate_hit; this class
## only owns the swing hitbox and viewmodel motion.

## Held low at the bottom-right, tip angled up-inward — a ready stance
## mirroring the shield's tucked idle rather than floating mid-screen.
const SWORD_REST_POS := Vector3(0.4, -0.28, 0.05)
const SWORD_REST_ROT := Vector3(35.0, 15.0, 10.0)
## Virtual shoulder the sword orbits during a slash. Handle and blade are
## rigidly locked to one arm direction from here, so the tip sweeps
## (ARM_LENGTH + blade) / ARM_LENGTH ≈ 3.5x further than the base.
const SHOULDER := Vector3(0.0, -0.45, -0.05)
const ARM_LENGTH := 0.4
## How far past the arc start the windup pulls back (radians), opposite
## the swing direction.
const WINDUP_ANGLE := 0.55
## Tucked low into the corner so it barely covers the screen when idle.
const SHIELD_REST_POS := Vector3(-0.55, -0.3, 0.1)
const SHIELD_REST_ROT := Vector3(-30.0, 35.0, 10.0)
const SHIELD_BLOCK_POS := Vector3(-0.08, 0.08, -0.12)
const SHIELD_BLOCK_ROT := Vector3.ZERO
## Real-time freeze frame per swing connect (coalesced by FreezeFrame).
const HIT_PAUSE := 0.03
## Blade Cyclone (unique boon): radial strike radius for a riposte swing.
## Widened +30% (was 2.8) to grow the sweep's AoE footprint.
const SWEEP_RADIUS := 3.64
## Second Wind (parry_heal): a lifesteal swing heals this fraction of the
## damage it deals, per enemy hit.
const LIFESTEAL_PCT := 0.25

@onready var hitbox: HitboxComponent = $Hitbox
@onready var sword_pivot: Node3D = $SwordPivot
@onready var shield_pivot: Node3D = $ShieldPivot
@onready var sword_model: Node3D = $SwordPivot/SwordModel
@onready var pencil_model: Node3D = $SwordPivot/PencilModel
@onready var shield_model: Node3D = $ShieldPivot/ShieldModel
@onready var postit_model: Node3D = $ShieldPivot/PostItModel
@onready var shield_face: MeshInstance3D = $ShieldPivot/ShieldModel/Face
@onready var postit_face: MeshInstance3D = $ShieldPivot/PostItModel/Note
@onready var blade: MeshInstance3D = $SwordPivot/SwordModel/Blade

var _swing_tween: Tween
var _shield_tween: Tween
var _flash_tween: Tween
var _swing_flip := false
var _shield_material: StandardMaterial3D
var _blade_material: StandardMaterial3D
var _riposte_tween: Tween
var _lifesteal_swing := false
var _swing_damage := 0.0
## Crescendo (riposte_chain): the active swing consumed a riposte, and whether
## its chain kill has already been credited (once per swing, however many
## enemies it drops).
var _riposte_swing := false
var _riposte_kill_logged := false


func _ready() -> void:
	sword_pivot.position = SWORD_REST_POS
	sword_pivot.rotation_degrees = SWORD_REST_ROT
	shield_pivot.position = SHIELD_REST_POS
	shield_pivot.rotation_degrees = SHIELD_REST_ROT
	hitbox.landed.connect(_on_hit_landed)
	Settings.changed.connect(_apply_style)
	_apply_style()
	var blade_mat := blade.get_active_material(0)
	if blade_mat != null:
		_blade_material = blade_mat.duplicate() as StandardMaterial3D
		_blade_material.emission_enabled = true
		_blade_material.emission = Color(1.0, 0.85, 0.3)
		_blade_material.emission_energy_multiplier = 0.0
		blade.material_override = _blade_material


func _on_hit_landed(hurtbox: HurtboxComponent) -> void:
	FreezeFrame.hit_pause(HIT_PAUSE)
	if _lifesteal_swing:
		var player := wielder as Player
		if player != null:
			player.heal(_swing_damage * LIFESTEAL_PCT)
	_try_riposte_chain(hurtbox)


## Crescendo (riposte_chain): a riposte swing that just killed an enemy feeds
## the chain. Attribution runs through the swing's own hit path — not the global
## enemy_killed, which swarm deaths would false-positive — and is credited at
## most once per swing. The hitbox's `landed` fires after receive_hit, so the
## resolved enemy's health already reflects this hit.
func _try_riposte_chain(hurtbox: HurtboxComponent) -> void:
	if not _riposte_swing or _riposte_kill_logged or hurtbox == null:
		return
	var player := wielder as Player
	if player == null or not player.has_ability(&"riposte_chain"):
		return
	var enemy := hurtbox.get_parent() as EnemyBase
	if enemy == null or enemy.health == null or enemy.health.current > 0.0:
		return
	_riposte_kill_logged = true
	player.notify_riposte_chain_kill()


## Swaps between the real models and the post-it/pencil easter egg
## (Settings.postit_mode, toggled by typing "postit" mid-run).
func _apply_style() -> void:
	var postit: bool = Settings.postit_mode
	sword_model.visible = not postit
	pencil_model.visible = postit
	shield_model.visible = not postit
	postit_model.visible = postit
	# Per-instance material on the active shield face so the block flash can
	# animate emission. Rebuilt on every settings change, so always reset the
	# energy — a duplicate taken mid-flash would otherwise stay lit forever.
	var face := postit_face if postit else shield_face
	var material := face.get_active_material(0)
	if material != null:
		_shield_material = material.duplicate() as StandardMaterial3D
		_shield_material.emission_enabled = true
		_shield_material.emission = Color(1.0, 1.0, 1.0)
		_shield_material.emission_energy_multiplier = 0.0
		face.material_override = _shield_material


func _do_attack(duration: float) -> void:
	var damage := weapon_data.damage + stats.get_stat(Stats.DAMAGE)
	var player := wielder as Player
	var riposte := player.consume_riposte() if player != null else 0.0
	if riposte > 0.0:
		damage *= 1.0 + riposte
		_flash_riposte(duration)
	# Crescendo tracks kills on riposte swings only, once per swing.
	_riposte_swing = riposte > 0.0
	_riposte_kill_logged = false
	var sweep := riposte > 0.0 and player != null and player.has_ability(&"riposte_sweep")
	_swing_damage = damage
	_lifesteal_swing = player != null and player.consume_lifesteal()
	var info := AttackInfo.new(wielder, damage)
	info.hit_sound = &"melee_hit"
	_swing_flip = not _swing_flip
	var side := 1.0 if _swing_flip else -1.0
	# Rigid arm-swing: the sword orbits the virtual SHOULDER. `dir` is the
	# arm direction; the handle sits ARM_LENGTH along it and the blade
	# points straight out along the same line, so base and tip share one
	# angular sweep — no independent translation to fight the rotation.
	var dir_start := Vector3(0.55 * side, 0.85, -0.25).normalized()
	var dir_end := Vector3(-0.6 * side, -0.35, -0.55).normalized()
	var axis := dir_start.cross(dir_end).normalized()
	# Windup cocks the arm back past the arc start, opposite the swing;
	# the attack then sweeps from there through to dir_end in one cut.
	var dir_windup := dir_start.rotated(axis, -WINDUP_ANGLE)
	var total_sweep := WINDUP_ANGLE + dir_start.angle_to(dir_end)
	var windup_pos := SHOULDER + dir_windup * ARM_LENGTH
	# Up vector is the arc tangent (axis × dir): the model is rolled 90° so
	# the blade's edges sit on the pivot's Y axis, and aligning Y with the
	# direction of travel keeps the edge — not the flat — leading the cut.
	var windup_quat := Basis.looking_at(
		dir_windup, axis.cross(dir_windup)).get_rotation_quaternion()
	if _swing_tween != null:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_parallel(true)
	# 1) Windup: pull back over the shoulder, away from the swing direction.
	_swing_tween.tween_property(sword_pivot, "position", windup_pos, duration * 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(sword_pivot, "quaternion", windup_quat, duration * 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2) Attack: fast sweep through the whole arc. The damage window opens
	# here so hits land with the visible cut, not the windup. Blade Cyclone
	# replaces the arc hitbox with a full-circle pass for a riposte swing.
	if sweep:
		_swing_tween.chain().tween_callback(_sweep_hit.bind(info))
	else:
		_swing_tween.chain().tween_callback(hitbox.activate.bind(info, duration * 0.35))
	_swing_tween.tween_method(
		func(t: float) -> void:
			var dir := dir_windup.rotated(axis, total_sweep * t)
			sword_pivot.position = SHOULDER + dir * ARM_LENGTH
			sword_pivot.basis = Basis.looking_at(dir, axis.cross(dir)),
		0.0, 1.0, duration * 0.3
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 3) Backswing: settle back to the ready stance.
	_swing_tween.chain().tween_property(
		sword_pivot, "position", SWORD_REST_POS, duration * 0.45
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(
		sword_pivot, "rotation_degrees", SWORD_REST_ROT, duration * 0.45
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _on_blocking_changed() -> void:
	if _shield_tween != null:
		_shield_tween.kill()
	var target_pos := SHIELD_BLOCK_POS if is_blocking else SHIELD_REST_POS
	var target_rot := SHIELD_BLOCK_ROT if is_blocking else SHIELD_REST_ROT
	_shield_tween = create_tween().set_parallel(true)
	_shield_tween.tween_property(shield_pivot, "position", target_pos, 0.12)
	_shield_tween.tween_property(shield_pivot, "rotation_degrees", target_rot, 0.12)


func notify_block_success(perfect: bool = false) -> void:
	# Emission flash on the shield face: white for a block, brighter gold
	# for a perfect block.
	if _shield_material != null:
		if _flash_tween != null:
			_flash_tween.kill()
		_shield_material.emission = Color(1.0, 0.8, 0.25) if perfect else Color(1.0, 1.0, 1.0)
		_shield_material.emission_energy_multiplier = 5.0 if perfect else 2.5
		_flash_tween = create_tween()
		_flash_tween.tween_property(
			_shield_material, "emission_energy_multiplier", 0.0, 0.4 if perfect else 0.25)
	# Impact kick: shield knocked back toward the camera, then re-settles.
	# A perfect block rebounds outward instead — a confident punch-back.
	if _shield_tween != null:
		_shield_tween.kill()
	var kick := Vector3(0.0, 0.02, -0.15) if perfect else Vector3(0.0, -0.03, 0.12)
	shield_pivot.position = SHIELD_BLOCK_POS + kick
	_shield_tween = create_tween()
	_shield_tween.tween_property(shield_pivot, "position", SHIELD_BLOCK_POS, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Primed-riposte tell: the blade lights gold and the glow fades over the
## window, so the player sees the punish window counting down.
func notify_riposte_primed(window: float = 2.0) -> void:
	if _blade_material == null:
		return
	if _riposte_tween != null:
		_riposte_tween.kill()
	_blade_material.emission_energy_multiplier = 3.0
	_riposte_tween = create_tween()
	_riposte_tween.tween_property(_blade_material, "emission_energy_multiplier", 0.0, window)


## Consuming swing: a bright gold flash that decays over the swing.
func _flash_riposte(duration: float) -> void:
	if _blade_material == null:
		return
	if _riposte_tween != null:
		_riposte_tween.kill()
	_blade_material.emission_energy_multiplier = 6.0
	_riposte_tween = create_tween()
	_riposte_tween.tween_property(_blade_material, "emission_energy_multiplier", 0.0, duration * 0.6)


## Blade Cyclone: a full-circle strike for a riposte swing. Hits every enemy in
## SWEEP_RADIUS once with the (already riposte-buffed) swing info, replacing the
## arc hitbox for that swing so nothing is hit twice.
func _sweep_hit(info: AttackInfo) -> void:
	if wielder == null:
		return
	for enemy: EnemyBase in EnemyBase.alive.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var offset := enemy.global_position - wielder.global_position
		offset.y = 0.0
		if offset.length() > SWEEP_RADIUS:
			continue
		var enemy_hurtbox := enemy.get_node_or_null(^"Hurtbox") as HurtboxComponent
		if enemy_hurtbox != null:
			enemy_hurtbox.receive_hit(info)
			# Blade Cyclone is the riposte swing itself — feed Crescendo here too.
			_try_riposte_chain(enemy_hurtbox)
	BlastVfx.spawn(get_tree().current_scene,
			wielder.global_position + Vector3(0.0, 0.1, 0.0), SWEEP_RADIUS,
			Color(1.0, 0.85, 0.3, 0.4), 0.12, 0.3)
