extends Control
## Rotating minimap: up is always the player's facing, so threats behind
## you sit at the bottom of the circle. Enemies beyond WORLD_RANGE clamp
## to the rim (dimmed) so approach direction is never lost.

const WORLD_RANGE := 24.0
const BLIP_RADIUS := 3.5
const BG_COLOR := Color(0.05, 0.06, 0.08, 0.55)
const RING_COLOR := Color(0.8, 0.85, 0.9, 0.5)
const PLAYER_COLOR := Color(1.0, 1.0, 1.0)
const ENEMY_COLOR := Color(0.9, 0.25, 0.25)
## Enemy is winding up or attacking — the "check your back" signal.
const ENEMY_ATTACKING_COLOR := Color(1.0, 0.62, 0.2)
const ENEMY_STUNNED_COLOR := Color(0.55, 0.7, 1.0)
## Rare bounty enemy (the Gilded One): a gold blip regardless of state.
const RARE_COLOR := Color(1.0, 0.84, 0.2)
const MAGNET_PING_COLOR := Color(0.85, 0.3, 0.95)
## Blips don't need 60 Hz; redrawing every frame was measurable on web.
const REDRAW_INTERVAL := 0.05

var _player: Player
var _redraw_accum := 0.0


func _ready() -> void:
	_bind_player.call_deferred()


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Player


func _process(delta: float) -> void:
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(center.x, center.y)
	draw_circle(center, radius, BG_COLOR)
	draw_arc(center, radius - 1.0, 0.0, TAU, 48, RING_COLOR, 2.0, true)
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	var basis := _player.global_transform.basis
	var right := Vector2(basis.x.x, basis.x.z)
	var forward := Vector2(-basis.z.x, -basis.z.z)
	var origin := Vector2(_player.global_position.x, _player.global_position.z)
	var scale_factor := radius / WORLD_RANGE
	# Read-only pass, so the live list is safe to iterate directly.
	for enemy: EnemyBase in EnemyBase.alive:
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		var offset := Vector2(enemy.global_position.x, enemy.global_position.z) - origin
		# Into view space: x along player right, y along player forward (up).
		var map_pos := Vector2(offset.dot(right), -offset.dot(forward)) * scale_factor
		var color := ENEMY_COLOR
		if enemy.data != null and enemy.data.tags.has(&"rare"):
			color = RARE_COLOR
		elif enemy.state == EnemyBase.State.WINDUP or enemy.state == EnemyBase.State.ATTACK:
			color = ENEMY_ATTACKING_COLOR
		elif enemy.state == EnemyBase.State.STUNNED:
			color = ENEMY_STUNNED_COLOR
		var blip_radius := BLIP_RADIUS
		if enemy.state == EnemyBase.State.WINDUP or enemy.state == EnemyBase.State.ATTACK:
			blip_radius = BLIP_RADIUS * 1.4
		var edge := radius - blip_radius - 2.0
		if map_pos.length() > edge:
			map_pos = map_pos.normalized() * edge
			color.a = 0.5
		draw_circle(center + map_pos, blip_radius, color)
	# Magnet pickups on the ground: a distinct ping so they read across the
	# arena, same clamp-to-rim treatment as enemies.
	for magnet: Pickup in Pickup.magnets:
		if not is_instance_valid(magnet) or not magnet.is_inside_tree():
			continue
		var offset := Vector2(magnet.global_position.x, magnet.global_position.z) - origin
		var map_pos := Vector2(offset.dot(right), -offset.dot(forward)) * scale_factor
		var color := MAGNET_PING_COLOR
		var blip_radius := BLIP_RADIUS * 1.2
		var edge := radius - blip_radius - 2.0
		if map_pos.length() > edge:
			map_pos = map_pos.normalized() * edge
			color.a = 0.5
		draw_circle(center + map_pos, blip_radius, color)
	# Player arrow, always pointing up (the facing direction).
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -8.0),
		center + Vector2(5.5, 6.0),
		center + Vector2(-5.5, 6.0),
	]), PLAYER_COLOR)
