extends Node
## Plays the procedurally generated SFX (see SfxFactory). Owns the SFX audio
## bus and two player pools (flat for player/UI sounds, positional for world
## events). Global combat cues attach here via EventBus so gameplay code
## stays audio-agnostic; direct play()/play_at() calls are only for
## actor-local moments (swings, casts, impacts) that have no bus signal.

const SFX_BUS := "SFX"
const POOL_SIZE := 12
const POOL_3D_SIZE := 16
## Identical sounds inside this window are dropped — a vacuumed coin fountain
## or a hammer slam into a pack must not stack 16 copies into one frame.
const MIN_REPEAT_MS := 45
## A pickup rush: this many collections inside the window plays one warm
## shimmer chord on top of the (already rate-limited) blips.
const BURST_WINDOW_MS := 250
const BURST_THRESHOLD := 12

var _sounds: Dictionary[StringName, AudioStreamWAV] = {}
var _players: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next_3d := 0
var _last_ms: Dictionary[StringName, int] = {}
var _burst_start_ms := 0
var _burst_count := 0


func _ready() -> void:
	# UI clicks and level-up stingers must play while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	_sounds = SfxFactory.build_all()
	for i: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)
	for i: int in POOL_3D_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = SFX_BUS
		player.max_distance = 45.0
		player.unit_size = 6.0
		add_child(player)
		_players_3d.append(player)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.attack_blocked.connect(play.bind(&"block"))
	EventBus.perfect_block.connect(play.bind(&"parry"))
	EventBus.player_died.connect(play.bind(&"player_death"))
	EventBus.level_up.connect(_on_level_up)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.wave_announcement.connect(_on_wave_announcement)
	EventBus.boss_spawned.connect(_on_boss_spawned)


## Flat (non-positional) one-shot: player-local and UI sounds.
func play(id: StringName, volume_db: float = 0.0, pitch_range: float = 0.08) -> void:
	var stream := _take_stream(id)
	if stream == null:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_range, 1.0 + pitch_range)
	player.play()


## Positional one-shot for world events (enemy hits/deaths, explosions).
func play_at(id: StringName, position: Vector3, volume_db: float = 0.0,
		pitch_range: float = 0.08) -> void:
	var stream := _take_stream(id)
	if stream == null:
		return
	var player := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _players_3d.size()
	player.global_position = position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_range, 1.0 + pitch_range)
	player.play()


## Looks the sound up and applies the per-id rate limit; null = don't play.
func _take_stream(id: StringName) -> AudioStreamWAV:
	var stream: AudioStreamWAV = _sounds.get(id)
	if stream == null:
		push_warning("Unknown sfx id: %s" % id)
		return null
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(id, -MIN_REPEAT_MS)) < MIN_REPEAT_MS:
		return null
	_last_ms[id] = now
	return stream


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(SFX_BUS) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, SFX_BUS)
	AudioServer.set_bus_send(index, &"Master")


func _on_enemy_killed(_enemy_data: Resource, position: Vector3) -> void:
	play_at(&"enemy_die", position, 0.0, 0.2)


func _on_player_damaged(_amount: float) -> void:
	play(&"hurt")


func _on_level_up(_new_level: int) -> void:
	play(&"level_up", 0.0, 0.0)


func _on_pickup_collected(kind: StringName, _value: int) -> void:
	if kind == &"magnet":
		play(&"magnet_collect", 0.0, 0.05)
		return
	if kind == &"health":
		play(&"health_pickup", -3.0, 0.1)
		return
	var now := Time.get_ticks_msec()
	if now - _burst_start_ms > BURST_WINDOW_MS:
		_burst_start_ms = now
		_burst_count = 0
	_burst_count += 1
	if _burst_count == BURST_THRESHOLD:
		play(&"loot_shimmer", -2.0, 0.03)
	if kind == &"gold":
		play(&"coin", -6.0, 0.18)
	else:
		play(&"xp", -8.0, 0.15)


func _on_wave_announcement(_text: String) -> void:
	play(&"alarm", -4.0, 0.0)


func _on_boss_spawned(_boss: Node) -> void:
	play(&"boss_horn", 0.0, 0.03)
