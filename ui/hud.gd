extends CanvasLayer
## In-run HUD: health bar (color ramp + ghost-damage trail), run timer,
## kill counter, count-up gold, XP bar with level-up flash, skill cooldown
## slots, boss bar, damage vignette, and the low-health heartbeat vignette.

@onready var health_bar: ProgressBar = $TopBar/HealthSlot/HealthBar
@onready var ghost_bar: ProgressBar = $TopBar/HealthSlot/GhostBar
@onready var timer_label: Label = $TopBar/TimerLabel
@onready var kills_label: Label = $TopBar/KillsLabel
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var damage_flash: ColorRect = $DamageFlash
@onready var low_health_vignette: ColorRect = $LowHealthVignette
@onready var xp_bar: ProgressBar = $XpRow/XpBar
@onready var level_label: Label = $XpRow/LevelLabel
@onready var skill_row: HBoxContainer = $SkillRow
@onready var boss_bars: VBoxContainer = $BossBars
@onready var announce_label: Label = $AnnounceLabel
@onready var streak_label: Label = $StreakLabel

## Skills that show a cooldown slot once the player owns the ability.
const SKILLS: Array[Dictionary] = [
	{"id": &"block", "key": "RMB", "name": "Block"},
	{"id": &"hammer_wave", "key": "RMB", "name": "Shockwave"},
	{"id": &"dash", "key": "SHIFT", "name": "Dash"},
	{"id": &"firebolt", "key": "RMB", "name": "Fireball"},
	{"id": &"frost_nova", "key": "E", "name": "Frost Nova"},
]

## Health bar fill ramps green -> amber -> red as health falls.
const HEALTH_FULL_COLOR := Color(0.35, 0.75, 0.35)
const HEALTH_MID_COLOR := Color(0.85, 0.65, 0.25)
const HEALTH_LOW_COLOR := Color(0.8, 0.2, 0.18)
## Below this fraction the heartbeat vignette starts pulsing.
const LOW_HEALTH_FRACTION := 0.25
## The white ghost segment lingers this long, then drains to the real value.
const GHOST_DELAY := 0.35
const GHOST_DRAIN_TIME := 0.4
const BOSS_BAR_COLOR := Color(1, 0.4, 0.35)
## Kill streak: purely cosmetic combo ticker. Shows from this many kills,
## resets after this long without one.
const STREAK_MIN := 3
const STREAK_WINDOW := 3.0

var _elapsed := 0.0
var _shown_second := -1
var _kills := 0
var _running := true
var _player: Player
var _skill_slots: Dictionary[StringName, SkillSlot] = {}
var _health_fill: StyleBoxFlat
var _mana_bar: ProgressBar
var _health_fraction := 1.0
var _heartbeat := 0.0
var _vignette_material: ShaderMaterial
var _ghost_tween: Tween
var _gold_pop_tween: Tween
var _gold_target := 0
var _gold_display := 0.0
var _streak := 0
var _streak_time := 0.0
var _streak_tween: Tween

## One bar per living boss, keyed by its health component.
var _boss_bars: Dictionary[HealthComponent, ProgressBar] = {}


func _ready() -> void:
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.attack_blocked.connect(_on_attack_blocked)
	EventBus.perfect_block.connect(_on_perfect_block)
	EventBus.player_died.connect(_on_player_died)
	EventBus.xp_changed.connect(_on_xp_changed)
	EventBus.level_up.connect(_on_level_up)
	EventBus.wave_announcement.connect(_on_wave_announcement)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.mana_cast_denied.connect(_on_cast_denied)
	_gold_target = MetaProgression.get_currency(&"gold")
	_gold_display = float(_gold_target)
	gold_label.text = "Gold: %d" % _gold_target
	_vignette_material = low_health_vignette.material as ShaderMaterial
	# Per-instance fill styleboxes so the health color ramp and the white
	# ghost trail can animate without touching the shared theme.
	_health_fill = StyleBoxFlat.new()
	_health_fill.bg_color = HEALTH_FULL_COLOR
	_health_fill.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override(&"fill", _health_fill)
	# The ghost bar underneath supplies the background; the health bar's own
	# background must be empty or it would paint over the ghost fill.
	health_bar.add_theme_stylebox_override(&"background", StyleBoxEmpty.new())
	var ghost_fill := StyleBoxFlat.new()
	ghost_fill.bg_color = Color(0.95, 0.93, 0.85, 0.8)
	ghost_fill.set_corner_radius_all(4)
	ghost_bar.add_theme_stylebox_override(&"fill", ghost_fill)
	# Mana bar: a slim strip beneath the skill row, shown only for the staff.
	_mana_bar = ProgressBar.new()
	_mana_bar.show_percentage = false
	_mana_bar.custom_minimum_size = Vector2(300.0, 10.0)
	_mana_bar.max_value = 100.0
	_mana_bar.value = 100.0
	_mana_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_mana_bar.anchor_left = 0.5
	_mana_bar.anchor_right = 0.5
	_mana_bar.offset_left = -150.0
	_mana_bar.offset_right = 150.0
	_mana_bar.offset_top = -16.0
	_mana_bar.offset_bottom = -6.0
	var mana_fill := StyleBoxFlat.new()
	mana_fill.bg_color = Color(0.35, 0.6, 1.0)
	mana_fill.set_corner_radius_all(4)
	_mana_bar.add_theme_stylebox_override(&"fill", mana_fill)
	_mana_bar.visible = false
	add_child(_mana_bar)
	_bind_player.call_deferred()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	# Rebuilding the string (and relayouting the label) only when the
	# displayed second actually changes.
	var second := int(_elapsed)
	if second != _shown_second:
		_shown_second = second
		timer_label.text = "%02d:%02d" % [floori(second / 60.0), second % 60]
	_update_skill_slots()
	_update_mana()
	# Gold ticker: races toward the target, faster the further behind, so
	# fountains read as a stream rather than a teleporting number.
	if int(_gold_display) != _gold_target:
		var rate := maxf(30.0, absf(float(_gold_target) - _gold_display) * 6.0)
		_gold_display = move_toward(_gold_display, float(_gold_target), rate * delta)
		gold_label.text = "Gold: %d" % int(_gold_display)
	if _streak > 0:
		_streak_time -= delta
		if _streak_time <= 0.0:
			_end_streak()
	_update_vignette(delta)


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
		if not _skill_owned(id):
			continue
		var slot: SkillSlot = _skill_slots.get(id)
		if slot == null:
			slot = SkillSlot.new()
			slot.setup(id, skill["key"], skill["name"])
			skill_row.add_child(slot)
			_skill_slots[id] = slot
		slot.update_cooldown(
			_player.get_cooldown_remaining(id), _player.get_cooldown_max(id))
		slot.update_charges(_player.get_charges(id), _player.get_max_charges(id))
		var cost := _player.get_mana_cost(id)
		slot.set_cost(int(cost))
		slot.set_affordable(cost <= 0.0 or _player.get_mana() >= cost)


## Mana bar tracks the staff's mana; hidden for every other loadout.
func _update_mana() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var is_staff := _player.weapon is Staff
	_mana_bar.visible = is_staff
	if is_staff:
		_mana_bar.max_value = _player.get_mana_max()
		_mana_bar.value = _player.get_mana()


## Most skills are ability flags; block/shockwave come with the weapon.
func _skill_owned(id: StringName) -> bool:
	match id:
		&"block":
			return _player.weapon != null and _player.weapon.weapon_data != null \
					and _player.weapon.weapon_data.can_block
		&"hammer_wave":
			return _player.weapon is Warhammer
		&"firebolt", &"frost_nova":
			return _player.weapon is Staff and _player.has_ability(id)
		_:
			return _player.has_ability(id)


## Heartbeat vignette: invisible until health is critical, then a red edge
## pulse that deepens the lower health gets.
func _update_vignette(delta: float) -> void:
	if _vignette_material == null:
		return
	var intensity := 0.0
	if _health_fraction > 0.0 and _health_fraction <= LOW_HEALTH_FRACTION:
		_heartbeat += delta * 5.0
		var depth := 1.0 - _health_fraction / LOW_HEALTH_FRACTION
		intensity = (0.3 + 0.4 * depth) * (0.72 + 0.28 * sin(_heartbeat))
	_vignette_material.set_shader_parameter(&"intensity", intensity)


func _on_health_changed(current: float, max_health: float) -> void:
	var previous := health_bar.value
	health_bar.max_value = max_health
	ghost_bar.max_value = max_health
	health_bar.value = current
	_health_fraction = current / maxf(max_health, 0.001)
	_health_fill.bg_color = _health_color(_health_fraction)
	if current < previous:
		# Leave the white segment at the old value for a beat, then drain.
		ghost_bar.value = maxf(ghost_bar.value, previous)
		if _ghost_tween != null:
			_ghost_tween.kill()
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(GHOST_DELAY)
		_ghost_tween.tween_property(ghost_bar, "value", current, GHOST_DRAIN_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		if _ghost_tween != null:
			_ghost_tween.kill()
		ghost_bar.value = current


func _health_color(fraction: float) -> Color:
	if fraction > 0.5:
		return HEALTH_MID_COLOR.lerp(HEALTH_FULL_COLOR, (fraction - 0.5) * 2.0)
	return HEALTH_LOW_COLOR.lerp(HEALTH_MID_COLOR, maxf(fraction - 0.2, 0.0) / 0.3)


func _on_currency_changed(id: StringName, amount: int) -> void:
	if id != &"gold":
		return
	var gained := amount > _gold_target
	_gold_target = amount
	if gained:
		gold_label.pivot_offset = gold_label.size * 0.5
		gold_label.scale = Vector2(1.25, 1.25)
		if _gold_pop_tween != null:
			_gold_pop_tween.kill()
		_gold_pop_tween = create_tween()
		_gold_pop_tween.tween_property(gold_label, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_enemy_killed(_data: Resource, _position: Vector3) -> void:
	_kills += 1
	kills_label.text = "Kills: %d" % _kills
	_streak += 1
	_streak_time = STREAK_WINDOW
	if _streak < STREAK_MIN:
		return
	streak_label.text = "COMBO ×%d" % _streak
	streak_label.modulate.a = 1.0
	streak_label.pivot_offset = streak_label.size * 0.5
	streak_label.scale = Vector2(1.25, 1.25)
	if _streak_tween != null:
		_streak_tween.kill()
	_streak_tween = create_tween()
	_streak_tween.tween_property(streak_label, "scale", Vector2.ONE, 0.15) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _end_streak() -> void:
	_streak = 0
	if _streak_tween != null:
		_streak_tween.kill()
	_streak_tween = create_tween()
	_streak_tween.tween_property(streak_label, "modulate:a", 0.0, 0.4)


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


## The mana bar flashes white when a cast is refused for lack of mana.
func _on_cast_denied() -> void:
	if _mana_bar == null:
		return
	_mana_bar.modulate = Color(1.7, 1.5, 1.5)
	var tween := create_tween()
	tween.tween_property(_mana_bar, "modulate", Color.WHITE, 0.35)


func _on_xp_changed(current: int, required: int, level: int) -> void:
	xp_bar.max_value = required
	xp_bar.value = current
	level_label.text = "Lv %d" % level


func _on_level_up(_new_level: int) -> void:
	xp_bar.modulate = Color(2.0, 1.8, 1.2)
	level_label.pivot_offset = level_label.size * 0.5
	level_label.scale = Vector2(1.4, 1.4)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(xp_bar, "modulate", Color.WHITE, 0.5)
	tween.tween_property(level_label, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_wave_announcement(text: String) -> void:
	announce_label.text = text
	announce_label.modulate.a = 1.0
	# Scale-in punch, hold, then the old fade.
	announce_label.pivot_offset = announce_label.size * 0.5
	announce_label.scale = Vector2(1.35, 1.35)
	var tween := create_tween()
	tween.tween_property(announce_label, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.7)
	tween.tween_property(announce_label, "modulate:a", 0.0, 1.0)


func _on_boss_spawned(boss: Node) -> void:
	var enemy := boss as EnemyBase
	if enemy == null or _boss_bars.has(enemy.health):
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	var label := Label.new()
	label.text = enemy.data.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.35, 0.3))
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0.0, 16.0)
	bar.show_percentage = false
	bar.modulate = BOSS_BAR_COLOR
	bar.max_value = enemy.health.max_health
	bar.value = enemy.health.current
	box.add_child(bar)
	boss_bars.add_child(box)
	_boss_bars[enemy.health] = bar
	enemy.health.health_changed.connect(_on_boss_health_changed.bind(enemy.health))
	enemy.health.died.connect(_on_boss_died.bind(enemy.health))


func _on_boss_health_changed(current: float, max_health: float,
		health: HealthComponent) -> void:
	var bar: ProgressBar = _boss_bars.get(health)
	if bar == null:
		return
	var decreased := current < bar.value
	bar.max_value = max_health
	bar.value = current
	if decreased:
		# Brief white-hot flash so boss damage registers at a glance.
		bar.modulate = Color(1.7, 1.1, 1.0)
		var tween := create_tween()
		tween.tween_property(bar, "modulate", BOSS_BAR_COLOR, 0.18)


func _on_boss_died(health: HealthComponent) -> void:
	var bar: ProgressBar = _boss_bars.get(health)
	if bar == null:
		return
	var box := bar.get_parent()
	if box != null:
		box.queue_free()
	_boss_bars.erase(health)


func _on_player_died() -> void:
	_running = false
	if _vignette_material != null:
		_vignette_material.set_shader_parameter(&"intensity", 0.0)
