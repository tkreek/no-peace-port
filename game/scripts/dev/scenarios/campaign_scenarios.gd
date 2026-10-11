extends Scenario
## Campaign missions played through by orders, as a player would (start them with
## --mission=...): checks that the mission's script, the units joining and the goals work.


## --mission=base/tut_01: walk the chief to the four tribesmen waiting in the mountains,
## set up the chief's tepee on its marked spot, gather 100 wood: the tutorial is won.
func _scenario_tutorial1() -> void:
	var mission := main.mission
	await _until(func() -> bool: return not Orders.locked, 120.0, "the opening scene")
	var chief := _own(func(u: Unit) -> bool: return u.unit_type.guid() in Player.COMMANDERS)[0] as Unit
	# Independent tribesmen join whoever walks up to them.
	var waiting := Unit.all_units.filter(func(u: Unit) -> bool:
		return u.is_alive() and u.team > 0 and Diplomacy.neutral(main.me, u.team))
	print("tribesmen waiting: %d" % waiting.size())
	for unit: Unit in waiting:
		if unit.team == main.me:
			continue
		Orders.unit(chief, "move_to", [unit.position])
		await _until(func() -> bool: return unit.team == main.me, 120.0, "a tribesman joining")
	print("joined: %d of %d" % [waiting.filter(func(u: Unit) -> bool: return u.team == main.me).size(), waiting.size()])
	# The chief's tepee on its marked spot (area 6), put up by the women.
	await _until(func() -> bool: return mission.goal == 105, 120.0, "the tepee goal")
	var women := _own(func(u: Unit) -> bool: return u.unit_type.anim_index("build") >= 0 and not u.unit_type.can_gather("wood"))
	if women.is_empty():
		women = _own(func(u: Unit) -> bool: return u.unit_type.anim_index("build") >= 0)
	var spot := mission.area(6).get_center()
	Orders.place(GameData.type_for_guid(100, main.terrain.biome), spot, false, null, women)
	await _until(func() -> bool: return mission.count(main.me, 100, mission.area(6)) == 1 and _tepee_done(), 300.0, "the tepee")
	print("tepee standing in its spot; wood %d" % main.players[main.me].resources.wood)
	# Wood: everyone who can, at the nearest trees.
	var cutters := _own(func(u: Unit) -> bool: return u.unit_type.can_gather("wood"))
	var tree := _nearest_tree(spot)
	Orders.units(cutters, "gather", [tree])
	await _until(func() -> bool: return mission.outcome != 0, 600.0, "the end of the tutorial")
	print("TUTORIAL 1 %s at %.0f s, wood %d" % ["WON" if mission.outcome > 0 else "LOST", Sim.time(),
			main.players[main.me].resources.wood])
	get_tree().quit()


func _own(filter: Callable) -> Array:
	return Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team == main.me and filter.call(u))


func _tepee_done() -> bool:
	for object in MapObject.structures:
		if object.owner_index == main.me and object.guid == 100 and object.complete:
			return true
	return false


func _nearest_tree(from: Vector2) -> MapObject:
	var best: MapObject = null
	for object in MapObject.all_objects:
		if object.is_tree() and object.stock.amount > 0 and (best == null or from.distance_to(object.position) < from.distance_to(best.position)):
			best = object
	return best


## Waits (game time) until `done` holds; gives up after `seconds` with a note.
func _until(done: Callable, seconds: float, what: String) -> void:
	var limit := Sim.time() + seconds
	while not done.call():
		if Sim.time() > limit:
			print("TIMED OUT waiting for %s at %.0f s" % [what, Sim.time()])
			get_tree().quit()
			return
		await get_tree().physics_frame
