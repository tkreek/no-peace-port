class_name InterfaceScenarios
extends Scenario
## Developer scenarios: menus, selection, picking, orders, saving and loading.


## The in-game menu's options panel, open.
func _scenario_options() -> void:
	main.hud.toggle_menu()
	main.hud.menu.show_options()


## Print the command buttons shown for player 1's builders and for its farmers, and the
## train buttons of each of its people's buildings (placed finished next to the HQ).
func _scenario_menus() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") != main.players[1].faction or stats.get("kind") != "structure":
			continue
		var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
		var building := MapObject.new()
		building.setup(type, 1)
		if building.production.trainable_units().is_empty():
			building.free()
			continue
		building.position = AiBuilder.find_spot(type, hq.position)
		main.units_root.add_child(building)
		main.selection.select_building(building)
		main.hud.commands.signature = ""
		main.hud.commands.refresh()
		await get_tree().process_frame
		var names := []
		for button in main.hud.commands.grid.get_children():
			if not button.is_queued_for_deletion():
				names.append(button.tooltip_text.replace("\n", " / "))
		var queued := []
		for unit_guid in building.production.trainable_units():
			queued.append("%s:%s" % [GameData.stats(unit_guid).get("name"), building.production.enqueue(unit_guid)])
		print("%s: %s | enqueue %s" % [stats.name, names, queued])
	for kind in ["builders", "farmers"]:
		var units := main.units_root.get_children().filter(func(n: Node) -> bool:
			return n is Unit and n.team == 1 and (n.unit_type.anim_index("build") >= 0 if kind == "builders" else n.unit_type.is_farmer()))
		main.selection._select(units, false)
		for menu in ["", "basic", "expanded"]:
			main.hud.commands.open_build_menu(menu)
			main.hud.commands.refresh()
			await get_tree().process_frame
			var names := []
			for button in main.hud.commands.grid.get_children():
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
			var site := MapObject.new()
			site.position = AiBuilder.find_spot(type, hq.position)
			site.setup(type, 1, 0, GameData.cmdline_option("pick") == "site")
			main.units_root.add_child(site)
			if GameData.cmdline_option("pick") == "site":
				site.condition.add_build_work(20.0)
			else:
				main.players[1].resources.gold = 5000
				main.players[1].resources.food = 5000
				site.production.enqueue(site.production.researchable_upgrades()[0])
				site.production.enqueue(site.production.researchable_upgrades()[1])
			main.selection.select_building(site)


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
	# Open ground inside the walls' bounding box (L-shaped and diagonal buildings have some).
	var walls := hq.work_rect()
	for y in range(int(walls.position.y) + 2, int(walls.end.y), 4):
		for x in range(int(walls.position.x) + 2, int(walls.end.x), 4):
			var p := Vector2(x, y)
			if not probes.has("open corner of the walls' box") and not hq.near_walls(p, 8.0) \
					and not hq._body.is_pixel_opaque(hq._body.to_local(p)):
				probes["open corner of the walls' box"] = p
	for label in probes:
		print("%-36s -> %s" % [label, main.selection._building_at(probes[label]) == hq])
	get_tree().quit()


## Play a little, save, load the save in a fresh scene and compare.
func _scenario_saveload() -> void:
	if not main.loaded_game:
		await get_tree().create_timer(30.0).timeout
		print("before: %s" % _snapshot())
		SaveGame.save(main)
		Match.load_data = SaveGame.read()
		get_tree().reload_current_scene()
		return
	await get_tree().create_timer(1.0).timeout
	print("after:  %s" % _snapshot())
	await get_tree().create_timer(30.0).timeout
	print("later:  %s" % _snapshot())
	get_tree().quit()


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
	main.hud.commands.set_formation(Unit.Formation.WEDGE)
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
	await _orders_landed()
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
	print("queued ", GameData.stats(hq.production.trainable_units()[1]).name, ": ", hq.production.enqueue(hq.production.trainable_units()[1]))
	await get_tree().create_timer(40.0).timeout
	var newest: Unit = null
	for n in main.units_root.get_children():
		if n is Unit and n.team == 1 and n not in before:
			newest = n
	if newest == null:
		print("nothing trained yet, queue ", hq.production.queue, " progress ", hq.production.progress)
		get_tree().quit()
		return
	print("rally flag: ", is_instance_valid(main.selection._rally_flag), " trained unit distance to rally: ",
			int(newest.position.distance_to(hq.production.rally_point)))
	get_tree().quit()


## The HQ with a queue of orders (cards), a right-clicked tree and a move marker.
func _scenario_ui() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	main.players[1].resources.food = 5000
	for guid in hq.production.trainable_units():
		hq.production.enqueue(guid)
		hq.production.enqueue(guid)
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


## The outlaws' expanded build menu beside the buildings it offers (picture check).
func _scenario_icons() -> void:
	var hq: MapObject = main.players[1].main_building()
	var x := -360.0
	for guid in GameData.cmdline_option("guids", "310,311,313").split(","):
		var type := ObjectTypes.get_type(GameData.type_for_guid(guid.to_int(), main.terrain.biome))
		var b := MapObject.new()
		b.position = hq.position + Vector2(x, 330)
		b.setup(type, 1)
		main.units_root.add_child(b)
		x += 260.0
	main.camera.position = hq.position + Vector2(-100, 260)
	var builders := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.anim_index("build") >= 0)
	main.selection._select(builders, false)
	main.hud.commands.open_build_menu("expanded")


## Filling the housing warns once; a train order with no room left warns again.
func _scenario_poplimit() -> void:
	var player: Player = main.players[1]
	var hq: MapObject = player.main_building()
	await get_tree().process_frame
	var before := main.hud.population_warnings
	main._spawn_squad(main.FACTIONS[player.faction].army, 1, hq.position + Vector2(0, 260),
			player.population_limit() - player.population())
	for i in 3:
		await get_tree().process_frame
	var filled := main.hud.population_warnings - before
	main.selection.select_building(hq)
	player.resources.food = 5000
	await get_tree().process_frame
	await get_tree().process_frame
	var trained := -1
	for button in main.hud.commands.grid.get_children():
		var guid: int = button.get_meta("guid", -1)
		if GameData.stats(guid).get("kind") == "unit" and hq.production.can_enqueue(guid):
			trained = guid
			button.pressed.emit()
			break
	for i in 3:
		await get_tree().process_frame
	var on_order := main.hud.population_warnings - before - filled
	var queued := Array(hq.production.queue).has(trained)
	# Like the original, the order is taken; the finished unit waits for living space.
	await get_tree().create_timer(BuildingProduction.production_seconds(int(GameData.stats(trained).build_time)) + 2.0).timeout
	var held := hq.production.queue.size() == 1 and hq.production.progress >= 1.0
	var while_held := main.hud.population_warnings - before - filled - on_order
	var population := player.population()
	for unit in Unit.all_units:
		if unit.team == 1 and unit.is_alive() and unit.unit_type.guid() != trained:
			unit.die()
			break
	await get_tree().create_timer(1.0).timeout
	print("population %d / %d: warned on filling %d, on a train order %d; queued %s, held when done %s, warned %d; out once room: %s" % [
			population, player.population_limit(), filled, on_order, queued, held, while_held,
			hq.production.queue.is_empty() and player.population() == population])
	get_tree().quit()


## Every building of player 1's people placed finished near the HQ and outlined, as when
## selected (to check the diamonds against the walls).
func _scenario_outlines() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	hq.selected = true
	for guid in GameData.stats_guids():
		var stats := GameData.stats(guid)
		if stats.get("faction") != main.players[1].faction or stats.get("kind") != "structure":
			continue
		var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
		if type == null:
			continue
		var building := MapObject.new()
		building.setup(type, 1)
		building.position = AiBuilder.find_spot(type, hq.position)
		main.units_root.add_child(building)
		NavGrid.current.block_footprint(type, building.position)
		building.selected = true
	main.camera.position = hq.position + Vector2(0, 80)


## Left clicks on a buffalo and an enemy soldier select them to look at (the panel shows
## their status, they take no orders); a right click on a wild horse with a cowboy
## selected circles the horse. --pick=animal|enemy|mount picks what the screenshot shows.
func _scenario_inspect() -> void:
	var hq: MapObject = main.players[1].main_building()
	var at := hq.position + Vector2(0, 220)
	main._spawn_squad("animals/buffalo", 0, at + Vector2(-120, 0), 1)
	main._spawn_squad(UnitAnimal.HORSE_DIR, 0, at + Vector2(120, 0), 1)
	main._spawn_squad(463, 2, at + Vector2(0, 90), 1)
	main._spawn_squad(463, 1, at + Vector2(0, -60), 1)
	main.camera.position = at
	await get_tree().process_frame
	await get_tree().process_frame
	var find := func(test: Callable) -> Unit:
		var found := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and test.call(n))
		found.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_to(at) < b.position.distance_to(at))
		return found[0]
	var buffalo: Unit = find.call(func(u: Unit) -> bool: return u.team == 0 and not u.animal.is_horse())
	var horse: Unit = find.call(func(u: Unit) -> bool: return u.animal.is_horse())
	var enemy: Unit = find.call(func(u: Unit) -> bool: return u.team == 2)
	var cowboy: Unit = find.call(func(u: Unit) -> bool: return u.team == 1 and u.unit_type.guid() == 463)
	enemy.fogged = false
	var click := func(world: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
		var screen: Vector2 = main.get_viewport().get_canvas_transform() * world
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = pressed
			event.position = screen
			main.selection._unhandled_input(event)
	for target: Unit in [buffalo, enemy]:
		click.call(target.position + Vector2(0, -14))
		main.hud.selected.refresh()
		main.hud.commands.refresh()
		var before := target.position
		click.call(target.position + Vector2(200, 0), MOUSE_BUTTON_RIGHT)
		await get_tree().process_frame
		print("clicked %s: selected %s, panel '%s' with %d stats, %d command buttons, ordered %s" % [
				target.unit_type.guid(), main.selection.selection == [target], main.hud.selected._title.text,
				main.hud.selected._stats.get_child_count(), main.hud.commands.grid.get_child_count(),
				target.path.size() > 0 or target.position != before])
	var pick := GameData.cmdline_option("pick", "mount")
	if pick == "mount":
		main.selection.select_units([cowboy])
		click.call(horse.position + Vector2(0, -12), MOUSE_BUTTON_RIGHT)
		print("mount order rings the horse: %s" % horse._flash_ring)
	else:
		click.call((buffalo if pick == "animal" else enemy).position + Vector2(0, -14))


## Nothing but a player's orders, given through the interface for 90 s (for --record and
## --replay, which must end in the same game): workers gather and build houses, the main
## building trains, soldiers and workers are sent about, stances change; on the Diplomacy
## page the next people is made an ally and later an enemy again, and allies are sent food.
func _scenario_commands() -> void:
	print("teams: %s, %s" % [main.players.values().map(func(p: Player) -> int: return p.team), Diplomacy.fingerprint()])
	var hq: MapObject = main.players[main.me].main_building()
	var picker := RandomNumberGenerator.new()
	picker.seed = 3
	var house_guid: int = {"mex": 201, "usa": 401, "des": 301, "ind": 101}[main.players[main.me].faction]
	var house := ObjectTypes.get_type(GameData.type_for_guid(house_guid, main.terrain.biome))
	for round in 45:
		var due := Sim.tick + Sim.RATE * 2  # rounds go by game time (a network game may wait)
		while Sim.tick < due:
			await get_tree().physics_frame
		var own := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == main.me and u.is_alive())
		if own.is_empty() or not is_instance_valid(hq):
			break
		var some := own.slice(0, picker.randi_range(1, own.size()))
		var next_people := main.me % main.players.size() + 1
		if round in [12, 26]:
			Orders.declare(next_people, round == 12)
		elif round in [8, 18]:
			Orders.send("food", main.players.keys())
		match round % 5:
			0:
				main.selection._select(some, false)
				main.selection.order_at(hq.position + Vector2(picker.randf_range(-400, 400), picker.randf_range(150, 400)))
			1:
				var trees := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.is_tree() and o.stock.amount > 0)
				trees.sort_custom(func(a: MapObject, b: MapObject) -> bool:
					return a.position.distance_to(hq.position) < b.position.distance_to(hq.position))
				main.selection._select(own.filter(func(u: Unit) -> bool: return u.unit_type.can_gather("wood")), false)
				main.selection.order_gather(trees[picker.randi_range(0, mini(5, trees.size() - 1))])
			2:
				main.selection.select_building(hq)
				var guid: int = hq.production.trainable_units()[picker.randi_range(0, 1)]
				if hq.production.can_enqueue(guid):
					Orders.building(hq, "enqueue", [guid])
			3:
				main.selection._select(own.filter(func(u: Unit) -> bool: return u.unit_type.can_build()), false)
				main.build_controller.start(house.id)
				var spot := AiBuilder.find_spot(house, hq.position, 220 + round * 8)
				if spot != Vector2.INF and main.build_controller.can_place(spot):
					main.build_controller._place(spot, false)
				main.build_controller.cancel()
			4:
				main.selection._select(some, false)
				main.hud.commands.set_stance(picker.randi_range(0, 2))
	get_tree().quit()


## Control groups by keyboard: Ctrl+1 keeps the selection, 1 brings it back; Ctrl+2 keeps
## a building, and its button on the HUD selects it and brings the view there.
func _scenario_groups() -> void:
	await get_tree().create_timer(0.5).timeout
	var own := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == main.me and u.is_alive())
	main.selection._select(own.slice(0, 3), false)
	await _key(KEY_1, true)
	main.selection._select([], false)
	await _key(KEY_1)
	print("group 1 recalled: %d of 3" % main.selection.selection.size())
	var hq: MapObject = MapObject.all_objects.filter(func(o: MapObject) -> bool:
		return o.is_building() and o.owner_index == main.me)[0]
	main.selection.select_building(hq)
	await _key(KEY_2, true)
	main.selection._select(own.slice(0, 1), false)
	main.camera.position = hq.position + Vector2(900, 600)
	await get_tree().process_frame
	var buttons := main.hud.groups.root.get_children()
	print("group buttons: %s" % ",".join(buttons.map(func(f: Control) -> String: return str(f.get_meta("digit")))))
	(buttons[1].get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	print("group 2 button: building %s, view %.0f px away, lit %d" % [main.selection.selected_building == hq,
			main.camera.position.distance_to(hq.position), main.hud.groups._active])
	main.selection._select([], false)
	await _key(KEY_2)
	print("group 2 key: building %s" % (main.selection.selected_building == hq))
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()


func _key(key: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


## Units where buildings and trees are drawn over them (the cover cells, grid bit 29):
## three behind our main building and four under the thickest canopy (one of each an
## enemy's, our three in the forest selected), and one in the open. Prints which show through.
## --cover-view=building|forest points the camera there for a screenshot.
func _scenario_cover() -> void:
	main.get_viewport().gui_disable_input = true  # keys pressed elsewhere while the window pops up
	var nav := NavGrid.current
	var hq: MapObject = main.players[1].main_building()
	var picture := hq.visual_rect()
	var behind := _cover_spots(picture, picture.position + picture.size * Vector2(0.5, 0.4), 3)
	var forest: MapObject = null
	var thickest := 0
	var inland := Rect2(Vector2.ZERO, main.terrain.map.pixel_size()).grow(-400.0)  # the view not up against an edge
	for tree in MapObject.all_objects:
		if tree.is_tree() and tree.position.distance_to(hq.position) > 500.0 and inland.has_point(tree.position):
			var near := MapObject.all_objects.filter(func(o: MapObject) -> bool:
				return o.is_tree() and o.position.distance_to(tree.position) < 120.0).size()
			if near > thickest:
				thickest = near
				forest = tree
	var under := _cover_spots(Rect2(forest.position - Vector2(96, 128), Vector2(192, 160)), forest.position, 4)
	var worker: int = hq.production.trainable_units()[0]
	var soldier: int = hq.production.trainable_units()[-1]
	var enemy: int = main.players[2].main_building().production.trainable_units()[0]
	var placed: Array[Unit] = []
	for i in behind.size():
		placed.append(_cover_unit(enemy if i == 1 else worker, 2 if i == 1 else 1, behind[i]))
	var mine: Array[Unit] = []
	for i in under.size():
		(mine if i < 3 else placed).append(_cover_unit([soldier, worker, worker, enemy][i], 2 if i == 3 else 1, under[i]))
	var open := _cover_unit(soldier, 1, (Vector2(nav.nearest_walkable(nav.cell_of(hq.position + Vector2(0, 260)))) + Vector2(0.5, 0.5)) * NavGrid.CELL)
	main.selection.select_units(mine)
	main.camera.position = forest.position if GameData.cmdline_option("cover-view") == "forest" else picture.get_center()
	for i in 4:
		await get_tree().physics_frame
	var through := func(units: Array) -> int:
		return units.filter(func(u: Unit) -> bool: return u.has_method("shows_through") and u.shows_through()).size()
	print("cover views: building %s, forest %s" % [picture.get_center().round(), forest.position.round()])
	print("cover: behind the building and in a forest of %d trees %d spots, %d show through; in the open shows through %s" % [
			thickest, behind.size() + under.size(), through.call(placed + mine), through.call([open]) == 1])
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()


## Up to `count` walkable cover cells in `area`, nearest `toward` first, a cell apart.
func _cover_spots(area: Rect2, toward: Vector2, count: int) -> Array[Vector2]:
	var nav := NavGrid.current
	var spots: Array[Vector2] = []
	for y in range(int(area.position.y), int(area.end.y), NavGrid.CELL):
		for x in range(int(area.position.x), int(area.end.x), NavGrid.CELL):
			var cell := nav.cell_of(Vector2(x, y))
			if nav.flags_at(cell) & NavGrid.COVER and nav.is_walkable(cell):
				spots.append(nav.center_of(cell))
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(toward) < b.distance_to(toward))
	var picked: Array[Vector2] = []
	for spot in spots:
		if picked.size() < count and picked.all(func(p: Vector2) -> bool: return p.distance_to(spot) >= 30.0):
			picked.append(spot)
	return picked


func _cover_unit(guid: int, team: int, at: Vector2) -> Unit:
	var unit := Unit.new()
	unit.position = at
	main.units_root.add_child(unit)
	unit.setup(UnitType.for_guid(guid), team)
	unit.direction = 1
	return unit
