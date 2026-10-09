class_name EditorUi
extends CanvasLayer
## The map editor's interface: a toolbar along the top (new, open, save, test, undo, erase,
## the map's title) and a side panel with a page per tool: terrain materials and brush
## size, nature (trees, rocks, mines, animals ...), buildings and units of each people for
## the chosen player, and the players (start points, people and computer control for test
## games, start resources).

const PAGES := ["Terrain", "Nature", "Buildings", "Units", "Players"]
const SIDE_WIDTH := 330.0
## Nature palette groups: type name prefix -> heading.
const NATURE := [["tree_deciduous", "Deciduous trees"], ["tree_conifer", "Conifers"], ["bush", "Bushes"],
		["cactus", "Cacti"], ["rock", "Rocks"], ["mine", "Gold mines"], ["animal_", "Animals"],
		["field", "Fields"], ["bridge", "Bridges"], ["ramp", "Ramps"]]

var editor: MapEditor
var ui_scale := 1.0
var root := Control.new()
var _top := PanelContainer.new()
var _side := PanelContainer.new()
var _page_box := VBoxContainer.new()
var _title := LineEdit.new()
var _status := Label.new()
var _notice := Label.new()
var _hint := Label.new()
var _erase := Button.new()
var _tabs: Array[Button] = []
var _page := "Terrain"
var _faction := "mex"
var _modal: Control
var _notice_time := 0.0
var _brush_slider: HSlider


func _ready() -> void:
	ui_scale = clampf(get_viewport().get_visible_rect().size.y / 1080.0, 0.75, 2.0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	_build_top()
	_build_side()
	_hint.add_theme_font_size_override("font_size", int(13 * ui_scale))
	_hint.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	_hint.add_theme_stylebox_override("normal", _box(Color(0.08, 0.05, 0.02, 0.75), Color(0, 0, 0, 0), 4))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)
	_notice.add_theme_font_size_override("font_size", int(18 * ui_scale))
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notice)
	editor.changed.connect(_refresh)
	editor.map_opened.connect(func() -> void: show_page(_page))
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_page("Terrain")


func _process(delta: float) -> void:
	if _notice_time > 0.0:
		_notice_time -= delta
		_notice.modulate.a = clampf(_notice_time, 0.0, 1.0)
	if editor.map:
		var at := editor.get_global_mouse_position()
		var cell := Vector2i(at / 32.0)
		var where := "%d, %d" % [cell.x, cell.y]
		if editor.painter and Rect2(Vector2.ZERO, editor.map.pixel_size()).has_point(at):
			var m := editor.painter.material_at(at)
			if m != TerrainRules.UNKNOWN:
				where += " · " + editor.rules.material_name(m)
		_status.text = "%s%s · %d × %d · %s · %s" % [editor.map.title, " *" if editor.dirty else "",
				editor.map.columns, editor.map.rows, "meadow" if editor.biome == "wiese" else "prairie", where]


func notify(text: String) -> void:
	_notice.text = text
	_notice_time = 3.0
	_notice.modulate.a = 1.0
	_layout()


func modal_open() -> bool:
	return _modal != null


func mouse_over_ui() -> bool:
	return _modal != null or get_viewport().gui_get_hovered_control() != null


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	_top.position = Vector2.ZERO
	_top.size = Vector2(view.x, 0)
	_top.reset_size()
	_top.size.x = view.x
	var top_h := _top.size.y
	_side.position = Vector2(0, top_h)
	_side.size = Vector2(SIDE_WIDTH * ui_scale, view.y - top_h)
	_hint.position = Vector2(SIDE_WIDTH * ui_scale + 12 * ui_scale, view.y - 28 * ui_scale)
	_notice.reset_size()
	_notice.position = Vector2(SIDE_WIDTH * ui_scale + (view.x - SIDE_WIDTH * ui_scale) / 2.0 - _notice.size.x / 2.0, top_h + 16 * ui_scale)


func _build_top() -> void:
	root.add_child(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * ui_scale))
	_top.add_child(row)
	row.add_child(_button("New", _ask_new, "Start a new map"))
	row.add_child(_button("Open", _ask_open, "Open a map (the original maps are saved as copies)"))
	row.add_child(_button("Save", func() -> void: editor.save(), "Save to the maps folder (Ctrl+S)"))
	row.add_child(_button("Test ▶", func() -> void: editor.test(), "Save and play the map now (F5)"))
	row.add_child(_button("Undo", func() -> void: editor.undo(), "Undo (Ctrl+Z)"))
	_erase = _button("Erase", func() -> void:
		editor.tool = MapEditor.Tool.ERASE if editor.tool != MapEditor.Tool.ERASE else _tool_for_page()
		_refresh(), "Remove objects by dragging over them (right click removes one with any tool)")
	_erase.toggle_mode = true
	row.add_child(_erase)
	var caption := Label.new()
	caption.text = "  Title"
	row.add_child(caption)
	_title.custom_minimum_size.x = 260 * ui_scale
	_title.text_changed.connect(func(text: String) -> void:
		editor.map.title = text
		editor.dirty = true)
	row.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_status.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	row.add_child(_status)
	row.add_child(_button("Menu", _ask_leave, "Back to the main menu"))


func _build_side() -> void:
	root.add_child(_side)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(8 * ui_scale))
	_side.add_child(column)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", int(4 * ui_scale))
	tabs.add_theme_constant_override("v_separation", int(4 * ui_scale))
	column.add_child(tabs)
	var group := ButtonGroup.new()
	for page in PAGES:
		var tab := _button(page, func() -> void: show_page(page))
		tab.toggle_mode = true
		tab.button_group = group
		tabs.add_child(tab)
		_tabs.append(tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_box.add_theme_constant_override("separation", int(6 * ui_scale))
	scroll.add_child(_page_box)


func show_page(page: String) -> void:
	_page = page
	for tab in _tabs:
		tab.set_pressed_no_signal(tab.text == page)
	for child in _page_box.get_children():
		child.queue_free()
	editor.tool = _tool_for_page()
	match page:
		"Terrain":
			_terrain_page()
		"Nature":
			_nature_page()
		"Buildings", "Units":
			_people_page(page == "Units")
		"Players":
			_players_page()
	_refresh()


func _tool_for_page() -> MapEditor.Tool:
	match _page:
		"Terrain":
			return MapEditor.Tool.TERRAIN
		"Players":
			return MapEditor.Tool.START
	return MapEditor.Tool.PLACE


func _refresh() -> void:
	if editor.map and not _title.has_focus():
		_title.text = editor.map.title
	_erase.set_pressed_no_signal(editor.tool == MapEditor.Tool.ERASE)
	if is_instance_valid(_brush_slider):
		_brush_slider.set_value_no_signal(editor.brush)
	match editor.tool:
		MapEditor.Tool.TERRAIN:
			_hint.text = "Left: paint   [ ]: brush size   Right: remove object   Middle drag / arrows: scroll   Wheel: zoom"
		MapEditor.Tool.PLACE:
			_hint.text = "Left: place   Right: remove   Ctrl+Z: undo   F5: save and test"
		MapEditor.Tool.START:
			_hint.text = "Left: put player %d's start point here   Right: remove" % editor.player
		MapEditor.Tool.ERASE:
			_hint.text = "Left drag: remove objects   Click Erase again to stop"


# ------------------------------------------------------------------ pages

func _terrain_page() -> void:
	if editor.rules == null:
		_page_box.add_child(_wrapped("Painting terrain needs the expansion's level editor data (Steppe.gfs in the expansion archives)."))
		return
	_page_box.add_child(_heading("Material"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(4 * ui_scale))
	grid.add_theme_constant_override("v_separation", int(4 * ui_scale))
	var group := ButtonGroup.new()
	for m in TerrainRules.PAINTABLE:
		var button := _button(editor.rules.material_name(m), func() -> void:
			editor.paint_material = m
			editor.tool = MapEditor.Tool.TERRAIN
			_refresh())
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(editor.paint_material == m)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = _swatch(m)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
	_page_box.add_child(grid)
	_page_box.add_child(_heading("Brush"))
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = 12
	slider.value = editor.brush
	slider.custom_minimum_size.y = 24 * ui_scale
	slider.value_changed.connect(func(value: float) -> void: editor.set_brush(int(value)))
	_brush_slider = slider
	_page_box.add_child(slider)
	_page_box.add_child(_wrapped("Materials blend only into their neighbours (water → shore → stone → steppe ...): the rings in between grow by themselves. Forests are planted with trees when the game starts."))


func _nature_page() -> void:
	var meadow := editor.biome == "wiese"
	for group in NATURE:
		var ids: Array[int] = []
		for id in ObjectTypes.count():
			var type := ObjectTypes.get_type(id)
			if type == null or type.anims.is_empty() or not type.name.begins_with(group[0]):
				continue
			if type.kind != ObjectTypes.Kind.ELEMENT and not type.name.begins_with("animal_"):
				continue
			if type.name.ends_with("_plateau"):
				continue
			var for_meadow := type.is_meadow() or type.name == "field_2"
			if type.name.begins_with("bridge") or type.name.begins_with("animal_") or for_meadow == meadow:
				ids.append(id)
		if ids.is_empty():
			continue
		_page_box.add_child(_heading(group[1]))
		var grid := _thumb_grid()
		for id in ids:
			grid.add_child(_type_button(id, 0, _nature_name(id, group[1])))
		_page_box.add_child(grid)
	_page_box.add_child(_heading("Gold in new mines"))
	var gold := SpinBox.new()
	gold.min_value = 500
	gold.max_value = 50000
	gold.step = 500
	gold.value = editor.mine_gold
	gold.value_changed.connect(func(value: float) -> void: editor.mine_gold = int(value))
	_page_box.add_child(gold)


func _people_page(units: bool) -> void:
	_page_box.add_child(_heading("People"))
	var factions := HFlowContainer.new()
	var group := ButtonGroup.new()
	for faction in Match.FACTIONS:
		var button := _button(Match.faction_name(faction), func() -> void:
			_faction = faction
			show_page(_page))
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(_faction == faction)
		factions.add_child(button)
	_page_box.add_child(factions)
	_page_box.add_child(_owner_row())
	_page_box.add_child(_heading("Units" if units else "Buildings"))
	var grid := _thumb_grid()
	var guids := GameData.stats_guids()
	guids.sort()
	for guid in guids:
		var stats := GameData.stats(guid)
		if stats.get("faction") != _faction or stats.get("kind") != ("unit" if units else "structure"):
			continue
		for variant in [guid, GameData.mounted_of(guid) if units else -1]:
			if variant < 0:
				continue
			var type_id := GameData.type_for_guid(variant, editor.biome)
			if type_id < 0:
				continue
			var name: String = stats.get("name", "?")
			if variant != guid:
				name += " (mounted)"
			grid.add_child(_type_button(type_id, editor.player, name, variant))
	_page_box.add_child(grid)
	if units:
		_page_box.add_child(_wrapped("A player who owns placed units or buildings starts with just those in a test game, without the usual main building and workers."))


func _players_page() -> void:
	_page_box.add_child(_wrapped("Click a player, then the map to put their start point. Players with a start point or objects of their own take part in a test game."))
	for player in range(1, 9):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(4 * ui_scale))
		var pick := _button("Player %d" % player, func() -> void:
			editor.player = player
			editor.tool = MapEditor.Tool.START
			show_page("Players"))
		pick.toggle_mode = true
		pick.set_pressed_no_signal(editor.player == player)
		pick.icon = _colour_icon(Player.TEAM_COLORS[player])
		pick.custom_minimum_size.x = 112 * ui_scale
		row.add_child(pick)
		var people := OptionButton.new()
		for faction in Match.FACTIONS:
			people.add_item(Match.faction_name(faction))
		people.select(Match.FACTIONS.find(editor.factions[player - 1]))
		people.fit_to_longest_item = false
		people.clip_text = true
		people.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		people.item_selected.connect(func(index: int) -> void: editor.factions[player - 1] = Match.FACTIONS[index])
		row.add_child(people)
		var ai := CheckBox.new()
		ai.text = "AI"
		ai.tooltip_text = "Computer player in test games (otherwise the player's units stand idle)"
		ai.button_pressed = editor.computer[player - 1]
		ai.disabled = player == 1
		ai.toggled.connect(func(on: bool) -> void: editor.computer[player - 1] = on)
		row.add_child(ai)
		_page_box.add_child(row)
	_page_box.add_child(_heading("Start resources"))
	var grid := GridContainer.new()
	grid.columns = 2
	for key in ["food", "wood", "gold", "guns"]:
		var caption := Label.new()
		caption.text = GameData.text(Player.RESOURCES[key].text, key.capitalize())
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(caption)
		var amount := SpinBox.new()
		amount.max_value = 100000
		amount.step = 50 if key != "guns" else 1
		amount.value = int(editor.map.start_resources.get(key, 0))
		amount.value_changed.connect(func(value: float) -> void:
			editor.map.start_resources[key] = int(value)
			editor.dirty = true)
		grid.add_child(amount)
	_page_box.add_child(grid)


func _owner_row() -> Control:
	var box := VBoxContainer.new()
	box.add_child(_heading("For player"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", int(3 * ui_scale))
	var group := ButtonGroup.new()
	for player in range(1, 9):
		var button := _button(str(player), func() -> void:
			editor.player = player
			show_page(_page))
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(editor.player == player)
		button.icon = _colour_icon(Player.TEAM_COLORS[player])
		button.tooltip_text = "Player %d" % player
		row.add_child(button)
	box.add_child(row)
	return box


# ------------------------------------------------------------------ dialogs

func _ask_new() -> void:
	_confirm_discard(func() -> void:
		var box := _dialog("New map")
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", int(10 * ui_scale))
		grid.add_theme_constant_override("v_separation", int(6 * ui_scale))
		var title := LineEdit.new()
		title.text = "New map"
		title.custom_minimum_size.x = 240 * ui_scale
		var width := OptionButton.new()
		var height := OptionButton.new()
		for option: OptionButton in [width, height]:
			for size in MapEditor.SIZES:
				option.add_item("%d cells (%d px)" % [size, size * 32])
			option.select(MapEditor.SIZES.find(128))
		var biome := OptionButton.new()
		biome.add_item("Prairie (steppe)")
		biome.add_item("Meadow (wiese)")
		var fill := OptionButton.new()
		var fills: Array = TerrainRules.PAINTABLE if editor.rules else [MapEditor.DEFAULT_FILL]
		for m in fills:
			fill.add_item(editor.rules.material_name(m) if editor.rules else "Default")
		fill.select(maxi(0, fills.find(MapEditor.DEFAULT_FILL)))
		for row in [["Title", title], ["Width", width], ["Height", height], ["Landscape", biome], ["Ground", fill]]:
			var caption := Label.new()
			caption.text = row[0]
			grid.add_child(caption)
			grid.add_child(row[1])
		box.add_child(grid)
		_dialog_buttons(box, "Create", func() -> void:
			editor.new_map(title.text, MapEditor.SIZES[width.selected], MapEditor.SIZES[height.selected],
					"wiese" if biome.selected == 1 else "steppe", fills[fill.selected])
			show_page(_page)))


func _ask_open() -> void:
	_confirm_discard(func() -> void:
		var box := _dialog("Open map")
		var list := ItemList.new()
		list.custom_minimum_size = Vector2(420, 360) * ui_scale
		var paths: Array[String] = []
		var mine := GameData.custom_maps_dir()
		var files := Array(GameData.map_files())
		files.sort_custom(func(a: String, b: String) -> bool:
			var a_mine := a.begins_with(mine)
			var b_mine := b.begins_with(mine)
			if a_mine != b_mine:
				return a_mine
			return a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
		for path: String in files:
			list.add_item(("★ " if path.begins_with(mine) else "") + path.get_file().get_basename())
			paths.append(path)
		box.add_child(list)
		box.add_child(_wrapped("★ your maps (in %s). Original maps are saved there as copies." % mine))
		var open := func() -> void:
			if list.get_selected_items().is_empty():
				return
			_close_dialog()
			editor.open_file(paths[list.get_selected_items()[0]])
			show_page(_page)
		list.item_activated.connect(func(_index: int) -> void: open.call())
		_dialog_buttons(box, "Open", open, false))


func _ask_leave() -> void:
	_confirm_discard(func() -> void:
		Match.editor_state = {}
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))


func _confirm_discard(then: Callable) -> void:
	if not editor.dirty:
		then.call()
		return
	var box := _dialog("Unsaved changes")
	box.add_child(_wrapped("The map has changes that are not saved. Continue without saving?"))
	_dialog_buttons(box, "Continue", then)


func _dialog(title: String) -> VBoxContainer:
	_close_dialog()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	_modal = shade
	var panel := PanelContainer.new()
	shade.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(10 * ui_scale))
	panel.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", int(22 * ui_scale))
	box.add_child(heading)
	panel.resized.connect(func() -> void:
		panel.position = (get_viewport().get_visible_rect().size - panel.size) / 2.0)
	return box


func _dialog_buttons(box: VBoxContainer, ok_text: String, ok: Callable, close_first := true) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", int(8 * ui_scale))
	row.add_child(_button("Cancel", _close_dialog))
	row.add_child(_button(ok_text, func() -> void:
		if close_first:
			_close_dialog()
		ok.call()))
	box.add_child(row)


func _close_dialog() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null


func _unhandled_key_input(event: InputEvent) -> void:
	if _modal and event.is_action_pressed("ui_cancel"):
		_close_dialog()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ widgets

func _button(text: String, action: Callable, tip := "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MenuStyle.TEXT_HOVER)
	label.add_theme_font_size_override("font_size", int(17 * ui_scale))
	return label


func _wrapped(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = (SIDE_WIDTH - 24) * ui_scale
	label.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	label.add_theme_font_size_override("font_size", int(13 * ui_scale))
	return label


func _thumb_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", int(4 * ui_scale))
	grid.add_theme_constant_override("v_separation", int(4 * ui_scale))
	return grid


## A palette button for an object type: picks the place tool with it.
func _type_button(type_id: int, player: int, name: String, guid := -1) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = name
	button.custom_minimum_size = Vector2(72, 72) * ui_scale
	button.set_pressed_no_signal(editor.place_type == type_id and editor.tool == MapEditor.Tool.PLACE)
	var thumb: Control = Thumbnail.portrait(guid) if guid >= 0 else null
	if thumb == null:
		thumb = Thumbnail.for_type(type_id, player)
	if thumb:
		thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = 4 * ui_scale
		thumb.offset_top = 4 * ui_scale
		thumb.offset_right = -4 * ui_scale
		thumb.offset_bottom = -4 * ui_scale
		button.add_child(thumb)
	else:
		button.text = name.left(6)
	button.pressed.connect(func() -> void:
		editor.place_type = type_id
		editor.tool = MapEditor.Tool.PLACE
		for sibling in button.get_parent().get_parent().find_children("*", "Button", true, false):
			if sibling != button and (sibling as Button).toggle_mode and sibling.get_parent() is GridContainer:
				(sibling as Button).set_pressed_no_signal(false)
		button.set_pressed_no_signal(true)
		_refresh())
	return button


## A readable name for a nature object from its type name, e.g. tree_deciduous_large_02_b_prairie
## -> "Deciduous tree, large 2b", mine_top_left_prairie -> "Gold mine (top left)".
func _nature_name(type_id: int, _group: String) -> String:
	var name := ObjectTypes.get_type(type_id).name.trim_suffix("_prairie").trim_suffix("_meadow")
	if name.begins_with("animal_"):
		return {"animal_buffalo": "Buffalo", "animal_horse": "Wild horse", "animal_cow": "Cow"}.get(name, name)
	if name.begins_with("mine_") or name.begins_with("ramp_"):
		var kind := "Gold mine" if name.begins_with("mine") else "Ramp"
		return "%s (%s)" % [kind, name.get_slice("_", 1) + " " + name.get_slice("_", 2)]
	var words := name.split("_")
	var variant := ""
	while not words.is_empty() and (words[-1].is_valid_int() or words[-1].length() == 1):
		variant = words[-1].trim_prefix("0") + variant
		words.remove_at(words.size() - 1)
	var text := " ".join(words).capitalize()
	text = text.replace("Tree Deciduous", "Deciduous tree").replace("Tree Conifer", "Conifer")
	return (text + " " + variant).strip_edges()


func _swatch(material: int) -> Texture2D:
	var colour := Color(0.5, 0.5, 0.5)
	var plain: Array = editor.rules.plain.get(material, [])
	if editor.terrain and not plain.is_empty():
		colour = editor.terrain.tile_color(plain[0][0])
	return _colour_icon(colour)


func _colour_icon(colour: Color) -> Texture2D:
	var size := int(18 * ui_scale)
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	for i in size:
		for edge in [Vector2i(i, 0), Vector2i(i, size - 1), Vector2i(0, i), Vector2i(size - 1, i)]:
			image.set_pixelv(edge, Color(0, 0, 0, 0.6))
	return ImageTexture.create_from_image(image)


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = MenuStyle.font()
	t.default_font_size = int(15 * ui_scale)
	var normal := _box(Color(0.16, 0.09, 0.04, 0.94), Color(0.45, 0.3, 0.14))
	var hover := _box(Color(0.3, 0.17, 0.07, 0.96), Color(0.7, 0.5, 0.24))
	var pressed := _box(Color(0.46, 0.26, 0.1, 0.97), Color(0.95, 0.75, 0.35))
	for type in ["Button", "OptionButton", "CheckBox"]:
		t.set_stylebox("normal", type, normal if type != "CheckBox" else StyleBoxEmpty.new())
		t.set_stylebox("hover", type, hover if type != "CheckBox" else StyleBoxEmpty.new())
		t.set_stylebox("pressed", type, pressed if type != "CheckBox" else StyleBoxEmpty.new())
		t.set_stylebox("hover_pressed", type, pressed if type != "CheckBox" else StyleBoxEmpty.new())
		t.set_stylebox("disabled", type, normal if type != "CheckBox" else StyleBoxEmpty.new())
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		for state in ["font_color", "font_focus_color"]:
			t.set_color(state, type, MenuStyle.TEXT)
		for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(state, type, MenuStyle.TEXT_HOVER)
		t.set_color("font_disabled_color", type, MenuStyle.TEXT_DIM)
	var field := _box(Color(0.08, 0.05, 0.02, 0.95), Color(0.4, 0.27, 0.12))
	for type in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, _box(Color(0.08, 0.05, 0.02, 0.95), Color(0.85, 0.65, 0.3)))
		t.set_color("font_color", type, MenuStyle.TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.1, 0.06, 0.03, 0.93), Color(0.3, 0.2, 0.1), 10))
	t.set_stylebox("panel", "ItemList", _box(Color(0.06, 0.04, 0.02, 0.95), Color(0.3, 0.2, 0.1)))
	t.set_stylebox("selected", "ItemList", _box(Color(0.55, 0.3, 0.12, 0.7), Color(0, 0, 0, 0)))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(0.55, 0.3, 0.12, 0.7), Color(0, 0, 0, 0)))
	t.set_color("font_color", "ItemList", MenuStyle.TEXT)
	t.set_color("font_selected_color", "ItemList", MenuStyle.TEXT_HOVER)
	t.set_color("font_color", "Label", MenuStyle.TEXT)
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.12, 0.07, 0.03, 0.98), Color(0.45, 0.3, 0.14)))
	t.set_stylebox("hover", "PopupMenu", _box(Color(0.45, 0.25, 0.1, 0.9), Color(0, 0, 0, 0)))
	t.set_color("font_color", "PopupMenu", MenuStyle.TEXT)
	t.set_color("font_hover_color", "PopupMenu", MenuStyle.TEXT_HOVER)
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.12, 0.07, 0.03, 0.97), Color(0.6, 0.42, 0.2)))
	t.set_color("font_color", "TooltipLabel", MenuStyle.TEXT)
	return t


func _box(colour: Color, border: Color, margin := 6) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(margin * ui_scale)
	return box
