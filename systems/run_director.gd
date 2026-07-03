class_name RunDirector
extends Node
## Owns one run: elapsed time, kill/gold tally, spawner pacing, and the
## death -> stats handoff to GameManager.

@onready var spawner: Spawner = $Spawner

const XP_BASE := 20
const XP_PER_LEVEL := 15

var elapsed := 0.0
var kills := 0
var gold_earned := 0
var xp := 0
var level := 0

var _run_active := true


func _ready() -> void:
	GameManager.state = GameManager.State.IN_RUN
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.run_started.emit()
	# Deferred so the HUD (readied after us) catches the initial state.
	EventBus.xp_changed.emit.call_deferred(xp, _xp_required(level), level)


func _physics_process(delta: float) -> void:
	if not _run_active:
		return
	elapsed += delta
	spawner.tick(elapsed, delta)


func _on_enemy_killed(enemy_data: Resource, _position: Vector3) -> void:
	if not _run_active:
		return
	kills += 1
	var data := enemy_data as EnemyData
	if data != null:
		gold_earned += data.gold_reward
		MetaProgression.add_currency(&"gold", data.gold_reward)
		_grant_xp(data.xp_reward)


func _grant_xp(amount: int) -> void:
	xp += amount
	while xp >= _xp_required(level):
		xp -= _xp_required(level)
		level += 1
		EventBus.level_up.emit(level)
	EventBus.xp_changed.emit(xp, _xp_required(level), level)


func _xp_required(current_level: int) -> int:
	return XP_BASE + current_level * XP_PER_LEVEL


func _on_player_died() -> void:
	if not _run_active:
		return
	_run_active = false
	MetaProgression.save_game()
	# Deferred: player_died fires mid-physics-frame; changing scene immediately
	# would yank nodes out of the tree while they still get processed this frame.
	GameManager.end_run.call_deferred({"time": elapsed, "kills": kills, "gold": gold_earned})
