extends "res://scripts/dev/scenarios/campaign_scenarios.gd"
## Campaign missions pushed along their way to the win, to see their later triggers and the
## AI modules they start at work (start them with --mission=... and --mission-stats=...,
## which counts the triggers fired). Prints what happens every 30 s of game time.


## --mission=base/usa_01: the whole wagon train treks west to the marked area (the ambushes
## on the way start), the headquarters goes up there, then the Mexicans come; they are
## killed by cheat when they have arrived, and the mission is won.
func _scenario_usa01_trek() -> void:
	var mission := main.mission
	guard = 400.0
	_watch(30.0)
	await _opening(60.0)
	var dest := mission.area(0).get_center()
	_go(_own(_any), 0)
	await _until(func() -> bool: return mission.flag(2) or mission.outcome != 0, 1500.0, "the wagon train in area 0")
	print("arrived at %.0f s: %s; outcome %d" % [Sim.time(), _kinds(_own(_any)), mission.outcome])
	if mission.outcome != 0:
		_end()
		return
	var builders := _own(func(u: Unit) -> bool: return u.unit_type.anim_index("build") >= 0)
	var type := ObjectTypes.get_type(GameData.type_for_guid(400, main.terrain.biome))
	var spot := _player_spot(type, mission.area(0))
	print("headquarters at %s (area %s), %d builders" % [spot, mission.area(0), builders.size()])
	Orders.place(type.id, spot, false, null, builders)
	await _until(func() -> bool: return mission.timer_ms(3) > 0 or mission.outcome != 0, 600.0, "the headquarters goal")
	print("headquarters started, goal %d at %.0f s" % [mission.goal, Sim.time()])
	Orders.cheat("fire", [11])  # the seven minutes of building up skipped
	await _until(func() -> bool: return mission.flag(0) or mission.outcome != 0, 1200.0, "the Mexicans")
	print("Mexicans spawned at %.0f s: %d units of player 8" % [Sim.time(), _of(8).size()])
	guard = 0.0  # the settlement defends itself from here
	var mex: Array = []
	var t0 := Sim.time()
	while Sim.time() < t0 + 420.0 and mission.outcome == 0:
		await _pause(15.0)
		mex = _of(8)
		var dist := mex.map(func(u: Unit) -> int: return int(u.position.distance_to(dest)))
		dist.sort()
		print("t=%.0f countdown %d: player 8 has %d units, nearest %s px; P8 modules %s; mine %s" % [Sim.time(), mission.countdown,
				mex.size(), dist.slice(0, 5), _modules(8), _kinds(_own(_any))])
		if mex.is_empty() or Sim.time() > t0 + 360.0:
			break
	Orders.cheat("kill", [], mex)
	await _until(func() -> bool: return mission.outcome != 0, 120.0, "the end")
	_end()


## --mission=expansion/usa_01: to the negotiations (the ambush springs), back to the
## stop line (the chase ends), into the town; then to the pioneers' siege ring, the
## besiegers killed by cheat, and the three tribes' camps by cheat: won.
func _scenario_xusa01() -> void:
	var mission := main.mission
	_watch(30.0)
	await _opening(60.0)
	_go(_own(_any), 1)
	await _until(func() -> bool: return _fired(13) or mission.outcome != 0, 400.0, "the ambush")
	print("ambush at %.0f s: player 4 has %d units; %s" % [Sim.time(), _of(4).size(), _modules(4)])
	_go(_own(_any), 18)
	await _until(func() -> bool: return _fired(14) or mission.outcome != 0, 400.0, "the escape")
	var chasers := _of(4).filter(func(u: Unit) -> bool: return u.position.distance_to(mission.area(18).get_center()) < 1500)
	print("escaped at %.0f s: %d of player 4 within 1500 px; %s" % [Sim.time(), chasers.size(), _kinds(_own(_any))])
	await _until(func() -> bool: return _fired(21) or mission.outcome != 0, 60.0, "the town shown")
	_go(_own(_any), 4)
	await _until(func() -> bool: return _fired(22) or mission.outcome != 0, 400.0, "the town")
	print("in town at %.0f s: %s; joined buildings %d" % [Sim.time(), _kinds(_own(_any)),
			MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == main.me and o.is_building()).size()])
	# The three tribes' attacks on the town (addon_usa01_angriff waits 30 s, then its
	# angriffmittel_* modules 7 to 14 minutes before the first wave).
	await _track(4, 500.0, [245229, 910224, 1094435, 999048, 654579, 1093685], 60.0)
	await _track(3, 400.0, [245229, 902637, 1094435, 999048, 654579, 1093685], 60.0)
	print("t=%.0f before the siege: %s; player 1 %s" % [Sim.time(), _kinds(_own(_any)), _kinds(_of(1))])
	guard = 400.0
	_go(_own(_any), 6)
	await _until(func() -> bool: return _fired(24) or mission.outcome != 0, 600.0, "the siege ring")
	var ring := mission.area(6)
	var besiegers := _of(3).filter(func(u: Unit) -> bool: return ring.has_point(u.position))
	var tepees := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == 3 and o.guid == 103 and ring.has_point(o.position))
	print("siege ring at %.0f s: %d besiegers, %d training tepees" % [Sim.time(), besiegers.size(), tepees.size()])
	Orders.cheat("kill", [], besiegers + tepees)
	await _until(func() -> bool: return _fired(25) or _fired(26) or mission.outcome != 0, 120.0, "the pioneers")
	await _until(func() -> bool: return Sim.time() > 1500.0 or mission.outcome != 0, 900.0, "a while more")
	var camps := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index in [3, 4, 7] and o.guid == 100)
	Orders.cheat("kill", [], camps + _of(4).filter(func(u: Unit) -> bool: return u.unit_type.guid() == 152)
			+ _of(7).filter(func(u: Unit) -> bool: return u.unit_type.guid() == 153)
			+ _of(3).filter(func(u: Unit) -> bool: return u.unit_type.guid() == 153))
	await _until(func() -> bool: return mission.outcome != 0, 120.0, "the end")
	_end()


# ------------------------------------------------------------------ helpers

## When above 0, _watch kills hostile units within this many px of ours (the player
## fighting back, so a push gets through).
var guard := 0.0


func _end() -> void:
	print("MISSION %s at %.0f s; fired %s" % [{1: "WON", -1: "LOST", 0: "NOT OVER"}[main.mission.outcome], Sim.time(), _fired_list()])
	if MissionStats.on:
		MissionStats.write(main)
	get_tree().quit()


## Waits for the opening scene to hand over the controls (the script locks them in its
## first steps, so a moment passes first).
func _opening(seconds: float) -> void:
	await _pause(1.0)
	await _until(func() -> bool: return not Orders.locked, seconds, "the opening scene")


func _any(_u: Unit) -> bool:
	return true


## `units` walk to the centre of area `id`.
func _go(units: Array, id: int) -> void:
	var at := main.mission.area(id).get_center()
	print("t=%.0f %d units to area %d %s" % [Sim.time(), units.size(), id, Vector2i(at)])
	Orders.units(units, "move_to", [at])


func _fired(index: int) -> bool:
	return MissionStats._fired.size() > index and MissionStats._fired[index] > 0


func _fired_list() -> Array:
	var out := []
	for i in MissionStats._fired.size():
		if MissionStats._fired[i] > 0:
			out.append(i)
	return out


## Every `seconds` of game time: the human's units by kind and where they are, the
## computer players' units near them, the triggers fired since.
func _watch(seconds: float) -> void:
	var state := {"next": Sim.time() + seconds, "fired": [], "guard": 0.0, "killed": {}}
	while is_inside_tree():
		await get_tree().physics_frame
		if guard > 0.0 and Sim.time() >= state.guard:  # the player defending: attackers near ours killed by cheat
			state.guard = Sim.time() + 2.0
			var mine := _own(_any)
			var attackers := Unit.all_units.filter(func(u: Unit) -> bool:
				return u.is_alive() and Diplomacy.hostile(main.me, u.team) and not u.animal.is_cow() \
						and mine.any(func(m: Unit) -> bool: return m.position.distance_to(u.position) < guard))
			for u: Unit in attackers:
				state.killed[u.team] = state.killed.get(u.team, 0) + 1
			if not attackers.is_empty():
				Orders.cheat("kill", [], attackers)
		if Sim.time() < state.next:
			continue
		state.next = Sim.time() + seconds
		var mine := _own(_any)
		var centre := Vector2.ZERO
		for u: Unit in mine:
			centre += u.position / mine.size()
		var fired := _fired_list()
		var new := fired.filter(func(i: int) -> bool: return i not in state.fired)
		state.fired = fired
		var enemies := {}
		for u: Unit in Unit.all_units:
			if u.is_alive() and u.team > 0 and u.team != main.me and u.position.distance_to(centre) < 1200:
				enemies[u.team] = enemies.get(u.team, 0) + 1
		print("t=%.0f me %d at %s %s; near: %s; new triggers %s; KI modules %d; goal %d%s" % [Sim.time(), mine.size(),
				Vector2i(centre), _kinds(mine), enemies, new, main.ki.running(), main.mission.goal,
				"; guard killed %s" % state.killed if not state.killed.is_empty() else ""])
		state.killed = {}


func _of(player: int) -> Array:
	return Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team == player)


func _kinds(units: Array) -> Dictionary:
	var out := {}
	for u: Unit in units:
		var name := u.display_name()
		out[name] = out.get(name, 0) + 1
	return out


## The modules player `people` runs, by number.
func _modules(people: int) -> Dictionary:
	var out := {}
	var ki: KiPlayer = main.ki.players.get(people)
	if ki:
		for task: KiTask in ki.slots:
			if task:
				out[task.module.number] = out.get(task.module.number, 0) + 1
	return out


## --mission=base/usa_03: everybody aboard the riverboats and across to the landing place,
## on to Malibrán (the goal changes), its command post attacked (killed by cheat if it
## still stands after two minutes): the counter-attacks start. Later the orange command
## post by cheat (the green attacks start), then the forts: won.
func _scenario_usa03() -> void:
	var mission := main.mission
	_watch(30.0)
	await _opening(60.0)
	await _ferry(_own(_any), mission.area(3).get_center())
	_go(_own(_any), 0)
	await _until(func() -> bool: return _fired(4) or mission.outcome != 0, 400.0, "Malibrán")
	await _until(func() -> bool: return not Orders.locked, 60.0, "the scene")
	var post := _buildings_of(8, 200)
	print("Malibrán at %.0f s: player 8 command posts %d" % [Sim.time(), post.size()])
	if not post.is_empty():
		Orders.units(_own(_any), "attack_move", [post[0].position])
	await _until(func() -> bool: return _buildings_of(8, 200).is_empty() or mission.outcome != 0, 120.0, "the command post")
	Orders.cheat("kill", [], _buildings_of(8, 200))
	await _until(func() -> bool: return _fired(7), 60.0, "the forts goal")
	print("forts goal at %.0f s: %s; player 7 %s" % [Sim.time(), _kinds(_own(_any)), _modules(7)])
	await _track(7, 600.0, [256941, 41821, 157307], GameData.cmdline_option("track-every", "30").to_float())
	Orders.cheat("kill", [], _buildings_of(7, 200))
	await _until(func() -> bool: return _fired(12), 60.0, "green's attacks")
	print("green attacks at %.0f s: player 3 %s" % [Sim.time(), _modules(3)])
	await _track(3, 420.0, [159684, 41821, 157307])
	Orders.cheat("kill", [], _buildings_of(3, 217) + _buildings_of(4, 217))
	await _until(func() -> bool: return mission.outcome != 0, 120.0, "the end")
	_end()


func _buildings_of(player: int, guid: int) -> Array:
	return MapObject.structures.filter(func(o: MapObject) -> bool:
		return o.owner_index == player and o.guid == guid and o.is_alive())


## `units` (the boats among them) aboard the boats and put ashore at `landing`, boat
## load by boat load.
func _ferry(units: Array, landing: Vector2) -> void:
	var boats := units.filter(func(u: Unit) -> bool: return u.water.is_boat())
	var walkers := units.filter(func(u: Unit) -> bool: return not u.water.is_boat())
	print("ferry: %d boats, %d to carry, to %s" % [boats.size(), walkers.size(), Vector2i(landing)])
	while not walkers.is_empty() and not boats.is_empty():
		var loads := []
		for boat: Unit in boats:
			walkers.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_to(boat.position) < b.position.distance_to(boat.position))
			var room: int = boat.water.capacity() - boat.water.passengers.size()
			var load := walkers.slice(0, room)
			walkers = walkers.slice(room)
			if not load.is_empty():
				main.selection.order_board(boat, load)  # as the player does: the boat comes to the bank
				loads.append([boat, load])
		await _until(func() -> bool:
			return loads.all(func(l: Array) -> bool: return l[1].all(func(u: Unit) -> bool: return not is_instance_valid(u) or not u.is_alive() or u.inside)), 120.0, "boarding")
		print("t=%.0f aboard: %s" % [Sim.time(), loads.map(func(l: Array) -> int: return l[0].water.passengers.size())])
		for l: Array in loads:
			Orders.unit(l[0], "unload_at", [landing])
		await _until(func() -> bool: return loads.all(func(l: Array) -> bool: return l[0].water.passengers.is_empty()), 400.0, "landing")
		print("t=%.0f landed; %d still to carry" % [Sim.time(), walkers.size()])


## Everything of `player` that counts as `what` (a GUID or a category, as the scripts
## count), in area `area_id` if given, killed by cheat; how many.
func _kill(player: int, what: int, area_id := -1) -> int:
	var rect := main.mission.area(area_id) if area_id >= 0 else Rect2()
	var victims := []
	for u: Unit in Unit.all_units:
		if u.is_alive() and u.team == player and Mission.unit_matches(u, what) and (area_id < 0 or rect.has_point(u.position)):
			victims.append(u)
	for o: MapObject in MapObject.structures:
		if o.owner_index == player and o.is_alive() and (o.is_building() or o.is_field()) and Mission.matches(o.guid, what) \
				and (area_id < 0 or rect.has_point(o.position)):
			victims.append(o)
	Orders.cheat("kill", [], victims)
	print("t=%.0f killed %d of player %d's %d%s" % [Sim.time(), victims.size(), player, what, " in area %d" % area_id if area_id >= 0 else ""])
	return victims.size()


## Waits `seconds` of game time (or the end of the mission).
func _pause(seconds: float) -> void:
	var until := Sim.time() + seconds
	await _until(func() -> bool: return Sim.time() >= until or main.mission.outcome != 0, seconds + 60.0, "time")


## Each step [[player, what, area], ...] killed by cheat `gap` seconds after the last.
func _conquer(steps: Array, gap: float) -> void:
	for step: Array in steps:
		await _pause(gap)
		if main.mission.outcome != 0:
			return
		for k: Array in step:
			_kill(k[0], k[1], k[2] if k.size() > 2 else -1)
		var states := []
		for index in main.ki.players:
			states.append("%d: %d" % [index, main.ki.players[index].running()])
		print("t=%.0f modules per player %s" % [Sim.time(), ", ".join(states)])


## --mission=base/usa_02: five Mexicans killed (the camp notices: the countdown), then all
## their soldiers: won.
func _scenario_usa02() -> void:
	_watch(30.0)
	await _opening(60.0)
	await _pause(240.0)
	Orders.cheat("kill", [], _of(3).slice(0, 5))
	await _until(func() -> bool: return _fired(5), 60.0, "being discovered")
	print("discovered at %.0f s; countdown %d" % [Sim.time(), main.mission.countdown])
	await _conquer([[[3, 18]]], 300.0)
	await _until(func() -> bool: return main.mission.outcome != 0, 120.0, "the end")
	_end()


## --mission=base/usa_04: San Augustin's command post, Valencia's, the bridgehead, then
## the army over the border (the red attacks start), the outposts and Chapultepec: won.
func _scenario_usa04() -> void:
	guard = 400.0
	_watch(30.0)
	await _opening(60.0)
	await _conquer([[[1, 200, 19]], [[6, 200]], [[8, 213, 2], [8, 200, 7]]], 180.0)
	await _until(func() -> bool: return _fired(11) and not Orders.locked, 120.0, "crossing the river")
	_go(_own(_any), 20)
	await _until(func() -> bool: return _fired(27) or main.mission.outcome != 0, 900.0, "the red start")
	print("over the border at %.0f s: player 4 %s" % [Sim.time(), _modules(4)])
	await _conquer([[[3, 203, 8], [3, 203, 9], [3, 203, 10]], [[4, 217, 12]]], 420.0)
	await _until(func() -> bool: return main.mission.outcome != 0, 120.0, "the end")
	_end()


## --mission=base/usa_05: the three chiefs' tepees after five minutes: won.
func _scenario_usa05() -> void:
	_watch(30.0)
	await _opening(60.0)
	# One at a time the tribes rebuild their chief's tepee (a_gebäude_v keeps GUID 100 up), so
	# the three go together.
	await _conquer([[[4, 100], [3, 100], [5, 100]]], 300.0)
	await _until(func() -> bool: return main.mission.outcome != 0, 120.0, "the end")
	_end()


## --mission=base/usa_06: each enemy's main buildings, 150 s apart: won.
func _scenario_usa06() -> void:
	guard = 400.0
	_watch(30.0)
	await _conquer([[[3, 200], [3, 203], [3, 211], [3, 217]], [[4, 100], [4, 103]], [[7, 300], [7, 307], [7, 303]],
			[[8, 200], [8, 211], [8, 203], [8, 217]], [[6, 100], [6, 103]]], 150.0)
	await _until(func() -> bool: return main.mission.outcome != 0, 120.0, "the end")
	_end()


## Units of ours of these GUIDs.
func _own_guids(guids: Array) -> Array:
	return _own(func(u: Unit) -> bool: return u.unit_type.guid() in guids)


## Whether `unit` is within `px` of the centre of area `id`.
func _near_area(unit: Unit, id: int, px: float) -> bool:
	return is_instance_valid(unit) and unit.position.distance_to(main.mission.area(id).get_center()) < px


## --mission=expansion/ind_01: the arrow shooters' pen (its stockade by cheat; they join),
## then everybody to the goal in the south-east: won with the chief and ten arrow shooters.
func _scenario_xind01() -> void:
	guard = 400.0  # the arrow shooters' guards (player 5, at war with the tribe)
	_watch(30.0)
	await _opening(120.0)
	var scout := _own_guids([157])
	print("mounted arrow shooter at %s (the briefing module sends it to 4448,896)" % [scout.map(func(u: Unit) -> Vector2i: return Vector2i(u.position))])
	_go(_own(_any), 28)
	await _pause(60.0)
	# The arrow shooters are penned in by player 5's stockade: it goes (the player would
	# break through), then our units walk up to them and they join.
	_kill(5, 9, 28)
	await _pause(2.0)
	var pen := _of(1).filter(func(u: Unit) -> bool: return main.mission.area(28).has_point(u.position))
	if not pen.is_empty():
		Orders.units(_own(_any), "move_to", [pen[0].position])
	await _pause(30.0)
	# Trigger 17 wants every arrow shooter of player 1 on the map, not just the penned ones:
	# the others are visited in turn.
	for i in 8:
		var left := _of(1).filter(func(u: Unit) -> bool: return u.unit_type.guid() == 156)
		if left.is_empty() or _fired(17):
			break
		var mine := _own(_any)
		left.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_to(mine[0].position) < b.position.distance_to(mine[0].position))
		print("t=%.0f %d arrow shooters of player 1 left; to %s" % [Sim.time(), left.size(), Vector2i(left[0].position)])
		Orders.units(mine, "move_to", [left[0].position])
		var target: Unit = left[0]
		await _until(func() -> bool: return target.team == main.me or not target.is_alive() or main.mission.outcome != 0, 300.0, "an arrow shooter")
	await _until(func() -> bool: return _fired(17) or main.mission.outcome != 0, 60.0, "the arrow shooters' goal")
	print("arrow shooters joined at %.0f s: %s; player 1 left %s" % [Sim.time(), _kinds(_own(_any)), _kinds(_of(1))])
	# The towers on the way out are the player's to deal with: by cheat here.
	for p in [8, 2, 5]:
		_kill(p, 413)
		_kill(p, 417)
	_go(_own(_any), 26)
	await _until(func() -> bool: return main.mission.outcome != 0, 1500.0, "the goal")
	_end()


## --mission=expansion/ind_02: off to the first new camp, then to the outlaws (the
## countdown); the attacks forced on by trigger, the second camp, the last attack: won.
func _scenario_xind02() -> void:
	guard = 400.0
	_watch(30.0)
	await _opening(60.0)
	_go(_own(_any), 6)
	await _until(func() -> bool: return _fired(9) or main.mission.outcome != 0, 600.0, "the first camp")
	print("first camp at %.0f s; P8 %s P7 %s" % [Sim.time(), _modules(8), _modules(7)])
	_go(_own(_any), 26)
	await _until(func() -> bool: return _fired(17) or main.mission.outcome != 0, 600.0, "the outlaws")
	Orders.cheat("fire", [21])  # the countdown's first attack, now
	await _pause(300.0)
	print("t=%.0f after the first attack: P2 %s" % [Sim.time(), _modules(2)])
	_kill(5, 413)  # the ranchers' watchtowers on the way north-east, the player's to deal with
	# The second camp lies behind the ranchers' stockade line, whose two strips (areas 28, 36)
	# note the arrival: the stockade goes (the player breaks through), then on to the camp.
	var line := MapObject.structures.filter(func(o: MapObject) -> bool:
		return o.owner_index == 5 and o.is_building() and (main.mission.area(28).grow(96).has_point(o.position) \
				or main.mission.area(36).grow(96).has_point(o.position)))
	print("t=%.0f the stockade line: %d pieces killed" % [Sim.time(), line.size()])
	Orders.cheat("kill", [], line)
	_go(_own(_any), 38)
	await _until(func() -> bool: return _fired(30) or main.mission.outcome != 0, 900.0, "the second camp")
	print("second camp at %.0f s" % Sim.time())
	Orders.cheat("fire", [33])  # the last attack, now
	await _pause(360.0)
	Orders.cheat("fire", [34])
	await _until(func() -> bool: return main.mission.outcome != 0, 120.0, "the end")
	_end()


## --mission=expansion/mex_01: Los Angeles taken (its headquarters by cheat if the army
## has not managed), a command post put up (the bases shown), Mervine's attacks for ten
## minutes, then his weapons factories and training camps by cheat: won.
func _scenario_xmex01() -> void:
	_watch(30.0)
	await _opening(60.0)
	var hq := _buildings_of(8, 400)
	if not hq.is_empty():
		Orders.units(_own(_any), "attack_move", [hq[0].position])
	await _until(func() -> bool: return _fired(14) or main.mission.outcome != 0, 300.0, "Los Angeles")
	_kill(8, 400)
	await _until(func() -> bool: return _fired(14), 30.0, "Los Angeles")
	Orders.cheat("resources")
	await _pause(2.0)
	var builders := _own(func(u: Unit) -> bool: return u.unit_type.anim_index("build") >= 0)
	await _build(200, main.mission.area(1).get_center(), builders)
	await _until(func() -> bool: return _fired(10) or main.mission.outcome != 0, 120.0, "the bases shown")
	print("bases shown at %.0f s: P2 %s" % [Sim.time(), _modules(2)])
	await _pause(600.0)
	await _conquer([[[2, 411], [2, 403]]], 1.0)
	await _until(func() -> bool: return main.mission.outcome != 0, 120.0, "the end")
	_end()


## --mission=expansion/mex_02: the royal army's attack (finished by cheat after four
## minutes), twenty cows put in the box, Kearny's base by cheat; Kearny flees: where does
## he get to; then he is killed: won.
func _scenario_xmex02() -> void:
	_watch(30.0)
	await _pause(240.0)
	_kill(6, 0)
	await _until(func() -> bool: return _fired(11) or main.mission.outcome != 0, 120.0, "the computer players starting")
	await _pause(300.0)
	_kill(5, Mission.COW)
	main.mission.spawn(main.me, 20, Mission.COW, main.mission.area(0).get_center())  # nobody's cows: made ours
	for u: Unit in Unit.all_units:
		if u.is_alive() and u.team == 0 and u.animal.is_cow() and main.mission.area(0).grow(64).has_point(u.position):
			u.change_team(main.me)
	print("cows in the box: %d" % Mission.count(main.me, Mission.COW, main.mission.area(0)))
	await _until(func() -> bool: return _fired(12) or main.mission.outcome != 0, 60.0, "the cows")
	await _conquer([[[2, 400], [2, 403], [2, 407], [2, 411], [2, 427], [2, 415]]], 60.0)
	await _until(func() -> bool: return _fired(14) or main.mission.outcome != 0, 60.0, "Kearny's escape")
	var t0 := Sim.time()
	while Sim.time() < t0 + 600.0 and main.mission.outcome == 0:
		await _pause(30.0)
		var kearny := _of(2).filter(func(u: Unit) -> bool: return u.unit_type.guid() == 293)
		print("t=%.0f Kearny %s, %d px from area 1; P2 %s" % [Sim.time(), kearny.map(func(u: Unit) -> Vector2i: return Vector2i(u.position)),
				kearny[0].position.distance_to(main.mission.area(1).get_center()) if not kearny.is_empty() else -1, _modules(2)])
		if kearny.is_empty() or _near_area(kearny[0], 1, 1200.0):
			break
	_kill(2, 293)
	await _until(func() -> bool: return main.mission.outcome != 0, 120.0, "the end")
	_end()


## --mission=expansion/des_01: Jack Johnson to his old friends (the intro module walks him
## to the first), the harbour (war with the settlers), the boats taken, across to the
## outlaw village, the Natives' visit, the jails by cheat, the stock by cheat: won.
func _scenario_xdes01() -> void:
	_watch(30.0)
	await _until(func() -> bool: return _fired(10) or main.mission.outcome != 0, 120.0, "the first old friend")
	print("first friend at %.0f s (fired 5: %s)" % [Sim.time(), _fired(5)])
	for id in [2, 3, 4, 5, 6]:
		_go(_own(_any), id)
		await _until(func() -> bool: return _fired(id + 9) or main.mission.outcome != 0, 600.0, "friend in area %d" % id)
	_go(_own(_any), 8)
	await _until(func() -> bool: return _fired(20) or main.mission.outcome != 0, 600.0, "the harbour")
	_go(_own(_any), 10)
	await _until(func() -> bool: return _fired(23) or main.mission.outcome != 0, 300.0, "the boats")
	print("boats at %.0f s: %s; P2 %s" % [Sim.time(), _kinds(_own(_any)), _modules(2)])
	await _ferry(_own(_any), main.mission.area(13).get_center())
	_go(_own(_any), 13)
	await _until(func() -> bool: return _fired(26) or main.mission.outcome != 0, 600.0, "the outlaw village")
	await _until(func() -> bool: return _fired(32) or main.mission.outcome != 0, 600.0, "the Natives' visit")
	print("war at %.0f s: P4 %s, P2 %s, P3 %s" % [Sim.time(), _modules(4), _modules(2), _modules(3)])
	await _pause(300.0)
	await _conquer([[[3, 407, 15], [3, 407, 16], [3, 407, 17]]], 1.0)
	Orders.cheat("resources")
	Orders.cheat("resources")
	await _until(func() -> bool: return main.mission.outcome != 0, 120.0, "the end")
	_end()


## --mission=expansion/des_02: the women kidnapped (their module walks them to the jail),
## the Natives' counter-attack, then the old bandits into the five banks: won.
func _scenario_xdes02() -> void:
	_watch(30.0)
	await _until(func() -> bool: return _fired(8) or main.mission.outcome != 0, 120.0, "the opening")
	_go(_own(_any), 5)
	await _until(func() -> bool: return _fired(12) or main.mission.outcome != 0, 900.0, "the women")
	print("women taken at %.0f s: P4 %s" % [Sim.time(), _modules(4)])
	_go(_own(_any), 16)
	await _until(func() -> bool: return _fired(13) or main.mission.outcome != 0, 600.0, "the women in jail")
	var women := _of(4)
	print("t=%.0f P4 women %s, in jail %d; P3 %s" % [Sim.time(), women.map(func(u: Unit) -> Vector2i: return Vector2i(u.position)),
			Mission.count(4, 153, main.mission.area(0)), _modules(3)])
	await _pause(420.0)
	var bandits := _own_guids([282, 283])
	for i in bandits.size():
		Orders.unit(bandits[i], "move_to", [main.mission.area(11 + i % 5).get_center()])
	await _until(func() -> bool: return main.mission.outcome != 0, 1200.0, "the banks")
	_end()


## A spot inside `rect` where the player may put `type` (the player's rule, not the AI's).
func _player_spot(type: ObjectTypes.ObjectType, rect: Rect2) -> Vector2:
	var centre := rect.get_center()
	for r in range(0, 400, 16):
		for k in 16:
			var at := (centre + Vector2(r, 0).rotated(k * TAU / 16.0)).snapped(Vector2(16, 16))
			if rect.has_point(at) and BuildController.can_place_for(type, at, main.me):
				return at
	return centre


## Waits (game time) until `done` holds; after `seconds` it notes the time-out and goes on
## (the pushes carry on by cheat where the game has not got there by itself).
func _until(done: Callable, seconds: float, what: String) -> void:
	var limit := Sim.time() + seconds
	while not done.call():
		if Sim.time() > limit:
			print("t=%.0f TIMED OUT waiting for %s" % [Sim.time(), what])
			return
		await get_tree().physics_frame


## For `seconds` of game time, every `every` s: how many units of `player` are within 1500 px
## of ours (and the nearest), its modules among `watch` and its unit count.
func _track(player: int, seconds: float, watch: Array, every := 30.0) -> void:
	var t0 := Sim.time()
	while main.mission.outcome == 0:  # at least once
		await _pause(every)
		var mine := _own(_any)
		var theirs := _of(player)
		var near := 0
		var nearest := 1e9
		for u: Unit in theirs:
			var d := 1e9
			for m: Unit in mine:
				d = minf(d, u.position.distance_to(m.position))
			nearest = minf(nearest, d)
			if d < 1500.0:
				near += 1
		var mods := _modules(player)
		var shown := {}
		for k in watch:
			shown[k] = mods.get(k, 0)
		print("t=%.0f player %d: %d units, %d within 1500 px of ours (nearest %d); modules %s; mine %d" % [Sim.time(), player,
				theirs.size(), near, int(nearest), shown, mine.size()])
		for dump in GameData.cmdline_option("dump-module").split(",", false):
			_dump_tasks(player, dump.to_int())
		if GameData.cmdline_option("track-cells") != "":
			var cells := {}
			for u: Unit in theirs:
				var c := Vector2i(u.position / 512.0) * 512
				cells[c] = cells.get(c, 0) + 1
			var mc := {}
			for m: Unit in mine:
				var c := Vector2i(m.position / 512.0) * 512
				mc[c] = mc.get(c, 0) + 1
			print("    theirs by 512 px cell %s; mine %s" % [cells, mc])
		if Sim.time() >= t0 + seconds:
			break


## --dump-module=N: every running task of module N of `player`: where it is, its child
## subroutine, and the units its variables name (position, state, order target).
func _dump_tasks(player: int, number: int) -> void:
	var ki: KiPlayer = main.ki.players.get(player)
	if ki == null:
		return
	for task: KiTask in ki.slots:
		if task == null or task.module.number != number:
			continue
		var line := "    task %d pc %d sleep %d waits %d" % [number, task.pc, task.sleep_ms, task.waits_for]
		var child := task.child
		while child:
			line += " > %d pc %d sleep %d" % [child.module.number, child.pc, child.sleep_ms]
			child = child.child
		print(line)
		for id in task.store.values:
			var v: int = task.store.values[id]
			var node := KiWorld.resolve(v) if v >= 1 << KiWorld.OWNER_SHIFT else null
			if node is Unit:
				var u := node as Unit
				print("      var %x = unit %s of %d at %s state %s path end %s attack-moving %s follows %s" % [id, u.display_name(), u.team,
						Vector2i(u.position), Unit.State.keys()[u.state], Vector2i(u.path[-1]) if not u.path.is_empty() else "-",
						u.attack_moving, u.follow_target != null])
				print("        guard %s stance %s target %s range %d sight %d" % [Vector2i(u.guard_position), Unit.Stance.keys()[u.stance],
						u.target.name if is_instance_valid(u.target) else "-", int(u.attack_range()), int(u.sight())])
			elif v != 0:
				print("      var %x = %d" % [id, v])


## --probe=x1,y1,x2,y2;...: whether ground units can walk from each first point to each
## second (where the path ends), at the start of the mission.
func _scenario_navprobe() -> void:
	await get_tree().physics_frame
	for pair in GameData.cmdline_option("probe").split(";"):
		var n := Array(pair.split(",")).map(func(v: String) -> float: return v.to_float())
		var from := Vector2(n[0], n[1])
		var to := Vector2(n[2], n[3])
		var path := main.nav.find_path(from, to)
		print("probe %s -> %s: %d points, ends at %s (%d px short)" % [Vector2i(from), Vector2i(to), path.size(),
				Vector2i(path[-1]) if not path.is_empty() else "-", int(path[-1].distance_to(to)) if not path.is_empty() else -1])
	get_tree().quit()


## --mission=expansion/usa_01 (a look at the tribes' attacks): straight to the town, then
## both attacking tribes watched for 16 minutes.
func _scenario_xusa01_town() -> void:
	_watch(60.0)
	await _opening(60.0)
	_go(_own(_any), 1)
	await _until(func() -> bool: return _fired(13), 400.0, "the ambush")
	_go(_own(_any), 18)
	await _until(func() -> bool: return _fired(21), 400.0, "the town shown")
	_go(_own(_any), 4)
	var every := GameData.cmdline_option("track-every", "20").to_float()
	for i in 48:
		await _track(4, every, [910224, 1094435, 999048, 654579, 1093685], every)
		await _track(3, 0.0, [902637, 1094435, 999048, 654579, 1093685], 0.0)
	_end()


## --census=id[,id...] [--census-radius=px]: who stands around those areas at the start.
func _scenario_census() -> void:
	await get_tree().physics_frame
	var radius := GameData.cmdline_option("census-radius", "500").to_float()
	for id in GameData.cmdline_option("census").split(","):
		var rect := main.mission.area(id.to_int())
		var at := {}
		for u: Unit in Unit.all_units:
			if u.is_alive() and u.position.distance_to(rect.get_center()) < radius:
				var key := "P%d %s" % [u.team, u.display_name()]
				at[key] = at.get(key, 0) + 1
		for o: MapObject in MapObject.structures:
			if o.is_building() and o.position.distance_to(rect.get_center()) < radius:
				var key := "P%d %s" % [o.owner_index, o.display_name()]
				at[key] = at.get(key, 0) + 1
		print("census area %s %s: %s" % [id, rect, at])
	for p in main.mission.data.players:
		var rel := []
		for q in main.mission.data.players:
			if q.index != p.index:
				rel.append("%d:%s" % [q.index, "ally" if Diplomacy.allied(p.index, q.index) else ("war" if Diplomacy.hostile(p.index, q.index) else "neutral")])
		print("relations of %d: %s" % [p.index, " ".join(rel)])
	get_tree().quit()


## --list-near=id: the map objects within 96 px of area id, at the start.
func _scenario_objects() -> void:
	await get_tree().physics_frame
	var rect := main.mission.area(GameData.cmdline_option("list-near").to_int()).grow(96)
	var seen := {}
	for o: MapObject in MapObject.all_objects:
		if rect.has_point(o.position):
			var key := "P%d %s guid %d building %s structure %s" % [o.owner_index, o.display_name(), o.guid, o.is_building(), o in MapObject.structures]
			seen[key] = seen.get(key, 0) + 1
	for k in seen:
		print("near: %s x%d" % [k, seen[k]])
	get_tree().quit()
