extends Node2D
## Development entry point: loads a map with the original terrain and spawns test units.
##
## Command line (after `--`):
##   --map=<file in Levels/ or absolute path>   default "[2 Players] - close combat.alf"
##   --biome=steppe|wiese
##   --screenshot=<png path>  save a frame after --frames=<n> (default 90) and quit
##   --scenario=battle  two infantry squads fighting in front of the camera
##   --scenario=food    women farm two fields at a finca, militiamen hunt
##   --scenario=economy player 1's workers gather the nearest wood and gold
##   --fog=off  disable the fog of war
##   --ai=off  no computer opponent (for isolated tests)
##   --ai-vs-ai=1  computer controls player 1 as well
##   --report-after=<frames>  print stockpiles every 300 frames, then quit (use --fixed-fps)
##   --camera=x,y  --zoom=z  --order=x,y (screenshot move target)  --debug-paths=1

const DEFAULT_MAP := "[2 Players] - close combat.alf"

var terrain := Terrain.new()
var units_root := Node2D.new()
var camera := RtsCamera.new()
var selection := SelectionController.new()
var nav := NavGrid.new()
var fog := FogOfWar.new()
var hud := Hud.new()
var build_controller := BuildController.new()
var ais: Array[AiPlayer] = []
var _game_over := false
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
	if GameData.cmdline_option("scenario") == "economy":
		var i := 0
		for node in units_root.get_children():
			if node is Unit and node.team == 1 and node.unit_type.can_gather("wood"):
				var unit: Unit = node
				var resource := "wood" if i % 2 == 0 else "gold"
				var source := unit._nearest_source(resource) if resource == "wood" else _nearest_mine(unit.position)
				unit.gather(source)
				i += 1
	if GameData.cmdline_option("scenario") == "food":
		_scenario_food.call_deferred()
	if GameData.cmdline_option("scenario") == "build":
		_scenario_build.call_deferred()
	var report := GameData.cmdline_option("report-after")
	if report != "":
		_report_after(report.to_int())
	if GameData.cmdline_option("scenario") == "battle":
		# Two infantry lines facing each other in front of the camera.
		var centre := camera.position
		_spawn_squad(FACTION_STARTS[1].army, 1, centre + Vector2(-60, 120), 9)
		_spawn_squad(FACTION_STARTS[2].army, 2, centre + Vector2(60, -160), 9)
	camera.set_zoom_level(GameData.cmdline_option("zoom", "1").to_float())
	fog.enabled = GameData.cmdline_option("fog", "on") != "off"
	add_child(fog)
	fog.setup(map, 1)
	build_controller.player = players[1]
	build_controller.selection = selection
	build_controller.objects_root = units_root
	add_child(build_controller)  # after the selection controller, so it sees clicks first
	build_controller.placed.connect(_on_building_placed)
	for object in MapObject.all_objects:
		if object.is_building():
			object.unit_trained.connect(_on_unit_trained)
	hud.build_controller = build_controller
	hud.biome = terrain.biome
	add_child(hud)
	hud.setup(map, terrain.overview_image(), camera, units_root, players[1], selection)
	hud.minimap.move_ordered.connect(selection._order_move)
	# Player 2 is computer controlled (player 1 too with --ai-vs-ai, for testing).
	for index in players:
		if GameData.cmdline_option("ai") == "off":
			break
		if index == 2 or GameData.cmdline_option("ai-vs-ai") != "":
			var ai := AiPlayer.new()
			ai.player = players[index]
			ai.units_root = units_root
			ai.biome = terrain.biome
			add_child(ai)
			ais.append(ai)
	var check := Timer.new()
	check.wait_time = 2.0
	check.autostart = true
	check.timeout.connect(_check_victory)
	add_child(check)
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
			if not object.setup(type, placement.owner, placement.amount):
				object.free()
				continue
			units_root.add_child(object)
		spawned += 1
	print("Placed %d/%d map objects in %d ms" % [spawned, map.placements.size(), Time.get_ticks_msec() - started])


## A player is out when they have no buildings and no units left.
func _check_victory() -> void:
	if _game_over:
		return
	var alive := {}
	for node in units_root.get_children():
		if (node is Unit and node.is_alive()) or (node is MapObject and node.is_building() and node.is_alive()):
			var owner: int = node.team if node is Unit else node.owner_index
			if owner > 0:
				alive[owner] = true
	var human_alive: bool = alive.has(1)
	var others_alive := alive.keys().any(func(k: int) -> bool: return k != 1)
	if human_alive and others_alive:
		return
	_game_over = true
	var won := human_alive
	print("GAME OVER: ", "player 1 wins" if won else "player 1 lost")
	Sound.play_mission_result(won)
	hud.show_banner(GameData.text(1 if won else 2, "Victory!" if won else "Defeat"))


func _on_building_placed(site: MapObject) -> void:
	site.unit_trained.connect(_on_unit_trained)


## A building finished training a unit: it steps out in front (below) of the footprint.
func _on_unit_trained(building: MapObject, unit_guid: int) -> void:
	var type_id := GameData.type_for_guid(unit_guid, terrain.biome)
	var type := ObjectTypes.get_type(type_id)
	if type == null:
		return
	var unit_type := UnitType.load_type(type.directory())
	if unit_type == null:
		return
	var rect := building.footprint_rect()
	var exit := Vector2(rect.get_center().x, rect.end.y + 12)
	var cell := nav.nearest_walkable(nav.cell_of(exit))
	var unit := Unit.new()
	unit.position = (Vector2(cell) + Vector2(0.5, 0.5)) * NavGrid.CELL
	units_root.add_child(unit)
	unit.setup(unit_type, building.owner_index)
	unit.move_to(unit.position + Vector2(randf_range(-40, 40), 50))


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
		var spot := centre + Vector2((i % columns - columns / 2.0) * 30.0, (i / columns) * 28.0)
		unit.position = (Vector2(nav.nearest_walkable(nav.cell_of(spot))) + Vector2(0.5, 0.5)) * NavGrid.CELL
		units_root.add_child(unit)
		unit.setup(unit_type, team)
		unit.direction = 5 if team == 1 else 1


## Workers build a house next to the HQ while the HQ trains two more workers.
func _scenario_build() -> void:
	var workers := units_root.get_children().filter(func(n: Node) -> bool:
		return n is Unit and n.team == 1 and n.unit_type.anim_index("build") >= 0)
	selection._select(workers, false)
	var house := GameData.type_for_guid(201, terrain.biome)
	build_controller.start(house)
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	for radius in range(200, 600, 32):
		var spot := hq.position + Vector2(radius, 0).rotated(radius * 0.7)
		spot = (spot / NavGrid.CELL).round() * NavGrid.CELL
		if build_controller.can_place(spot):
			build_controller._place(spot, false)
			print("house site at ", spot)
			break
	print("queued: ", hq.enqueue(252), hq.enqueue(252))


## A finca with two fields worked by three women, and two militiamen hunting.
func _scenario_food() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var ai := AiPlayer.new()
	ai.biome = terrain.biome
	var finca_type := ObjectTypes.get_type(GameData.type_for_guid(208, terrain.biome))
	var finca := MapObject.new()
	finca.position = ai._find_spot(finca_type, hq.position)
	finca.setup(finca_type, 1)
	units_root.add_child(finca)
	nav.block_footprint(finca_type, finca.position)
	ai.free()
	_spawn_squad("global/gfx/mex/frau", 1, finca.position + Vector2(0, 120), 3)
	_spawn_squad("global/gfx/mex/milizionaer", 1, hq.position + Vector2(0, 160), 2)
	var field_type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.FIELD_GUID, terrain.biome))
	var fields: Array[MapObject] = []
	for k in 2:
		var field := MapObject.new()
		field.position = finca.position + Vector2(-140 + k * 150, 170)
		field.setup(field_type, 1)
		units_root.add_child(field)
		fields.append(field)
	var i := 0
	for node in units_root.get_children():
		if node is Unit and node.team == 1:
			if node.unit_type.can_gather("food") and node.unit_type.anim_index("build") < 0:
				node.gather(fields[i % 2])
				i += 1
			elif node.unit_type.is_hunter():
				node.hunt(node._nearest_animal())
	print("food scenario: finca at %s, %d women farming" % [finca.position, i])


func _nearest_mine(from: Vector2) -> MapObject:
	var best: MapObject = null
	for object in MapObject.all_objects:
		if object.resource == "gold" and (best == null or from.distance_to(object.position) < from.distance_to(best.position)):
			best = object
	return best


func _report_after(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
		if i % (60 if GameData.cmdline_option("trace-workers") != "" else 300) == 0:
			_print_report(i)
	_print_report(frames)
	get_tree().quit()


func _print_report(frame: int) -> void:
	if GameData.cmdline_option("trace-workers") != "":
		for node in units_root.get_children():
			if node is Unit and node.team == 1 and node.unit_type.is_hunter():
				print("  hunter state=%d hunting=%s target=%s pos=%s carrying=%s" % [node.state, node.hunting, node.target, node.position.round(), node.carrying])
			if node is Unit and node.team == 1 and node.state == Unit.State.GATHERING:
				print("  worker phase=%d action=%s carrying='%s' inside=%s" % [node._gather_phase, node._action, node.carrying, node.inside])
	var alive := {}
	for node in units_root.get_children():
		if node is Unit and node.is_alive():
			alive[node.team] = alive.get(node.team, 0) + 1
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			print("  %s complete=%s progress=%.2f queue=%s" % [object.display_name(), object.complete, object.build_progress, object.queue])
		elif object.is_field() and object.owner_index == 1:
			print("  field state=%d progress=%.2f amount=%d" % [object.field_state, object.field_progress, object.amount])
	for index in players:
		print("frame %d player %d: %s units=%d" % [frame, index, players[index].resources, alive.get(index, 0)])


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
	Unit.debug_paths = GameData.cmdline_option("debug-paths") != ""
	if GameData.cmdline_option("scenario") == "":
		# Exercise the move order so walking animations show up in the capture.
		selection._select(units_root.get_children().filter(func(u: Node) -> bool: return u is Unit and u.team == 1), false)
		selection._order_move(_vector_option("order", camera.position + Vector2(-200, -120)))
	for i in GameData.cmdline_option("frames", "90").to_int():
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## --selftest=1: decode all sounds and maps, print a summary and quit.
func _selftest() -> void:
	if GameData.cmdline_option("selftest") == "audio":
		Sound.play_music("mex")
		Sound.play_sound(198)  # "landarbeiter anklicken"
		for i in 90:
			await get_tree().process_frame
			if i % 15 == 0:
				print("music playing=%s stream=%s peak L=%.1f dB" % [Sound._music.playing, Sound._music.stream,
						AudioServer.get_bus_peak_volume_left_db(0, 0)])
		get_tree().quit()
		return
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
