class_name ArcaneBolt
extends Area3D
## The staff's primary: a fast straight bolt that hits the first enemy it
## touches (or a wall) and pops with a small flash. Damage flows through the
## hurtbox pipeline so numbers/drops/vulnerability all apply. Enemy hits refund
## mana (the staff's generator loop); with Split Shot a bolt that lands on an
## enemy splits into weaker children that fan onward.

const LIFETIME := 3.0
const IMPACT_COLOR := Color(0.6, 0.5, 1.0, 0.6)
const BOLT_SCENE := preload("res://weapons/ArcaneBolt.tscn")
## Split Shot: children spawned on an enemy hit, fanning around the travel dir.
const SPLIT_COUNT := 3
const SPLIT_DAMAGE_MULT := 0.4
const SPLIT_FAN_DEG := 20.0

@export var speed := 24.0

var _info: AttackInfo
var _dir := Vector3.FORWARD
var _age := 0.0
var _done := false
## Staff mana/split config (all no-ops for a bare bolt with no budget).
var _budget: BoltManaBudget
var _mana_per_hit := 0.0
var _can_split := false


func setup(info: AttackInfo, direction: Vector3, budget: BoltManaBudget = null,
		mana_per_hit: float = 0.0, can_split: bool = false) -> void:
	_info = info
	_dir = direction.normalized()
	_budget = budget
	_mana_per_hit = mana_per_hit
	_can_split = can_split


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	global_position += _dir * speed * delta


func _on_area_entered(area: Area3D) -> void:
	var hurtbox := area as HurtboxComponent
	if hurtbox == null or _info == null:
		return
	hurtbox.receive_hit(_info)
	# Generator loop: a bolt that lands on an enemy refunds mana, drawn from a
	# per-volley budget so scatter + split can't print mana.
	if _budget != null:
		_budget.grant(_mana_per_hit)
	if _can_split:
		_split()
	_impact()


func _on_body_entered(_body: Node3D) -> void:
	# Walls/ground: no damage, no mana, no split -- the bolt just fizzles.
	_impact()


## Split Shot: fan SPLIT_COUNT weaker children out from the impact point along
## the travel direction. Children never re-split and refund half mana, still
## drawn from the same shared volley budget.
func _split() -> void:
	for i: int in SPLIT_COUNT:
		var t := float(i) - float(SPLIT_COUNT - 1) * 0.5
		var child_dir := _dir.rotated(Vector3.UP, deg_to_rad(SPLIT_FAN_DEG * t))
		var child := BOLT_SCENE.instantiate() as ArcaneBolt
		child.setup(AttackInfo.new(_info.source, _info.damage * SPLIT_DAMAGE_MULT),
				child_dir, _budget, _mana_per_hit * 0.5, false)
		get_tree().current_scene.add_child(child)
		child.global_position = global_position


func _impact() -> void:
	if _done:
		return
	_done = true
	BlastVfx.spawn(get_tree().current_scene, global_position, 0.8, IMPACT_COLOR, 0.4, 0.15)
	queue_free()
