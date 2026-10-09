extends Node2D
## Development entry point: loads a map with the original terrain and spawns test units.
##
## Command line (after `--`):
##   --map=<file in Levels/ or absolute path>   default "[2 Players] - close combat.alf"
##   --biome=steppe|wiese
##   --screenshot=<png path>  save a frame after --frames=<n> (default 90) and quit
##   --camera=x,y  --zoom=z  --order=x,y (screenshot move target)  --debug-paths=1

const DEFAULT_MAP := "[2 Players] - close combat.alf"

var terrain := Terrain.new()
var units_root := Node2D.new()
var camera := RtsCamera.new()
var selection := SelectionController.new()
var nav := NavGrid.new()
var hud := Hud.new()
var players := {}
var start_positions := {}  # player -> Vector2, from the map's Editor_Start markers

## Starting setup per player for this test scene: HQ object type and worker unit folder.
const FACTION_STARTS := {
	1: {"hq": 3, "workers": "global/gfx/mex/landarbeiter", "army": "global/gfx/mex/infanterist"},
	2: {"hq": 2, "workers": "global/gfx/usa/siedler", "army": "global/gfx/usa/infanterist"},
}


func _ready() -> void:
	if not GameData.is_ready():
		_show_message("Original game data not found.\nRun with --install-dir=<folder containing america0.rda>")
		return
	if GameData.cmdline_option("selftest") != "":
		_selftest()
		return
	var map_arg := GameData.cmdline_option("map", DEFAULT_MAP)
	var map_path := map_arg if map_arg.is_absolute_path() else GameData.maps_dir().path_join(map_arg)
	var map := AlfMap.load_from_file(map_path)
	if map == null:
		_show_message("Could not load map %s" % map_path)
		return

	add_child(terrain)
	terrain.setup(map, GameData.cmdline_option("biome", map.guess_biome()))
	units_root.y_sort_enabled = true
	add_child(units_root)
	nav.setup(map)
	_spawn_placements(map)
	selection.units_root = units_root
	add_child(selection)
	camera.bounds = Rect2(Vector2.ZERO, map.pixel_size())
	add_child(camera)
	camera.make_current()

	var size := Vector2(map.pixel_size())
	players[1] = Player.new(1, "mex")
	players[2] = Player.new(2, "usa")
	for player in FACTION_STARTS:
		_setup_player(player, start_positions.get(player, size * Vector2(0.5, 0.15 if player == 2 else 0.85)))
	camera.position = _vector_option("camera", start_positions.get(1, size / 2.0))
	camera.set_zoom_level(GameData.cmdline_option("zoom", "1").to_float())
	add_child(hud)
	hud.setup(map, terrain.overview_image(), camera, units_root, players[1], selection)
	hud.minimap.move_ordered.connect(selection._order_move)
	Sound.play_music(players[1].faction)
	DisplayServer.window_set_title("America — %s" % map.title)
	_setup_screenshot()


func _spawn_placements(map: AlfMap) -> void:
	var started := Time.get_ticks_msec()
	var spawned := 0
	for placement in map.placements:
		var type := ObjectTypes.get_type(placement.type_id)
		if type and type.name == "Editor_Start":
			start_positions[placement.owner] = placement.position
			continue
		if type == null or type.bob_path.is_empty() or type.bob_path.begins_with("editor"):
			continue
		if type.kind == ObjectTypes.Kind.UNIT:
			var unit_type := UnitType.load_type(type.directory())
			if unit_type == null:
				continue
			var unit := Unit.new()
			unit.position = placement.position
			units_root.add_child(unit)
			unit.setup(unit_type, placement.owner)
		else:
			var object := MapObject.new()
			object.position = placement.position
			object.amount = placement.amount
			if not object.setup(type, placement.owner):
				object.free()
				continue
			units_root.add_child(object)
		spawned += 1
	print("Placed %d/%d map objects in %d ms" % [spawned, map.placements.size(), Time.get_ticks_msec() - started])


func _setup_player(player: int, start: Vector2) -> void:
	var setup: Dictionary = FACTION_STARTS[player]
	var hq := MapObject.new()
	hq.position = start
	if hq.setup(ObjectTypes.get_type(setup.hq), player):
		units_root.add_child(hq)
		nav.block_footprint(ObjectTypes.get_type(setup.hq), start)
	else:
		hq.free()
	# Workers gather in front of the HQ, the army a little further out towards the map centre.
	var toward_centre := (Vector2(terrain.map.pixel_size()) / 2.0 - start).normalized()
	_spawn_squad(setup.workers, player, start + toward_centre * 220.0, 5)
	_spawn_squad(setup.army, player, start + toward_centre * 380.0, 9)


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
	selection._select(units_root.get_children().filter(func(u: Node) -> bool: return u is Unit and u.team == 1), false)
	Unit.debug_paths = GameData.cmdline_option("debug-paths") != ""
	selection._order_move(_vector_option("order", camera.position + Vector2(-200, -120)))
	for i in GameData.cmdline_option("frames", "90").to_int():
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## --selftest=1: decode all sounds and maps, print a summary and quit.
func _selftest() -> void:
	var result := Sound.verify_all()
	print("sounds: %d ok, %d failed %s" % [result[0], result[1].size(), result[1]])
	var maps := 0
	var bad := PackedStringArray()
	for file in DirAccess.get_files_at(GameData.maps_dir()):
		var map := AlfMap.load_from_file(GameData.maps_dir().path_join(file))
		if map and map.columns > 0 and map.grid_size != Vector2i.ZERO:
			maps += 1
		else:
			bad.append(file)
	print("maps: %d ok, %d failed %s" % [maps, bad.size(), bad])
	print("object types: %d" % ObjectTypes.count())
	get_tree().quit()


func _show_message(text: String) -> void:
	push_error(text)
	var label := Label.new()
	label.text = text
	label.position = Vector2(40, 40)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
