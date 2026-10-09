class_name NavGrid
extends RefCounted
## Ground navigation on the original 16 px collision grid.
##
## Cell flags (map BITARRAY and object "BARY" footprints share them):
##   bits 0-2   walkable ground (cleared on cliff faces and water)
##   bit 6      blocked by a placed object
##   bit 7      terrain type
##   bits 12-13 height level
##   bits 29-31 blocked by an object (trees, rocks, buildings)

const CELL := 16
const WALKABLE := 0x2
const BLOCKED := 0x40 | 0xE0000000

static var current: NavGrid

var size := Vector2i.ZERO
var flags := PackedInt32Array()
var _astar := AStarGrid2D.new()


func setup(map: AlfMap) -> void:
	size = map.grid_size
	flags = map.grid_flags.duplicate()
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.offset = Vector2(CELL, CELL) / 2.0
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in size.y:
		for x in size.x:
			if not _passable_flags(flags[y * size.x + x]):
				_astar.set_point_solid(Vector2i(x, y))
	current = self


static func _passable_flags(value: int) -> bool:
	return (value & WALKABLE) != 0 and (value & BLOCKED) == 0


func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))


func is_walkable(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell)


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
			_astar.set_point_solid(cell)
			flags[cell.y * size.x + cell.x] |= type.footprint_cells[i] & BLOCKED


## Nearest walkable cell to `cell` (spiral search), or `cell` itself if none nearby.
func nearest_walkable(cell: Vector2i, max_radius := 24) -> Vector2i:
	if is_walkable(cell):
		return cell
	for r in range(1, max_radius):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and is_walkable(cell + Vector2i(dx, dy)):
					return cell + Vector2i(dx, dy)
	return cell


## World-space waypoints from `from` to `to`, smoothed by line-of-sight. Empty if unreachable.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := nearest_walkable(cell_of(from))
	var goal := nearest_walkable(cell_of(to))
	var cells := _astar.get_id_path(start, goal, true)
	if cells.is_empty():
		return PackedVector2Array()
	var points := PackedVector2Array()
	var anchor := start
	var i := 1
	while i < cells.size():
		# Skip ahead while the straight line from the anchor stays on walkable cells.
		var j := i
		while j + 1 < cells.size() and _line_clear(anchor, cells[j + 1]):
			j += 1
		points.append(_center(cells[j]))
		anchor = cells[j]
		i = j + 1
	var exact_goal := goal == cell_of(to) and is_walkable(cell_of(to))
	if exact_goal and not points.is_empty():
		points[points.size() - 1] = to
	return points


func _center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## Supercover line test between cell centres.
func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var delta := b - a
	var steps := maxi(absi(delta.x), absi(delta.y)) * 2
	if steps == 0:
		return true
	for s in range(1, steps + 1):
		var p := Vector2(a) + Vector2(delta) * (float(s) / steps)
		var c := Vector2i(roundi(p.x), roundi(p.y))
		if not is_walkable(c):
			return false
		# Don't cut diagonal corners between two blocked cells.
		var f := Vector2i(floori(p.x), floori(p.y))
		if not is_walkable(f) and not is_walkable(f + Vector2i.ONE):
			return false
	return true
