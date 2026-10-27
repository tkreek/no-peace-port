class_name SaveGame
extends RefCounted
## Saving and loading a match (F2 / the in-game menu). A save is a JSON file holding the
## match settings, each people's stockpile, research and AI progress, every building and
## field, what is left of the trees and mines, every unit, and the explored map. Loading
## builds the map as usual, then replaces everything that can change with the saved state.
##
## Each save has a name the player gives it and a file of its own (the name in lower case,
## made safe for a file name); F2 saves as "Quicksave". The file's first line is a small
## header (the name, when it was saved, where, how long it had been played, a little picture),
## so the list of saves reads only that; the second line is the game. A save from before the
## header (one line, the game alone) still lists and loads.

const DIR := "user://saves"
const QUICK_NAME := "Quicksave"
const VERSION := 1
const THUMBNAIL_SIZE := Vector2i(192, 108)


## Where the saves are kept: --save-dir=<folder>, else user://saves. Developer runs
## (--scenario, --menu-shot) keep theirs apart, so they never touch the player's own.
static func folder() -> String:
	var given := GameData.cmdline_option("save-dir")
	if given != "":
		return given
	if GameData.cmdline_option("scenario") != "" or GameData.cmdline_option("menu-shot") != "":
		return "user://saves_test"
	return DIR


## The file a save of this name goes to (the same file for names differing only in case).
static func path_for(save_name: String) -> String:
	var file := save_name.strip_edges().to_lower().validate_filename()
	return folder().path_join((file if file != "" else "save") + ".json")


## A name to offer for a new save: where it is played and when.
static func default_name(main: Node) -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%s %04d-%02d-%02d %02d.%02d" % [place(main), now.year, now.month, now.day, now.hour, now.minute]


## The mission's title, or the map's (as the skirmish menu lists it).
static func place(main: Node) -> String:
	if main.mission and not Match.campaign.is_empty():
		return Campaign.title(Match.campaign)
	return _map_title(main.map_path)


static func _map_title(map_path: String) -> String:
	var base := map_path.get_file().get_basename()
	return base.get_slice("] - ", 1).capitalize() if base.contains("] - ") else base


## A small picture of the game view for a save's header, or null (headless, no frame yet):
## the middle of the screen, without the interface along its edges.
static func capture(viewport: Viewport) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var frame := viewport.get_texture().get_image()
	if frame == null or frame.is_empty():
		return null
	var size := Vector2(frame.get_size())
	var picture := frame.get_region(Rect2i(Vector2i(size * Vector2(0.18, 0.1)), Vector2i(size * 0.64)))
	picture.resize(THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, Image.INTERPOLATE_BILINEAR)
	return picture


## Save the match as `save_name` (to path_for(save_name)), with a picture for the list.
static func save(main: Node, save_name := QUICK_NAME, picture: Image = null) -> bool:
	var path := path_for(save_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var header := {"name": save_name.strip_edges(), "saved": int(Time.get_unix_time_from_system()),
			"place": place(main), "game_time": main.game_time,
			"thumbnail": Marshalls.raw_to_base64(picture.save_png_to_buffer()) if picture else ""}
	var data := {
		"version": VERSION, "map": main.map_path, "biome": main.terrain.biome, "game_time": main.game_time,
		"tick": Sim.tick, "rng": str(Sim.rng.state),  # the game's clock and randomness (Sim), to carry on alike
		"camera": [main.camera.position.x, main.camera.position.y],
		"match": {"game_type": Match.game_type, "population_limit": Match.population_limit, "speed": Match.speed,
				"difficulty": Match.difficulty},
		"players": [], "objects": [], "resources": [], "units": [],
		"explored": Marshalls.raw_to_base64(main.fog.explored) if main.fog.enabled else "",
		"diplomacy": Diplomacy.save_state(), "next_sim_id": Sim.next_id(),
		"prices": Player.trade_prices,  # one set for every people
	}
	if main.mission:
		data["campaign"] = Match.campaign
		data["mission"] = main.mission.save_state()
		data["ki"] = main.ki.save_state()
		data["revealed_areas"] = main.fog.revealed_areas.keys()
	for index in main.players:
		var p: Player = main.players[index]
		var ai_state := {}
		for ai: AiPlayer in main.ais:
			if ai.player == p:
				ai_state = ai.save_state()
		data.players.append({"index": index, "faction": p.faction, "resources": p.resources,
				"researched": p.researched.keys(), "surrendered": p.surrendered, "ai": ai_state,
				"team": p.team, "name": p.player_name, "stats": p.stats})
	var unit_ids := {}
	for unit in Unit.all_units:
		unit_ids[unit] = unit_ids.size()
	for object in MapObject.all_objects:
		if object.is_ghost:
			continue
		if object.is_building() or object.is_field():
			data.objects.append(object.save_state(unit_ids))
		elif object.stock.resource != "" or object.is_tree():
			data.resources.append({"key": _key(object), "amount": object.stock.amount, "tree_state": object.stock.tree_state,
					"mine_work": object.stock.mine_work})
	for unit in Unit.all_units:
		if not unit.is_alive():
			continue
		var source := unit.work.gather_source
		data.units.append({"id": unit_ids[unit], "sim": unit.sim_id, "dir": unit.unit_type.directory, "mounted": unit.unit_type.mounted,
				"type": unit.unit_type.type_id, "team": unit.team, "x": unit.position.x, "y": unit.position.y,
				"health": unit.health, "stance": unit.stance, "formation": unit.formation, "carried": unit.work.carried,
				"carrying": unit.work.carrying, "cattle": unit.animal.cattle_value, "magic": unit.magic.magic_energy,
				"gather": _key(source) if is_instance_valid(source) and source.stock.resource != "" else "",
				"gather_resource": unit.work.gather_resource, "packed_tepee": unit.tepees.packed,
				"vessel": unit_ids[unit.water.vessel] if unit.state == Unit.State.QUARTERED and unit_ids.has(unit.water.vessel) else -1})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line(JSON.stringify({"header": header}))
	file.store_string(JSON.stringify(data))
	return true


## The game saved in a file (path_for; none given: the quick save), or empty when there is
## none or it cannot be read.
static func read(path := "") -> Dictionary:
	if path == "":
		path = path_for(QUICK_NAME)
	var file := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_line())
	if parsed is Dictionary and parsed.has("header"):
		parsed = JSON.parse_string(file.get_line())
	return parsed if parsed is Dictionary and int(parsed.get("version", 0)) == VERSION else {}


## The saves there are, newest first: {"path", "name", "saved" (Unix time), "place",
## "game_time", "thumbnail" (an Image or null)}. Only the headers are read; a save from
## before them is read whole and named after its file.
static func list() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	for file in _files():
		var entry := _entry(folder().path_join(file))
		if not entry.is_empty():
			saves.append(entry)
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.saved > b.saved if a.saved != b.saved else a.name.naturalnocasecmp_to(b.name) < 0)
	return saves


## Whether there is a save to load (without reading any).
static func any() -> bool:
	return not _files().is_empty()


static func _files() -> Array:
	if not DirAccess.dir_exists_absolute(folder()):
		return []
	return Array(DirAccess.get_files_at(folder())).filter(func(file: String) -> bool: return file.get_extension() == "json")


static func _entry(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_line())
	if not parsed is Dictionary:
		return {}
	var header: Dictionary = parsed.get("header", {})
	if header.is_empty():  # an old save: the game alone
		if int(parsed.get("version", 0)) != VERSION:
			return {}
		var campaign = parsed.get("campaign", {})
		header = {"name": path.get_file().get_basename().capitalize(), "saved": FileAccess.get_modified_time(path),
				"place": Campaign.title(campaign) if campaign is Dictionary and not campaign.is_empty() \
					else _map_title(String(parsed.get("map", ""))),
				"game_time": parsed.get("game_time", 0.0)}
	var picture: Image = null
	if String(header.get("thumbnail", "")) != "":
		picture = Image.new()
		if picture.load_png_from_buffer(Marshalls.base64_to_raw(header.thumbnail)) != OK:
			picture = null
	return {"path": path, "name": String(header.get("name", "")), "saved": int(header.get("saved", 0)),
			"place": String(header.get("place", "")), "game_time": float(header.get("game_time", 0.0)),
			"thumbnail": picture}


static func delete(path: String) -> bool:
	return DirAccess.remove_absolute(path) == OK


## Bring a freshly set-up match (map, terrain, forests, players) to the saved state.
static func restore(main: Node, data: Dictionary) -> void:
	main.game_time = float(data.get("game_time", 0.0))
	Player.reset_trade_prices()
	for good in data.get("prices", {}):
		Player.trade_prices[good] = float(data.prices[good])
	if data.has("diplomacy"):
		Diplomacy.restore_state(data.diplomacy)
	if main.mission and data.has("mission"):
		main.mission.restore_state(data.mission)
		if data.has("ki"):
			main.ki.restore_state(data.ki)
		for id in data.get("revealed_areas", []):
			main.fog.revealed_areas[int(id)] = main.mission.area(int(id))
	if data.has("tick"):
		Sim.tick = int(data.tick)
		Sim.rng.state = String(data.rng).to_int()
	for entry in data.players:
		var p: Player = main.players.get(int(entry.index))
		if p == null:
			continue
		for key in entry.resources:
			p.resources[key] = int(entry.resources[key])
		p.researched.clear()
		for upgrade in entry.researched:
			p.researched[int(upgrade)] = true
		p.surrendered = bool(entry.surrendered)
		for key in entry.get("stats", {}):
			p.stats[key] = int(entry.stats[key])
		for ai: AiPlayer in main.ais:
			if ai.player == p and not entry.ai.is_empty():
				ai.restore_state(entry.ai)
		p.resources_changed.emit()
	# Clear what the map and the start set up, keep the scenery.
	for unit in Unit.all_units.duplicate():
		unit.get_parent().remove_child(unit)
		unit.queue_free()
	for object in MapObject.all_objects.duplicate():
		if object.is_building() or object.is_field():
			if object.is_building() and not object.is_trap():
				main.nav.unblock_footprint(object.object_type, object.position)
			object.get_parent().remove_child(object)
			object.queue_free()
	# Trees and mines: what is left of each; those gone entirely are removed.
	var saved_resources := {}
	for entry in data.resources:
		saved_resources[entry.key] = entry
	var by_key := {}
	for object in MapObject.all_objects.duplicate():
		if (object.stock.resource == "" and not object.is_tree()) or object.is_field():
			continue
		var entry: Dictionary = saved_resources.get(_key(object), {})
		if entry.is_empty():
			main.nav.unblock_footprint(object.object_type, object.position)
			object.get_parent().remove_child(object)
			object.queue_free()
			continue
		object.stock.restore_resource(int(entry.amount), int(entry.tree_state), float(entry.mine_work))
		by_key[_key(object)] = object
	# What was made during the game gets its own number back (Sim.reidentify); new numbers
	# handed out meanwhile start above the saved ones so they never collide.
	Sim.set_next_id(int(data.get("next_sim_id", 0)))
	# Buildings and fields.
	var garrisons := []
	for entry in data.objects:
		var type := ObjectTypes.get_type(int(entry.type))
		if type == null:
			continue
		var object := MapObject.new()
		object.position = Vector2(entry.x, entry.y)
		if not object.setup(type, int(entry.owner), 0, not bool(entry.complete)):
			object.free()
			continue
		main.units_root.add_child(object)
		Sim.reidentify(object, int(entry.get("sim", 0)))
		object.restore_state(entry)
		if object.is_building() and not object.is_trap():
			main.nav.block_footprint(type, object.position)
		object.unit_trained.connect(main._on_unit_trained)
		if not entry.get("garrison", []).is_empty():
			garrisons.append([object, entry.garrison])
	# Units.
	var units := {}
	for entry in data.units:
		var unit_type := UnitType.load_type(entry.dir, bool(entry.mounted), int(entry.type))
		if unit_type == null:
			continue
		var unit := Unit.new()
		unit.position = Vector2(entry.x, entry.y)
		main.units_root.add_child(unit)
		unit.setup(unit_type, int(entry.team))
		Sim.reidentify(unit, int(entry.get("sim", 0)))
		unit.health = float(entry.health)
		unit.stance = int(entry.stance)
		unit.formation = int(entry.formation)
		unit.work.carried = int(entry.carried)
		unit.work.carrying = entry.carrying
		unit.animal.cattle_value = float(entry.cattle)
		unit.magic.magic_energy = float(entry.magic)
		var packed: Dictionary = entry.get("packed_tepee", {})
		if not packed.is_empty():
			unit.tepees.packed = {"guid": int(packed.guid), "health": float(packed.health)}
		units[int(entry.id)] = unit
		if entry.gather != "" and by_key.has(entry.gather):
			unit.gather.call_deferred(by_key[entry.gather])
	for entry in data.units:
		var boat: Unit = units.get(int(entry.get("vessel", -1)))
		if boat and units.has(int(entry.id)):
			units[int(entry.id)].water.vessel = boat
			boat.water.take_aboard(units[int(entry.id)])
	for pair in garrisons:
		for id in pair[1]:
			if units.has(int(id)):
				pair[0].defence.enter(units[int(id)])
	if data.explored != "" and main.fog.enabled:
		var explored := Marshalls.base64_to_raw(data.explored)
		if explored.size() == main.fog.explored.size():
			main.fog.explored = explored
	main.camera.position = Vector2(data.camera[0], data.camera[1])
	main.fog.update_now()


static func _key(object: MapObject) -> String:
	return "%d@%d,%d" % [object.object_type.id, roundi(object.position.x), roundi(object.position.y)]
