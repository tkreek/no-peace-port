extends Scenario
## Mexican and outlaw campaign missions pushed along their way (start with --mission=...):
## what the scripts and their AI modules do once the player does his part.


## --mission=base/des_01: the band walks up to the independent boarding houses and the
## distillery in the west; they join, and the goals move on.
func _scenario_des01_takeover() -> void:
	var mission := main.mission
	await _until(func() -> bool: return Sim.time() >= 3.0, 30.0, "the start")
	var houses := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == 1 and o.is_building())
	print("independent buildings: %s" % [houses.map(func(o: MapObject) -> String: return "%s at %s" % [o.display_name(), o.position])])
	var band := _own(func(_u: Unit) -> bool: return true)
	for house: MapObject in houses:
		Orders.units(band, "move_to", [house.position + Vector2(0, 80)])
		await _until(func() -> bool: return house.owner_index == main.me, 600.0, "%s joining" % house.display_name())
		print("%s joined at %.0f s" % [house.display_name(), Sim.time()])
	await _until(func() -> bool: return mission.goal == 762, 120.0, "the next goal")
	print("goal now %d at %.0f s: %s" % [mission.goal, Sim.time(), mission.goal_text().left(60)])
	get_tree().quit()


## --mission=base/mex_01: cows of ours in the west (area 4), where the orange militia comes
## to take them (trigger 7, its kuhklau module); then guns and twelve cows at the northern
## store (area 6): won.
func _scenario_mex01_cows() -> void:
	var mission := main.mission
	await _until(func() -> bool: return not Orders.locked and Sim.time() > 12.0, 60.0, "the start")
	var west := _cows(main.me, 4, mission.area(4).get_center())
	print("4 cows at %s" % mission.area(4).get_center())
	for t in [30.0, 60.0, 120.0, 240.0]:
		await _until(func() -> bool: return Sim.time() > t, 300.0, "a while")
		print("t=%.0f cows: %s; P7 gauchos near: %s; KI p7 modules %d" % [Sim.time(),
				west.map(func(c) -> String: return "%s P%d at (%d,%d)" % ["alive" if c.is_alive() else "dead", c.team, c.position.x, c.position.y] if is_instance_valid(c) else "gone"),
				Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team == 7 and u.unit_type.guid() in [263, 264] \
						and u.position.distance_to(mission.area(4).get_center()) < 1500).map(func(u: Unit) -> String: return "(%d,%d)%s" % [u.position.x, u.position.y, Unit.State.keys()[u.state]]),
				main.ki.players[7].running()])
	if GameData.cmdline_option("stop", "") != "":
		get_tree().quit()
		return
	(main.players[main.me] as Player).add("guns", 10)
	_cows(main.me, 12, mission.area(6).get_center())
	await _until(func() -> bool: return mission.outcome != 0, 120.0, "the end")
	print("MEX 01 %s at %.0f s; cows left in area 6: %d" % ["WON" if mission.outcome > 0 else "LOST", Sim.time(),
			mission.count(main.me, Mission.COW, mission.area(6))])
	get_tree().quit()


## --mission=base/des_02: the barber steals the western settlers' (player 3) stagecoach on
## the road, three times; then the west goes to war with the east (trigger 8).
func _scenario_des02_coaches() -> void:
	var mission := main.mission
	await _until(func() -> bool: return not Orders.locked and Sim.time() > 14.0, 60.0, "the start")
	var barber := _own(func(u: Unit) -> bool: return u.work.can_steal())[0] as Unit
	var watched := [mission.area(7), mission.area(8)]
	for n in 3:
		var coach: Array = [null]
		var start := Sim.time()
		await _until(func() -> bool:
			coach[0] = _first(func(u: Unit) -> bool: return u.team == 3 and u.unit_type.guid() == 456)
			return coach[0] != null and not watched.any(func(r: Rect2) -> bool: return r.grow(700).has_point(coach[0].position)),
				900.0, "coach %d on the road" % n)
		var c: Unit = coach[0]
		print("coach %d of P3 on the road at %s after %.0f s (t=%.0f)" % [n, c.position, Sim.time() - start, Sim.time()])
		barber.position = c.position + Vector2(60, 0)
		barber.health = barber.max_health * 50.0  # outlives the escort
		barber.set_stance(Unit.Stance.PASSIVE)  # steals instead of shooting back
		var tried := Sim.time()
		Orders.unit(barber, "steal", [c])
		await _until(func() -> bool: return c.team == main.me or not c.is_alive() or Sim.time() > tried + 15.0, 120.0, "the theft")
		print("  stolen %s (alive %s) at %.0f s" % [c.team == main.me, c.is_alive(), Sim.time()])
		if c.is_alive() and c.team != main.me:
			c.change_team(main.me)
			print("  (handed over by the test)")
		c.position = mission.area(15).get_center()  # home, out of the escort's reach
		barber.position = mission.area(15).get_center() + Vector2(0, 60)
		barber.stop()
		for i in 4 * 60:
			await get_tree().physics_frame
		print("  flags %s goal %d" % [range(10).filter(func(f: int) -> bool: return mission.flag(f)), mission.goal])
	await _until(func() -> bool: return mission.flag(0), 120.0, "the west at war")
	print("west at war with east: %s; P3 module 439257 running %s" % [Diplomacy.hostile(3, 2),
			main.ki.players[3].slots.any(func(t: KiTask) -> bool: return t != null and t.module.number == 439257)])
	for m in 40:
		for i in 60 * 30 / 4:
			await get_tree().physics_frame
		var army := Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team == 3 and Mission.matches(u.unit_type.guid(), 20))
		var centre := Vector2.ZERO
		var moving := 0
		for u: Unit in army:
			centre += u.position / army.size()
			moving += int(u.state != Unit.State.IDLE)
		print("t=%.0f P3 soldiers %d (busy %d) round %s, in area 7: %d; P2 soldiers %d; HQs P2 %d P3 %d; fired %s" % [Sim.time(), army.size(), moving,
				centre, mission.count(3, 20, mission.area(7)), mission.count(2, 20), mission.count(2, 400), mission.count(3, 400),
				mission.fired_log.map(func(e: PackedInt32Array) -> int: return e[1]).filter(func(t: int) -> bool: return t != 32).slice(-8)])
	get_tree().quit()


## --mission=base/des_03: the band rides north into the duel area; the green band leader
## the script brings shoots the sheriff (des03_duell), flees (trigger 4) and turns up in
## his camp in the north (trigger 5).
func _scenario_des03_duel() -> void:
	var mission := main.mission
	await _until(func() -> bool: return not Orders.locked and Sim.time() > 6.0, 60.0, "the start")
	Orders.units(_own(func(_u: Unit) -> bool: return true), "move_to", [mission.area(2).get_center()])
	await _until(func() -> bool: return _fired(mission, 1), 300.0, "the duel scene")
	print("duel scene at %.0f s" % Sim.time())
	var sheriff := _first(func(u: Unit) -> bool: return u.team == 8 and u.unit_type.guid() == 462)
	var leader := _first(func(u: Unit) -> bool: return u.team == 3 and u.unit_type.guid() == 350)
	print("sheriff %s at %s hp %.0f, band leader %s at %s hp %.0f" % [sheriff != null, sheriff.position if sheriff else Vector2.ZERO,
			sheriff.health if sheriff else 0.0, leader != null, leader.position if leader else Vector2.ZERO, leader.health if leader else 0.0])
	while not (_fired(mission, 5) or (leader != null and not leader.is_alive())) and Sim.time() < 300.0:
		for i in 5 * 30 / 4:
			await get_tree().physics_frame
		if sheriff.is_alive():
			print("  t=%.0f sheriff hp %.0f %s at %s; leader hp %.0f %s at %s target %s dist %.0f range %.0f" % [Sim.time(), sheriff.health,
					Unit.State.keys()[sheriff.state], sheriff.position, leader.health, Unit.State.keys()[leader.state], leader.position,
					leader.target, leader.position.distance_to(sheriff.position), leader.attack_range()])
	print("at %.0f s: sheriff alive %s, leader alive %s at %s; fired %s" % [Sim.time(), sheriff != null and sheriff.is_alive(),
			leader != null and leader.is_alive(), leader.position if leader else Vector2.ZERO,
			mission.fired_log.map(func(e: PackedInt32Array) -> int: return e[1])])
	get_tree().quit()


## Any mission, idle: every --every=<s> game seconds (60) the units of the peoples in
## --track=<p,q,...> (their kind, place, state), until --until=<s> (1200).
func _scenario_track() -> void:
	var peoples := Array(GameData.cmdline_option("track", "").split(",")).map(func(s: String) -> int: return s.to_int())
	var every := GameData.cmdline_option("every", "60").to_float()
	var until := GameData.cmdline_option("until", "1200").to_float()
	var next := 0.0
	while Sim.time() < until:
		if Sim.time() >= next:
			next += every
			for p in peoples:
				var units := Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team == p)
				var groups := {}
				for u: Unit in units:
					var key := "%s %s" % [u.display_name(), Unit.State.keys()[u.state]]
					groups.get_or_add(key, []).append("(%d,%d)" % [u.position.x, u.position.y])
				print("t=%.0f P%d %d units: %s" % [Sim.time(), p, units.size(), "; ".join(groups.keys().map(
						func(k: String) -> String: return "%s x%d %s" % [k, groups[k].size(), " ".join(groups[k].slice(0, 6))]))])
		await get_tree().physics_frame
	get_tree().quit()


func _fired(mission: Mission, index: int) -> bool:
	return mission.fired_log.any(func(e: PackedInt32Array) -> bool: return e[1] == index)


func _first(filter: Callable) -> Unit:
	for u in Unit.all_units:
		if u.is_alive() and filter.call(u):
			return u
	return null


## `amount` cows of people `owner` round `at`.
func _cows(owner: int, amount: int, at: Vector2) -> Array:
	var before := Unit.all_units.duplicate()
	main.mission.spawn(1, amount, Mission.COW, at)  # nobody's, then ours
	var out := Unit.all_units.filter(func(u: Unit) -> bool: return u not in before)
	for cow: Unit in out:
		cow.change_team(owner)
	return out


func _own(filter: Callable) -> Array:
	return Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team == main.me and filter.call(u))


## Waits (game time) until `done` holds; gives up after `seconds` with a note.
func _until(done: Callable, seconds: float, what: String) -> void:
	var limit := Sim.time() + seconds
	while not done.call():
		if Sim.time() > limit:
			print("TIMED OUT waiting for %s at %.0f s" % [what, Sim.time()])
			get_tree().quit()
			return
		await get_tree().physics_frame
