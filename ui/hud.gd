extends CanvasLayer
## In-run HUD: health bar, run timer, kill counter, gold, damage vignette.

@onready var health_bar: ProgressBar = $TopBar/HealthBar
@onready var timer_label: Label = $TopBar/TimerLabel
@onready var kills_label: Label = $TopBar/KillsLabel
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var damage_flash: ColorRect = $DamageFlash

var _elapsed := 0.0
var _kills := 0
var _running := true


func _ready() -> void:
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	gold_label.text = "Gold: %d" % MetaProgression.get_currency(&"gold")
	_bind_player.call_deferred()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	timer_label.text = "%02d:%02d" % [int(_elapsed / 60.0), int(fmod(_elapsed, 60.0))]


func _bind_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		return
	player.health.health_changed.connect(_on_health_changed)
	_on_health_changed(player.health.current, player.health.max_health)


func _on_health_changed(current: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = current


func _on_currency_changed(id: StringName, amount: int) -> void:
	if id == &"gold":
		gold_label.text = "Gold: %d" % amount


func _on_enemy_killed(_data: Resource, _position: Vector3) -> void:
	_kills += 1
	kills_label.text = "Kills: %d" % _kills


func _on_player_damaged(_amount: float) -> void:
	damage_flash.color.a = 0.35
	var tween := create_tween()
	tween.tween_property(damage_flash, "color:a", 0.0, 0.3)


func _on_player_died() -> void:
	_running = false
