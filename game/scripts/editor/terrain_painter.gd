class_name TerrainPainter
extends RefCounted
## Paints terrain materials the way the expansion's level editor lays them out.
##
## The map is tiled with 64 px blocks (2x2 atlas tiles) in columns that start at odd cell
## columns, every other column shifted down by half a block (column k starts on rows of
## parity k + 1). Each block therefore meets its neighbours at six lattice points: the top,
## middle and bottom of its left and right edges. A material is painted on those points;
## a block whose points all hold one material gets one of that material's plain blocks, a
## block between two neighbouring materials the transition whose shape code (TerrainRules
## .SHAPES) matches which points hold which. Neighbouring points may only hold materials
## that blend into each other, so painting water into grass grows the shore and shallow
## water rings in between.

var rules: TerrainRules
var map: AlfMap
var columns := 0  ## lattice columns: edges e = -1 .. columns - 2
var rows := 0  ## lattice rows: j = -1 .. rows - 2 (one every 32 px)
var points := PackedByteArray()
var _pinned := {}


func _init(terrain_rules: TerrainRules, alf_map: AlfMap) -> void:
	rules = terrain_rules
	map = alf_map
	columns = map.columns / 2 + 3
	rows = map.rows + 3
	points.resize(columns * rows)
	points.fill(TerrainRules.UNKNOWN)


## Fill the whole map with one material.
func fill(material: int) -> void:
	points.fill(material)
	for block in all_blocks():
		_render(block)


## Read the materials back from the map's tiles (blocks the rules do not know, such as
## cliffs, keep their tiles until painted over).
func read_map() -> void:
	# Every lattice point is the middle of one block's edge, which shows it faithfully; at a
	# block's corners a lone point may be left out of the picture (see _render).
	for corners_too in [false, true]:
		for block in all_blocks():
			var cell := _first_cell(block)
			if cell.x < 0:
				continue
			var shape: Vector4i = rules.tile_shape.get(map.tile_ids[cell.y * map.columns + cell.x], Vector4i(-1, -1, -1, -1))
			if shape.x < 0:
				continue
			var pattern := "AAAAAA"
			if shape.y >= 0 and TerrainRules.SHAPES.values().has(shape.z):
				pattern = TerrainRules.SHAPES.find_key(shape.z)
			var corners := _corners(block)
			for i in 6:
				var middle := i == 2 or i == 3
				if middle == corners_too or not _valid(corners[i]):
					continue
				if corners_too and _get_point(corners[i]) != TerrainRules.UNKNOWN:
					continue
				_set_point(corners[i], shape.x if pattern[i] == "A" or shape.y < 0 else shape.y)


## Paint `material` on the lattice points within `radius` px of `at`. Returns the changed
## map cells (to redraw), or an empty rect.
func paint(at: Vector2, radius: float, material: int) -> Rect2i:
	_pinned.clear()
	var low := lattice_of(at - Vector2(radius, radius))
	var high := lattice_of(at + Vector2(radius, radius))
	var changed := {}
	for e in range(low.x - 1, high.x + 2):
		for j in range(low.y - 1, high.y + 2):
			var point := Vector2i(e, j)
			if not _valid(point) or point_position(point).distance_to(at) > radius:
				continue
			_pinned[point] = true
			if _get_point(point) != material:
				_set_point(point, material)
				changed[point] = true
	if _pinned.is_empty():
		var nearest := lattice_of(at)
		if _valid(nearest):
			_pinned[nearest] = true
			if _get_point(nearest) != material:
				_set_point(nearest, material)
				changed[nearest] = true
	if changed.is_empty():
		return Rect2i()
	_settle(changed)
	return _render_around(changed)


## Lattice point nearest to a map position.
func lattice_of(at: Vector2) -> Vector2i:
	return Vector2i(roundi((at.x / 32.0 - 1.0) / 2.0), roundi(at.y / 32.0))


func point_position(point: Vector2i) -> Vector2:
	return Vector2((2 * point.x + 1) * 32, point.y * 32)


func material_at(at: Vector2) -> int:
	var point := lattice_of(at)
	return _get_point(point) if _valid(point) else TerrainRules.UNKNOWN


## Every block that touches the map: Vector2i(column k, top row).
func all_blocks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in range(-1, map.columns / 2 + 1):
		var y := -1 if posmod(k + 1, 2) == 1 else 0
		while y < map.rows:
			out.append(Vector2i(k, y))
			y += 2
	return out


# ------------------------------------------------------------------ lattice

func _valid(point: Vector2i) -> bool:
	return point.x >= -1 and point.x < columns - 1 and point.y >= -1 and point.y < rows - 1


func _get_point(point: Vector2i) -> int:
	return points[(point.y + 1) * columns + point.x + 1]


func _set_point(point: Vector2i, material: int) -> void:
	if _valid(point):
		points[(point.y + 1) * columns + point.x + 1] = material


## A block's points in the order of the shape patterns: TL, TR, ML, MR, BL, BR.
func _corners(block: Vector2i) -> Array[Vector2i]:
	var k := block.x
	var y := block.y
	return [Vector2i(k, y), Vector2i(k + 1, y), Vector2i(k, y + 1), Vector2i(k + 1, y + 1),
			Vector2i(k, y + 2), Vector2i(k + 1, y + 2)]


## The blocks a lattice point belongs to (on their left or right edge).
func _blocks_of(point: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in [point.x - 1, point.x]:
		for y in range(point.y - 2, point.y + 1):
			if posmod(y, 2) == posmod(k + 1, 2):
				out.append(Vector2i(k, y))
	return out


## Make every pair of points in a block blend: a point next to one more than a step away
## along the blend graph moves one step towards it (rings of the materials in between grow
## outwards from the brush). Points the brush just painted stay as they are.
func _settle(changed: Dictionary) -> void:
	var queue: Array = changed.keys()
	var guard := 0
	while not queue.is_empty() and guard < 400000:
		guard += 1
		var point: Vector2i = queue.pop_front()
		var material := _get_point(point)
		if material == TerrainRules.UNKNOWN:
			continue
		for block in _blocks_of(point):
			for other in _corners(block):
				if other == point or not _valid(other):
					continue
				var theirs := _get_point(other)
				if theirs == TerrainRules.UNKNOWN or rules.distance(material, theirs) <= 1:
					continue
				var mover := other
				var anchor := material
				var moving := theirs
				if _pinned.has(other):
					if _pinned.has(point):
						continue
					mover = point
					anchor = theirs
					moving = material
				var route := rules.path(anchor, moving)
				_set_point(mover, route[1] if route.size() > 1 else anchor)
				changed[mover] = true
				queue.append(mover)
				if mover == point:
					break
			if _get_point(point) != material:
				queue.append(point)
				break


## The (A, B) material pair of a block's six materials as the rules order it, (m, -1) for
## a single material, or (-1, -1) when they do not form a pair.
func _pair_of(mats: Array[int]) -> Vector2i:
	var seen: Array[int] = []
	for m in mats:
		if m != TerrainRules.UNKNOWN and m not in seen:
			seen.append(m)
	if seen.size() == 1:
		return Vector2i(seen[0], -1)
	if seen.size() != 2:
		return Vector2i(-1, -1)
	if rules.blocks.has(Vector2i(seen[0], seen[1])):
		return Vector2i(seen[0], seen[1])
	if rules.blocks.has(Vector2i(seen[1], seen[0])):
		return Vector2i(seen[1], seen[0])
	return Vector2i(-1, -1)


# ------------------------------------------------------------------ tiles

func _render_around(changed: Dictionary) -> Rect2i:
	var blocks := {}
	for point in changed:
		for block in _blocks_of(point):
			blocks[block] = true
	var dirty := Rect2i()
	for block in blocks:
		if _render(block):
			var rect := Rect2i(2 * block.x + 1, block.y, 2, 2).intersection(Rect2i(0, 0, map.columns, map.rows))
			dirty = rect if dirty.size == Vector2i.ZERO else dirty.merge(rect)
	return dirty


## Pick the block's tiles from its points; false when it has no piece (left as it was).
func _render(block: Vector2i) -> bool:
	var mats: Array[int] = []
	for point in _corners(block):
		mats.append(_get_point(point) if _valid(point) else TerrainRules.UNKNOWN)
	var pair := _pair_of(mats)
	if pair.x < 0:
		return false
	var choices: Array = []
	var code := TerrainRules.PLAIN
	if pair.y < 0:
		choices = rules.plain.get(pair.x, [])
	else:
		var pattern := ""
		for m in mats:
			pattern += "B" if m == pair.y else "A"
		pattern = _drawable(pattern)
		if pattern == "AAAAAA" or pattern == "BBBBBB":
			choices = rules.plain.get(pair.x if pattern[0] == "A" else pair.y, [])
		else:
			code = TerrainRules.SHAPES[pattern]
			choices = rules.blocks[pair].get(code, [])
	if choices.is_empty():
		return false
	var tiles: Array = choices[posmod(hash(block), choices.size())]
	for q in 4:
		var cell := Vector2i(2 * block.x + 1 + q % 2, block.y + q / 2)
		if cell.x < 0 or cell.y < 0 or cell.x >= map.columns or cell.y >= map.rows:
			continue
		var index := cell.y * map.columns + cell.x
		map.tile_ids[index] = tiles[q]
		map.tile_codes[index] = code
	return true


## The pattern itself when the rules have a piece for it, else the nearest one that only
## differs at the corners where it can: a lone point at a block's corner is the middle of
## the neighbouring block's edge, whose piece shows it as a bump.
func _drawable(pattern: String) -> String:
	if pattern == "AAAAAA" or pattern == "BBBBBB" or TerrainRules.SHAPES.has(pattern):
		return pattern
	var best := pattern
	var best_cost := 999
	for candidate: String in TerrainRules.SHAPES.keys() + ["AAAAAA", "BBBBBB"]:
		var cost := 0
		for i in 6:
			if candidate[i] != pattern[i]:
				cost += 10 if i == 2 or i == 3 else 1
		if cost < best_cost:
			best_cost = cost
			best = candidate
	return best


func _first_cell(block: Vector2i) -> Vector2i:
	for q in 4:
		var cell := Vector2i(2 * block.x + 1 + q % 2, block.y + q / 2)
		if cell.x >= 0 and cell.y >= 0 and cell.x < map.columns and cell.y < map.rows:
			return cell
	return Vector2i(-1, -1)


## The collision grid for the painted tiles (objects stamp their footprints in when the
## game places them).
func write_flags() -> void:
	map.grid_size = Vector2i(map.columns * 2, map.rows * 2)
	map.grid_flags.resize(map.grid_size.x * map.grid_size.y)
	for i in map.tile_ids.size():
		var x := (i % map.columns) * 2
		var y := (i / map.columns) * 2
		for q in 4:
			map.grid_flags[(y + q / 2) * map.grid_size.x + x + q % 2] = rules.tile_flags(map.tile_ids[i], q)
