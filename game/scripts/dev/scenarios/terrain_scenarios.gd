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
