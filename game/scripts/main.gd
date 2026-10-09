extends Node2D
## Development entry point: loads a map with the original terrain and spawns test units.
##
## Command line (after `--`):
##   --map=<file in Levels/ or absolute path>   default "[2 Players] - close combat.alf"
##   --biome=steppe|wiese
##   --screenshot=<png path>  save a frame after --frames=<n> (default 90) and quit
##   --camera=x,y  --zoom=z

const DEFAULT_MAP := "[2 Players] - close combat.alf"

var terrain := Terrain.new()
var units_root := Node2D.new()
var camera := RtsCamera.new()
var selection := SelectionController.new()


func _ready() -> void:
	if not GameData.is_ready():
		_show_message("Original game data not found.\nRun with --install-dir=<folder containing america0.rda>")
		return
	var map_arg := GameData.cmdline_option("map", DEFAULT_MAP)
	var map_path := map_arg if map_arg.is_absolute_path() else GameData.maps_dir().path_join(map_arg)
	var map := AlfMap.load_from_file(map_path)
	if map == null:
		_show_message("Could not load map %s" % map_path)
		return

	add_child(terrain)
	terrain.setup(map, GameData.cmdline_option("biome", "steppe"))
	units_root.y_sort_enabled = true
	add_child(units_root)
	selection.units_root = units_root
	add_child(selection)
	camera.bounds = Rect2(Vector2.ZERO, map.pixel_size())
	add_child(camera)
	camera.make_current()

	var size := Vector2(map.pixel_size())
	_spawn_squad("global/gfx/mex/infanterist", 1, size * Vector2(0.5, 0.86), 12)
	_spawn_squad("global/gfx/usa/infanterist", 2, size * Vector2(0.5, 0.14), 8)
	camera.position = _vector_option("camera", size * Vector2(0.5, 0.84))
	camera.set_zoom_level(GameData.cmdline_option("zoom", "1").to_float())
	DisplayServer.window_set_title("America — %s" % map.title)
	_setup_screenshot()


func _spawn_squad(directory: String, team: int, centre: Vector2, count: int) -> void:
	var unit_type := UnitType.load_type(directory)
	if unit_type == null:
		return
	var columns := ceili(sqrt(count))
	for i in count:
		var unit := Unit.new()
		unit.position = centre + Vector2((i % columns - columns / 2.0) * 30.0, (i / columns) * 28.0)
		units_root.add_child(unit)
		unit.setup(unit_type, team)
		unit.direction = 5 if team == 1 else 1


func _vector_option(name: String, default: Vector2) -> Vector2:
	var value := GameData.cmdline_option(name)
	if value.is_empty():
		return default
	var parts := value.split(",")
	return Vector2(parts[0].to_float(), parts[1].to_float())


func _setup_screenshot() -> void:
	var path := GameData.cmdline_option("screenshot")
	if path.is_empty():
		return
	camera.input_enabled = false
	# Exercise the move order so walking animations show up in the capture.
	selection._select(units_root.get_children().filter(func(u: Unit) -> bool: return u.team == 1), false)
	selection._order_move(camera.position + Vector2(-200, -120))
	for i in GameData.cmdline_option("frames", "90").to_int():
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _show_message(text: String) -> void:
	push_error(text)
	var label := Label.new()
	label.text = text
	label.position = Vector2(40, 40)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
