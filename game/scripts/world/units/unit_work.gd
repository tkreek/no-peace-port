class_name UnitWork
extends UnitPart
## Work: gathering wood, gold and food and carrying it to a drop-off; hauling gold from
## warehouses (and abandoned stores) to the main building; building and repairing;
## hunting and butchering; robbing buildings and stealing transports (manual 3.9).

enum Phase { TO_SOURCE, WORKING, TO_DROP_OFF }

const WORK_SECONDS := {"wood": 4.0, "gold": 5.0, "food": 5.0}
const HUNT_RANGE := 1500.0
const BUTCHER_SECONDS := 2.0
const MEAT_PER_TRIP := 30  # a hunter carries this much home per trip; carcasses last several
## Robbing banks, missions and gold warehouses, and stealing transports: unit GUID -> the
## upgrade it needs (0 = none; the outlaws are born robbers).
const ROBBERS := {152: 916, 155: 916, 252: 941, 255: 941, 452: 991, 455: 991, 456: 991,
		352: 0, 355: 0, 360: 0, 361: 0}
const THIEVES := {156: 0, 157: 0, 263: 942, 264: 942, 463: 992, 464: 992, 353: 0, 354: 0,
		352: 0, 360: 0, 361: 0}
const ROB_SECONDS := 4.0  # inside the building, filling the bags
const STEAL_SECONDS := 4.0  # beside the vehicle before it changes hands

var carrying := ""  ## resource in hand ("" when empty-handed)
var carried := 0
var gather_resource := ""  ## what this unit is assigned to collect ("haul", "rob" and "meat" too)
var gather_source: MapObject
var build_site: MapObject
var hunting := false  ## the target is an animal; carry the meat home after the kill
var phase := Phase.TO_SOURCE
var _work_timer := 0.0
var _drop_off: MapObject
var _haul_wait := 0.0
var _field_spot := Vector2.INF  # this unit's patch of the field it works
var _field_spot_of: MapObject
var _carcass: Unit  # the kill a hunter keeps going back to
var _steal_target: Unit
var _steal_time := 0.0


func clear_orders() -> void:
	_steal_target = null
	busy = false


func update(delta: float) -> bool:
	if _steal_target != null and idle_or_moving():
		_update_steal(delta)
	return false


# ------------------------------------------------------------------ orders

## Harvest `source` repeatedly, carrying loads to the nearest drop-off.
func gather(source: MapObject) -> void:
	if not unit.is_alive() or source == null or not unit.unit_type.can_gather(source.stock.resource):
		return
	if carrying != "" and carrying != source.stock.resource:
		carrying = ""
		carried = 0
	unit.clear_orders()
	gather_source = source
	gather_resource = source.stock.resource
	unit.target = null
	unit.state = Unit.State.GATHERING
	phase = Phase.TO_DROP_OFF if carried >= unit.unit_type.carry else Phase.TO_SOURCE
	_route()


## Shuttle gold from a gold warehouse to the main building for as long as it holds any;
## an empty warehouse is waited at, since the miners keep filling it.
func haul(warehouse: MapObject) -> void:
	if not unit.is_alive() or warehouse == null or not unit.unit_type.is_transport() \
			or not unit.tepees.packed.is_empty() \
			or (warehouse.owner_index != unit.team and not warehouse.is_abandoned_store()):
		return
	unit.clear_orders()
	gather_source = warehouse
	gather_resource = "haul"
	unit.target = null
	unit.state = Unit.State.GATHERING
	phase = Phase.TO_DROP_OFF if carried > 0 else Phase.TO_SOURCE
	unit.path = unit.find_path(warehouse.work_rect().get_center()) if carried == 0 else PackedVector2Array()


## Build a construction site, or repair a damaged finished building.
func build(site: MapObject) -> void:
	if not unit.is_alive() or site == null or not unit.unit_type.can_build(site.guid) \
			or (site.complete and not site.condition.needs_repair()):
		return
	unit.clear_orders()
	build_site = site
	unit.target = null
	gather_source = null
	unit.inside = false
	unit.state = Unit.State.BUILDING
	unit.path = unit.find_path(site.position)


## Kill an animal and carry its meat to a butcher or the main building, then hunt again.
## Horses are hunted only when ordered, and never by Native Americans, for whom they are
## too valuable as mounts (manual 3.10).
func hunt(animal: Unit) -> void:
	if not unit.unit_type.is_hunter() or animal == null or animal.team != 0 or not animal.animal.has_meat():
		return
	if animal.animal.is_horse() and animal.is_alive() and not may_hunt_horses():
		return
	unit.clear_orders()
	if animal.is_alive():
		unit.attack(animal)
	else:
		# Back to a carcass: walk over and cut off the next load.
		unit.target = animal
		gather_source = null
		unit.inside = false
		unit._attack_step = -1
		unit.state = Unit.State.ATTACKING
		unit.path.clear()
	hunting = true
	_work_timer = BUTCHER_SECONDS


func may_hunt_horses() -> bool:
	var owner := player()
	return unit.unit_type.is_hunter() and (owner == null or owner.faction != "ind")


func _may(table: Dictionary) -> bool:
	var me := unit.unit_type.guid()
	if not table.has(me):
		return false
	var owner := player()
	return table[me] == 0 or (owner != null and owner.researched.has(table[me]))


func can_rob() -> bool:
	return _may(ROBBERS)


func can_steal() -> bool:
	return _may(THIEVES)


## Gold an enemy building holds for the taking: a gold warehouse's store, or for a bank or
## mission its owner's treasury.
static func loot_of(building: MapObject) -> int:
	if building.is_gold_warehouse():
		return building.stock.stored_gold
	if building.guid in BuildingProduction.INCOME_BUILDINGS:
		var owner: Player = Player.by_index.get(building.owner_index)
		return int(owner.resources.get("gold", 0)) if owner else 0
	return 0


func rob(building: MapObject) -> void:
	if not unit.is_alive() or building == null or not can_rob():
		return
	unit.clear_orders()
	gather_source = building
	gather_resource = "rob"
	unit.target = null
	unit.state = Unit.State.GATHERING
	phase = Phase.TO_SOURCE
	unit.path = unit.find_path(building.work_rect().get_center())


func steal(vehicle: Unit) -> void:
	if not unit.is_alive() or vehicle == null or not can_steal() or not vehicle.unit_type.is_transport():
		return
	unit.clear_orders()
	_steal_target = vehicle
	_steal_time = 0.0
	busy = true
	unit.state = Unit.State.MOVING
	unit.path = unit.find_path(vehicle.position)


func stop() -> void:
	gather_source = null
	build_site = null


# ------------------------------------------------------------------ the work itself

## The GATHERING state: gathering, hauling or robbing.
func update_gathering(delta: float) -> void:
	match gather_resource:
		"haul":
			_update_haul(delta)
		"rob":
			_update_rob(delta)
		_:
			_update_gather(delta)


func walk_action() -> String:
	if carrying != "" and unit.unit_type.anim_index("carry_" + carrying) >= 0:
		return "carry_" + carrying
	return "walk"


func idle_action() -> String:
	if carrying != "" and unit.unit_type.anim_index("carry_%s_idle" % carrying) >= 0:
		return "carry_%s_idle" % carrying
	return "idle"


func _update_gather(delta: float) -> void:
	match phase:
		Phase.TO_SOURCE:
			if not _source_valid():
				gather_source = nearest_source(_last_resource(), 1200.0)
				if gather_source == null:
					unit.state = Unit.State.IDLE
					return
				_route()
			unit.follow_path(delta)
			unit.play(walk_action())
			var arrived := gather_source.near_walls(unit.position, Unit.REACH)
			if gather_source.is_field():
				arrived = unit.position.distance_to(_work_spot()) < 10.0
			if arrived or unit.path.is_empty():
				unit.path.clear()
				phase = Phase.WORKING
				var faster := unit.bonus("chop_pct") if gather_source.stock.resource == "wood" else unit.bonus("mine_pct")
				if gather_source.stock.resource == "food":
					faster = 0.0
				_work_timer = WORK_SECONDS.get(gather_source.stock.resource, 4.0) / (1.0 + faster / 100.0) \
						/ unit.morale() / unit.effectiveness()
				unit.face(gather_source.work_rect().get_center() - unit.position)
				if gather_source.stock.resource == "gold":
					unit.inside = true  # workers go inside the mine
		Phase.WORKING:
			if not _source_valid():
				# Felled or emptied by someone else: find the next source.
				unit.inside = false
				gather_source = null
				phase = Phase.TO_SOURCE
				return
			if gather_source.is_field() and gather_source.stock.field_state != ObjectStock.Field.RIPE:
				unit.play_repeating("sow")  # sow the fallow field, tend the growing crop
				if gather_source.stock.field_state == ObjectStock.Field.FALLOW:
					gather_source.stock.sow(delta)
				return
			if gather_source.stock.resource == "food":
				unit.play_repeating("harvest")
			elif gather_source.is_mine():
				gather_source.stock.add_mine_work(delta)
			_work_timer -= delta
			if gather_source.stock.resource == "wood" and unit.play_repeating("chop"):
				Sound.play_event(unit.unit_type.guid(), Sound.Event.CHOP, unit.position, 300, unit.get_instance_id(), Sound.WORK_RANGE)
			if _work_timer > 0.0:
				return
			var resource := gather_source.stock.resource
			var got := gather_source.stock.harvest(unit.unit_type.carry)
			unit.inside = false
			if got > 0:
				carrying = resource
				carried = got
			phase = Phase.TO_DROP_OFF if carried > 0 else Phase.TO_SOURCE
			_route()
		Phase.TO_DROP_OFF:
			if _drop_off == null or not is_instance_valid(_drop_off):
				_route()
				if _drop_off == null:
					unit.state = Unit.State.IDLE
					return
			unit.follow_path(delta)
			unit.play(walk_action())
			if _drop_off.near_walls(unit.position, Unit.REACH) or unit.path.is_empty():
				unit.path.clear()
				_deliver()
				if gather_resource == "meat":
					var next: Unit = _carcass if is_instance_valid(_carcass) and _carcass.animal.has_meat() else nearest_animal()
					gather_resource = ""
					if next:
						hunt(next)
					else:
						unit.state = Unit.State.IDLE
					return
				phase = Phase.TO_SOURCE
				_route()


## Hand the load over at the drop-off (gold at a gold warehouse waits for a wagon).
func _deliver() -> void:
	var owner := player()
	if owner and carried > 0:
		if carrying == "gold" and _drop_off.is_gold_warehouse():
			_drop_off.stock.store_gold(carried)
		else:
			owner.add(carrying, carried)
		owner.stats.gathered += carried
		unit.gain_experience(Unit.EXPERIENCE_PER_LOAD)
	carried = 0
	carrying = ""  # walk back empty-handed


func _update_haul(delta: float) -> void:
	if gather_source == null or not is_instance_valid(gather_source) or not gather_source.is_alive():
		gather_source = null
		if carried == 0:
			unit.state = Unit.State.IDLE
			return
		phase = Phase.TO_DROP_OFF
	match phase:
		Phase.TO_SOURCE:
			if unit.path.is_empty() and not gather_source.near_walls(unit.position, Unit.REACH * 2):
				unit.path = unit.find_path(gather_source.work_rect().get_center())
			unit.follow_path(delta)
			unit.play(walk_action())
			if gather_source.near_walls(unit.position, Unit.REACH * 2) or unit.path.is_empty():
				unit.path.clear()
				phase = Phase.WORKING
				_work_timer = 1.0
		Phase.WORKING:
			unit.play("idle")
			_work_timer -= delta
			_haul_wait += delta
			# Leave with a full load, or whatever there is after a while.
			if _work_timer > 0.0 or (gather_source.stock.haul_available() < unit.unit_type.carry and _haul_wait < 8.0 \
					and not gather_source.is_abandoned_store()):
				return
			carried = gather_source.stock.take_haul(unit.unit_type.carry)
			if carried <= 0 and gather_source.is_abandoned_store():
				unit.stop()  # emptied
				return
			if carried <= 0:
				_work_timer = 2.0  # wait for the miners
				return
			_haul_wait = 0.0
			carrying = gather_source.stock.haul_kind()
			phase = Phase.TO_DROP_OFF
			_drop_off = main_building()
			unit.path = unit.find_path(_drop_off.position) if _drop_off else PackedVector2Array()
		Phase.TO_DROP_OFF:
			if _drop_off == null or not is_instance_valid(_drop_off):
				_drop_off = main_building()
				if _drop_off == null:
					unit.state = Unit.State.IDLE
					return
				unit.path = unit.find_path(_drop_off.position)
			unit.follow_path(delta)
			unit.play(walk_action())
			if _drop_off.near_walls(unit.position, Unit.REACH * 2) or unit.path.is_empty():
				unit.path.clear()
				var owner := player()
				if owner and carried > 0:
					owner.add(carrying, carried)
				carried = 0
				carrying = ""
				if gather_source and is_instance_valid(gather_source):
					phase = Phase.TO_SOURCE
					unit.path = unit.find_path(gather_source.work_rect().get_center())
				else:
					unit.state = Unit.State.IDLE


func _update_rob(delta: float) -> void:
	var building := gather_source
	if phase != Phase.TO_DROP_OFF and (building == null or not is_instance_valid(building) or not building.is_alive()):
		unit.inside = false
		unit.stop()
		return
	match phase:
		Phase.TO_SOURCE:
			unit.follow_path(delta)
			unit.play(walk_action())
			if building.near_walls(unit.position, Unit.REACH * 2) or unit.path.is_empty():
				unit.path.clear()
				if loot_of(building) <= 0:
					unit.stop()
					return
				phase = Phase.WORKING
				_work_timer = ROB_SECONDS
				unit.inside = true
		Phase.WORKING:
			_work_timer -= delta
			if _work_timer > 0.0:
				return
			unit.inside = false
			var bags := unit.unit_type.carry * (1 if unit.unit_type.is_transport() else 3)
			carried = mini(bags, loot_of(building))
			if building.is_gold_warehouse():
				building.stock.take_gold(carried)
			else:
				var victim: Player = Player.by_index.get(building.owner_index)
				if victim:
					victim.add("gold", -carried)
			carrying = "gold"
			phase = Phase.TO_DROP_OFF
			_drop_off = main_building()
			unit.path = unit.find_path(_drop_off.position) if _drop_off else PackedVector2Array()
		Phase.TO_DROP_OFF:
			if _drop_off == null or not is_instance_valid(_drop_off):
				unit.stop()
				return
			unit.follow_path(delta)
			unit.play(walk_action())
			if _drop_off.near_walls(unit.position, Unit.REACH * 2) or unit.path.is_empty():
				var owner := player()
				if owner and carried > 0:
					owner.add("gold", carried)
				carried = 0
				carrying = ""
				if is_instance_valid(building) and building.is_alive() and loot_of(building) > 0:
					phase = Phase.TO_SOURCE
					unit.path = unit.find_path(building.work_rect().get_center())
				else:
					unit.stop()


## Stay beside the vehicle; once it has been quiet long enough it is ours, cargo and all.
func _update_steal(delta: float) -> void:
	var vehicle := _steal_target
	if not is_instance_valid(vehicle) or not vehicle.is_alive() or vehicle.team == unit.team:
		_steal_target = null
		busy = false
		return
	var distance := unit.position.distance_to(vehicle.position)
	if distance > 160.0:
		_steal_time = 0.0  # it got away
	if distance <= 100.0:
		_steal_time += delta  # alongside, even on the move
	if distance > 36.0:
		approach(vehicle.position, 36.0, Unit.REPATH_MS / 2)
	else:
		unit.path.clear()
		unit.state = Unit.State.IDLE
		unit.face(vehicle.position - unit.position)
	if _steal_time >= STEAL_SECONDS:
		vehicle.change_team(unit.team)
		_steal_target = null
		busy = false


## The BUILDING state: walk to the site and hammer (or repair) until it is done.
func update_building(delta: float) -> void:
	if build_site == null or not is_instance_valid(build_site) or not build_site.is_alive() \
			or (build_site.complete and not build_site.condition.needs_repair()):
		build_site = null
		unit.state = Unit.State.IDLE
		return
	if not build_site.near_walls(unit.position, Unit.REACH):
		if unit.path.is_empty():
			unit.path = unit.find_path(build_site.position)
		unit.follow_path(delta)
		unit.play(walk_action())
		if not unit.path.is_empty():
			return
	unit.path.clear()
	unit.face(build_site.work_rect().get_center() - unit.position)
	# Women without a hammering animation swing their axe instead.
	unit.play_repeating("build" if unit.unit_type.anim_index("build") >= 0 else "chop")
	if build_site.complete:
		if not build_site.condition.add_repair_work(delta):
			unit.stop()  # out of resources for the repair
	else:
		build_site.condition.add_build_work(delta)


## Walk up to the kill and gut it (the hunters' "erlegen"/"ausbeinen" animation), then
## carry the meat home.
func butcher(carcass: Unit, delta: float) -> void:
	if unit.unit_type.anim_index("butcher") < 0:
		_carry_meat(carcass)
		return
	if unit.position.distance_to(carcass.position) > 26.0:
		if unit.path.is_empty():
			unit.path = unit.find_path(carcass.position)
		unit.follow_path(delta)
		unit.play("walk")
		if not unit.path.is_empty():
			return
	unit.path.clear()
	unit.face(carcass.position - unit.position)
	unit.play_repeating("butcher")
	_work_timer -= delta
	if _work_timer <= 0.0:
		_carry_meat(carcass)


func _carry_meat(carcass: Unit) -> void:
	carrying = "food"
	carried = carcass.animal.cut_meat(MEAT_PER_TRIP)
	_carcass = carcass if carcass.animal.has_meat() else null
	unit.target = null
	hunting = false
	gather_resource = "meat"
	gather_source = null
	unit.state = Unit.State.GATHERING
	phase = Phase.TO_DROP_OFF
	_route()


# ------------------------------------------------------------------ where to go

func nearest_animal() -> Unit:
	var best: Unit = null
	var best_distance := HUNT_RANGE
	for other in Unit.all_units:
		if other.animal.has_meat() and not (other.animal.is_horse() and other.is_alive()):
			var distance := unit.position.distance_to(other.position)
			if distance < best_distance:
				best = other
				best_distance = distance
	return best


func _route() -> void:
	if phase == Phase.TO_DROP_OFF:
		_drop_off = nearest_drop_off(carrying)
		unit.path = unit.find_path(_drop_off.position) if _drop_off else PackedVector2Array()
	elif _source_valid():
		unit.path = unit.find_path(_work_spot())


## Where to stand to work the current source: on the plot itself for a field (each woman
## her own patch of the furrows), else at the source and the arrival test does the rest.
func _work_spot() -> Vector2:
	if not gather_source.is_field():
		return gather_source.position
	if _field_spot == Vector2.INF or _field_spot_of != gather_source:
		var size := gather_source.footprint_rect().size
		# The furrows form a diamond around the field's position; keep inside its middle.
		var u := randf_range(-0.3, 0.3)
		var v := randf_range(-0.3, 0.3)
		_field_spot = gather_source.position + Vector2((u - v) * size.x * 0.5, (u + v) * size.y * 0.5)
		_field_spot_of = gather_source
	return _field_spot


func _source_valid() -> bool:
	if gather_source == null or not is_instance_valid(gather_source) or gather_source.stock.resource == "":
		return false
	return gather_source.is_field() or gather_source.stock.amount > 0


func _last_resource() -> String:
	if gather_resource != "":
		return gather_resource
	return "wood" if unit.unit_type.can_gather("wood") else "gold"


func nearest_source(resource: String, max_distance := INF) -> MapObject:
	var best: MapObject = null
	var best_distance := max_distance
	for object in MapObject.all_objects:
		var usable := object.stock.resource == resource and (object.stock.amount > 0 or object.is_field())
		if usable and object.is_field() and object.owner_index != unit.team:
			usable = false
		if usable:
			var distance := unit.position.distance_to(object.position)
			if distance < best_distance:
				best = object
				best_distance = distance
	return best


func nearest_drop_off(resource: String) -> MapObject:
	var best: MapObject = null
	var best_distance := INF
	for object in MapObject.structures:
		if object.owner_index == unit.team and resource in object.accepts:
			var distance := unit.position.distance_to(object.position)
			if distance < best_distance:
				best = object
				best_distance = distance
	return best


func main_building() -> MapObject:
	var best: MapObject = null
	for object in MapObject.structures:
		if object.owner_index == unit.team and object.guid in MapObject.MAIN_BUILDINGS and object.complete and object.is_alive() \
				and (best == null or unit.position.distance_to(object.position) < unit.position.distance_to(best.position)):
			best = object
	return best
