class_name Staff
extends Weapon
## Arcanist loadout: no shield (can_block=false). LMB fires a fast Arcane Bolt;
## RMB casts the player's Fireball (the staff is the cast focus, so it does not
## stow). Frost Nova and future spells arrive as Arcana purchases, gated on the
## staff being mounted. All spell damage scales with the spell_damage stat.
##
## Bolt boons reshape the LMB: Scatter Shot fires a spread, Burst Fire fires a
## timed 3-round burst, Split Shot splits bolts on enemy hits, and Arcane Surge
## buffs bolt damage while mana is banked high. They stack -- a burst fires
## scatters, whose bolts can split.

const REST_POS := Vector3(0.32, -0.26, 0.0)
const REST_ROT := Vector3(10.0, -8.0, 4.0)
const RECOIL_POS := Vector3(0.30, -0.24, 0.12)
const BOLT_SCENE := preload("res://weapons/ArcaneBolt.tscn")
const ORB_FLARE := 5.0
## Scatter Shot: a flat horizontal fan of weaker bolts. Shotgun-style spread --
## outer bolts are offset this many degrees from center, so all 3 only stack
## on one target up close; at range they splay wide enough to spread across
## multiple enemies.
const SCATTER_COUNT := 3
const SCATTER_DAMAGE_MULT := 0.55
const SCATTER_FAN_DEG := 16.0
## Burst Fire: a rapid burst, then a longer committed pause. The cycle length
## is BURST_CYCLE_MULT swing-times, so BURST_COUNT rounds fired across that
## cycle already beats single fire by a flat BURST_COUNT/BURST_CYCLE_MULT
## (~+25%) at any attack_speed -- that ratio alone never shrinks, since both
## the cycle length and the burst interval are swing-time-scaled (they shrink
## at the same rate as attack_speed rises, so their ratio -- and the round
## timers' fit inside the cycle -- holds regardless of atk). To make faster
## builds actually pull ahead instead of capping at that flat bonus, every
## full BURST_BONUS_ATK_STEP of attack_speed above baseline (1.0) adds one
## more round to the burst, so the throughput lead over single fire grows
## with attack_speed instead of staying fixed.
const BURST_COUNT := 3
const BURST_INTERVAL := 0.08
const BURST_CYCLE_MULT := 2.4
const BURST_BONUS_ATK_STEP := 1.0
## Arcane Surge: bolts hit harder while mana is at least this full.
const SURGE_MANA_FRACTION := 0.8
const SURGE_DAMAGE_MULT := 1.3
## Stormcaller (Arcanist Aspect): while levitating, every trigger pull forks into
## three aimed fans, the outer two offset this many degrees. The forks share the
## volley's single mana budget, so they are extra chances to land the capped
## refund (funding flight), never extra income.
const STORMCALLER_FORK_DEG := 10.0

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


func mobility_id() -> StringName:
	return &"levitate"


func _do_attack(duration: float) -> void:
	var player := wielder as Player
	if player == null:
		return
	if player.has_ability(&"burst_fire"):
		_fire_burst(player, duration)
	else:
		_fire_volley(player)


## One trigger pull's worth of bolts. Every bolt (scatter fan, split children,
## and Stormcaller forks) shares ONE mana budget so the refund is capped per
## volley — the anti-printer rule. Each volley kicks the viewmodel.
func _fire_volley(player: Player) -> void:
	var base_damage := _bolt_damage(player)
	var budget := BoltManaBudget.new(player, Player.BOLT_MANA_RESTORE)
	var can_split := player.has_ability(&"split_shot")
	# Fork the whole pull three ways when Stormcaller is levitating; each fork
	# then fans/splits exactly like a normal volley would.
	for fork_dir: Vector3 in _volley_directions(player):
		_fire_fan(player, fork_dir, base_damage, budget, can_split)
	_recoil()


## The aim directions this trigger pull fires along: just the aim vector, or a
## three-way ±STORMCALLER_FORK_DEG fork while Stormcaller is levitating.
func _volley_directions(player: Player) -> Array[Vector3]:
	var aim := player.aim_direction()
	if player.has_ability(&"stormcaller") and player.is_levitating():
		return [
			aim.rotated(Vector3.UP, deg_to_rad(-STORMCALLER_FORK_DEG)),
			aim,
			aim.rotated(Vector3.UP, deg_to_rad(STORMCALLER_FORK_DEG)),
		]
	return [aim]


## One aim direction's worth of bolts: a single bolt, or a Scatter Shot spread.
## Shares the passed-in budget so forks/scatter/split never exceed the cap.
func _fire_fan(player: Player, dir: Vector3, base_damage: float,
		budget: BoltManaBudget, can_split: bool) -> void:
	if player.has_ability(&"scatter_shot"):
		for i: int in SCATTER_COUNT:
			var t := float(i) - float(SCATTER_COUNT - 1) * 0.5
			var spread := dir.rotated(Vector3.UP, deg_to_rad(SCATTER_FAN_DEG * t))
			_spawn_bolt(player, spread, base_damage * SCATTER_DAMAGE_MULT, budget, can_split)
	else:
		_spawn_bolt(player, dir, base_damage, budget, can_split)


## Burst Fire: fire now and schedule the remaining rounds, then hold the primary
## on a longer cooldown so the burst reads as a committed cycle. Round count
## grows with attack_speed (see tuning comment above) so the throughput lead
## over single fire widens instead of capping at a flat bonus.
func _fire_burst(player: Player, duration: float) -> void:
	_fire_volley(player)
	var atk := maxf(0.1, stats.get_stat(Stats.ATTACK_SPEED))
	var bonus_rounds := int(maxf(0.0, atk - 1.0) / BURST_BONUS_ATK_STEP)
	var round_count := BURST_COUNT + bonus_rounds
	var interval := BURST_INTERVAL / atk
	for i: int in range(1, round_count):
		get_tree().create_timer(interval * float(i), false).timeout.connect(
				_burst_round.bind(player))
	_cooldown = duration * BURST_CYCLE_MULT


func _burst_round(player: Player) -> void:
	if not is_instance_valid(player) or not is_inside_tree():
		return
	# Don't keep firing if the loadout changed out from under the timer.
	if player.weapon != self:
		return
	_fire_volley(player)


func _spawn_bolt(player: Player, dir: Vector3, damage: float, budget: BoltManaBudget,
		can_split: bool) -> void:
	var bolt := BOLT_SCENE.instantiate() as ArcaneBolt
	bolt.setup(AttackInfo.new(wielder, damage), dir, budget, Player.BOLT_MANA_RESTORE, can_split)
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = player.aim_origin() + dir * 0.8


## Base per-bolt damage, before any scatter/split fraction. Arcane Surge adds a
## flat multiplier while mana is banked high, rewarding not hoarding casts.
func _bolt_damage(player: Player) -> float:
	var damage := (weapon_data.damage + stats.get_stat(Stats.DAMAGE) * 0.8) \
			* stats.get_stat(Stats.SPELL_DAMAGE)
	if player.has_ability(&"arcane_surge") \
			and player.get_mana() >= player.get_mana_max() * SURGE_MANA_FRACTION:
		damage *= SURGE_DAMAGE_MULT
	return damage


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
