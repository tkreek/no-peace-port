class_name GameMenu
extends RefCounted
## The in-game menu (Esc; it pauses the game): continue, save, load, options, restart, back
## to the main menu. Also the statistics shown after a game.

var hud: Hud
var _panel: Control  # the open menu (its dimmed backdrop), or null


func _init(owner: Hud) -> void:
	hud = owner


func is_open() -> bool:
	return _panel != null


func toggle() -> void:
	if _panel:
		_close()
		return
	hud.get_tree().paused = true
	_panel = _menu_panel(GameData.menu_text(50, "Settings"), [
		[GameData.menu_text(57, "Continue"), toggle],
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
