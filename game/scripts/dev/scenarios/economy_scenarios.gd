class_name EconomyScenarios
extends Scenario
## Developer scenarios: gathering, farming, hunting, building, trading, animals and research.


## Half the player's workers on wood, half on gold.
func _scenario_economy() -> void:
	var i := 0
	for node in main.units_root.get_children():
		if node is Unit and node.team == 1 and node.unit_type.can_gather("wood"):
			var unit: Unit = node
			var resource := "wood" if i % 2 == 0 else "gold"
			var source := unit.work.nearest_source(resource) if resource == "wood" else _nearest_mine(unit.position)
			unit.gather(source)
			i += 1


## A finished weapons factory researches rifle and armour upgrades; infantry stats are checked.
func _scenario_research() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var type := ObjectTypes.get_type(GameData.type_for_guid(211, main.terrain.biome))
	var factory := MapObject.new()
	factory.setup(type, 1)
	factory.position = AiBuilder.find_spot(type, hq.position)
	main.units_root.add_child(factory)
	main.players[1].resources.gold = 5000
	main.players[1].resources.food = 5000
	main.selection.select_building(factory)
	main.camera.position = factory.position
	print("research options: ", Array(factory.production.researchable_upgrades()).map(func(g: int) -> String: return GameData.stats(g).name))
	print("queue rifle 1:", factory.production.enqueue(925), " rifle 2 now:", factory.production.enqueue(926))
	main._spawn_squad(258, 1, hq.position + Vector2(0, 200), 1)
	var infantry: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 258)[0]
	print("before: damage %.0f health %.0f" % [infantry.attack_damage(), infantry.max_health])
	await get_tree().create_timer(65.0).timeout
	print("researched: ", main.players[1].researched.keys(), " rifle 2 now:", factory.production.enqueue(926), " clothing 1:", factory.production.enqueue(929))
	await get_tree().create_timer(160.0).timeout
	print("after: damage %.0f health %.0f researched %s" % [infantry.attack_damage(), infantry.max_health, main.players[1].researched.keys()])


## The women place a field next to a finished grain store the way a player does, then
## sow, wait and harvest it; their state and the food are printed as it goes.
func _scenario_fields() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var store_guid := 0
	for guid in MapObject.FOOD_STORES:
		if GameData.stats(guid).get("faction") == main.players[1].faction:
			store_guid = guid
	var store_type := ObjectTypes.get_type(GameData.type_for_guid(store_guid, main.terrain.biome))
	var store := MapObject.new()
	store.position = AiBuilder.find_spot(store_type, hq.position)
	store.setup(store_type, 1)
	main.units_root.add_child(store)
	main.nav.block_footprint(store_type, store.position)
	var women := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.is_farmer())
	main.selection._select(women, false)
	var field_type := GameData.type_for_guid(MapObject.FIELD_GUID, main.terrain.biome)
	main.build_controller.start(field_type)
	var placed := false
	for radius in range(120, 500, 24):
		for k in 12:
			var spot := ((store.position + Vector2(radius, 0).rotated(k * TAU / 12.0)) / NavGrid.CELL).round() * NavGrid.CELL
			if main.build_controller.can_place(spot):
				main.build_controller._place(spot, false)
				placed = true
				break
		if placed:
			break
	var field: MapObject = null
	for object in MapObject.all_objects:
		if object.is_field() and object.owner_index == 1:
			field = object
	if field:
		main.camera.position = field.position
	print("field placed=%s complete=%s resource=%s state=%d store=%s" % [placed, field.complete if field else false,
			field.stock.resource if field else "", field.stock.field_state if field else -1, GameData.stats(store_guid).get("name")])
	for i in 16:
		await get_tree().create_timer(5.0).timeout
		print("t=%ds field state=%d progress=%.2f amount=%d food=%d women=%s" % [(i + 1) * 5, field.stock.field_state,
				field.stock.field_progress, field.stock.amount, main.players[1].resources.food,
				women.map(func(u: Unit) -> String: return "%d/%d/%s" % [u.state, u.work.phase, u._action])])
	get_tree().quit()


## Two hunters bring down a buffalo and carry it home in loads until it is picked clean.
func _scenario_hunt() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	main._spawn_squad("global/gfx/animals/bueffel", 0, hq.position + Vector2(260, 260), 1)
	var hunter_guid: int = {"mex": 261, "usa": 461, "ind": 156, "des": 358}[main.players[1].faction]
	main._spawn_squad(hunter_guid, 1, hq.position + Vector2(0, 200), 2)
	var buffalo: Unit = null
	for n in main.units_root.get_children():
		if n is Unit and n.team == 0 and n.position.distance_to(hq.position + Vector2(260, 260)) < 60:
			buffalo = n
	var hunters := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == hunter_guid)
	main.selection._select(hunters, false)
	main.selection.order_at(buffalo.position + Vector2(0, -12))  # a right click on it
	print("hunt order marks the prey: %s, hunters on it %s" % [buffalo._flash_time > 0.0,
			hunters.all(func(h: Unit) -> bool: return h.target == buffalo)])
	var food: int = main.players[1].resources.food
	buffalo.died.connect(func(_u: Unit) -> void:
		print("buffalo dies: plays %s, drawn above the ground %s" % [buffalo._action, buffalo.z_index > main.terrain.z_index]))
	var vanished_with_meat := false
	for i in 18:
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(buffalo) and not buffalo.is_alive() and buffalo.animal.has_meat() and buffalo.modulate.a < 1.0:
			vanished_with_meat = true
		if i == 15:
			print("carcass faded with meat left: %s" % vanished_with_meat)
		print("t=%ds buffalo alive=%s meat_left=%d visible=%s food +%d hunters=%s" % [(i + 1) * 5, buffalo.is_alive() if is_instance_valid(buffalo) else false,
				buffalo.animal.meat_left if is_instance_valid(buffalo) else -9, is_instance_valid(buffalo),
				main.players[1].resources.food - food, hunters.map(func(h: Unit) -> String: return "%d/%s/%d" % [h.state, h._action, h.work.carried])])
	get_tree().quit()


## Miners fill a gold warehouse by the nearest mine; a wagon hauls it to the main building.
func _scenario_gold() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var mine := _nearest_mine(hq.position)
	var store_guid: int = {"mex": 206, "usa": 419, "ind": 104, "des": 304}[main.players[1].faction]
	var wagon_guid: int = {"mex": 255, "usa": 455, "ind": 155, "des": 355}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(store_guid, main.terrain.biome))
	var store := MapObject.new()
	store.position = AiBuilder.find_spot(type, mine.position, 100)
	store.setup(type, 1)
	main.units_root.add_child(store)
	main.nav.block_footprint(type, store.position)
	hq.accepts = PackedStringArray(["wood", "food"])  # test: miners must use the warehouse
	var workers := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.can_gather("gold"))
	for w: Unit in workers.slice(0, 3):
		w.gather(mine)
	main._spawn_squad(wagon_guid, 1, hq.position + Vector2(0, 220), 1)
	var wagon: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == wagon_guid)[0]
	print("mine %d px from HQ, warehouse %d px from mine; wagon carry %d transport=%s" % [mine.position.distance_to(hq.position),
			store.position.distance_to(mine.position), wagon.unit_type.carry, wagon.unit_type.is_transport()])
	var start_gold: int = main.players[1].resources.gold
	for i in 16:
		await get_tree().create_timer(10.0).timeout
		if i == 3:
			wagon.haul(store)
		print("t=%ds gold +%d warehoused %d wagon state %d carrying %d" % [(i + 1) * 10, main.players[1].resources.gold - start_gold,
				main.players[1].warehoused_gold(), wagon.state, wagon.work.carried])
	get_tree().quit()


## One worker on the nearest tree: what each second of a wood round trip is spent on.
func _scenario_woodcut() -> void:
	var worker: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.can_gather("wood") and n.unit_type.anim_index("build") >= 0)[0]
	var tree := worker.work.nearest_source("wood")
	print("tree %d px away, wood %d" % [worker.position.distance_to(tree.position), tree.stock.amount])
	worker.gather(tree)
	var wood: int = main.players[1].resources.wood
	for i in 60:
		await get_tree().create_timer(1.0).timeout
		print("t=%2d phase=%d action=%-14s pos=%s path=%d carried=%d tree=%s d_tree=%d wood+%d" % [i + 1, worker.work.phase, worker._action,
				worker.position.round(), worker.path.size(), worker.work.carried, worker.work.gather_source.position if is_instance_valid(worker.work.gather_source) else null,
				worker.position.distance_to(worker.work.gather_source.position) if is_instance_valid(worker.work.gather_source) else -1, main.players[1].resources.wood - wood])
	get_tree().quit()


## A finished trading building buys guns twice and sells wood; prices and stock printed.
func _scenario_trade() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var guid: int = {"mex": 210, "usa": 410, "ind": 106, "des": 310}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var post := MapObject.new()
	post.position = AiBuilder.find_spot(type, hq.position)
	post.setup(type, 1)
	main.units_root.add_child(post)
	var p: Player = main.players[1]
	print("trades offered: ", Array(post.production.trainable_units()).map(func(g: int) -> String: return GameData.stats(g).name))
	print("before: %s  gun price %d, wood sells for %d" % [p.resources, p.buy_price("guns"), p.sell_price("wood")])
	print("queued: ", post.production.enqueue(BuildingProduction.TRADE_GUID + 4), post.production.enqueue(BuildingProduction.TRADE_GUID + 4), post.production.enqueue(BuildingProduction.TRADE_GUID + 3))
	print("paid:   %s" % p.resources)
	await get_tree().create_timer(20.0).timeout
	print("after:  %s  gun price %d, wood sells for %d" % [p.resources, p.buy_price("guns"), p.sell_price("wood")])
	get_tree().quit()


## A cowboy takes over a wild cow; it grazes, then is driven to the stockyard and sold.
func _scenario_cattle() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var type := ObjectTypes.get_type(GameData.type_for_guid(402, main.terrain.biome))
	var yard := MapObject.new()
	yard.position = AiBuilder.find_spot(type, hq.position)
	yard.setup(type, 1)
	main.units_root.add_child(yard)
	main.nav.block_footprint(type, yard.position)
	main._spawn_squad(UnitAnimal.COW_DIR, 0, hq.position + Vector2(-260, 240), 1)
	main._spawn_squad(463, 1, hq.position + Vector2(0, 240), 1)
	var cow: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.animal.is_cow() and n.position.distance_to(hq.position + Vector2(-260, 240)) < 60)[0]
	var cowboy: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 463)[0]
	cowboy.move_to(cow.position + Vector2(20, 0))
	await get_tree().create_timer(8.0).timeout
	print("cow team %d after the cowboy came by" % cow.team)
	await get_tree().create_timer(40.0).timeout
	var gold: int = main.players[1].resources.gold
	print("cow worth %.1f gold after grazing" % cow.animal.cattle_value)
	cow.animal.deliver(yard)
	await get_tree().create_timer(15.0).timeout
	print("sold: cow gone %s, gold +%d; stockyard trains: %s" % [not is_instance_valid(cow), main.players[1].resources.gold - gold,
			Array(MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.guid == 405).map(func(o: MapObject) -> Array: return Array(o.production.trainable_units())))])
	get_tree().quit()


## One worker starts a house; the others are then sent to help via the help-build order.
func _scenario_help_build() -> void:
	var workers := main.units_root.get_children().filter(func(n: Node) -> bool:
		return n is Unit and n.team == 1 and n.unit_type.anim_index("build") >= 0)
	main.selection._select([workers[0]], false)
	main.build_controller.start(GameData.type_for_guid(201, main.terrain.biome))
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	for radius in range(200, 600, 32):
		var spot := ((hq.position + Vector2(radius, 0).rotated(radius * 0.7)) / NavGrid.CELL).round() * NavGrid.CELL
		if main.build_controller.can_place(spot):
			main.build_controller._place(spot, false)
			break
	var site: MapObject = MapObject.all_objects.filter(func(o: MapObject) -> bool: return not o.complete)[0]
	main.selection._select(workers.slice(1), false)
	main.selection.order_build(site)
	OrderMarker.spawn(main.units_root, site.position + Vector2(-160, 60), 1)
	var helpers := workers.filter(func(u: Unit) -> bool: return u.work.build_site == site).size()
	print("help-build: %d of %d workers now building" % [helpers, workers.size()])


## Workers build a house next to the HQ while the HQ trains two more workers.
## --builders=women: the women put up their people's grain store instead.
func _scenario_build() -> void:
	var women := GameData.cmdline_option("builders") == "women"
	var workers := main.units_root.get_children().filter(func(n: Node) -> bool:
		return n is Unit and n.team == 1 and (n.unit_type.is_farmer() if women else n.unit_type.anim_index("build") >= 0))
	main.selection._select(workers, false)
	var store := 0
	for guid in MapObject.FOOD_STORES:
		if GameData.stats(guid).get("faction") == main.players[1].faction:
			store = guid
	var house := GameData.type_for_guid(store if women else 201, main.terrain.biome)
	main.build_controller.start(house)
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	for radius in range(200, 600, 32):
		var spot := hq.position + Vector2(radius, 0).rotated(radius * 0.7)
		spot = (spot / NavGrid.CELL).round() * NavGrid.CELL
		if main.build_controller.can_place(spot):
			main.build_controller._place(spot, false)
			print("house site at ", spot)
			break
	print("queued: ", hq.production.enqueue(252), hq.production.enqueue(252))


## A finca with two fields worked by three women, and two militiamen hunting.
func _scenario_food() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var finca_type := ObjectTypes.get_type(GameData.type_for_guid(208, main.terrain.biome))
	var finca := MapObject.new()
	finca.position = AiBuilder.find_spot(finca_type, hq.position)
	finca.setup(finca_type, 1)
	main.units_root.add_child(finca)
	main.nav.block_footprint(finca_type, finca.position)
	main._spawn_squad(253, 1, finca.position + Vector2(0, 120), 3)
	main._spawn_squad(261, 1, hq.position + Vector2(0, 160), 2)
	var field_type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.FIELD_GUID, main.terrain.biome))
	var fields: Array[MapObject] = []
	for k in 2:
		var field := MapObject.new()
		field.position = finca.position + Vector2(-140 + k * 150, 170)
		field.setup(field_type, 1)
		main.units_root.add_child(field)
		fields.append(field)
	var i := 0
	for node in main.units_root.get_children():
		if node is Unit and node.team == 1:
			if node.unit_type.can_gather("food") and node.unit_type.anim_index("build") < 0:
				node.gather(fields[i % 2])
				i += 1
			elif node.unit_type.is_hunter():
				node.hunt(node.work.nearest_animal())
	print("food scenario: finca at %s, %d women farming" % [finca.position, i])


## A cowboy mounts a wild horse, dismounts, and the horse is led into a ranch.
func _scenario_horses() -> void:
	var hq: MapObject = main.players[1].main_building()
	var type := ObjectTypes.get_type(GameData.type_for_guid(405, main.terrain.biome))
	var ranch := MapObject.new()
	ranch.position = AiBuilder.find_spot(type, hq.position)
	ranch.setup(type, 1)
	main.units_root.add_child(ranch)
	main.nav.block_footprint(type, ranch.position)
	main._spawn_squad(UnitAnimal.HORSE_DIR, 0, hq.position + Vector2(-240, 240), 1)
	main._spawn_squad(463, 1, hq.position + Vector2(0, 240), 1)
	var horse: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.animal.is_horse())[0]
	var cowboy: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 463)[0]
	cowboy.mount(horse)
	await get_tree().create_timer(8.0).timeout
	var rider: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.is_alive() and n.unit_type.guid() == 464)[0] if main.units_root.get_children().any(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 464) else null
	print("mounted: %s (horse gone %s)" % [rider != null, not is_instance_valid(horse)])
	rider.dismount()
	await get_tree().process_frame
	var led: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.animal.is_horse() and n.team == 1)[0]
	led.animal.stable(ranch)
	await get_tree().create_timer(12.0).timeout
	print("horses %d / %d, cowboy on foot again %s" % [main.players[1].resources.horses, main.players[1].horse_capacity(),
			main.units_root.get_children().any(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 463)])
	get_tree().quit()


## A wagon empties the nearest abandoned warehouse into the main building.
func _scenario_abandoned() -> void:
	var hq: MapObject = main.players[1].main_building()
	var stores := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.is_abandoned_store() and o.stock.loot > 0)
	stores.sort_custom(func(a: MapObject, b: MapObject) -> bool: return a.position.distance_to(hq.position) < b.position.distance_to(hq.position))
	var store: MapObject = stores[0]
	print("%d abandoned warehouses; nearest holds %d %s, %d px away" % [stores.size(), store.stock.loot, store.stock.loot_kind, store.position.distance_to(hq.position)])
	var wagon_guid: int = {"mex": 255, "usa": 455, "ind": 155, "des": 355}[main.players[1].faction]
	main._spawn_squad(wagon_guid, 1, store.position + Vector2(0, 160), 1)
	var wagon: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == wagon_guid)[0]
	var before: Dictionary = main.players[1].resources.duplicate()
	wagon.haul(store)
	for k in 12:
		await get_tree().create_timer(10.0).timeout
		print("  t=%d wagon state %d phase %d carrying %s %d path %d at %s" % [(k + 1) * 10, wagon.state, wagon.work.phase, wagon.work.carrying, wagon.work.carried, wagon.path.size(), wagon.position.round()])
	print("store left %d; %s %d -> %d" % [store.stock.loot, store.stock.loot_kind, before[store.stock.loot_kind], main.players[1].resources[store.stock.loot_kind]])
	get_tree().quit()


## Every people's structures in both landscapes: the last construction stage is the finished
## picture, and a burnt and a destroyed one show their damage pictures.
func _scenario_stages() -> void:
	var total := 0
	var finished_last := 0
	var burnt := 0
	var rubble := 0
	var wrong := []
	for guid in GameData.stats_guids():
		if GameData.stats(guid).get("kind") != "structure" or guid in [MapObject.FIELD_GUID, MapObject.PITFALL_GUID]:
			continue
		for biome in ["steppe", "wiese"]:
			var type := ObjectTypes.get_type(GameData.type_for_guid(guid, biome))
			if type == null:
				continue
			total += 1
			var b := MapObject.new()
			b.setup(type, 1, 0, true)
			b.build_progress = 0.99
			b.refresh_sprites()
			var last_stage := b._body.region_rect
			b.complete = true
			b.health = b.max_health
			b.refresh_sprites()
			if b._body.region_rect == last_stage:
				finished_last += 1
			else:
				wrong.append("%d %s" % [guid, biome])
			b.health = b.max_health * 0.2
			b.refresh_sprites()
			burnt += 1 if b._body_anim == MapObject.BURNT_ANIM else 0
			b.health = 0.0
			b.refresh_sprites()
			rubble += 1 if b.shows_rubble() else 0
			b.free()
	print("structures %d: construction ends on the finished picture %d, burnt %d, rubble %d %s" % [total,
			finished_last, burnt, rubble, wrong])
	get_tree().quit()




## The weapons factory's furnace glows only while it makes something.
func _scenario_furnace() -> void:
	var hq: MapObject = main.players[1].main_building()
	var guid: int = 411 if main.players[1].faction == "usa" else 211
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var factory := MapObject.new()
	factory.position = AiBuilder.find_spot(type, hq.position)
	factory.setup(type, 1)
	main.units_root.add_child(factory)
	main.camera.position = factory.position
	main.players[1].resources.gold = 5000
	main.players[1].resources.food = 5000
	await get_tree().process_frame
	var idle := factory._ambient != null
	factory.production.enqueue(factory.production.researchable_upgrades()[0])
	await get_tree().process_frame
	await get_tree().process_frame
	var working := factory._ambient != null
	factory.production.cancel(0)
	await get_tree().process_frame
	await get_tree().process_frame
	print("furnace glows: idle %s, working %s, after cancelling %s" % [idle, working, factory._ambient != null])
	get_tree().quit()



## A damaged tower: a right click with workers and a soldier selected quarters the soldier
## (the workers don't start repairing); the Repair button, then a click on it, sets the
## workers to work.
func _scenario_repair() -> void:
	var hq: MapObject = main.players[1].main_building()
	var guid: int = {"mex": 213, "usa": 413, "des": 313, "ind": 111}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var tower := MapObject.new()
	tower.position = AiBuilder.find_spot(type, hq.position)
	tower.setup(type, 1)
	main.units_root.add_child(tower)
	main.nav.block_footprint(type, tower.position)
	tower.take_damage(tower.max_health * 0.5)
	var army: int = main.FACTIONS[main.players[1].faction].army
	main._spawn_squad(army, 1, tower.position + Vector2(0, 140), 1)
	var soldier: Unit = Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 1 and u.unit_type.guid() == army)[0]
	var builders := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 1 and u.unit_type.can_build())
	main.selection._select(builders + [soldier], false)
	main.selection.order_at(tower.work_rect().get_center())
	await get_tree().create_timer(1.0).timeout
	print("right click: soldier to quarters %s, workers repairing %s" % [soldier.quarters == tower,
			builders.any(func(u: Unit) -> bool: return u.work.build_site == tower)])
	main.selection._select(builders, false)
	await get_tree().process_frame
	await get_tree().process_frame
	for button in main.hud.commands.grid.get_children():
		if String(button.get_meta("tooltip", "")).begins_with("Repair"):
			button.pressed.emit()
	await _click(tower.work_rect().get_center())
	var before := tower.health
	await get_tree().create_timer(20.0).timeout
	print("repair command: repaired %s (energy %d -> %d)" % [tower.health > before, before, tower.health])
	get_tree().quit()
