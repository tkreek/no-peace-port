class_name Scenarios
extends Node
## Developer test scenarios, started with --scenario=<name> (see README): each sets up a
## situation in the running match and prints what happened, for headless checks and
## screenshots. They reach the match through `main`.

var main: Main


static func start(main_node: Main, scenario: String) -> void:
	var runner := Scenarios.new()
	runner.main = main_node
	main_node.add_child(runner)
	var method := "_scenario_" + scenario.replace("-", "_")
	if runner.has_method(method):
		runner.call_deferred(method)
	else:
		push_warning("Unknown scenario %s" % scenario)


## Half the player's workers on wood, half on gold.
func _scenario_economy() -> void:
	var i := 0
	for node in main.units_root.get_children():
		if node is Unit and node.team == 1 and node.unit_type.can_gather("wood"):
			var unit: Unit = node
			var resource := "wood" if i % 2 == 0 else "gold"
			var source := unit._nearest_source(resource) if resource == "wood" else _nearest_mine(unit.position)
			unit.gather(source)
			i += 1


## Two infantry lines facing each other in front of the camera.
func _scenario_battle() -> void:
	var centre: Vector2 = main.camera.position
	main._spawn_squad(main.FACTIONS[main.players[1].faction].army, 1, centre + Vector2(-60, 120), 9)
	main._spawn_squad(main.FACTIONS[main.players[2].faction].army, 2, centre + Vector2(60, -160), 9)


## The in-game menu's options panel, open.
func _scenario_options() -> void:
	main.hud.toggle_menu()
	main.hud._show_options()


## A finished weapons factory researches rifle and armour upgrades; infantry stats are checked.
func _scenario_research() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var ai := AiPlayer.new()
	ai.biome = main.terrain.biome
	var type := ObjectTypes.get_type(GameData.type_for_guid(211, main.terrain.biome))
	var factory := MapObject.new()
	factory.setup(type, 1)
	factory.position = ai._find_spot(type, hq.position)
	main.units_root.add_child(factory)
	ai.free()
	main.players[1].resources.gold = 5000
	main.players[1].resources.food = 5000
	main.selection.select_building(factory)
	main.camera.position = factory.position
	print("research options: ", Array(factory.researchable_upgrades()).map(func(g: int) -> String: return GameData.stats(g).name))
	print("queue rifle 1:", factory.enqueue(925), " rifle 2 now:", factory.enqueue(926))
	main._spawn_squad(258, 1, hq.position + Vector2(0, 200), 1)
	var infantry: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 258)[0]
	print("before: damage %.0f health %.0f" % [infantry.attack_damage(), infantry.max_health])
	await get_tree().create_timer(65.0).timeout
	print("researched: ", main.players[1].researched.keys(), " rifle 2 now:", factory.enqueue(926), " clothing 1:", factory.enqueue(929))
	await get_tree().create_timer(160.0).timeout
	print("after: damage %.0f health %.0f researched %s" % [infantry.attack_damage(), infantry.max_health, main.players[1].researched.keys()])


## Print the command buttons shown for player 1's builders and for its farmers, and the
## train buttons of each of its people's buildings (placed finished next to the HQ).
func _scenario_menus() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var ai := AiPlayer.new()
	ai.biome = main.terrain.biome
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") != main.players[1].faction or stats.get("kind") != "structure":
			continue
		var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
		var building := MapObject.new()
		building.setup(type, 1)
		if building.trainable_units().is_empty():
			building.free()
			continue
		building.position = ai._find_spot(type, hq.position)
		main.units_root.add_child(building)
		main.selection.select_building(building)
		main.hud._command_signature = ""
		main.hud._refresh_commands()
		await get_tree().process_frame
		var names := []
		for button in main.hud._commands.get_children():
			if not button.is_queued_for_deletion():
				names.append(button.tooltip_text.replace("\n", " / "))
		var queued := []
		for unit_guid in building.trainable_units():
			queued.append("%s:%s" % [GameData.stats(unit_guid).get("name"), building.enqueue(unit_guid)])
		print("%s: %s | enqueue %s" % [stats.name, names, queued])
	ai.free()
	for kind in ["builders", "farmers"]:
		var units := main.units_root.get_children().filter(func(n: Node) -> bool:
			return n is Unit and n.team == 1 and (n.unit_type.anim_index("build") >= 0 if kind == "builders" else n.unit_type.is_farmer()))
		main.selection._select(units, false)
		for menu in ["", "basic", "expanded"]:
			main.hud._open_build_menu(menu)
			main.hud._refresh_commands()
			await get_tree().process_frame
			var names := []
			for button in main.hud._commands.get_children():
				if not button.is_queued_for_deletion():
					names.append("%s%s" % [button.tooltip_text.get_slice("\n", 0), " (off)" if button.disabled else ""])
			print("%s %s %s (%d units): %s" % [main.players[1].faction, kind, menu, units.size(), ", ".join(names)])


## --scenario=select --pick=unit|mine|tree|site|research: what the panel shows for each.
func _scenario_select() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var near := func(test: Callable) -> MapObject:
		var best: MapObject = null
		for object in MapObject.all_objects:
			if test.call(object) and (best == null or object.position.distance_to(hq.position) < best.position.distance_to(hq.position)):
				best = object
		return best
	match GameData.cmdline_option("pick", "unit"):
		"unit":
			var unit: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 \
					and not n.unit_type.attack_anims.is_empty() and not n.unit_type.can_build())[0]
			main.selection._select([unit], false)
		"mine":
			main.selection.select_building(near.call(func(o: MapObject) -> bool: return o.is_mine()))
		"tree":
			main.selection.select_building(near.call(func(o: MapObject) -> bool: return o.is_tree()))
		"site", "research":
			var guid := 211 if GameData.cmdline_option("pick") == "research" else 201
			for i in 5:
				if guid == 211:
					guid = [211, 411, 115, 314][["mex", "usa", "ind", "des"].find(main.players[1].faction)]
			var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
			var ai := AiPlayer.new()
			var site := MapObject.new()
			site.position = ai._find_spot(type, hq.position)
			ai.free()
			site.setup(type, 1, 0, GameData.cmdline_option("pick") == "site")
			main.units_root.add_child(site)
			if GameData.cmdline_option("pick") == "site":
				site.add_build_work(20.0)
			else:
				main.players[1].resources.gold = 5000
				main.players[1].resources.food = 5000
				site.enqueue(site.researchable_upgrades()[0])
				site.enqueue(site.researchable_upgrades()[1])
			main.selection.select_building(site)


## A tower manned by riflemen while enemy infantry walk up to it.
func _scenario_quarters() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var tower_guid: int = {"mex": 213, "usa": 413, "des": 313, "ind": 111}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(tower_guid, main.terrain.biome))
	var ai := AiPlayer.new()
	var tower := MapObject.new()
	tower.position = ai._find_spot(type, hq.position)
	ai.free()
	tower.setup(type, 1)
	main.units_root.add_child(tower)
	main.nav.block_footprint(type, tower.position)
	var army: int = main.FACTIONS[main.players[1].faction].army
	main._spawn_squad(army, 1, tower.position + Vector2(0, 160), 4)
	var squad := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 \
			and n.unit_type.guid() == army)
	main.selection._select(squad, false)
	main.selection.order_quarters(tower)
	await get_tree().create_timer(8.0).timeout
	print("capacity %d, quartered %d, outside %d" % [tower.capacity(), tower.garrison.size(),
			squad.filter(func(u: Unit) -> bool: return not u.inside).size()])
	main._spawn_squad(main.FACTIONS[main.players[2].faction].army, 2, tower.position + Vector2(260, 0), 3)
	var enemies := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 \
			and n.position.distance_to(tower.position) < 400)
	for e: Unit in enemies:
		e.stance = Unit.Stance.PASSIVE
	await get_tree().create_timer(30.0).timeout
	print("enemy energy after 30 s: ", enemies.map(func(u: Unit) -> int: return int(u.health) if is_instance_valid(u) else -1),
			" quartered energy: ", tower.garrison.map(func(u: Unit) -> int: return int(u.health)))
	main.selection.select_building(tower)
	tower.release()
	await get_tree().process_frame
	print("after release: quartered %d, outside %d" % [tower.garrison.size(),
			squad.filter(func(u: Unit) -> bool: return not u.inside).size()])
	get_tree().quit()


## Cannons, archers and a knife thrower against infantry; a nurse tends a wounded soldier.
func _scenario_projectiles() -> void:
	var centre := main.camera.position
	main._spawn_squad(465, 1, centre + Vector2(-140, 160), 2)   # cannons
	main._spawn_squad(156, 1, centre + Vector2(0, 160), 3)      # arrow shooters
	main._spawn_squad(163, 1, centre + Vector2(120, 160), 1)    # knife thrower
	main._spawn_squad(457, 1, centre + Vector2(220, 200), 1)    # nurse
	main._spawn_squad(458, 1, centre + Vector2(260, 200), 1)    # wounded infantryman
	main._spawn_squad(258, 2, centre + Vector2(0, -150), 6)
	var wounded: Unit = null
	for n in main.units_root.get_children():
		if n is Unit and n.team == 1 and n.unit_type.guid() == 458:
			wounded = n
	wounded.health = 40.0
	for n in main.units_root.get_children():
		if n is Unit and n.team == 2:
			n.stance = Unit.Stance.PASSIVE
	var shooters := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 \
			and not n.unit_type.attack_anims.is_empty() and n != wounded)
	print("shooters: ", shooters.map(func(u: Unit) -> String: return "%s ranged=%s proj=%d range=%d" % [u.display_name(), u.unit_type.ranged, u.unit_type.projectile_anim, u.attack_range()]))
	await get_tree().create_timer(float(GameData.cmdline_option("wait", "20"))).timeout
	var enemies := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2)
	print("enemy energy: ", enemies.map(func(u: Unit) -> int: return int(u.health)), " wounded now ", int(wounded.health))
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()


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
	var ai := AiPlayer.new()
	var store := MapObject.new()
	store.position = ai._find_spot(store_type, hq.position)
	ai.free()
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
			field.resource if field else "", field.field_state if field else -1, GameData.stats(store_guid).get("name")])
	for i in 16:
		await get_tree().create_timer(5.0).timeout
		print("t=%ds field state=%d progress=%.2f amount=%d food=%d women=%s" % [(i + 1) * 5, field.field_state,
				field.field_progress, field.amount, main.players[1].resources.food,
				women.map(func(u: Unit) -> String: return "%d/%d/%s" % [u.state, u._gather_phase, u._action])])
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
	for h: Unit in hunters:
		h.hunt(buffalo)
	var food: int = main.players[1].resources.food
	for i in 18:
		await get_tree().create_timer(5.0).timeout
		print("t=%ds buffalo alive=%s meat_left=%d visible=%s food +%d hunters=%s" % [(i + 1) * 5, buffalo.is_alive() if is_instance_valid(buffalo) else false,
				buffalo.meat_left if is_instance_valid(buffalo) else -9, is_instance_valid(buffalo),
				main.players[1].resources.food - food, hunters.map(func(h: Unit) -> String: return "%d/%s/%d" % [h.state, h._action, h.carried])])
	get_tree().quit()


## Where clicks land on the HQ: roof, walls, empty corners of its footprint, beside it.
func _scenario_picking() -> void:
	await get_tree().process_frame
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var picture := hq.visual_rect()
	var foot := hq.footprint_rect()
	var probes := {"roof (picture centre, upper third)": Vector2(picture.get_center().x, picture.position.y + picture.size.y * 0.3),
		"walls centre": hq.work_rect().get_center(),
		"picture top-left corner": picture.position + Vector2(4, 4),
		"footprint bottom-left corner": Vector2(foot.position.x + 2, foot.end.y - 2),
		"40px right of picture": Vector2(picture.end.x + 40, picture.get_center().y)}
	for label in probes:
		print("%-36s -> %s" % [label, main.selection._building_at(probes[label]) == hq])
	get_tree().quit()


## Three of the people's grain stores side by side at 60%, 25% and 0% energy.
func _scenario_damage() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var guid: int = {"mex": 208, "usa": 408, "ind": 108, "des": 308}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var ai := AiPlayer.new()
	var built: Array[MapObject] = []
	for ratio in [0.6, 0.25, 0.0]:
		var b := MapObject.new()
		b.position = ai._find_spot(type, hq.position + Vector2(-500, 300))
		b.setup(type, 1)
		main.units_root.add_child(b)
		main.nav.block_footprint(type, b.position)
		b.take_damage(b.max_health * (1.0 - ratio) + (1.0 if ratio == 0.0 else 0.0))
		built.append(b)
	ai.free()
	main.camera.position = built[1].position + Vector2(0, -60)
	if GameData.cmdline_option("repair") != "":
		var builders := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.anim_index("build") >= 0)
		main.selection._select(builders, false)
		main.selection.order_build(built[1])
		var wood: int = main.players[1].resources.wood
		for i in 6:
			await get_tree().create_timer(5.0).timeout
			print("repair t=%ds energy %d%% anim %d fires %d wood -%d" % [(i + 1) * 5, int(100 * built[1].health / built[1].max_health), built[1]._body_anim, built[1]._fires.size(), wood - main.players[1].resources.wood])
		get_tree().quit()
	print("damage: ", built.map(func(b: MapObject) -> String: return "%d%% anim %d fires %d" % [int(100 * b.health / b.max_health), b._body_anim, b._fires.size()]))


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
	var ai := AiPlayer.new()
	var store := MapObject.new()
	store.position = ai._find_spot(type, mine.position, 100)
	ai.free()
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
				main.players[1].warehoused_gold(), wagon.state, wagon.carried])
	get_tree().quit()


## One worker on the nearest tree: what each second of a wood round trip is spent on.
func _scenario_woodcut() -> void:
	var worker: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.can_gather("wood") and n.unit_type.anim_index("build") >= 0)[0]
	var tree := worker._nearest_source("wood")
	print("tree %d px away, wood %d" % [worker.position.distance_to(tree.position), tree.amount])
	worker.gather(tree)
	var wood: int = main.players[1].resources.wood
	for i in 60:
		await get_tree().create_timer(1.0).timeout
		print("t=%2d phase=%d action=%-14s pos=%s path=%d carried=%d tree=%s d_tree=%d wood+%d" % [i + 1, worker._gather_phase, worker._action,
				worker.position.round(), worker.path.size(), worker.carried, worker.gather_source.position if is_instance_valid(worker.gather_source) else null,
				worker.position.distance_to(worker.gather_source.position) if is_instance_valid(worker.gather_source) else -1, main.players[1].resources.wood - wood])
	get_tree().quit()


## A finished trading building buys guns twice and sells wood; prices and stock printed.
func _scenario_trade() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var guid: int = {"mex": 210, "usa": 410, "ind": 106, "des": 310}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var ai := AiPlayer.new()
	var post := MapObject.new()
	post.position = ai._find_spot(type, hq.position)
	ai.free()
	post.setup(type, 1)
	main.units_root.add_child(post)
	var p: Player = main.players[1]
	print("trades offered: ", Array(post.trainable_units()).map(func(g: int) -> String: return GameData.stats(g).name))
	print("before: %s  gun price %d, wood sells for %d" % [p.resources, p.buy_price("guns"), p.sell_price("wood")])
	print("queued: ", post.enqueue(MapObject.TRADE_GUID + 4), post.enqueue(MapObject.TRADE_GUID + 4), post.enqueue(MapObject.TRADE_GUID + 3))
	print("paid:   %s" % p.resources)
	await get_tree().create_timer(20.0).timeout
	print("after:  %s  gun price %d, wood sells for %d" % [p.resources, p.buy_price("guns"), p.sell_price("wood")])
	get_tree().quit()


## Outlaws rob an enemy gold warehouse and a barber steals an enemy wagon.
func _scenario_rob() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var enemy_store := 419 if main.players[2].faction == "usa" else 206
	var type := ObjectTypes.get_type(GameData.type_for_guid(enemy_store, main.terrain.biome))
	var ai := AiPlayer.new()
	var store := MapObject.new()
	store.position = ai._find_spot(type, hq.position + Vector2(300, 300))
	ai.free()
	store.setup(type, 2)
	main.units_root.add_child(store)
	main.nav.block_footprint(type, store.position)
	store.stored_gold = 300
	main._spawn_squad(455 if main.players[2].faction == "usa" else 255, 2, store.position + Vector2(-200, 120), 1)
	main._spawn_squad(353, 1, hq.position + Vector2(0, 220), 1)
	var robber: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.guid() == 352)[0]
	var barber: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 353)[0]
	var wagon: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.unit_type.is_transport())[0]
	print("robber can rob %s, barber can steal %s" % [robber.can_rob(), barber.can_steal()])
	robber.rob(store)
	barber.steal(wagon)
	var gold: int = main.players[1].resources.gold
	for i in 8:
		await get_tree().create_timer(5.0).timeout
		print("t=%ds store %d, our gold +%d, robber phase %d carrying %d inside %s; wagon team %d" % [(i + 1) * 5, store.stored_gold,
				main.players[1].resources.gold - gold, robber._gather_phase, robber.carried, robber.inside, wagon.team])
	get_tree().quit()


## Camouflaged riflemen beside enemy infantry go unseen until a trapper comes along.
func _scenario_camouflage() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0  # away from both bases
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	main.players[1].researched[915] = true
	main._spawn_squad(160, 1, centre, 2)
	var hiders := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.guid() == 160)
	for h: Unit in hiders:
		h.stance = Unit.Stance.PASSIVE
		h.conceal()
	main._spawn_squad(458, 2, centre + Vector2(150, 0), 3)
	await get_tree().create_timer(10.0).timeout
	print("unseen: concealed %s, energy %s, fogged to player 2's eyes n/a" % [hiders.map(func(h: Unit) -> bool: return h.concealed), hiders.map(func(h: Unit) -> int: return int(h.health))])
	main._spawn_squad(461, 2, centre + Vector2(220, 40), 1)
	await get_tree().create_timer(12.0).timeout
	print("after the trapper: energy %s" % [hiders.map(func(h: Unit) -> int: return int(h.health))])
	get_tree().quit()


## A pitfall between enemy infantry and our base: they walk into it, our own unit does not.
func _scenario_pitfall() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	var type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.PITFALL_GUID, main.terrain.biome))
	var pit := MapObject.new()
	pit.position = centre
	pit.setup(type, 1)
	main.units_root.add_child(pit)
	main._spawn_squad(458, 2, centre + Vector2(-200, 0), 4)
	main._spawn_squad(152, 1, centre + Vector2(-120, 60), 1)
	var friend: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.guid() == 152 and n.position.distance_to(centre) < 200)[0]
	friend.move_to(pit.footprint_rect().get_center() + Vector2(60, 0))
	for n in main.units_root.get_children():
		if n is Unit and n.team == 2 and n.position.distance_to(centre) < 300:
			n.stance = Unit.Stance.PASSIVE
			n.move_to(pit.footprint_rect().get_center() + Vector2(220, 0))
	await get_tree().create_timer(12.0).timeout
	var foes := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.position.distance_to(centre) < 400)
	print("enemies alive %s; our warrior alive %s; pit %s" % [foes.map(func(f: Unit) -> bool: return f.is_alive()), friend.is_alive(),
			"spent" if not is_instance_valid(pit) or not pit.is_alive() else "%d kills" % pit.trap_kills])
	get_tree().quit()


## A medicine man calls lightning on enemy infantry and shields a warrior; a priest converts.
func _scenario_magic() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	for spell in [918, 919, 920, 921, 922, 948]:
		main.players[1].researched[spell] = true
	var caster_guid := 164 if main.players[1].faction == "ind" else 257
	main._spawn_squad(caster_guid, 1, centre, 1)
	main._spawn_squad(152 if main.players[1].faction == "ind" else 252, 1, centre + Vector2(40, 0), 1)
	main._spawn_squad(458, 2, centre + Vector2(0, -260), 4)
	var caster: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == caster_guid)[0]
	var friend: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.position.distance_to(centre + Vector2(40, 0)) < 40)[0]
	var foes := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.position.distance_to(centre) < 400)
	for f: Unit in foes:
		f.stance = Unit.Stance.PASSIVE
	caster.stance = Unit.Stance.PASSIVE
	main.camera.position = centre + Vector2(0, -120)
	if caster_guid == 164:
		caster.cast(919, foes[0].position)
		await get_tree().create_timer(10.0).timeout
		caster.magic_energy = 100.0
		caster.cast(922, friend.position, friend)
		await get_tree().create_timer(4.0).timeout
		print("lightning: enemy energy %s; warrior shielded %.0fs; magic left %d" % [foes.map(func(f: Unit) -> int: return int(f.health)), friend.shield_time, caster.magic_energy])
	else:
		caster.cast(948, foes[0].position, foes[0])
		await get_tree().create_timer(8.0).timeout
		print("conversion: target now team %d" % foes[0].team)
	get_tree().quit()


## A cowboy takes over a wild cow; it grazes, then is driven to the stockyard and sold.
func _scenario_cattle() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var type := ObjectTypes.get_type(GameData.type_for_guid(402, main.terrain.biome))
	var ai := AiPlayer.new()
	var yard := MapObject.new()
	yard.position = ai._find_spot(type, hq.position)
	ai.free()
	yard.setup(type, 1)
	main.units_root.add_child(yard)
	main.nav.block_footprint(type, yard.position)
	main._spawn_squad(Unit.COW_DIR, 0, hq.position + Vector2(-260, 240), 1)
	main._spawn_squad(463, 1, hq.position + Vector2(0, 240), 1)
	var cow: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.is_cow() and n.position.distance_to(hq.position + Vector2(-260, 240)) < 60)[0]
	var cowboy: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 463)[0]
	cowboy.move_to(cow.position + Vector2(20, 0))
	await get_tree().create_timer(8.0).timeout
	print("cow team %d after the cowboy came by" % cow.team)
	await get_tree().create_timer(40.0).timeout
	var gold: int = main.players[1].resources.gold
	print("cow worth %.1f gold after grazing" % cow.cattle_value)
	cow.deliver(yard)
	await get_tree().create_timer(15.0).timeout
	print("sold: cow gone %s, gold +%d; stockyard trains: %s" % [not is_instance_valid(cow), main.players[1].resources.gold - gold,
			Array(MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.guid == 405).map(func(o: MapObject) -> Array: return Array(o.trainable_units())))])
	get_tree().quit()


## The computer's main building burns down; with its builders gone too it gives up.
func _scenario_surrender() -> void:
	await get_tree().create_timer(2.0).timeout
	if GameData.cmdline_option("keep-builders") == "":
		for n in main.units_root.get_children():
			if n is Unit and n.team == 2 and n.unit_type.can_build():
				n.take_damage(10000.0)
	main.players[2].main_building().take_damage(100000.0)
	await get_tree().create_timer(30.0).timeout
	print("player 2 surrendered: %s; game over: %s; rebuilding: %s" % [main.players[2].surrendered, main._game_over,
			MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.owner_index == 2 and o.guid in MapObject.MAIN_BUILDINGS and o.is_alive()).map(func(o: MapObject) -> String: return "%d%%" % int(o.build_progress * 100))])
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()


## Play a little, save, load the save in a fresh scene and compare.
func _scenario_saveload() -> void:
	if not main.loaded_game:
		await get_tree().create_timer(30.0).timeout
		print("before: %s" % _snapshot())
		SaveGame.save(self)
		Match.load_data = SaveGame.read()
		get_tree().reload_current_scene()
		return
	await get_tree().create_timer(1.0).timeout
	print("after:  %s" % _snapshot())
	await get_tree().create_timer(30.0).timeout
	print("later:  %s" % _snapshot())
	get_tree().quit()


func _snapshot() -> String:
	var units := Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team > 0)
	var buildings := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.is_building())
	var stumps := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.is_tree() and o.tree_state != MapObject.TreeState.STANDING)
	return "units %d, buildings %d (%s), felled/stumps %d, p1 %s, time %d" % [units.size(), buildings.size(),
			", ".join(buildings.map(func(b: MapObject) -> String: return "%s %d%%" % [b.display_name(), int(b.build_progress * 100)])),
			stumps.size(), main.players[1].resources, main.game_time]


## Formations, patrol, follow and a rally point, with positions printed as they play out.
func _scenario_orders() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var start := hq.position + Vector2(0, 220)
	main._spawn_squad(main.FACTIONS[main.players[1].faction].army, 1, start, 6)
	var squad := main.units_root.get_children().filter(func(n: Node) -> bool:
		return n is Unit and n.team == 1 and n.unit_type.guid() == main.FACTIONS[main.players[1].faction].army)
	main.selection._select(squad, false)
	main.hud.set_formation(Unit.Formation.WEDGE)
	main.selection._order_move(start + Vector2(0, 200))
	await get_tree().create_timer(6.0).timeout
	var centre := SelectionController._centre(squad)
	print("wedge slots: ", squad.map(func(u: Unit) -> Vector2: return ((u.position - centre) / 26.0).round()))
	main.selection.begin_targeting("patrol")
	main.selection._give_targeted(start + Vector2(260, 200))
	var leg := []
	for i in 12:
		await get_tree().create_timer(1.5).timeout
		leg.append(int(squad[0].position.x))
	print("patrol x over time: ", leg, " state ", squad[0].state)
	var leader: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 \
			and n not in squad)[0]
	main.selection._select(squad.slice(0, 2), false)
	main.selection.begin_targeting("follow")
	main.selection._give_targeted(leader.position)
	leader = squad[0].follow_target
	leader.move_to(leader.position + Vector2(-250, 0))
	await get_tree().create_timer(8.0).timeout
	print("follow distances: ", squad.slice(0, 2).map(func(u: Unit) -> int: return int(u.position.distance_to(leader.position))))
	main.selection.select_building(hq)
	main.selection.begin_targeting("rally")
	main.selection._give_targeted(hq.position + Vector2(-300, 150))
	main.players[1].resources.food = 5000
	for u in squad:
		u.queue_free()  # make room in the housing
	await get_tree().process_frame
	var before := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit)
	print("queued ", GameData.stats(hq.trainable_units()[1]).name, ": ", hq.enqueue(hq.trainable_units()[1]))
	await get_tree().create_timer(40.0).timeout
	var newest: Unit = null
	for n in main.units_root.get_children():
		if n is Unit and n.team == 1 and n not in before:
			newest = n
	if newest == null:
		print("nothing trained yet, queue ", hq.queue, " progress ", hq.train_progress)
		get_tree().quit()
		return
	print("rally flag: ", is_instance_valid(main.selection._rally_flag), " trained unit distance to rally: ",
			int(newest.position.distance_to(hq.rally_point)))
	get_tree().quit()


## The HQ with a queue of orders (cards), a right-clicked tree and a move marker.
func _scenario_ui() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	main.players[1].resources.food = 5000
	for guid in hq.trainable_units():
		hq.enqueue(guid)
		hq.enqueue(guid)
	main.selection.select_building(hq)
	var tree: MapObject = null
	for object in MapObject.all_objects:
		if object.is_tree() and (tree == null or object.position.distance_to(hq.position) < tree.position.distance_to(hq.position)):
			tree = object
	main.camera.position = tree.position
	var picked := main.selection._resource_at(tree.position + Vector2(0, -60))
	print("click above trunk picks the tree: ", picked == tree, " ", picked.position if picked else null, " ", tree.position)
	for i in 4:
		await get_tree().create_timer(0.35).timeout
		tree.flash()
	OrderMarker.spawn(main.units_root, tree.position + Vector2(-120, 40), 1)


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
	var helpers := workers.filter(func(u: Unit) -> bool: return u.build_site == site).size()
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
	print("queued: ", hq.enqueue(252), hq.enqueue(252))


## A finca with two fields worked by three women, and two militiamen hunting.
func _scenario_food() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var ai := AiPlayer.new()
	ai.biome = main.terrain.biome
	var finca_type := ObjectTypes.get_type(GameData.type_for_guid(208, main.terrain.biome))
	var finca := MapObject.new()
	finca.position = ai._find_spot(finca_type, hq.position)
	finca.setup(finca_type, 1)
	main.units_root.add_child(finca)
	main.nav.block_footprint(finca_type, finca.position)
	ai.free()
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
				node.hunt(node._nearest_animal())
	print("food scenario: finca at %s, %d women farming" % [finca.position, i])


func _nearest_mine(from: Vector2) -> MapObject:
	var best: MapObject = null
	for object in MapObject.all_objects:
		if object.resource == "gold" and (best == null or from.distance_to(object.position) < from.distance_to(best.position)):
			best = object
	return best


## A cowboy mounts a wild horse, dismounts, and the horse is led into a ranch.
func _scenario_horses() -> void:
	var hq: MapObject = main.players[1].main_building()
	var type := ObjectTypes.get_type(GameData.type_for_guid(405, main.terrain.biome))
	var ai := AiPlayer.new()
	var ranch := MapObject.new()
	ranch.position = ai._find_spot(type, hq.position)
	ai.free()
	ranch.setup(type, 1)
	main.units_root.add_child(ranch)
	main.nav.block_footprint(type, ranch.position)
	main._spawn_squad(Unit.HORSE_DIR, 0, hq.position + Vector2(-240, 240), 1)
	main._spawn_squad(463, 1, hq.position + Vector2(0, 240), 1)
	var horse: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.is_horse())[0]
	var cowboy: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 463)[0]
	cowboy.mount(horse)
	await get_tree().create_timer(8.0).timeout
	var rider: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.is_alive() and n.unit_type.guid() == 464)[0] if main.units_root.get_children().any(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 464) else null
	print("mounted: %s (horse gone %s)" % [rider != null, not is_instance_valid(horse)])
	rider.dismount()
	await get_tree().process_frame
	var led: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.is_horse() and n.team == 1)[0]
	led.stable(ranch)
	await get_tree().create_timer(12.0).timeout
	print("horses %d / %d, cowboy on foot again %s" % [main.players[1].resources.horses, main.players[1].horse_capacity(),
			main.units_root.get_children().any(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 463)])
	get_tree().quit()
