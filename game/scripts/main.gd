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
##   --faction=ind|mex|des|usa  your people (default mex); --enemy=... the computer's (default usa)
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

## Main building and a representative soldier per people (for --scenario=battle).
const FACTIONS := {
	"ind": {"main": 100, "army": 160, "commander": 151},
	"mex": {"main": 200, "army": 258, "commander": 251},
	"des": {"main": 300, "army": 356, "commander": 351},
	"usa": {"main": 400, "army": 458, "commander": 451},
}
const START_BUILDERS := 5
const START_FARMERS := 3


func _ready() -> void:
	if not GameData.is_ready():
		_show_message("Original game data not found.\nRun with --install-dir=<folder containing america0.rda>")
		return
	if GameData.cmdline_option("selftest") != "":
		_selftest()
		return
	var map_arg := GameData.cmdline_option("map", DEFAULT_MAP)
	var map_path := map_arg
	if Match.configured:
		map_path = Match.map_path
	elif not map_arg.is_absolute_path():
		map_path = GameData.maps_dir().path_join(map_arg)
		for candidate in GameData.map_files():
			if candidate.get_file() == map_arg:
				map_path = candidate
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
	Player.by_index.clear()
	var computer := {}  # player index -> true when AI controlled
	if Match.configured:
		for i in Match.players.size():
			players[i + 1] = Player.new(i + 1, Match.players[i].faction)
			computer[i + 1] = Match.players[i].ai
	else:
		players[1] = Player.new(1, _faction_option("faction", "mex"))
		players[2] = Player.new(2, _faction_option("enemy", "usa"))
		computer[2] = GameData.cmdline_option("ai") != "off"
		computer[1] = GameData.cmdline_option("ai-vs-ai") != ""
	for player in players:
		_setup_player(player, start_positions.get(player, _fallback_start(player, size)))
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
	if GameData.cmdline_option("scenario") == "menus":
		_scenario_menus.call_deferred()
	if GameData.cmdline_option("scenario") == "help-build":
		_scenario_help_build.call_deferred()
	var report := GameData.cmdline_option("report-after")
	if report != "":
		_report_after(report.to_int())
	if GameData.cmdline_option("scenario") == "battle":
		# Two infantry lines facing each other in front of the camera.
		var centre := camera.position
		_spawn_squad(_unit_dir(FACTIONS[players[1].faction].army), 1, centre + Vector2(-60, 120), 9)
		_spawn_squad(_unit_dir(FACTIONS[players[2].faction].army), 2, centre + Vector2(60, -160), 9)
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
	for index in players:
		if computer.get(index, false):
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
	_grow_forests(map)


## Plant the map's painted forests (see ForestGenerator).
func _grow_forests(map: AlfMap) -> void:
	var started := Time.get_ticks_msec()
	var avoid: Array[Vector2] = []
	for object in MapObject.all_objects:
		if object.resource != "wood":
			avoid.append(object.position)
	var trees := ForestGenerator.generate(map, terrain.biome, avoid, start_positions.values())
	for tree in trees:
		var type := ObjectTypes.get_type(tree.type_id)
		var object := MapObject.new()
		object.position = tree.position
		if not object.setup(type, 0):
			object.free()
			continue
		object.amount = tree.wood
		units_root.add_child(object)
		nav.block_footprint(type, tree.position)
	print("Grew %d forest trees in %d ms" % [trees.size(), Time.get_ticks_msec() - started])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not event.echo:
		hud.toggle_menu()
		get_viewport().set_input_as_handled()


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


## Start point when the map has no Editor_Start for a player: spread around the map.
func _fallback_start(player: int, size: Vector2) -> Vector2:
	var angle := TAU * float(player - 1) / 8.0 + PI / 2.0
	return size / 2.0 + Vector2(cos(angle), sin(angle)) * size * 0.38


func _faction_option(name: String, default: String) -> String:
	var value := GameData.cmdline_option(name, default)
	return value if FACTIONS.has(value) else default


## Unit folder for a GUID (units look the same in both biomes).
func _unit_dir(guid: int) -> String:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, terrain.biome))
	return type.directory() if type else ""


## The people's main building at the start point, with builders and farmers in front of it.
func _setup_player(player: int, start: Vector2) -> void:
	var main_guid: int = FACTIONS[players[player].faction].main
	var main_type := ObjectTypes.get_type(GameData.type_for_guid(main_guid, terrain.biome))
	var hq := MapObject.new()
	hq.position = start
	if hq.setup(main_type, player):
		units_root.add_child(hq)
		nav.block_footprint(main_type, start)
	else:
		hq.free()
		return
	var toward_centre := (Vector2(terrain.map.pixel_size()) / 2.0 - start).normalized()
	var builder := ""
	var farmer := ""
	for guid in hq.trainable_units():
		var unit_type := UnitType.load_type(_unit_dir(guid))
		if unit_type == null:
			continue
		if builder.is_empty() and unit_type.can_gather("wood") and unit_type.anim_index("build") >= 0:
			builder = _unit_dir(guid)
		elif farmer.is_empty() and unit_type.is_farmer():
			farmer = _unit_dir(guid)
	if not builder.is_empty():
		_spawn_squad(builder, player, start + toward_centre * 220.0, START_BUILDERS)
	if not farmer.is_empty():
		_spawn_squad(farmer, player, start + toward_centre * 220.0 + toward_centre.orthogonal() * 120.0, START_FARMERS)
	# Every people starts with its commander on horseback.
	var commander_dir := _unit_dir(FACTIONS[players[player].faction].commander)
	var commander_type := UnitType.load_type(commander_dir, true) if commander_dir else null
	if commander_type:
		var commander := Unit.new()
		var spot := start + toward_centre * 300.0 - toward_centre.orthogonal() * 100.0
		commander.position = (Vector2(nav.nearest_walkable(nav.cell_of(spot))) + Vector2(0.5, 0.5)) * NavGrid.CELL
		units_root.add_child(commander)
		commander.setup(commander_type, player)


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


## Print the command buttons shown for player 1's builders and for its farmers, and the
## train buttons of each of its people's buildings (placed finished next to the HQ).
func _scenario_menus() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var ai := AiPlayer.new()
	ai.biome = terrain.biome
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") != players[1].faction or stats.get("kind") != "structure":
			continue
		var type := ObjectTypes.get_type(GameData.type_for_guid(guid, terrain.biome))
		var building := MapObject.new()
		building.setup(type, 1)
		if building.trainable_units().is_empty():
			building.free()
			continue
		building.position = ai._find_spot(type, hq.position)
		units_root.add_child(building)
		selection.select_building(building)
		hud._command_signature = ""
		hud._refresh_commands()
		await get_tree().process_frame
		var names := []
		for button in hud._commands.get_children():
			if not button.is_queued_for_deletion():
				names.append(button.tooltip_text.replace("\n", " / "))
		var queued := []
		for unit_guid in building.trainable_units():
			queued.append("%s:%s" % [GameData.stats(unit_guid).get("name"), building.enqueue(unit_guid)])
		print("%s: %s | enqueue %s" % [stats.name, names, queued])
	ai.free()
	for kind in ["builders", "farmers"]:
		var units := units_root.get_children().filter(func(n: Node) -> bool:
			return n is Unit and n.team == 1 and (n.unit_type.anim_index("build") >= 0 if kind == "builders" else n.unit_type.is_farmer()))
		selection._select(units, false)
		hud._command_signature = ""
		hud._refresh_commands()
		await get_tree().process_frame
		var names := []
		for button in hud._commands.get_children():
			if not button.is_queued_for_deletion():
				names.append("%s%s" % [button.tooltip_text.get_slice("\n", 0), " (off)" if button.disabled else ""])
		print("%s %s (%d units): %s" % [players[1].faction, kind, units.size(), ", ".join(names)])


## One worker starts a house; the others are then sent to help via the help-build order.
func _scenario_help_build() -> void:
	var workers := units_root.get_children().filter(func(n: Node) -> bool:
		return n is Unit and n.team == 1 and n.unit_type.anim_index("build") >= 0)
	selection._select([workers[0]], false)
	build_controller.start(GameData.type_for_guid(201, terrain.biome))
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	for radius in range(200, 600, 32):
		var spot := ((hq.position + Vector2(radius, 0).rotated(radius * 0.7)) / NavGrid.CELL).round() * NavGrid.CELL
		if build_controller.can_place(spot):
			build_controller._place(spot, false)
			break
	var site: MapObject = MapObject.all_objects.filter(func(o: MapObject) -> bool: return not o.complete)[0]
	selection._select(workers.slice(1), false)
	selection.order_build(site)
	OrderMarker.spawn(units_root, site.position + Vector2(-160, 60), 1)
	var helpers := workers.filter(func(u: Unit) -> bool: return u.build_site == site).size()
	print("help-build: %d of %d workers now building" % [helpers, workers.size()])


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
	var states := [0, 0, 0]
	for object in MapObject.all_objects:
		if object.is_tree():
			states[object.tree_state] += 1
	print("  trees standing/felled/stumps: %s" % [states])
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
	for path in GameData.map_files():
		var map := AlfMap.load_from_file(path)
		if map and map.columns > 0 and map.grid_size != Vector2i.ZERO and not map.placements.is_empty():
			maps += 1
		else:
			bad.append(path.get_file())
	print("maps: %d ok, %d failed %s" % [maps, bad.size(), bad])
	print("object types: %d" % ObjectTypes.count())
	if GameData.cmdline_option("selftest") == "farm":
		for guid in [108, 208, 408, 149]:
			for biome in ["steppe", "wiese"]:
				var tid := GameData.type_for_guid(guid, biome)
				var t := ObjectTypes.get_type(tid)
				var bob := GameData.load_bob(t.bob_path) if t else null
				print("guid %d %s -> type %d %s %s anims=%d stats=%s" % [guid, biome, tid, t.name if t else "?", t.bob_path if t else "", bob.anims.size() if bob else -1, GameData.stats(guid).get("name")])
	if GameData.cmdline_option("selftest") == "stats":
		var d := DefaultsData.load()
		print("defaults entries: ", d.size(), " sample: ", d.get(258), " raw bytes: ", GameData.read("Defaults.dat").size())
		for guid in GameData.stats_guids():
			var st := GameData.stats(guid)
			if st.get("kind") in ["unit", "structure"]:
				print("  %d %s %s %s hp=%s dmg=%s cost=%s at=%s types=%s" % [guid, st.get("faction"), st.get("kind"), st.get("name"), st.get("health"), st.get("damage"), st.get("cost"), st.get("produced_at"), st.get("types")])
	get_tree().quit()


func _show_message(text: String) -> void:
	push_error(text)
	var label := Label.new()
	label.text = text
	label.position = Vector2(40, 40)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
