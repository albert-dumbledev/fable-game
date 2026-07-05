class_name Staff
extends Weapon
## Arcanist loadout: no shield (can_block=false). LMB fires a fast Arcane Bolt;
## RMB casts the player's Fireball (the staff is the cast focus, so it does not
## stow). Frost Nova and future spells arrive as Arcana purchases, gated on the
## staff being mounted. All spell damage scales with the spell_damage stat.

const REST_POS := Vector3(0.32, -0.26, 0.0)
const REST_ROT := Vector3(10.0, -8.0, 4.0)
const RECOIL_POS := Vector3(0.30, -0.24, 0.12)
const BOLT_SCENE := preload("res://weapons/ArcaneBolt.tscn")
const ORB_FLARE := 5.0

@onready var staff_pivot: Node3D = $StaffPivot
@onready var orb: MeshInstance3D = $StaffPivot/Orb

var _recoil_tween: Tween
var _orb_material: StandardMaterial3D


func _ready() -> void:
	staff_pivot.position = REST_POS
	staff_pivot.rotation_degrees = REST_ROT
	var mat := orb.get_active_material(0)
	if mat != null:
		_orb_material = mat.duplicate() as StandardMaterial3D
		orb.material_override = _orb_material


func _swing_sound() -> StringName:
	return &"arcane_bolt"


func _do_attack(_duration: float) -> void:
	var player := wielder as Player
	if player == null:
		return
	var damage := (weapon_data.damage + stats.get_stat(Stats.DAMAGE) * 0.8) \
			* stats.get_stat(Stats.SPELL_DAMAGE)
	var dir := player.aim_direction()
	var bolt := BOLT_SCENE.instantiate() as ArcaneBolt
	bolt.setup(AttackInfo.new(wielder, damage), dir)
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = player.aim_origin() + dir * 0.8
	_recoil()


func _do_secondary() -> void:
	var player := wielder as Player
	if player != null:
		player.try_cast_fireball()


## A quick kick back + orb flare when the bolt fires.
func _recoil() -> void:
	if _recoil_tween != null:
		_recoil_tween.kill()
	if _orb_material != null:
		_orb_material.emission_energy_multiplier = ORB_FLARE
	_recoil_tween = create_tween()
	_recoil_tween.set_parallel(true)
	_recoil_tween.tween_property(staff_pivot, "position", RECOIL_POS, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.chain().tween_property(staff_pivot, "position", REST_POS, 0.14) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _orb_material != null:
		_recoil_tween.tween_property(_orb_material, "emission_energy_multiplier", 3.0, 0.2)
