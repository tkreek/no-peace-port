class_name CoverGrid
extends RefCounted
## The objects a unit can be hidden behind (trees, buildings, mines, rocks: whatever is drawn
## standing, y-sorted with the units), bucketed by where they stand into 128 px cells, so
## the drawing can tell whether one is drawn over a unit's picture (UnitSprite then shows the
## unit through it). Rebuilt when objects come or go. Drawing only: the game never reads it.

const CELL := 128.0
## How far an object's picture reaches from where it stands: to either side, and up.
const REACH_SIDE := 224.0
const REACH_UP := 400.0

static var _cells := {}  # packed cell key -> Array of objects
static var _version := -1


static func _key(x: int, y: int) -> int:
	return (x + 4096) * 8192 + (y + 4096)


static func _refresh() -> void:
	if MapObject.roster_version == _version:
		return
	_version = MapObject.roster_version
	_cells.clear()
	for object in MapObject.all_objects:
		if object.is_ghost or object.z_index < 0:
			continue  # fields and ramps lie flat under everyone
		var key := _key(floori(object.position.x / CELL), floori(object.position.y / CELL))
		var bucket = _cells.get(key)
		if bucket == null:
			_cells[key] = [object]
		else:
			bucket.append(object)


## Whether an object drawn after a unit standing at `feet` (y-sorted further down) has a
## picture over `picture`, the unit's (world).
static func covered(feet: Vector2, picture: Rect2) -> bool:
	_refresh()
	for y in range(floori(feet.y / CELL), floori((picture.end.y + REACH_UP) / CELL) + 1):
		for x in range(floori((picture.position.x - REACH_SIDE) / CELL), floori((picture.end.x + REACH_SIDE) / CELL) + 1):
			var bucket = _cells.get(_key(x, y))
			if bucket == null:
				continue
			for object: MapObject in bucket:
				if object.position.y > feet.y and object.visual_rect().intersects(picture):
					return true
	return false
