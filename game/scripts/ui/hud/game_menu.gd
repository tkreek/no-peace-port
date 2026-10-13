class_name GameMenu
extends RefCounted
## The in-game menu (Esc; it pauses the game): continue, save, load, options, restart, back
## to the main menu; in a skirmish or network game the diplomacy page. Also the statistics
## shown after a game.

const DONE_COLOR := Color(0.62, 0.56, 0.45)  ## a mission goal done, crossed out

var hud: Hud
var _panel: Control  # the open menu (its dimmed backdrop), or null
var _rows := {}  # the diplomacy page's rows while it is open: people -> its controls
var _recipients := {}  # people -> true: who the diplomacy page's resource buttons send to
var _stock: Label  # the diplomacy page's line with our stockpile


func _init(owner: Hud) -> void:
	hud = owner


func is_open() -> bool:
	return _panel != null


func toggle() -> void:
	if _panel:
		_close()
		return
	var diplomacy := [[GameData.menu_text(58, "Diplomacy"), show_diplomacy]] if Diplomacy.negotiable else []
	if Net.active:
		# The others play on: no pause, and nothing to save or restart alone.
		_panel = _menu_panel(GameData.menu_text(50, "Settings"), [
			[GameData.menu_text(57, "Continue"), toggle]] + diplomacy + [
			["Options", show_options],
			["Leave the match", to_main_menu],
		])
		return
	hud.get_tree().paused = true
	var goals := []
	if hud.mission and (hud.mission.goal_text() != "" or not hud.mission.told.is_empty()):
		goals = [[hud.mission.text(56) if hud.mission.text(56) != "" else "Mission goals", show_goals]]
	_panel = _menu_panel(GameData.menu_text(50, "Settings"), [
		[GameData.menu_text(57, "Continue"), toggle]] + goals + diplomacy + [
		["Save game (F2)", func() -> void:
			toggle()
			quick_save()],
		["Load game", func() -> void:
			toggle()
			quick_load()],
		["Options", show_options],
		[GameData.menu_text(54, "Restart"), func() -> void:
			hud.get_tree().paused = false
			hud.get_tree().reload_current_scene()],
		["Main menu", to_main_menu],
	] if Match.editor_map.is_empty() else [
		[GameData.menu_text(57, "Continue"), toggle],
		[GameData.menu_text(54, "Restart"), func() -> void:
			hud.get_tree().paused = false
			hud.get_tree().reload_current_scene()],
		["Back to the map editor", to_editor],
		["Main menu", to_main_menu],
	])


func _close() -> void:
	_panel.queue_free()
	_panel = null
	_rows.clear()
	hud.get_tree().paused = false


func quick_save() -> void:
	hud.notify("Game saved" if SaveGame.save(hud.get_parent()) else "Could not save the game")


func quick_load() -> void:
	var data := SaveGame.read()
	if data.is_empty():
		hud.notify("No saved game")
		return
	Match.load_data = data
	hud.get_tree().paused = false
	hud.get_tree().reload_current_scene()


## The mission's current goals (the script's last goal text), and below them everything the
## mission has told the player so far (tips, people talking), newest first.
func show_goals() -> void:
	if _panel:
		_panel.queue_free()
	var mission := hud.mission
	_panel = _menu_panel(mission.text(56) if mission.text(56) != "" else "Mission goals", [["Back", func() -> void:
		_close()
		toggle()]])
	var scale := hud.ui_scale
	var box: Control = _panel.get_child(0)
	var column: VBoxContainer = box.get_child(0)
	var width := 560 * scale
	var page := MissionGoals.of(mission)
	var lines := PackedStringArray()
	for i in page.goals.size():
		var goal: Dictionary = page.goals[i]
		var line := "%d. %s" % [i + 1, _escape(goal.text)]
		lines.append("[color=#%s][s]%s[/s][/color]" % [DONE_COLOR.to_html(false), line] if goal.done else line)
	var text := _goal_text("\n".join(lines) if not lines.is_empty() else "No goals given yet.", width, 17)
	var at := 1
	if not page.tips.is_empty():
		text.text += "\n\n[font_size=%d]Tips[/font_size]\n" % int(18 * scale) \
				+ "\n".join(page.tips.map(func(t: String) -> String: return "• " + _escape(t)))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(text)
	column.add_child(scroll)
	column.move_child(scroll, at)
	text.reset_size()
	var tall := hud.get_viewport().get_visible_rect().size.y * 0.65
	scroll.custom_minimum_size = Vector2(width + 16 * scale, minf(text.get_content_height() + 4, tall))
	box.reset_size()
	box.position = hud.get_viewport().get_visible_rect().size / 2.0 - box.get_combined_minimum_size() / 2.0


func _goal_text(text: String, width: float, size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width
	label.add_theme_color_override("default_color", HudStyle.TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_constant_override("paragraph_separation", int(6 * hud.ui_scale))
	label.add_theme_font_size_override("normal_font_size", int(size * hud.ui_scale))
	label.text = text
	return label


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


## The Diplomacy page (manual 6.5; AmericaAddOn.exe dialog 0x44ff60, only in network games
## there, here in a skirmish too): every other player with their total score, buttons to make
## them an ally or an enemy, and a mark for those our resource packages go to. Each side's
## stance is its own (Diplomacy.take_side), so the page shows both. Everything it changes goes
## as orders (Orders.declare, Orders.send); the page follows the game as it changes. No chat:
## the remake has none yet.
func show_diplomacy() -> void:
	if _panel:
		_panel.queue_free()
	_rows.clear()
	_recipients.clear()
	_panel = _menu_panel(GameData.menu_text(141, "Diplomacy"), [["Back", func() -> void:
		_close()
		toggle()]])
	var scale := hud.ui_scale
	var size := int(16 * scale)
	var box: Control = _panel.get_child(0)
	var column: VBoxContainer = box.get_child(0)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", int(12 * scale))
	grid.add_theme_constant_override("v_separation", int(6 * scale))
	for heading in ["Player", "Stance", "", "", GameData.menu_text(100, "Score"), ""]:
		grid.add_child(MenuStyle.label(heading, int(14 * scale), MenuStyle.TEXT_DIM))
	for index in Player.by_index:
		var other: Player = Player.by_index[index]
		if index == hud.player.index:
			continue
		var name := MenuStyle.label(other.title() + (" (computer)" if other.computer else ""), size, other.color())
		var stance := MenuStyle.label("", int(14 * scale))
		var ally := _choice_button("Ally", func() -> void: Orders.declare(index, true))
		var enemy := _choice_button("Enemy", func() -> void: Orders.declare(index, false))
		var score := MenuStyle.label("", size)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var send := _choice_button("Receives", func() -> void: pass)
		send.toggle_mode = true
		send.tooltip_text = "Mark this player to receive the resource packages"
		send.toggled.connect(func(on: bool) -> void:
			_light(send, on)
			if on:
				_recipients[index] = true
			else:
				_recipients.erase(index))
		for control: Control in [name, stance, ally, enemy, score, send]:
			grid.add_child(control)
		_rows[index] = {"stance": stance, "ally": ally, "enemy": enemy, "score": score, "send": send}
	if _rows.is_empty():
		grid.add_child(MenuStyle.label("Nobody else is playing.", size, MenuStyle.TEXT_DIM))
	column.add_child(grid)
	column.move_child(grid, 1)
	# Packages for the marked allies: 100 food, wood or gold, or 2 guns (Diplomacy.PACKAGES).
	var goods := HBoxContainer.new()
	goods.add_theme_constant_override("separation", int(10 * scale))
	goods.alignment = BoxContainer.ALIGNMENT_CENTER
	goods.add_child(MenuStyle.label("Send each marked player:", int(14 * scale), MenuStyle.TEXT_DIM))
	for good in Diplomacy.PACKAGES:
		var button := _choice_button("%d" % Diplomacy.PACKAGES[good], func() -> void: Orders.send(good, _recipients.keys()))
		button.tooltip_text = "Send %d %s to each marked player" % [Diplomacy.PACKAGES[good], good]
		var icon := HudStyle.status_icon(Diplomacy.ICONS[good])
		icon.custom_minimum_size = Vector2(22, 22) * scale
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", int(3 * scale))
		pair.add_child(icon)
		pair.add_child(button)
		goods.add_child(pair)
	column.add_child(goods)
	column.move_child(goods, 2)
	_stock = MenuStyle.label("", int(14 * scale), MenuStyle.TEXT_DIM)
	_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_stock)
	column.move_child(_stock, 3)
	refresh()
	box.reset_size()
	box.position = hud.get_viewport().get_visible_rect().size / 2.0 - box.get_combined_minimum_size() / 2.0


## Bring the diplomacy page (when open) up to date with the game: the stances, the scores,
## our stockpile. The ally button is lit while we are not at war with them (0x431ec0).
func refresh() -> void:
	if _rows.is_empty() or not is_instance_valid(_stock):
		return
	var me := hud.player.index
	for index in _rows:
		var row: Dictionary = _rows[index]
		var other: Player = Player.by_index[index]
		var ours := not Diplomacy.hostile(me, index)
		var theirs := not Diplomacy.hostile(index, me)
		row.stance.text = "Allies" if ours and theirs else ("At war with you" if ours else ("You are at war" if theirs else "Enemies"))
		row.stance.add_theme_color_override("font_color", Color(0.6, 0.9, 0.5) if ours and theirs \
				else (Color(1.0, 0.6, 0.45) if ours != theirs else MenuStyle.TEXT))
		_light(row.ally, ours)
		_light(row.enemy, not ours)
		row.score.text = str(other.score())
	var stock := PackedStringArray()
	for good in Diplomacy.PACKAGES:
		stock.append("%s %d" % [good, int(hud.player.resources.get(good, 0))])
	_stock.text = "You have: " + ", ".join(stock)


func _choice_button(text: String, action: Callable) -> Button:
	var scale := hud.ui_scale
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(70, 28) * scale
	button.add_theme_color_override("font_disabled_color", MenuStyle.TEXT_DIM.darkened(0.3))
	MenuStyle.style(button, int(15 * scale))
	_light(button, false)
	button.pressed.connect(action)
	return button


## A choice button's look: lit when it is the current choice.
func _light(button: Button, on: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.55, 0.33, 0.1) if on else Color(0.3, 0.17, 0.08)
	normal.border_color = Color(1.0, 0.85, 0.3)
	normal.set_border_width_all(2 if on else 0)
	normal.set_corner_radius_all(3)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.48, 0.27, 0.1) if not on else normal.bg_color
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)


## Sound, scrolling, interface and display settings (SettingsPanel), kept between sessions.
func show_options() -> void:
	if _panel:
		_panel.queue_free()
	_panel = _menu_panel("Options", [["Back", func() -> void:
		_close()
		toggle()]])
	var box: Control = _panel.get_child(0)
	var column: VBoxContainer = box.get_child(0)
	var rows := SettingsPanel.create(int(16 * hud.ui_scale), 190 * hud.ui_scale)
	column.add_child(rows)
	column.move_child(rows, 1)
	box.reset_size()
	box.position = hud.get_viewport().get_visible_rect().size / 2.0 - box.get_combined_minimum_size() / 2.0


func to_main_menu() -> void:
	Net.end_match()
	hud.get_tree().paused = false
	Sim.set_speed(1.0)
	Match.configured = false
	Match.editor_map = ""
	hud.get_tree().change_scene_to_file("res://scenes/menu.tscn")


## Leave a test game for the map editor, which reopens the map.
func to_editor() -> void:
	hud.get_tree().paused = false
	Sim.set_speed(1.0)
	Match.configured = false
	hud.get_tree().change_scene_to_file("res://scenes/editor.tscn")


## A dimmed screen with a board holding a title and a column of buttons [[text, action]...].
func _menu_panel(title: String, entries: Array) -> Control:
	var scale := hud.ui_scale
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.root.add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", board(22 * scale))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(10 * scale))
	var heading := MenuStyle.label(title, int(26 * scale))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	for entry in entries:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(260, 36) * scale
		MenuStyle.style(button, int(18 * scale))
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.3, 0.17, 0.08)
		normal.set_corner_radius_all(3)
		var hover := normal.duplicate()
		hover.bg_color = Color(0.48, 0.27, 0.1)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.pressed.connect(entry[1])
		column.add_child(button)
	panel.add_child(column)
	shade.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = hud.get_viewport().get_visible_rect().size / 2.0 - panel.get_combined_minimum_size() / 2.0
	return shade


static func board(margin: float, alpha := 0.95) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.18, 0.1, 0.05, alpha)
	box.border_color = Color(0.62, 0.43, 0.2)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(margin)
	return box


## The statistics after a game (manual 7.7): per people, what it built, trained, gathered,
## killed and destroyed, and a total score.
func show_statistics(players: Dictionary) -> void:
	var scale := hud.ui_scale
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", int(18 * scale))
	grid.add_theme_constant_override("v_separation", int(6 * scale))
	for heading in ["People", "Buildings", "Units", "Resources", "Kills", "Razed", "Score"]:
		grid.add_child(MenuStyle.label(heading, int(16 * scale), MenuStyle.TEXT_DIM))
	for index in players:
		var p: Player = players[index]
		var name := Match.faction_name(p.faction) + (" (you)" if index == hud.player.index else "")
		var row := [name, p.stats.built, p.stats.produced, p.stats.gathered, p.stats.kills, p.stats.razed, p.score()]
		for i in row.size():
			grid.add_child(MenuStyle.label(str(row[i]), int(16 * scale), p.color() if i == 0 else MenuStyle.TEXT))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", board(18 * scale, 0.92))
	panel.add_child(grid)
	hud.root.add_child(panel)
	var view := hud.get_viewport().get_visible_rect().size
	panel.position = Vector2(view.x / 2.0 - panel.get_combined_minimum_size().x / 2.0, view.y * 0.58)
