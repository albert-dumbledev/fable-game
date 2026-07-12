extends Control
## Death/victory screen: the recap of the run just played — title (YOU DIED /
## VICTORY / RUN ABANDONED), any depth-clear banner, the killer headline, the
## stats line, the BOONS/SLAIN/DAMAGE recap panel, and the lifetime-records
## "BEST —" line. All of it is built once from the frozen
## GameManager.last_run_stats / MetaProgression.records — nothing here changes
## after _ready, so there is no _refresh loop.
##
## The pre-run hub — loadout picker, depth picker, badge grid, and the two
## upgrade shops — lives in ui/loadout_screen.gd (split out 2026-07-12);
## "Continue" hands off there.

@onready var title_label: Label = $Scroll/Center/Box/Title
@onready var stats_label: Label = $Scroll/Center/Box/StatsLabel
@onready var gold_label: Label = $Scroll/Center/Box/GoldLabel
@onready var continue_button: Button = $Scroll/Center/Box/Buttons/ContinueButton
@onready var menu_button: Button = $Scroll/Center/Box/Buttons/MenuButton

var _victory_banner: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	continue_button.pressed.connect(_on_continue)
	menu_button.pressed.connect(_on_menu)
	continue_button.grab_focus()
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
	gold_label.text = "Gold: %d" % MetaProgression.get_currency(&"gold")
	_build_victory_banner(run_stats)
	_build_run_recap(run_stats)


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
## GameManager.last_run_stats / MetaProgression.records — none of this changes
## after _ready, so it never needs to be rebuilt.
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
	_add_depth_fastest_entries(entries, records, new_records)
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


## Per-Depth fastest NEW BEST surfacing (docs/DEPTHS.md M4). depth_wins has no
## flat top-level records key (each Depth's fastest lives nested at
## depth_wins[N].fastest), so _add_record_entry's generic records.get(key)
## lookup can't reach it — this walks new_records for "depth_fastest_<N>"
## instead and pulls the time straight out of depth_wins. Unlike the other
## entries there is no persistent "current best" slot to keep showing
## afterward, so a per-Depth fastest only ever appears the run it's set —
## NEW-BEST-or-nothing by design, which is exactly what a record-setting deep
## clear needs to badge correctly.
func _add_depth_fastest_entries(
		entries: Array[Dictionary], records: Dictionary, new_records: Array) -> void:
	var wins: Dictionary = records.get("depth_wins", {})
	for key: String in new_records:
		if not key.begins_with("depth_fastest_"):
			continue
		var level := int(key.trim_prefix("depth_fastest_"))
		var entry: Dictionary = wins.get(str(level), {})
		var fastest := float(entry.get("fastest", 0.0))
		if fastest <= 0.0:
			continue
		entries.append({
			"label": "FASTEST — DEPTH %s" % DepthData.numeral(level),
			"value": _format_time(fastest),
			"is_new": true,
		})


func _on_continue() -> void:
	AudioManager.play(&"click")
	GameManager.go_to_loadout()


func _on_menu() -> void:
	AudioManager.play(&"click")
	GameManager.go_to_menu()
