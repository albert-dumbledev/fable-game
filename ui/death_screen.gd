extends Control
## Death screen: run stats plus the upgrade tree, generated entirely from the
## UpgradeRegistry — one column per branch, cards gated by their
## requires_upgrade prerequisite. New upgrades never touch this script.

const BRANCHES: Array[Dictionary] = [
	{"id": &"might", "title": "MIGHT", "color": Color(0.95, 0.5, 0.4)},
	{"id": &"vigor", "title": "VIGOR", "color": Color(0.55, 0.85, 0.5)},
	{"id": &"arcana", "title": "ARCANA", "color": Color(0.6, 0.7, 1.0)},
]

## Signature colour + identity name per loadout, so the shop visibly re-themes
## when you switch weapons in the picker.
const LOADOUT_THEMES: Dictionary = {
	&"sword_and_shield": {"name": "DUELIST", "color": Color(0.55, 0.72, 0.95), "mobility": "Shift: Phantom Step"},
	&"warhammer": {"name": "EARTHSHAKER", "color": Color(0.95, 0.62, 0.32), "mobility": "Shift: Crashing Leap"},
	&"battle_staff": {"name": "ARCANIST", "color": Color(0.72, 0.55, 1.0), "mobility": "Shift: Levitate"},
}
const DEFAULT_LOADOUT_COLOR := Color(0.8, 0.8, 0.85)

@onready var title_label: Label = $Scroll/Center/Box/Title
@onready var stats_label: Label = $Scroll/Center/Box/StatsLabel
@onready var gold_label: Label = $Scroll/Center/Box/GoldLabel
@onready var loadout_label: Label = $Scroll/Center/Box/Loadout/LoadoutLabel
@onready var loadout_box: HBoxContainer = $Scroll/Center/Box/Loadout
@onready var branches_box: HBoxContainer = $Scroll/Center/Box/Branches
@onready var next_run_button: Button = $Scroll/Center/Box/Buttons/NextRunButton
@onready var menu_button: Button = $Scroll/Center/Box/Buttons/MenuButton

var _loadout_banner: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	next_run_button.pressed.connect(_on_next_run)
	menu_button.pressed.connect(_on_menu)
	var run_stats := GameManager.last_run_stats
	if run_stats.get("victory", false):
		title_label.text = "VICTORY"
		title_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.4))
	elif run_stats.get("abandoned", false):
		title_label.text = "RUN ABANDONED"
		title_label.add_theme_color_override(&"font_color", Color(0.75, 0.7, 0.6))
	var time := float(run_stats.get("time", 0.0))
	stats_label.text = "Survived %02d:%02d   |   Kills: %d   |   Gold earned: %d" % [
		int(time / 60.0),
		int(fmod(time, 60.0)),
		int(run_stats.get("kills", 0)),
		int(run_stats.get("gold", 0)),
	]
	_refresh()


func _refresh() -> void:
	var gold := MetaProgression.get_currency(&"gold")
	gold_label.text = "Gold: %d" % gold
	_refresh_loadout()
	for child: Node in branches_box.get_children():
		child.queue_free()
	_refresh_loadout_banner()
	if MetaProgression.registry == null:
		return
	var placed := 0
	for branch: Dictionary in BRANCHES:
		var column := _make_column(branch, gold)
		var count := int(column.get_meta(&"card_count", 0))
		placed += count
		if count == 0:
			column.queue_free()
			continue
		branches_box.add_child(column)
	var hidden := 0
	for upgrade: UpgradeData in MetaProgression.registry.upgrades:
		if _is_hidden(upgrade):
			hidden += 1
	if placed + hidden < MetaProgression.registry.upgrades.size():
		push_warning("Some upgrades have a branch not listed in DeathScreen.BRANCHES.")


## The theme for the currently selected loadout (falls back to a neutral grey).
func _loadout_color() -> Color:
	var theme: Dictionary = LOADOUT_THEMES.get(MetaProgression.selected_weapon, {})
	return theme.get("color", DEFAULT_LOADOUT_COLOR)


func _loadout_name() -> String:
	var theme: Dictionary = LOADOUT_THEMES.get(MetaProgression.selected_weapon, {})
	return theme.get("name", "")


func _loadout_mobility() -> String:
	var theme: Dictionary = LOADOUT_THEMES.get(MetaProgression.selected_weapon, {})
	return theme.get("mobility", "")


## Identity banner shown above the upgrade tree, themed to match the
## selected loadout's signature colour. Created lazily and kept just above
## branches_box in the Box VBoxContainer.
func _refresh_loadout_banner() -> void:
	var box := branches_box.get_parent()
	if _loadout_banner == null:
		_loadout_banner = Label.new()
		_loadout_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loadout_banner.add_theme_font_size_override(&"font_size", 26)
		box.add_child(_loadout_banner)
		box.move_child(_loadout_banner, branches_box.get_index())
	var identity := _loadout_name()
	_loadout_banner.visible = identity != ""
	var mobility := _loadout_mobility()
	_loadout_banner.text = "%s\n%s" % [identity, mobility] if mobility != "" else identity
	_loadout_banner.add_theme_color_override(&"font_color", _loadout_color())


func _make_column(branch: Dictionary, gold: int) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 4)
	var header := Label.new()
	header.text = String(branch["title"])
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override(&"font_size", 20)
	header.add_theme_color_override(&"font_color", branch["color"])
	column.add_child(header)
	var cards := 0
	for upgrade: UpgradeData in MetaProgression.registry.upgrades:
		if upgrade.branch != branch["id"]:
			continue
		if _is_hidden(upgrade):
			continue
		if cards > 0:
			var arrow := Label.new()
			arrow.text = "▼"
			arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			arrow.add_theme_font_size_override(&"font_size", 11)
			arrow.add_theme_color_override(&"font_color", Color(0.45, 0.45, 0.5))
			column.add_child(arrow)
		column.add_child(_make_card(upgrade, gold))
		cards += 1
	column.set_meta(&"card_count", cards)
	return column


func _make_card(upgrade: UpgradeData, gold: int) -> Control:
	var level := MetaProgression.get_upgrade_level(upgrade.id)
	if not _is_locked(upgrade) and upgrade.max_level > 0 and level >= upgrade.max_level:
		return _make_maxed_card(upgrade)
	var card := PanelContainer.new()
	var accent := StyleBoxFlat.new()
	accent.bg_color = Color(0.12, 0.12, 0.15, 0.9)
	accent.border_color = _loadout_color()
	accent.set_border_width_all(1)
	accent.border_width_left = 4
	accent.set_corner_radius_all(4)
	accent.content_margin_left = 2.0
	card.add_theme_stylebox_override(&"panel", accent)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_top", 6)
	margin.add_theme_constant_override(&"margin_right", 10)
	margin.add_theme_constant_override(&"margin_bottom", 6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	var name_label := Label.new()
	name_label.text = "%s  (Lv %d)" % [upgrade.display_name, level] \
			if level > 0 else upgrade.display_name
	name_label.add_theme_font_size_override(&"font_size", 17)
	box.add_child(name_label)
	var desc := Label.new()
	desc.text = upgrade.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(230, 0)
	desc.add_theme_font_size_override(&"font_size", 13)
	desc.add_theme_color_override(&"font_color", Color(0.65, 0.65, 0.7))
	box.add_child(desc)
	if _is_locked(upgrade):
		card.modulate = Color(1.0, 1.0, 1.0, 0.5)
		var lock := Label.new()
		lock.text = "Locked — %s Lv %d" % [
			_display_name_of(upgrade.requires_upgrade), upgrade.requires_level]
		lock.add_theme_font_size_override(&"font_size", 13)
		lock.add_theme_color_override(&"font_color", Color(0.85, 0.7, 0.4))
		box.add_child(lock)
	else:
		var cost := upgrade.cost_at(level)
		var buy := Button.new()
		buy.text = "Buy — %d g" % cost
		buy.disabled = gold < cost
		buy.pressed.connect(_on_buy.bind(upgrade))
		box.add_child(buy)
	margin.add_child(box)
	card.add_child(margin)
	return card


## Owned one-shot unlocks (and any maxed upgrade) collapse to a slim
## gold-highlighted chip; the description survives as a tooltip.
func _make_maxed_card(upgrade: UpgradeData) -> Control:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.17, 0.1)
	style.border_color = Color(0.92, 0.78, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	card.add_theme_stylebox_override(&"panel", style)
	card.tooltip_text = upgrade.description
	var label := Label.new()
	label.text = "✔ %s" % upgrade.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 15)
	label.add_theme_color_override(&"font_color", Color(0.92, 0.78, 0.5))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	return card


func _is_locked(upgrade: UpgradeData) -> bool:
	return upgrade.requires_upgrade != &"" \
			and MetaProgression.get_upgrade_level(upgrade.requires_upgrade) \
			< upgrade.requires_level


## Hidden until its gating ability is owned — the whole card, not just locked
## (this is how weapon subtrees appear only after the weapon's boss drop).
func _is_hidden(upgrade: UpgradeData) -> bool:
	if upgrade.loadout != &"" and upgrade.loadout != MetaProgression.selected_weapon:
		return true
	return upgrade.requires_ability != &"" \
			and not MetaProgression.get_granted_abilities().has(upgrade.requires_ability)


func _display_name_of(id: StringName) -> String:
	for upgrade: UpgradeData in MetaProgression.registry.upgrades:
		if upgrade.id == id:
			return upgrade.display_name
	return String(id)


## Loadout picker: one button per unlocked weapon, the equipped one pressed
## and disabled. Hidden entirely until a second weapon is unlocked.
func _refresh_loadout() -> void:
	for child: Node in loadout_box.get_children():
		if child != loadout_label:
			child.queue_free()
	var weapons := MetaProgression.get_unlocked_weapons()
	var visible_row := weapons.size() > 1
	loadout_box.visible = visible_row
	if not visible_row:
		return
	var selected := MetaProgression.get_selected_weapon()
	for weapon: WeaponData in weapons:
		var button := Button.new()
		button.text = weapon.display_name
		button.tooltip_text = weapon.description
		button.toggle_mode = true
		button.button_pressed = weapon == selected
		button.disabled = weapon == selected
		button.pressed.connect(_on_weapon_selected.bind(weapon))
		loadout_box.add_child(button)


func _on_weapon_selected(weapon: WeaponData) -> void:
	AudioManager.play(&"click")
	MetaProgression.select_weapon(weapon.id)
	MetaProgression.save_game()
	_refresh()


func _on_buy(upgrade: UpgradeData) -> void:
	var level := MetaProgression.get_upgrade_level(upgrade.id)
	if not MetaProgression.try_spend(&"gold", upgrade.cost_at(level)):
		return
	AudioManager.play(&"coin")
	MetaProgression.increment_upgrade(upgrade.id)
	MetaProgression.save_game()
	_refresh()


func _on_next_run() -> void:
	AudioManager.play(&"click")
	GameManager.start_run()


func _on_menu() -> void:
	AudioManager.play(&"click")
	GameManager.go_to_menu()
