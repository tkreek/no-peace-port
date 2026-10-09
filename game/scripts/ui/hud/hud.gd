class_name Hud
extends CanvasLayer
## In-game interface built from the original wooden status bar, as the original lays it out
## at high resolutions: the bar's two boards at the bottom left, the selection on the
## nailed board (SelectionPanel) and the command buttons on the long one (CommandPanel),
## the minimap panel at the bottom right, the map open in between, and a strip with the
## stockpiles at the top left. Scales with the window height and the interface-size
## setting. Esc opens the game menu (GameMenu).

const STATUS_SHEET := "interface/hud/bar/sheet_1"
const MINIMAP_PANEL := "interface/hud/bar/bar_right.png"
const MINIMAP_HOLE := Rect2(83, 15, 164, 160)  # magenta window in leisterechts.pic
const BAR_HEIGHT := 167.0
## The status bar's boards (original px): the nailed one for the selection, then the long
## one for the commands.
const SELECTION_BOARD := Rect2(0, 0, 186, 167)
const COMMAND_BOARD := Rect2(186, 0, 376, 167)
## Bar height relative to a 1080-line screen (the original's bar takes about a seventh of it).
const SIZE := 1.0
const MAP_MODE_ICONS := [13, 15, 17]  # KleineIcons: landscape, field, armed men
const MAP_MODE_NAMES := ["Regular map (Alt+N)", "Economic map (Alt+R)", "Military map (Alt+C)"]
const ICON_IDLE := 19  # KleineIcons: a lone cowboy
## Full housing ("sound kein wohnraum mehr.wav", text 805) and the match's population limit
## ("sound bevölkerungslimit erreicht.wav", text 807).
const HOUSING_FULL_SOUND := 76
const POPULATION_LIMIT_SOUND := 52

var player: Player
var selection: SelectionController
var build_controller: BuildController
var biome := "steppe"
var ui_scale := 1.0
var minimap := Minimap.new()
var root := Control.new()  ## everything the HUD shows hangs off this
var commands: CommandPanel
var selected: SelectionPanel
var menu := GameMenu.new(self)

var _left := TextureRect.new()
var _right := TextureRect.new()
var _top := Panel.new()  ## the stockpiles: a slim translucent strip at the top left
var _resources := HBoxContainer.new()
var _resource_labels := {}
var _population_label: Label
var _status_sheet: RdSprite
var _map_button: Button
var _idle_button: Button
var _resource_timer := 0.0
var _scale_setting := 1.0
var _at_population_limit := false
## How often the population limit has been announced (for the checks).
var population_warnings := 0


func setup(map: AlfMap, terrain_colors: Image, camera: Camera2D, objects: Node2D, local_player: Player,
		selection_controller: SelectionController) -> void:
	player = local_player
	selection = selection_controller
	_status_sheet = GameData.load_sprite(STATUS_SHEET)
	process_mode = Node.PROCESS_MODE_ALWAYS  # the game menu works while paused
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	for panel: TextureRect in [_left, _right]:
		panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		panel.stretch_mode = TextureRect.STRETCH_SCALE
	for panel: Control in [_left, _right, _top]:
		panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		root.add_child(panel)
	_right.texture = _minimap_panel_texture()
	_setup_minimap(map, camera, objects, terrain_colors)
	_setup_resources()
	selected = SelectionPanel.new(self, _left)
	commands = CommandPanel.new(self, root)
	player.resources_changed.connect(_refresh_resources)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_resources()
	_at_population_limit = player.population() >= player.population_limit()


func _setup_minimap(map: AlfMap, camera: Camera2D, objects: Node2D, terrain_colors: Image) -> void:
	# The frame sits over the minimap; clicks in its window belong to the map.
	_right.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouse:
			var local: Vector2 = _right.get_global_transform() * event.position - minimap.global_position
			if Rect2(Vector2.ZERO, minimap.size).has_point(local) or minimap.is_dragging():
				var forwarded: InputEvent = event.duplicate()
				forwarded.position = local
				minimap.handle_input(forwarded)
				_right.accept_event())
	minimap.setup(map, camera, objects, terrain_colors)
	root.add_child(minimap)
	root.move_child(minimap, root.get_children().find(_right))  # behind the frame
	# Buttons beside the minimap: map mode and the next idle worker.
	var small_icons := GameData.load_sprite(CommandPanel.SMALL_ICONS)
	_map_button = HudStyle.icon_button(small_icons, MAP_MODE_ICONS[0], MAP_MODE_NAMES[0])
	_map_button.pressed.connect(_cycle_map_mode)
	_idle_button = HudStyle.icon_button(small_icons, ICON_IDLE, "Next idle worker (.)")
	_idle_button.pressed.connect(func() -> void: selection._select_idle_worker())
	root.add_child(_map_button)
	root.add_child(_idle_button)


## Food, wood, horses, gold, guns and population along the top, with the original icons.
func _setup_resources() -> void:
	_top.add_child(_resources)
	var add_icon := func(frame: int, tip: String) -> void:
		_resources.add_child(HudStyle.status_icon(frame, tip))
	for key in Player.RESOURCES:
		add_icon.call(Player.RESOURCES[key].icon, GameData.text(Player.RESOURCES[key].text, key.capitalize()))
		var label := HudStyle.label(18)
		_resources.add_child(label)
		_resource_labels[key] = label
	add_icon.call(5, GameData.text(77, "Population"))
	_population_label = HudStyle.label(18)
	_resources.add_child(_population_label)


func _process(delta: float) -> void:
	if Settings.value("ui_scale") != _scale_setting:
		_layout()
		commands.signature = ""
	_resource_timer -= delta
	if _resource_timer <= 0.0:
		_resource_timer = 0.5
		_refresh_resources()  # horse room and warehoused gold change with buildings too
	var population := player.population()
	_population_label.text = "%d / %d" % [population, player.population_cap()]
	_check_population_limit(population)
	selected.refresh()
	commands.refresh()


## The warning sound and message when the people fill their housing (or the match's limit).
func _check_population_limit(population: int) -> void:
	var at_limit := population >= player.population_limit()
	if at_limit and not _at_population_limit:
		warn_population_limit()
	_at_population_limit = at_limit


func warn_population_limit() -> void:
	population_warnings += 1
	if Match.population_limit <= player.population_cap():
		Sound.play_sound(POPULATION_LIMIT_SOUND)
		notify(GameData.text(807, "We've reached our population limit"))
	else:
		Sound.play_sound(HOUSING_FULL_SOUND)
		notify(GameData.text(805, "We don't have enough living space"))


## Screen area covered by the HUD (for camera bounds and clicks).
func blocks_point(screen_point: Vector2) -> bool:
	for panel: Control in [_left, _right, _top]:
		if panel.get_global_rect().has_point(screen_point):
			return true
	return false


## Where the command buttons go: the long board.
func command_area() -> Rect2:
	return Rect2(_left.position + COMMAND_BOARD.position * ui_scale, COMMAND_BOARD.size * ui_scale)


## Where the selection shows: the nailed board.
func selection_area() -> Rect2:
	return Rect2(SELECTION_BOARD.position * ui_scale, SELECTION_BOARD.size * ui_scale)


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	_scale_setting = Settings.value("ui_scale")
	ui_scale = clampf(minf(view.y / 1080.0, view.x / 1920.0) * SIZE * _scale_setting, 0.5, 3.0)
	var bar_h := BAR_HEIGHT * ui_scale
	var left_size := HudStyle.frame_size(_status_sheet, 0) * ui_scale
	_left.texture = _status_frame(0, 1.0)
	var right_size := Vector2(256, 184) * ui_scale
	_left.position = Vector2(0, view.y - bar_h)
	_left.size = left_size
	_right.position = view - right_size
	_right.size = right_size
	minimap.position = _right.position + MINIMAP_HOLE.position * ui_scale
	minimap.size = MINIMAP_HOLE.size * ui_scale
	for i in 2:
		var button: Button = [_map_button, _idle_button][i]
		button.size = Vector2(46, 46) * ui_scale
		button.position = _right.position + Vector2(22, 34 + i * 62) * ui_scale

	var top_h := 22.0 * ui_scale
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(0.05, 0.03, 0.02, 0.55)
	strip.corner_radius_bottom_right = int(6 * ui_scale)
	_top.add_theme_stylebox_override("panel", strip)
	_resources.position = Vector2(8, 2) * ui_scale
	_resources.size = Vector2(0, top_h - 4 * ui_scale)
	_resources.add_theme_constant_override("separation", int(4 * ui_scale))
	for child in _resources.get_children():
		if child is TextureRect:
			child.custom_minimum_size = Vector2(16, 16) * ui_scale
		else:
			child.add_theme_font_size_override("font_size", int(14 * ui_scale))
			var width := 44
			if child == _population_label:
				width = 60
			elif child == _resource_labels.get("gold"):
				width = 84  # "gold (warehoused)"
			elif child == _resource_labels.get("horses"):
				width = 48
			child.custom_minimum_size.x = width * ui_scale
	# The strip is only as long as the stockpiles need.
	_resources.reset_size()
	_top.position = Vector2.ZERO
	_top.size = Vector2(minf(view.x, _resources.get_combined_minimum_size().x + 16 * ui_scale), top_h)
	commands.layout(command_area())
	selected.layout()


func _refresh_resources() -> void:
	for key in _resource_labels:
		_resource_labels[key].text = str(player.resources.get(key, 0))
	_resource_labels.horses.text = "%d / %d" % [player.resources.get("horses", 0), player.horse_capacity()]
	# Gold still in warehouses shows in brackets, as in the original resource bar.
	var warehoused := player.warehoused_gold()
	if warehoused > 0:
		_resource_labels.gold.text = "%d (%d)" % [player.resources.get("gold", 0), warehoused]


## A status-bar plank as its own texture, resized so 1 original pixel = `pixel_scale` screen px
## (tiling needs a standalone texture; the left panel is stretched instead, so 1.0 there).
func _status_frame(frame: int, pixel_scale: float) -> Texture2D:
	var image := _status_sheet.texture.get_image().get_region(_status_sheet.rects[frame])
	if image.is_compressed():
		image.decompress()
	var target := (HudStyle.frame_size(_status_sheet, frame) * pixel_scale).round()
	if Vector2(image.get_size()) != target:
		image.resize(int(target.x), int(target.y), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


## The minimap frame with its magenta window cut out.
func _minimap_panel_texture() -> Texture2D:
	var image := GameData.load_image(MINIMAP_PANEL)
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r8 > 240 and c.g8 < 16 and c.b8 > 240:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


func _cycle_map_mode(to := -1) -> void:
	minimap.mode = ((int(minimap.mode) + 1) % 3 if to < 0 else to) as Minimap.Mode
	var small_icons := GameData.load_sprite(CommandPanel.SMALL_ICONS)
	(_map_button.get_node("Icon") as TextureRect).texture = HudStyle.atlas(small_icons, MAP_MODE_ICONS[minimap.mode])
	_map_button.tooltip_text = MAP_MODE_NAMES[minimap.mode]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or get_tree().paused:
		return
	var key: int = event.keycode
	if event.alt_pressed and key in [KEY_N, KEY_R, KEY_C]:
		_cycle_map_mode([KEY_N, KEY_R, KEY_C].find(key))
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed or event.alt_pressed:
		return
	if key == KEY_F2:
		menu.quick_save()
		get_viewport().set_input_as_handled()
	elif commands.handle_key(key):
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ messages

func toggle_menu() -> void:
	menu.toggle()


func show_statistics(players: Dictionary) -> void:
	menu.show_statistics(players)


## A message across the top of the screen for a few seconds (surrenders, warnings).
func notify(text: String) -> void:
	var label := HudStyle.label(int(28 * ui_scale))
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", int(6 * ui_scale))
	root.add_child(label)
	var view := get_viewport().get_visible_rect().size
	label.position = Vector2(view.x / 2.0 - label.get_minimum_size().x / 2.0, 60 * ui_scale)
	var tween := label.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(label.queue_free)


## Large centred message (victory / defeat) with a way back to the main menu.
func show_banner(text: String) -> void:
	var label := HudStyle.label(int(64 * ui_scale))
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.add_theme_constant_override("outline_size", int(10 * ui_scale))
	root.add_child(label)
	label.position = get_viewport().get_visible_rect().size / 2.0 - label.get_minimum_size() / 2.0
	var back := Button.new()
	back.text = "Back to main menu"
	MenuStyle.style(back, int(20 * ui_scale))
	back.pressed.connect(menu.to_main_menu)
	root.add_child(back)
	back.position = label.position + Vector2(label.get_minimum_size().x / 2.0 - 110 * ui_scale, label.get_minimum_size().y + 20)
