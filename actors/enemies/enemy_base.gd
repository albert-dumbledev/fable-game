class_name EnemyBase
extends CharacterBody3D
## Melee chaser with a Chase -> Windup -> Attack -> Recover state machine.
## Ranged/boss variants override state behavior, not the plumbing.
## All numbers come from an EnemyData resource, scaled by the spawner.

enum State { CHASE, WINDUP, ATTACK, RECOVER, STUNNED, DEAD }

## Every living enemy, maintained alongside the "enemies" group. AoE weapons,
## the spawner, and the minimap iterate this instead of group queries (which
## allocate and scan every call — noticeable on web with 60 enemies alive).
## Sites that can kill mid-loop iterate a duplicate() snapshot.
static var alive: Array[EnemyBase] = []

const PICKUP_SCENE := preload("res://actors/pickups/Pickup.tscn")
const MAX_PICKUP_PIECES := 8
## Rare utility drops: at most one magnet in the arena at a time (checked
## via Pickup.magnets); health is a straight per-kill roll plus a guaranteed
## boss-kill drop (see BossEnemy._spawn_loot_wave).
const MAGNET_DROP_CHANCE := 0.007
const HEALTH_DROP_CHANCE := 0.02
const HEALTH_HEAL_PCT := 25
const MAGNET_LIFETIME := 45.0
const DEATH_SPAWN_RADIUS := 1.2
const DEATH_SPAWN_ARENA_HALF := 18.5
const DEATH_SPAWN_HEIGHT := 1.0

## Elite variants (Aspect Drops M1): a rare buffed pool spawn — a visible
## ×4-HP bounty. The spawner gates the roll (rate + time); make_elite() only
## folds in the stat mults, and _ready applies the look. Emission is a hot
## magenta that persists through windup/stun (those drive albedo, not emission).
const ELITE_HP_MULT := 4.0
const ELITE_REWARD_MULT := 3.0
const ELITE_SCALE := 1.3
const ELITE_EMISSION := Color(1.0, 0.15, 0.6)
const ELITE_EMISSION_ENERGY := 2.5

const ATTACK_ACTIVE_TIME := 0.25
const WINDUP_COLOR := Color(1.0, 0.55, 0.35)
const STUN_COLOR := Color(0.55, 0.7, 1.0)
const SLOW_COLOR := Color(0.55, 0.85, 1.0)
const STUN_TILT_DEG := 14.0
const FIST_REST := Vector3(0.35, 1.05, -0.35)
const FIST_WINDUP := FIST_REST + Vector3(0.05, 0.05, 0.35)
const FIST_PUNCH := FIST_REST + Vector3(-0.15, -0.1, -0.95)
const LUNGE_SPEED_MULT := 1.8
const SHOVE_DECAY := 18.0
const VULNERABLE_MULT := 1.35
## Bone Breaker: a shove carrying wall damage that lands the enemy on a wall
## deals it once, if the shove is still strong enough to count as a slam.
const WALL_IMPACT_MIN_SPEED := 5.0

@onready var health: HealthComponent = $Health
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var hitbox: HitboxComponent = $AttackHitbox
@onready var mesh: MeshInstance3D = $Mesh
@onready var fist_pivot: Node3D = $FistPivot

var data: EnemyData
var state: State = State.CHASE
## Elite bounty (Aspect Drops M1): set by make_elite() before _ready; read by
## the spawner (rate limit), the minimap (ping), and _on_died (guaranteed drop).
var is_elite := false

var _state_time := 0.0
var _hp_mult := 1.0
var _dmg_mult := 1.0
var _reward_mult := 1.0
var _target: Node3D
var _material: StandardMaterial3D
var _base_color := Color.WHITE
var _fist_tween: Tween
var _color_tween: Tween
var _eyes: Array[MeshInstance3D] = []
var _eye_material: StandardMaterial3D
var _eye_tween: Tween
var _stun_duration := 0.0
var _vulnerable_until := 0.0  ## ticks_msec deadline for Expose Weakness; 0 = not vulnerable.
var _shove := Vector3.ZERO
## Bone Breaker payload riding the current shove (0 = none), and its source.
var _shove_wall_damage := 0.0
var _shove_source: Node3D
var _slow_mult := 1.0
var _slow_time := 0.0
var _frenzy_mult := 1.0
var _frenzy_time := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


## Must be called before adding to the tree.
func setup(enemy_data: EnemyData, hp_mult: float, dmg_mult: float,
		reward_mult: float = 1.0) -> void:
	data = enemy_data
	_hp_mult = hp_mult
	_dmg_mult = dmg_mult
	_reward_mult = reward_mult


## Promote this spawn to an elite. Must be called after setup() and before the
## enemy enters the tree: it folds ×4 into _hp_mult (which _ready reads for max
## health) and ×3 into _reward_mult, so no re-application is needed. The bigger
## scale and emissive glow are applied in _ready, once _material exists.
func make_elite() -> void:
	is_elite = true
	_hp_mult *= ELITE_HP_MULT
	_reward_mult *= ELITE_REWARD_MULT


func _ready() -> void:
	add_to_group(&"enemies")
	alive.append(self)
	if data == null:
		push_error("EnemyBase spawned without EnemyData; call setup() first.")
		data = EnemyData.new()
	health.set_max_health(data.max_health * _hp_mult, true)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_target = get_tree().get_first_node_in_group(&"player") as Node3D
	var base_material := mesh.get_active_material(0)
	if base_material != null:
		_material = base_material.duplicate() as StandardMaterial3D
		mesh.material_override = _material
		_base_color = _material.albedo_color
	# Shared per-enemy eye material so windups can ignite the eyes — the
	# tell that reads through a crowd better than body tint alone.
	for path: NodePath in [^"Mesh/EyeL", ^"Mesh/EyeR"]:
		var eye := get_node_or_null(path) as MeshInstance3D
		if eye != null:
			_eyes.append(eye)
	if not _eyes.is_empty():
		_eye_material = StandardMaterial3D.new()
		_eye_material.albedo_color = Color(0.9, 0.9, 0.9)
		_eye_material.emission_enabled = true
		_eye_material.emission = Color(1.0, 0.25, 0.1)
		_eye_material.emission_energy_multiplier = 0.0
		for eye: MeshInstance3D in _eyes:
			eye.material_override = _eye_material
	if is_elite:
		_apply_elite_look()


## Elite look: scale the whole body up and ignite the emissive tint on the
## shared material. Emission (unlike albedo) is untouched by the windup/stun
## color logic, so the glow reads constantly for the enemy's whole life.
func _apply_elite_look() -> void:
	scale = Vector3.ONE * ELITE_SCALE
	if _material != null:
		_material.emission_enabled = true
		_material.emission = ELITE_EMISSION
		_material.emission_energy_multiplier = ELITE_EMISSION_ENERGY


func _exit_tree() -> void:
	# Safety net for frees that skip _on_died (scene teardown).
	alive.erase(self)


func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if state == State.DEAD:
		move_and_slide()
		return
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	_state_time += delta
	if _slow_time > 0.0:
		_slow_time -= delta
		if _slow_time <= 0.0:
			_slow_mult = 1.0
			_refresh_resting_color()
	if _frenzy_time > 0.0:
		_frenzy_time -= delta
		if _frenzy_time <= 0.0:
			_frenzy_mult = 1.0
	if state != State.STUNNED:
		_face_target()
	match state:
		State.CHASE:
			_chase()
		State.WINDUP:
			_hold_still()
			if _state_time >= data.windup_time:
				_begin_attack()
		State.ATTACK:
			# Lunge momentum from _begin_attack, bleeding off quickly.
			velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
			if _state_time >= ATTACK_ACTIVE_TIME:
				_begin_recover()
		State.RECOVER:
			_hold_still()
			if _state_time >= data.recover_time:
				_set_state(State.CHASE)
		State.STUNNED:
			_hold_still()
			if _state_time >= _stun_duration:
				_end_stun()
	# External shoves (boss charge plowing) ride on top of state movement.
	if _shove != Vector3.ZERO:
		velocity.x += _shove.x
		velocity.z += _shove.z
		_shove = _shove.move_toward(Vector3.ZERO, SHOVE_DECAY * delta)
	move_and_slide()
	if _shove_wall_damage > 0.0 and _shove.length() > WALL_IMPACT_MIN_SPEED \
			and is_on_wall():
		_wall_impact()


## Physically fling this enemy (no damage). Impulse decays over ~a second.
## Bone Breaker rides a wall-damage payload on the shove: if the enemy slams
## into a wall while the impulse is still strong, it takes wall_damage once.
func apply_shove(impulse: Vector3, wall_damage: float = 0.0, source: Node3D = null) -> void:
	_shove = impulse
	_shove_wall_damage = wall_damage
	_shove_source = source


## Bone Breaker: the enemy slammed into a wall mid-shove — take the payload
## once (through the hurtbox so vulnerability/drops apply) and stagger, then
## clear the payload so it fires at most once per shove.
func _wall_impact() -> void:
	var dmg := _shove_wall_damage
	_shove_wall_damage = 0.0
	if hurtbox != null:
		hurtbox.receive_hit(AttackInfo.new(_shove_source, dmg))


## Expose Weakness (sword unique boon): the enemy takes VULNERABLE_MULT damage
## from all sources until `duration` seconds elapse (set to the stun window).
func mark_vulnerable(duration: float) -> void:
	if state == State.DEAD:
		return
	_vulnerable_until = float(Time.get_ticks_msec()) + duration * 1000.0


## Routes every incoming hit; scales damage while the Expose Weakness window is
## open. Returns a fresh AttackInfo so the shared swing info is never mutated.
func mitigate_hit(info: AttackInfo) -> AttackInfo:
	if _vulnerable_until <= 0.0 or float(Time.get_ticks_msec()) > _vulnerable_until:
		return info
	var scaled := AttackInfo.new(info.source, info.damage * VULNERABLE_MULT, info.knockback)
	scaled.hit_sound = info.hit_sound
	return scaled


## Chill (frost nova): scales all movement — chasing, kiting, lunges — but
## not attack timings. Reapplying overwrites the previous slow.
func apply_slow(mult: float, duration: float) -> void:
	if state == State.DEAD:
		return
	_slow_mult = mult
	_slow_time = duration
	_refresh_resting_color()


## Hatch frenzy (broodlings): a temporary speed burst applied when hatched
## from a death-burst. Decays after `duration` like the slow does.
func apply_spawn_frenzy(mult: float, duration: float) -> void:
	if state == State.DEAD:
		return
	_frenzy_mult = mult
	_frenzy_time = duration


## data.move_speed with the current slow and hatch frenzy applied. All
## steering — base and variant overrides — must route through this.
func move_speed() -> float:
	return data.move_speed * _slow_mult * _frenzy_mult


func _chase() -> void:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= data.attack_range:
		_begin_windup()
		return
	var direction := to_target.normalized()
	velocity.x = direction.x * move_speed()
	velocity.z = direction.z * move_speed()


func _hold_still() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face_target() -> void:
	var to_target := _target.global_position - global_position
	rotation.y = atan2(-to_target.x, -to_target.z)


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


func _begin_windup() -> void:
	_set_state(State.WINDUP)
	if _material != null:
		_kill_color_tween()
		_color_tween = create_tween()
		_color_tween.tween_property(_material, "albedo_color", WINDUP_COLOR, data.windup_time)
	_flash_eyes(data.windup_time)
	# Cock the fist back so the incoming punch is readable.
	_tween_fist(FIST_WINDUP, data.windup_time)


func _begin_attack() -> void:
	_set_state(State.ATTACK)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _resting_color()
	_reset_eyes()
	hitbox.activate(
		AttackInfo.new(self, data.damage * _dmg_mult, data.knockback), ATTACK_ACTIVE_TIME)
	# A perfect block inside activate() can stun us synchronously — if so,
	# skip the punch and lunge.
	if state != State.ATTACK:
		return
	# Punch toward the player with a short lunge for readability.
	_tween_fist(FIST_PUNCH, ATTACK_ACTIVE_TIME * 0.5)
	var dir := _target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * move_speed() * LUNGE_SPEED_MULT
	velocity.z = dir.z * move_speed() * LUNGE_SPEED_MULT


## Perfect-block reward: freeze in place, visibly dazed, attack cancelled.
## Called dynamically (e.g. from Player.mitigate_hit); bosses can override.
func stun(duration: float) -> void:
	if state == State.DEAD:
		return
	_set_state(State.STUNNED)
	_stun_duration = duration
	velocity.x = 0.0
	velocity.z = 0.0
	_reset_eyes()
	hitbox.deactivate()
	_tween_fist(FIST_REST, 0.2)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = STUN_COLOR
	var tween := create_tween()
	tween.tween_property(mesh, "rotation_degrees:z", STUN_TILT_DEG, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _end_stun() -> void:
	if _material != null:
		_material.albedo_color = _resting_color()
	var tween := create_tween()
	tween.tween_property(mesh, "rotation_degrees:z", 0.0, 0.15)
	_set_state(State.CHASE)


## Albedo for states that don't own the color: base, tinted icy while slowed.
func _resting_color() -> Color:
	return _base_color.lerp(SLOW_COLOR, 0.65) if _slow_time > 0.0 else _base_color


## Retint now — unless windup/stun owns the color; those reset on their own.
func _refresh_resting_color() -> void:
	if _material == null or state == State.WINDUP or state == State.STUNNED:
		return
	_material.albedo_color = _resting_color()


func _kill_color_tween() -> void:
	if _color_tween != null:
		_color_tween.kill()
		_color_tween = null


## Windup tell: the eyes ignite over the windup duration.
func _flash_eyes(duration: float) -> void:
	if _eye_material == null:
		return
	if _eye_tween != null:
		_eye_tween.kill()
	_eye_tween = create_tween()
	_eye_tween.tween_property(_eye_material, "emission_energy_multiplier", 3.5, duration)


func _reset_eyes() -> void:
	if _eye_material == null:
		return
	if _eye_tween != null:
		_eye_tween.kill()
		_eye_tween = null
	_eye_material.emission_energy_multiplier = 0.0


func _begin_recover() -> void:
	_set_state(State.RECOVER)
	_tween_fist(FIST_REST, 0.3)


func _tween_fist(target: Vector3, duration: float) -> void:
	if _fist_tween != null:
		_fist_tween.kill()
	_fist_tween = create_tween()
	_fist_tween.tween_property(fist_pivot, "position", target, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_damaged(info: AttackInfo) -> void:
	AudioManager.play_at(info.hit_sound, global_position)
	mesh.scale = Vector3.ONE * 1.18
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.12)
	DamageNumber.spawn(
		get_tree().current_scene,
		global_position + Vector3(randf_range(-0.25, 0.25), 2.0, randf_range(-0.25, 0.25)),
		info.damage, health.current <= 0.0)


func _on_died() -> void:
	_set_state(State.DEAD)
	remove_from_group(&"enemies")
	alive.erase(self)
	collision_layer = 0
	hitbox.deactivate()
	hurtbox.set_deferred(&"monitorable", false)
	EventBus.enemy_killed.emit(data, global_position)
	_reset_eyes()
	# Kill pop: color-matched shards and a brief ground ring under the
	# shrinking corpse.
	ShardBurst.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.9, 0.0), _base_color, 9, 5.5, 0.12)
	BlastVfx.spawn(get_tree().current_scene,
			global_position + Vector3(0.0, 0.1, 0.0), 1.1,
			Color(_base_color.r, _base_color.g, _base_color.b, 0.4), 0.1, 0.25)
	_spawn_pickups(&"gold", int(round(data.gold_reward * _reward_mult)))
	_spawn_pickups(&"xp", int(round(data.xp_reward * _reward_mult)))
	# Elite death (Aspect Drops M2): the drop decision now lives in RunDirector —
	# the first elites per run drop an Aspect relic, later elites fall back to the
	# M1 magnet-or-health bounty. RunDirector owns that split (it counts kills and
	# checks the Aspect pool), so this just reports where the elite fell.
	if is_elite:
		EventBus.elite_died.emit(global_position)
	if Pickup.magnets.is_empty() and randf() < MAGNET_DROP_CHANCE:
		_spawn_single_pickup(&"magnet", 1, MAGNET_LIFETIME)
	if randf() < HEALTH_DROP_CHANCE:
		_spawn_single_pickup(&"health", HEALTH_HEAL_PCT, 0.0)
	_spawn_death_children()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.22)
	tween.tween_callback(queue_free)


## Broodmother-style death burst (EnemyData.death_spawns): instantiate the
## children in a tight ring around the corpse, inheriting this enemy's wave
## mults, hatching from RECOVER (they hold still for recover_time with a
## scale-up pop before chasing). No recursion — a child that itself has
## death_spawns is refused.
func _spawn_death_children() -> void:
	if data.death_spawns == null or data.death_spawn_count <= 0:
		return
	if data.death_spawns.death_spawns != null:
		push_warning("Refusing recursive death_spawns on %s" % data.display_name)
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	AudioManager.play_at(&"brood_burst", global_position)
	var count := data.death_spawn_count
	for i: int in count:
		var child := data.death_spawns.scene.instantiate() as EnemyBase
		if child == null:
			continue
		child.setup(data.death_spawns, _hp_mult, _dmg_mult, _reward_mult)
		var angle := (float(i) + randf_range(-0.2, 0.2)) * TAU / float(count)
		var pos := global_position + Vector3(cos(angle) * DEATH_SPAWN_RADIUS, 0.0,
				sin(angle) * DEATH_SPAWN_RADIUS)
		pos.x = clampf(pos.x, -DEATH_SPAWN_ARENA_HALF, DEATH_SPAWN_ARENA_HALF)
		pos.z = clampf(pos.z, -DEATH_SPAWN_ARENA_HALF, DEATH_SPAWN_ARENA_HALF)
		pos.y = DEATH_SPAWN_HEIGHT
		child.scale = Vector3.ONE * 0.2
		parent.add_child(child)
		child.global_position = pos
		# Hatch beat: normally hold in RECOVER and pop up before chasing.
		# Frenzied hatchlings (broodlings) skip the stagger and burst in.
		if data.death_spawns.death_spawn_frenzy_time > 0.0:
			child.apply_spawn_frenzy(data.death_spawns.death_spawn_frenzy_mult,
				data.death_spawns.death_spawn_frenzy_time)
		else:
			child._set_state(State.RECOVER)
		var pop := child.create_tween()
		pop.tween_property(child, "scale", Vector3.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Explode the reward outward as collectable pieces.
func _spawn_pickups(kind: StringName, total: int) -> void:
	_spawn_pickup_pieces(kind, total, MAX_PICKUP_PIECES)


## Spawns exactly one pickup with a gentle upward burst — used for the rare
## utility drops (magnet, health), which are always a single piece.
## `lifetime` overrides the pickup default when > 0.
func _spawn_single_pickup(kind: StringName, value: int, lifetime: float) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	var pickup := PICKUP_SCENE.instantiate() as Pickup
	var burst := Vector3(randf_range(-1.5, 1.5), randf_range(6.0, 9.0), randf_range(-1.5, 1.5))
	pickup.setup(kind, value, burst)
	if lifetime > 0.0:
		pickup.lifetime = lifetime
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector3(0.0, 1.2, 0.0)


## Split `total` reward into up to `pieces_cap` pickups and burst them out.
## `speed_mult` scales the launch (horizontal fully, vertical half-way so
## fountains spread wide without leaving orbit); `ring` spaces the pieces
## evenly around the circle for deliberate boss fountains. `lifetime` and
## `magnet_radius` override the pickup defaults when > 0.
func _spawn_pickup_pieces(kind: StringName, total: int, pieces_cap: int,
		speed_mult: float = 1.0, ring: bool = false,
		lifetime: float = 0.0, magnet_radius: float = 0.0) -> void:
	if total <= 0:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var pieces := clampi(total, 1, pieces_cap)
	var base_value := int(floor(float(total) / float(pieces)))
	var remainder := total - base_value * pieces
	var vertical_mult := (1.0 + speed_mult) * 0.5
	for i: int in pieces:
		var piece_value := base_value + (1 if i < remainder else 0)
		if piece_value <= 0:
			continue
		var pickup := PICKUP_SCENE.instantiate() as Pickup
		var angle := randf() * TAU
		if ring:
			angle = (float(i) + randf_range(-0.3, 0.3)) * TAU / float(pieces)
		var burst := Vector3(
			cos(angle) * randf_range(3.0, 6.5) * speed_mult,
			randf_range(7.0, 11.0) * vertical_mult,
			sin(angle) * randf_range(3.0, 6.5) * speed_mult)
		pickup.setup(kind, piece_value, burst)
		if lifetime > 0.0:
			pickup.lifetime = lifetime
		if magnet_radius > 0.0:
			pickup.magnet_radius = magnet_radius
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(0.0, 1.2, 0.0)
