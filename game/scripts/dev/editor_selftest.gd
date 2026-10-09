class_name EditorSelftest
extends Node
## --editor-selftest=1: builds a small map in the editor (a lake, a forest, a path, start
## points, units, a building, a mine), saves it, reads it back and prints what it finds,
## then quits (tools/check_scenarios.py "editor"). With --editor-shot=<png> it captures
## the editor first; --editor-keep=1 keeps the saved map.

var editor: MapEditor


static func run(map_editor: MapEditor) -> void:
	var test := EditorSelftest.new()
	test.editor = map_editor
	map_editor.add_child(test)
	test._run.call_deferred()


func _run() -> void:
	editor.new_map("Selftest", 64, 64, "steppe", 2)
	if editor.painter == null:
		print("editor: no terrain rules (expansion missing)")
		get_tree().quit()
		return
	var centre := Vector2(editor.map.pixel_size()) / 2.0
	editor.set_brush(5)
	editor.paint(centre, 11)  # deep water: shallow water, shore and stone grow round it
	editor.set_brush(3)
	editor.paint(Vector2(420, 1560), 16)
	for x in range(300, 1700, 40):
		editor.set_brush(1)
		editor.paint(Vector2(x, 400 + x * 0.1), 5)
	var rings := {}
	for r in [0.0, 200.0, 260.0, 320.0, 380.0, 440.0]:
		rings[int(r)] = editor.rules.material_name(editor.painter.material_at(centre + Vector2(r, 0)))
	print("editor: lake from the centre out %s" % [rings.values()])
	print("editor: blocks without a piece %d, drawn with a corner left out %d" % _unmatched())
	var mex: Dictionary = Main.FACTIONS.mex
	editor.place_start(1, Vector2(400, 400))
	editor.place_start(2, Vector2(1600, 1600))
	for i in 4:
		editor.place(GameData.type_for_guid(mex.army), Vector2(500 + i * 30, 520), 1)
	editor.place(GameData.type_for_guid(mex.main, "steppe"), Vector2(1500, 520), 1)
	editor.place(GameData.type_for_guid(Main.FACTIONS.usa.army), Vector2(700, 600), 2)
	editor.place(MapEditor._type_named("Mine_ul_St"), Vector2(1600, 300), 0)
	editor.place(MapEditor._type_named("Tier_Büffel"), Vector2(900, 1500), 0)
	if not editor.save():
		print("editor: save failed")
		get_tree().quit()
		return
	var path := editor.map_path
	var back := AlfMap.load_from_file(path)
	var same_tiles := back != null and back.tile_ids == editor.map.tile_ids and back.tile_codes == editor.map.tile_codes
	var water := 0
	for value in back.grid_flags:
		if value & NavGrid.WATER:
			water += 1
	print("editor: saved %s, read back: tiles %s, %d placements, %d water cells, title %s" % [
			path.get_file(), "same" if same_tiles else "DIFFERENT", back.placements.size(), water, back.title])
	var again := TerrainPainter.new(editor.rules, back)
	again.read_map()
	var differ := 0
	for i in again.points.size():
		if again.points[i] != TerrainRules.UNKNOWN and again.points[i] != editor.painter.points[i]:
			differ += 1
	print("editor: lattice read back, %d points differ" % differ)
	_compare_original("[4 Players] - riverside.alf")
	var shot := GameData.cmdline_option("editor-shot")
	if not shot.is_empty():
		var look := GameData.cmdline_option("editor-camera")
		editor.camera.position = centre if look.is_empty() else Vector2(look.get_slice(",", 0).to_float(), look.get_slice(",", 1).to_float())
		editor.camera.set_zoom_level(GameData.cmdline_option("zoom", "0.5").to_float())
		if GameData.cmdline_option("editor-page") != "":
			editor.ui.show_page(GameData.cmdline_option("editor-page"))
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
	await _try_input()
	if GameData.cmdline_option("editor-keep").is_empty():
		DirAccess.remove_absolute(path)
	get_tree().quit()


## Drive the editor through real input events: a brush stroke, a right click on a unit
## and Ctrl+Z.
func _try_input() -> void:
	editor.ui.show_page("Terrain")
	editor.ui.root.visible = false  # a headless viewport is 64 px: the panels would take every click
	editor.paint_material = 6
	editor.set_brush(2)
	var target := Vector2(1500, 1300)
	editor.camera.position = target
	editor.camera.set_zoom_level(1.0)
	for i in 5:
		await get_tree().process_frame
	var screen := editor.get_viewport().get_canvas_transform() * target
	_mouse(screen, MOUSE_BUTTON_LEFT, true)
	var motion := InputEventMouseMotion.new()
	motion.position = screen + Vector2(60, 0)
	Input.parse_input_event(motion)
	_mouse(screen + Vector2(60, 0), MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var painted := editor.rules.material_name(editor.painter.material_at(target))
	var before := editor.map.placements.size()
	var unit_at: Vector2 = editor.map.placements[2].position
	editor.camera.position = unit_at
	for i in 5:
		await get_tree().process_frame
	_mouse(editor.get_viewport().get_canvas_transform() * unit_at, MOUSE_BUTTON_RIGHT, true)
	_mouse(editor.get_viewport().get_canvas_transform() * unit_at, MOUSE_BUTTON_RIGHT, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var removed := before - editor.map.placements.size()
	var key := InputEventKey.new()
	key.keycode = KEY_Z
	key.ctrl_pressed = true
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	print("editor: input: stroke painted %s, right click removed %d, undo back to %d placements" % [
			painted, removed, editor.map.placements.size()])


func _mouse(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


## Blocks whose points do not form a blending pair (an error), and blocks whose pattern
## is drawn with a lone corner left to the neighbouring block (normal).
func _unmatched() -> Array:
	var broken := 0
	var corners := 0
	for block in editor.painter.all_blocks():
		var mats: Array[int] = []
		for point in editor.painter._corners(block):
			mats.append(editor.painter._get_point(point) if editor.painter._valid(point) else TerrainRules.UNKNOWN)
		var pair := editor.painter._pair_of(mats)
		if pair.x < 0:
			broken += 1
			continue
		if pair.y < 0:
			continue
		var pattern := ""
		for m in mats:
			pattern += "B" if m == pair.y else "A"
		if editor.painter._drawable(pattern) != pattern:
			corners += 1
	return [broken, corners]


## Read an original map into the lattice and draw every block again: how many come out
## with the shape the original editor gave them (the rest are cliffs and other pieces the
## painter does not know).
func _compare_original(file: String) -> void:
	var original := AlfMap.load_from_file(GameData.maps_dir().path_join(file))
	if original == null:
		return
	var painter := TerrainPainter.new(TerrainRules.for_biome(original.guess_biome()), original)
	painter.read_map()
	var codes := original.tile_codes.duplicate()
	var known := 0
	var same := 0
	for block in painter.all_blocks():
		var cell := painter._first_cell(block)
		if cell.x < 0 or not painter.rules.tile_shape.has(original.tile_ids[cell.y * original.columns + cell.x]):
			continue
		known += 1
		painter._render(block)
		if original.tile_codes[cell.y * original.columns + cell.x] == codes[cell.y * original.columns + cell.x]:
			same += 1
	print("editor: %s redrawn, %d of %d known blocks keep their shape" % [file, same, known])
