class_name AiPlayer
extends Node
## A skirmish opponent playing by the same rules as the human player.
##
## Economy: keeps its worker count growing, builds a wood store at the nearest forest and a
## gold warehouse at the nearest mine (with a wagon to haul the gold home), keeps housing
## ahead of its population, farms and hunts. Army: builds the structures that train soldiers,
## trains a mixed force, defends its base and attacks in growing waves. The four difficulty
## levels of the original (very easy .. difficult) set its pace and ambition.

const DIFFICULTY := [
	# think s, workers, production buildings, first attack s, wave size, research, building sites at once
	{"think": 3.0, "workers": 8, "production": 1, "first_attack": 720.0, "wave": 4, "research": false, "sites": 1},
	{"think": 2.0, "workers": 12, "production": 2, "first_attack": 480.0, "wave": 6, "research": false, "sites": 1},
	{"think": 1.5, "workers": 16, "production": 3, "first_attack": 330.0, "wave": 8, "research": true, "sites": 2},
	{"think": 1.0, "workers": 22, "production": 4, "first_attack": 240.0, "wave": 10, "research": true, "sites": 2},
]
const WOOD_SHARE := 0.6
const FIELD_TARGET := 4
const FAR_FROM_HQ := 380.0  # a resource this far away gets its own drop-off building
const DEFEND_RADIUS := 700.0

var player: Player
var units_root: Node2D
var biome := "steppe"
var difficulty := 2
var _timer := 0.0
var _elapsed := 0.0
var _attack_wave := 0
var _last_attack := -1000.0
var _failed := {}  # structure GUID -> when it last found no room
var _home := Vector2.ZERO
var _lost_since := -1.0
const SURRENDER_GRACE := 20.0  # seconds to start rebuilding before giving up


## The main building has fallen: rebuild it if there are builders and the means, keep the
## workers at it, and surrender when that is no longer possible.
func _without_main_building() -> void:
	if _lost_since < 0.0:
		_lost_since = _elapsed
	var main := _faction_guid(MapObject.MAIN_BUILDINGS)
	var units := _my_units()
	var builders := units.filter(func(u: Unit) -> bool: return u.unit_type.can_build(main))
	var rebuilding := _my_buildings().any(func(b: MapObject) -> bool: return b.guid == main)
	if rebuilding:
		_assign_workers(builders)
		return
	if not builders.is_empty() and _affordable(main) and _place(main, _home, builders, 0):
		return
	if _elapsed - _lost_since >= SURRENDER_GRACE:
		_surrender()


func _surrender() -> void:
	player.surrendered = true
	for unit: Unit in _my_units():
		unit.stance = Unit.Stance.PASSIVE
		unit.stop()
	var main := get_parent()
	if main and main.has_method("on_surrender"):
		main.on_surrender(player)


func _process(delta: float) -> void:
	_elapsed += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _level().think
	_think()


func _level() -> Dictionary:
	return DIFFICULTY[clampi(difficulty, 0, DIFFICULTY.size() - 1)]


func _think() -> void:
	if player.surrendered:
		return
	var hq := _hq()
	if hq == null:
		_without_main_building()
		return
	_home = hq.position
	_lost_since = -1.0
	var units := _my_units()
	var workers := units.filter(func(u: Unit) -> bool:
		return u.unit_type.can_gather("wood") and u.unit_type.anim_index("build") >= 0)
	var transports := units.filter(func(u: Unit) -> bool: return u.unit_type.is_transport())
	var army := units.filter(_is_soldier)
	_assign_workers(workers)
	_farm(units, hq)
	for unit: Unit in units:
		if unit.state == Unit.State.IDLE and unit.unit_type.is_hunter() and not _is_soldier(unit) \
				and int(player.resources.get("food", 0)) < 3000:
			unit.hunt(unit._nearest_animal())
	_train_civilians(hq, workers, units)
	_haul_gold(transports)
	_build(workers, hq)
	_train_army()
	if _level().research:
		_research()
	_command_army(army, hq)


func _is_soldier(u: Unit) -> bool:
	return not u.unit_type.attack_anims.is_empty() and not u.unit_type.can_gather("wood") \
			and not u.unit_type.can_gather("food") and not u.unit_type.is_transport() \
			and not (u.unit_type.is_hunter() and u.hunting)


func _my_units() -> Array:
	return units_root.get_children().filter(func(n: Node) -> bool:
		return n is Unit and n.team == player.index and n.is_alive())


func _my_buildings() -> Array:
	return MapObject.all_objects.filter(func(o: MapObject) -> bool:
		return o.is_building() and o.owner_index == player.index and o.is_alive())


func _hq() -> MapObject:
	for building in _my_buildings():
		if building.guid in MapObject.MAIN_BUILDINGS:
			return building
	return null


func _unit_type_for(guid: int) -> UnitType:
	return UnitType.for_guid(guid)


func _faction_guid(candidates: Array) -> int:
	for guid in candidates:
		if GameData.stats(guid).get("faction") == player.faction:
			return guid
	return -1


# ------------------------------------------------------------------ economy

## Idle workers build first, then gather: about WOOD_SHARE of them on wood.
func _assign_workers(workers: Array) -> void:
	var on_wood := workers.filter(func(u: Unit) -> bool:
		return is_instance_valid(u.gather_source) and u.gather_source.resource == "wood").size()
	for worker: Unit in workers:
		if worker.state != Unit.State.IDLE:
			continue
		var site := _unfinished_site()
		if site:
			worker.build(site)
			continue
		var gold := int(player.resources.get("gold", 0)) + player.warehoused_gold()
		var wood := int(player.resources.get("wood", 0))
		var share := WOOD_SHARE if gold < wood * 3 + 500 else 0.85
		var want_wood := on_wood < ceili(workers.size() * share)
		var source := worker._nearest_source("wood" if want_wood else "gold")
		if source == null:
			source = worker._nearest_source("gold" if want_wood else "wood")
		if source:
			worker.gather(source)
			if source.resource == "wood":
				on_wood += 1


## Workers up to the difficulty's target, and women for the fields.
func _train_civilians(hq: MapObject, workers: Array, units: Array) -> void:
	if not hq.complete or hq.queue.size() >= 2:
		return
	var fields := MapObject.all_objects.filter(func(o: MapObject) -> bool:
		return o.is_field() and o.owner_index == player.index).size()
	var farmers := units.filter(func(u: Unit) -> bool: return u.unit_type.is_farmer()).size()
	var want_farmer := farmers < fields * 2
	if not want_farmer and workers.size() >= _level().workers:
		return
	for guid in hq.trainable_units():
		var unit_type := _unit_type_for(guid)
		if unit_type == null or guid in Player.COMMANDERS:
			continue
		var is_builder := unit_type.anim_index("build") >= 0 and unit_type.can_gather("wood")
		if (want_farmer and unit_type.is_farmer()) or (not want_farmer and is_builder):
			hq.enqueue(guid)
			return


## Wagons shuttle from the fullest gold warehouse; one is trained when gold piles up there.
func _haul_gold(transports: Array) -> void:
	var warehouses := _my_buildings().filter(func(b: MapObject) -> bool: return b.is_gold_warehouse() and b.complete)
	if warehouses.is_empty():
		return
	for wagon: Unit in transports:
		if wagon.state == Unit.State.IDLE:
			warehouses.sort_custom(func(a: MapObject, b: MapObject) -> bool: return a.stored_gold > b.stored_gold)
			wagon.haul(warehouses[0])
	var waiting := 0
	for w: MapObject in warehouses:
		waiting += w.stored_gold
	if transports.size() < warehouses.size() and waiting >= 60:
		for building: MapObject in _my_buildings():
			if not building.complete or not building.queue.is_empty():
				continue
			for guid in building.trainable_units():
				var unit_type := _unit_type_for(guid)
				if unit_type and unit_type.is_transport() and building.enqueue(guid):
					return


## Keep a grain store with a few fields and put idle women to work on them.
func _farm(units: Array, hq: MapObject) -> void:
	var store := _faction_guid(MapObject.FOOD_STORES)
	if store < 0:
		_distil(units, hq)  # the outlaws distil liquor instead
		return
	var fields := MapObject.all_objects.filter(func(o: MapObject) -> bool:
		return o.is_field() and o.owner_index == player.index)
	var store_pending := _my_buildings().any(func(b: MapObject) -> bool: return b.guid == store)
	if not player.has_building(store):
		if not store_pending and _sites() < _level().sites and _affordable(store) \
				and int(player.resources.get("food", 0)) < 4000:
			_place(store, hq.position, units.filter(func(u: Unit) -> bool: return u.unit_type.can_build(store)))
		return
	# Fields cost wood: a couple early, more once the workforce is up.
	var field_target := FIELD_TARGET if _workers_ready(units) else 2
	if fields.size() < field_target and MapObject.field_allowance(player.index) > 0 and _affordable(MapObject.FIELD_GUID):
		var store_object: MapObject = null
		for object in MapObject.all_objects:
			if object.guid == store and object.owner_index == player.index and object.complete:
				store_object = object
		if store_object:
			var type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.FIELD_GUID, biome))
			var spot := _find_spot(type, store_object.position, 120)
			if spot != Vector2.INF:
				var cost: Dictionary = GameData.stats(MapObject.FIELD_GUID).get("cost", {}).duplicate()
				cost.erase("population")
				player.spend(cost)
				var field := MapObject.new()
				field.position = spot
				field.setup(type, player.index)
				units_root.add_child(field)
				fields.append(field)
	for unit: Unit in units:
		if unit.state != Unit.State.IDLE or not unit.unit_type.is_farmer() or fields.is_empty():
			continue
		var counts := {}
		for other: Unit in units:
			if is_instance_valid(other.gather_source) and other.gather_source in fields:
				counts[other.gather_source] = counts.get(other.gather_source, 0) + 1
		var least: MapObject = fields[0]
		for field: MapObject in fields:
			if counts.get(field, 0) < counts.get(least, 0):
				least = field
		unit.gather(least)


## Outlaws turn wood into liquor: keep a distillery per few workers while food runs low.
func _distil(units: Array, hq: MapObject) -> void:
	var distilleries := _my_buildings().filter(func(b: MapObject) -> bool: return b.guid == MapObject.DISTILLERY_GUID).size()
	var wanted := 1 + _my_units().size() / 12
	var food := int(player.resources.get("food", 0))
	if distilleries < wanted and food < 2500 and _sites() < _level().sites and _affordable(MapObject.DISTILLERY_GUID):
		_place(MapObject.DISTILLERY_GUID, hq.position, units.filter(func(u: Unit) -> bool:
			return u.unit_type.can_build(MapObject.DISTILLERY_GUID)))


# ------------------------------------------------------------------ building

func _sites() -> int:
	return _my_buildings().filter(func(b: MapObject) -> bool: return not b.complete).size()


func _unfinished_site() -> MapObject:
	for building in _my_buildings():
		if not building.complete:
			return building
	return null


## What to build next, in order: housing ahead of need, drop-offs by distant resources,
## then the structures that train soldiers (up to the difficulty's limit).
func _build(workers: Array, hq: MapObject) -> void:
	if workers.size() < 3 or _sites() >= _level().sites:
		return
	var buildings := _my_buildings()
	var owned := {}
	for b: MapObject in buildings:
		owned[b.guid] = owned.get(b.guid, 0) + 1
	# Housing.
	var house := _house_guid()
	var room := player.population_cap() - player.population() - player.queued_units()
	if house >= 0 and room < 4 and _affordable(house) and _place(house, hq.position, workers):
		return
	if room < 1:
		return
	# A wood store at the nearest forest, a gold warehouse at the nearest mine.
	var wood_store := _faction_guid(MapObject.DROP_OFFS.wood)
	var forest := _nearest_resource("wood", hq.position)
	if wood_store >= 0 and forest and _no_drop_off_near("wood", forest.position) and _worth_trying(wood_store) \
			and forest.position.distance_to(hq.position) > FAR_FROM_HQ and _affordable(wood_store) \
			and _place(wood_store, forest.position, workers, 110, FAR_FROM_HQ * 0.8):
		return
	var gold_store := _faction_guid(Array(MapObject.DROP_OFFS.gold).filter(func(g: int) -> bool: return g not in MapObject.MAIN_BUILDINGS))
	var mine := _nearest_resource("gold", hq.position)
	if gold_store >= 0 and mine and _no_drop_off_near("gold", mine.position) and _worth_trying(gold_store) \
			and mine.position.distance_to(hq.position) > FAR_FROM_HQ and _affordable(gold_store) \
			and player.meets_prerequisites(gold_store) and _place(gold_store, mine.position, workers, 110, FAR_FROM_HQ * 0.8):
		return
	# Soldiers, once most of the workforce is in place (the first one a little earlier).
	var production := buildings.filter(func(b: MapObject) -> bool: return _produces_army(b.guid)).size()
	if production >= _level().production:
		return
	if production > 0 and not _workers_ready(_my_units()):
		return
	if production == 0 and workers.size() < _level().workers / 3:
		return
	var options := []
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") != player.faction or stats.get("kind") != "structure":
			continue
		if owned.has(guid) or not player.meets_prerequisites(guid):
			continue
		# Structures that train soldiers, and those that unlock one (the fort before barracks).
		if _produces_army(guid) or _unlocks_army(guid, owned):
			options.append(guid)
	options.sort_custom(func(a: int, b: int) -> bool: return _total_cost(a) < _total_cost(b))
	for guid in options:
		if _affordable(guid) and _place(guid, hq.position, workers):
			return


func _unlocks_army(structure: int, owned: Dictionary) -> bool:
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") == player.faction and stats.get("kind") == "structure" and not owned.has(guid) \
				and _produces_army(guid) and structure in GameData.prerequisites(guid):
			return true
	return false


func _workers_ready(units: Array) -> bool:
	var workers := units.filter(func(u: Unit) -> bool:
		return u.unit_type.can_gather("wood") and u.unit_type.anim_index("build") >= 0).size()
	return workers >= int(_level().workers * 0.5)


func _house_guid() -> int:
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") == player.faction and stats.get("kind") == "structure" \
				and int(stats.get("housing", 0)) > 0 and guid not in MapObject.MAIN_BUILDINGS:
			return guid
	return -1


func _nearest_resource(resource: String, from: Vector2) -> MapObject:
	var best: MapObject = null
	for object in MapObject.all_objects:
		if object.resource == resource and object.amount > 0 and not object.is_field() \
				and (best == null or from.distance_to(object.position) < from.distance_to(best.position)):
			best = object
	return best


func _no_drop_off_near(resource: String, at: Vector2) -> bool:
	for object in MapObject.all_objects:
		if object.owner_index == player.index and object.is_building() \
				and (resource in object.accepts or (not object.complete and object.guid in MapObject.DROP_OFFS.get(resource, []))) \
				and object.position.distance_to(at) < FAR_FROM_HQ:
			return false
	return true


## Start building `guid` near `around` (within `max_distance` of it); false when there is
## no room there, which also keeps the AI from retrying it for a while.
func _place(guid: int, around: Vector2, builders: Array, min_radius := 220, max_distance := INF) -> bool:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, biome))
	if type == null or builders.is_empty():
		return false
	var spot := _find_spot(type, around, min_radius)
	if spot == Vector2.INF or spot.distance_to(around) > max_distance:
		_failed[guid] = _elapsed
		return false
	var cost: Dictionary = GameData.stats(guid).get("cost", {}).duplicate()
	cost.erase("population")
	if not player.spend(cost):
		return false
	var site := MapObject.new()
	site.position = spot
	if not site.setup(type, player.index, 0, true):
		site.free()
		return false
	units_root.add_child(site)
	NavGrid.current.block_footprint(type, spot)
	site.unit_trained.connect(get_parent()._on_unit_trained)
	if OS.is_debug_build() and GameData.cmdline_option("trace-ai") != "":
		print("t=%ds AI %d builds %s (workers %d, units %d/%d, wood %d)" % [_elapsed, player.index, GameData.stats(guid).get("name"),
				builders.size(), player.population(), player.population_cap(), player.resources.get("wood", 0)])
	var nearest := builders.duplicate()
	nearest.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.position.distance_to(spot) < b.position.distance_to(spot))
	for worker: Unit in nearest.slice(0, 3):
		worker.build(site)
	return true


func _worth_trying(guid: int) -> bool:
	return _elapsed - float(_failed.get(guid, -1000.0)) > 90.0


func _produces_army(structure_guid: int) -> bool:
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("kind") == "unit" and int(stats.get("produced_at", -1)) == structure_guid \
				and stats.get("damage", 0) >= 5:
			return true
	return false


func _affordable(guid: int) -> bool:
	var cost: Dictionary = GameData.stats(guid).get("cost", {}).duplicate()
	cost.erase("population")
	return player.can_afford(cost)


func _total_cost(guid: int) -> int:
	var total := 0
	for key in GameData.stats(guid).get("cost", {}):
		total += int(GameData.stats(guid).cost[key])
	return total


## Search outward from `around` for a free footprint.
func _find_spot(type: ObjectTypes.ObjectType, around: Vector2, min_radius := 220) -> Vector2:
	var nav := NavGrid.current
	for radius in range(min_radius, 900, 32):
		for step in 12:
			var spot := around + Vector2(radius, 0).rotated(step * TAU / 12.0 + radius * 0.37)
			spot = (spot / NavGrid.CELL).round() * NavGrid.CELL
			if _footprint_free(type, spot, nav):
				return spot
	return Vector2.INF


func _footprint_free(type: ObjectTypes.ObjectType, at: Vector2, nav: NavGrid) -> bool:
	var rect := MapObject.footprint_rect_for(type, at)
	var origin := nav.cell_of(rect.position)
	for i in type.footprint_cells.size():
		var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
		if not nav.is_walkable(cell):
			return false
	# Keep a walkable margin so buildings don't wall each other in.
	for object in MapObject.all_objects:
		if object.is_building() and object.footprint_rect().grow(32).intersects(rect):
			return false
	return true


# ------------------------------------------------------------------ army

func _train_army() -> void:
	for building: MapObject in _my_buildings():
		if not building.complete or building.queue.size() >= 2 or building.guid in MapObject.MAIN_BUILDINGS:
			continue
		# Raise horses for the mounted units while there is room and food to spare.
		if building.guid in MapObject.HORSE_BUILDINGS and int(player.resources.get("food", 0)) > 400 \
				and int(player.resources.get("horses", 0)) < player.horse_capacity() and randf() < 0.5:
			if building.enqueue(MapObject.HORSE_GUID):
				continue
		var options := Array(building.trainable_units()).filter(func(guid: int) -> bool:
			return GameData.stats(guid).get("damage", 0) >= 5 and guid not in Player.COMMANDERS)
		options.shuffle()
		for guid in options:
			if building.enqueue(guid):
				break


## Spend spare food and gold on upgrades, one at a time.
func _research() -> void:
	if int(player.resources.get("gold", 0)) < 600 or int(player.resources.get("food", 0)) < 800:
		return
	for building: MapObject in _my_buildings():
		if not building.queue.is_empty():
			continue
		var options := building.researchable_upgrades()
		if not options.is_empty():
			building.enqueue(options[randi() % options.size()])
			return


## Defend against anything near the base; otherwise attack in growing waves once the
## difficulty's first-attack time has passed.
func _command_army(army: Array, hq: MapObject) -> void:
	var intruder := _intruder(hq)
	if intruder:
		for unit: Unit in army:
			if unit.state == Unit.State.IDLE or unit.state == Unit.State.MOVING:
				unit.attack_move(intruder.position)
		return
	var wave_size: int = _level().wave + _attack_wave * 2
	if _elapsed < _level().first_attack or army.size() < wave_size or _elapsed - _last_attack < 60.0:
		return
	var target := _enemy_base()
	if target == Vector2.INF:
		return
	_attack_wave += 1
	_last_attack = _elapsed
	if GameData.cmdline_option("trace-ai") != "":
		print("t=%ds AI %d attacks with %d units (wave %d)" % [_elapsed, player.index, army.size(), _attack_wave])
	for unit: Unit in army:
		unit.attack_move(target + Vector2(randf_range(-60, 60), randf_range(-60, 60)))


func _intruder(hq: MapObject) -> Unit:
	var buildings := _my_buildings()
	for unit in Unit.all_units:
		if unit.team > 0 and unit.team != player.index and unit.is_alive() and not unit.inside:
			for building: MapObject in buildings:
				if building.position.distance_to(unit.position) < DEFEND_RADIUS * (1.0 if building == hq else 0.5):
					return unit
	return null


func _enemy_base() -> Vector2:
	var best := Vector2.INF
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index > 0 and object.owner_index != player.index and object.is_alive():
			if best == Vector2.INF or object.guid in MapObject.MAIN_BUILDINGS:
				best = object.position
	return best
