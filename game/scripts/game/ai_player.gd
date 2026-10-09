class_name AiPlayer
extends Node
## A skirmish opponent playing by the same rules as the human player.
##
## Economy: keeps its worker count growing, builds a wood store at the nearest forest and a
## gold warehouse at the nearest mine (with a wagon to haul the gold home), keeps housing
## ahead of its population, farms and hunts. Army: builds the structures that train soldiers,
## trains a mixed force, defends its base and attacks in growing waves. The four difficulty
## levels of the original (very easy .. difficult) set its pace and ambition.
##
## Later in the game it spends what piles up: more production, towers (pitfalls for the
## Native Americans), a trading post, a second mine. It catches wild horses, raises and
## sells cattle, empties abandoned warehouses, has its medicine men and priests cast, its
## scouts hide, its robbers rob and its thieves steal. Waves gather before they set out,
## march in formation and send the badly wounded home; a home guard stays behind on the
## defensive. When the enemy cannot be reached on foot it ferries its troops by boat, or
## (the Native Americans) learns to swim.

const DIFFICULTY := [
	# think s, workers, production buildings, first attack s, wave size, research, building sites at once
	{"think": 3.0, "workers": 8, "production": 1, "first_attack": 720.0, "wave": 4, "research": false, "sites": 1},
	{"think": 2.0, "workers": 12, "production": 2, "first_attack": 480.0, "wave": 6, "research": false, "sites": 1},
	{"think": 1.5, "workers": 16, "production": 3, "first_attack": 330.0, "wave": 8, "research": true, "sites": 2},
	{"think": 1.0, "workers": 22, "production": 4, "first_attack": 240.0, "wave": 10, "research": true, "sites": 2},
]
const TOWERS := [213, 413, 313]  # Mexican tower, American watchtower, outlaw lookout
const TOWER_TARGET := [0, 1, 2, 3]  # per difficulty
const PITFALL_TARGET := [0, 1, 2, 3]
const RICH_WOOD := 1200
const RICH_OTHER := 1500  # gold and food together
const RETREAT_BELOW := 0.3  # energy share at which a unit in a wave turns back
const RETREAT_SECONDS := 60.0  # time at home before it rejoins
const GUARD_SHARE := 0.2
const GATHER_SECONDS := 30.0
const GATHER_DISTANCE := 380.0  # the assembly point, out from the HQ toward the enemy
const COW_TARGET := 4
const COW_SELL_VALUE := 18.0
const BOAT_TARGET := 2
const MAX_WOOD_STORES := 4
const FOREST_TREES := 10  # a wood store only by a forest this big
const FOOD_SURPLUS := 2500  # distilleries rest above this
const CANOE_TARGET := 3  # canoes fight only on the water
const SWIM := 914
const CAMOUFLAGE_SCHOOL := 112
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
## The current wave: "home" (building up), "gathering" at the assembly point, "attacking".
var _wave_state := "home"
var _wave: Array = []
var _wave_size := 0
var _wave_target := Vector2.INF
var _gather_point := Vector2.INF
var _gather_started := 0.0
var _guard := {}  # instance id -> true: stays home on the defensive
var _retreating := {}  # instance id -> when it turned back
var _land_route := true  # can the army walk to the enemy?
var _route_checked := -1000.0
var _ferry_started := 0.0
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
	_cache_valid = false
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
			unit.hunt(unit.work.nearest_animal())
	_train_civilians(hq, workers, units)
	_haul_gold(transports)
	_build(workers, hq)
	_build_extras(workers, hq)
	_train_army()
	_train_specialists()
	if _level().research or _rich() or not _land_route:
		_research()
	_trade()
	_use_horses(units)
	_cattle(units)
	_magic(units, army)
	_command_army(army, hq)


func _is_soldier(u: Unit) -> bool:
	return not u.inside and not u.unit_type.attack_anims.is_empty() and not u.unit_type.can_gather("wood") \
			and u.unit_type.guid() != UnitWater.CANOE \
			and not u.unit_type.can_gather("food") and not u.unit_type.is_transport() \
			and not (u.unit_type.is_hunter() and u.work.hunting)


## Our living units and standing buildings, gathered once per think (sites placed during
## a think drop the cache so they count at once).
var _units_cache: Array = []
var _buildings_cache: Array = []
var _cache_valid := false


func _my_units() -> Array:
	_fill_cache()
	return _units_cache.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())


func _my_buildings() -> Array:
	_fill_cache()
	return _buildings_cache.filter(func(b: MapObject) -> bool: return is_instance_valid(b) and b.is_alive())


func _fill_cache() -> void:
	if _cache_valid:
		return
	_cache_valid = true
	_units_cache = Unit.all_units.filter(func(u: Unit) -> bool: return u.team == player.index and u.is_alive())
	_buildings_cache = MapObject.structures.filter(func(o: MapObject) -> bool:
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
		return is_instance_valid(u.work.gather_source) and u.work.gather_source.resource == "wood").size()
	var share := _wood_share()
	# Every half minute, move workers over when the stock leans too far one way.
	if _elapsed - _rebalanced > 30.0:
		_rebalanced = _elapsed
		var wanted := ceili(workers.size() * share)
		var from := "wood" if on_wood > wanted + 1 else ("gold" if on_wood < wanted - 1 else "")
		if from != "":
			var excess := absi(on_wood - wanted) - 1
			for worker: Unit in workers:
				if excess <= 0:
					break
				if worker.state == Unit.State.GATHERING and is_instance_valid(worker.work.gather_source) \
						and worker.work.gather_source.resource == from and worker.work.carried == 0:
					var source := _gold_source_for(worker, workers) if from == "wood" else worker.work.nearest_source("wood")
					if source:
						worker.gather(source)
						on_wood += -1 if from == "wood" else 1
						excess -= 1
	for worker: Unit in workers:
		if worker.state != Unit.State.IDLE:
			continue
		var site := _unfinished_site()
		if site:
			worker.build(site)
			continue
		var want_wood := on_wood < ceili(workers.size() * share)
		var source := worker.work.nearest_source("wood") if want_wood else _gold_source_for(worker, workers)
		if source == null:
			source = _gold_source_for(worker, workers) if want_wood else worker.work.nearest_source("wood")
		if source:
			worker.gather(source)
			if source.resource == "wood":
				on_wood += 1


## The share of workers on wood: 60% when wood and gold stand even, fewer as wood piles up
## beside little gold, more when gold is plentiful.
func _wood_share() -> float:
	var gold := int(player.resources.get("gold", 0)) + player.warehoused_gold()
	var wood := int(player.resources.get("wood", 0))
	return clampf(WOOD_SHARE - (wood - gold) / 4000.0, 0.25, 0.85)


var _rebalanced := 0.0


## Miners spread over the mines that have somewhere to take the gold (the HQ or a gold
## warehouse close by): the one with the fewest miners, the nearest of those.
func _gold_source_for(worker: Unit, workers: Array) -> MapObject:
	var served := MapObject.all_objects.filter(func(o: MapObject) -> bool:
		return o.resource == "gold" and o.amount > 0 and not _no_drop_off_near("gold", o.position))
	if served.is_empty():
		return worker.work.nearest_source("gold")
	var miners := {}
	for other: Unit in workers:
		if is_instance_valid(other.work.gather_source) and other.work.gather_source in served:
			miners[other.work.gather_source] = miners.get(other.work.gather_source, 0) + 1
	served.sort_custom(func(a: MapObject, b: MapObject) -> bool:
		if miners.get(a, 0) != miners.get(b, 0):
			return miners.get(a, 0) < miners.get(b, 0)
		return worker.position.distance_to(a.position) < worker.position.distance_to(b.position))
	return served[0]


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
## Spare wagons empty abandoned warehouses nearby.
func _haul_gold(transports: Array) -> void:
	var warehouses := _my_buildings().filter(func(b: MapObject) -> bool: return b.is_gold_warehouse() and b.complete)
	var abandoned := MapObject.abandoned_stores.filter(func(o: MapObject) -> bool:
		return o.is_abandoned_store() and o.loot > 0 and o.position.distance_to(_home) < 1800.0 and not _enemy_near(o.position, 600.0))
	if warehouses.is_empty() and abandoned.is_empty():
		return
	if warehouses.is_empty():
		for wagon: Unit in transports:
			if wagon.state == Unit.State.IDLE and wagon.tepees.packed.is_empty():
				abandoned.sort_custom(func(a: MapObject, b: MapObject) -> bool: return a.position.distance_to(wagon.position) < b.position.distance_to(wagon.position))
				wagon.haul(abandoned[0])
		if transports.is_empty():
			_train_transport()
		return
	var on_abandoned := transports.filter(func(w: Unit) -> bool:
		return is_instance_valid(w.work.gather_source) and w.work.gather_source.is_abandoned_store()).size()
	for wagon: Unit in transports:
		if wagon.state != Unit.State.IDLE or not wagon.tepees.packed.is_empty():
			continue
		if not abandoned.is_empty() and on_abandoned == 0 and transports.size() > warehouses.size():
			wagon.haul(abandoned[0])
			on_abandoned += 1
			continue
		warehouses.sort_custom(func(a: MapObject, b: MapObject) -> bool: return a.stored_gold > b.stored_gold)
		wagon.haul(warehouses[0])
	var waiting := 0
	for w: MapObject in warehouses:
		waiting += w.stored_gold
	if transports.size() < warehouses.size() + (1 if not abandoned.is_empty() else 0) and waiting >= 60:
		_train_transport()


func _train_transport() -> void:
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
		for object in MapObject.structures:
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
			if is_instance_valid(other.work.gather_source) and other.work.gather_source in fields:
				counts[other.work.gather_source] = counts.get(other.work.gather_source, 0) + 1
		var least: MapObject = fields[0]
		for field: MapObject in fields:
			if counts.get(field, 0) < counts.get(least, 0):
				least = field
		unit.gather(least)


## Outlaws turn wood into liquor: keep a distillery per few workers while food runs low,
## and let them rest while food piles up.
func _distil(units: Array, hq: MapObject) -> void:
	var food_now := int(player.resources.get("food", 0))
	for still: MapObject in _my_buildings().filter(func(b: MapObject) -> bool: return b.guid == MapObject.DISTILLERY_GUID):
		still.distilling = food_now < FOOD_SURPLUS
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
	if house >= 0 and room < (8 if _rich() else 4) and _affordable(house) and _place(house, hq.position, workers):
		return
	if room < 1:
		return
	# A wood store at the nearest forest, a gold warehouse at the nearest mine.
	var wood_store := _faction_guid(MapObject.DROP_OFFS.wood)
	var forest := _nearest_resource("wood", hq.position)
	var wood_stores := buildings.filter(func(b: MapObject) -> bool: return b.guid == wood_store).size()
	if wood_store >= 0 and forest and wood_stores < MAX_WOOD_STORES and _trees_near(forest.position) >= FOREST_TREES \
			and _no_drop_off_near("wood", forest.position) and _worth_trying(wood_store) \
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
	if production >= _production_limit():
		return
	if production > 0 and not _workers_ready(_my_units()):
		return
	if production == 0 and workers.size() < _level().workers / 3:
		return
	# Structures that train soldiers: each new kind (with whatever it requires first, such as
	# the sawmill and fort before barracks), then, when rich, a second of a kind.
	var options := []
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") != player.faction or stats.get("kind") != "structure" or not _produces_army(guid):
			continue
		if owned.has(guid) and (not _rich() or not player.meets_prerequisites(guid)):
			continue
		options.append(guid)
	options.sort_custom(func(a: int, b: int) -> bool:
		if owned.has(a) != owned.has(b):
			return not owned.has(a)  # new kinds first
		return _chain_cost(a) < _chain_cost(b))
	for guid in options:
		if not owned.has(guid):
			if _my_buildings().any(func(b: MapObject) -> bool: return not b.complete):
				return  # one step of a chain at a time
			if _build_with_prerequisites(guid, hq.position, workers) or _worth_trying(guid):
				return  # built a step, or saving up for it rather than buying another cheap one
			continue
		if _affordable(guid) and _place(guid, hq.position, workers):
			return


## What a structure costs with the structures it still requires.
func _chain_cost(guid: int, depth := 0) -> int:
	var total := _total_cost(guid)
	if depth < 3:
		for required in GameData.prerequisites(guid):
			if not player.has_building(required):
				total += _chain_cost(required, depth + 1)
	return total


## More production when stock piles up (one more when rich, two when very rich).
func _production_limit() -> int:
	var limit: int = _level().production
	if _rich():
		limit += 1
	if int(player.resources.get("wood", 0)) > RICH_WOOD * 3 and int(player.resources.get("gold", 0)) > RICH_OTHER:
		limit += 1
	return limit


func _rich() -> bool:
	return int(player.resources.get("wood", 0)) >= RICH_WOOD \
			and int(player.resources.get("gold", 0)) + int(player.resources.get("food", 0)) >= RICH_OTHER


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


## The nearest tree or mine with something left (remembered for a while: the search
## covers thousands of trees).
var _nearest_cache := {}  # "resource@x,y" -> [MapObject, when]


func _nearest_resource(resource: String, from: Vector2) -> MapObject:
	var key := "%s@%d,%d" % [resource, int(from.x), int(from.y)]
	var cached: Array = _nearest_cache.get(key, [])
	if not cached.is_empty() and _elapsed - float(cached[1]) < 15.0 and is_instance_valid(cached[0]) and cached[0].amount > 0:
		return cached[0]
	var best := _search_nearest_resource(resource, from)
	_nearest_cache[key] = [best, _elapsed]
	return best


func _search_nearest_resource(resource: String, from: Vector2) -> MapObject:
	var best: MapObject = null
	for object in MapObject.all_objects:
		if object.resource == resource and object.amount > 0 and not object.is_field() \
				and (best == null or from.distance_to(object.position) < from.distance_to(best.position)):
			best = object
	return best


func _trees_near(at: Vector2) -> int:
	var count := 0
	for object in MapObject.all_objects:
		if object.resource == "wood" and object.amount > 0 and object.position.distance_to(at) < 260.0:
			count += 1
	return count


func _no_drop_off_near(resource: String, at: Vector2) -> bool:
	for object in MapObject.structures:
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
	_cache_valid = false
	if not site.is_trap():
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
	for guid in MapObject.units_trained_at(structure_guid):
		if GameData.stats(guid).get("damage", 0) >= 5 and guid not in Player.COMMANDERS and guid != UnitWater.CANOE:
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
	# Ever wider rings, sampled about every 48 px along each (bases hemmed in by cliffs
	# and water need the search to reach well out).
	for radius in range(min_radius, 1500, 32):
		var steps := maxi(12, int(TAU * radius / 48.0))
		for step in steps:
			var spot := around + Vector2(radius, 0).rotated(step * TAU / steps + radius * 0.37)
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
	for object in MapObject.structures:
		if object.is_building() and object.footprint_rect().grow(32).intersects(rect):
			return false
	return true



# ------------------------------------------------------------------ later game

## Once the core is in place and stock piles up: towers toward the enemy (the Native
## Americans dig pitfalls instead), a trading post, a gold warehouse by a second mine, and
## a wharf or boathouse when the enemy is across the water.
func _build_extras(workers: Array, hq: MapObject) -> void:
	if workers.size() < 3 or _sites() >= _level().sites or not _workers_ready(_my_units()):
		return
	var buildings := _my_buildings()
	var count := func(guids: Array) -> int:
		return buildings.filter(func(b: MapObject) -> bool: return b.guid in guids).size()
	var toward := (_enemy_base() - hq.position).normalized() if _enemy_base() != Vector2.INF else Vector2.DOWN
	# Across the water: a shipyard first.
	var shipyard := _faction_guid(MapObject.SHIPYARDS)
	if not _land_route and shipyard >= 0 and count.call([shipyard]) == 0 and _affordable(shipyard) \
			and _worth_trying(shipyard) and _place_by_water(shipyard, hq.position, workers):
		return
	if player.faction == "ind" and not _land_route and not player.researched.has(SWIM) \
			and count.call([CAMOUFLAGE_SCHOOL]) == 0:
		_build_with_prerequisites(CAMOUFLAGE_SCHOOL, hq.position, workers)
		return
	if not _rich():
		return
	var tower := _faction_guid(TOWERS)
	if tower >= 0 and count.call([tower]) < TOWER_TARGET[difficulty] and player.meets_prerequisites(tower) \
			and _affordable(tower) and _worth_trying(tower) \
			and _place(tower, hq.position + toward.rotated(randf_range(-0.8, 0.8)) * 300.0, workers, 0, 260.0):
		return
	if player.faction == "ind" and count.call([MapObject.PITFALL_GUID]) < PITFALL_TARGET[difficulty] \
			and player.meets_prerequisites(MapObject.PITFALL_GUID) and _affordable(MapObject.PITFALL_GUID) \
			and _worth_trying(MapObject.PITFALL_GUID) \
			and _place(MapObject.PITFALL_GUID, hq.position + toward.rotated(randf_range(-0.5, 0.5)) * 520.0, workers, 0, 200.0):
		return
	var post := _faction_guid(MapObject.TRADE_BUILDINGS)
	if post >= 0 and count.call([post]) == 0 and _build_with_prerequisites(post, hq.position, workers):
		return
	# A second mine with its own warehouse, so the miners spread out.
	var gold_store := _faction_guid(Array(MapObject.DROP_OFFS.gold).filter(func(g: int) -> bool: return g not in MapObject.MAIN_BUILDINGS))
	var served := 0
	var next_mine: MapObject = null
	var mines := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.resource == "gold" and o.amount > 300)
	mines.sort_custom(func(a: MapObject, b: MapObject) -> bool: return a.position.distance_to(hq.position) < b.position.distance_to(hq.position))
	for mine: MapObject in mines:
		if not _no_drop_off_near("gold", mine.position):
			served += 1
		elif next_mine == null and mine.position.distance_to(hq.position) < 2600.0 and not _enemy_near(mine.position, 700.0):
			next_mine = mine
	if served < 2 and next_mine and gold_store >= 0 and _affordable(gold_store) and _worth_trying(gold_store) \
			and player.meets_prerequisites(gold_store):
		_place(gold_store, next_mine.position, workers, 110, FAR_FROM_HQ * 0.8)


## Build `guid`, or first whichever structure it still requires; true when a site went up.
func _build_with_prerequisites(guid: int, around: Vector2, workers: Array, depth := 0) -> bool:
	if depth > 2:
		return false
	for required in GameData.prerequisites(guid):
		if not player.has_building(required):
			if _my_buildings().any(func(b: MapObject) -> bool: return b.guid == required):
				return false  # going up already
			return _build_with_prerequisites(required, around, workers, depth + 1)
	return _affordable(guid) and _worth_trying(guid) and _place(guid, around, workers)


func _enemy_near(at: Vector2, radius: float) -> bool:
	for object in MapObject.structures:
		if object.is_building() and object.owner_index > 0 and object.owner_index != player.index \
				and object.position.distance_to(at) < radius:
			return true
	return false


## A shipyard at the nearest stretch of shore to `around`.
func _place_by_water(guid: int, around: Vector2, builders: Array) -> bool:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, biome))
	if type == null:
		return false
	var nav := NavGrid.current
	for radius in range(160, 2400, 48):
		for step in 24:
			var spot := (around + Vector2(radius, 0).rotated(step * TAU / 24.0)).snapped(Vector2(NavGrid.CELL, NavGrid.CELL))
			if _footprint_free(type, spot, nav) and MapObject.by_water(type, spot):
				return _place(guid, spot, builders, 0, 64.0)
	_failed[guid] = _elapsed
	return false


## Healers, casters and boats, which the army trainer leaves out (they don't fight).
func _train_specialists() -> void:
	var units := _my_units()
	var soldiers := units.filter(_is_soldier).size()
	for building: MapObject in _my_buildings():
		if not building.complete or building.queue.size() >= 1:
			continue
		for guid in building.trainable_units():
			var unit_type := _unit_type_for(guid)
			if unit_type == null or not unit_type.attack_anims.is_empty() or guid in Player.COMMANDERS:
				continue
			var have := units.filter(func(u: Unit) -> bool: return u.unit_type.guid() == guid).size()
			var wanted := 0
			if guid in UnitWater.BOATS:
				wanted = BOAT_TARGET if not _land_route else 0
			elif UnitMagic.CASTERS.has(guid):
				wanted = 1 if soldiers >= 6 else 0
			elif unit_type.anim_index("heal") >= 0 and not unit_type.is_transport():
				wanted = soldiers / 8
			if have < wanted and building.enqueue(guid):
				return


## The trading post evens out the stock: sell what piles up when gold runs short, buy wood
## or food when they run out and gold is plentiful, and guns for the riflemen.
func _trade() -> void:
	var post: MapObject = null
	for building: MapObject in _my_buildings():
		if building.guid in MapObject.TRADE_BUILDINGS and building.complete and building.queue.size() < 3:
			post = building
	if post == null:
		return
	var r := player.resources
	var gold := int(r.get("gold", 0))
	var trade := -1
	if int(r.get("guns", 0)) < 4 and gold > 500:
		trade = 4  # buy guns
	elif gold < 400 and maxi(int(r.get("food", 0)), int(r.get("wood", 0))) > 1500:
		trade = 1 if int(r.get("food", 0)) > int(r.get("wood", 0)) else 3  # sell food / wood
	elif int(r.get("wood", 0)) < 250 and gold > 1200:
		trade = 2  # buy wood
	elif int(r.get("food", 0)) < 250 and gold > 1200:
		trade = 0  # buy food
	elif gold < 1500 and int(r.get("food", 0)) > FOOD_SURPLUS:
		trade = 1  # surplus food for gold
	elif gold < 1500 and int(r.get("wood", 0)) > 3000:
		trade = 3
	if trade >= 0:
		post.enqueue(MapObject.TRADE_GUID + trade)


## Idle soldiers who can ride catch wild horses near them.
func _use_horses(units: Array) -> void:
	for unit: Unit in units:
		if unit.state != Unit.State.IDLE or not unit.riding.can_mount() or unit.riding.busy:
			continue
		for other in Unit.all_units:
			if other.animal.is_horse() and other.is_alive() and (other.team == 0 or other.team == player.index) \
					and other.position.distance_to(unit.position) < 600.0:
				unit.mount(other)
				break


## Raise a few cows where the people can (hacienda, ranch) and drive the grown ones to the
## butcher; herders bring in strays.
func _cattle(units: Array) -> void:
	var processing: MapObject = null
	for building: MapObject in _my_buildings():
		if building.guid in MapObject.ANIMAL_PROCESSING and building.complete:
			processing = building
	var cows := units.filter(func(u: Unit) -> bool: return u.animal.is_cow())
	if processing:
		for cow: Unit in cows:
			if cow.state == Unit.State.IDLE and cow.animal.cattle_value >= COW_SELL_VALUE:
				cow.animal.deliver(processing)
	if cows.size() >= COW_TARGET or int(player.resources.get("food", 0)) < 600:
		return
	for building: MapObject in _my_buildings():
		if building.guid in MapObject.COW_BUILDINGS and building.complete and building.queue.is_empty():
			building.enqueue(MapObject.COW_GUID)
			return


## Medicine men dance (lightning on enemies fighting ours, a shield for a hurt soldier,
## rain on our fields); priests convert enemy soldiers who come close.
func _magic(units: Array, army: Array) -> void:
	for caster: Unit in units:
		if caster.state != Unit.State.IDLE or caster.magic.spell >= 0:
			continue
		var spells := caster.magic.known_spells()
		if spells.is_empty():
			continue
		var enemy := caster.nearest_enemy(700.0)
		if 919 in spells and enemy and caster.magic.magic_energy >= UnitMagic.SPELLS[919].cost:
			caster.cast(919, enemy.position)
		elif 948 in spells and enemy and caster.magic.convertible(enemy) and caster.magic.magic_energy >= UnitMagic.SPELLS[948].cost:
			caster.cast(948, enemy.position, enemy)
		elif 922 in spells and caster.magic.magic_energy >= UnitMagic.SPELLS[922].cost:
			for soldier: Unit in army:
				if soldier.state == Unit.State.ATTACKING and soldier.health < soldier.max_health * 0.6 \
						and soldier.magic.shield_time <= 0.0 and soldier.position.distance_to(caster.position) < 600.0:
					caster.cast(922, soldier.position, soldier)
					break
		elif 921 in spells and caster.magic.magic_energy >= caster.magic.magic_pool() * 0.9:
			for field in MapObject.structures:
				if field.is_field() and field.owner_index == player.index and field.field_state == MapObject.Field.GROWING \
						and not field._rained:
					caster.cast(921, field.position)
					break


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
		# Rifles for the infantry, while gold allows.
		if building.guid in MapObject.GUN_FACTORIES and int(player.resources.get("guns", 0)) < 8 \
				and int(player.resources.get("gold", 0)) > 250 and building.enqueue(MapObject.GUN_GUID):
			continue
		var canoes := _my_units().filter(func(u: Unit) -> bool: return u.unit_type.guid() == UnitWater.CANOE).size()
		var want_canoes := NavGrid.current != null and NavGrid.current.has_water and canoes < CANOE_TARGET
		var options := Array(building.trainable_units()).filter(func(guid: int) -> bool:
			return GameData.stats(guid).get("damage", 0) >= 5 and guid not in Player.COMMANDERS \
					and (guid != UnitWater.CANOE or want_canoes))
		options.shuffle()
		for guid in options:
			if building.enqueue(guid):
				break


## Spend spare food and gold on upgrades, one at a time.
func _research() -> void:
	# Across the water the Native Americans learn to swim first.
	if player.faction == "ind" and not _land_route and player.can_research(SWIM):
		for building: MapObject in _my_buildings():
			if building.queue.is_empty() and SWIM in building.researchable_upgrades():
				building.enqueue(SWIM)
				return
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
## difficulty's first-attack time has passed. A wave gathers at an assembly point first,
## then marches in formation; the badly wounded turn back. A home guard stays behind.
func _command_army(army: Array, hq: MapObject) -> void:
	_check_route()
	_retreat_wounded(army)
	var ready := army.filter(func(u: Unit) -> bool: return not _retreating.has(u.get_instance_id()))
	_keep_guard(ready, hq)
	var intruder := _intruder(hq)
	if intruder:
		for unit: Unit in ready:
			if (unit.state == Unit.State.IDLE or unit.state == Unit.State.MOVING) \
					and (_wave_state != "attacking" or unit not in _wave):
				unit.attack_move(intruder.position)
		if _wave_state == "gathering":
			_wave_state = "home"  # stay and fight
		return
	_raid(ready.filter(func(u: Unit) -> bool: return not _guard.has(u.get_instance_id())))
	match _wave_state:
		"home":
			_form_wave(ready, hq)
		"gathering":
			_gather_wave()
		"attacking":
			_reinforce(ready)
			_press_attack()


## While a wave is out, fresh troops at home follow it once there are enough of them.
func _reinforce(army: Array) -> void:
	if not _land_route:
		return
	var free := army.filter(func(u: Unit) -> bool:
		return not _guard.has(u.get_instance_id()) and u not in _wave and u.state == Unit.State.IDLE)
	if free.size() < maxi(4, _level().wave / 2):
		return
	for unit: Unit in free:
		unit.set_stance(Unit.Stance.AGGRESSIVE)
		unit.attack_move(_wave_target + Vector2(randf_range(-80, 80), randf_range(-80, 80)))
	_wave.append_array(free)


func _check_route() -> void:
	if _elapsed - _route_checked < 120.0:
		return
	_route_checked = _elapsed
	if GameData.cmdline_option("ai-ferry") != "":
		_land_route = false  # test: behave as if the enemy were across the water
		return
	var target := _enemy_base()
	if target == Vector2.INF or NavGrid.current == null or not NavGrid.current.has_water:
		_land_route = true
		return
	var path := NavGrid.current.find_path(_home, target)
	_land_route = not path.is_empty() and path[path.size() - 1].distance_to(target) < 320.0


## Units below RETREAT_BELOW energy leave the wave and go home for a while.
func _retreat_wounded(army: Array) -> void:
	for unit: Unit in army:
		var id := unit.get_instance_id()
		if _retreating.has(id):
			if _elapsed - float(_retreating[id]) > RETREAT_SECONDS or unit.health >= unit.max_health * 0.8:
				_retreating.erase(id)
			continue
		if unit.health < unit.max_health * RETREAT_BELOW and unit.position.distance_to(_home) > 600.0 \
				and unit.state != Unit.State.QUARTERED:
			_retreating[id] = _elapsed
			_wave.erase(unit)
			unit.move_to(_home + Vector2(randf_range(-80, 80), randf_range(60, 140)))


## A fifth of the army (at least two) stays home on the defensive; ranged guards man the
## towers and the Native scouts lie in wait camouflaged.
func _keep_guard(army: Array, hq: MapObject) -> void:
	for id in _guard.keys():
		if not is_instance_valid(instance_from_id(id)):
			_guard.erase(id)
	var wanted := maxi(2, int(army.size() * GUARD_SHARE)) if army.size() >= 4 else 0
	for unit: Unit in army:
		if _guard.size() >= wanted:
			break
		if not _guard.has(unit.get_instance_id()) and unit not in _wave:
			_guard[unit.get_instance_id()] = true
			unit.set_stance(Unit.Stance.DEFENSIVE)
	var towers := _my_buildings().filter(func(b: MapObject) -> bool: return b.capacity() > 0 and b.complete \
			and b.guid not in MapObject.MAIN_BUILDINGS)
	var toward := (_enemy_base() - hq.position).normalized() if _enemy_base() != Vector2.INF else Vector2.DOWN
	for unit: Unit in army:
		if not _guard.has(unit.get_instance_id()) or unit.state != Unit.State.IDLE:
			continue
		for tower: MapObject in towers:
			if unit.unit_type.ranged and tower.has_room_for(unit):
				unit.take_quarters(tower)
				break
		if unit.state == Unit.State.IDLE and unit.quarters == null:
			if unit.position.distance_to(hq.position) > 500.0:
				unit.move_to(hq.position + toward * 220.0 + Vector2(randf_range(-90, 90), randf_range(-60, 60)))
			elif unit.stealth.can_hide() and not unit.stealth.concealed:
				unit.conceal()


func _form_wave(army: Array, hq: MapObject) -> void:
	var free := army.filter(func(u: Unit) -> bool: return not _guard.has(u.get_instance_id()))
	var wave_size: int = _level().wave + _attack_wave * 2
	if _elapsed < _level().first_attack or free.size() < wave_size or _elapsed - _last_attack < 60.0:
		return
	var target := _enemy_base()
	if target == Vector2.INF:
		return
	_wave = free
	_wave_size = free.size()
	_wave_target = target
	var toward := (target - hq.position).normalized()
	_gather_point = hq.position + toward * GATHER_DISTANCE
	if not _land_route:
		_gather_point = _shore_near(hq.position)
		_ferry_started = _elapsed
	_gather_started = _elapsed
	_wave_state = "gathering"
	for unit: Unit in _wave:
		unit.set_stance(Unit.Stance.AGGRESSIVE)
		unit.stealth.uncover()
	_march(_gather_point, false)


## Wait at the assembly point until most of the wave is there (or long enough), then go.
## Across the water the boats take them: board, then sail for the enemy's shore.
func _gather_wave() -> void:
	_wave = _wave.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	if _wave.is_empty():
		_wave_state = "home"
		return
	if not _land_route and not _can_cross_alone():
		_ferry()
		return
	var there := _wave.filter(func(u: Unit) -> bool: return u.position.distance_to(_gather_point) < 220.0).size()
	if there < _wave.size() * 0.75 and _elapsed - _gather_started < GATHER_SECONDS:
		return
	_attack_wave += 1
	_last_attack = _elapsed
	_wave_state = "attacking"
	if GameData.cmdline_option("trace-ai") != "":
		print("t=%ds AI %d attacks with %d units (wave %d%s)" % [_elapsed, player.index, _wave.size(), _attack_wave,
				"" if _land_route else ", swimming"])
	_march(_wave_target, true)


## The Native Americans swim once they know how (mounted units stay behind).
func _can_cross_alone() -> bool:
	if player.faction != "ind":
		return false
	var swimmers := _wave.filter(func(u: Unit) -> bool: return u.water.nav_layer() != NavGrid.Layer.GROUND)
	if swimmers.size() < _level().wave / 2:
		return false
	_wave = swimmers
	return true


func _ferry() -> void:
	var boats := _my_units().filter(func(u: Unit) -> bool: return u.water.is_boat())
	if boats.is_empty():
		if _elapsed - _ferry_started > 240.0:
			_wave_state = "home"  # no boats came: try again later
		return
	var aboard := 0
	for boat: Unit in boats:
		aboard += boat.water.passengers.size()
	var waiting := _wave.filter(func(u: Unit) -> bool: return not u.inside)
	for boat: Unit in boats:
		if boat.state == Unit.State.IDLE and boat.water.passengers.size() < boat.water.capacity() \
				and boat.position.distance_to(_gather_point) > 200.0 and boat.water.passengers.is_empty():
			boat.move_to(_gather_point)
		var room := boat.water.capacity() - boat.water.passengers.size()
		for unit: Unit in waiting.duplicate():
			if room <= 0:
				break
			if unit.water.vessel == null and unit.state == Unit.State.IDLE:
				unit.board(boat)
				waiting.erase(unit)
				room -= 1
	var full := boats.all(func(b: Unit) -> bool: return b.water.passengers.size() >= b.water.capacity())
	if aboard > 0 and (waiting.is_empty() or full or _elapsed - _ferry_started > 90.0):
		_attack_wave += 1
		_last_attack = _elapsed
		_wave_state = "attacking"
		if GameData.cmdline_option("trace-ai") != "":
			print("t=%ds AI %d ferries %d units (wave %d)" % [_elapsed, player.index, aboard, _attack_wave])
		var landing := _shore_near(_wave_target)
		for boat: Unit in boats:
			if not boat.water.passengers.is_empty():
				boat.unload_at(landing)
		_wave = _wave.filter(func(u: Unit) -> bool: return u.inside)
		_wave_size = _wave.size()


## The wave presses on to the next enemy building once its target falls; when it has
## melted away the survivors come home.
func _press_attack() -> void:
	_wave = _wave.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	if _wave.size() < maxi(1, _wave_size / 4):
		for unit: Unit in _wave:
			if not unit.inside:
				unit.move_to(_home + Vector2(randf_range(-80, 80), randf_range(60, 140)))
		_wave_state = "home"
		return
	var target := _enemy_base()
	if target == Vector2.INF:
		return
	if target.distance_to(_wave_target) > 64.0:
		_wave_target = target
		_march(target, true)
		return
	for unit: Unit in _wave:
		if unit.state == Unit.State.IDLE and not unit.inside:
			unit.attack_move(target + Vector2(randf_range(-60, 60), randf_range(-60, 60)))
	# Boats that have put their troops ashore go back for more.
	for boat: Unit in _my_units().filter(func(u: Unit) -> bool: return u.water.is_boat() and u.water.passengers.is_empty()):
		if boat.state == Unit.State.IDLE and boat.position.distance_to(_home) > 900.0:
			boat.move_to(_shore_near(_home))


## Move the wave to `point` in a double line facing it.
func _march(point: Vector2, fighting: bool) -> void:
	var units := _wave.filter(func(u: Unit) -> bool: return not u.inside)
	if units.is_empty():
		return
	var centre := SelectionController._centre(units)
	var facing := (point - centre).normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN
	var side := facing.orthogonal()
	units.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.dot(side) < b.position.dot(side))
	var slots := SelectionController.formation_slots(units.size(), Unit.Formation.DOUBLE_LINE)
	for i in units.size():
		var unit: Unit = units[i]
		unit.formation = Unit.Formation.DOUBLE_LINE
		var spot := point + (side * slots[i].x - facing * slots[i].y) * SelectionController.FORMATION_SPACING
		if fighting:
			unit.attack_move(spot)
		else:
			unit.move_to(spot)


## The water's edge nearest `point` (on the water), or the point itself on a dry map.
func _shore_near(point: Vector2) -> Vector2:
	var nav := NavGrid.current
	if nav == null or not nav.has_water:
		return point
	var cell := nav.nearest_passable(nav.cell_of(point), 60, NavGrid.Layer.WATER)
	return nav.center_of(cell) if cell.x >= 0 else point


## Robbers rob enemy banks, missions and gold warehouses in reach; thieves steal the enemy's
## wagons when they see one.
func _raid(army: Array) -> void:
	for unit: Unit in army:
		if unit.state != Unit.State.IDLE and unit.state != Unit.State.MOVING:
			continue
		if unit.work.can_steal():
			for other in Unit.all_units:
				if other.is_alive() and other.team > 0 and other.team != player.index and other.unit_type.is_transport() \
						and other.position.distance_to(unit.position) < unit.sight():
					unit.steal(other)
					break
		if unit.work.can_rob() and unit.state != Unit.State.GATHERING:
			for object in MapObject.structures:
				if object.is_building() and object.owner_index > 0 and object.owner_index != player.index \
						and object.is_alive() and UnitWork.loot_of(object) > 0 and object.position.distance_to(unit.position) < 900.0:
					unit.rob(object)
					break


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
	for object in MapObject.structures:
		if object.is_building() and object.owner_index > 0 and object.owner_index != player.index and object.is_alive():
			if best == Vector2.INF or object.guid in MapObject.MAIN_BUILDINGS:
				best = object.position
	return best
