class_name AiBuilder
extends RefCounted
## What the AI builds and where. In order: housing ahead of need; a wood store by a big
## forest and a gold warehouse by a mine when they lie far from home; the structures that
## train soldiers (each new kind with whatever it requires first, saving up for it rather
## than buying another cheap one; duplicates only when rich). Later, when stock piles up:
## towers toward the enemy (the Native Americans dig pitfalls), a trading post, a second
## mine; a shipyard, or the Natives' camouflage school (for Swim), when the enemy is across
## the water. Sites are searched in ever wider rings round the spot.

const TOWERS := [213, 413, 313]  # Mexican tower, American watchtower, outlaw lookout
const TOWER_TARGET := [0, 1, 2, 3]  # per difficulty
const PITFALL_TARGET := [0, 1, 2, 3]
const MAX_WOOD_STORES := 4
const FOREST_TREES := 10  # a wood store only by a forest this big
const FAR_FROM_HQ := 380.0  # a resource this far away gets its own drop-off building
const RETRY_SECONDS := 90.0  # after a structure found no room
const CAMOUFLAGE_SCHOOL := 112

var ai: AiPlayer
var _failed := {}  # structure GUID -> when it last found no room
var _nearest_cache := {}  # "resource@x,y" -> [MapObject, when]


func _init(owner: AiPlayer) -> void:
	ai = owner


func think(workers: Array, hq: MapObject) -> void:
	_build(workers, hq)
	_build_extras(workers, hq)


func sites() -> int:
	return ai.my_buildings().filter(func(b: MapObject) -> bool: return not b.complete).size()


func unfinished_site() -> MapObject:
	for building in ai.my_buildings():
		if not building.complete:
			return building
	return null


func _build(workers: Array, hq: MapObject) -> void:
	var player := ai.player
	if workers.size() < 3 or sites() >= ai.level().sites:
		return
	var buildings := ai.my_buildings()
	var owned := {}
	for b: MapObject in buildings:
		owned[b.guid] = owned.get(b.guid, 0) + 1
	# Housing.
	var house := _house_guid()
	var room := player.population_cap() - player.population() - player.queued_units()
	if house >= 0 and room < (8 if ai.rich() else 4) and ai.affordable(house) and place(house, hq.position, workers):
		return
	if room < 1:
		return
	# A wood store at the nearest forest, a gold warehouse at the nearest mine.
	var wood_store := ai.faction_guid(MapObject.DROP_OFFS.wood)
	var forest := nearest_resource("wood", hq.position)
	var wood_stores := buildings.filter(func(b: MapObject) -> bool: return b.guid == wood_store).size()
	if wood_store >= 0 and forest and wood_stores < MAX_WOOD_STORES and _trees_near(forest.position) >= FOREST_TREES \
			and no_drop_off_near("wood", forest.position) and _worth_trying(wood_store) \
			and forest.position.distance_to(hq.position) > FAR_FROM_HQ and ai.affordable(wood_store) \
			and place(wood_store, forest.position, workers, 110, FAR_FROM_HQ * 0.8):
		return
	var gold_store := _gold_store_guid()
	var mine := nearest_resource("gold", hq.position)
	if gold_store >= 0 and mine and no_drop_off_near("gold", mine.position) and _worth_trying(gold_store) \
			and mine.position.distance_to(hq.position) > FAR_FROM_HQ and ai.affordable(gold_store) \
			and player.meets_prerequisites(gold_store) and place(gold_store, mine.position, workers, 110, FAR_FROM_HQ * 0.8):
		return
	# Soldiers, once most of the workforce is in place (the first one a little earlier).
	var production := buildings.filter(func(b: MapObject) -> bool: return ai.produces_army(b.guid)).size()
	if production >= _production_limit():
		return
	if production > 0 and not ai.workers_ready():
		return
	if production == 0 and workers.size() < ai.level().workers / 3:
		return
	var options := []
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") != player.faction or stats.get("kind") != "structure" or not ai.produces_army(guid):
			continue
		if owned.has(guid) and (not ai.rich() or not player.meets_prerequisites(guid)):
			continue
		options.append(guid)
	options.sort_custom(func(a: int, b: int) -> bool:
		if owned.has(a) != owned.has(b):
			return not owned.has(a)  # new kinds first
		return _chain_cost(a) < _chain_cost(b))
	for guid in options:
		if not owned.has(guid):
			if sites() > 0:
				return  # one step of a chain at a time
			if build_with_prerequisites(guid, hq.position, workers) or _worth_trying(guid):
				return  # built a step, or saving up for it rather than buying another cheap one
			continue
		if ai.affordable(guid) and place(guid, hq.position, workers):
			return


## What a structure costs with the structures it still requires.
func _chain_cost(guid: int, depth := 0) -> int:
	var total := ai.total_cost(guid)
	if depth < 3:
		for required in GameData.prerequisites(guid):
			if not ai.player.has_building(required):
				total += _chain_cost(required, depth + 1)
	return total


## More production when stock piles up (one more when rich, two when very rich).
func _production_limit() -> int:
	var limit: int = ai.level().production
	if ai.rich():
		limit += 1
	if int(ai.player.resources.get("wood", 0)) > AiPlayer.RICH_WOOD * 3 \
			and int(ai.player.resources.get("gold", 0)) > AiPlayer.RICH_OTHER:
		limit += 1
	return limit


func _house_guid() -> int:
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") == ai.player.faction and stats.get("kind") == "structure" \
				and int(stats.get("housing", 0)) > 0 and guid not in MapObject.MAIN_BUILDINGS:
			return guid
	return -1


func _gold_store_guid() -> int:
	return ai.faction_guid(Array(MapObject.DROP_OFFS.gold).filter(func(g: int) -> bool: return g not in MapObject.MAIN_BUILDINGS))


## Build `guid`, or first whichever structure it still requires; true when a site went up.
func build_with_prerequisites(guid: int, around: Vector2, workers: Array, depth := 0) -> bool:
	if depth > 2:
		return false
	for required in GameData.prerequisites(guid):
		if not ai.player.has_building(required):
			if ai.my_buildings().any(func(b: MapObject) -> bool: return b.guid == required):
				return false  # going up already
			return build_with_prerequisites(required, around, workers, depth + 1)
	return ai.affordable(guid) and _worth_trying(guid) and place(guid, around, workers)


func _build_extras(workers: Array, hq: MapObject) -> void:
	var player := ai.player
	if workers.size() < 3 or sites() >= ai.level().sites or not ai.workers_ready():
		return
	var buildings := ai.my_buildings()
	var count := func(guids: Array) -> int:
		return buildings.filter(func(b: MapObject) -> bool: return b.guid in guids).size()
	var enemy := ai.enemy_base()
	var toward := (enemy - hq.position).normalized() if enemy != Vector2.INF else Vector2.DOWN
	# Across the water: a shipyard first, or for the Native Americans the school that teaches Swim.
	var shipyard := ai.faction_guid(MapObject.SHIPYARDS)
	if not ai.army.land_route and shipyard >= 0 and count.call([shipyard]) == 0 and ai.affordable(shipyard) \
			and _worth_trying(shipyard) and _place_by_water(shipyard, hq.position, workers):
		return
	if player.faction == "ind" and not ai.army.land_route and not player.researched.has(AiArmy.SWIM) \
			and count.call([CAMOUFLAGE_SCHOOL]) == 0:
		build_with_prerequisites(CAMOUFLAGE_SCHOOL, hq.position, workers)
		return
	if not ai.rich():
		return
	var tower := ai.faction_guid(TOWERS)
	if tower >= 0 and count.call([tower]) < TOWER_TARGET[ai.difficulty] and player.meets_prerequisites(tower) \
			and ai.affordable(tower) and _worth_trying(tower) \
			and place(tower, hq.position + toward.rotated(randf_range(-0.8, 0.8)) * 300.0, workers, 0, 260.0):
		return
	var pit := MapObject.PITFALL_GUID
	if player.faction == "ind" and count.call([pit]) < PITFALL_TARGET[ai.difficulty] and player.meets_prerequisites(pit) \
			and ai.affordable(pit) and _worth_trying(pit) \
			and place(pit, hq.position + toward.rotated(randf_range(-0.5, 0.5)) * 520.0, workers, 0, 200.0):
		return
	var post := ai.faction_guid(BuildingProduction.TRADE_BUILDINGS)
	if post >= 0 and count.call([post]) == 0 and build_with_prerequisites(post, hq.position, workers):
		return
	# A second mine with its own warehouse, so the miners spread out.
	var gold_store := _gold_store_guid()
	var served := 0
	var next_mine: MapObject = null
	var mines := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.stock.resource == "gold" and o.stock.amount > 300)
	mines.sort_custom(func(a: MapObject, b: MapObject) -> bool: return a.position.distance_to(hq.position) < b.position.distance_to(hq.position))
	for mine: MapObject in mines:
		if not no_drop_off_near("gold", mine.position):
			served += 1
		elif next_mine == null and mine.position.distance_to(hq.position) < 2600.0 and not ai.enemy_near(mine.position, 700.0):
			next_mine = mine
	if served < 2 and next_mine and gold_store >= 0 and ai.affordable(gold_store) and _worth_trying(gold_store) \
			and player.meets_prerequisites(gold_store):
		place(gold_store, next_mine.position, workers, 110, FAR_FROM_HQ * 0.8)


# ------------------------------------------------------------------ resources

## The nearest tree or mine with something left (remembered for a while: the search
## covers thousands of trees).
func nearest_resource(resource: String, from: Vector2) -> MapObject:
	var key := "%s@%d,%d" % [resource, int(from.x), int(from.y)]
	var cached: Array = _nearest_cache.get(key, [])
	if not cached.is_empty() and ai.elapsed - float(cached[1]) < 15.0 and is_instance_valid(cached[0]) and cached[0].stock.amount > 0:
		return cached[0]
	var best: MapObject = null
	for object in MapObject.all_objects:
		if object.stock.resource == resource and object.stock.amount > 0 and not object.is_field() \
				and (best == null or from.distance_to(object.position) < from.distance_to(best.position)):
			best = object
	_nearest_cache[key] = [best, ai.elapsed]
	return best


func _trees_near(at: Vector2) -> int:
	var count := 0
	for object in MapObject.all_objects:
		if object.stock.resource == "wood" and object.stock.amount > 0 and object.position.distance_to(at) < 260.0:
			count += 1
	return count


func no_drop_off_near(resource: String, at: Vector2) -> bool:
	for object in MapObject.structures:
		if object.owner_index == ai.player.index and object.is_building() \
				and (resource in object.accepts or (not object.complete and object.guid in MapObject.DROP_OFFS.get(resource, []))) \
				and object.position.distance_to(at) < FAR_FROM_HQ:
			return false
	return true


# ------------------------------------------------------------------ placing

func _worth_trying(guid: int) -> bool:
	return ai.elapsed - float(_failed.get(guid, -1000.0)) > RETRY_SECONDS


## Start building `guid` near `around` (within `max_distance` of it); false when there is
## no room there, which also keeps the AI from retrying it for a while.
func place(guid: int, around: Vector2, builders: Array, min_radius := 220, max_distance := INF) -> bool:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, ai.biome))
	if type == null or builders.is_empty():
		return false
	var spot := find_spot(type, around, min_radius)
	if spot == Vector2.INF or spot.distance_to(around) > max_distance:
		_failed[guid] = ai.elapsed
		return false
	var cost: Dictionary = GameData.stats(guid).get("cost", {}).duplicate()
	cost.erase("population")
	if not ai.player.spend(cost):
		return false
	var site := MapObject.new()
	site.position = spot
	if not site.setup(type, ai.player.index, 0, true):
		site.free()
		return false
	ai.units_root.add_child(site)
	ai.forget_buildings()
	if not site.is_trap():
		NavGrid.current.block_footprint(type, spot)
	site.unit_trained.connect(ai.get_parent()._on_unit_trained)
	ai.trace("builds %s (workers %d, units %d/%d, wood %d)" % [GameData.stats(guid).get("name"), builders.size(),
			ai.player.population(), ai.player.population_cap(), ai.player.resources.get("wood", 0)])
	var nearest := builders.duplicate()
	nearest.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_to(spot) < b.position.distance_to(spot))
	for worker: Unit in nearest.slice(0, 3):
		worker.build(site)
	return true


## A field (paid for, no workers needed: the women sow it) near the grain store.
func plant_field(near: Vector2) -> MapObject:
	var type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.FIELD_GUID, ai.biome))
	var spot := find_spot(type, near, 120)
	if spot == Vector2.INF:
		return null
	var cost: Dictionary = GameData.stats(MapObject.FIELD_GUID).get("cost", {}).duplicate()
	cost.erase("population")
	if not ai.player.spend(cost):
		return null
	var field := MapObject.new()
	field.position = spot
	field.setup(type, ai.player.index)
	ai.units_root.add_child(field)
	return field


## A shipyard at the nearest stretch of shore to `around`.
func _place_by_water(guid: int, around: Vector2, builders: Array) -> bool:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, ai.biome))
	if type == null:
		return false
	var nav := NavGrid.current
	for radius in range(160, 2400, 48):
		for step in 24:
			var spot := (around + Vector2(radius, 0).rotated(step * TAU / 24.0)).snapped(Vector2(NavGrid.CELL, NavGrid.CELL))
			if footprint_free(type, spot, nav) and MapObject.by_water(type, spot):
				return place(guid, spot, builders, 0, 64.0)
	_failed[guid] = ai.elapsed
	return false


## Search outward from `around` for a free footprint: ever wider rings, sampled about every
## 48 px along each (bases hemmed in by cliffs and water need the search to reach well out).
static func find_spot(type: ObjectTypes.ObjectType, around: Vector2, min_radius := 220) -> Vector2:
	var nav := NavGrid.current
	for radius in range(min_radius, 1500, 32):
		var steps := maxi(12, int(TAU * radius / 48.0))
		for step in steps:
			var spot := around + Vector2(radius, 0).rotated(step * TAU / steps + radius * 0.37)
			spot = (spot / NavGrid.CELL).round() * NavGrid.CELL
			if footprint_free(type, spot, nav):
				return spot
	return Vector2.INF


## Walkable ground under the whole footprint, and a margin to other buildings so they
## don't wall each other in.
static func footprint_free(type: ObjectTypes.ObjectType, at: Vector2, nav: NavGrid) -> bool:
	var rect := MapObject.footprint_rect_for(type, at)
	var origin := nav.cell_of(rect.position)
	for i in type.footprint_cells.size():
		var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
		if not nav.is_walkable(cell):
			return false
	for object in MapObject.structures:
		if object.is_building() and object.footprint_rect().grow(32).intersects(rect):
			return false
	return true
