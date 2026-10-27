class_name TerrainScenarios
extends Scenario
## Developer scenarios: getting about on the ground.

const RAMP := 0x10000000  ## the bit a ramp's cells carry (see NavGrid._lay_ramps)


## Plateaus are reached only by their ramps: a unit sent onto one walks up the ramp, a
## unit sent onto one without a ramp stops at the foot of its cliff.
func _scenario_plateau() -> void:
	var nav: NavGrid = main.nav
	var walker: Unit = Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 1 and u.is_alive())[0]
	var home := nav.cell_of(walker.position)
	var level := func(cell: Vector2i) -> int: return (nav.flags_at(cell) >> 12) & 3
	# Plateau cells, nearest first: the first one the path reaches and the first it doesn't.
	var high: Array[Vector2i] = []
	for y in range(2, nav.size.y - 2, 4):
		for x in range(2, nav.size.x - 2, 4):
			var cell := Vector2i(x, y)
			if level.call(cell) > level.call(home) and nav.is_walkable(cell) and (nav.flags_at(cell) & RAMP) == 0:
				high.append(cell)
	high.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - home).length_squared() < (b - home).length_squared())
	var reachable := Vector2.INF
	var cut_off := Vector2.INF
	var slowest := 0
	for cell in high:
		var goal := nav.center_of(cell)
		var started := Time.get_ticks_usec()
		var path := nav.find_path(walker.position, goal)
		slowest = maxi(slowest, Time.get_ticks_usec() - started)
		var arrives := not path.is_empty() and path[path.size() - 1] == goal
		if arrives and reachable == Vector2.INF:
			reachable = goal
		elif not arrives and cut_off == Vector2.INF:
			cut_off = goal
		if reachable != Vector2.INF and cut_off != Vector2.INF:
			break
	print("plateau cells %d, reachable %s, cut off %s, slowest path %d ms" % [high.size(), reachable != Vector2.INF,
			cut_off != Vector2.INF, slowest / 1000])
	for goal: Vector2 in [cut_off, reachable]:
		if goal == Vector2.INF:
			continue
		var start := walker.position
		walker.move_to(goal)
		var ramp := false
		var highest := 0
		for i in 120 * 30:
			await get_tree().physics_frame
			var cell := nav.cell_of(walker.position)
			ramp = ramp or (nav.flags_at(cell) & RAMP) != 0
			if nav.flags_at(cell) & NavGrid.WALKABLE:
				highest = maxi(highest, level.call(cell))
			if walker.path.is_empty():
				break
		print("%s plateau: %d px short, level %d -> %d (highest %d), by a ramp %s" % [
				"cut off" if goal == cut_off else "ramped", walker.position.distance_to(goal),
				level.call(nav.cell_of(start)), level.call(nav.cell_of(walker.position)), highest, ramp])
	get_tree().quit()


## Units on a ramp, from its foot to its top: each is drawn over the ramp (it lies on the
## ground; drawn standing, it hid the upper half of whoever climbed it). The camera looks
## at the first ramp for a screenshot.
func _scenario_ramp() -> void:
	var nav: NavGrid = main.nav
	var ramps := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.object_type.name.begins_with("ramp_"))
	var ramp: MapObject = ramps[0]
	var cells: Array[Vector2i] = []
	var low := nav.cell_of(ramp.visual_rect().position)
	var high := nav.cell_of(ramp.visual_rect().end)
	for y in range(low.y, high.y + 1, 2):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			if nav.flags_at(cell) & RAMP and nav.is_walkable(cell):
				cells.append(cell)
				break
	var walkers: Array[Unit] = []
	var guid: int = main.players[1].main_building().production.trainable_units()[-1]
	for cell in cells:
		var unit := Unit.new()
		unit.position = nav.center_of(cell)
		main.units_root.add_child(unit)
		unit.setup(UnitType.for_guid(guid), 1)
		unit.direction = 5  # facing up the slope
		walkers.append(unit)
	main.camera.position = ramp.position
	for i in 4:
		await get_tree().physics_frame
	var over := walkers.filter(func(u: Unit) -> bool:
		return ramp.z_index < u.z_index or (ramp.z_index == u.z_index and ramp.position.y < u.position.y))
	var above := walkers.filter(func(u: Unit) -> bool: return u.position.y < ramp.position.y)
	print("ramp view %s" % ramp.position.round())
	print("ramps %d; on the first %d walkers, %d above where it stands, %d drawn over it" % [ramps.size(),
			walkers.size(), above.size(), over.size()])
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()
