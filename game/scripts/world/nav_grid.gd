class_name NavGrid
extends RefCounted
## Ground navigation on the original 16 px collision grid.
##
## Cell flags (map BITARRAY and object "BARY" footprints share them):
##   bits 0-2   walkable ground (cleared on cliff faces and deep water)
##   bit 3      water (deep, or shallow where the ground bits are set as well)
##   bit 6      blocked (cliffs, rocks painted into the map)
##   bit 7      terrain type
##   bits 12-13 height level
##   bit 29     cover: canopy or roof drawn over the ground (walkable)
##   bit 30     margin: a one-cell ring round buildings and mines that keeps other
##              buildings at a distance (walkable, so there is always a lane between them)
##   bit 31     solid: walls, mine entrances, tree trunks

const CELL := 16
const WALKABLE := 0x2
const WATER := 0x8
const SOLID := 0x40 | 0x80000000
const MARGIN := 0x40000000
const COVER := 0x20000000
## Every bit an object footprint stamps into the grid.
const BLOCKED := SOLID | MARGIN | COVER

## Who moves where: walkers on the ground, boats on the water, and the canoe and swimmers
## (Native Americans with the Swim upgrade) on both.
enum Layer { GROUND, WATER, AMPHIBIOUS }

static var current: NavGrid

var size := Vector2i.ZERO
var flags := PackedInt32Array()
var has_water := false
var _astar := AStarGrid2D.new()
var _layers: Array[AStarGrid2D] = []


func setup(map: AlfMap) -> void:
	size = map.grid_size
	flags = map.grid_flags.duplicate()
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
		if layer != Layer.GROUND and not has_water:
			continue  # dry maps: the other layers are never used
		for y in size.y:
			for x in size.x:
				if not _passable_flags(flags[y * size.x + x], layer):
					grid.set_point_solid(Vector2i(x, y))
	current = self


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
			_layers[layer].set_point_solid(cell, not _passable_flags(value, layer))


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
## the ground not to be solid.
func can_build_on(cell: Vector2i, own: int) -> bool:
	if not _astar.is_in_boundsv(cell):
		return false
	var there := flags_at(cell)
	if own & SOLID:
		return is_walkable(cell) and (there & (MARGIN | COVER)) == 0
	return (there & SOLID) == 0


## Mark an object's footprint as blocked. The footprint grid's top-left is position - anchor.
func block_footprint(type: ObjectTypes.ObjectType, position: Vector2) -> void:
	if type == null or type.footprint_cells.is_empty():
		return
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
	var origin := cell_of(position - Vector2(type.footprint_anchor))
	for i in type.footprint_cells.size():
		if (type.footprint_cells[i] & BLOCKED) == 0:
			continue
		var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
		if not _astar.is_in_boundsv(cell):
			continue
		var index := cell.y * size.x + cell.x
		flags[index] &= ~BLOCKED
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
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and is_walkable(cell + Vector2i(dx, dy), layer):
					return cell + Vector2i(dx, dy)
	return Vector2i(-1, -1)


func center_of(cell: Vector2i) -> Vector2:
	return _center(cell)


## World-space waypoints from `from` to `to`, smoothed by line-of-sight. Empty if unreachable.
func find_path(from: Vector2, to: Vector2, layer := Layer.GROUND) -> PackedVector2Array:
	var start := nearest_walkable(cell_of(from), 24, layer)
	var goal := nearest_walkable(cell_of(to), 24, layer)
	var cells := _layers[layer].get_id_path(start, goal, true)
	if cells.is_empty():
		return PackedVector2Array()
	var points := PackedVector2Array()
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
	var exact_goal := goal == cell_of(to) and is_walkable(cell_of(to), layer)
	if exact_goal and not points.is_empty():
		points[points.size() - 1] = to
	return points


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
