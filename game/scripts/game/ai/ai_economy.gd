class_name AiEconomy
extends RefCounted
## The AI's economy: workers build what is going up and otherwise gather, wood and gold in
## a share that follows the stock (miners spread over the mines that have a drop-off);
## workers and women are trained up to the difficulty's target; a grain store with a few
## fields (the outlaws distil liquor instead); hunters hunt; wagons haul warehoused gold
## and empty abandoned warehouses; the trading post evens out the stock; idle riders catch
## wild horses; cows are raised and sold.

const WOOD_SHARE := 0.6
const FIELD_TARGET := 4
const FOOD_SURPLUS := 2500  # distilleries rest above this
const COW_TARGET := 4
const COW_SELL_VALUE := 18.0
const REBALANCE_SECONDS := 30.0

var ai: AiPlayer
var _rebalanced := 0.0


func _init(owner: AiPlayer) -> void:
	ai = owner


func think(units: Array, workers: Array, hq: MapObject) -> void:
	assign_workers(workers)
	_farm(units, hq)
	for unit: Unit in units:
		if unit.state == Unit.State.IDLE and unit.unit_type.is_hunter() and not ai.is_soldier(unit) \
				and int(ai.player.resources.get("food", 0)) < 3000:
			unit.hunt(unit.work.nearest_animal())
	_train_civilians(hq, workers, units)
	_haul_gold(units.filter(func(u: Unit) -> bool: return u.unit_type.is_transport()))
	_trade()
	_use_horses(units)
	_cattle(units)


## Idle workers build first, then gather: about the wood share of them on wood.
func assign_workers(workers: Array) -> void:
	var on_wood := workers.filter(func(u: Unit) -> bool:
		return is_instance_valid(u.work.gather_source) and u.work.gather_source.stock.resource == "wood").size()
	var share := _wood_share()
	# Every half minute, move workers over when the stock leans too far one way.
	if ai.elapsed - _rebalanced > REBALANCE_SECONDS:
		_rebalanced = ai.elapsed
		var wanted := ceili(workers.size() * share)
		var from := "wood" if on_wood > wanted + 1 else ("gold" if on_wood < wanted - 1 else "")
		if from != "":
			var excess := absi(on_wood - wanted) - 1
			for worker: Unit in workers:
				if excess <= 0:
					break
				if worker.state == Unit.State.GATHERING and is_instance_valid(worker.work.gather_source) \
						and worker.work.gather_source.stock.resource == from and worker.work.carried == 0:
					var source := _gold_source_for(worker, workers) if from == "wood" else worker.work.nearest_source("wood")
					if source:
						worker.gather(source)
						on_wood += -1 if from == "wood" else 1
						excess -= 1
	for worker: Unit in workers:
		if worker.state != Unit.State.IDLE:
			continue
		var site := ai.builder.unfinished_site()
		if site:
			worker.build(site)
			continue
		var want_wood := on_wood < ceili(workers.size() * share)
		var source := worker.work.nearest_source("wood") if want_wood else _gold_source_for(worker, workers)
		if source == null:
			source = _gold_source_for(worker, workers) if want_wood else worker.work.nearest_source("wood")
		if source:
			worker.gather(source)
			if source.stock.resource == "wood":
				on_wood += 1


## The share of workers on wood: 60% when wood and gold stand even, fewer as wood piles up
## beside little gold, more when gold is plentiful.
func _wood_share() -> float:
	var gold := int(ai.player.resources.get("gold", 0)) + ai.player.warehoused_gold()
	var wood := int(ai.player.resources.get("wood", 0))
	return clampf(WOOD_SHARE - (wood - gold) / 4000.0, 0.25, 0.85)


## Miners spread over the mines that have somewhere to take the gold (the HQ or a gold
## warehouse close by): the one with the fewest miners, the nearest of those.
func _gold_source_for(worker: Unit, workers: Array) -> MapObject:
	var served := MapObject.all_objects.filter(func(o: MapObject) -> bool:
		return o.stock.resource == "gold" and o.stock.amount > 0 and not ai.builder.no_drop_off_near("gold", o.position))
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
	if not hq.complete or hq.production.queue.size() >= 2:
		return
	var fields := MapObject.structures.filter(func(o: MapObject) -> bool:
		return o.is_field() and o.owner_index == ai.player.index).size()
	var farmers := units.filter(func(u: Unit) -> bool: return u.unit_type.is_farmer()).size()
	var want_farmer := farmers < fields * 2
	if not want_farmer and workers.size() >= ai.level().workers:
		return
	for guid in hq.production.trainable_units():
		var unit_type := UnitType.for_guid(guid)
		if unit_type == null or guid in Player.COMMANDERS:
			continue
		var is_builder := unit_type.anim_index("build") >= 0 and unit_type.can_gather("wood")
		if (want_farmer and unit_type.is_farmer()) or (not want_farmer and is_builder):
			hq.production.enqueue(guid)
			return


## Wagons shuttle from the fullest gold warehouse; one is trained when gold piles up there.
## Spare wagons empty abandoned warehouses nearby.
func _haul_gold(transports: Array) -> void:
	var warehouses := ai.my_buildings().filter(func(b: MapObject) -> bool: return b.is_gold_warehouse() and b.complete)
	var abandoned := MapObject.abandoned_stores.filter(func(o: MapObject) -> bool:
		return o.stock.loot > 0 and o.position.distance_to(ai.home) < 1800.0 and not ai.enemy_near(o.position, 600.0))
	if warehouses.is_empty() and abandoned.is_empty():
		return
	if warehouses.is_empty():
		for wagon: Unit in transports:
			if wagon.state == Unit.State.IDLE and wagon.tepees.packed.is_empty():
				abandoned.sort_custom(func(a: MapObject, b: MapObject) -> bool:
					return a.position.distance_to(wagon.position) < b.position.distance_to(wagon.position))
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
		warehouses.sort_custom(func(a: MapObject, b: MapObject) -> bool: return a.stock.stored_gold > b.stock.stored_gold)
		wagon.haul(warehouses[0])
	var waiting := 0
	for w: MapObject in warehouses:
		waiting += w.stock.stored_gold
	if transports.size() < warehouses.size() + (1 if not abandoned.is_empty() else 0) and waiting >= 60:
		_train_transport()


func _train_transport() -> void:
	for building: MapObject in ai.my_buildings():
		if not building.complete or not building.production.queue.is_empty():
			continue
		for guid in building.production.trainable_units():
			var unit_type := UnitType.for_guid(guid)
			if unit_type and unit_type.is_transport() and building.production.enqueue(guid):
				return


## Keep a grain store with a few fields and put idle women to work on them.
func _farm(units: Array, hq: MapObject) -> void:
	var store := ai.faction_guid(MapObject.FOOD_STORES)
	if store < 0:
		_distil(units, hq)  # the outlaws distil liquor instead
		return
	var player := ai.player
	var fields := MapObject.structures.filter(func(o: MapObject) -> bool: return o.is_field() and o.owner_index == player.index)
	if not player.has_building(store):
		var store_pending := ai.my_buildings().any(func(b: MapObject) -> bool: return b.guid == store)
		if not store_pending and ai.builder.sites() < ai.level().sites and ai.affordable(store) \
				and int(player.resources.get("food", 0)) < 4000:
			ai.builder.place(store, hq.position, units.filter(func(u: Unit) -> bool: return u.unit_type.can_build(store)))
		return
	# Fields cost wood: a couple early, more once the workforce is up.
	var field_target := FIELD_TARGET if ai.workers_ready() else 2
	if fields.size() < field_target and MapObject.field_allowance(player.index) > 0 and ai.affordable(MapObject.FIELD_GUID):
		var store_object: MapObject = null
		for object in ai.my_buildings():
			if object.guid == store and object.complete:
				store_object = object
		if store_object:
			var field := ai.builder.plant_field(store_object.position)
			if field:
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
	var food := int(ai.player.resources.get("food", 0))
	var stills := ai.my_buildings().filter(func(b: MapObject) -> bool: return b.guid == BuildingProduction.DISTILLERY_GUID)
	for still: MapObject in stills:
		still.production.distilling = food < FOOD_SURPLUS
	var wanted := 1 + ai.my_units().size() / 12
	if stills.size() < wanted and food < FOOD_SURPLUS and ai.builder.sites() < ai.level().sites \
			and ai.affordable(BuildingProduction.DISTILLERY_GUID):
		ai.builder.place(BuildingProduction.DISTILLERY_GUID, hq.position, units.filter(func(u: Unit) -> bool:
			return u.unit_type.can_build(BuildingProduction.DISTILLERY_GUID)))


## The trading post evens out the stock: sell what piles up when gold runs short, buy wood
## or food when they run out and gold is plentiful, and guns for the riflemen.
func _trade() -> void:
	var post: MapObject = null
	for building: MapObject in ai.my_buildings():
		if building.guid in BuildingProduction.TRADE_BUILDINGS and building.complete and building.production.queue.size() < 3:
			post = building
	if post == null:
		return
	var r := ai.player.resources
	var gold := int(r.get("gold", 0))
	var trade := -1  # index into BuildingProduction.TRADES
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
		post.production.enqueue(BuildingProduction.TRADE_GUID + trade)


## Idle units that can ride catch wild horses near them.
func _use_horses(units: Array) -> void:
	for unit: Unit in units:
		if unit.state != Unit.State.IDLE or not unit.riding.can_mount() or unit.riding.busy:
			continue
		for other in Unit.all_units:
			if other.animal.is_horse() and other.is_alive() and (other.team == 0 or other.team == ai.player.index) \
					and other.position.distance_to(unit.position) < 600.0:
				unit.mount(other)
				break


## Raise a few cows where the people can (hacienda, ranch) and drive the grown ones to the
## butcher; herders bring in strays on their own.
func _cattle(units: Array) -> void:
	var processing: MapObject = null
	for building: MapObject in ai.my_buildings():
		if building.guid in BuildingProduction.ANIMAL_PROCESSING and building.complete:
			processing = building
	var cows := units.filter(func(u: Unit) -> bool: return u.animal.is_cow())
	if processing:
		for cow: Unit in cows:
			if cow.state == Unit.State.IDLE and cow.animal.cattle_value >= COW_SELL_VALUE:
				cow.animal.deliver(processing)
	if cows.size() >= COW_TARGET or int(ai.player.resources.get("food", 0)) < 600:
		return
	for building: MapObject in ai.my_buildings():
		if building.guid in BuildingProduction.COW_BUILDINGS and building.complete and building.production.queue.is_empty():
			building.production.enqueue(BuildingProduction.COW_GUID)
			return
