class_name BuildingDefence
extends RefCounted
## A building's defenders: units quartered inside forts and towers, safe from attack and
## shooting out at enemies; and the Native pitfall, crossed safely by its own people,
## deadly to enemies, hidden from them unless a detector sees it, spent after three kills.

## Firing from the walls or a platform reaches a quarter further than in the open, counted
## from the walls (not the middle of the building, which would eat most of it on a big fort).
const GARRISON_RANGE_FACTOR := 1.25
const PITFALL_GUID := 114
const PITFALL_KILLS := 3
const EXIT_ROW := 5  # spots per row below the building for units leaving quarters

var building: MapObject
var garrison: Array[Unit] = []
var trap_kills := 0
var _garrison_scan := 0.0
var _trap_scan := 0.0


func _init(owner: MapObject) -> void:
	building = owner


func capacity() -> int:
	if not building.complete or building.health <= 0.0:
		return 0
	return int(GameData.stats(building.guid).get("capacity", 0))


func has_room_for(unit: Unit) -> bool:
	return unit.team == building.owner_index and garrison.size() < capacity()


func enter(unit: Unit) -> bool:
	if not has_room_for(unit):
		return false
	garrison.append(unit)
	unit.enter_quarters(building)
	Sim.activate(building)
	building.redraw_overlay()
	return true


## Send quartered units back outside, below the building (all of them, or just `which`),
## each on a cell of its own: rows along the bottom wall, from the middle outwards.
func release(which: Unit = null) -> void:
	var taken := {}
	var slot := 0
	for unit in garrison.duplicate():
		if which != null and unit != which:
			continue
		garrison.erase(unit)
		if not is_instance_valid(unit) or not unit.is_alive():
			continue
		var spot := _exit_spot(slot, taken)
		slot += 1
		unit.leave_quarters(spot)


func _exit_spot(slot: int, taken: Dictionary) -> Vector2:
	var rect := building.footprint_rect()
	var column := slot % EXIT_ROW
	var offset := (column + 1) / 2 * (1 if column % 2 == 1 else -1)  # 0, +1, -1, +2, -2
	var spot := Vector2(rect.get_center().x + offset * 24.0, rect.end.y + 8.0 + slot / EXIT_ROW * 22.0)
	var nav := NavGrid.current
	if nav == null:
		return spot
	var want := nav.cell_of(spot)
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := want + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and nav.is_walkable(cell) and not taken.has(cell):
					taken[cell] = true
					return spot if cell == want else nav.center_of(cell)
	return nav.center_of(nav.nearest_walkable(want))


func update(delta: float) -> void:
	if not garrison.is_empty():
		_update_garrison(delta)
	if building.guid == PITFALL_GUID and building.complete and building.health > 0.0:
		_spring_trap(delta)


## Quartered riflemen and archers fire out at the nearest enemy each can reach.
func _update_garrison(delta: float) -> void:
	_garrison_scan -= delta
	for unit in garrison.duplicate():
		if not is_instance_valid(unit):
			garrison.erase(unit)
	if _garrison_scan > 0.0:
		return
	_garrison_scan = 0.25
	var walls := building.work_rect()
	var centre := walls.get_center()
	for unit in garrison:
		if not unit.unit_type.ranged or unit.unit_type.attack_anims.is_empty() or not unit.ready_to_fire():
			continue
		var reach := garrison_range(unit)
		var best: Node2D = null
		var best_distance := reach
		var loophole := centre
		for other: Unit in UnitGrid.near(centre, reach + walls.size.length() / 2.0):
			if other.is_alive() and not other.inside and other.team > 0 and other.team != building.owner_index:
				var edge := building.wall_point(other.position)
				var d := edge.distance_to(other.position)
				if d < best_distance:
					best = other
					best_distance = d
					loophole = edge
		if best:
			unit.fire_from_quarters(best, loophole, reach)


## How far a quartered unit shoots, from the walls.
static func garrison_range(unit: Unit) -> float:
	return unit.attack_range() * GARRISON_RANGE_FACTOR


func _spring_trap(delta: float) -> void:
	_trap_scan -= delta
	if _trap_scan > 0.0:
		return
	_trap_scan = 0.2
	var pit := building.footprint_rect().get_center()
	for unit: Unit in UnitGrid.near(pit, 30.0):
		if unit.is_alive() and unit.team > 0 and unit.team != building.owner_index and not unit.inside \
				and not unit.unit_type.is_transport() and unit.position.distance_to(pit) < 30.0:
			unit.take_damage(unit.max_health * 10.0, building, true)
			trap_kills += 1
			if trap_kills >= PITFALL_KILLS:
				building.health = 0.0
				building.condition.destroy()
				return
