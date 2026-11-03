class_name BuildingDefence
extends RefCounted
## A building's defenders: units quartered inside forts and towers, safe from attack and
## fighting out at enemies; and the Native pitfall, crossed safely by its own people,
## deadly to enemies, hidden from them unless a detector sees it, spent after two catches.
## Buildings never fight by themselves (no class overrides the building tick 0x40c070).

## A unit taking quarters (AmericaAddOn.exe 0x41a829..0x41a88e) stands at the middle of the
## building's rectangle and reaches its attack range plus half the rectangle's longer side
## (+0x3ec), measured from there (0x435ce4); its sight grows by half the shorter side when
## it is more than 64 px (+0x3dc). Its attack is the one it has outside, on its own reload
## (0x435d04 -> 0x436cc0): hand-to-hand fighters strike out too. It looks for enemy units
## only, from 16 px out (0x435fe8: 0x45d940 with 16, +0x3ec, class 2), never buildings.
const GARRISON_MIN_REACH := 16.0
const PITFALL_GUID := 114
## The pitfall (class 0x41e900, tick 0x41f2f0): every 100 ms it looks for an enemy unit
## within 48 px of it (0x45d940 with 0..0x30, class 2) and deals it 1000 points (vtable
## +0x44); then it springs for 2 s, catching nobody, and is gone after its second catch
## (0x41f3e8, `+0x6f8 >= 2`). It is disarmed while it is being dug (0x41ed08).
const PITFALL_KILLS := 2
const PITFALL_REACH := 48.0
const PITFALL_DAMAGE := 1000.0
const PITFALL_SCAN := 0.1
const PITFALL_SPRING := 2.0
const EXIT_ROW := 5  # spots per row below the building for units leaving quarters

var building: MapObject
var garrison: Array[Unit] = []
var trap_kills := 0  ## catches so far
var _garrison_scan := 0.0
var _trap_scan := 0.0
var _trap_spring := 0.0  ## seconds the sprung pitfall still needs before it is set again (or gone)


func _init(owner: MapObject) -> void:
	building = owner


func capacity() -> int:
	if not building.complete or building.health <= 0.0:
		return 0
	return int(MapRules.stats(building.owner_index, building.guid).get("capacity", 0))


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


## Quartered fighters fight out at the nearest enemy unit each can reach.
func _update_garrison(delta: float) -> void:
	_garrison_scan -= delta
	for i in garrison.size():
		if not is_instance_valid(garrison[i]):
			garrison.assign(garrison.filter(func(u) -> bool: return is_instance_valid(u)))
			break
	if _garrison_scan > 0.0:
		return
	_garrison_scan = 0.25
	var centre := building.ground_rect().get_center()
	for unit in garrison:
		if unit.unit_type.attack_anims.is_empty() or DefaultsData.WORKERS.has(unit.unit_type.guid()) \
				or not unit.ready_to_fire():
			continue
		var reach := garrison_range(unit, building)
		var best: Node2D = null
		var best_distance := reach
		for other: Unit in UnitGrid.near(centre, reach):
			if other.is_alive() and not other.inside and Diplomacy.hostile(building.owner_index, other.team) \
					and not other.animal.is_cow() and not other.animal.is_horse():
				var d := centre.distance_to(other.position)
				if d < best_distance and d > GARRISON_MIN_REACH:
					best = other
					best_distance = d
		if best:
			unit.fire_from_quarters(best, centre, reach)


## How far a unit quartered in `quarters` reaches, from the building's middle (0x41a854):
## its range plus half the longer side of the building's rectangle (its ground patch's).
static func garrison_range(unit: Unit, quarters: MapObject) -> float:
	var size := quarters.ground_rect().size
	return unit.attack_range() + maxf(size.x, size.y) / 2.0


## How far a unit quartered in `quarters` sees (0x41a85c): half the shorter side further.
static func garrison_sight(unit: Unit, quarters: MapObject) -> float:
	var sight := unit.sight()
	var size := quarters.ground_rect().size
	return sight + minf(size.x, size.y) / 2.0 if sight > 64.0 else sight


func _spring_trap(delta: float) -> void:
	if _trap_spring > 0.0:
		_trap_spring -= delta
		if _trap_spring <= 0.0 and trap_kills >= PITFALL_KILLS:
			building.condition.destroy()
		return
	_trap_scan -= delta
	if _trap_scan > 0.0:
		return
	_trap_scan = PITFALL_SCAN
	var pit := building.position
	var best: Unit = null
	var best_distance := PITFALL_REACH
	for unit: Unit in UnitGrid.near(pit, PITFALL_REACH):
		if unit.is_alive() and Diplomacy.hostile(building.owner_index, unit.team) and not unit.inside \
				and not unit.unit_type.is_transport():
			var d := unit.position.distance_to(pit)
			if d < best_distance:
				best = unit
				best_distance = d
	if best:
		best.take_damage(PITFALL_DAMAGE, building, true)
		trap_kills += 1
		_trap_spring = PITFALL_SPRING


func save_trap() -> float:
	return _trap_spring


func restore_trap(spring) -> void:
	_trap_spring = float(spring) if spring != null else 0.0
