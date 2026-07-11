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
var _victory_banner: Label
var _depth_box: HBoxContainer
var _depth_label: Label


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
	stats_label.text = "Survived %s   |   Kills: %d   |   Level: %d   |   Gold earned: %d" % [
		_format_time(time),
		int(run_stats.get("kills", 0)),
		int(run_stats.get("level", 0)),
		int(run_stats.get("gold", 0)),
	]
	_build_victory_banner(run_stats)
	_build_run_recap(run_stats)
	_refresh()


func _refresh() -> void:
	var gold := MetaProgression.get_currency(&"gold")
	gold_label.text = "Gold: %d" % gold
	_refresh_loadout()
	_refresh_depth()
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


## --- Depth victory banners (docs/DEPTHS.md) -------------------------------
## The moment-defining lines for the first-ever Revenant kill and each
## Depth's first clear. Re-clears and Surface re-wins get no second banner —
## the plain "VICTORY" title already covers those.
func _victory_banner_text(run_stats: Dictionary) -> String:
	if not run_stats.get("victory", false):
		return ""
	var new_records: Array = run_stats.get("new_records", [])
	var depth := int(run_stats.get("depth", 0))
	if depth > 0 and new_records.has("best_depth"):
		var max_level := 0
		if MetaProgression.depth_registry != null:
			max_level = MetaProgression.depth_registry.max_level()
		if depth >= max_level:
			return "DEPTH %s CLEARED — THE LADDER ENDS HERE" % DepthData.numeral(depth)
		return "DEPTH %s CLEARED — DEPTH %s UNLOCKED" % [
			DepthData.numeral(depth), DepthData.numeral(depth + 1)]
	if int(MetaProgression.records.get("victories", 0)) == 1:
		return "THE WAY DOWN OPENS — DEPTH I UNLOCKED"
	return ""


## Builds (once) and shows the banner Label just below Title when
## _victory_banner_text has something to say; a no-op otherwise — the death
## and abandon paths, and ordinary re-clear victories, never grow this label.
func _build_victory_banner(run_stats: Dictionary) -> void:
	var text := _victory_banner_text(run_stats)
	if text == "":
		return
	if _victory_banner == null:
		_victory_banner = Label.new()
		_victory_banner.name = "VictoryBanner"
		_victory_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_victory_banner.add_theme_font_size_override(&"font_size", 20)
		_victory_banner.add_theme_color_override(&"font_color", Color(0.55, 0.85, 1.0))
		var box := title_label.get_parent()
		box.add_child(_victory_banner)
		box.move_child(_victory_banner, title_label.get_index() + 1)
	_victory_banner.text = text


## --- Run Recap (docs/RUN_RECAP.md) ---------------------------------------
## Killer headline, recap panel, and lifetime-records line, code-built and
## inserted into the Box VBox around StatsLabel. Built once from the frozen
## GameManager.last_run_stats / MetaProgression.records — unlike the shop
## below, none of this changes as the player buys upgrades, so it never
## needs to be rebuilt from _refresh().
func _build_run_recap(run_stats: Dictionary) -> void:
	var box := stats_label.get_parent()
	var recap: Dictionary = run_stats.get("recap", {})
	var is_death: bool = not run_stats.get("victory", false) and not run_stats.get("abandoned", false)
	var killer_name: String = recap.get("killer_name", "")
	if is_death and killer_name != "":
		var headline := Label.new()
		headline.text = "Slain by %s" % killer_name.to_upper()
		headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		headline.add_theme_font_size_override(&"font_size", 20)
		headline.add_theme_color_override(&"font_color", Color(0.9, 0.45, 0.4))
		box.add_child(headline)
		box.move_child(headline, stats_label.get_index())

	var insert_at := stats_label.get_index() + 1
	var panel := _make_recap_panel(recap)
	if panel != null:
		box.add_child(panel)
		box.move_child(panel, insert_at)
		insert_at += 1

	var records_line := _make_records_line(run_stats)
	if records_line != null:
		box.add_child(records_line)
		box.move_child(records_line, insert_at)


## mm:ss formatting shared by the stats line, boss kill times, and records.
func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60.0), int(fmod(seconds, 60.0))]


## Three-column recap panel (BOONS / SLAIN / DAMAGE TAKEN). Returns null (and
## builds nothing) when the run has no recap data or every column is empty —
## covers the {} last_run_stats case (scene opened directly).
func _make_recap_panel(recap: Dictionary) -> Control:
	if recap.is_empty():
		return null
	var columns: Array[Control] = []
	var boons_column := _make_recap_column("BOONS", Color(0.72, 0.55, 1.0), _boon_rows(recap))
	if boons_column != null:
		columns.append(boons_column)
	var slain_column := _make_recap_column("SLAIN", Color(0.95, 0.5, 0.4), _slain_rows(recap))
	if slain_column != null:
		columns.append(slain_column)
	var damage_column := _make_recap_column(
			"DAMAGE TAKEN", Color(0.55, 0.85, 0.5), _damage_rows(recap), _damage_total_row(recap))
	if damage_column != null:
		columns.append(damage_column)
	if columns.is_empty():
		return null

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.85)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override(&"panel", style)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 20)
	for column: Control in columns:
		hbox.add_child(column)
	panel.add_child(hbox)
	return panel


## Generic recap column: header, up to 8 rows, a dim "+N more" tail if there
## were more, then an optional pinned row (e.g. the damage "Total" line) that
## always shows and isn't counted against the cap. Returns null when there's
## nothing at all to show.
func _make_recap_column(
		title: String, header_color: Color, rows: Array[Dictionary],
		pinned: Dictionary = {}) -> Control:
	if rows.is_empty() and pinned.is_empty():
		return null
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(200, 0)
	column.add_theme_constant_override(&"separation", 3)
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override(&"font_size", 15)
	header.add_theme_color_override(&"font_color", header_color)
	column.add_child(header)
	for row: Dictionary in rows.slice(0, 8):
		var label := Label.new()
		label.text = String(row.get("text", ""))
		label.add_theme_font_size_override(&"font_size", 13)
		label.add_theme_color_override(&"font_color", row.get("color", Color(0.8, 0.8, 0.85)))
		column.add_child(label)
	if rows.size() > 8:
		var more := Label.new()
		more.text = "+%d more" % (rows.size() - 8)
		more.add_theme_font_size_override(&"font_size", 12)
		more.add_theme_color_override(&"font_color", Color(0.5, 0.5, 0.55))
		column.add_child(more)
	if not pinned.is_empty():
		var total := Label.new()
		total.text = String(pinned.get("text", ""))
		total.add_theme_font_size_override(&"font_size", 13)
		total.add_theme_color_override(&"font_color", pinned.get("color", Color(0.9, 0.9, 0.95)))
		column.add_child(total)
	return column


## Aspects (gold, on top) then boons in pick order. Duplicate boon ids
## collapse to "name ×N", tinted with the highest-mult copy's colour.
func _boon_rows(recap: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for aspect: Dictionary in recap.get("aspects", []):
		rows.append({
			"text": "◆ %s" % String(aspect.get("name", "")),
			"color": Color(1.0, 0.78, 0.2),
		})
	var groups: Dictionary = {}
	var order: Array[String] = []
	for boon: Dictionary in recap.get("boons", []):
		var id := String(boon.get("id", boon.get("name", "")))
		var mult := float(boon.get("mult", 1.0))
		var color: Color = boon.get("color", Color(0.8, 0.8, 0.85))
		if groups.has(id):
			var g: Dictionary = groups[id]
			g["count"] = int(g["count"]) + 1
			if mult > float(g["mult"]):
				g["mult"] = mult
				g["color"] = color
			groups[id] = g
		else:
			groups[id] = {"name": String(boon.get("name", "")), "color": color, "mult": mult, "count": 1}
			order.append(id)
	for id: String in order:
		var g: Dictionary = groups[id]
		var count := int(g["count"])
		var text: String = String(g["name"]) if count <= 1 else "%s ×%d" % [g["name"], count]
		rows.append({"text": text, "color": g["color"]})
	return rows


## Kills-by-enemy sorted by count desc; bosses are pulled to the top with a
## skull prefix and their kill-clock time (matched against recap.bosses by
## display name).
func _slain_rows(recap: Dictionary) -> Array[Dictionary]:
	var kills: Dictionary = recap.get("kills_by_enemy", {})
	var enemies: Array[Dictionary] = []
	for id: StringName in kills:
		var entry: Dictionary = kills[id]
		enemies.append({"name": String(entry.get("name", "")), "count": int(entry.get("count", 0))})
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) > int(b["count"]))
	var boss_times: Dictionary = {}
	for boss: Dictionary in recap.get("bosses", []):
		boss_times[String(boss.get("name", ""))] = float(boss.get("t", 0.0))
	var boss_rows: Array[Dictionary] = []
	var normal_rows: Array[Dictionary] = []
	for enemy: Dictionary in enemies:
		var name: String = enemy["name"]
		var count: int = enemy["count"]
		if boss_times.has(name):
			boss_rows.append({
				"text": "☠ %s  ×%d  %s" % [name, count, _format_time(boss_times[name])],
				"color": Color(1.0, 0.78, 0.2),
			})
		else:
			normal_rows.append({"text": "%s  ×%d" % [name, count], "color": Color(0.8, 0.8, 0.85)})
	var rows: Array[Dictionary] = []
	rows.append_array(boss_rows)
	rows.append_array(normal_rows)
	return rows


## Damage-taken-by-enemy sorted by dmg desc (the "Total" row is built
## separately by _damage_total_row so it can be pinned below the cap).
func _damage_rows(recap: Dictionary) -> Array[Dictionary]:
	var taken: Dictionary = recap.get("damage_taken", {})
	var enemies: Array[Dictionary] = []
	for id: StringName in taken:
		var entry: Dictionary = taken[id]
		enemies.append({
			"name": String(entry.get("name", "")),
			"dmg": float(entry.get("dmg", 0.0)),
			"hits": int(entry.get("hits", 0)),
		})
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dmg"]) > float(b["dmg"]))
	var rows: Array[Dictionary] = []
	for enemy: Dictionary in enemies:
		rows.append({
			"text": "%s  %d (%d hits)" % [enemy["name"], roundi(float(enemy["dmg"])), int(enemy["hits"])],
			"color": Color(0.8, 0.8, 0.85),
		})
	return rows


func _damage_total_row(recap: Dictionary) -> Dictionary:
	var taken: Dictionary = recap.get("damage_taken", {})
	if taken.is_empty():
		return {}
	return {
		"text": "Total  %d (%d hits)" % [
			roundi(float(recap.get("damage_taken_total", 0.0))),
			int(recap.get("hits_taken", 0)),
		],
		"color": Color(0.95, 0.95, 0.98),
	}


## Lifetime-bests strip: "BEST — Longest run mm:ss · Kills N · Level N ·
## Gold N · Victories N [· Fastest victory mm:ss]", built as individual
## Labels so any record newly set this run gets its own gold "NEW BEST!"
## chip. Returns null when there are no records yet (fresh save).
func _make_records_line(run_stats: Dictionary) -> Control:
	var records: Dictionary = MetaProgression.records
	if records.is_empty():
		return null
	var new_records: Array = run_stats.get("new_records", [])
	var entries: Array[Dictionary] = []
	_add_record_entry(entries, records, new_records, "longest_run", "Longest run", true)
	_add_record_entry(entries, records, new_records, "most_kills", "Kills", false)
	_add_record_entry(entries, records, new_records, "best_level", "Level", false)
	_add_record_entry(entries, records, new_records, "most_gold", "Gold", false)
	_add_record_entry(entries, records, new_records, "victories", "Victories", false)
	_add_record_entry(entries, records, new_records, "fastest_victory", "Fastest victory", true)
	_add_depth_record_entry(entries, records, new_records)
	if entries.is_empty():
		return null

	var center := CenterContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 6)
	var prefix := Label.new()
	prefix.text = "BEST —"
	prefix.add_theme_font_size_override(&"font_size", 13)
	prefix.add_theme_color_override(&"font_color", Color(0.65, 0.65, 0.7))
	hbox.add_child(prefix)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var label := Label.new()
		label.text = "%s %s" % [String(entry["label"]), String(entry["value"])]
		label.add_theme_font_size_override(&"font_size", 13)
		label.add_theme_color_override(&"font_color", Color(0.65, 0.65, 0.7))
		hbox.add_child(label)
		if entry["is_new"]:
			var chip := Label.new()
			chip.text = "NEW BEST!"
			chip.add_theme_font_size_override(&"font_size", 12)
			chip.add_theme_color_override(&"font_color", Color(1.0, 0.78, 0.2))
			hbox.add_child(chip)
		if i < entries.size() - 1:
			var dot := Label.new()
			dot.text = "·"
			dot.add_theme_font_size_override(&"font_size", 13)
			dot.add_theme_color_override(&"font_color", Color(0.65, 0.65, 0.7))
			hbox.add_child(dot)
	center.add_child(hbox)
	return center


## Appends a {label, value, is_new} entry unless the record is unset — every
## records field defaults to 0 until it's first achieved, which doubles as
## "omit this entry" per the design.
func _add_record_entry(
		entries: Array[Dictionary], records: Dictionary, new_records: Array,
		key: String, label: String, is_time: bool) -> void:
	var value := float(records.get(key, 0.0))
	if value <= 0.0:
		return
	var formatted := _format_time(value) if is_time else str(int(value))
	entries.append({"label": label, "value": formatted, "is_new": new_records.has(key)})


## Deepest Depth cleared (docs/DEPTHS.md), roman-numeralled instead of the raw
## int/time formatting _add_record_entry uses — same {label, value, is_new}
## shape so it drops into the same row, NEW BEST chip included.
func _add_depth_record_entry(
		entries: Array[Dictionary], records: Dictionary, new_records: Array) -> void:
	var best := int(records.get("best_depth", 0))
	if best <= 0:
		return
	entries.append({
		"label": "Deepest",
		"value": DepthData.numeral(best),
		"is_new": new_records.has("best_depth"),
	})


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


## Depth picker (docs/DEPTHS.md): SURFACE + one button per unlocked Depth,
## mirroring _refresh_loadout exactly — toggle-mode buttons, the current
## selection pressed+disabled. Hidden entirely until the first victory opens
## Depth I; locked Depths beyond max_selectable_depth() are never shown (no
## tease-noise). The row itself is code-built (lazily created once) since this
## screen has no scene edits, same as _loadout_banner below.
func _refresh_depth() -> void:
	if _depth_box == null:
		_depth_box = HBoxContainer.new()
		_depth_box.name = "DepthPicker"
		_depth_box.add_theme_constant_override(&"separation", 10)
		_depth_box.alignment = BoxContainer.ALIGNMENT_CENTER
		_depth_label = Label.new()
		_depth_label.text = "Depth:"
		_depth_label.add_theme_font_size_override(&"font_size", 18)
		_depth_box.add_child(_depth_label)
		loadout_box.get_parent().add_child(_depth_box)
	loadout_box.get_parent().move_child(_depth_box, loadout_box.get_index() + 1)
	for child: Node in _depth_box.get_children():
		if child != _depth_label:
			child.queue_free()
	var max_depth := MetaProgression.max_selectable_depth()
	_depth_box.visible = max_depth > 0
	if max_depth == 0:
		return
	# An edited/stale save's selection clamps down to the unlocked range —
	# the clamped value is what reads as selected, same as get_selected_depth_data.
	var selected := clampi(MetaProgression.selected_depth, 0, max_depth)
	for level: int in range(max_depth + 1):
		var button := Button.new()
		button.text = "SURFACE" if level == 0 else DepthData.numeral(level)
		if level > 0 and MetaProgression.depth_registry != null:
			var depth_data := MetaProgression.depth_registry.get_depth(level)
			if depth_data != null:
				button.tooltip_text = depth_data.display_name
		button.toggle_mode = true
		button.button_pressed = level == selected
		button.disabled = level == selected
		button.pressed.connect(_on_depth_selected.bind(level))
		_depth_box.add_child(button)


func _on_depth_selected(level: int) -> void:
	AudioManager.play(&"click")
	MetaProgression.select_depth(level)
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
