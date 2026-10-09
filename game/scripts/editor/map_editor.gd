class_name MapEditor
extends Node2D
## The map builder: paints terrain with the expansion level editor's rules (TerrainPainter),
## places nature, buildings, units and start points, saves expansion-format maps (.ulf) to
## the maps folder (GameData.custom_maps_dir) and starts a test game on the map at once.
## A player given units or buildings of their own starts with exactly those (see Main), so
## a few units on an empty map make a quick test bench.
##
## Mouse: left paints or places, right removes the object under the cursor, middle drags
## the view, wheel zooms. Keys: Ctrl+Z undo, Ctrl+S save, F5 test, [ and ] brush size.
##
## Command line (after `--`): --editor[=<map file>]  open the editor (on a map)
##   --editor-selftest=1  build, save and reload a small map, print the results and quit
##   --editor-shot=<png>  capture the editor after --editor-selftest's steps and quit

signal changed  ## the map, the tool or the selection changed (the interface refreshes)
signal map_opened  ## a different map (possibly another landscape) is being edited

enum Tool { TERRAIN, PLACE, START, ERASE }

const SIZES := [64, 96, 128, 192, 256, 320, 384]
const DEFAULT_FILL := 2
const MINE_GOLD := 5000
const UNDO_LIMIT := 30
const START_NAME := "Editor_Start"
const PICK_RADIUS := 36.0

var map: AlfMap
var map_path := ""  ## the file this map was opened from or saved to
var biome := "steppe"
var rules: TerrainRules  ## null without the expansion: then terrain cannot be painted
var painter: TerrainPainter
var terrain: Terrain
var camera := RtsCamera.new()
var pieces := Node2D.new()  ## previews of the placements, in the same order
var overlay := EditorOverlay.new()
var ui: EditorUi

var tool := Tool.TERRAIN
var paint_material := 9
var brush := 2  ## radius in steps of 32 px
var place_type := -1
var player := 1  ## whose buildings, units and start point the tools place
var mine_gold := MINE_GOLD
## Per player (index 0 = player 1) for test games: people and whether the computer plays it.
var factions: Array = ["mex", "usa", "ind", "des", "mex", "usa", "ind", "des"]
var computer: Array = [false, true, true, true, true, true, true, true]
var dirty := false

var _undo: Array = []
var _painting := false
var _last_paint := Vector2.INF
var _start_type := -1


func _ready() -> void:
	if not GameData.is_ready():
		return
	_start_type = _type_named(START_NAME)
	pieces.y_sort_enabled = true
	add_child(pieces)
	add_child(overlay)
	overlay.editor = self
	camera.min_zoom = 0.3
	add_child(camera)
	camera.make_current()
	ui = EditorUi.new()
	ui.editor = self
	add_child(ui)
	if not Match.editor_state.is_empty():
		_restore_settings(Match.editor_state)
	var reopen := Match.editor_map
	Match.editor_map = ""
	var option := GameData.cmdline_option("editor")
	if not reopen.is_empty() and FileAccess.file_exists(reopen):
		open_file(reopen)
	elif option.get_extension().to_lower() in ["alf", "ulf"]:
		open_file(option if option.is_absolute_path() else GameData.maps_dir().path_join(option))
	else:
		new_map("New map", 128, 128, "steppe", DEFAULT_FILL)
	if GameData.cmdline_option("editor-selftest") != "":
		EditorSelftest.run(self)


# ------------------------------------------------------------------ maps

func new_map(title: String, columns: int, rows: int, biome_name: String, fill: int) -> void:
	var fresh := AlfMap.create(title, columns, rows)
	biome = biome_name
	_use(fresh, "")
	if painter:
		painter.fill(fill)
		painter.write_flags()
	_build_terrain()
	camera.position = Vector2(map.pixel_size()) / 2.0


func open_file(path: String) -> bool:
	var loaded := AlfMap.load_from_file(path)
	if loaded == null:
		ui.notify("Could not open %s" % path.get_file())
		return false
	if loaded.title.is_empty():
		loaded.title = path.get_file().get_basename().get_slice("] - ", 1).capitalize()
	biome = loaded.guess_biome()
	_use(loaded, path)
	if painter:
		painter.read_map()
	_build_terrain()
	camera.position = _start_of(1, Vector2(map.pixel_size()) / 2.0)
	return true


func _use(alf: AlfMap, path: String) -> void:
	map = alf
	map_path = path
	rules = TerrainRules.for_biome(biome)
	painter = TerrainPainter.new(rules, map) if rules else null
	if rules and paint_material not in TerrainRules.PAINTABLE:
		paint_material = 9
	_undo.clear()
	dirty = false
	_rebuild_pieces()
	camera.bounds = Rect2(Vector2.ZERO, map.pixel_size())


func _build_terrain() -> void:
	if terrain:
		terrain.queue_free()
	terrain = Terrain.new()
	add_child(terrain)
	move_child(terrain, 0)
	terrain.setup(map, biome)
	map_opened.emit()
	changed.emit()


## The maps folder file for this map: "[N Players] - title.ulf" (the menu reads the
## number of players from the name).
func file_name() -> String:
	var title := map.title.strip_edges()
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "[", "]"]:
		title = title.replace(bad, "")
	if title.is_empty():
		title = "Untitled"
	return "[%d Players] - %s.ulf" % [maxi(1, player_count()), title.to_lower()]


func save() -> bool:
	if painter:
		painter.write_flags()
	var dir := GameData.custom_maps_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name())
	if not map.save(path):
		ui.notify("Could not save to %s" % path)
		return false
	# Renamed (title or number of players changed): drop the editor's previous file.
	if map_path != path and map_path.get_base_dir() == dir and FileAccess.file_exists(map_path):
		DirAccess.remove_absolute(map_path)
	map_path = path
	dirty = false
	ui.notify("Saved %s" % path.get_file())
	changed.emit()
	return true


## Save and play the map: every player with a start point or objects of their own takes
## part (at least player 1), as set on the Players page.
func test() -> void:
	if not save():
		return
	var slots: Array[Dictionary] = []
	for i in maxi(1, player_count()):
		slots.append({"faction": factions[i], "ai": computer[i] and i > 0})
	Match.setup(map_path, slots)
	Match.supply = 0
	Match.editor_map = map_path
	Match.editor_state = _settings()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _settings() -> Dictionary:
	return {"factions": factions.duplicate(), "computer": computer.duplicate(), "paint_material": paint_material,
			"brush": brush, "player": player, "camera": camera.position, "zoom": camera.zoom}


func _restore_settings(state: Dictionary) -> void:
	factions = state.get("factions", factions)
	computer = state.get("computer", computer)
	paint_material = state.get("paint_material", paint_material)
	brush = state.get("brush", brush)
	player = state.get("player", player)


## The highest player number with a start point or objects of their own.
func player_count() -> int:
	var count := 0
	for p in map.placements:
		if p.owner > 0 and p.owner < 9:
			count = maxi(count, p.owner)
	return count


# ------------------------------------------------------------------ editing

func _unhandled_input(event: InputEvent) -> void:
	if map == null or ui.modal_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Z when event.ctrl_pressed:
				undo()
			KEY_S when event.ctrl_pressed:
				save()
			KEY_F5:
				test()
			KEY_BRACKETLEFT:
				set_brush(brush - 1)
			KEY_BRACKETRIGHT:
				set_brush(brush + 1)
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var at: Vector2 = make_input_local(event).position
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(at)
			else:
				_painting = false
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_push_undo()
			if not remove_at(at):
				_undo.pop_back()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		overlay.queue_redraw()
		if _painting:
			_drag(make_input_local(event).position)


func _press(at: Vector2) -> void:
	if not Rect2(Vector2.ZERO, map.pixel_size()).has_point(at):
		return
	_push_undo()
	match tool:
		Tool.TERRAIN:
			_painting = true
			_last_paint = Vector2.INF
			_drag(at)
		Tool.ERASE:
			_painting = true
			_drag(at)
		Tool.PLACE:
			if place_type >= 0:
				place(place_type, at, player)
		Tool.START:
			place_start(player, at)


func _drag(at: Vector2) -> void:
	if tool == Tool.ERASE:
		remove_at(at)
		return
	if tool != Tool.TERRAIN or painter == null:
		return
	if _last_paint != Vector2.INF and _last_paint.distance_to(at) < brush_radius() * 0.4:
		return
	_last_paint = at
	paint(at, paint_material)


func brush_radius() -> float:
	return brush * 32.0


func set_brush(value: int) -> void:
	brush = clampi(value, 1, 12)
	overlay.queue_redraw()
	changed.emit()


func paint(at: Vector2, with_material: int) -> void:
	var rect := painter.paint(at, brush_radius(), with_material)
	if rect.size != Vector2i.ZERO:
		terrain.refresh_cells(rect)
		dirty = true


func place(type_id: int, at: Vector2, who: int) -> void:
	var type := ObjectTypes.get_type(type_id)
	if type == null:
		return
	var p := AlfMap.Placement.new()
	p.position = at.round()
	p.type_id = type_id
	p.owner = who if type.kind != ObjectTypes.Kind.ELEMENT or _is_animal(type) else 0
	if type.name.begins_with("Mine"):
		p.amount = mine_gold
	map.placements.append(p)
	pieces.add_child(_make_piece(p))
	dirty = true
	changed.emit()


## One start point per player: placing it again moves it.
func place_start(who: int, at: Vector2) -> void:
	for i in map.placements.size():
		var p: AlfMap.Placement = map.placements[i]
		if p.type_id == _start_type and p.owner == who:
			p.position = at.round()
			pieces.get_child(i).position = p.position
			dirty = true
			changed.emit()
			return
	place(_start_type, at, who)


## Remove the placement nearest to `at` (within reach); false when there is none.
func remove_at(at: Vector2) -> bool:
	var best := -1
	var best_distance := INF
	for i in map.placements.size():
		var d: float = map.placements[i].position.distance_to(at)
		var type := ObjectTypes.get_type(map.placements[i].type_id)
		var reach := PICK_RADIUS
		if type and type.kind == ObjectTypes.Kind.BUILDING:
			reach = maxf(reach, type.footprint_size.length() * 0.4)
		if d < reach and d < best_distance:
			best = i
			best_distance = d
	if best < 0:
		return false
	map.placements.remove_at(best)
	pieces.get_child(best).free()
	dirty = true
	changed.emit()
	return true


func undo() -> void:
	if _undo.is_empty():
		ui.notify("Nothing to undo")
		return
	var state: Dictionary = _undo.pop_back()
	if painter:
		painter.points = state.points
	map.tile_ids = state.tiles
	map.tile_codes = state.codes
	map.placements.assign(state.placements)
	_rebuild_pieces()
	terrain.refresh_cells(Rect2i(0, 0, map.columns, map.rows))
	dirty = true
	changed.emit()


func _push_undo() -> void:
	var copies: Array[AlfMap.Placement] = []
	for p in map.placements:
		var copy := AlfMap.Placement.new()
		copy.position = p.position
		copy.type_id = p.type_id
		copy.owner = p.owner
		copy.amount = p.amount
		copy.content = p.content
		copies.append(copy)
	_undo.append({"points": painter.points.duplicate() if painter else PackedByteArray(),
			"tiles": map.tile_ids.duplicate(), "codes": map.tile_codes.duplicate(), "placements": copies})
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


# ------------------------------------------------------------------ previews

func _rebuild_pieces() -> void:
	for child in pieces.get_children():
		child.free()
	for p in map.placements:
		pieces.add_child(_make_piece(p))


## What a placement looks like: the object or unit itself, or a flag for a start point.
func _make_piece(p: AlfMap.Placement) -> Node2D:
	var type := ObjectTypes.get_type(p.type_id)
	var piece: Node2D = null
	if type and p.type_id != _start_type and not type.bob_path.is_empty():
		if type.kind == ObjectTypes.Kind.UNIT:
			var unit_type := UnitType.load_type(type.directory(), type.name.contains("Pferd"), type.id)
			if unit_type:
				var sprite := UnitSprite.new()
				sprite._setup_sprites(unit_type, p.owner)
				sprite.play("idle")
				piece = sprite
		else:
			var object := MapObject.new()
			object.is_ghost = true
			if object.setup(type, p.owner, p.amount):
				piece = object
			else:
				object.free()
	if piece == null:
		var flag := StartFlag.new()
		flag.player = p.owner
		piece = flag
	piece.position = p.position
	return piece


## Preview of what the place tool would put down (follows the mouse).
func make_ghost(type_id: int, who: int) -> Node2D:
	var p := AlfMap.Placement.new()
	p.type_id = type_id
	p.owner = who
	var ghost := _make_piece(p)
	ghost.modulate = Color(1, 1, 1, 0.6)
	return ghost


func _start_of(who: int, fallback: Vector2) -> Vector2:
	for p in map.placements:
		if p.type_id == _start_type and p.owner == who:
			return p.position
	return fallback


func start_type() -> int:
	return _start_type


static func _is_animal(type: ObjectTypes.ObjectType) -> bool:
	return type.name.begins_with("Tier_")


static func _type_named(name: String) -> int:
	for id in ObjectTypes.count():
		var type := ObjectTypes.get_type(id)
		if type and type.name == name:
			return id
	return -1


## A start point marker: a pole with a flag in the player's colour and their number.
class StartFlag:
	extends Node2D

	var player := 1

	func _draw() -> void:
		var colour: Color = Player.TEAM_COLORS[player] if player < Player.TEAM_COLORS.size() else Color.WHITE
		draw_circle(Vector2.ZERO, 26.0, Color(colour, 0.25))
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 32, colour, 2.0)
		draw_line(Vector2.ZERO, Vector2(0, -44), Color(0.25, 0.16, 0.08), 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(1, -44), Vector2(26, -37), Vector2(1, -30)]), colour)
		draw_string(MenuStyle.font(), Vector2(-5, 7), str(player), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


## The brush outline and the place tool's ghost under the mouse.
class EditorOverlay:
	extends Node2D

	var editor: MapEditor
	var _ghost: Node2D
	var _ghost_key := ""

	func _ready() -> void:
		z_index = 10

	func _process(_delta: float) -> void:
		var key := ""
		if editor.tool == MapEditor.Tool.PLACE and editor.place_type >= 0:
			key = "%d/%d" % [editor.place_type, editor.player]
		elif editor.tool == MapEditor.Tool.START:
			key = "%d/%d" % [editor.start_type(), editor.player]
		if key != _ghost_key:
			_ghost_key = key
			if _ghost:
				_ghost.queue_free()
				_ghost = null
			if not key.is_empty():
				var type_id := editor.place_type if editor.tool == MapEditor.Tool.PLACE else editor.start_type()
				_ghost = editor.make_ghost(type_id, editor.player)
				add_child(_ghost)
		if _ghost:
			_ghost.position = get_global_mouse_position().round()
			_ghost.visible = not editor.ui.mouse_over_ui()

	func _draw() -> void:
		if editor.map == null or editor.ui.mouse_over_ui():
			return
		var at := get_global_mouse_position()
		if editor.tool == MapEditor.Tool.TERRAIN:
			draw_arc(at, editor.brush_radius(), 0.0, TAU, 48, Color(1, 0.95, 0.7, 0.9), 2.0 / editor.camera.zoom.x)
		elif editor.tool == MapEditor.Tool.ERASE:
			draw_arc(at, MapEditor.PICK_RADIUS, 0.0, TAU, 32, Color(1, 0.4, 0.3, 0.9), 2.0 / editor.camera.zoom.x)
