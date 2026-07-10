class_name Pickup
extends Node3D
## Collectable dropped by dying enemies. Bursts outward ballistically,
## bounces to rest, then magnets to the player once they come near.
## No physics body — manual motion keeps hundreds of these cheap.

const MAGNET_RADIUS := 4.5
const MAGNET_SPEED := 13.0
const MAGNET_ACCEL := 50.0
## Generous so a fast magnet — or a laggy web frame with a big step — still
## lands inside the collect zone instead of skimming past.
const COLLECT_RADIUS := 1.1
## No magnet/collection until the burst has had time to play out —
## melee kills drop loot right on top of the player, and without this
## grace period the fountain gets vacuumed on frame one.
const MAGNET_DELAY := 0.4
const LIFETIME := 30.0
const GRAVITY := 18.0
const REST_Y := 0.3
const SPIN_SPEED := 3.0
const ARENA_HALF := 19.0
## Pulse range for the magnet mesh's emission — loud enough to read across
## the arena without blowing out into a solid glow.
const MAGNET_PULSE_LOW := 0.8
const MAGNET_PULSE_HIGH := 3.5
const MAGNET_PULSE_TIME := 0.6
const UNLOCK_PULSE_LOW := 1.5
const UNLOCK_PULSE_HIGH := 4.0
const ASPECT_PULSE_LOW := 1.5
const ASPECT_PULSE_HIGH := 4.5

## Every magnet pickup currently alive, so the minimap can ping them without
## a group scan.
static var magnets: Array[Pickup] = []

## Every gold/XP pickup currently on the ground — the Scavenger's food. (Relics,
## magnets, and health never register: boss loot and utility drops are theft-proof.)
static var edible: Array[Pickup] = []

var kind: StringName = &"gold"
var value := 1
## For &"unlock" relics, the flag granted on collect.
var ability: StringName = &""
## Overridable per pickup: boss loot lives longer and magnets from further
## away so a fountain earned mid-swarm isn't stranded.
var lifetime := LIFETIME
var magnet_radius := MAGNET_RADIUS

var _velocity := Vector3.ZERO
var _age := 0.0
var _target: Node3D

@onready var gold_mesh: MeshInstance3D = $GoldMesh
@onready var xp_mesh: MeshInstance3D = $XpMesh
@onready var magnet_mesh: MeshInstance3D = $MagnetMesh
@onready var health_mesh: Node3D = $HealthMesh
@onready var unlock_mesh: MeshInstance3D = $UnlockMesh
@onready var aspect_mesh: MeshInstance3D = $AspectMesh


## Call before adding to the tree.
func setup(p_kind: StringName, p_value: int, burst_velocity: Vector3) -> void:
	kind = p_kind
	value = p_value
	_velocity = burst_velocity


func _ready() -> void:
	add_to_group(&"pickups")
	if kind == &"gold" or kind == &"xp":
		edible.append(self)
	gold_mesh.visible = kind == &"gold"
	xp_mesh.visible = kind == &"xp"
	magnet_mesh.visible = kind == &"magnet"
	health_mesh.visible = kind == &"health"
	unlock_mesh.visible = kind == &"unlock"
	aspect_mesh.visible = kind == &"aspect"
	_target = get_tree().get_first_node_in_group(&"player") as Node3D
	if kind == &"magnet":
		magnets.append(self)
		# Walking to it is the decision — it must never home to the player.
		magnet_radius = 0.0
		lifetime = 45.0
		_start_pulse(magnet_mesh, MAGNET_PULSE_LOW, MAGNET_PULSE_HIGH)
	if kind == &"unlock":
		# A permanent relic: walk to it, and it never expires unclaimed.
		magnet_radius = 0.0
		lifetime = INF
		_start_pulse(unlock_mesh, UNLOCK_PULSE_LOW, UNLOCK_PULSE_HIGH)
	if kind == &"aspect":
		# An Aspect relic: same theft-proof, walk-to-it contract as &"unlock" —
		# walking onto it IS the decision, so it never magnets or expires.
		magnet_radius = 0.0
		lifetime = INF
		_start_pulse(aspect_mesh, ASPECT_PULSE_LOW, ASPECT_PULSE_HIGH)


func _exit_tree() -> void:
	magnets.erase(self)
	edible.erase(self)


## Forces this pickup into the collection path this very frame — used by a
## collected magnet to vacuum every other pickup in the arena.
func force_magnet() -> void:
	magnet_radius = INF
	_age = maxf(_age, MAGNET_DELAY)


## Eaten by a Scavenger: hand over the value and vanish WITHOUT emitting
## pickup_collected — loot a Scavenger ate was never collected by the player.
func consume() -> int:
	edible.erase(self)
	queue_free()
	return value


func _start_pulse(target_mesh: MeshInstance3D, low: float, high: float) -> void:
	var base_material := target_mesh.get_active_material(0)
	if base_material == null:
		return
	var material := base_material.duplicate() as StandardMaterial3D
	target_mesh.material_override = material
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(material, "emission_energy_multiplier", high, MAGNET_PULSE_TIME)
	tween.tween_property(material, "emission_energy_multiplier", low, MAGNET_PULSE_TIME)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	rotate_y(SPIN_SPEED * delta)
	if _age >= MAGNET_DELAY and _target != null and is_instance_valid(_target) \
			and _target.is_inside_tree() and _should_collect():
		var to_player := _target.global_position + Vector3(0.0, 0.9, 0.0) - global_position
		var dist := to_player.length()
		if dist <= COLLECT_RADIUS:
			if kind == &"unlock":
				_claim_unlock()
				queue_free()
			elif kind == &"aspect":
				_claim_aspect()
				queue_free()
			else:
				_collect()
			return
		if dist <= magnet_radius:
			_velocity = _velocity.move_toward(to_player / dist * MAGNET_SPEED, MAGNET_ACCEL * delta)
			var step := _velocity * delta
			# Overshoot guard: if this frame's step would cross into the collect
			# zone (a big delta on a laggy web frame), collect now instead of
			# skimming past the player and orbiting without ever landing inside.
			# This is what makes a magnet reliably *collect* everything, not just
			# drag it closer.
			if step.length() >= dist - COLLECT_RADIUS:
				_collect()
				return
			global_position += step
			return
	# Ballistic scatter: gravity, then a damped bounce on the floor.
	_velocity.y -= GRAVITY * delta
	global_position += _velocity * delta
	global_position.x = clampf(global_position.x, -ARENA_HALF, ARENA_HALF)
	global_position.z = clampf(global_position.z, -ARENA_HALF, ARENA_HALF)
	if global_position.y <= REST_Y and _velocity.y < 0.0:
		global_position.y = REST_Y
		_velocity.y *= -0.35
		_velocity.x *= 0.6
		_velocity.z *= 0.6
		if absf(_velocity.y) < 0.8:
			_velocity = Vector3.ZERO


## Health pickups are ignored while the player is already at full health, so a
## heal is never wasted — they rest on the ground until they are needed.
func _should_collect() -> bool:
	if kind != &"health":
		return true
	var player := _target as Player
	return player == null or player.health.current < player.health.max_health


## Grant the pickup and vanish. A collected magnet vacuums every other pickup.
func _collect() -> void:
	EventBus.pickup_collected.emit(kind, value)
	if kind == &"magnet":
		for pickup: Pickup in get_tree().get_nodes_in_group(&"pickups"):
			if pickup != self:
				pickup.force_magnet()
	queue_free()


## Claims an Aspect relic: unlike the weapon relic, the pickup carries no
## ability — walking onto it just opens the AspectScreen, which does the
## pick-1-of-2 roll and applies the chosen Aspect. Reuses the unlock stinger.
func _claim_aspect() -> void:
	AudioManager.play(&"unlock_claim")
	EventBus.aspect_relic_claimed.emit()


## Claims a weapon-unlock relic: grants the ability (persisted immediately),
## announces it on the wave banner, and plays a unique stinger.
func _claim_unlock() -> void:
	MetaProgression.grant_meta_ability(ability)
	AudioManager.play(&"unlock_claim")
	EventBus.wave_announcement.emit("%s CLAIMED — equip it from your loadout" % _unlock_label())
	EventBus.unlock_claimed.emit(ability)


## The claimed weapon's display name (upper-cased) for the banner, resolved
## from the weapon registry by matching unlock_ability; falls back to the flag.
func _unlock_label() -> String:
	var weapon_registry := MetaProgression.weapon_registry
	if weapon_registry != null:
		for weapon: WeaponData in weapon_registry.weapons:
			if weapon.unlock_ability == ability:
				return weapon.display_name.to_upper()
	return String(ability).to_upper()
