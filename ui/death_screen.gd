extends Control
## Death screen: run stats plus the upgrade shop, generated entirely from the
## UpgradeRegistry so new upgrades never touch this script.

@onready var stats_label: Label = $Center/Box/StatsLabel
@onready var gold_label: Label = $Center/Box/GoldLabel
@onready var loadout_label: Label = $Center/Box/LoadoutLabel
@onready var loadout_box: HBoxContainer = $Center/Box/Loadout
@onready var upgrades_box: VBoxContainer = $Center/Box/Upgrades
@onready var next_run_button: Button = $Center/Box/NextRunButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	next_run_button.pressed.connect(_on_next_run)
	var run_stats := GameManager.last_run_stats
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
	for child: Node in upgrades_box.get_children():
		child.queue_free()
	if MetaProgression.registry == null:
		return
	for upgrade: UpgradeData in MetaProgression.registry.upgrades:
		var level := MetaProgression.get_upgrade_level(upgrade.id)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s  (Lv %d)  —  %s" % [upgrade.display_name, level, upgrade.description]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if upgrade.max_level > 0 and level >= upgrade.max_level:
			var maxed := Label.new()
			maxed.text = "MAX"
			row.add_child(maxed)
		else:
			var cost := upgrade.cost_at(level)
			var buy := Button.new()
			buy.text = "Buy — %d g" % cost
			buy.disabled = gold < cost
			buy.pressed.connect(_on_buy.bind(upgrade))
			row.add_child(buy)
		upgrades_box.add_child(row)


## Loadout picker: one button per unlocked weapon, the equipped one pressed
## and disabled. Hidden entirely until a second weapon is unlocked.
func _refresh_loadout() -> void:
	for child: Node in loadout_box.get_children():
		child.queue_free()
	var weapons := MetaProgression.get_unlocked_weapons()
	var visible_row := weapons.size() > 1
	loadout_label.visible = visible_row
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
	MetaProgression.select_weapon(weapon.id)
	MetaProgression.save_game()
	_refresh()


func _on_buy(upgrade: UpgradeData) -> void:
	var level := MetaProgression.get_upgrade_level(upgrade.id)
	if not MetaProgression.try_spend(&"gold", upgrade.cost_at(level)):
		return
	MetaProgression.increment_upgrade(upgrade.id)
	MetaProgression.save_game()
	_refresh()


func _on_next_run() -> void:
	GameManager.start_run()
