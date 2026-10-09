class_name WaterScenarios
extends Scenario
## Developer scenarios: boats, swimming and the travois.


## A travois packs a sleeping tepee and sets it up again elsewhere.
func _scenario_tepee() -> void:
	var hq: MapObject = main.players[1].main_building()
	var type := ObjectTypes.get_type(GameData.type_for_guid(101, main.terrain.biome))
	var tepee := MapObject.new()
	tepee.position = AiBuilder.find_spot(type, hq.position)
	tepee.setup(type, 1)
	main.units_root.add_child(tepee)
	main.nav.block_footprint(type, tepee.position)
	tepee.take_damage(tepee.max_health * 0.3)
	var target := AiBuilder.find_spot(type, hq.position + Vector2(-400, 300))
	main._spawn_squad(UnitTepees.TRAVOIS, 1, tepee.position + Vector2(0, 160), 1)
	var travois: Unit = Unit.all_units.filter(func(u: Unit) -> bool: return u.unit_type.guid() == UnitTepees.TRAVOIS)[0]
	var cap: int = main.players[1].population_cap()
	main.selection._select([travois], false)
	main.selection.begin_targeting("pack")
	main.selection._give_targeted(tepee.work_rect().get_center())
	await get_tree().create_timer(14.0).timeout
	print("packed %s, tepee gone %s, housing %d -> %d" % [travois.tepees.packed, not is_instance_valid(tepee), cap, main.players[1].population_cap()])
	main.hud.commands.unpack_tepee()
	main.build_controller._place(target, false)
	for i in 5:
		await get_tree().create_timer(5.0).timeout
		var again := MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.guid == 101 and o.owner_index == 1)
		print("t=%ds travois at %s carrying %s; tepees %s" % [(i + 1) * 5, travois.position.round(), not travois.tepees.packed.is_empty(),
				again.map(func(o: MapObject) -> String: return "%s %d%%" % ["up" if o.complete else "site", int(100 * o.health / o.max_health)])])
	main.camera.position = target
	print("housing now %d" % main.players[1].population_cap())
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()


## A wharf by the water launches a riverboat; infantry board it, sail to the nearest other
## shore and land; Native warriors with Swim cross on their own.
func _scenario_boats() -> void:
	var nav: NavGrid = main.nav
	var hq: MapObject = main.players[1].main_building()
	var faction: String = main.players[1].faction
	var wharf_guid: int = {"mex": 218, "usa": 418, "des": 315, "ind": -1}[faction]
	var boat_guid: int = {"mex": 254, "usa": 454, "des": 364, "ind": -1}[faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(wharf_guid, main.terrain.biome))
	var spot := Vector2.INF
	for radius in range(200, 2400, 48):
		for step in 24:
			var at: Vector2 = (hq.position + Vector2(radius, 0).rotated(step * TAU / 24.0)).snapped(Vector2(16, 16))
			if AiBuilder.footprint_free(type, at, nav) and MapObject.by_water(type, at):
				spot = at
				break
		if spot != Vector2.INF:
			break
	print("wharf spot %s (%d px from HQ)" % [spot, spot.distance_to(hq.position) if spot != Vector2.INF else -1])
	var wharf := MapObject.new()
	wharf.position = spot
	wharf.setup(type, 1)
	main.units_root.add_child(wharf)
	nav.block_footprint(type, spot)
	wharf.unit_trained.connect(main._on_unit_trained)
	main.camera.position = spot
	main.players[1].resources.wood = 5000
	main.players[1].resources.gold = 5000
	main.players[1].resources.food = 5000
	print("enqueue boat: %s (%s s)" % [wharf.production.enqueue(boat_guid), GameData.stats(boat_guid).get("build_time")])
	var boat: Unit = null
	for i in 120:
		await get_tree().create_timer(1.0).timeout
		var boats := Unit.all_units.filter(func(u: Unit) -> bool: return u.water.is_boat())
		if not boats.is_empty():
			boat = boats[0]
			break
	if boat == null:
		print("no boat launched")
		get_tree().quit()
		return
	print("boat launched at %s, on deep water %s" % [boat.position.round(), boat.water.on_water()])
	# The player's way: click the boat's hull (well off its middle), then right-click open water.
	main.selection._select([], false)
	await _click(boat.position + Vector2(0, 30))
	var open_water := Vector2.INF
	for r in range(12, 40):
		for k in 16:
			var cell := nav.cell_of(boat.position) + Vector2i(Vector2(r, 0).rotated(k * TAU / 16.0).round())
			if open_water == Vector2.INF and nav.is_deep_water(cell):
				open_water = nav.center_of(cell)
	var launched_at := boat.position
	await _click(open_water, MOUSE_BUTTON_RIGHT)
	for i in 20:
		await get_tree().create_timer(1.0).timeout
		if boat.state == Unit.State.IDLE:
			break
	print("clicked boat selected %s; sailed %d px, %d px short of the click" % [main.selection.selection == [boat],
			boat.position.distance_to(launched_at), boat.position.distance_to(open_water)])
	var army_guid: int = main.FACTIONS[faction].army
	main._spawn_squad(army_guid, 1, spot + Vector2(0, 140), 4)
	var soldiers := Unit.all_units.filter(func(u: Unit) -> bool: return u.unit_type.guid() == army_guid and u.team == 1)
	main.selection._select(soldiers, false)
	main.selection.order_board(boat, soldiers)
	for i in 10:
		await get_tree().create_timer(2.0).timeout
		if boat.water.passengers.size() == soldiers.size():
			break
	print("aboard %d / %d" % [boat.water.passengers.size(), soldiers.size()])
	# The nearest bank straight across deep water.
	var landing := Vector2.INF
	for step in 32:
		var heading := Vector2.RIGHT.rotated(step * TAU / 32.0)
		var deep := 0
		for k in range(1, 300):
			var cell := nav.cell_of(boat.position + heading * k * 16.0)
			if nav.is_deep_water(cell):
				deep += 1
			elif deep >= 12 and nav.is_walkable(cell):
				var at := boat.position + heading * k * 16.0
				if landing == Vector2.INF or at.distance_to(boat.position) < landing.distance_to(boat.position):
					landing = at
				break
			elif not nav.is_water(cell) and deep > 0:
				break
	print("landing at %s" % landing)
	boat.unload_at(landing)
	for i in 30:
		await get_tree().create_timer(2.0).timeout
		main.camera.position = boat.position
		if boat.water.passengers.is_empty():
			break
	print("boat at %s, passengers %d, soldiers ashore %s" % [boat.position.round(), boat.water.passengers.size(),
			soldiers.map(func(u: Unit) -> String: return "%d" % int(u.position.distance_to(landing)) if is_instance_valid(u) and not u.inside else "aboard")])
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()


## Native warriors who have learned to swim cross deep water; without Swim they cannot.
func _scenario_swim() -> void:
	var nav: NavGrid = main.nav
	var hq: MapObject = main.players[1].main_building()
	# The nearest deep water to the HQ, and the bank across it.
	var shore := Vector2.INF
	var across := Vector2.INF
	for step in 64:
		var heading := Vector2.RIGHT.rotated(step * TAU / 64.0)
		var deep := 0
		var first := Vector2.INF
		for k in range(1, 400):
			var at := hq.position + heading * k * 16.0
			var cell := nav.cell_of(at)
			if nav.is_deep_water(cell):
				if deep == 0:
					first = at - heading * 48.0
				deep += 1
			elif deep >= 10 and nav.is_walkable(cell):
				if shore == Vector2.INF or first.distance_to(hq.position) < shore.distance_to(hq.position):
					shore = first
					across = at + heading * 32.0
				break
	print("shore %s, across %s" % [shore, across])
	main.players[1].complete_research(914)
	main._spawn_squad(152, 1, shore, 3)
	main._spawn_squad(153, 1, shore + Vector2(0, 40), 1)
	main._spawn_squad(UnitWater.CANOE, 1, shore + Vector2(40, 0), 1)
	main.camera.position = shore
	var swimmers := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 1 and u.unit_type.guid() in [152, 153, UnitWater.CANOE])
	for u: Unit in swimmers:
		u.move_to(across)
	var seen_swimming := false
	for i in 20:
		await get_tree().create_timer(2.0).timeout
		for u: Unit in swimmers:
			if u.unit_type.guid() == UnitWater.CANOE and u.water.on_water():
				print("  canoe on water plays ", u._action)
			if u.water.on_water() and u._action == "swim":
				seen_swimming = true
				main.camera.position = u.position
		if i % 4 == 3:
			print("t=%ds %s" % [(i + 1) * 2, swimmers.map(func(u: Unit) -> String: return "%d%s" % [int(u.position.distance_to(across)), "~" if u.water.on_water() else ""])])
	print("swam: %s" % seen_swimming)
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()
