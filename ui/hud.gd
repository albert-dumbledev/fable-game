extends CanvasLayer
## In-run HUD: health bar, run timer, kill counter, gold, damage vignette.

@onready var health_bar: ProgressBar = $TopBar/HealthBar
@onready var timer_label: Label = $TopBar/TimerLabel
@onready var kills_label: Label = $TopBar/KillsLabel
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var damage_flash: ColorRect = $DamageFlash
@onready var xp_bar: ProgressBar = $XpRow/XpBar
@onready var level_label: Label = $XpRow/LevelLabel
@onready var skill_row: HBoxContainer = $SkillRow
@onready var boss_bar: ProgressBar = $BossBar
@onready var boss_name_label: Label = $BossNameLabel
@onready var announce_label: Label = $AnnounceLabel

## Skills that show a cooldown slot once the player owns the ability.
const SKILLS: Array[Dictionary] = [
	{"id": &"dash", "key": "SPACE", "name": "Dash"},
	{"id": &"firebolt", "key": "Q", "name": "Firebolt"},
]

var _elapsed := 0.0
var _kills := 0
var _running := true
var _boss_health: HealthComponent
var _player: Player
var _skill_slots: Dictionary[StringName, SkillSlot] = {}


func _ready() -> void:
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.attack_blocked.connect(_on_attack_blocked)
	EventBus.perfect_block.connect(_on_perfect_block)
	EventBus.player_died.connect(_on_player_died)
	EventBus.xp_changed.connect(_on_xp_changed)
	EventBus.wave_announcement.connect(_on_wave_announcement)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	gold_label.text = "Gold: %d" % MetaProgression.get_currency(&"gold")
	_bind_player.call_deferred()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	timer_label.text = "%02d:%02d" % [int(_elapsed / 60.0), int(fmod(_elapsed, 60.0))]
	_update_skill_slots()


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player == null:
		return
	_player.health.health_changed.connect(_on_health_changed)
	_on_health_changed(_player.health.current, _player.health.max_health)


## Slots appear the moment an ability is owned (meta unlock or mid-run
## boon) and track remaining cooldown every frame.
func _update_skill_slots() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for skill: Dictionary in SKILLS:
		var id: StringName = skill["id"]
		if not _player.has_ability(id):
			continue
		var slot: SkillSlot = _skill_slots.get(id)
		if slot == null:
			slot = SkillSlot.new()
			slot.setup(id, skill["key"], skill["name"])
			skill_row.add_child(slot)
			_skill_slots[id] = slot
		slot.update_cooldown(
			_player.get_cooldown_remaining(id), _player.get_cooldown_max(id))


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
	damage_flash.color = Color(1.0, 0.0, 0.0, 0.35)
	var tween := create_tween()
	tween.tween_property(damage_flash, "color:a", 0.0, 0.3)


func _on_attack_blocked() -> void:
	damage_flash.color = Color(1.0, 1.0, 1.0, 0.14)
	var tween := create_tween()
	tween.tween_property(damage_flash, "color:a", 0.0, 0.2)


func _on_perfect_block() -> void:
	damage_flash.color = Color(1.0, 0.85, 0.3, 0.25)
	var tween := create_tween()
	tween.tween_property(damage_flash, "color:a", 0.0, 0.35)


func _on_xp_changed(current: int, required: int, level: int) -> void:
	xp_bar.max_value = required
	xp_bar.value = current
	level_label.text = "Lv %d" % level


func _on_wave_announcement(text: String) -> void:
	announce_label.text = text
	announce_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(announce_label, "modulate:a", 0.0, 1.0)


func _on_boss_spawned(boss: Node) -> void:
	var enemy := boss as EnemyBase
	if enemy == null:
		return
	# Rebind to the newest boss; the bar hides when it dies.
	if _boss_health != null and is_instance_valid(_boss_health):
		_boss_health.health_changed.disconnect(_on_boss_health_changed)
		_boss_health.died.disconnect(_on_boss_died)
	_boss_health = enemy.health
	_boss_health.health_changed.connect(_on_boss_health_changed)
	_boss_health.died.connect(_on_boss_died)
	boss_name_label.text = enemy.data.display_name
	boss_name_label.visible = true
	boss_bar.visible = true
	_on_boss_health_changed(_boss_health.current, _boss_health.max_health)


func _on_boss_health_changed(current: float, max_health: float) -> void:
	boss_bar.max_value = max_health
	boss_bar.value = current


func _on_boss_died() -> void:
	boss_bar.visible = false
	boss_name_label.visible = false


func _on_player_died() -> void:
	_running = false
