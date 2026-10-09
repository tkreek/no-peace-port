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
	for button in main.hud.commands.grid.get_children():
		if GameData.stats(button.get_meta("guid", -1)).get("kind") == "unit":
			button.pressed.emit()
			break
	print("population %d / %d: warned on filling %d, on a train order %d" % [player.population(), player.population_limit(),
			filled, main.hud.population_warnings - before - filled])
	get_tree().quit()
