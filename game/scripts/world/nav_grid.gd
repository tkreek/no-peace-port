class_name NavGrid
extends RefCounted
## Ground navigation on the original 16 px collision grid.
##
## Cell flags (map BITARRAY and object "BARY" footprints share them):
##   bits 0-2   walkable ground (cleared on cliff faces and deep water)
##   bit 3      water (deep, or shallow where the ground bits are set as well)
##   bit 6      blocked (cliffs, rocks painted into the map)
##   bit 7      terrain type
##   bits 12-13 height level: the map walls each level off with unwalkable cliff faces,
##              and the ramps placed on it are the only ways up (see _lay_ramps)
##   bit 29     cover: canopy or roof drawn over the ground (walkable)
##   bit 30     margin: a one-cell ring round buildings and mines that keeps other
##              buildings at a distance (walkable, so there is always a lane between them)
##   bit 31     solid: walls, mine entrances, tree trunks

const CELL := 16
const WALKABLE := 0x2
const WATER := 0x8
const SOLID := 0x40 | 0x80000000
const MARGIN := 0x40000000
const GROUND := 0x7 | 0x40 | 0x3000  ## what a ramp's walkable cells replace
const COVER := 0x20000000
## How far (in cells) a start may be from one a path was found from in the same step, to
## take that path too.
const SHARE_CELLS := 8
## Game steps at least between labelling a layer's regions afresh (NavGrid._relabel_if_cut).
const RELABEL_TICKS := 90
## Every bit an object footprint stamps into the grid.
const BLOCKED := SOLID | MARGIN | COVER

## Who moves where: walkers on the ground, boats on the water, and the canoe and swimmers
## (Native Americans with the Swim upgrade) on both.
enum Layer { GROUND, WATER, AMPHIBIOUS }

static var current: NavGrid

var size := Vector2i.ZERO
var flags := PackedInt32Array()
var has_water := false
## Counts footprints stamped or cleared, for units that gave up on a target out of reach to
## try again (Unit._chase).
var footprints_changed := 0
var _astar := AStarGrid2D.new()
var _layers: Array[AStarGrid2D] = []
## Connected regions per layer, so that a goal out of reach is known at once instead of by
## a search through every cell the start can reach: each cell's label (-1 where the layer
## was closed), the labels joined (union-find: a label's parent, the root its own). An
## opened cell joins its neighbours' regions at once; a closed one may cut a region in two,
## which the labels learn only when labelled afresh (_relabel_if_cut). So two cells with
## different roots are never connected; with the same root they may not be after all.
var _labels: Array[PackedInt32Array] = []
var _parents: Array[PackedInt32Array] = []
var _stale: Array[bool] = []  ## cells have closed since the labelling
var _labelled_tick: Array[int] = []
## Goals out of reach moved to the nearest cell in reach: (layer, start root, goal) -> cell,
## kept until the grid changes (many attackers going after the same target ask alike).
var _nearest_in_reach := {}
## Paths found in this game step, by layer and goal cell: [[start, waypoints, last cell], ...].
## Units sent the same way together (a squad ordered on one target) take the way one of
## them found from close by instead of searching and smoothing a long way each. Only in
## the step (Sim.stepping), so every machine shares alike.
var _paths := {}
var _paths_tick := -1


func setup(map: AlfMap) -> void:
	size = map.grid_size
	flags = map.grid_flags.duplicate()
	_lay_ramps(map)
	for value in flags:
		if value & WATER:
			has_water = true
			break
	for layer in Layer.size():
		var grid := _astar if layer == Layer.GROUND else AStarGrid2D.new()
		grid.region = Rect2i(Vector2i.ZERO, size)
		grid.cell_size = Vector2(CELL, CELL)
		grid.offset = Vector2(CELL, CELL) / 2.0
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.update()
		_layers.append(grid)
		_labels.append(PackedInt32Array())
		_parents.append(PackedInt32Array())
		_stale.append(false)
		_labelled_tick.append(0)
		if layer != Layer.GROUND and not has_water:
			continue  # dry maps: the other layers are never used
		for y in size.y:
			for x in size.x:
				if not _passable_flags(flags[y * size.x + x], layer):
					grid.set_point_solid(Vector2i(x, y))
		_label(layer)
		_labelled_tick[layer] = Sim.tick - RELABEL_TICKS  # free to label again from the start
	current = self


## Ramps between ground and plateau: the map has a cliff where each one stands, and the
## level editor's "_plateau" variant of the ramp (the one placed is drawn per biome and
## has no footprint) gives the cells that turn it into a slope from one level to the next.
func _lay_ramps(map: AlfMap) -> void:
	for placement in map.placements:
		var placed := ObjectTypes.get_type(placement.type_id)
		if placed == null or not placed.name.begins_with("ramp_") or placed.name.ends_with("_plateau"):
			continue
		var words := placed.name.split("_")
		var type := ObjectTypes.get_type(ObjectTypes.named("ramp_%s_%s_plateau" % [words[1], words[2]]))
		if type == null or type.footprint_cells.is_empty():
			continue
		var origin := cell_of(placement.position - Vector2(type.footprint_anchor))
		for i in type.footprint_cells.size():
			var value := type.footprint_cells[i]
			var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
			if value == 0 or not Rect2i(Vector2i.ZERO, size).has_point(cell):
				continue
			var index := cell.y * size.x + cell.x
			flags[index] = (flags[index] & ~GROUND) | value if value & WALKABLE else flags[index] | (value & SOLID)


static func _passable_flags(value: int, layer := Layer.GROUND) -> bool:
	if value & SOLID:
		return false
	match layer:
		Layer.WATER:
			return (value & WATER) != 0
		Layer.AMPHIBIOUS:
			return (value & (WALKABLE | WATER)) != 0
	return (value & WALKABLE) != 0


func _set_cell(cell: Vector2i) -> void:
	var value := flags[cell.y * size.x + cell.x]
	for layer in _layers.size():
		if layer == Layer.GROUND or has_water:
			var open := _passable_flags(value, layer)
			if open == _layers[layer].is_point_solid(cell):  # it opens or closes
				_layers[layer].set_point_solid(cell, not open)
				_nearest_in_reach.clear()
				_paths.clear()
				if open:
					_join(cell, layer)
				else:
					_stale[layer] = true


# ------------------------------------------------------------------ regions

## Label the layer's connected regions afresh (4-connected, as the paths go: a diagonal
## step needs both cells beside it open). One pass, joining each open cell to the open
## cells left of and above it: some 100 ms on the largest maps.
func _label(layer: int) -> void:
	var clock := Prof.start()
	var labels := PackedInt32Array()
	labels.resize(size.x * size.y)
	labels.fill(-1)
	var parents := PackedInt32Array()
	var footing: int = [WALKABLE, WATER, WALKABLE | WATER][layer]  # _passable_flags, inline
	var i := 0
	for y in size.y:
		for x in size.x:
			var value := flags[i]
			if (value & SOLID) == 0 and (value & footing) != 0:
				var left := labels[i - 1] if x > 0 else -1
				var up := labels[i - size.x] if y > 0 else -1
				if left < 0 and up < 0:
					labels[i] = parents.size()
					parents.append(parents.size())
				elif up < 0 or left == up:
					labels[i] = left
				else:
					labels[i] = up
					if left >= 0:
						_union(parents, left, up)
			i += 1
	_labels[layer] = labels
	_parents[layer] = parents
	_stale[layer] = false
	_labelled_tick[layer] = Sim.tick
	_nearest_in_reach.clear()  # by the old roots
	Prof.stop("nav regions", clock)


## An opened cell joins the regions round it into one.
func _join(cell: Vector2i, layer: int) -> void:
	var labels := _labels[layer]
	if labels.is_empty():
		return
	var index := cell.y * size.x + cell.x
	var joined := -1
	for side: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		var next := cell + side
		if not _astar.is_in_boundsv(next):
			continue
		var label := labels[next.y * size.x + next.x]
		if label < 0:
			continue
		if joined < 0:
			joined = label
		else:
			_union(_parents[layer], joined, label)
	if joined < 0:
		joined = _parents[layer].size()
		_parents[layer].append(joined)
	labels[index] = joined


static func _root(parents: PackedInt32Array, label: int) -> int:
	while parents[label] != label:
		parents[label] = parents[parents[label]]  # halve the way for the next look
		label = parents[label]
	return label


static func _union(parents: PackedInt32Array, a: int, b: int) -> void:
	a = _root(parents, a)
	b = _root(parents, b)
	if a != b:
		parents[maxi(a, b)] = mini(a, b)


## The region an open cell belongs to on the layer, or -1 for a closed one: cells in
## different regions are not connected (see _labels).
func region_of(cell: Vector2i, layer := Layer.GROUND) -> int:
	if not is_walkable(cell, layer) or _labels[layer].is_empty():
		return -1
	var label := _labels[layer][cell.y * size.x + cell.x]
	return _root(_parents[layer], label) if label >= 0 else -1


## A search fell short of a goal its region shares with the start: a closed cell (a wall
## built) has cut the region since it was labelled. Labelled afresh, the next search to a
## goal out of reach there knows it at once. Only in the game step, so every machine
## labels at the same time, and at most every RELABEL_TICKS.
func _relabel_if_cut(layer: Layer) -> void:
	if _stale[layer] and Sim.stepping and Sim.tick - _labelled_tick[layer] >= RELABEL_TICKS:
		_label(layer)


## Nearest cell to `goal` in region `region`: the rings round it a short way out, else
## the first such cell on the straight line from the goal back to `start` (which is in it).
func _nearest_in_region(goal: Vector2i, region: int, start: Vector2i, layer: Layer) -> Vector2i:
	var key := Vector4i(layer, region, goal.x, goal.y)
	var known = _nearest_in_reach.get(key)
	if known != null:
		return known
	var found := Vector2i(-1, -1)
	for r in range(1, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1, 1 if absi(dy) == r else 2 * r):
				if region_of(goal + Vector2i(dx, dy), layer) == region:
					found = goal + Vector2i(dx, dy)
					break
			if found.x >= 0:
				break
		if found.x >= 0:
			break
	if found.x < 0:
		var delta := start - goal
		var steps := maxi(absi(delta.x), absi(delta.y))
		found = start
		for s in range(1, steps):
			var cell := goal + Vector2i((Vector2(delta) * (float(s) / steps)).round())
			if region_of(cell, layer) == region:
				found = cell
				break
	_nearest_in_reach[key] = found
	return found


func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))


func is_walkable(cell: Vector2i, layer := Layer.GROUND) -> bool:
	return _astar.is_in_boundsv(cell) and not _layers[layer].is_point_solid(cell)


func is_water(cell: Vector2i) -> bool:
	return (flags_at(cell) & WATER) != 0 and (flags_at(cell) & SOLID) == 0


## Deep water: no footing at all (shallows and fords can be waded).
func is_deep_water(cell: Vector2i) -> bool:
	return is_water(cell) and (flags_at(cell) & WALKABLE) == 0


func flags_at(cell: Vector2i) -> int:
	return flags[cell.y * size.x + cell.x] if _astar.is_in_boundsv(cell) else SOLID


## Whether a new building's footprint cell (its own flags `own`) can go on `cell`: walls
## need open, uncovered ground clear of other buildings' margins; the margin only needs
## the ground not to be solid. `wall`: a wall piece, which may stand in a margin (up against
## a building, tree or cliff edge, so the wall closes there).
func can_build_on(cell: Vector2i, own: int, wall := false) -> bool:
	if not _astar.is_in_boundsv(cell):
		return false
	var there := flags_at(cell)
	if own & SOLID:
		return is_walkable(cell) and (there & (COVER if wall else MARGIN | COVER)) == 0
	return (there & SOLID) == 0


## Mark an object's footprint as blocked. The footprint grid's top-left is position - anchor.
func block_footprint(type: ObjectTypes.ObjectType, position: Vector2) -> void:
	if type == null or type.footprint_cells.is_empty():
		return
	footprints_changed += 1
	var origin := cell_of(position - Vector2(type.footprint_anchor))
	for i in type.footprint_cells.size():
		if (type.footprint_cells[i] & BLOCKED) == 0:
			continue
		var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
		if _astar.is_in_boundsv(cell):
			flags[cell.y * size.x + cell.x] |= type.footprint_cells[i] & BLOCKED
			_set_cell(cell)


## Clear an object's footprint again (e.g. a felled tree), keeping the ground's own flags.
func unblock_footprint(type: ObjectTypes.ObjectType, position: Vector2) -> void:
	if type == null or type.footprint_cells.is_empty():
		return
	footprints_changed += 1
	var origin := cell_of(position - Vector2(type.footprint_anchor))
	for i in type.footprint_cells.size():
		if (type.footprint_cells[i] & BLOCKED) == 0:
			continue
		var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
		if not _astar.is_in_boundsv(cell):
			continue
		var index := cell.y * size.x + cell.x
		flags[index] &= ~(type.footprint_cells[i] & BLOCKED)  # its own marks: a wall may share the cell
		_set_cell(cell)


## Nearest walkable cell to `cell` (spiral search), or `cell` itself if none nearby.
func nearest_walkable(cell: Vector2i, max_radius := 24, layer := Layer.GROUND) -> Vector2i:
	var found := nearest_passable(cell, max_radius, layer)
	return found if found.x >= 0 else cell


## Nearest cell of the layer within `max_radius` cells, or (-1, -1).
func nearest_passable(cell: Vector2i, max_radius := 24, layer := Layer.GROUND) -> Vector2i:
	if is_walkable(cell, layer):
		return cell
	for r in range(1, max_radius):
		for dy in range(-r, r + 1):
			# The ring alone, in the same order: its top and bottom rows whole, the two ends between.
			for dx in range(-r, r + 1, 1 if absi(dy) == r else 2 * r):
				if is_walkable(cell + Vector2i(dx, dy), layer):
					return cell + Vector2i(dx, dy)
	return Vector2i(-1, -1)


func center_of(cell: Vector2i) -> Vector2:
	return _center(cell)


## World-space waypoints from `from` to `to`, smoothed by line-of-sight. Empty if unreachable.
## A point off the map (the AI scripts work some out) heads for the nearest edge.
func find_path(from: Vector2, to: Vector2, layer := Layer.GROUND) -> PackedVector2Array:
	var clock := Prof.start()
	var points := _find_path(from, to, layer)
	Prof.stop("path search", clock)
	return points


func _find_path(from: Vector2, to: Vector2, layer: Layer) -> PackedVector2Array:
	var start := nearest_walkable(cell_of(from).clamp(Vector2i.ZERO, size - Vector2i.ONE), 24, layer)
	var goal := nearest_walkable(cell_of(to).clamp(Vector2i.ZERO, size - Vector2i.ONE), 24, layer)
	# A goal out of reach (up a cliff with no ramp to it, behind a wall, over the water)
	# gives the path to the nearest reachable cell instead: found from the regions, as a
	# search for the goal itself would go through every cell the start can reach first.
	var region := region_of(start, layer)
	if region >= 0 and region_of(goal, layer) != region:
		goal = _nearest_in_region(goal, region, start, layer)
	var points := PackedVector2Array()
	var last := goal
	var shared := _shared_way(start, goal, layer)
	if not shared.is_empty():
		points = shared[0]
		last = shared[1]
	else:
		var cells := _layers[layer].get_id_path(start, goal, true)
		if cells.is_empty():
			return points
		var anchor := start
		var i := 1
		while i < cells.size():
			# Skip ahead while the straight line from the anchor stays on walkable cells.
			var j := i
			while j + 1 < cells.size() and _line_clear(anchor, cells[j + 1], layer):
				j += 1
			points.append(_center(cells[j]))
			anchor = cells[j]
			i = j + 1
		last = cells[cells.size() - 1]
		if last != goal:
			_relabel_if_cut(layer)
		if Sim.stepping:
			_paths[Vector3i(layer, goal.x, goal.y)].append([start, points.duplicate(), last])
	var exact_goal := last == cell_of(to) and is_walkable(cell_of(to), layer)
	if exact_goal and not points.is_empty():
		points[points.size() - 1] = to
	return points


## A way found in this step to the same goal from a start near `start` (in a straight line
## from it), as [points, last cell]: from `start` to that start's first waypoint if that
## is in a straight line too, else by that start. [] when there is none.
func _shared_way(start: Vector2i, goal: Vector2i, layer: Layer) -> Array:
	if not Sim.stepping:
		return []
	if _paths_tick != Sim.tick:
		_paths_tick = Sim.tick
		_paths.clear()
	var key := Vector3i(layer, goal.x, goal.y)
	if not _paths.has(key):
		_paths[key] = []
	for entry: Array in _paths[key]:
		var from: Vector2i = entry[0]
		var offset := (from - start).abs()
		if maxi(offset.x, offset.y) > SHARE_CELLS or not _line_clear(start, from, layer):
			continue
		var points: PackedVector2Array = entry[1].duplicate()
		if from != start and (points.is_empty() or not _line_clear(start, cell_of(points[0]), layer)):
			points.insert(0, _center(from))
		return [points, entry[2]]
	return []


func _center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## Supercover line test between cell centres.
func _line_clear(a: Vector2i, b: Vector2i, layer := Layer.GROUND) -> bool:
	var delta := b - a
	var steps := maxi(absi(delta.x), absi(delta.y)) * 2
	if steps == 0:
		return true
	for s in range(1, steps + 1):
		var p := Vector2(a) + Vector2(delta) * (float(s) / steps)
		var c := Vector2i(roundi(p.x), roundi(p.y))
		if not is_walkable(c, layer):
			return false
		# Don't cut diagonal corners between two blocked cells.
		var f := Vector2i(floori(p.x), floori(p.y))
		if not is_walkable(f, layer) and not is_walkable(f + Vector2i.ONE, layer):
			return false
	return true
