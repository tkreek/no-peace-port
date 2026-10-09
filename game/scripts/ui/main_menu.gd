extends Control
## Main menu and skirmish setup, built from the original menu art (expansion versions when
## available), laid out for widescreen: the 4:3 artwork is centred at full height over a
## blurred, darkened copy of itself, and the original glow sprites back the buttons.

const MAIN_BG := "global/gfx/menues/main/mainmenu2.pic"
const MAIN_BG_BASE := "global/gfx/menues/main/mainmenu.pic"
const MAIN_GLOW := "global/gfx/menues/main/bilderliste__1.spr"
const SETUP_BG := "global/gfx/menues/selectgame/selectgame.pic"
const SETUP_SPRITES := "global/gfx/menues/selectgame/piclist00.spr"
const LOADING_BG := "global/gfx/ladebild/ladebild2.pic"
const LOADING_BG_BASE := "global/gfx/ladebild/ladebild1024768.pic"
const ART_SIZE := Vector2(800, 600)
## Areas of the selectgame artwork (800x600 coordinates).
const SETUP_TITLE := Rect2(277, 103, 247, 30)
const SETUP_LIST := Rect2(214, 170, 374, 270)

var _art := Control.new()  # 800x600 design space, scaled to fit the window
var _screens := {}
var _glow: RdSprite
var _setup_sprites: RdSprite
var _maps: Array[Dictionary] = []
var _map_list := ItemList.new()
var _preview := TextureRect.new()
var _map_info := Label.new()
var _slots := VBoxContainer.new()
var _supply := OptionButton.new()
var _difficulty := OptionButton.new()
var _game_type := OptionButton.new()
var _population := OptionButton.new()
var _speed := OptionButton.new()
var _faction := OptionButton.new()


func _ready() -> void:
	Engine.time_scale = 1.0  # a finished match may have left its game speed behind
	theme = MenuStyle.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _skip_to_game():
		return
	if not GameData.is_ready():
		add_child(MenuStyle.label("Original game data not found.\nStart with --install-dir=<folder containing america0.rda>", 24))
		return
	_glow = GameData.load_sprite(MAIN_GLOW)
	_setup_sprites = GameData.load_sprite(SETUP_SPRITES)
	_add_backdrop(MAIN_BG if GameData.exists(MAIN_BG) else MAIN_BG_BASE)
	add_child(_art)
	_screens.main = _build_main()
	_screens.setup = _build_setup()
	_screens.settings = _build_settings()
	for screen in _screens.values():
		_art.add_child(screen)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_show("main")
	Sound.play_music("title")
	_menu_screenshot()
	if GameData.cmdline_option("menu-autostart") != "":
		_map_list.select(clampi(GameData.cmdline_option("menu-autostart").to_int(), 0, _maps.size() - 1))
		_on_map_selected(_map_list.get_selected_items()[0])
		_start()


## --menu-shot=<png> [--menu-screen=setup]: capture a menu screen and quit (for checks).
func _menu_screenshot() -> void:
	var path := GameData.cmdline_option("menu-shot")
	if path.is_empty():
		return
	_show(GameData.cmdline_option("menu-screen", "main"))
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## Development options (map, scenario, screenshot, selftest) start the game directly.
func _skip_to_game() -> bool:
	for option in ["map", "scenario", "screenshot", "selftest", "report-after"]:
		if GameData.cmdline_option(option) != "":
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return true
	return false


func _fit() -> void:
	var view := get_viewport_rect().size
	var scale_factor := minf(view.x / ART_SIZE.x, view.y / ART_SIZE.y)
	_art.scale = Vector2(scale_factor, scale_factor)
	_art.position = (view - ART_SIZE * scale_factor) / 2.0
	_art.size = ART_SIZE


func _show(screen: String) -> void:
	for key in _screens:
		_screens[key].visible = key == screen
	var art: TextureRect = get_node_or_null("Art")
	if art:
		var path := SETUP_BG if screen == "setup" else MAIN_BG
		if path == MAIN_BG and not GameData.exists(MAIN_BG):
			path = MAIN_BG_BASE
		_set_backdrop(path)


# ------------------------------------------------------------------ background

func _add_backdrop(path: String) -> void:
	var blurred := TextureRect.new()
	blurred.name = "Blur"
	blurred.set_anchors_preset(Control.PRESET_FULL_RECT)
	blurred.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blurred.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	blurred.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	blurred.modulate = Color(0.35, 0.32, 0.3)
	add_child(blurred)
	var art := TextureRect.new()
	art.name = "Art"
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(art)
	_set_backdrop(path)


func _set_backdrop(path: String) -> void:
	var image := GameData.load_image(path)
	if image == null:
		return
	(get_node("Art") as TextureRect).texture = ImageTexture.create_from_image(image)
	var small := image.duplicate()
	small.resize(40, 30, Image.INTERPOLATE_BILINEAR)
	(get_node("Blur") as TextureRect).texture = ImageTexture.create_from_image(small)


# ------------------------------------------------------------------ main menu

func _build_main() -> Control:
	var screen := Control.new()
	screen.size = ART_SIZE
	var column := VBoxContainer.new()
	column.position = Vector2(400, 250)
	column.add_theme_constant_override("separation", 14)
	screen.add_child(column)
	column.add_child(_glow_button("Skirmish", func() -> void: _show("setup")))
	if FileAccess.file_exists(SaveGame.QUICK):
		column.add_child(_glow_button("Load game", func() -> void:
			var data := SaveGame.read()
			if data.is_empty():
				return
			Match.load_data = data
			_show_loading()
			await get_tree().process_frame
			await get_tree().process_frame
			get_tree().change_scene_to_file("res://scenes/main.tscn")))
	column.add_child(_glow_button(GameData.menu_text(50, "Settings"), func() -> void: _show("settings")))
	column.add_child(_glow_button(GameData.menu_text(14, "Exit game"), func() -> void: get_tree().quit()))
	var version := MenuStyle.label("America Remastered — original data%s" %
			(" + expansion pack" if GameData.has_expansion else ""), 11, MenuStyle.TEXT_DIM)
	version.position = Vector2(12, 578)
	screen.add_child(version)
	return screen


## A menu entry drawn over the original glow sprite (frame 0 normal, 1 hover, 2 pressed).
func _glow_button(text: String, action: Callable) -> Control:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(360, 34)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var glow := TextureRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.texture = _frame(_glow, 0)
	button.add_child(glow)
	var label := MenuStyle.label(text, 20)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	button.mouse_entered.connect(func() -> void:
		glow.texture = _frame(_glow, 1)
		label.add_theme_color_override("font_color", MenuStyle.TEXT_HOVER))
	button.mouse_exited.connect(func() -> void:
		glow.texture = _frame(_glow, 0)
		label.add_theme_color_override("font_color", MenuStyle.TEXT))
	button.button_down.connect(func() -> void: glow.texture = _frame(_glow, 2))
	button.pressed.connect(func() -> void:
		Sound.play_sound(268)  # "ding"
		action.call())
	return button


func _frame(sheet: RdSprite, frame: int) -> Texture2D:
	if sheet == null or frame >= sheet.frame_count():
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet.texture
	atlas.region = Rect2(sheet.rects[frame])
	return atlas


# ------------------------------------------------------------------ settings

## Sound, scrolling, interface and display settings on a dark board over the title art.
func _build_settings() -> Control:
	var screen := Control.new()
	screen.size = ART_SIZE
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.07, 0.03, 0.9)
	box.border_color = Color(0.62, 0.43, 0.2)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	var heading := MenuStyle.label(GameData.menu_text(50, "Settings"), 24)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	column.add_child(SettingsPanel.create(15, 170))
	var back := _small_button(GameData.menu_text(16, "Back"), func() -> void: _show("main"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)
	panel.add_child(column)
	screen.add_child(panel)
	panel.reset_size()
	panel.position = Vector2(ART_SIZE.x * 0.5 - panel.get_combined_minimum_size().x * 0.5, 150)
	return screen


# ------------------------------------------------------------------ skirmish setup

func _build_setup() -> Control:
	var screen := Control.new()
	screen.size = ART_SIZE
	var title := MenuStyle.label(GameData.menu_text(21, "Select a level:"), 16)
	title.position = SETUP_TITLE.position
	title.size = SETUP_TITLE.size
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	screen.add_child(title)

	_map_list.position = SETUP_LIST.position
	_map_list.size = Vector2(SETUP_LIST.size.x * 0.58, SETUP_LIST.size.y)
	_map_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_map_list.add_theme_font_size_override("font_size", 13)
	_map_list.add_theme_color_override("font_color", MenuStyle.TEXT)
	_map_list.add_theme_color_override("font_selected_color", MenuStyle.TEXT_HOVER)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(0.55, 0.3, 0.12, 0.6)
	_map_list.add_theme_stylebox_override("selected", selected)
	_map_list.add_theme_stylebox_override("selected_focus", selected)
	_map_list.item_selected.connect(_on_map_selected)
	screen.add_child(_map_list)

	_preview.position = SETUP_LIST.position + Vector2(SETUP_LIST.size.x * 0.62, 6)
	_preview.size = Vector2(SETUP_LIST.size.x * 0.38 - 6, SETUP_LIST.size.x * 0.38 - 6)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.add_child(_preview)
	MenuStyle.style(_map_info, 12, MenuStyle.TEXT_DIM)
	_map_info.position = _preview.position + Vector2(0, _preview.size.y + 4)
	_map_info.size = Vector2(_preview.size.x, 60)
	_map_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	screen.add_child(_map_info)

	# Players: you, then the computer opponents.
	var players_box := VBoxContainer.new()
	players_box.position = Vector2(214, 452)
	players_box.add_theme_constant_override("separation", 4)
	screen.add_child(players_box)
	var you := HBoxContainer.new()
	you.add_child(_fixed_label("You", 110))
	_fill_factions(_faction, 0)
	MenuStyle.style(_faction, 13)
	you.add_child(_faction)
	players_box.add_child(you)
	players_box.add_child(_slots)
	var supply := HBoxContainer.new()
	supply.add_child(_fixed_label(GameData.menu_text(268, "Raw materials"), 110))
	for i in Match.SUPPLY_TEXT.size():
		_supply.add_item(GameData.menu_text(Match.SUPPLY_TEXT[i], Match.SUPPLY_NAMES[i]))
	MenuStyle.style(_supply, 13)
	supply.add_child(_supply)
	players_box.add_child(supply)
	# Raw materials and the computer's level share one line.
	var level := supply
	level.add_theme_constant_override("separation", 6)
	var gap := Control.new()
	gap.custom_minimum_size.x = 18
	level.add_child(gap)
	level.add_child(_fixed_label(GameData.menu_text(265, "Computer AI"), 92))
	for i in Match.DIFFICULTY_TEXT.size():
		_difficulty.add_item(GameData.menu_text(Match.DIFFICULTY_TEXT[i], Match.DIFFICULTY_NAMES[i]))
	_difficulty.select(Match.difficulty)
	MenuStyle.style(_difficulty, 13)
	level.add_child(_difficulty)
	var rules := HBoxContainer.new()
	rules.add_theme_constant_override("separation", 6)
	for i in Match.GAME_TYPE_TEXT.size():
		_game_type.add_item(GameData.menu_text(Match.GAME_TYPE_TEXT[i], Match.GAME_TYPE_NAMES[i]))
	for limit in Match.POPULATION_LIMITS:
		_population.add_item("%d units" % limit)
	_population.select(Match.POPULATION_LIMITS.find(100))
	for i in Match.SPEEDS.size():
		_speed.add_item(Match.SPEED_NAMES[i])
	_speed.select(1)
	_game_type.tooltip_text = GameData.menu_text(264, "Game type")
	_population.tooltip_text = GameData.menu_text(266, "Population limit")
	_speed.tooltip_text = GameData.menu_text(267, "Game speed")
	for option: OptionButton in [_game_type, _population, _speed]:
		MenuStyle.style(option, 12)
		rules.add_child(option)
	players_box.add_child(rules)

	var buttons := HBoxContainer.new()
	buttons.position = Vector2(214, 562)
	buttons.add_theme_constant_override("separation", 24)
	buttons.add_child(_small_button(GameData.menu_text(16, "Back"), func() -> void: _show("main")))
	buttons.add_child(_small_button(GameData.menu_text(15, "Start"), _start))
	screen.add_child(buttons)

	_load_map_list()
	return screen


func _fixed_label(text: String, width: float) -> Label:
	var label := MenuStyle.label(text, 13)
	label.custom_minimum_size.x = width
	return label


func _fill_factions(option: OptionButton, selected: int, closed := false) -> void:
	option.clear()
	if closed:
		option.add_item("— closed —")
	for faction in Match.FACTIONS:
		option.add_item(("Computer: " if closed else "") + Match.faction_name(faction))
	option.select(selected)


func _small_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 30)
	button.focus_mode = Control.FOCUS_NONE
	MenuStyle.style(button, 16)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.22, 0.12, 0.06, 0.85)
	normal.border_color = Color(0.6, 0.42, 0.2)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.4, 0.22, 0.08, 0.95)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(func() -> void:
		Sound.play_sound(268)
		action.call())
	return button


func _load_map_list() -> void:
	var files := Array(GameData.map_files())
	files.sort_custom(func(a: String, b: String) -> bool: return a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
	var seen := {}
	for path in files:
		var file: String = path.get_file()
		var players := file.get_slice("[", 1).get_slice(" ", 0).to_int()
		var title := file.get_basename().get_slice("] - ", 1).capitalize()
		var key := "%d %s" % [players, title]
		var expansion := file.get_extension().to_lower() == "ulf"
		if seen.has(key):
			# The expansion re-ships many base maps; prefer its updated version.
			if expansion:
				_maps[seen[key]].path = path
			continue
		seen[key] = _maps.size()
		_maps.append({"path": path, "players": maxi(2, players), "title": title})
	for map in _maps:
		_map_list.add_item("%s  (%d)" % [map.title, map.players])
	if not _maps.is_empty():
		_map_list.select(0)
		_on_map_selected(0)


func _on_map_selected(index: int) -> void:
	var map: Dictionary = _maps[index]
	var alf := AlfMap.load_from_file(map.path)
	if alf:
		_preview.texture = ImageTexture.create_from_image(_preview_image(alf))
		_map_info.text = "%d players · %d × %d · %s" % [map.players, alf.columns, alf.rows,
				"forest" if alf.guess_biome() == "wiese" else "prairie"]
	# One row per possible opponent; the first is a computer player by default.
	for child in _slots.get_children():
		child.queue_free()
	for slot in range(1, map.players):
		var row := HBoxContainer.new()
		row.add_child(_fixed_label("Player %d" % (slot + 1), 110))
		var option := OptionButton.new()
		_fill_factions(option, 2 if slot == 1 else 0, true)
		MenuStyle.style(option, 13)
		row.add_child(option)
		_slots.add_child(row)
		if slot >= 4:
			row.visible = false  # keep the panel tidy; up to 4 opponents are offered
	_map_list.ensure_current_is_visible()


## Quick overview from the biome's per-tile minimap colours.
func _preview_image(map: AlfMap) -> Image:
	var bytes := GameData.read("%s/gfx/landschaft/minimap.pic" % map.guess_biome())
	var image := Image.create_empty(map.columns, map.rows, false, Image.FORMAT_RGB8)
	for i in map.tile_ids.size():
		var offset := 20 + map.tile_ids[i] * 2
		if offset + 2 <= bytes.size():
			image.set_pixel(i % map.columns, i / map.columns, RdImage.rgb555(bytes.decode_u16(offset)))
	return image


func _start() -> void:
	var map: Dictionary = _maps[_map_list.get_selected_items()[0]] if _map_list.is_anything_selected() else _maps[0]
	var slots: Array[Dictionary] = [{"faction": Match.FACTIONS[_faction.selected], "ai": false}]
	for row in _slots.get_children():
		var option: OptionButton = row.get_child(1)
		if option.selected > 0:
			slots.append({"faction": Match.FACTIONS[option.selected - 1], "ai": true})
	if slots.size() < 2:
		slots.append({"faction": "usa", "ai": true})
	Match.setup(map.path, slots)
	Match.supply = _supply.selected
	Match.difficulty = _difficulty.selected
	Match.game_type = _game_type.selected as Match.GameType
	Match.population_limit = Match.POPULATION_LIMITS[_population.selected]
	Match.speed = Match.SPEEDS[_speed.selected]
	_show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _show_loading() -> void:
	_art.visible = false
	_set_backdrop(LOADING_BG if GameData.exists(LOADING_BG) else LOADING_BG_BASE)
	var label := MenuStyle.label("Loading…", 28)
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.position = Vector2(get_viewport_rect().size.x / 2.0 - 60, get_viewport_rect().size.y - 80)
	add_child(label)
