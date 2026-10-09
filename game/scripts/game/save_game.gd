class_name SaveGame
extends RefCounted
## Saving and loading a match (F2 / the in-game menu). A save is a JSON file holding the
## match settings, each people's stockpile, research and AI progress, every building and
## field, what is left of the trees and mines, every unit, and the explored map. Loading
## builds the map as usual, then replaces everything that can change with the saved state.

const DIR := "user://saves"
const QUICK := "user://saves/quicksave.json"
const VERSION := 1


static func save(main: Node, path := QUICK) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"version": VERSION, "map": main.map_path, "biome": main.terrain.biome, "game_time": main.game_time,
		"camera": [main.camera.position.x, main.camera.position.y],
		"match": {"game_type": Match.game_type, "population_limit": Match.population_limit, "speed": Match.speed,
				"difficulty": Match.difficulty},
		"players": [], "objects": [], "resources": [], "units": [],
		"explored": Marshalls.raw_to_base64(main.fog.explored) if main.fog.enabled else "",
	}
	for index in main.players:
		var p: Player = main.players[index]
		var ai_state := {}
		for ai: AiPlayer in main.ais:
			if ai.player == p:
				ai_state = {"elapsed": ai._elapsed, "wave": ai._attack_wave, "last_attack": ai._last_attack,
						"difficulty": ai.difficulty}
		data.players.append({"index": index, "faction": p.faction, "resources": p.resources,
				"researched": p.researched.keys(), "prices": p.trade_prices, "surrendered": p.surrendered, "ai": ai_state})
	var unit_ids := {}
	for unit in Unit.all_units:
		unit_ids[unit] = unit_ids.size()
	for object in MapObject.all_objects:
		if object.is_ghost:
			continue
		if object.is_building() or object.is_field():
			data.objects.append({"type": object.object_type.id, "x": object.position.x, "y": object.position.y,
					"owner": object.owner_index, "complete": object.complete, "progress": object.build_progress,
					"health": object.health, "queue": Array(object.queue), "train": object.train_progress,
					"rally": [object.rally_point.x, object.rally_point.y] if object.rally_point != Vector2.INF else null,
					"stored_gold": object.stored_gold, "trap_kills": object.trap_kills,
					"loot_kind": object.loot_kind, "loot": object.loot, "burning": object.burning, "distilling": object.distilling,
					"field_state": object.field_state, "field_progress": object.field_progress, "amount": object.amount,
					"garrison": object.garrison.filter(func(u: Unit) -> bool: return unit_ids.has(u)).map(func(u: Unit) -> int: return unit_ids[u])})
		elif object.resource != "" or object.is_tree():
			data.resources.append({"key": _key(object), "amount": object.amount, "tree_state": object.tree_state,
					"mine_work": object.mine_work})
	for unit in Unit.all_units:
		if not unit.is_alive():
			continue
		var source := unit.gather_source
		data.units.append({"id": unit_ids[unit], "dir": unit.unit_type.directory, "mounted": unit.unit_type.mounted,
				"type": unit.unit_type.type_id, "team": unit.team, "x": unit.position.x, "y": unit.position.y,
				"health": unit.health, "stance": unit.stance, "formation": unit.formation, "carried": unit.carried,
				"carrying": unit.carrying, "cattle": unit.cattle_value, "magic": unit.magic_energy,
				"gather": _key(source) if is_instance_valid(source) and source.resource != "" else "",
				"gather_resource": unit.gather_resource, "packed_tepee": unit.packed_tepee,
				"vessel": unit_ids[unit.vessel] if unit.state == Unit.State.QUARTERED and unit_ids.has(unit.vessel) else -1})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true


static func read(path := QUICK) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary and int(parsed.get("version", 0)) == VERSION else {}


## Bring a freshly set-up match (map, terrain, forests, players) to the saved state.
static func restore(main: Node, data: Dictionary) -> void:
	main.game_time = float(data.get("game_time", 0.0))
	for entry in data.players:
		var p: Player = main.players.get(int(entry.index))
		if p == null:
			continue
		for key in entry.resources:
			p.resources[key] = int(entry.resources[key])
		p.researched.clear()
		for upgrade in entry.researched:
			p.researched[int(upgrade)] = true
		for good in entry.prices:
			p.trade_prices[good] = float(entry.prices[good])
		p.surrendered = bool(entry.surrendered)
		for ai: AiPlayer in main.ais:
			if ai.player == p and not entry.ai.is_empty():
				ai._elapsed = float(entry.ai.elapsed)
				ai._attack_wave = int(entry.ai.wave)
				ai._last_attack = float(entry.ai.last_attack)
				ai.difficulty = int(entry.ai.difficulty)
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
		if (object.resource == "" and not object.is_tree()) or object.is_field():
			continue
		var entry: Dictionary = saved_resources.get(_key(object), {})
		if entry.is_empty():
			main.nav.unblock_footprint(object.object_type, object.position)
			object.get_parent().remove_child(object)
			object.queue_free()
			continue
		object.restore_resource(int(entry.amount), int(entry.tree_state), float(entry.mine_work))
		by_key[_key(object)] = object
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
		object.restore_state(entry)
		if object.is_building() and not object.is_trap():
			main.nav.block_footprint(type, object.position)
		object.unit_trained.connect(main._on_unit_trained)
		if not entry.garrison.is_empty():
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
		unit.health = float(entry.health)
		unit.stance = int(entry.stance)
		unit.formation = int(entry.formation)
		unit.carried = int(entry.carried)
		unit.carrying = entry.carrying
		unit.cattle_value = float(entry.cattle)
		unit.magic_energy = float(entry.magic)
		var packed: Dictionary = entry.get("packed_tepee", {})
		if not packed.is_empty():
			unit.packed_tepee = {"guid": int(packed.guid), "health": float(packed.health)}
		units[int(entry.id)] = unit
		if entry.gather != "" and by_key.has(entry.gather):
			unit.gather.call_deferred(by_key[entry.gather])
	for entry in data.units:
		var boat: Unit = units.get(int(entry.get("vessel", -1)))
		if boat and units.has(int(entry.id)):
			units[int(entry.id)].vessel = boat
			boat.take_aboard(units[int(entry.id)])
	for pair in garrisons:
		for id in pair[1]:
			if units.has(int(id)):
				pair[0].enter(units[int(id)])
	if data.explored != "" and main.fog.enabled:
		var explored := Marshalls.base64_to_raw(data.explored)
		if explored.size() == main.fog.explored.size():
			main.fog.explored = explored
	main.camera.position = Vector2(data.camera[0], data.camera[1])
	main.fog.update_now()


static func _key(object: MapObject) -> String:
	return "%d@%d,%d" % [object.object_type.id, roundi(object.position.x), roundi(object.position.y)]
