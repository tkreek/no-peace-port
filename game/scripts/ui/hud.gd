class_name Hud
extends CanvasLayer
## In-game interface built from the original wooden status bar, laid out for widescreen:
## left panel (selection), tiled planks in the middle, minimap panel on the right, and a
## resource strip along the top. Scales with the window height.

const STATUS_SHEET := "global/gfx/status/leiste/bilderliste__1.spr"
const MINIMAP_PANEL := "global/gfx/status/leiste/leisterechts.pic"
const ICON_BOB := "global/gfx/status/resourcenicons/resourcenicons.bob"
const MINIMAP_HOLE := Rect2(83, 15, 164, 160)  # magenta window in leisterechts.pic
const BAR_HEIGHT := 167.0
const TEXT_COLOR := Color("#f3e3bd")

var player: Player
var selection: SelectionController
var ui_scale := 1.0
var minimap := Minimap.new()

var _root := Control.new()
var _left := TextureRect.new()
var _middle := TextureRect.new()
var _right := TextureRect.new()
var _top := TextureRect.new()
var _resources := HBoxContainer.new()
var _resource_labels := {}
var _selection_title := Label.new()
var _selection_detail := Label.new()
var _health_bar := ProgressBar.new()
var build_controller: BuildController
var biome := "steppe"
var _commands := GridContainer.new()
var _command_signature := ""
var _population_label: Label
var _status_sheet: RdSprite
var _icon_sheet: RdSprite
var _icon_material: Material


func setup(map: AlfMap, terrain_colors: Image, camera: Camera2D, objects: Node2D, local_player: Player,
		selection_controller: SelectionController) -> void:
	player = local_player
	selection = selection_controller
	_status_sheet = GameData.load_sprite(STATUS_SHEET)
	var icon_bob := GameData.load_bob(ICON_BOB)
	_icon_sheet = GameData.load_sprite(ICON_BOB.get_base_dir().path_join(icon_bob.sub_sprites[0]))
	_icon_material = SpriteMaterials.body(_icon_sheet,
			GameData.load_palette_texture(ICON_BOB.get_base_dir(), icon_bob.palettes), null)

	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	for panel: TextureRect in [_middle, _left, _right, _top]:
		panel.stretch_mode = TextureRect.STRETCH_TILE
		panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_root.add_child(panel)
	_left.stretch_mode = TextureRect.STRETCH_SCALE
	_right.stretch_mode = TextureRect.STRETCH_SCALE
	_right.texture = _minimap_panel_texture()

	minimap.setup(map, camera, objects, terrain_colors)
	_root.add_child(minimap)
	_root.move_child(minimap, _root.get_children().find(_right))  # behind the frame

	_top.add_child(_resources)
	for key in Player.RESOURCES:
		var icon := TextureRect.new()
		var frame: int = Player.RESOURCES[key].icon
		icon.texture = _atlas(_icon_sheet, frame)
		icon.material = _icon_material
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.tooltip_text = GameData.text(Player.RESOURCES[key].text, key)
		_resources.add_child(icon)
		icon.set_instance_shader_parameter("palette_row", 0)
		var label := _label(18)
		_resources.add_child(label)
		_resource_labels[key] = label

	for label in [_selection_title, _selection_detail]:
		_style_label(label, 22 if label == _selection_title else 16)
		_left.add_child(label)
	_root.add_child(_commands)
	_health_bar.show_percentage = false
	_health_bar.add_theme_stylebox_override("background", _flat(Color(0.12, 0.08, 0.05, 0.85)))
	_health_bar.add_theme_stylebox_override("fill", _flat(Color(0.35, 0.75, 0.2)))
	_left.add_child(_health_bar)

	var pop_icon := TextureRect.new()
	pop_icon.texture = _atlas(_icon_sheet, 5)
	pop_icon.material = _icon_material
	pop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pop_icon.tooltip_text = GameData.text(77, "Population")
	_resources.add_child(pop_icon)
	pop_icon.set_instance_shader_parameter("palette_row", 0)
	_population_label = _label(18)
	_resources.add_child(_population_label)
	player.resources_changed.connect(_refresh_resources)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_resources()


func _process(_delta: float) -> void:
	_population_label.text = "%d / %d" % [player.population(), player.population_cap()]
	_refresh_selection()
	_refresh_commands()


## Screen area not covered by the HUD (for camera bounds and clicks).
func blocks_point(screen_point: Vector2) -> bool:
	for panel: Control in [_left, _middle, _right, _top]:
		if panel.get_global_rect().has_point(screen_point):
			return true
	return false


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	ui_scale = clampf(minf(view.y / 720.0, view.x / 1280.0), 1.0, 3.0)
	var bar_h := BAR_HEIGHT * ui_scale
	var left_size := _frame_size(_status_sheet, 0) * ui_scale
	_left.texture = _status_frame(0, 1.0)
	_middle.texture = _status_frame(1, ui_scale)
	_top.texture = _status_frame(1, ui_scale)
	var right_size := Vector2(256, 184) * ui_scale
	_left.position = Vector2(0, view.y - bar_h)
	_left.size = left_size
	_right.position = view - right_size
	_right.size = right_size
	_middle.position = Vector2(left_size.x, view.y - bar_h)
	_middle.size = Vector2(maxf(0.0, view.x - left_size.x - right_size.x), bar_h)
	_middle.scale = Vector2.ONE
	minimap.position = _right.position + MINIMAP_HOLE.position * ui_scale
	minimap.size = MINIMAP_HOLE.size * ui_scale

	var top_h := 30.0 * ui_scale
	_top.position = Vector2.ZERO
	_top.size = Vector2(view.x, top_h)
	_resources.position = Vector2(12, 3) * ui_scale
	_resources.size = Vector2(view.x - 24 * ui_scale, top_h - 6 * ui_scale)
	_resources.add_theme_constant_override("separation", int(8 * ui_scale))
	for child in _resources.get_children():
		if child is TextureRect:
			child.custom_minimum_size = Vector2(22, 22) * ui_scale
		else:
			child.add_theme_font_size_override("font_size", int(18 * ui_scale))
			child.custom_minimum_size.x = (90 if child == _population_label else 64) * ui_scale

	# Command buttons fill the plank area between the selection panel and the minimap.
	var button_size := 50.0 * ui_scale
	var spacing := 4.0 * ui_scale
	_commands.position = _middle.position + Vector2(10, 14) * ui_scale
	_commands.columns = maxi(1, int((_middle.size.x - 20 * ui_scale + spacing) / (button_size + spacing)))
	_commands.add_theme_constant_override("h_separation", int(4 * ui_scale))
	_commands.add_theme_constant_override("v_separation", int(4 * ui_scale))
	for button in _commands.get_children():
		button.custom_minimum_size = Vector2(50, 50) * ui_scale
	var pad := Vector2(28, 22) * ui_scale
	_selection_title.position = pad
	_selection_title.add_theme_font_size_override("font_size", int(22 * ui_scale))
	_health_bar.position = pad + Vector2(0, 36) * ui_scale
	_health_bar.size = Vector2(220, 10) * ui_scale
	_selection_detail.position = pad + Vector2(0, 54) * ui_scale
	_selection_detail.add_theme_font_size_override("font_size", int(16 * ui_scale))


func _refresh_resources() -> void:
	for key in _resource_labels:
		_resource_labels[key].text = str(player.resources.get(key, 0))


func _refresh_selection() -> void:
	var units := selection.selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	var building := selection.selected_building
	if units.is_empty() and is_instance_valid(building):
		_health_bar.visible = true
		_selection_title.text = building.display_name()
		_health_bar.max_value = building.max_health
		_health_bar.value = building.health
		if not building.complete:
			_selection_detail.text = "Under construction %d%%" % int(building.build_progress * 100)
		elif not building.queue.is_empty():
			_selection_detail.text = "Training %s (%d queued)" % [
				GameData.stats(building.queue[0]).get("name", "?"), building.queue.size()]
		else:
			_selection_detail.text = "Energy %d / %d" % [building.health, building.max_health]
		return
	_health_bar.visible = not units.is_empty()
	if units.is_empty():
		_selection_title.text = ""
		_selection_detail.text = ""
		return
	var first: Unit = units[0]
	var same := units.all(func(u: Unit) -> bool: return u.unit_type == first.unit_type)
	_selection_title.text = first.display_name() if same else "%d units" % units.size()
	var health := 0.0
	var max_health := 0.0
	for u: Unit in units:
		health += u.health
		max_health += u.max_health
	_health_bar.max_value = max_health
	_health_bar.value = health
	_selection_detail.text = ("%d selected" % units.size()) if units.size() > 1 else \
			"Health %d / %d" % [first.health, first.max_health]


## A status-bar plank as its own texture, resized so 1 original pixel = `pixel_scale` screen px
## (tiling needs a standalone texture; the left panel is stretched instead, so 1.0 there).
func _status_frame(frame: int, pixel_scale: float) -> Texture2D:
	var image := _status_sheet.texture.get_image().get_region(_status_sheet.rects[frame])
	if image.is_compressed():
		image.decompress()
	var target := (_frame_size(_status_sheet, frame) * pixel_scale).round()
	if Vector2(image.get_size()) != target:
		image.resize(int(target.x), int(target.y), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func _atlas(sheet: RdSprite, frame: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet.texture
	atlas.region = Rect2(sheet.rects[frame])
	return atlas


func _frame_size(sheet: RdSprite, frame: int) -> Vector2:
	return Vector2(sheet.rects[frame].size) / sheet.scale


func _minimap_panel_texture() -> Texture2D:
	var image := GameData.load_image(MINIMAP_PANEL)
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r8 > 240 and c.g8 < 16 and c.b8 > 240:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


func _label(size: int) -> Label:
	var label := Label.new()
	_style_label(label, size)
	return label


func _style_label(label: Label, size: int) -> void:
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


## Rebuild the command buttons when what they depend on changes.
func _refresh_commands() -> void:
	var units := selection.selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	var building := selection.selected_building if is_instance_valid(selection.selected_building) else null
	var builders := units.filter(func(u: Unit) -> bool: return u.unit_type.anim_index("build") >= 0)
	var farmers := units.filter(func(u: Unit) -> bool: return u.unit_type.can_gather("food"))
	var signature := "%s|%s|%s|%s" % [builders.size() > 0, farmers.size() > 0, building.get_instance_id() if building else 0,
			building.complete if building else false]
	if signature == _command_signature:
		_update_affordability()
		return
	_command_signature = signature
	for child in _commands.get_children():
		child.queue_free()
	if not farmers.is_empty():
		var field_type := GameData.type_for_guid(MapObject.FIELD_GUID, biome)
		if field_type >= 0:
			_add_command(field_type, MapObject.FIELD_GUID, func() -> void: build_controller.start(field_type))
	if not builders.is_empty():
		for guid in _faction_guids("structure"):
			if guid == MapObject.FIELD_GUID:
				continue
			var type_id := GameData.type_for_guid(guid, biome)
			if type_id >= 0:
				_add_command(type_id, guid, func() -> void: build_controller.start(type_id))
	elif building and building.complete and building.owner_index == player.index:
		for guid in building.trainable_units():
			var type_id := GameData.type_for_guid(guid, biome)
			if type_id >= 0:
				_add_command(type_id, guid, func() -> void: building.enqueue(guid))
	_layout()


func _faction_guids(kind: String) -> Array:
	var out := []
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") == player.faction and stats.get("kind") == kind:
			out.append(guid)
	out.sort()
	return out


func _add_command(type_id: int, guid: int, action: Callable) -> void:
	var button := Button.new()
	button.flat = false
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _flat(Color(0.93, 0.84, 0.64, 0.92)))
	button.add_theme_stylebox_override("hover", _flat(Color(1.0, 0.94, 0.78, 0.98)))
	button.add_theme_stylebox_override("pressed", _flat(Color(0.8, 0.7, 0.5, 0.98)))
	button.add_theme_stylebox_override("disabled", _flat(Color(0.45, 0.4, 0.35, 0.8)))
	var stats := GameData.stats(guid)
	var cost := PackedStringArray()
	for key in stats.get("cost", {}):
		if key != "population":
			cost.append("%d %s" % [stats.cost[key], key])
	button.tooltip_text = "%s\n%s" % [stats.get("name", "?"), ", ".join(cost)]
	button.set_meta("guid", guid)
	button.pressed.connect(action)
	var thumb := Thumbnail.portrait(guid)
	var inset := 0
	if thumb == null:
		thumb = Thumbnail.for_type(type_id, player.index)
		inset = 3
	if thumb and thumb.has_meta("portrait"):
		# The parchment portrait is the button; just brighten it on hover.
		var none := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, none)
		button.mouse_entered.connect(func() -> void: thumb.self_modulate = Color(1.15, 1.1, 1.0))
		button.mouse_exited.connect(func() -> void: thumb.self_modulate = Color.WHITE)
	if thumb:
		thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = inset
		thumb.offset_top = inset
		thumb.offset_right = -inset
		thumb.offset_bottom = -inset
		button.add_child(thumb)
	_commands.add_child(button)


func _update_affordability() -> void:
	for button: Button in _commands.get_children():
		var cost: Dictionary = GameData.stats(button.get_meta("guid")).get("cost", {}).duplicate()
		cost.erase("population")
		cost.erase("horses")
		var guid: int = button.get_meta("guid")
		button.disabled = not player.can_afford(cost) or not player.meets_prerequisites(guid)
		if guid == MapObject.FIELD_GUID:
			button.disabled = not player.can_afford(cost) or MapObject.field_allowance(player.index) <= 0
		button.modulate = Color(1, 1, 1, 0.55) if button.disabled else Color.WHITE


## Large centred message (victory / defeat).
func show_banner(text: String) -> void:
	var label := _label(64)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.add_theme_font_size_override("font_size", int(64 * ui_scale))
	label.add_theme_constant_override("outline_size", int(10 * ui_scale))
	_root.add_child(label)
	label.position = get_viewport().get_visible_rect().size / 2.0 - label.get_minimum_size() / 2.0
