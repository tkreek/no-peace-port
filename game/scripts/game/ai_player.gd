class_name AiPlayer
extends Node
## A straightforward skirmish opponent using the same rules as the human player:
## keeps workers gathering, trains more, builds houses and unit-producing structures whose
## prerequisites are met, trains soldiers, and attacks once its army is large enough.

const THINK_SECONDS := 1.5
const TARGET_WORKERS := 10
const ATTACK_ARMY := 6
const WOOD_SHARE := 0.6
const MAX_PRODUCTION_BUILDINGS := 3

var player: Player
var units_root: Node2D
var biome := "steppe"
var _timer := 0.0
var _attack_wave := 0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = THINK_SECONDS
	_think()


func _think() -> void:
	var units := _my_units()
	var workers := units.filter(func(u: Unit) -> bool: return u.unit_type.can_gather("wood"))
	var army := units.filter(func(u: Unit) -> bool:
		return not u.unit_type.can_gather("wood") and u.unit_type.damage >= 5)
	var hq := _hq()
	if hq == null:
		return
	_assign_workers(workers)
	if workers.size() < TARGET_WORKERS:
		for guid in hq.trainable_units():
			if GameData.stats(guid).get("damage", 0) <= 4 and _is_gatherer(guid) and hq.queue.size() < 2:
				hq.enqueue(guid)
				break
	_build(workers, hq)
	_train_army()
	if army.size() >= ATTACK_ARMY + _attack_wave * 2:
		_attack(army)


func _my_units() -> Array:
	return units_root.get_children().filter(func(n: Node) -> bool:
		return n is Unit and n.team == player.index and n.is_alive())


func _my_buildings() -> Array:
	return MapObject.all_objects.filter(func(o: MapObject) -> bool:
		return o.is_building() and o.owner_index == player.index and o.is_alive())


func _hq() -> MapObject:
	for building in _my_buildings():
		if not building.accepts.is_empty() and building.accepts.size() > 1:
			return building
	return null


func _is_gatherer(guid: int) -> bool:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, biome))
	if type == null:
		return false
	var unit_type := UnitType.load_type(type.directory())
	return unit_type != null and unit_type.can_gather("wood")


## Idle workers go to wood or gold so that roughly WOOD_SHARE of them cut wood.
func _assign_workers(workers: Array) -> void:
	var on_wood := workers.filter(func(u: Unit) -> bool: return u.gather_source and u.gather_source.resource == "wood").size()
	for worker: Unit in workers:
		if worker.state != Unit.State.IDLE:
			continue
		var site := _unfinished_site()
		if site:
			worker.build(site)
			continue
		var want_wood := on_wood < ceili(workers.size() * WOOD_SHARE)
		var source := worker._nearest_source("wood" if want_wood else "gold")
		if source == null:
			source = worker._nearest_source("gold" if want_wood else "wood")
		if source:
			worker.gather(source)
			if source.resource == "wood":
				on_wood += 1


func _unfinished_site() -> MapObject:
	for building in _my_buildings():
		if not building.complete:
			return building
	return null


func _build(workers: Array, hq: MapObject) -> void:
	if workers.size() < 3 or _unfinished_site() != null:
		return
	var buildings := _my_buildings()
	var wanted := _next_structure(buildings)
	if wanted < 0:
		return
	var type_id := GameData.type_for_guid(wanted, biome)
	var type := ObjectTypes.get_type(type_id)
	if type == null:
		return
	var spot := _find_spot(type, hq.position)
	if spot == Vector2.INF:
		return
	var cost: Dictionary = GameData.stats(wanted).get("cost", {}).duplicate()
	cost.erase("population")
	if not player.spend(cost):
		return
	var site := MapObject.new()
	site.position = spot
	if not site.setup(type, player.index, 0, true):
		site.free()
		return
	units_root.add_child(site)
	NavGrid.current.block_footprint(type, spot)
	site.unit_trained.connect(get_parent()._on_unit_trained)
	# Two closest workers go and build it.
	var builders := workers.duplicate()
	builders.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.position.distance_to(spot) < b.position.distance_to(spot))
	for worker: Unit in builders.slice(0, 3):
		worker.build(site)


## A house first, then affordable structures that unlock combat units.
func _next_structure(buildings: Array) -> int:
	var owned := {}
	for b: MapObject in buildings:
		owned[b.guid] = owned.get(b.guid, 0) + 1
	var house := _faction_structure_named(["House", "Sleeping tepee", "Boarding house"])
	var room := player.population_cap() - player.population() - player.queued_units()
	if house >= 0 and room < 4 and _affordable(house):
		return house
	if room < 1:
		return -1  # save up for housing first
	var production := buildings.filter(func(b: MapObject) -> bool: return _produces_army(b.guid)).size()
	if production >= MAX_PRODUCTION_BUILDINGS:
		return -1
	var options := []
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") != player.faction or stats.get("kind") != "structure":
			continue
		if owned.has(guid) or not player.meets_prerequisites(guid) or not _produces_army(guid):
			continue
		options.append(guid)
	options.sort_custom(func(a: int, b: int) -> bool: return _total_cost(a) < _total_cost(b))
	for guid in options:
		if _affordable(guid):
			return guid
	return -1


func _faction_structure_named(names: Array) -> int:
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") == player.faction and stats.get("kind") == "structure" and stats.get("name") in names:
			return guid
	return -1


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


## Search outward from the HQ for a free footprint.
func _find_spot(type: ObjectTypes.ObjectType, around: Vector2) -> Vector2:
	var nav := NavGrid.current
	for radius in range(220, 900, 48):
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


func _train_army() -> void:
	for building: MapObject in _my_buildings():
		if not building.complete or building.queue.size() >= 2:
			continue
		var options := Array(building.trainable_units()).filter(func(guid: int) -> bool:
			return GameData.stats(guid).get("damage", 0) >= 5)
		options.shuffle()
		for guid in options:
			if building.enqueue(guid):
				break


func _attack(army: Array) -> void:
	var target := _enemy_base()
	if target == Vector2.INF:
		return
	_attack_wave += 1
	for unit: Unit in army:
		if unit.state == Unit.State.IDLE:
			unit.attack_move(target + Vector2(randf_range(-60, 60), randf_range(-60, 60)))


func _enemy_base() -> Vector2:
	var best := Vector2.INF
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index > 0 and object.owner_index != player.index and object.is_alive():
			if best == Vector2.INF or object.accepts.size() > 1:
				best = object.position
	return best
