extends Scenario
## Mission testing aids (start them with --mission=...): what the computer players' units
## do over time, for checking that the KI modules move them as their code says.


## --scenario=track_units: every 20 game seconds a line per living unit of every people: "TRACK t sim_id team guid x y state patrol-end attack-moving quartered".
## --track-every=<s> changes the interval; --track-team=<n> lists one people only.
func _scenario_track_units() -> void:
	var every := GameData.cmdline_option("track-every", "20").to_float()
	var only := GameData.cmdline_option("track-team", "0").to_int()
	var next := 0.0
	while true:
		if Sim.time() >= next:
			next += every
			for unit: Unit in Unit.all_units:
				if not unit.is_alive() or unit.team <= 0 or (only > 0 and unit.team != only):
					continue
				var p := unit._patrol
				print("TRACK %d %d %d %d %d %d %d %s %d %d" % [int(Sim.time()), unit.sim_id, unit.team,
						unit.unit_type.guid(), int(unit.position.x), int(unit.position.y), unit.state,
						"%d,%d" % [int(p[1].x), int(p[1].y)] if p.size() == 2 else "-",
						int(unit.attack_moving), int(unit.quarters != null)])
		await get_tree().physics_frame


## --scenario=steps --steps="T:what:args;...": at game second T (in order) does one thing,
## through cheats and orders as a player would, and prints what it did:
##   kill:P:G[:x0:y0:x1:y1]   people P's objects of GUID/category G (within the rectangle)
##   fire:N                   trigger N fires whatever its conditions say
##   move:G:x:y               the local people's units of GUID/category G attack-move there
##   state                    the script's armed triggers, timers, flags, goal, fired log
##   shot:name:x:y            a screenshot of the view at x,y (--shot-dir; not headless)
##   teleport:P:G:n:x:y[:team] n of P's G put down at x,y (and given to `team`): a test
##                            shortcut outside the game step, to reach a mission's next point
##   cast:G:spell:x:y[:n:k]  the local people's G (n of them from the k-th) cast a spell at x,y
##   research:G               the local people has upgrade G (shortcut)
##   order:G                  one of the local people's buildings whose buttons offer G (what
##                            the map allows it: MapRules) queues it, as a click would
##   owned                    the local people's buildings and units by GUID, and what it researched
##   stats:P:G                what people P has G as in this map (MapRules): offered, hit points,
##                            attack, cost, time, and the hit points of P's living G
##   animals, fields:P, relations   horses/cows/buffalo by owner, P's fields, the stances
## With --track-every the units are listed as in track_units.
func _scenario_steps() -> void:
	if GameData.cmdline_option("track-every") != "":
		_scenario_track_units()
	var steps := Array(GameData.cmdline_option("steps").split(";", false))
	for step: String in steps:
		var part := step.split(":")
		var at := part[0].to_float()
		while Sim.time() < at:
			await get_tree().physics_frame
		var mission := main.mission
		match part[1]:
			"kill":
				var p := part[2].to_int()
				var what := part[3].to_int()
				var rect := Rect2()
				if part.size() >= 8:
					rect = Rect2(Vector2(part[4].to_float(), part[5].to_float()), Vector2(part[6].to_float() - part[4].to_float(), part[7].to_float() - part[5].to_float()))
				var victims := []
				for unit in Unit.all_units:
					if unit.is_alive() and unit.team == p and Mission.unit_matches(unit, what) and (not rect.has_area() or rect.has_point(unit.position)):
						victims.append(unit)
				for object in MapObject.structures:
					if object.owner_index == p and object.is_building() and object.is_alive() and Mission.matches(object.guid, what) \
							and (not rect.has_area() or rect.has_point(object.position)):
						victims.append(object)
				Orders.cheat("kill", [], victims)
				print("STEP t=%.1f kill %d of P%d %d" % [Sim.time(), victims.size(), p, what])
			"fire":
				Orders.cheat("fire", [part[2].to_int()])
				print("STEP t=%.1f fire %s" % [Sim.time(), part[2]])
			"move":
				var what := part[2].to_int()
				var group := _own(func(u: Unit) -> bool: return Mission.unit_matches(u, what))
				Orders.units(group, "attack_move", [Vector2(part[3].to_float(), part[4].to_float())])
				print("STEP t=%.1f move %d units" % [Sim.time(), group.size()])
			"state":
				var armed := []
				for i in mission.data.triggers.size():
					if mission.is_armed(i):
						armed.append(i)
				var timers := {}
				for i in Mission.TIMERS:
					if mission.timer_ms(i) >= 0:
						timers[i] = mission.timer_ms(i)
				var flags := []
				for i in Mission.FLAGS:
					if mission.flag(i):
						flags.append(i)
				print("STEP t=%.1f state armed %s timers %s flags %s goal %d outcome %d countdown %s %d" % [Sim.time(), armed, timers,
						flags, mission.goal, mission.outcome, mission.countdown_running, mission.countdown])
				for index in main.ki.players:
					var ki: KiPlayer = main.ki.players[index]
					var running := []
					for task: KiTask in ki.slots:
						if task:
							running.append("%s@%d" % [task.module.source, task.pc])
					print("  KI P%d: %s" % [index, ", ".join(running)])
			"teleport":  # teleport:P:G:n:x:y[:team]: n of P's G put down around x,y (a test shortcut, not a game step)
				var p := part[2].to_int()
				var what := part[3].to_int()
				var n := part[4].to_int()
				var spot := Vector2(part[5].to_float(), part[6].to_float())
				var moved := 0
				for unit in Unit.all_units:
					if moved < n and unit.is_alive() and unit.team == p and Mission.unit_matches(unit, what):
						var cell := main.nav.nearest_walkable(main.nav.cell_of(spot + Vector2((moved % 5) * 24, (moved / 5) * 24)), 8)
						unit.stop()
						unit.position = main.nav.center_of(cell)
						if part.size() > 7:
							unit.change_team(part[7].to_int())
							if unit.animal.is_horse():
								unit.animal.wild_timer = UnitAnimal.OWNED_HORSE_SECONDS
						moved += 1
				print("STEP t=%.1f teleport %d of P%d %d" % [Sim.time(), moved, p, what])
			"cast":  # cast:G:spell:x:y[:n:k]: the local people's units of G (n from the k-th) cast the spell at x,y
				var what := part[2].to_int()
				var group := _own(func(u: Unit) -> bool: return Mission.unit_matches(u, what))
				if part.size() > 6:  # only n of them (from the k-th)
					var from := part[7].to_int() if part.size() > 7 else 0
					group = group.slice(from, from + part[6].to_int())
				Orders.units(group, "cast", [part[3].to_int(), Vector2(part[4].to_float(), part[5].to_float())])
				print("STEP t=%.1f cast %s by %d units" % [Sim.time(), part[3], group.size()])
			"fields":  # fields:P: people P's fields, where and in which state (0 fallow, 1 growing, 2 ripe)
				var list := []
				for object in MapObject.structures:
					if object.owner_index == part[2].to_int() and object.is_field():
						list.append("%d,%d:%d" % [int(object.position.x), int(object.position.y), object.stock.field_state])
				print("STEP t=%.1f fields of P%s: %s; counted %d" % [Sim.time(), part[2], " ".join(list), Mission.count(part[2].to_int(), MapObject.FIELD_GUID)])
			"research":  # research:G: the local people has upgrade G (a test shortcut)
				var people: Player = main.players[main.me]
				people.researched[part[2].to_int()] = true
				print("STEP t=%.1f research %s" % [Sim.time(), part[2]])
			"order":  # order:G: a building of ours with a button for G queues it
				var wanted := part[2].to_int()
				var offerer: MapObject = null
				for object in MapObject.structures:
					if object.owner_index == main.me and object.is_building() and object.is_alive() and object.complete \
							and MapRules.allows(main.me, wanted) and (wanted in object.production.trainable_units() \
							or wanted in object.production.researchable_upgrades()):
						offerer = object
						break
				var can := offerer != null and offerer.production.can_enqueue(wanted)
				if can:
					Orders.building(offerer, "enqueue", [wanted])
				print("STEP t=%.1f order %d: offered %s, queued %s" % [Sim.time(), wanted, offerer != null, can])
			"stats":  # stats:P:G: what people P's G is here, and P's living ones
				var p := part[2].to_int()
				var what := part[3].to_int()
				var st := MapRules.stats(p, what)
				var lives := []
				for unit in Unit.all_units:
					if unit.is_alive() and unit.team == p and unit.unit_type.guid() == what:
						lives.append("%.0f/%.0f" % [unit.health, unit.max_health])
				for object in MapObject.structures:
					if object.is_alive() and object.owner_index == p and object.guid == what:
						lives.append("%.0f/%.0f" % [object.health, object.max_health])
				print("STEP t=%.1f stats P%d %d: offered %s, health %s, damage %s, cost %s, time %s, housing %s; living %s" % [Sim.time(), p, what,
						MapRules.allows(p, what), st.get("health"), st.get("damage"), st.get("cost"), st.get("build_time"), st.get("housing"), lives])
			"owned":
				var counts := {}
				for object in MapObject.structures:
					if object.owner_index == main.me and object.is_alive():
						counts[object.guid] = counts.get(object.guid, 0) + 1
				for unit in Unit.all_units:
					if unit.team == main.me and unit.is_alive():
						counts[unit.unit_type.guid()] = counts.get(unit.unit_type.guid(), 0) + 1
				var keys := counts.keys()
				keys.sort()
				var people: Player = main.players[main.me]
				var done := people.researched.keys()
				done.sort()
				print("STEP t=%.1f owned %s; researched %s; stock %s" % [Sim.time(), ", ".join(keys.map(func(g: int) -> String: return "%d x%d" % [g, counts[g]])),
						done, people.resources])
			"relations":
				for p in mission.data.players:
					var row := []
					for q in mission.data.players:
						var r := Diplomacy.relation(p.index, q.index)
						row.append("%d:%s" % [q.index, "A" if r & Diplomacy.ALLY else ("N" if r & Diplomacy.NEUTRAL else ("W" if r & Diplomacy.ENEMY else "?"))])
					print("STEP t=%.1f relations P%d %s" % [Sim.time(), p.index, " ".join(row)])
			"animals":
				var seen := {}
				for unit in Unit.all_units:
					if unit.is_alive() and (unit.animal.is_horse() or unit.animal.is_cow() or unit.unit_type.guid() == Mission.BUFFALO):
						var key := "P%d %d" % [unit.team, unit.unit_type.guid()]
						if not seen.has(key):
							seen[key] = []
						seen[key].append("%d,%d" % [int(unit.position.x), int(unit.position.y)])
				for key in seen:
					print("STEP t=%.1f animals %s: %d at %s" % [Sim.time(), key, seen[key].size(), " ".join(seen[key].slice(0, 20))])
			"shot":
				if DisplayServer.get_name() == "headless":
					continue
				main.camera.position = Vector2(part[3].to_float(), part[4].to_float())
				for i in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var file := "%s/%s.png" % [GameData.cmdline_option("shot-dir", "/tmp"), part[2]]
				get_viewport().get_texture().get_image().save_png(file)
				print("STEP t=%.1f shot %s" % [Sim.time(), file])
	print("STEPS done at %.1f" % Sim.time())


func _own(filter: Callable) -> Array:
	return Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.team == main.me and filter.call(u))
