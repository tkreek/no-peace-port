extends Scenario
## Campaign missions played through by orders, as a player would (start them with
## --mission=...): checks that the mission's script, the units joining and the goals work.


## --mission=base/tut_01: walk the chief to the four tribesmen waiting in the mountains,
## set up the chief's tepee on its marked spot, gather 100 wood: the tutorial is won.
func _scenario_tutorial1() -> void:
	var mission := main.mission
	await _until(func() -> bool: return not Orders.locked, 120.0, "the opening scene")
	var chief := _own(func(u: Unit) -> bool: return u.unit_type.guid() in Player.COMMANDERS)[0] as Unit
	# Independent tribesmen join whoever walks up to them.
	var waiting := Unit.all_units.filter(func(u: Unit) -> bool:
		return u.is_alive() and u.team > 0 and Diplomacy.neutral(main.me, u.team))
	print("tribesmen waiting: %d" % waiting.size())
	for unit: Unit in waiting:
		if unit.team == main.me:
			continue
		Orders.unit(chief, "move_to", [unit.position])
		await _until(func() -> bool: return unit.team == main.me, 120.0, "a tribesman joining")
	print("joined: %d of %d" % [waiting.filter(func(u: Unit) -> bool: return u.team == main.me).size(), waiting.size()])
	# The chief's tepee on its marked spot (area 6), put up by the women.
	await _until(func() -> bool: return mission.goal == 105, 120.0, "the tepee goal")
	var women := _own(func(u: Unit) -> bool: return u.unit_type.anim_index("build") >= 0 and not u.unit_type.can_gather("wood"))
	if women.is_empty():
		women = _own(func(u: Unit) -> bool: return u.unit_type.anim_index("build") >= 0)
	var spot := mission.area(6).get_center()
	Orders.place(GameData.type_for_guid(100, main.terrain.biome), spot, false, null, women)
	await _until(func() -> bool: return mission.count(main.me, 100, mission.area(6)) == 1 and _tepee_done(), 300.0, "the tepee")
	print("tepee standing in its spot; wood %d" % main.players[main.me].resources.wood)
	# Wood: everyone who can, at the nearest trees.
	var cutters := _own(func(u: Unit) -> bool: return u.unit_type.can_gather("wood"))
	var tree := _nearest_tree(spot)
	Orders.units(cutters, "gather", [tree])
	await _until(func() -> bool: return mission.outcome != 0, 600.0, "the end of the tutorial")
	print("TUTORIAL 1 %s at %.0f s, wood %d" % ["WON" if mission.outcome > 0 else "LOST", Sim.time(),
			main.players[main.me].resources.wood])
	get_tree().quit()


## --mission=base/tut_02: a granary and two fields, a training tepee and five arrow
## shooters; then the buffalo the script brings are hunted down and the tutorial is won.
func _scenario_tutorial2() -> void:
	var mission := main.mission
	var me := main.players[main.me] as Player
	var hq := _own_building(100)
	var women := _own(func(u: Unit) -> bool: return u.unit_type.is_farmer())
	var cutters := _own(func(u: Unit) -> bool: return u.unit_type.can_gather("wood") and not u.unit_type.is_farmer())
	print("start: %d women, %d wood cutters, %s" % [women.size(), cutters.size(), me.resources])
	if not cutters.is_empty():
		Orders.units(cutters, "gather", [_nearest_tree(hq.position)])
	await _build(108, hq.position, women)  # granary
	for i in 2:
		await _build(MapObject.FIELD_GUID, hq.position, [women[i % women.size()]], false)
	await _until(func() -> bool: return int(me.resources.food) >= 150, 900.0, "150 food")
	print("150 food at %.0f s" % Sim.time())
	var helpers := women.slice(2) if women.size() > 2 else women
	await _build(101, hq.position, helpers)  # room for the new shooters
	var school := await _build(103, hq.position, helpers)
	await _until(func() -> bool:
		_keep_farming(women)
		if school.production.queue.is_empty() and mission.count(main.me, 156) < 5:
			Orders.building(school, "enqueue", [156])
		return mission.count(main.me, 156) >= 5, 900.0, "five arrow shooters")
	print("five arrow shooters at %.0f s" % Sim.time())
	await _until(func() -> bool: return mission.goal == 136, 300.0, "the buffalo")
	var shooters := _own(func(u: Unit) -> bool: return u.unit_type.guid() == 156)
	await _until(func() -> bool:
		var herd := Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.unit_type.guid() == Mission.BUFFALO)
		if not herd.is_empty() and shooters.all(func(s: Unit) -> bool: return s.state == Unit.State.IDLE or not s.work.hunting):
			Orders.units(shooters, "hunt", [herd[0]])
		return mission.outcome != 0, 1200.0, "the buffalo hunted")
	print("TUTORIAL 2 %s at %.0f s, food %d" % ["WON" if mission.outcome > 0 else "LOST", Sim.time(), me.resources.food])
	get_tree().quit()


## --mission=base/tut_03: a corral and a wood processing tepee, a wild horse caught,
## ridden home and put in the corral, a travois built; five more horses for the arrow
## shooters, who ride ahead to the settlers' warehouse (the trappers there flee, run by
## their AI module), and the travois takes the guns: won.
func _scenario_tutorial3() -> void:
	var mission := main.mission
	var me := main.players[main.me] as Player
	var hq := _own_building(100)
	var women := _own(func(u: Unit) -> bool: return u.unit_type.is_farmer())
	var cutters := _own(func(u: Unit) -> bool: return u.unit_type.guid() == 152)
	Orders.units(cutters, "gather", [_nearest_tree(hq.position)])
	var corral := await _build(105, hq.position, women)
	var works := await _build(109, hq.position, women)
	await _until(func() -> bool: return mission.goal == 162, 300.0, "the wild horse")
	var rider := _own(func(u: Unit) -> bool: return u.unit_type.guid() == 156)[0] as Unit
	var horse := _nearest_unit(mission.area(8).get_center(), func(u: Unit) -> bool: return u.animal.is_horse() and u.team == 0)
	Orders.unit(rider, "mount", [horse])
	await _until(func() -> bool: return mission.count(main.me, 157) > 0, 300.0, "a mounted shooter")
	print("caught a horse at %.0f s" % Sim.time())
	var mounted := _own(func(u: Unit) -> bool: return u.unit_type.guid() == 157)[0] as Unit
	Orders.unit(mounted, "move_to", [corral.position + Vector2(0, 90)])
	await _until(func() -> bool: return mounted.position.distance_to(corral.position + Vector2(0, 90)) < 40.0, 300.0, "the ride home")
	Orders.unit(mounted, "dismount")
	await get_tree().create_timer(0.5).timeout
	var loose := _nearest_unit(corral.position, func(u: Unit) -> bool: return u.animal.is_horse() and u.is_alive())
	Orders.unit(loose, "stable", [corral])
	await _until(func() -> bool: return int(me.resources.horses) >= 1, 120.0, "the horse in the corral")
	print("horse in the corral at %.0f s" % Sim.time())
	await _until(func() -> bool:
		if works.production.queue.is_empty() and mission.count(main.me, 155) == 0:
			Orders.building(works, "enqueue", [155])
		return mission.count(main.me, 155) > 0, 600.0, "the travois")
	print("travois at %.0f s" % Sim.time())
	# The script lets five horses loose in the southeast: one for each arrow shooter.
	await get_tree().create_timer(1.0).timeout
	var horses := Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.animal.is_horse() and u.team == 0)
	var shooters := _own(func(u: Unit) -> bool: return u.unit_type.guid() == 156)
	for i in mini(horses.size(), shooters.size()):
		Orders.unit(shooters[i], "mount", [horses[i]])
	await _until(func() -> bool: return mission.count(main.me, 157) > 4, 600.0, "five mounted shooters")
	print("five mounted shooters at %.0f s" % Sim.time())
	var store := _nearest_store(mission.area(1).get_center())
	var escort := _own(func(u: Unit) -> bool: return u.unit_type.guid() == 157)
	Orders.units(escort, "move_to", [store.position + Vector2(120, 120)])
	await _until(func() -> bool: return mission.goal == 171, 600.0, "the way clear")
	print("trappers gone at %.0f s" % Sim.time())
	var travois := _own(func(u: Unit) -> bool: return u.unit_type.guid() == 155)[0] as Unit
	Orders.unit(travois, "haul", [store])
	await _until(func() -> bool: return mission.outcome != 0, 900.0, "the guns")
	print("TUTORIAL 3 %s at %.0f s, guns %d" % ["WON" if mission.outcome > 0 else "LOST", Sim.time(), me.resources.guns])
	get_tree().quit()


func _nearest_unit(at: Vector2, filter: Callable) -> Unit:
	return KiWorld.nearest(Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and filter.call(u)), at,
			func(_n: Node) -> bool: return true) as Unit


func _nearest_store(at: Vector2) -> MapObject:
	return KiWorld.nearest(MapObject.abandoned_stores, at, func(_n: Node) -> bool: return true) as MapObject


## Idle women back onto our fields (a harvested field lies fallow until worked again).
func _keep_farming(women: Array) -> void:
	var fields := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == main.me and o.is_field())
	for i in women.size():
		var woman: Unit = women[i]
		if is_instance_valid(woman) and woman.is_alive() and woman.state == Unit.State.IDLE and not fields.is_empty():
			Orders.unit(woman, "gather", [fields[i % fields.size()]])


## A building (or field) of `guid` put up near `around` by `builders`; waits until it stands.
func _build(guid: int, around: Vector2, builders: Array, wait := true) -> MapObject:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var cost: Dictionary = BuildController._cost_of(type)
	await _until(func() -> bool: return (main.players[main.me] as Player).can_afford(cost), 900.0, "the cost of %d" % guid)
	var spot := AiBuilder.find_spot(type, around, 120)
	var had := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == main.me and o.guid == guid).size()
	Orders.place(type.id, spot, false, null, builders)
	var site: Array = [null]
	await _until(func() -> bool:
		for o in MapObject.structures:
			if o.owner_index == main.me and o.guid == guid and o.position == spot:
				site[0] = o
		return site[0] != null and (not wait or site[0].complete), 600.0, "building %d" % guid)
	print("built %d at %.0f s (%d before)" % [guid, Sim.time(), had])
	return site[0]


func _own_building(guid: int) -> MapObject:
	for object in MapObject.structures:
		if object.owner_index == main.me and object.guid == guid and object.is_alive():
			return object
	return null


## --mission=...: save a mission after a minute and load it; the AI modules carry on with
## the same units (their handles still name them) and the script with its timers.
func _scenario_mission_saveload() -> void:
	if not main.loaded_game:
		await _until(func() -> bool: return Sim.time() >= 60.0, 120.0, "a minute")
		print("before: %s" % _ki_snapshot())
		SaveGame.save(main)
		Match.load_data = SaveGame.read()
		get_tree().reload_current_scene()
		return
	await get_tree().physics_frame
	print("after:  %s" % _ki_snapshot())
	await _until(func() -> bool: return Sim.time() >= 120.0, 120.0, "another minute")
	print("later:  %s" % _ki_snapshot())
	get_tree().quit()


## --mission=base/ind_02: the playtesting cheats, each given as an order (Cheats; two by
## their keys), and the overlay's report (MissionDebug).
func _scenario_cheats() -> void:
	var mission := main.mission
	var me := main.players[main.me] as Player
	var debug := main.hud.debug
	await _until(func() -> bool: return Sim.time() >= 5.0, 30.0, "the start")
	var food := int(me.resources.food)
	await _cheat_key(KEY_G)
	var fog := main.fog.enabled
	Orders.cheat("reveal")
	var victim := _own(func(u: Unit) -> bool: return u.unit_type.guid() not in Player.COMMANDERS)[0] as Unit
	Orders.cheat("kill", [], [victim])
	# A trigger waiting on something, that neither wins nor loses the mission.
	var waiting := -1
	for i in mission.data.triggers.size():
		var trigger: MissionData.Trigger = mission.data.triggers[i]
		if mission.is_armed(i) and not trigger.conditions.all(mission.holds) \
				and not trigger.actions.any(func(a: PackedInt32Array) -> bool: return a[0] in [4, 13]):
			waiting = i
			break
	Orders.cheat("fire", [waiting])
	Orders.cheat("speed")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var forced := mission.fired_log.any(func(e: PackedInt32Array) -> bool: return e[1] == waiting and e[2] == 1)
	print("cheats: food +%d, fog %s -> %s, victim dead %s, trigger %d forced %s, speed %.0fx" % [
			int(me.resources.food) - food, fog, main.fog.enabled, not victim.is_alive(), waiting, forced, Engine.time_scale])
	Orders.cheat("speed")
	Orders.cheat("speed")
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("speed back to %.0fx" % Engine.time_scale)
	await _cheat_key(KEY_F9, false)
	var report := debug.report_text()
	var modules := Array(report.split("\n")).filter(func(l: String) -> bool: return l.contains(" modules:"))
	print("overlay open %s, %d lines; fired shows the cheat %s; %s" % [debug.panel.visible, report.split("\n").size(),
			report.contains("(cheat)"), modules[0].strip_edges() if not modules.is_empty() else "no modules"])
	Orders.cheat("win")
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("won by cheat: %s" % (mission.outcome > 0))
	get_tree().quit()  # before the end screen, which would count the mission won


func _cheat_key(key: Key, ctrl_shift := true) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.ctrl_pressed = ctrl_shift
		event.shift_pressed = ctrl_shift
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


## Modules running, handles the modules hold that still name something, the script's goal.
func _ki_snapshot() -> String:
	var modules := 0
	var held := 0
	var alive := 0
	for index in main.ki.players:
		var ki: KiPlayer = main.ki.players[index]
		for task: KiTask in ki.slots:
			if task == null:
				continue
			modules += 1
			for value in task.store.values.values():
				if value >= 1 << KiWorld.OWNER_SHIFT and value < 9 << KiWorld.OWNER_SHIFT:
					held += 1
					alive += int(KiWorld.resolve(value) != null)
	return "modules %d, handles %d alive %d, goal %d, claims %d" % [modules, held, alive, main.mission.goal, KiWorld.claims.size()]


func _own(filter: Callable) -> Array:
	return Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team == main.me and filter.call(u))


func _tepee_done() -> bool:
	for object in MapObject.structures:
		if object.owner_index == main.me and object.guid == 100 and object.complete:
			return true
	return false


func _nearest_tree(from: Vector2) -> MapObject:
	var best: MapObject = null
	for object in MapObject.all_objects:
		if object.is_tree() and object.stock.amount > 0 and (best == null or from.distance_to(object.position) < from.distance_to(best.position)):
			best = object
	return best


## Waits (game time) until `done` holds; gives up after `seconds` with a note.
func _until(done: Callable, seconds: float, what: String) -> void:
	var limit := Sim.time() + seconds
	while not done.call():
		if Sim.time() > limit:
			var people := main.players[main.me] as Player
			print("TIMED OUT waiting for %s at %.0f s: %s, population %d / %d" % [what, Sim.time(), people.resources,
					people.population(), people.population_limit()])
			for o in MapObject.structures:
				if o.owner_index == main.me and o.is_building():
					print("  %s complete %s queue %s" % [o.display_name(), o.complete, o.production.queue])
			get_tree().quit()
			return
		await get_tree().physics_frame
