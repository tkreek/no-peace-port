class_name UnitGrid
extends RefCounted
## Units bucketed into 128 px cells, rebuilt at most once a game step (Sim), so that "who is near
## here" looks at a few cells instead of every unit on the map. Answers are candidates:
## callers still check the exact distance.

const CELL := 128.0

static var _cells := {}  # packed cell key -> Array of units
static var _tick := -1


static func _key(x: int, y: int) -> int:
	return (x + 4096) * 8192 + (y + 4096)


static func _refresh() -> void:
	if Sim.tick == _tick:
		return
	_tick = Sim.tick
	_cells.clear()
	for unit in Unit.all_units:
		var key := _key(floori(unit.position.x / CELL), floori(unit.position.y / CELL))
		var bucket: Array = _cells.get(key, [])
		if bucket.is_empty():
			_cells[key] = bucket
		bucket.append(unit)


## Units in the cells overlapping the square of `radius` round `at`.
static func near(at: Vector2, radius: float) -> Array:
	_refresh()
	radius = minf(radius, 4096.0)
	var out := []
	var low_x := floori((at.x - radius) / CELL)
	var high_x := floori((at.x + radius) / CELL)
	var low_y := floori((at.y - radius) / CELL)
	var high_y := floori((at.y + radius) / CELL)
	for y in range(low_y, high_y + 1):
		for x in range(low_x, high_x + 1):
			var bucket = _cells.get(_key(x, y))
			if bucket != null:
				out.append_array(bucket)
	return out


## Drop the cached cells (a unit was added or removed mid-step and must be seen at once).
static func invalidate() -> void:
	_tick = -1
