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
## Walls (Mexicans, outlaws, Americans), once wood piles up, where the ground makes them
## worth it: across the narrowest choke on the way from home to an enemy (between cliffs,
## water, forest or buildings), from one side of it to the other, with a gate left open
## where the way crosses. On open ground, where a wall is simply walked round, none.
const WALL_TARGET := [0, 1, 2, 3]  # passes walled, per difficulty
const WALL_NEAR := 260.0  # how far along the way from home the choke may lie
const WALL_FAR := 1800.0
const WALL_MAX_SIDE := 14  # pieces from the way to either side of the choke, at most
const WALL_GATE := 1  # pieces left out each side of the way (a gate three pieces wide)
const WALL_CLEARANCE := 64.0  # from mines, fields and buildings
const WALL_DETOUR := 1.3  # the way to the enemy may grow by this much, and a little

var ai: AiPlayer
var _failed := {}  # structure GUID -> when it last found no room
var _nearest_cache := {}  # "resource@x,y" -> [MapObject, when]


func _init(owner: AiPlayer) -> void:
	ai = owner


func think(workers: Array, hq: MapObject) -> void:
	_build(workers, hq)
	_build_extras(workers, hq)


## Construction sites going on (a wall's pieces count once, as one project).
func sites() -> int:
	var walls := 0
	var count := 0
	for b: MapObject in ai.my_buildings():
		if not b.complete:
			if WallLine.is_wall(b.guid):
				walls = 1
			else:
				count += 1
	return count + walls


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
	# Walls cost wood alone: they go up once wood piles up, whatever the gold and food.
	if _build_wall(workers, hq):
		return
	if not ai.rich():
		return
	var tower := ai.faction_guid(TOWERS)
	if tower >= 0 and count.call([tower]) < TOWER_TARGET[ai.difficulty] and player.meets_prerequisites(tower) \
			and ai.affordable(tower) and _worth_trying(tower) \
			and place(tower, hq.position + toward.rotated(Sim.randf_range(-0.8, 0.8)) * 300.0, workers, 0, 260.0):
		return
	var pit := MapObject.PITFALL_GUID
	if player.faction == "ind" and count.call([pit]) < PITFALL_TARGET[ai.difficulty] and player.meets_prerequisites(pit) \
			and ai.affordable(pit) and _worth_trying(pit) \
			and place(pit, hq.position + toward.rotated(Sim.randf_range(-0.5, 0.5)) * 520.0, workers, 0, 200.0):
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


## The next stretch of wall, if this people builds walls and it's time for one.
func _build_wall(workers: Array, hq: MapObject) -> bool:
	var player := ai.player
	var pieces: Array = WallLine.PIECES.get(player.faction, [])
	if pieces.is_empty() or int(player.resources.get("wood", 0)) < AiPlayer.RICH_WOOD \
			or ai.enemy_base() == Vector2.INF or not ai.army.land_route:
		return false
	var corner: int = pieces[0]
	var built := ai.my_buildings().filter(func(b: MapObject) -> bool: return WallLine.is_wall(b.guid))
	if built.any(func(b: MapObject) -> bool: return not b.complete):
		return false  # one stretch at a time
	if _passes_walled(built) >= WALL_TARGET[ai.difficulty] or not player.meets_prerequisites(corner) \
			or not _worth_trying(corner):
		return false
	var cost: Dictionary = MapRules.stats(player.index, corner).get("cost", {})
	var stock := player.resources.duplicate()
	for i in (WALL_MAX_SIDE + 1) * 2:
		if not BuildController._take(stock, cost):
			return false  # not before the widest choke could be paid
	var plan := _wall_plan(hq, corner, built)
	if plan.is_empty():
		_failed[corner] = ai.elapsed
		return false
	var nearest := workers.duplicate()
	nearest.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_to(plan[0].position) < b.position.distance_to(plan[0].position))
	for piece in plan:
		var type := ObjectTypes.get_type(piece.type_id)
		if not player.spend(cost):
			break
		var site := MapObject.new()
		site.position = piece.position
		if not site.setup(type, player.index, 0, true):
			site.free()
			continue
		ai.units_root.add_child(site)
		NavGrid.current.block_footprint(type, piece.position)
		for worker: Unit in nearest.slice(0, 2):
			worker.work.queue_build(site)  # one piece after another, then back to work
	ai.forget_buildings()
	ai.trace("walls a choke: %d pieces at %s" % [plan.size(), plan[0].position])
	return true


## How many passes this people has walled: its wall pieces in groups, the two sides of a
## gate counting as one.
func _passes_walled(walls: Array) -> int:
	var left := walls.duplicate()
	var groups := 0
	while not left.is_empty():
		groups += 1
		var reach := [left.pop_back()]
		while not reach.is_empty():
			var piece: MapObject = reach.pop_back()
			for other: MapObject in left.duplicate():
				if other.position.distance_to(piece.position) < WallLine.STEP_LEFT.length() * (WALL_GATE * 2 + 2.5):
					left.erase(other)
					reach.append(other)
	return groups


## The wall for the best choke: on the way from home to each enemy (nearest first), the
## narrowest crossing of open ground along one of the wall's two diagonals, the pieces
## running from edge to edge with the gate on the way. Every piece has to fit and the way
## has to stay open through the gate, or the next narrowest is tried. [] when there's none.
func _wall_plan(hq: MapObject, corner: int, walls: Array) -> Array[Dictionary]:
	var nav := NavGrid.current
	var candidates := []
	for goal in _enemy_bases(hq.position):
		var path := nav.find_path(hq.position, goal)
		var walked := 0.0
		var at := hq.position
		for point in path:
			var leg := point - at
			var steps := int(leg.length() / 32.0)
			for k in steps:
				var spot := at + leg * (k / float(maxi(steps, 1)))
				var travelled := walked + leg.length() * k / float(maxi(steps, 1))
				if travelled >= WALL_NEAR and travelled <= WALL_FAR:
					_measure_pass(candidates, (spot / NavGrid.CELL).round() * NavGrid.CELL, leg.normalized(), travelled, walls, goal)
			walked += leg.length()
			at = point
			if walked > WALL_FAR:
				break
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	var unfit := 0
	var closing := 0
	for choke: Dictionary in candidates.slice(0, 12):
		var plan := _pass_pieces(choke, corner)
		if plan.is_empty():
			unfit += 1
		elif not _leaves_way_out(plan, hq.position, choke.goal, choke.at):
			closing += 1
		else:
			return plan
	ai.trace("no pass to wall: %d found, %d with ground a wall can't stand on, %d not closed by it" % [
			candidates.size(), unfit, closing])
	return []


## The choke at `at` across each diagonal that cuts the way (`dir`): how many pieces of open
## ground lie to either side before cliff, water or anything standing stops it.
func _measure_pass(candidates: Array, at: Vector2, dir: Vector2, travelled: float, walls: Array, goal: Vector2) -> void:
	for wall: MapObject in walls:
		if wall.position.distance_to(at) < 320.0:
			return  # walled already
	for axis: Vector2 in [WallLine.STEP_LEFT, WallLine.STEP_RIGHT]:
		if absf(dir.dot(axis.normalized())) > 0.95:
			continue  # running along the way, not across it (the diagonals are shallow: an
			# east-west way is crossed at 27 degrees)
		var back := _open_steps(at, -axis)
		var ahead := _open_steps(at, axis)
		if back > WALL_MAX_SIDE or ahead > WALL_MAX_SIDE or back + ahead < WALL_GATE * 2 + 2:
			continue  # open ground, or too narrow to need more than the gate
		if _own_building_at(at - axis * (back + 1)) or _own_building_at(at + axis * (ahead + 1)):
			continue  # a lane between its own buildings, not a pass
		candidates.append({"at": at, "axis": axis, "back": back, "ahead": ahead, "goal": goal,
				"score": (back + ahead) * 32.0 + travelled * 0.2})


func _own_building_at(point: Vector2) -> bool:
	for building: MapObject in ai.my_buildings():
		if not WallLine.is_wall(building.guid) and building.footprint_rect().grow(24.0).has_point(point):
			return true
	return false


## Wall pieces' worth of ground from `from` in steps of `step` up to the pass's solid edge:
## three steps of cliff, water or anything standing in a row. A lone tree or rock in the
## way is stepped past (it closes its own spot in the line). Beyond the limit: open ground.
func _open_steps(from: Vector2, step: Vector2) -> int:
	var last_open := 0
	var blocked := 0
	for k in range(1, WALL_MAX_SIDE + 4):
		if _open_at(from + step * k):
			last_open = k
			blocked = 0
			if k > WALL_MAX_SIDE:
				return WALL_MAX_SIDE + 1
		else:
			blocked += 1
			if blocked >= 3:
				return last_open
	return WALL_MAX_SIDE + 1


## Whether a wall piece at `piece` would stand on walkable ground (both its cells).
func _open_at(piece: Vector2) -> bool:
	var nav := NavGrid.current
	return nav.is_walkable(nav.cell_of(piece + Vector2(-8, 8))) and nav.is_walkable(nav.cell_of(piece + Vector2(8, 8)))


## The pieces closing `choke`, both sides of the gate, in runs between whatever already
## stands in the line; [] if any of them can't go there.
func _pass_pieces(choke: Dictionary, corner: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var axis: Vector2 = choke.axis
	for side in [[-1.0, choke.back], [1.0, choke.ahead]]:
		var step: Vector2 = axis * side[0]
		var run_from := -1
		for k in range(WALL_GATE + 1, int(side[1]) + 2):
			var open := k <= int(side[1]) and _open_at(choke.at + step * k)
			if open and run_from < 0:
				run_from = k
			elif not open and run_from >= 0:
				for piece in WallLine.plan(corner, choke.at + step * run_from, choke.at + step * (k - 1), ai.biome):
					var type := ObjectTypes.get_type(piece.type_id)
					if not BuildController.can_place_for(type, piece.position, ai.player.index, true) or not _wall_clear(piece.position):
						return []
					out.append(piece)
				run_from = -1
	return out


func _wall_clear(at: Vector2) -> bool:
	for object in MapObject.structures:
		if object.position.distance_to(at) < WALL_CLEARANCE * 3.0 and not WallLine.is_wall(object.guid) \
				and (object.is_building() or object.is_field()) \
				and object.footprint_rect().grow(WALL_CLEARANCE).has_point(at):
			return false
	for object in MapObject.all_objects:
		if object.stock.resource == "gold" and object.position.distance_to(at) < WALL_CLEARANCE * 2.0:
			return false  # not across a mine's mouth
	return true


## Enemy main buildings (else any of their buildings), nearest first.
func _enemy_bases(from: Vector2) -> Array:
	var mains := []
	var others := []
	for object in MapObject.structures:
		if object.is_building() and object.owner_index > 0 and object.owner_index != ai.player.index and object.is_alive():
			(mains if object.guid in MapObject.MAIN_BUILDINGS else others).append(object.position)
	var out := mains if not mains.is_empty() else others.slice(0, 1)
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(from) < b.distance_to(from))
	return out


## Whether, with the wall in place, the way from home to the enemy still goes through, by
## the gate (`gate`; not round the wall's ends, which would leave the pass open) and
## without much of a detour. Tried with the pieces' cells blocked for a moment.
func _leaves_way_out(plan: Array[Dictionary], from: Vector2, goal: Vector2, gate: Vector2) -> bool:
	var nav := NavGrid.current
	var before := _path_length(nav.find_path(from, goal), from)
	for piece in plan:
		nav.block_footprint(ObjectTypes.get_type(piece.type_id), piece.position)
	var path := nav.find_path(from, goal)
	var after := _path_length(path, from)
	for piece in plan:
		nav.unblock_footprint(ObjectTypes.get_type(piece.type_id), piece.position)
	var reaches := not path.is_empty() and path[path.size() - 1].distance_to(goal) < 200.0
	var by_gate := false
	var at := from
	for point in path:
		by_gate = by_gate or Geometry2D.get_closest_point_to_segment(gate, at, point).distance_to(gate) < 64.0
		at = point
	return reaches and by_gate and after <= before * WALL_DETOUR + 200.0


static func _path_length(path: PackedVector2Array, from: Vector2) -> float:
	var length := 0.0
	var at := from
	for point in path:
		length += at.distance_to(point)
		at = point
	return length


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
	var cost: Dictionary = MapRules.stats(ai.player.index, guid).get("cost", {}).duplicate()
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
	var cost: Dictionary = MapRules.stats(ai.player.index, MapObject.FIELD_GUID).get("cost", {}).duplicate()
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


## Walkable ground under the whole footprint, and a margin to other buildings and fields so
## they don't wall each other in (fields leave the ground walkable, so it alone won't tell).
static func footprint_free(type: ObjectTypes.ObjectType, at: Vector2, nav: NavGrid) -> bool:
	var rect := MapObject.footprint_rect_for(type, at)
	var origin := nav.cell_of(rect.position)
	for i in type.footprint_cells.size():
		var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
		if not nav.is_walkable(cell):
			return false
	for object in MapObject.structures:
		if (object.is_building() or object.is_field()) and object.footprint_rect().grow(32).intersects(rect):
			return false
	return true
