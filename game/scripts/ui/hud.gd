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
## The original command icons (all peoples use the same sheets).
const COMMAND_ICONS := "global/gfx/usa/sonstigeicons/SonstigeIcons.spr"
const EXTRA_ICONS := "global/gfx/usa/sonstigeicons/Iconserstereihe.spr"
## SonstigeIcons frames (colour; +1 is the greyed version).
const ICON_STOP := 14
const ICON_BUILD := 18  # small hammer: structures for the economic and military cycle
const ICON_BUILD_EXPANDED := 16  # large hammer: structures with enhanced functions
const STANCE_ICONS := {Unit.Stance.AGGRESSIVE: 0, Unit.Stance.DEFENSIVE: 6, Unit.Stance.HOLD: 12,
		Unit.Stance.PASSIVE: 8}
const STANCE_NAMES := {Unit.Stance.AGGRESSIVE: "Act aggressively", Unit.Stance.DEFENSIVE: "Act defensively",
		Unit.Stance.HOLD: "Hold ground", Unit.Stance.PASSIVE: "Passive"}
const STANCE_KEYS := {KEY_A: Unit.Stance.AGGRESSIVE, KEY_D: Unit.Stance.DEFENSIVE, KEY_H: Unit.Stance.HOLD,
		KEY_Y: Unit.Stance.PASSIVE}
const FIELD_ICONS := "global/gfx/usa/icons/einheiten/USAEinheiten.spr"
const ICON_FIELD := 32  # the green crop field among the unit icons
const FORMATION_ICONS_SHEET := "global/gfx/usa/sonstigeicons/KleineIcons.spr"
const FORMATION_ICONS := {Unit.Formation.COLUMN: 11, Unit.Formation.DOUBLE_COLUMN: 9, Unit.Formation.WEDGE: 6,
		Unit.Formation.DOUBLE_LINE: 4, Unit.Formation.SQUARE: 2, Unit.Formation.RELAXED: 0}
const FORMATION_NAMES := {Unit.Formation.COLUMN: "Column", Unit.Formation.DOUBLE_COLUMN: "Double column",
		Unit.Formation.WEDGE: "Wedge", Unit.Formation.DOUBLE_LINE: "Double line", Unit.Formation.SQUARE: "Square",
		Unit.Formation.RELAXED: "Relaxed"}
const ICON_FOLLOW := 2  # two men walking one behind the other
const ICON_PATROL := 4  # two men with an arrow
const ICON_RALLY := 12  # Iconserstereihe: signpost
const ICON_ENTER := 2  # Iconserstereihe: arrow into a doorway
const ICON_LEAVE := 0  # arrow out of a doorway
const ICON_DEMOLISH := 8  # Iconserstereihe: gravestone
const ICON_BACK := 0  # Iconserstereihe: arrow out of a doorway
## "Build expanded structure" (V) per the manual's keyboard table; every other structure is
## a basic one (B).
const EXPANDED_STRUCTURES := [110, 111, 112, 114, 115,  # campfire, totem, camouflage school, pitfall, medicine man
		210, 211, 212, 213, 215, 216, 217, 218,  # Mexican trading post, weapons, wall, tower, church, mission, fort, wharf
		307, 310, 311, 312, 313, 314, 315,  # hotel, drugstore, cellar, barricade, lookout, explosives, boathouse
		407, 411, 412, 413, 415, 416, 417, 418]  # sheriff, weapons, stockade, tower, church, bank, fort, wharf
const TREE_PORTRAIT := "Potraits/Sonstige_icons/z04_baum.bmp"
const MINE_PORTRAIT := "Potraits/Sonstige_icons/z05_goldmine.bmp"
const PORTRAIT_SIZE := 72.0
const CARD_SIZE := 44.0
const CARD_STEP := 15.0  # queued units overlap like a hand of cards
const GROUP_ICON := 34.0

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
var _command_icons: RdSprite
var _extra_icons: RdSprite
var _formation_icons: RdSprite
var _build_menu := ""  # "", "basic" or "expanded"
var _queue_box := Control.new()
var _queue_signature := ""
var _group_box := Control.new()
var _group_signature := ""
var _portrait := TextureRect.new()
var _portrait_key := ""


func setup(map: AlfMap, terrain_colors: Image, camera: Camera2D, objects: Node2D, local_player: Player,
		selection_controller: SelectionController) -> void:
	player = local_player
	selection = selection_controller
	_status_sheet = GameData.load_sprite(STATUS_SHEET)
	_command_icons = GameData.load_sprite(COMMAND_ICONS)
	_extra_icons = GameData.load_sprite(EXTRA_ICONS)
	_formation_icons = GameData.load_sprite(FORMATION_ICONS_SHEET)
	var icon_bob := GameData.load_bob(ICON_BOB)
	_icon_sheet = GameData.load_sprite(ICON_BOB.get_base_dir().path_join(icon_bob.sub_sprites[0]))
	_icon_material = SpriteMaterials.body(_icon_sheet,
			GameData.load_palette_texture(ICON_BOB.get_base_dir(), icon_bob.palettes), null)

	process_mode = Node.PROCESS_MODE_ALWAYS  # the in-game menu works while paused
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
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(_portrait)
	for box: Control in [_queue_box, _group_box]:
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_left.add_child(box)

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
	ui_scale = clampf(minf(view.y / 1080.0, view.x / 1920.0) * 1.15, 0.8, 2.5)
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
	_portrait.position = pad + Vector2(0, 4) * ui_scale
	_portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE) * ui_scale
	_layout_selection(_portrait.texture != null)
	_selection_title.add_theme_font_size_override("font_size", int(22 * ui_scale))
	_selection_detail.add_theme_font_size_override("font_size", int(13 * ui_scale))
	_selection_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_group_box.position = pad + Vector2(0, 2) * ui_scale
	_queue_signature = ""
	_group_signature = ""


func _refresh_resources() -> void:
	for key in _resource_labels:
		_resource_labels[key].text = str(player.resources.get(key, 0))


func _refresh_selection() -> void:
	var units := selection.selection.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	var building := selection.selected_building if is_instance_valid(selection.selected_building) else null
	if units.is_empty() and building:
		_set_portrait(building.guid, building)
		_selection_title.visible = true
		_selection_detail.visible = true
		_selection_title.text = building.display_name()
		_health_bar.visible = building.is_building()
		_health_bar.max_value = building.max_health
		_health_bar.value = building.health
		_selection_detail.text = _object_detail(building)
		_refresh_queue(building)
		_refresh_group([])
		return
	_refresh_queue(null)
	_refresh_group(units if units.size() > 1 else [])
	_health_bar.visible = units.size() == 1
	_selection_title.visible = units.size() <= 1
	_selection_detail.visible = units.size() <= 1
	if units.size() != 1:
		_set_portrait(-1, null)
		_selection_title.text = ""
		_selection_detail.text = ""
		return
	var unit: Unit = units[0]
	_set_portrait(unit.unit_type.guid(), unit)
	_selection_title.text = unit.display_name()
	_health_bar.max_value = unit.max_health
	_health_bar.value = unit.health
	_selection_detail.text = _unit_detail(unit)


## Everything worth knowing about one unit: energy, weapon, range, reload, sight, speed.
func _unit_detail(unit: Unit) -> String:
	var lines := PackedStringArray(["Energy %d / %d" % [unit.health, unit.max_health]])
	if not unit.unit_type.attack_anims.is_empty():
		var weapon := "Range %d" % unit.attack_range() if unit.unit_type.ranged else "Melee"
		lines.append("Damage %d   %s" % [unit.attack_damage(), weapon])
		lines.append("Reload %.1f s   Sight %d" % [unit.unit_type.reload_ms / 1000.0, unit.sight()])
		lines.append("Speed %d   %s" % [unit.move_speed(), STANCE_NAMES[unit.stance]])
	else:
		lines.append("Sight %d   Speed %d" % [unit.sight(), unit.move_speed()])
	if unit.carried > 0:
		lines.append("Carrying %d %s" % [unit.carried, unit.carrying])
	return "\n".join(lines)


func _object_detail(object: MapObject) -> String:
	if object.is_tree():
		return "Wood left: %d" % object.amount
	if object.is_mine():
		return "Gold left: %d" % object.amount if object.amount > 0 else "Exhausted"
	if object.is_field():
		match object.field_state:
			MapObject.Field.FALLOW:
				return "Fallow — needs sowing"
			MapObject.Field.GROWING:
				return "Growing %d%%" % int(object.field_progress * 100)
		return "Ripe: %d food" % object.amount
	var owner_note := ""
	if object.owner_index != player.index and Player.by_index.has(object.owner_index):
		owner_note = "\n" + Match.faction_name(Player.by_index[object.owner_index].faction)
	if not object.complete:
		return "Under construction %d%%\nEnergy %d / %d%s" % [int(object.build_progress * 100), object.health,
				object.max_health, owner_note]
	if not object.queue.is_empty():
		var current := GameData.stats(object.queue[0])
		return "%s %s — %d%%" % ["Researching" if current.get("kind") == "upgrade" else "Training",
				current.get("name", "?"), int(object.train_progress * 100)]
	var housing := int(GameData.stats(object.guid).get("housing", 0))
	var quartered := "\nQuartered %d / %d" % [object.garrison.size(), object.capacity()] if object.capacity() > 0 else ""
	return "Energy %d / %d%s%s%s" % [object.health, object.max_health,
			"\nHouses %d" % housing if housing > 0 else "", quartered, owner_note]


## The portrait of the selected unit or object at the left of the panel.
func _set_portrait(guid: int, thing: Object) -> void:
	var key := "%d:%s" % [guid, thing.get_instance_id() if thing else 0]
	if key == _portrait_key:
		return
	_portrait_key = key
	_portrait.texture = null
	if thing == null:
		_layout_selection(false)
		return
	var thumb: Thumbnail = null
	if thing is MapObject and thing.is_tree():
		thumb = Thumbnail.from_bmp(TREE_PORTRAIT)
	elif thing is MapObject and thing.is_mine():
		thumb = Thumbnail.from_bmp(MINE_PORTRAIT)
	elif guid >= 0:
		thumb = Thumbnail.portrait(guid)
	if thumb == null and thing is MapObject and thing.object_type:
		thumb = Thumbnail.for_type(thing.object_type.id, thing.owner_index)
	elif thumb == null and thing is Unit:
		thumb = Thumbnail.for_type(thing.unit_type.type_id, thing.team)
	if thumb:
		_portrait.texture = thumb.texture
		_portrait.material = thumb.material
		thumb.free()
	_layout_selection(_portrait.texture != null)


## The production queue as a hand of overlapping cards; the first one shows its progress.
## Clicking a card cancels that order and refunds it.
func _refresh_queue(building: MapObject) -> void:
	var queue: Array = Array(building.queue) if building and building.complete else []
	var quartered: Array = building.garrison.duplicate() if building and queue.is_empty() else []
	var signature := "%s|%s|%s" % [building.get_instance_id() if building else 0, queue,
			quartered.map(func(u: Unit) -> int: return u.get_instance_id())]
	if signature != _queue_signature:
		_queue_signature = signature
		for child in _queue_box.get_children():
			child.queue_free()
		for i in queue.size():
			var card := _card(queue[i], CARD_SIZE * ui_scale)
			card.position = Vector2(i * CARD_STEP * ui_scale + (8 * ui_scale if i > 0 else 0.0), 0)
			card.tooltip_text = "%s\nClick to cancel" % GameData.stats(queue[i]).get("name", "?")
			var index := i
			card.pressed.connect(func() -> void: building.cancel_queued(index))
			_queue_box.add_child(card)
			_queue_box.move_child(card, 0)  # later orders tuck in behind the first
		# Quartered units: click one to send it out.
		for i in quartered.size():
			var unit: Unit = quartered[i]
			var card := _card(unit.unit_type.guid(), CARD_SIZE * 0.8 * ui_scale, unit.unit_type.type_id)
			card.position = Vector2(i * (CARD_SIZE * 0.8 + 3) * ui_scale, 0)
			card.tooltip_text = "%s\nClick to leave quarters" % unit.display_name()
			card.pressed.connect(func() -> void: building.release(unit))
			_queue_box.add_child(card)
		if not queue.is_empty():
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.add_theme_stylebox_override("background", _flat(Color(0.12, 0.08, 0.05, 0.85)))
			bar.add_theme_stylebox_override("fill", _flat(Color(0.4, 0.7, 1.0)))
			bar.position = Vector2(0, CARD_SIZE * ui_scale + 2)
			bar.size = Vector2(CARD_SIZE * ui_scale, 5 * ui_scale)
			bar.max_value = 1.0
			bar.step = 0.0
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.name = "Progress"
			_queue_box.add_child(bar)
	var progress := _queue_box.get_node_or_null("Progress") as ProgressBar
	if progress and building:
		progress.value = building.train_progress


## Portraits of every selected unit with a health strip. Click one to select only it,
## shift-click to drop it from the selection.
func _refresh_group(units: Array) -> void:
	var signature := ",".join(units.map(func(u: Unit) -> String: return str(u.get_instance_id())))
	if signature != _group_signature:
		_group_signature = signature
		for child in _group_box.get_children():
			child.queue_free()
		var size := GROUP_ICON * ui_scale
		var columns := maxi(1, int((_left.size.x - 50 * ui_scale) / (size + 2)))
		for i in units.size():
			var unit: Unit = units[i]
			var card := _card(unit.unit_type.guid(), size, unit.unit_type.type_id)
			card.position = Vector2((i % columns) * (size + 2), (i / columns) * (size + 7 * ui_scale))
			card.tooltip_text = unit.display_name()
			card.set_meta("unit", unit)
			card.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					if event.shift_pressed:
						selection.deselect(unit)
					else:
						selection.select_units([unit])
					card.accept_event())
			var health := ColorRect.new()
			health.name = "Health"
			health.mouse_filter = Control.MOUSE_FILTER_IGNORE
			health.position = Vector2(0, size + 1)
			health.size = Vector2(size, 3 * ui_scale)
			card.add_child(health)
			_group_box.add_child(card)
	for card in _group_box.get_children():
		var unit = card.get_meta("unit") if card.has_meta("unit") else null  # may have been freed
		var health := card.get_node_or_null("Health") as ColorRect
		if is_instance_valid(unit) and health:
			var ratio: float = unit.health / unit.max_health if unit.max_health > 0 else 0.0
			health.size.x = GROUP_ICON * ui_scale * ratio
			health.color = Color(0.9, 0.2, 0.1).lerp(Color(0.3, 0.85, 0.2), ratio)


## A small portrait button for a unit, building or upgrade.
func _card(guid: int, size: float, type_id := -1) -> Button:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.size = Vector2(size, size)
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		card.add_theme_stylebox_override(state, none)
	var thumb: Control = Thumbnail.portrait(guid)
	if thumb == null and type_id < 0:
		type_id = GameData.type_for_guid(guid, biome)
	if thumb == null and type_id >= 0:
		thumb = Thumbnail.for_type(type_id, player.index)
	if thumb == null:
		var label := MenuStyle.label(GameData.stats(guid).get("name", "?"), int(9 * ui_scale), Color("#3a2410"))
		label.add_theme_constant_override("outline_size", 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var paper := Panel.new()
		paper.add_theme_stylebox_override("panel", _flat(Color(0.93, 0.84, 0.64, 0.95)))
		paper.add_child(label)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb = paper
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(thumb)
	card.mouse_entered.connect(func() -> void: thumb.modulate = Color(1.2, 1.15, 1.0))
	card.mouse_exited.connect(func() -> void: thumb.modulate = Color.WHITE)
	return card


## A status-bar plank as its own texture, resized so 1 original pixel = `pixel_scale` screen px
## (tiling needs a standalone texture; the left panel is stretched instead, so 1.0 there).
## Title, energy bar and details sit beside the portrait when there is one.
func _layout_selection(with_portrait: bool) -> void:
	var pad := Vector2(28, 22) * ui_scale
	var x := (PORTRAIT_SIZE + 10) * ui_scale if with_portrait else 0.0
	_portrait.visible = with_portrait
	_selection_title.position = pad + Vector2(x, 0)
	_health_bar.position = pad + Vector2(x, 34 * ui_scale)
	_health_bar.size = Vector2(maxf(80 * ui_scale, _left.size.x - pad.x * 2 - x - 20 * ui_scale), 8 * ui_scale)
	_selection_detail.position = pad + Vector2(x, 44 * ui_scale)
	_queue_box.position = pad + Vector2(0, 86) * ui_scale


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
	var builders := units.filter(func(u: Unit) -> bool: return u.unit_type.can_build())
	var full_builders := builders.any(func(u: Unit) -> bool: return u.unit_type.anim_index("build") >= 0)
	var farmers := units.filter(func(u: Unit) -> bool: return u.unit_type.is_farmer())
	var fighters := units.filter(func(u: Unit) -> bool: return not u.unit_type.attack_anims.is_empty() \
			and not u.unit_type.can_build() and u.team == player.index)
	var stances := {}
	var formations := {}
	for u: Unit in fighters:
		stances[u.stance] = true
		formations[u.formation] = true
	if builders.is_empty():
		_build_menu = ""
	var research_state := "%d/%s" % [player.researched.size(), building.queue if building else []]
	var signature := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [research_state, builders.size() > 0, full_builders,
			farmers.size() > 0, building.get_instance_id() if building else 0,
			building.complete if building else false, _build_menu, fighters.size() > 0, stances.keys(),
			units.size() > 0, formations.keys(), selection.pending,
			building.garrison.size() if building else 0]
	if signature == _command_signature:
		_update_affordability()
		return
	_command_signature = signature
	for child in _commands.get_children():
		child.queue_free()
	if not _build_menu.is_empty():
		# One of the two building menus: its structures, then a way back.
		for guid in _faction_guids("structure"):
			if guid == MapObject.FIELD_GUID or (guid in EXPANDED_STRUCTURES) != (_build_menu == "expanded"):
				continue
			if not full_builders and guid not in MapObject.FOOD_STORES:
				continue
			var type_id := GameData.type_for_guid(guid, biome)
			if type_id >= 0:
				_add_command(type_id, guid, func() -> void: build_controller.start(type_id))
		_add_icon_command(_extra_icons, ICON_BACK, "Back", func() -> void: _open_build_menu(""))
	elif not units.is_empty():
		if not builders.is_empty():
			_add_icon_command(_command_icons, ICON_BUILD, "Build structure (B)", func() -> void: _open_build_menu("basic"))
			if full_builders:
				_add_icon_command(_command_icons, ICON_BUILD_EXPANDED, "Build expanded structure (V)",
						func() -> void: _open_build_menu("expanded"))
		if not farmers.is_empty():
			var field_type := GameData.type_for_guid(MapObject.FIELD_GUID, biome)
			if field_type >= 0:
				_add_command(field_type, MapObject.FIELD_GUID, func() -> void: build_controller.start(field_type))
				_commands.get_child(_commands.get_child_count() - 1).set_meta("tooltip", "Field (F)\n" + \
						_commands.get_child(_commands.get_child_count() - 1).get_meta("tooltip"))
		if not fighters.is_empty():
			for stance in STANCE_ICONS:
				var key: int = STANCE_KEYS.find_key(stance)
				_add_icon_command(_command_icons, STANCE_ICONS[stance], "%s (%s)" % [STANCE_NAMES[stance],
						OS.get_keycode_string(key)], func() -> void: set_stance(stance),
						stances.size() == 1 and stances.has(stance))
		if not fighters.is_empty():
			_add_icon_command(_command_icons, ICON_PATROL, "Patrol (Z): click the far end of the route",
					func() -> void: selection.begin_targeting("patrol"), selection.pending == "patrol")
			_add_icon_command(_command_icons, ICON_FOLLOW, "Follow (C): click the unit to follow",
					func() -> void: selection.begin_targeting("follow"), selection.pending == "follow")
			if fighters.size() > 1:
				for formation in FORMATION_ICONS:
					_add_icon_command(_formation_icons, FORMATION_ICONS[formation], FORMATION_NAMES[formation],
							func() -> void: set_formation(formation), formations.size() == 1 and formations.has(formation))
		_add_icon_command(_extra_icons, ICON_ENTER, "Move into quarters (G): click a fort or tower",
				func() -> void: selection.begin_targeting("quarters"), selection.pending == "quarters")
		_add_icon_command(_command_icons, ICON_STOP, "Stop (S)", stop_selection)
	elif building and building.complete and building.owner_index == player.index:
		for guid in building.trainable_units():
			var type_id := GameData.type_for_guid(guid, biome)
			if type_id >= 0:
				_add_command(type_id, guid, func() -> void:
					if not building.enqueue(guid):
						Sound.play_sound(80))  # the original "not possible" sound
		if not building.trainable_units().is_empty():
			_add_icon_command(_extra_icons, ICON_RALLY, "Specify assembly location (I)",
					func() -> void: selection.begin_targeting("rally"), selection.pending == "rally")
		for upgrade in building.researchable_upgrades():
			_add_command(-1, upgrade, func() -> void:
				if not building.enqueue(upgrade):
					Sound.play_sound(80))
	if building and building.owner_index == player.index and not building.garrison.is_empty():
		_add_icon_command(_extra_icons, ICON_LEAVE, "Move units from quarters (L)", func() -> void: building.release())
	if building and building.is_building() and building.owner_index == player.index:
		_add_icon_command(_extra_icons, ICON_DEMOLISH, "Demolish (Del)" if building.complete \
				else "Demolish (Del) — refunds the unbuilt part", func() -> void: building.demolish())
	_layout()


func _open_build_menu(menu: String) -> void:
	_build_menu = menu
	_command_signature = ""


func set_stance(stance: Unit.Stance) -> void:
	for u: Unit in selection.selection:
		if is_instance_valid(u) and u.is_alive() and not u.unit_type.attack_anims.is_empty():
			u.set_stance(stance)
	_command_signature = ""


func set_formation(formation: Unit.Formation) -> void:
	for u: Unit in selection.selection:
		if is_instance_valid(u) and u.is_alive():
			u.formation = formation
	selection.reform()
	_command_signature = ""


func stop_selection() -> void:
	for u: Unit in selection.selection:
		if is_instance_valid(u):
			u.stop()


## Original keyboard shortcuts for the command menu.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or get_tree().paused:
		return
	var key: int = event.keycode
	if event.ctrl_pressed or event.alt_pressed:
		return
	var handled := true
	if key == KEY_S:
		stop_selection()
	elif key == KEY_Z or key == KEY_C:
		if not selection.selection.is_empty():
			selection.begin_targeting("patrol" if key == KEY_Z else "follow")
	elif key == KEY_DELETE:
		var building := selection.selected_building
		if is_instance_valid(building) and building.owner_index == player.index:
			building.demolish()
	elif key == KEY_G:
		if not selection.selection.is_empty():
			selection.begin_targeting("quarters")
	elif key == KEY_L:
		if is_instance_valid(selection.selected_building) and selection.selected_building.owner_index == player.index:
			selection.selected_building.release()
	elif key == KEY_I:
		if is_instance_valid(selection.selected_building) and selection.selected_building.owner_index == player.index:
			selection.begin_targeting("rally")
	elif STANCE_KEYS.has(key):
		set_stance(STANCE_KEYS[key])
	elif key == KEY_B or key == KEY_V:
		_open_build_menu("basic" if key == KEY_B else "expanded")
	elif key == KEY_F:
		var field_type := GameData.type_for_guid(MapObject.FIELD_GUID, biome)
		if field_type >= 0 and selection.selection.any(func(u: Unit) -> bool:
				return is_instance_valid(u) and u.unit_type.is_farmer()):
			build_controller.start(field_type)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _add_icon_command(sheet: RdSprite, frame: int, tip: String, action: Callable, active := false) -> void:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, none)
	if active:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = Color(1.0, 0.85, 0.3)
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal", ring)
		button.add_theme_stylebox_override("hover", ring)
	button.tooltip_text = tip
	button.set_meta("tooltip", tip)
	button.set_meta("guid", -1)
	button.pressed.connect(action)
	if sheet and frame < sheet.frame_count():
		var icon := TextureRect.new()
		icon.texture = _atlas(sheet, frame)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(icon)
		button.mouse_entered.connect(func() -> void: icon.modulate = Color(1.2, 1.15, 1.0))
		button.mouse_exited.connect(func() -> void: icon.modulate = Color.WHITE)
	_commands.add_child(button)


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
	if stats.get("kind") == "upgrade":
		button.tooltip_text = "Research: %s\n%s\n%s\nApplies to: %s" % [stats.get("name", "?"),
				stats.get("function", ""), ", ".join(cost), stats.get("applies_to", "")]
	button.set_meta("tooltip", button.tooltip_text)
	button.set_meta("guid", guid)
	button.pressed.connect(action)
	var thumb: Thumbnail = null
	var inset := 0
	if guid == MapObject.FIELD_GUID:
		var sheet := GameData.load_sprite(FIELD_ICONS)
		if sheet and ICON_FIELD < sheet.frame_count():
			thumb = Thumbnail.new()
			thumb.set_meta("portrait", true)
			thumb.texture = _atlas(sheet, ICON_FIELD)
			thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif type_id >= 0:
		thumb = Thumbnail.portrait(guid)
		if thumb == null:
			thumb = Thumbnail.for_type(type_id, player.index)
			inset = 3
	else:
		thumb = Thumbnail.portrait(guid)  # the upgrade's own picture
	if thumb == null and type_id < 0:
		# Upgrades without a picture: a parchment card with the upgrade's name.
		var label := MenuStyle.label(stats.get("name", "?"), int(10 * ui_scale), Color("#3a2410"))
		label.add_theme_constant_override("outline_size", 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
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
		if int(button.get_meta("guid", -1)) < 0:
			continue
		var cost: Dictionary = GameData.stats(button.get_meta("guid")).get("cost", {}).duplicate()
		cost.erase("population")
		cost.erase("horses")
		var guid: int = button.get_meta("guid")
		var reason := _unavailable_reason(guid, cost)
		button.disabled = not reason.is_empty()
		button.tooltip_text = button.get_meta("tooltip") + ("\n" + reason if reason else "")
		button.modulate = Color(1, 1, 1, 0.55) if button.disabled else Color.WHITE
		# An upgrade being researched here shows its progress across the button.
		var building := selection.selected_building
		var researching: bool = GameData.stats(guid).get("kind") == "upgrade" and is_instance_valid(building) \
				and guid in building.queue
		var bar := button.get_node_or_null("Research") as ProgressBar
		if researching:
			if bar == null:
				bar = ProgressBar.new()
				bar.name = "Research"
				bar.show_percentage = true
				bar.max_value = 1.0
				bar.step = 0.0
				bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				bar.add_theme_stylebox_override("background", _flat(Color(0.1, 0.07, 0.04, 0.75)))
				bar.add_theme_stylebox_override("fill", _flat(Color(0.4, 0.7, 1.0, 0.9)))
				bar.add_theme_font_size_override("font_size", int(11 * ui_scale))
				bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
				bar.offset_top = -14 * ui_scale
				button.add_child(bar)
			bar.value = building.train_progress if building.queue[0] == guid else 0.0
			button.modulate = Color.WHITE
			button.tooltip_text = "%s\nResearching: %d%%" % [button.get_meta("tooltip"), int(bar.value * 100)]
		elif bar:
			bar.queue_free()


var _menu: Control


## The in-game menu (Esc): continue, restart, back to the main menu. Pauses the game.
func toggle_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
		get_tree().paused = false
		return
	get_tree().paused = true
	_menu = _menu_panel(GameData.menu_text(50, "Settings"), [
		[GameData.menu_text(57, "Continue"), toggle_menu],
		[GameData.menu_text(54, "Restart"), func() -> void:
			get_tree().paused = false
			get_tree().reload_current_scene()],
		["Main menu", _to_main_menu],
	])


func _to_main_menu() -> void:
	get_tree().paused = false
	Match.configured = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _menu_panel(title: String, entries: Array) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(shade)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.18, 0.1, 0.05, 0.95)
	box.border_color = Color(0.62, 0.43, 0.2)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(22 * ui_scale)
	panel.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(10 * ui_scale))
	var heading := MenuStyle.label(title, int(26 * ui_scale))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	for entry in entries:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(260, 36) * ui_scale
		MenuStyle.style(button, int(18 * ui_scale))
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
	panel.position = get_viewport().get_visible_rect().size / 2.0 - panel.get_combined_minimum_size() / 2.0
	return shade


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
	var back := Button.new()
	back.text = "Back to main menu"
	MenuStyle.style(back, int(20 * ui_scale))
	back.pressed.connect(_to_main_menu)
	_root.add_child(back)
	back.position = label.position + Vector2(label.get_minimum_size().x / 2.0 - 110 * ui_scale, label.get_minimum_size().y + 20)


## Why a build/train button is unavailable, or "" when it can be used.
func _unavailable_reason(guid: int, cost: Dictionary) -> String:
	if guid == MapObject.FIELD_GUID and MapObject.field_allowance(player.index) <= 0:
		var store := ""
		for food_store in MapObject.FOOD_STORES:
			if GameData.stats(food_store).get("faction") == player.faction:
				store = GameData.stats(food_store).get("name", "food store")
		return "Build a %s first (each allows %d fields)" % [store, MapObject.FIELDS_PER_STORE] if store \
				else "Needs a food store"
	var stats := GameData.stats(guid)
	if stats.get("kind") == "upgrade" and not player.can_research(guid):
		return "Already researched or in progress" if player.researched.has(guid) or player.is_researching(guid) \
				else "Research the previous level first"
	if stats.get("kind") == "unit":
		if guid in Player.COMMANDERS and player.has_commander():
			return "You can only have one %s" % stats.get("name", "commander").to_lower()
		if not player.has_room():
			var house := ""
			for other in GameData.stats_guids():
				var s2 := GameData.stats(other)
				if s2.get("faction") == player.faction and s2.get("kind") == "structure" \
						and int(s2.get("housing", 0)) > 0 and int(s2.get("housing", 0)) < 12:
					house = s2.get("name", "")
			return "Not enough housing (%d/%d)%s" % [player.population() + player.queued_units(),
					player.population_cap(), " — build a %s" % house if house else ""]
		var selected := selection.selected_building
		if is_instance_valid(selected) and selected.queue.size() >= MapObject.QUEUE_LIMIT:
			return "Queue full"
	var missing := PackedStringArray()
	# Fields are shared by every people; their requirement is the grain store checked above.
	for required in ([] if guid == MapObject.FIELD_GUID else GameData.prerequisites(guid)):
		if not player.has_building(required):
			missing.append(GameData.stats(required).get("name", "?"))
	if not missing.is_empty():
		return "Requires: " + ", ".join(missing)
	var short := PackedStringArray()
	for key in cost:
		if int(player.resources.get(key, 0)) < int(cost[key]):
			short.append(GameData.text(Player.RESOURCES[key].text, key) if Player.RESOURCES.has(key) else key)
	if not short.is_empty():
		return "Not enough " + ", ".join(short).to_lower()
	return ""
