class_name Main
extends Node2D
## The match: loads a map with the original terrain, sets up the peoples, the interface and
## the computer players, and decides when the game is won.
##
## Command line (after `--`):
##   --map=<file in assets/maps or absolute path>   default "[2 Players] - close combat.ulf"
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
##   --seed=n  the game's randomness; --checksum-every=<s>  print a state fingerprint (Sim)
##   --record=<file>  keep the match's orders (written on leaving); --replay=<file>  play them
##     back instead of the player's (start it with the same map and peoples)
##   --camera=x,y  --zoom=z  --order=x,y (screenshot move target)  --debug-paths=1

const DEFAULT_MAP := "[2 Players] - close combat.ulf"

var terrain := Terrain.new()
var units_root := Node2D.new()
var camera := RtsCamera.new()
var selection := SelectionController.new()
var nav := NavGrid.new()
var fog := FogOfWar.new()
var hud := Hud.new()
var build_controller := BuildController.new()
var ambience := Ambience.new()
var ais: Array[AiPlayer] = []
var _game_over := false
var players := {}
var start_positions := {}  # player -> Vector2, from the map's Editor_Start markers
## Players the map gives units or buildings of their own: they start with exactly those
## instead of the usual main building, workers and commander (maps made for tests).
var placed_owners := {}
var map_path := ""
var loaded_game := false

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
		_show_message("Game assets not found.\nBuild them with tools/assets/build_assets.py, or run with --assets-dir=<folder>")
		return
	if GameData.cmdline_option("selftest") != "":
		DevTools.attach(self).selftest()
		return
	var map_arg := GameData.cmdline_option("map", DEFAULT_MAP)
	map_path = map_arg
	var loading: Dictionary = Match.load_data
	Match.load_data = {}
	if not loading.is_empty():
		map_path = loading.map
	elif Match.configured:
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
	# The game's randomness: --seed=n for a repeatable run (scenarios default to 1); a replay
	# brings its own, and its orders instead of the player's.
	var default_seed := "1" if GameData.cmdline_option("scenario") != "" else str(randi())
	var replay := Orders.read_replay(GameData.cmdline_option("replay"))
	Sim.reset(int(replay.seed) if not replay.is_empty() else GameData.cmdline_option("seed", default_seed).to_int())
	if not replay.is_empty():
		Orders.play(replay)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # the camera and interface move per frame
	units_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON  # the game moves per step

	add_child(terrain)
	terrain.setup(map, loading.get("biome", GameData.cmdline_option("biome", map.guess_biome())))
	units_root.y_sort_enabled = true
	add_child(units_root)
	nav.setup(map)
	_spawn_placements(map)
	selection.units_root = units_root
	selection.camera = camera
	add_child(selection)
	camera.bounds = Rect2(Vector2.ZERO, map.pixel_size())
	add_child(camera)
	camera.make_current()
	ambience.camera = camera
	add_child(ambience)

	var size := Vector2(map.pixel_size())
	Player.by_index.clear()
	var computer := {}  # player index -> true when AI controlled
	if not loading.is_empty():
		var settings: Dictionary = loading.match
		Match.game_type = int(settings.game_type) as Match.GameType
		Match.population_limit = int(settings.population_limit)
		Match.speed = float(settings.speed)
		Match.configured = true
		for entry in loading.players:
			players[int(entry.index)] = Player.new(int(entry.index), entry.faction)
			computer[int(entry.index)] = not entry.ai.is_empty()
	elif Match.configured:
		for i in Match.players.size():
			players[i + 1] = Player.new(i + 1, Match.players[i].faction)
			computer[i + 1] = Match.players[i].ai
	elif GameData.cmdline_option("players") != "":
		# --players=mex,usa,ind,...: one people per start point, all but the first computer
		# players (the first too with --ai-vs-ai).
		var factions := GameData.cmdline_option("players").split(",")
		for i in factions.size():
			players[i + 1] = Player.new(i + 1, factions[i] if FACTIONS.has(factions[i]) else "mex")
			computer[i + 1] = i > 0 or GameData.cmdline_option("ai-vs-ai") != ""
	else:
		players[1] = Player.new(1, _faction_option("faction", "mex"))
		players[2] = Player.new(2, _faction_option("enemy", "usa"))
		computer[2] = GameData.cmdline_option("ai") != "off"
		computer[1] = GameData.cmdline_option("ai-vs-ai") != ""
	for player in players:
		players[player].set_start_resources(Match.start_resources(map.start_resources))
		if loading.is_empty() and not placed_owners.has(player):
			_setup_player(player, start_positions.get(player, _fallback_start(player, size)))
	camera.position = _vector_option("camera", start_positions.get(1, size / 2.0))
	# --time-scale=N runs the simulation N times faster (long AI tests).
	var speed := clampf(GameData.cmdline_option("time-scale", "1").to_float(), 0.1, 8.0)
	if Match.configured:
		speed *= Match.speed  # the setup screen's game speed
	Sim.set_speed(speed)
	var report := GameData.cmdline_option("report-after")
	if report != "":
		DevTools.attach(self).report_after(report.to_int())
	camera.set_zoom_level(GameData.cmdline_option("zoom", "1").to_float())
	fog.enabled = GameData.cmdline_option("fog", "on") != "off"
	add_child(fog)
	fog.setup(map, 1)
	build_controller.player = players[1]
	build_controller.selection = selection
	build_controller.objects_root = units_root
	Orders.build_controller = build_controller
	Orders.local_player = 1  # the interface gives player 1's orders
	add_child(build_controller)  # after the selection controller, so it sees clicks first
	build_controller.placed.connect(_on_building_placed)
	for object in MapObject.structures:
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
			ai.difficulty = Match.difficulty if Match.configured else GameData.cmdline_option("difficulty", "2").to_int()
			add_child(ai)
			ais.append(ai)
	if not loading.is_empty():
		SaveGame.restore(self, loading)
		loaded_game = true
	if GameData.cmdline_option("scenario") != "":
		Scenario.start(self, GameData.cmdline_option("scenario"))
	Sound.play_music(players[1].faction)
	DisplayServer.window_set_title("America — %s" % map.title)
	if GameData.cmdline_option("screenshot") != "":
		DevTools.attach(self).screenshot(GameData.cmdline_option("screenshot"))


func _spawn_placements(map: AlfMap) -> void:
	var started := Time.get_ticks_msec()
	var spawned := 0
	for placement in map.placements:
		var type := ObjectTypes.get_type(placement.type_id)
		if type and type.name.begins_with("editor_start"):
			start_positions[placement.owner] = placement.position
			continue
		if type == null or type.anims.is_empty():
			continue
		if placement.owner > 0 and placement.owner < 9:
			placed_owners[placement.owner] = true
		if type.kind == ObjectTypes.Kind.UNIT:
			var unit_type := UnitType.load_type(type.directory(), type.is_mounted(), type.id)
			if unit_type == null:
				continue
			var unit := Unit.new()
			unit.position = placement.position
			units_root.add_child(unit)
			unit.setup(unit_type, placement.owner)
		else:
			var object := MapObject.new()
			object.position = placement.position
			if not object.setup(type, placement.owner, placement.amount):
				object.free()
				continue
			if object.is_abandoned_store():
				object.stock.stock_abandoned_store(placement.content, placement.amount)
			units_root.add_child(object)
			# The original maps carry their objects' footprints in the collision grid already;
			# stamping again changes nothing there and fills them in for editor maps.
			nav.block_footprint(type, placement.position)
		spawned += 1
	print("Placed %d/%d map objects in %d ms" % [spawned, map.placements.size(), Time.get_ticks_msec() - started])
	_grow_forests(map)


## Plant the map's painted forests (see ForestGenerator).
func _grow_forests(map: AlfMap) -> void:
	var started := Time.get_ticks_msec()
	var avoid: Array[Vector2] = []
	for object in MapObject.all_objects:
		if object.stock.resource != "wood":
			avoid.append(object.position)
	var trees := ForestGenerator.generate(map, terrain.biome, avoid, start_positions.values())
	for tree in trees:
		var type := ObjectTypes.get_type(tree.type_id)
		var object := MapObject.new()
		object.position = tree.position
		if not object.setup(type, 0):
			object.free()
			continue
		object.stock.amount = tree.wood
		units_root.add_child(object)
		nav.block_footprint(type, tree.position)
	print("Grew %d forest trees in %d ms" % [trees.size(), Time.get_ticks_msec() - started])


func _exit_tree() -> void:
	if GameData.cmdline_option("record") != "":
		Orders.write_replay(GameData.cmdline_option("record"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not event.echo:
		hud.toggle_menu()
		get_viewport().set_input_as_handled()


## A player is out when they have no buildings and no units left.
func _check_victory() -> void:
	if _game_over or Match.editor_map != "":
		return
	# Who is still in the game depends on the game type: anyone with units or buildings left,
	# anyone whose leader lives, or anyone whose main building stands.
	var alive := {}
	match Match.game_type if Match.configured else Match.GameType.EVERYBODY:
		Match.GameType.KILL_LEADER:
			for index in players:
				if players[index].leader() != null:
					alive[index] = true
		Match.GameType.MAIN_BUILDING:
			for index in players:
				if players[index].main_building() != null:
					alive[index] = true
			# A chief's tepee packed on a travois is still the people's.
			for unit in Unit.all_units:
				if unit.is_alive() and unit.team > 0 and int(unit.tepees.packed.get("guid", -1)) in MapObject.MAIN_BUILDINGS:
					alive[unit.team] = true
		_:
			for node in units_root.get_children():
				if (node is Unit and node.is_alive() and not node.animal.is_cow()) or (node is MapObject and node.is_building() and node.is_alive()):
					var owner: int = node.team if node is Unit else node.owner_index
					if owner > 0:
						alive[owner] = true
	for index in players:
		if players[index].surrendered:
			alive.erase(index)
	var human_alive: bool = alive.has(1)
	var others_alive := alive.keys().any(func(k: int) -> bool: return k != 1)
	if human_alive and others_alive:
		return
	_game_over = true
	var won := human_alive
	print("GAME OVER: ", "player 1 wins" if won else "player 1 lost")
	Sound.play_mission_result(won)
	hud.show_banner(GameData.text(1 if won else 2, "Victory!" if won else "Defeat"))
	hud.show_statistics(players)


## An AI player gave up (its main building gone and no way to rebuild it).
func on_surrender(player: Player) -> void:
	print("SURRENDER: player %d (%s)" % [player.index, player.faction])
	hud.notify("The %s surrender!" % Match.faction_name(player.faction))
	_check_victory()


func _on_building_placed(site: MapObject) -> void:
	site.unit_trained.connect(_on_unit_trained)


## A building finished training a unit: it steps out in front (below) of the footprint.
func _on_unit_trained(building: MapObject, unit_guid: int) -> void:
	var unit_type: UnitType = null
	if unit_guid == BuildingProduction.COW_GUID:
		unit_type = UnitType.load_type(UnitAnimal.COW_DIR)  # a calf raised at the ranch or hacienda
	else:
		var type := ObjectTypes.get_type(GameData.type_for_guid(unit_guid, terrain.biome))
		if type == null:
			return
		unit_type = UnitType.for_guid(unit_guid)
	if unit_type == null:
		return
	var rect := building.footprint_rect()
	var exit := Vector2(rect.get_center().x, rect.end.y + 12)
	var cell := nav.nearest_walkable(nav.cell_of(exit))
	if unit_guid in UnitWater.BOATS:
		# Boats are launched onto the water by the wharf or boathouse.
		var water := nav.nearest_passable(nav.cell_of(rect.get_center()), 30, NavGrid.Layer.WATER)
		if water.x < 0:
			return
		cell = water
	var unit := Unit.new()
	unit.position = (Vector2(cell) + Vector2(0.5, 0.5)) * NavGrid.CELL
	units_root.add_child(unit)
	unit.setup(unit_type, building.owner_index)
	if building.production.rally_point != Vector2.INF:
		unit.move_to(building.production.rally_point + Vector2(Sim.randf_range(-24, 24), Sim.randf_range(-16, 16)))
	elif unit.water.is_boat():
		pass
	else:
		unit.move_to(unit.position + Vector2(Sim.randf_range(-40, 40), 50))


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
	var builder := -1
	var farmer := -1
	for guid in hq.production.trainable_units():
		var unit_type := UnitType.for_guid(guid)
		if unit_type == null:
			continue
		if builder < 0 and unit_type.can_gather("wood") and unit_type.anim_index("build") >= 0:
			builder = guid
		elif farmer < 0 and unit_type.is_farmer():
			farmer = guid
	if builder >= 0:
		_spawn_squad(builder, player, start + toward_centre * 220.0, START_BUILDERS)
	if farmer >= 0:
		_spawn_squad(farmer, player, start + toward_centre * 220.0 + toward_centre.orthogonal() * 120.0, START_FARMERS)
	# Every people starts with its commander on horseback.
	var commander_type := UnitType.for_guid(FACTIONS[players[player].faction].commander)  # mounted
	if commander_type:
		var commander := Unit.new()
		var spot := start + toward_centre * 300.0 - toward_centre.orthogonal() * 100.0
		commander.position = (Vector2(nav.nearest_walkable(nav.cell_of(spot))) + Vector2(0.5, 0.5)) * NavGrid.CELL
		units_root.add_child(commander)
		commander.setup(commander_type, player)


## `what` is a unit GUID or (for tests) a unit graphics folder.
func _spawn_squad(what: Variant, team: int, centre: Vector2, count: int) -> void:
	var unit_type := UnitType.for_guid(what) if what is int else UnitType.load_type(what)
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


## Simulated seconds since the match began.
var game_time: float:
	get:
		return Sim.time()
	set(value):
		Sim.tick = roundi(value * Sim.RATE)
const VICTORY_CHECK_TICKS := Sim.RATE * 2
## --checksum-every=<seconds>: print the state's fingerprint (compare runs for determinism).
var _dump_tick := GameData.cmdline_option("dump-at", "-1").to_int()  # --dump-at=<step>: every unit's state
var _checksum_ticks := roundi(GameData.cmdline_option("checksum-every", "0").to_float() * Sim.RATE)


## The game advances one fixed step per physics frame (Sim).
func _physics_process(_delta: float) -> void:
	Sim.step()
	if Sim.tick % VICTORY_CHECK_TICKS == 0:
		_check_victory()
	if _checksum_ticks > 0 and Sim.tick % _checksum_ticks == 0:
		print("tick %d checksum %s" % [Sim.tick, Sim.checksum()])
	if _dump_tick >= 0 and Sim.tick >= _dump_tick and Sim.tick % 10 == 0:
		for unit in Unit.all_units:
			print("dump t%d #%d %s team %d at %s hp %.2f state %d path %d" % [Sim.tick, unit.sim_id, unit.unit_type.guid(), unit.team,
					unit.position, unit.health, unit.state, unit.path.size()])
		for index in Player.by_index:
			print("dump people %d %s" % [index, Player.by_index[index].resources])


func _vector_option(name: String, default: Vector2) -> Vector2:
	var value := GameData.cmdline_option(name)
	if value.is_empty():
		return default
	var parts := value.split(",")
	return Vector2(parts[0].to_float(), parts[1].to_float())


func _show_message(text: String) -> void:
	push_error(text)
	var label := Label.new()
	label.text = text
	label.position = Vector2(40, 40)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
