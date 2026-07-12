extends Control
## Loadout screen: the pre-run hub. Pick a weapon and a Depth, read the
## loadout×Depth badge grid, and spend at the two upgrade shops before starting
## a run. The gold shop (might/vigor/arcana) and the shard-priced Reliquary read
## as two separate sections. Both shops are generated entirely from the
## UpgradeRegistry — one column per branch, cards gated by their
## requires_upgrade prerequisite. New upgrades never touch this script.
##
## Split out of the death screen (2026-07-12): the recap of the run just played
## stays in ui/death_screen.gd; "Continue" there hands off here.

## Gold branches (docs/DEPTHS.md Lane 2): rendered side by side in the loadout
## shop, one column each, all priced in gold.
const GOLD_BRANCHES: Array[Dictionary] = [
	{"id": &"might", "title": "MIGHT", "color": Color(0.95, 0.5, 0.4)},
	{"id": &"vigor", "title": "VIGOR", "color": Color(0.55, 0.85, 0.5)},
	{"id": &"arcana", "title": "ARCANA", "color": Color(0.6, 0.7, 1.0)},
]

## The Reliquary (docs/DEPTHS.md Lane 2): a shard-priced branch, hidden until
## the first victory (gated in _is_hidden), themed to the shard-violet. Rendered
## on its own below the gold shop, in a bordered panel, so it reads as a second
## shop rather than a fourth column.
const RELIQUARY_BRANCH: Dictionary = {
	"id": &"reliquary", "title": "RELIQUARY", "color": Color(0.74, 0.62, 0.96)}

## Signature colour + identity name per loadout, so the shop visibly re-themes
## when you switch weapons in the picker.
const LOADOUT_THEMES: Dictionary = {
	&"sword_and_shield": {"name": "DUELIST", "color": Color(0.55, 0.72, 0.95), "mobility": "Shift: Phantom Step"},
	&"warhammer": {"name": "EARTHSHAKER", "color": Color(0.95, 0.62, 0.32), "mobility": "Shift: Crashing Leap"},
	&"battle_staff": {"name": "ARCANIST", "color": Color(0.72, 0.55, 1.0), "mobility": "Shift: Levitate"},
}
const DEFAULT_LOADOUT_COLOR := Color(0.8, 0.8, 0.85)

@onready var gold_label: Label = $Scroll/Center/Box/GoldLabel
@onready var loadout_label: Label = $Scroll/Center/Box/Loadout/LoadoutLabel
@onready var loadout_box: HBoxContainer = $Scroll/Center/Box/Loadout
@onready var branches_box: HBoxContainer = $Scroll/Center/Box/Branches
@onready var reliquary_box: VBoxContainer = $Scroll/Center/Box/Reliquary
@onready var start_run_button: Button = $Scroll/Center/Box/Buttons/StartRunButton
@onready var menu_button: Button = $Scroll/Center/Box/Buttons/MenuButton

var _loadout_banner: Label
var _depth_box: HBoxContainer
var _depth_label: Label
var _depth_grid: VBoxContainer


func _ready() -> void:
	GameManager.state = GameManager.State.LOADOUT
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_run_button.pressed.connect(_on_start_run)
	menu_button.pressed.connect(_on_menu)
	start_run_button.grab_focus()
	_refresh()


func _refresh() -> void:
	var gold := MetaProgression.get_currency(&"gold")
	gold_label.text = "Gold: %d" % gold
	_refresh_loadout()
	_refresh_depth()
	_refresh_badge_grid()
	for child: Node in branches_box.get_children():
		child.queue_free()
	for child: Node in reliquary_box.get_children():
		child.queue_free()
	_refresh_loadout_banner()
	if MetaProgression.registry == null:
		return
	var placed := 0
	# --- Loadout shop: the gold branches, side by side ---
	for branch: Dictionary in GOLD_BRANCHES:
		var column := _make_column(branch)
		var count := int(column.get_meta(&"card_count", 0))
		placed += count
		if count == 0:
			column.queue_free()
			continue
		branches_box.add_child(column)
	# --- Reliquary shop: the shard branch in its own bordered panel below ---
	var rel_column := _make_column(RELIQUARY_BRANCH)
	var rel_count := int(rel_column.get_meta(&"card_count", 0))
	placed += rel_count
	reliquary_box.visible = rel_count > 0
	if rel_count == 0:
		rel_column.queue_free()
	else:
		reliquary_box.add_child(_make_reliquary_panel(rel_column))
	var hidden := 0
	for upgrade: UpgradeData in MetaProgression.registry.upgrades:
		if _is_hidden(upgrade):
			hidden += 1
	if placed + hidden < MetaProgression.registry.upgrades.size():
		push_warning("Some upgrades have a branch not listed in LoadoutScreen branches.")


## Wraps the Reliquary column in a shard-violet-bordered panel so the shard
## shop reads as its own section rather than a fourth gold column. The column's
## own header already carries the shard balance ("RELIQUARY — N ◆").
func _make_reliquary_panel(column: Control) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.09, 0.15, 0.9)
	style.border_color = Color(0.74, 0.62, 0.96)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override(&"panel", style)
	panel.add_child(column)
	return panel


## mm:ss formatting shared by the badge-grid tooltips (matches the recap
## screen's own copy).
func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60.0), int(fmod(seconds, 60.0))]


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
		_loadout_banner.name = "LoadoutBanner"
		_loadout_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loadout_banner.add_theme_font_size_override(&"font_size", 26)
		box.add_child(_loadout_banner)
		box.move_child(_loadout_banner, branches_box.get_index())
	var identity := _loadout_name()
	_loadout_banner.visible = identity != ""
	var lines: Array[String] = [identity]
	var mobility := _loadout_mobility()
	if mobility != "":
		lines.append(mobility)
	var title := _loadout_title()
	if title != "":
		lines.append(title)
	_loadout_banner.text = "\n".join(lines)
	_loadout_banner.add_theme_color_override(&"font_color", _loadout_color())


## "DUELIST OF THE THIRD" (docs/DEPTHS.md): the selected loadout's identity
## word plus an ordinal built from MetaProgression.deepest_clear_for, the same
## lookup the weapon trim tints from. Display-only; no clears yet -> "".
func _loadout_title() -> String:
	var identity := _loadout_name()
	if identity == "":
		return ""
	var deepest := MetaProgression.deepest_clear_for(MetaProgression.selected_weapon)
	if deepest <= 0:
		return ""
	return "%s OF THE %s" % [identity, DepthData.ordinal_word(deepest)]


func _make_column(branch: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 4)
	var header := Label.new()
	header.text = _branch_header(branch)
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
		column.add_child(_make_card(upgrade))
		cards += 1
	column.set_meta(&"card_count", cards)
	return column


## A branch header (docs/DEPTHS.md Lane 2): the plain title for gold branches, or
## "TITLE — N ◆" for a branch priced in a non-gold currency (the Reliquary), so
## the shard balance reads right where you spend it — echoing the top gold label's
## always-visible-balance idea, per-column since only this branch is non-gold.
func _branch_header(branch: Dictionary) -> String:
	var title := String(branch["title"])
	var currency := _branch_currency(branch["id"])
	if currency == &"gold":
		return title
	return "%s — %d %s" % [title, MetaProgression.get_currency(currency), _currency_label(currency)]


## The (single) non-gold currency a branch charges in, or &"gold" if all its nodes
## are gold — read from the registry so the header follows the data, not a hardcode.
func _branch_currency(branch_id: StringName) -> StringName:
	for upgrade: UpgradeData in MetaProgression.registry.upgrades:
		if upgrade.branch == branch_id and upgrade.currency != &"gold":
			return upgrade.currency
	return &"gold"


## Short currency tag for buy buttons + headers: "g" for gold, "◆" for shards
## (the same diamond the recap uses for Aspects — a glyph the shipped font has).
func _currency_label(currency: StringName) -> String:
	return "g" if currency == &"gold" else "◆"


func _make_card(upgrade: UpgradeData) -> Control:
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
		# Affordability greys against this node's own currency balance (docs/DEPTHS.md
		# Lane 2) — shards for the Reliquary, gold for everything else.
		var balance := MetaProgression.get_currency(upgrade.currency)
		var buy := Button.new()
		buy.text = "Buy — %d %s" % [cost, _currency_label(upgrade.currency)]
		buy.disabled = balance < cost
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
## (this is how weapon subtrees appear only after the weapon's boss drop). The
## Reliquary adds two Depth gates (docs/DEPTHS.md Lane 2): the whole branch stays
## hidden until the first victory (same gate as the depth picker), and any node
## whose requires_depth outruns the deepest clear stays hidden until that Depth
## falls — so the shop reads as a map of the descent.
func _is_hidden(upgrade: UpgradeData) -> bool:
	if upgrade.loadout != &"" and upgrade.loadout != MetaProgression.selected_weapon:
		return true
	if upgrade.branch == &"reliquary" \
			and int(MetaProgression.records.get("victories", 0)) < 1:
		return true
	if upgrade.requires_depth > int(MetaProgression.records.get("best_depth", 0)):
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


## Loadout x Depth badge grid (docs/DEPTHS.md Lane 3): one row per unlocked
## loadout (weapon registry order, via get_unlocked_weapons), one column per
## authored Depth. Cleared cells read purely from records.depth_wins (no new
## save data) and light up in that Depth's theme_color; uncleared cells stay
## dim/empty. Hidden entirely until the first Depth clear — the picker alone
## covers the pre-Depth state, same hide-entirely idiom as _refresh_depth.
## Rebuilt each _refresh() like the pickers above it; cells are named
## Cell_<loadout>_<level> so the smoke test can key a specific cell without
## depending on layout.
func _refresh_badge_grid() -> void:
	if _depth_grid == null:
		_depth_grid = VBoxContainer.new()
		_depth_grid.name = "DepthGrid"
		_depth_grid.add_theme_constant_override(&"separation", 3)
		loadout_box.get_parent().add_child(_depth_grid)
	loadout_box.get_parent().move_child(_depth_grid, _depth_box.get_index() + 1)
	for child: Node in _depth_grid.get_children():
		child.queue_free()
	var best := int(MetaProgression.records.get("best_depth", 0))
	_depth_grid.visible = best >= 1
	if best < 1 or MetaProgression.depth_registry == null:
		return
	var max_level := MetaProgression.depth_registry.max_level()
	if max_level <= 0:
		return
	for weapon: WeaponData in MetaProgression.get_unlocked_weapons():
		_depth_grid.add_child(_make_grid_row(weapon, max_level))


func _make_grid_row(weapon: WeaponData, max_level: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % weapon.id
	row.add_theme_constant_override(&"separation", 4)
	var theme: Dictionary = LOADOUT_THEMES.get(weapon.id, {})
	var label := Label.new()
	label.text = String(theme.get("name", weapon.display_name))
	label.custom_minimum_size = Vector2(90, 0)
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", theme.get("color", DEFAULT_LOADOUT_COLOR))
	row.add_child(label)
	for level: int in range(1, max_level + 1):
		row.add_child(_make_grid_cell(weapon.id, level))
	return row


## A single loadout x Depth cell. Cleared reads purely from
## records.depth_wins[str(level)].loadouts containing this loadout's id — no
## new save data. The tooltip carries the per-Depth fastest on cleared cells.
func _make_grid_cell(loadout: StringName, level: int) -> Control:
	var wins: Dictionary = MetaProgression.records.get("depth_wins", {})
	var entry: Dictionary = wins.get(str(level), {})
	var loadouts: Array = entry.get("loadouts", [])
	var cleared := loadouts.has(String(loadout))
	var cell := PanelContainer.new()
	cell.name = "Cell_%s_%d" % [loadout, level]
	cell.custom_minimum_size = Vector2(16, 16)
	cell.set_meta(&"cleared", cleared)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	if cleared:
		var depth_data: DepthData = MetaProgression.depth_registry.get_depth(level)
		style.bg_color = depth_data.theme_color if depth_data != null else Color.WHITE
		cell.tooltip_text = "DEPTH %s — fastest %s" % [
			DepthData.numeral(level), _format_time(float(entry.get("fastest", 0.0)))]
	else:
		style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
		cell.tooltip_text = "DEPTH %s" % DepthData.numeral(level)
	cell.add_theme_stylebox_override(&"panel", style)
	return cell


func _on_buy(upgrade: UpgradeData) -> void:
	var level := MetaProgression.get_upgrade_level(upgrade.id)
	# Charge the node's own currency (docs/DEPTHS.md Lane 2) — gold leaves gold
	# untouched, Reliquary nodes spend shards.
	if not MetaProgression.try_spend(upgrade.currency, upgrade.cost_at(level)):
		return
	AudioManager.play(&"coin")
	MetaProgression.increment_upgrade(upgrade.id)
	MetaProgression.save_game()
	_refresh()


func _on_start_run() -> void:
	AudioManager.play(&"click")
	GameManager.start_run()


func _on_menu() -> void:
	AudioManager.play(&"click")
	GameManager.go_to_menu()
