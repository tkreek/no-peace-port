class_name UnitWater
extends UnitPart
## Water (manual 5): riverboats and rafts keep to the water, the canoe "can move across
## water and land" (and fights only on it), and Native infantry and travois swim once Swim
## is researched. Boats carry units across; those aboard shoot from the deck. When a boat
## sinks, its passengers drown unless they can swim.

const BOATS := [254, 454, 364]  # Mexican and American riverboats, the outlaws' raft
const CANOE := 154
const SWIM_UPGRADES := [914, 995]  # the base game's and the expansion's Swim
const BOAT_CAPACITY := {254: 10, 454: 10, 364: 8}  # the raft "transports up to 8 units"
const BOARD_REACH := 72.0
const LANDING_REACH := 7  # cells from the boat to dry land when unloading
## On deep water swimmers swim and the canoe paddles (its land sheets show it carried).
const WATER_ACTIONS := {"walk": ["swim", "paddle"], "idle": ["swim", "idle_water"], "die": ["die_water"]}

var passengers: Array[Unit] = []
var vessel: Unit  ## the boat this unit is heading for or sitting in
var _unload_at := Vector2.INF  ## where the passengers go once the boat reaches the shore
var _deck_scan := 0.0
var _boat := false


func _init(owner: Unit) -> void:
	super(owner)
	_boat = unit.unit_type.guid() in BOATS


func is_boat() -> bool:
	return _boat


func capacity() -> int:
	return BOAT_CAPACITY.get(unit.unit_type.guid(), 0)


func can_swim() -> bool:
	if unit.team <= 0 or unit.unit_type.mounted or unit.unit_type.anim_index("swim") < 0:
		return false
	var owner := player()
	return owner != null and SWIM_UPGRADES.any(func(u: int) -> bool: return owner.researched.has(u))


func nav_layer() -> NavGrid.Layer:
	if _boat:
		return NavGrid.Layer.WATER
	if unit.unit_type.guid() == CANOE or can_swim():
		return NavGrid.Layer.AMPHIBIOUS
	return NavGrid.Layer.GROUND


func on_water() -> bool:
	return NavGrid.current != null and NavGrid.current.is_deep_water(NavGrid.current.cell_of(unit.position))


## The canoe "can attack and defend itself on water"; carried over land it cannot fight.
func can_fight_here() -> bool:
	return unit.unit_type.guid() != CANOE or on_water()


## The sheet to show on water for a walk, idle or death animation.
func variant(action: String) -> String:
	if WATER_ACTIONS.has(action) and NavGrid.current and NavGrid.current.has_water and on_water():
		for wet in WATER_ACTIONS[action]:
			if unit.unit_type.anim_index(wet) >= 0:
				return wet
	return action


func clear_orders() -> void:
	_unload_at = Vector2.INF
	if unit.state != Unit.State.QUARTERED:
		vessel = null
	_refresh_busy()


func _refresh_busy() -> void:
	busy = vessel != null or not passengers.is_empty() or _unload_at != Vector2.INF


func update(delta: float) -> bool:
	if vessel != null and idle_or_moving():
		_update_board()
		if unit.state == Unit.State.QUARTERED:
			return true
	if not passengers.is_empty() or _unload_at != Vector2.INF:
		_update_boat(delta)
	return false


# ------------------------------------------------------------------ passengers

## Walk to the shore by the boat and climb aboard (the boat comes to meet them, see
## SelectionController.order_board).
func board(boat: Unit) -> void:
	if not unit.is_alive() or boat == null or not boat.water.is_boat() or boat.team != unit.team or _boat \
			or boat.water.passengers.size() >= boat.water.capacity():
		return
	unit.clear_orders()
	vessel = boat
	busy = true
	unit.state = Unit.State.MOVING
	unit.path = unit.find_path(boat.position)


func _update_board() -> void:
	if not is_instance_valid(vessel) or not vessel.is_alive() or vessel.water.passengers.size() >= vessel.water.capacity():
		vessel = null
		_refresh_busy()
		if unit.state == Unit.State.MOVING and unit.path.is_empty():
			unit.state = Unit.State.IDLE
		return
	if unit.position.distance_to(vessel.position) <= BOARD_REACH:
		vessel.water.take_aboard(unit)
		return
	approach(vessel.position, BOARD_REACH, Unit.REPATH_MS * 2)


func take_aboard(passenger: Unit) -> bool:
	if passengers.size() >= capacity() or passenger.team != unit.team:
		passenger.water.vessel = null
		passenger.water._refresh_busy()
		return false
	passengers.append(passenger)
	passenger.path.clear()
	passenger.target = null
	passenger.state = Unit.State.QUARTERED
	passenger.inside = true
	passenger.selected = false
	passenger.position = unit.position
	busy = true
	return true


## Sail to the shore nearest `point` and put the passengers ashore there.
func unload_at(point: Vector2) -> void:
	if not _boat or passengers.is_empty():
		return
	var nav := NavGrid.current
	var landing := point
	if nav:
		var cell := nav.nearest_passable(nav.cell_of(point), 40, NavGrid.Layer.WATER)
		if cell.x >= 0:
			landing = nav.center_of(cell)
	unit.move_to(landing)
	_unload_at = point
	busy = true
	if unit.path.is_empty():
		_disembark()


## Put everyone ashore on the dry land nearest the boat; false when there is none close.
func _disembark() -> bool:
	var nav := NavGrid.current
	if nav == null:
		return false
	var land := nav.nearest_passable(nav.cell_of(unit.position), LANDING_REACH, NavGrid.Layer.GROUND)
	if land.x < 0:
		return false
	var goal := _unload_at
	_unload_at = Vector2.INF
	var i := 0
	for passenger in passengers.duplicate():
		passengers.erase(passenger)
		if not is_instance_valid(passenger) or not passenger.is_alive():
			continue
		var spot := nav.center_of(nav.nearest_walkable(land + Vector2i(i % 3 - 1, i / 3), 6))
		passenger.water.vessel = null
		passenger.water._refresh_busy()
		passenger.leave_quarters(spot)
		if goal != Vector2.INF and goal.distance_to(spot) > 40.0:
			# Landing troops fight their way to where they were sent.
			var at := goal + Vector2((i % 3 - 1) * 26, (i / 3) * 24)
			if passenger.unit_type.attack_anims.is_empty():
				passenger.move_to(at)
			else:
				passenger.attack_move(at)
		i += 1
	_refresh_busy()
	return true


func _update_boat(delta: float) -> void:
	for passenger in passengers.duplicate():
		if not is_instance_valid(passenger):
			passengers.erase(passenger)
		else:
			passenger.position = unit.position
	if _unload_at != Vector2.INF and unit.state == Unit.State.IDLE and not _disembark():
		# No dry land at hand: put in at the nearest shore instead.
		var nav := NavGrid.current
		var land := nav.nearest_passable(nav.cell_of(unit.position), 40, NavGrid.Layer.GROUND)
		var water := nav.nearest_passable(land, 8, NavGrid.Layer.WATER) if land.x >= 0 else Vector2i(-1, -1)
		var goal := _unload_at
		if water.x >= 0 and nav.center_of(water).distance_to(unit.position) > 8.0:
			unit.move_to(nav.center_of(water))
			_unload_at = goal
		else:
			_unload_at = Vector2.INF
	_refresh_busy()
	# Those aboard shoot from the deck at the nearest enemy each can reach.
	_deck_scan -= delta
	if _deck_scan > 0.0 or passengers.is_empty():
		return
	_deck_scan = 0.25
	for passenger in passengers:
		if not passenger.unit_type.ranged or passenger.unit_type.attack_anims.is_empty() or not passenger.ready_to_fire():
			continue
		var best: Unit = null
		var best_distance := passenger.attack_range()
		for other: Unit in UnitGrid.near(unit.position, best_distance):
			if other.is_alive() and not other.inside and unit.is_enemy_of(other):
				var d := unit.position.distance_to(other.position)
				if d < best_distance:
					best = other
					best_distance = d
		if best:
			passenger.fire_from_quarters(best, unit.position, passenger.attack_range())


## The boat goes down: swimmers make for the shore, the rest drown.
func sink() -> void:
	for passenger in passengers:
		if not is_instance_valid(passenger) or not passenger.is_alive():
			continue
		passenger.water.vessel = null
		passenger.water._refresh_busy()
		passenger.leave_quarters(unit.position + Vector2(randf_range(-16, 16), randf_range(-10, 10)))
		if not passenger.water.can_swim():
			passenger.health = 0.0
			passenger.die()
	passengers.clear()
