extends Scenario
## Outlaw and American campaign missions played fairly, as a human would (start with
## --mission=...): only orders through Orders (no cheats, no teleports, no forced triggers),
## decisions from what the player can know (own units, explored ground, enemies in sight,
## the goal texts).


## Any mission: what the human has and may make here (costs, values), for planning.
func _scenario_fair_info() -> void:
	await get_tree().physics_frame
	var me := main.players[main.me] as Player
	print("human P%d %s: %s" % [main.me, me.faction, me.resources])
	for guid in [9001, 9002, 9003, 9004, 149]:
		print("  %d: %s" % [guid, MapRules.stats(main.me, guid)])
	for guid in GameData.stats_guids():
		var s := MapRules.stats(main.me, guid)
		if not MapRules.allows(main.me, guid) or s.get("kind") == "upgrade" and s.get("faction") != me.faction:
			continue
		if GameData.cmdline_option("full") == "" or s.get("faction") != me.faction:
			print("  %d %s %s %s: cost %s hp %s dmg %s at %s needs %s" % [guid, s.get("faction"), s.get("kind"), s.get("name"), s.get("cost"),
					s.get("health"), s.get("damage"), s.get("produced_at"), s.get("prerequisites")])
		else:
			print("  %d %s: %s" % [guid, s.get("name"), s])
	get_tree().quit()


## Any mission: each people's values for the units they field (--guids=a,b,...), to compare
## a campaign map's per-player tables.
func _scenario_fair_stats() -> void:
	await get_tree().physics_frame
	var guids := Array(GameData.cmdline_option("guids", "").split(",")).map(func(g: String) -> int: return g.to_int())
	for index in main.players:
		for guid in guids:
			var st := MapRules.stats(index, guid)
			var t := UnitType.for_guid(guid)
			var ut := MapRules.unit_type(t, index) if t else null
			print("P%d %d %s: hp %s dmg %s cost %s; type hp %s dmg %s range %s reload %s speed %s" % [index, guid, st.get("name"),
					st.get("health"), st.get("damage"), st.get("cost"), ut.health if ut else "-", ut.damage if ut else "-",
					ut.attack_range if ut else "-", ut.reload_ms if ut else "-", ut.speed if ut else "-"])
	get_tree().quit()


## Any mission: a picture of the map for planning (--out=<png>, 1 px per 32 map px):
## ground grey, water blue, cliffs dark, trees green, mines yellow, each player's buildings
## (squares) and units (dots) in its colour, the script's areas outlined. Reads everything
## (it is for the tester, not the player).
func _scenario_fair_layout() -> void:
	await get_tree().physics_frame
	var nav: NavGrid = main.nav
	var scale := GameData.cmdline_option("px", "16").to_float()
	var size := Vector2i(ceili(nav.size.x * NavGrid.CELL / scale), ceili(nav.size.y * NavGrid.CELL / scale))
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			var cell := nav.cell_of(Vector2(x, y) * scale + Vector2(scale, scale) / 2)
			var colour := Color(0.55, 0.52, 0.45)
			if nav.is_water(cell):
				colour = Color(0.2, 0.35, 0.7)
			elif not nav.is_walkable(cell):
				colour = Color(0.25, 0.22, 0.2)
			image.set_pixel(x, y, colour)
	for object in MapObject.all_objects:
		var p := Vector2i(object.position / scale)
		if not Rect2i(Vector2i.ZERO, size).has_point(p):
			continue
		if object.is_tree():
			image.set_pixel(p.x, p.y, Color(0.15, 0.45, 0.15))
		elif object.stock.resource == "gold":
			image.fill_rect(Rect2i(p - Vector2i(1, 1), Vector2i(3, 3)), Color(1, 0.9, 0.1))
	var colours := Player.TEAM_COLORS
	for object in MapObject.structures:
		if object.is_building() and object.owner_index > 0:
			var p := Vector2i(object.position / scale)
			image.fill_rect(Rect2i(p - Vector2i(2, 2), Vector2i(4, 4)).intersection(Rect2i(Vector2i.ZERO, size)), colours[object.owner_index % colours.size()])
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team > 0:
			var p := Vector2i(unit.position / scale)
			if Rect2i(Vector2i.ZERO, size).has_point(p):
				image.set_pixel(p.x, p.y, colours[unit.team % colours.size()].lightened(0.3))
	if main.mission:
		for id in main.mission.data.areas:
			var r: Rect2 = main.mission.data.areas[id]
			var a := Vector2i(r.position / scale)
			var b := Vector2i(r.end / scale)
			for x in range(a.x, b.x + 1):
				for y in [a.y, b.y]:
					if Rect2i(Vector2i.ZERO, size).has_point(Vector2i(x, y)):
						image.set_pixel(x, y, Color.WHITE)
			for y in range(a.y, b.y + 1):
				for x in [a.x, b.x]:
					if Rect2i(Vector2i.ZERO, size).has_point(Vector2i(x, y)):
						image.set_pixel(x, y, Color.WHITE)
			print("area %d %s at %s" % [id, main.mission.data.area_names.get(id, ""), r])
	for index in main.players:
		var kinds := {}
		var centre := Vector2.ZERO
		var n := 0
		for object in MapObject.structures:
			if object.is_building() and object.owner_index == index:
				centre += object.position
				n += 1
				if object.guid in MapObject.MAIN_BUILDINGS:
					kinds["main"] = object.position
		print("P%d %s colour %s: %d buildings round %s, main %s" % [index, main.players[index].faction,
				colours[index % colours.size()], n, centre / maxi(n, 1), kinds.get("main", "-")])
	var start := Vector2.ZERO
	var own := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == main.me)
	for u: Unit in own:
		start += u.position / own.size()
	for index in main.players:
		for object in MapObject.structures:
			if object.owner_index == index and object.guid in MapObject.MAIN_BUILDINGS:
				var path := nav.find_path(start, object.position)
				var length := 0.0
				for i in range(1, path.size()):
					length += path[i - 1].distance_to(path[i])
				print("by land from %s to P%d's main: %s" % [start, index, "%.0f px" % length if not path.is_empty() and path[-1].distance_to(object.position) < 200 else "NO (ends %s)" % (path[-1] if not path.is_empty() else "-")])
	print("mines: %s" % [MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.stock.resource == "gold").map(
			func(o: MapObject) -> String: return "(%d,%d) %d" % [o.position.x, o.position.y, o.stock.amount])])
	for who in GameData.cmdline_option("list", "").split(",", false):
		for object in MapObject.structures:
			if object.is_building() and object.owner_index == who.to_int() and not WallLine.is_wall(object.guid):
				print("P%s %d %s at (%d,%d)" % [who, object.guid, object.display_name(), object.position.x, object.position.y])
	image.save_png(GameData.cmdline_option("out", "user://layout.png"))
	get_tree().quit()


# ------------------------------------------------------------------ the fair player

## A human-like player for one people: economy, building, training, defending and attacking
## in waves, through Orders only and on what the player can see. The mission scenarios
## below set its plan (what to build and train, where to attack) and call think() every
## couple of game seconds.
class FairBot:
	extends RefCounted

	var main: Main
	var me := 0
	var player: Player
	var home := Vector2.INF  ## where the base goes up
	var plan: Array = []  ## structure GUIDs to have, in order (a GUID twice: two of them)
	var army_mix: Array = []  ## unit GUIDs to train, taken in turn
	var worker_target := 10
	var farmer_target := 0
	var wood_share := 0.6
	var food_low := 2000  ## the distilleries work below this
	var attack_size := 12
	var retreat_share := 0.3
	var target := Vector2.INF  ## where the next wave goes
	var target_radius := 900.0
	var protect: Array = []  ## unit GUIDs that stay home (heroes who must live)
	var research := true
	var build_enabled := true
	var only_when_poor: Array = []  ## in the mix, but trained only while gold is short
	var extra_production: Array = []  ## built again (up to 4 each) while food and gold pile up
	var train_enabled := true
	var defend_radius := 900.0
	var mode := "home"  ## home, gathering, attacking
	var wave: Array = []
	var wave_size := 0
	var events: Array[String] = []
	var trained := 0
	var lost := 0
	var kills := 0  ## hostile units dead (counted for the report, not used to play)
	var _mix_i := 0
	var _gather_started := 0.0
	var _trees: Array = []
	var _mines: Array = []
	var _known_dead := {}
	var _threat_since := -1000.0
	var _threat_peak := {}
	var _threat_logged := false
	var _status_at := -1000.0
	var _failed := {}  # structure guid -> time a spot was not found
	var _wave_ordered := {}  # unit instance id -> time of its last order in a wave
	var scout: Unit = null  ## out exploring (not in the army while it is)
	var reserved: Array = []  ## units the mission's plan runs itself (robbers...)
	var _scout_route: Array = []

	func _init(main_node: Main) -> void:
		main = main_node
		me = main.me
		player = main.players[me]
		for object in MapObject.all_objects:
			if object.is_tree():
				_trees.append(object)
			elif object.stock.resource == "gold":
				_mines.append(object)

	func now() -> float:
		return Sim.time()

	func note(text: String) -> void:
		var line := "t=%d %s" % [int(now()), text]
		events.append(line)
		print("FAIR " + line)

	# -------------------------------------------------------------- what we have

	func units() -> Array:
		return Unit.all_units.filter(func(u: Unit) -> bool: return u.team == me and u.is_alive())

	func buildings(complete := false) -> Array:
		return MapObject.structures.filter(func(o: MapObject) -> bool:
			return o.owner_index == me and o.is_building() and o.is_alive() and (o.complete or not complete))

	func count_buildings(guid: int) -> int:
		return buildings().filter(func(o: MapObject) -> bool: return o.guid == guid).size()

	func main_building() -> MapObject:
		for b: MapObject in buildings(true):
			if b.guid in MapObject.MAIN_BUILDINGS:
				return b
		return null

	static func is_animal(u: Unit) -> bool:
		return u.animal.is_cow() or u.animal.is_horse() or u.unit_type.guid() >= 480

	static func is_worker(u: Unit) -> bool:
		return u.unit_type.can_gather("wood") and u.unit_type.can_build()

	func is_soldier(u: Unit) -> bool:
		var t := u.unit_type
		if t.attack_anims.is_empty() or is_worker(u) or t.is_farmer() or t.is_transport() or is_animal(u) or u.water.is_boat():
			return false
		if t.is_hunter() and t.guid() not in army_mix:
			return false
		return not u.inside

	func soldiers() -> Array:
		return units().filter(func(u: Unit) -> bool: return is_soldier(u) and u != scout and u not in reserved)

	## Send `who` round `points` (explored as it goes), then back into the army.
	func send_scout(who: Unit, points: Array) -> void:
		scout = who
		_scout_route = points.duplicate()
		note("scouts with %s: %d points" % [who.display_name(), points.size()])

	## A ring of points round `at` (inside the map), for a scout.
	func ring(at: Vector2, radius: float, points := 8) -> Array:
		var size: Vector2 = main.camera.bounds.size
		var out := []
		for i in points:
			var p := at + Vector2(radius, 0).rotated(TAU * i / points)
			out.append(p.clamp(Vector2(150, 150), size - Vector2(150, 150)))
		return out

	func _scouting() -> void:
		if scout == null:
			return
		if not is_instance_valid(scout) or not scout.is_alive():
			note("scout lost")
			scout = null
			return
		if scout.state == Unit.State.IDLE or _scout_route.is_empty():
			if _scout_route.is_empty():
				scout = null
				return
			Orders.unit(scout, "move_to", [_scout_route.pop_front()])

	func heroes_kept() -> Array:
		return units().filter(func(u: Unit) -> bool: return u.unit_type.guid() in protect)

	# -------------------------------------------------------------- what we see

	func hostile(team: int) -> bool:
		return team > 0 and team != me and Diplomacy.hostile(me, team)

	func visible_enemies() -> Array:
		return Unit.all_units.filter(func(u: Unit) -> bool:
			return u.is_alive() and hostile(u.team) and not u.fogged and not u.inside and not is_animal(u) \
					and not (u.stealth.concealed and not u.stealth.detected_by(me)))

	func known_enemy_buildings() -> Array:
		return MapObject.structures.filter(func(o: MapObject) -> bool:
			return o.is_building() and o.is_alive() and hostile(o.owner_index) and not o.is_trap() \
					and main.fog.is_explored_at(o.position))

	static func centre(list: Array) -> Vector2:
		var c := Vector2.ZERO
		for n: Node2D in list:
			c += n.position / list.size()
		return c

	static func nearest(list: Array, at: Vector2) -> Node2D:
		var best: Node2D = null
		for n: Node2D in list:
			if best == null or n.position.distance_squared_to(at) < best.position.distance_squared_to(at):
				best = n
		return best

	# -------------------------------------------------------------- one think

	func think() -> void:
		if home == Vector2.INF:
			var hq := main_building()
			if hq:
				home = hq.position
		_count_losses()
		_scouting()
		_collect()
		_economy()
		if build_enabled:
			_build()
		if train_enabled:
			_train()
		_army()
		if now() - _status_at >= 60.0:
			_status_at = now()
			print("FAIR " + status())

	func status() -> String:
		var kinds := {}
		for u: Unit in units():
			kinds[u.display_name()] = kinds.get(u.display_name(), 0) + 1
		var jobs := {}
		for u: Unit in units():
			if is_worker(u):
				var job: String = u.work.gather_source.stock.resource if is_instance_valid(u.work.gather_source) else Unit.State.keys()[u.state].to_lower()
				jobs[job] = jobs.get(job, 0) + 1
		return "t=%d %s pop %d/%d workers %s mode %s wave %d/%d; %s; buildings %d; enemies in sight %d; trained %d lost %d enemy dead %d" % [
				int(now()), player.resources, player.population(), player.population_cap(), jobs, mode,
				wave.filter(func(u) -> bool: return is_instance_valid(u) and u.is_alive()).size(), wave_size,
				kinds, buildings().size(), visible_enemies().size(), trained, lost, kills]

	var _recent_losses := {}  # kind -> count, since the last loss note
	var _loss_note_at := 0.0

	func _count_losses() -> void:
		for u: Unit in Unit.all_units:
			# (for the report only: enemies that died, wherever)
			if hostile(u.team) and not u.is_alive() and not is_animal(u) and not _known_dead.has(u.get_instance_id()):
				_known_dead[u.get_instance_id()] = true
				kills += 1
			if u.team == me and not u.is_alive() and not _known_dead.has(u.get_instance_id()):
				_known_dead[u.get_instance_id()] = true
				lost += 1
				var key := "%s near (%d,%d)" % [u.display_name(), int(u.position.x / 500) * 500, int(u.position.y / 500) * 500]
				_recent_losses[key] = _recent_losses.get(key, 0) + 1
		if not _recent_losses.is_empty() and now() - _loss_note_at >= 30.0:
			_loss_note_at = now()
			var seen := {}
			for e: Unit in visible_enemies():
				var k := "P%d %s" % [e.team, e.display_name()]
				seen[k] = seen.get(k, 0) + 1
			note("losses %s; enemies in sight %s" % [_recent_losses, seen])
			_recent_losses.clear()

	# -------------------------------------------------------------- economy

	func _economy() -> void:
		var all := units()
		var workers := all.filter(is_worker)
		var sites := buildings().filter(func(o: MapObject) -> bool: return not o.complete)
		var on_wood := workers.filter(func(u: Unit) -> bool:
			return is_instance_valid(u.work.gather_source) and u.work.gather_source.stock.resource == "wood").size()
		var share := wood_share
		var wood := int(player.resources.get("wood", 0))
		var gold := int(player.resources.get("gold", 0))
		if wood > 1500 and gold < 500:
			share = 0.3
		elif gold > 1500 and wood < 500:
			share = 0.85
		if _sources("gold", Vector2.INF).is_empty():
			share = 1.0
		for w: Unit in workers:
			if w.state != Unit.State.IDLE:
				continue
			var site: MapObject = null
			for s: MapObject in sites:
				var on := workers.filter(func(o: Unit) -> bool: return o.state == Unit.State.BUILDING and o.position.distance_to(s.position) < 200).size()
				if on < 3:
					site = s
					break
			if site:
				Orders.unit(w, "build", [site])
				continue
			var want := "wood" if on_wood < ceili(workers.size() * share) else "gold"
			var source := _source_for(w, want)
			if source == null:
				source = _source_for(w, "gold" if want == "wood" else "wood")
			if source:
				Orders.unit(w, "gather", [source])
				if source.stock.resource == "wood":
					on_wood += 1
		# Women on the fields; more fields while there is room.
		var farmers := all.filter(func(u: Unit) -> bool: return u.unit_type.is_farmer())
		var fields := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == me and o.is_field())
		for f: Unit in farmers:
			if f.state != Unit.State.IDLE:
				continue
			for field: MapObject in fields:
				if UnitWork.field_worker(field) == null:
					Orders.unit(f, "gather", [field])
					break
		var starving := int(player.resources.get("food", 0)) < 300
		if fields.size() < farmers.size() and MapObject.field_allowance(me) > 0 and player.can_afford({"wood": 150 + (0 if starving else _wood_kept())}):
			var store: MapObject = null
			for b: MapObject in buildings(true):
				if b.guid in MapObject.FOOD_STORES:
					store = b
			if store:
				_place(MapObject.FIELD_GUID, store.position, farmers.filter(func(u: Unit) -> bool: return u.state == Unit.State.IDLE).slice(0, 1), 100)
		# Hunters who are not soldiers hunt what is in sight.
		var food := int(player.resources.get("food", 0))
		for h: Unit in all:
			if h.unit_type.is_hunter() and not is_soldier(h) and h.state == Unit.State.IDLE and food < 3000:
				var prey := _prey_near(h.position)
				if prey:
					Orders.unit(h, "hunt", [prey])
		# Liquor while food is short.
		for still: MapObject in buildings(true):
			if still.guid == BuildingProduction.DISTILLERY_GUID and still.production.queue.size() < 2 and food < food_low \
					and int(player.resources.get("wood", 0)) >= 75 + _wood_kept():
				Orders.building(still, "enqueue", [BuildingProduction.LIQUOR_GUID])
		_haul()
		_trade()
		# Workers and women from the main building.
		var hq := main_building()
		if hq and hq.production.queue.size() < 2 and player.has_room():
			for guid in hq.production.trainable_units():
				var t := UnitType.for_guid(guid)
				if t == null or guid in Player.COMMANDERS or not MapRules.allows(me, guid):
					continue
				var builder := t.can_gather("wood") and t.anim_index("build") >= 0
				if (builder and workers.size() + _queued(guid) < worker_target) \
						or (t.is_farmer() and farmers.size() + _queued(guid) < farmer_target):
					if hq.production.can_enqueue(guid):
						Orders.building(hq, "enqueue", [guid])
						trained += 1
					break

	## Wood kept for the next planned structure (and a little for houses).
	func _wood_kept() -> int:
		var next := _next_planned()
		return int(MapRules.stats(me, next).get("cost", {}).get("wood", 0)) if next >= 0 else 100

	## Independent people's units and buildings we have seen: one idle unit walks up to
	## them (they join whoever comes by).
	var collect_neutrals := true

	func _collect() -> void:
		if not collect_neutrals:
			return
		var lone := Unit.all_units.filter(func(u: Unit) -> bool:
			return u.is_alive() and u.team > 0 and u.team != me and Diplomacy.neutral(me, u.team) and not u.fogged \
					and main.fog.is_visible_at(u.position) and not is_animal(u))
		if lone.is_empty():
			return
		var idle := units().filter(func(u: Unit) -> bool: return u.state == Unit.State.IDLE and is_soldier(u))
		if idle.is_empty():
			return
		var who: Unit = nearest(idle, centre(lone))
		Orders.unit(who, "move_to", [nearest(lone, who.position).position])

	## Gold mined into a warehouse waits there for a wagon to take it to the main building:
	## idle wagons haul from the fullest, and one is made (a horse first) when there is none.
	func _haul() -> void:
		var stores := buildings(true).filter(func(o: MapObject) -> bool: return o.is_gold_warehouse())
		if stores.is_empty():
			return
		var wagons := units().filter(func(u: Unit) -> bool: return u.unit_type.is_transport() and not u.water.is_boat())
		stores.sort_custom(func(a: MapObject, b: MapObject) -> bool: return a.stock.stored_gold > b.stock.stored_gold)
		for w: Unit in wagons:
			if w.state == Unit.State.IDLE:
				Orders.unit(w, "haul", [stores[0]])
		var waiting := 0
		for st: MapObject in stores:
			waiting += st.stock.stored_gold
		if wagons.size() >= stores.size() or waiting < 40 or _queued(wagon_guid()) > 0:
			return
		var maker: MapObject = null
		for b: MapObject in buildings(true):
			if wagon_guid() in b.production.trainable_units():
				maker = b
		if maker == null:
			return
		if int(player.resources.get("horses", 0)) < 1:
			for b: MapObject in buildings(true):
				if b.guid in BuildingProduction.HORSE_BUILDINGS and b.production.queue.is_empty() \
						and b.production.can_enqueue(BuildingProduction.HORSE_GUID):
					Orders.building(b, "enqueue", [BuildingProduction.HORSE_GUID])
					note("raises a horse for a wagon")
					return
			return
		if maker.production.can_enqueue(wagon_guid()):
			Orders.building(maker, "enqueue", [wagon_guid()])
			note("makes a wagon for the gold")

	## The trading building evens out the stock: spare wood or food for gold when gold runs
	## short, wood or food bought when gold piles up, guns for the riflemen.
	func _trade() -> void:
		var post: MapObject = null
		for b: MapObject in buildings(true):
			if b.guid in BuildingProduction.TRADE_BUILDINGS and b.production.queue.size() < 2:
				post = b
		if post == null:
			return
		var r := player.resources
		var gold := int(r.get("gold", 0))
		var trade := -1
		if army_mix.any(func(g: int) -> bool: return int(MapRules.stats(me, g).get("cost", {}).get("guns", 0)) > 0) \
				and int(r.get("guns", 0)) < 4 and gold > 600:
			trade = 4
		elif gold < 600 and int(r.get("wood", 0)) > 1200:
			trade = 3
		elif gold < 600 and int(r.get("food", 0)) > 1500:
			trade = 1
		elif int(r.get("food", 0)) < 300 and gold > 1500:
			trade = 0
		elif int(r.get("wood", 0)) < 300 and gold > 1500:
			trade = 2
		if trade >= 0 and post.production.can_enqueue(BuildingProduction.TRADE_GUID + trade):
			Orders.building(post, "enqueue", [BuildingProduction.TRADE_GUID + trade])

	func wagon_guid() -> int:
		return {"des": 355, "usa": 455, "mex": 255, "ind": 155}.get(player.faction, -1)

	## What the gold haul still needs built: the wagon's workshop and a horse building.
	func _haul_needs() -> int:
		if not buildings(true).any(func(o: MapObject) -> bool: return o.is_gold_warehouse()):
			return -1
		if units().any(func(u: Unit) -> bool: return u.unit_type.guid() == wagon_guid()):
			return -1
		var workshop: int = {"des": 309, "usa": 409, "mex": 209, "ind": 109}.get(player.faction, -1)
		if count_buildings(workshop) == 0:
			return workshop
		var horses: int = {"des": 305, "usa": 405, "mex": 205, "ind": 105}.get(player.faction, -1)
		if int(player.resources.get("horses", 0)) < 1 and count_buildings(horses) == 0:
			return horses
		return -1

	func _queued(guid: int) -> int:
		var n := 0
		for b: MapObject in buildings():
			n += Array(b.production.queue).count(guid)
		return n

	func _drop_offs(resource: String) -> Array:
		return buildings(true).filter(func(o: MapObject) -> bool: return resource in o.accepts)

	## Trees or mines we have seen, with something left, near one of our drop-offs.
	func _sources(resource: String, at: Vector2) -> Array:
		var drops := _drop_offs(resource)
		if drops.is_empty():
			return []
		var list := _trees if resource == "wood" else _mines
		return list.filter(func(o) -> bool:
			if not is_instance_valid(o) or o.stock.amount <= 0 or not main.fog.is_explored_at(o.position):
				return false
			for d: MapObject in drops:
				if d.position.distance_to(o.position) < 900.0:
					return true
			return false)

	func _source_for(w: Unit, resource: String) -> MapObject:
		return nearest(_sources(resource, w.position), w.position) as MapObject

	func _prey_near(at: Vector2) -> Unit:
		var best: Unit = null
		for u: Unit in Unit.all_units:
			if u.animal.has_meat() and not u.animal.is_horse() and (u.team == 0 or not u.is_alive()) and not u.fogged \
					and main.fog.is_visible_at(u.position) and u.position.distance_to(at) < 900.0 \
					and (best == null or u.position.distance_to(at) < best.position.distance_to(at)):
				best = u
		return best

	# -------------------------------------------------------------- building

	func _house_guid() -> int:
		return {"des": 301, "usa": 401, "mex": 201, "ind": 101}.get(player.faction, -1)

	func _build() -> void:
		var workers := units().filter(is_worker)
		if workers.is_empty() or home == Vector2.INF:
			return
		var sites := buildings().filter(func(o: MapObject) -> bool: return not o.complete).size()
		if sites >= 2:
			return
		var room := player.population_cap() - player.population() - player.queued_units()
		var house := _house_guid()
		var has_main := buildings().any(func(o: MapObject) -> bool: return o.guid in MapObject.MAIN_BUILDINGS)
		if room < 4 and has_main and player.population_cap() < 200 and sites == 0 and _affordable(house):
			_place(house, home, _builders(workers, 2))
			return
		# Drop-offs by the resources when they lie far.
		for res in ["gold", "wood"]:
			var drop: int = {"des": {"gold": 304, "wood": 309}, "usa": {"gold": 419, "wood": 409}}.get(player.faction, {}).get(res, -1)
			if drop < 0 or not player.meets_prerequisites(drop) or not _affordable(drop) or sites > 0:
				continue
			var list := _trees if res == "wood" else _mines
			var near: MapObject = null
			for o in list:
				if is_instance_valid(o) and o.stock.amount > 0 and main.fog.is_explored_at(o.position) \
						and o.position.distance_to(home) < 2200.0 and (near == null or o.position.distance_to(home) < near.position.distance_to(home)):
					near = o
			if GameData.cmdline_option("debug-drop") != "" and res == "gold":
				print("mines %s home %s" % [_mines.map(func(o: MapObject) -> String: return "%s %s %d %s" % [is_instance_valid(o), o.position if is_instance_valid(o) else Vector2.ZERO, o.stock.amount if is_instance_valid(o) else -1, main.fog.is_explored_at(o.position) if is_instance_valid(o) else false]), home])
			if GameData.cmdline_option("debug-drop") != "":
				print("drop %s: near %s far %s failed %s" % [res, near.position if near else Vector2.INF,
						_drop_offs(res).map(func(d: MapObject) -> float: return d.position.distance_to(near.position)) if near else [], _failed.get(drop)])
			if near and _drop_offs(res).all(func(d: MapObject) -> bool: return d.position.distance_to(near.position) > 600.0) \
					and count_buildings(drop) < 2 \
					and (res == "gold" or _sources("wood", home).size() < 15) and now() - float(_failed.get(drop, -1000.0)) > 60.0:
				if _place(drop, near.position, _builders(workers, 2), 140):
					return
		# The gold haul's workshop and horses.
		var need := _haul_needs()
		if need >= 0 and sites == 0 and player.meets_prerequisites(need) and MapRules.allows(me, need):
			if _affordable(need):
				_place(need, home, _builders(workers, 2))
			return
		# Outlaws turn spare wood into food: another distillery while wood piles up.
		if player.faction == "des" and int(player.resources.get("wood", 0)) > 1200 and int(player.resources.get("food", 0)) < food_low \
				and count_buildings(BuildingProduction.DISTILLERY_GUID) < 5 and sites == 0 and player.meets_prerequisites(BuildingProduction.DISTILLERY_GUID):
			if _place(BuildingProduction.DISTILLERY_GUID, home, _builders(workers, 2)):
				return
		# More production while the stock piles up.
		if sites == 0 and int(player.resources.get("food", 0)) > 1000 and int(player.resources.get("gold", 0)) > 800:
			for guid in extra_production:
				if count_buildings(guid) < 4 and player.meets_prerequisites(guid) and _affordable(guid) \
						and now() - float(_failed.get(guid, -1000.0)) > 60.0:
					if _place(guid, home, _builders(workers, 3)):
						return
		# The plan, in order.
		var have := {}
		for b: MapObject in buildings():
			have[b.guid] = have.get(b.guid, 0) + 1
		var wanted := {}
		for guid in plan:
			wanted[guid] = wanted.get(guid, 0) + 1
			if have.get(guid, 0) >= wanted[guid]:
				continue
			if not MapRules.allows(me, guid) or not player.meets_prerequisites(guid):
				continue
			if not _affordable(guid):
				return  # save up for it
			if now() - float(_failed.get(guid, -1000.0)) > 60.0:
				_place(guid, home, _builders(workers, 3))
			return

	func _builders(workers: Array, n: int) -> Array:
		var free := workers.filter(func(u: Unit) -> bool: return u.state != Unit.State.BUILDING)
		free.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_to(home) < b.position.distance_to(home))
		return free.slice(0, n)

	func _affordable(guid: int) -> bool:
		if guid < 0:
			return false
		var cost: Dictionary = MapRules.stats(me, guid).get("cost", {}).duplicate()
		cost.erase("population")
		return player.can_afford(cost)

	## A site for `guid` on seen ground near `around`; false when none.
	func _place(guid: int, around: Vector2, builders: Array, min_radius := 160) -> bool:
		var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
		if type == null or builders.is_empty() and guid != MapObject.FIELD_GUID:
			return false
		var nav := NavGrid.current
		var enemies := known_enemy_buildings()
		for radius in range(min_radius, 1400, 32):
			var steps := maxi(12, int(TAU * radius / 48.0))
			for step in steps:
				var spot := around + Vector2(radius, 0).rotated(step * TAU / steps + radius * 0.37)
				spot = (spot / NavGrid.CELL).round() * NavGrid.CELL
				if not main.fog.is_explored_at(spot) or not AiBuilder.footprint_free(type, spot, nav) \
						or not BuildController.can_place_for(type, spot, me):
					continue
				if enemies.any(func(e: MapObject) -> bool: return e.position.distance_to(spot) < 700.0):
					continue
				Orders.place(type.id, spot, false, null, builders)
				note("builds %s at (%d,%d)" % [GameData.stats(guid).get("name"), spot.x, spot.y])
				return true
		_failed[guid] = now()
		return false

	# -------------------------------------------------------------- training

	func _train() -> void:
		if army_mix.is_empty():
			return
		# Keep back what the next planned structure costs (the base comes first).
		var next := _next_planned()
		var keep: Dictionary = MapRules.stats(me, next).get("cost", {}) if next >= 0 else {}
		for b: MapObject in buildings(true):
			# Guns for the riflemen, while gold allows.
			if b.guid in BuildingProduction.GUN_FACTORIES and b.production.queue.is_empty() \
					and int(player.resources.get("guns", 0)) < 6 and int(player.resources.get("gold", 0)) > 450:
				Orders.building(b, "enqueue", [BuildingProduction.GUN_GUID])
				continue
			if b.production.queue.size() >= 2 or not player.has_room():
				continue
			var offered := b.production.trainable_units()
			for i in army_mix.size():
				var guid: int = army_mix[(_mix_i + i) % army_mix.size()]
				if guid not in offered or not MapRules.allows(me, guid):
					continue
				if guid in only_when_poor and int(player.resources.get("gold", 0)) >= 150:
					continue
				var cost: Dictionary = MapRules.stats(me, guid).get("cost", {}).duplicate()
				cost.erase("population")
				var total := cost.duplicate()
				for k in keep:
					if cost.has(k):  # only what the structure and the unit both need
						total[k] = int(total.get(k, 0)) + int(keep[k])
				if player.can_afford(total) and b.production.can_enqueue(guid):
					Orders.building(b, "enqueue", [guid])
					trained += 1
					_mix_i = (_mix_i + i + 1) % army_mix.size()
					break
		if research and int(player.resources.get("gold", 0)) > 700 and int(player.resources.get("food", 0)) > 700:
			for b: MapObject in buildings(true):
				if not b.production.queue.is_empty():
					continue
				for up in b.production.researchable_upgrades():
					var effects: Dictionary = GameData.stats(up).get("effects", {})
					if (effects.has("attack") or effects.has("health_pct")) and b.production.can_enqueue(up):
						Orders.building(b, "enqueue", [up])
						note("researches %s" % GameData.stats(up).get("name"))
						return

	func _next_planned() -> int:
		var have := {}
		for b: MapObject in buildings():
			have[b.guid] = have.get(b.guid, 0) + 1
		var wanted := {}
		for guid in plan:
			wanted[guid] = wanted.get(guid, 0) + 1
			if have.get(guid, 0) < wanted[guid] and MapRules.allows(me, guid) and player.meets_prerequisites(guid):
				return guid
		return -1

	# -------------------------------------------------------------- the army

	func _spread(list: Array, method: String, at: Vector2) -> void:
		var slots := SelectionController.formation_slots(list.size(), Unit.Formation.RELAXED)
		for i in list.size():
			var spot := at + slots[i] * 40.0 - Vector2(sqrt(list.size()) * 20.0, 0)
			Orders.unit(list[i], method, [spot])

	func _army() -> void:
		var all_soldiers := soldiers()
		wave = wave.filter(func(u) -> bool: return is_instance_valid(u) and u.is_alive())
		var at_home := all_soldiers.filter(func(u: Unit) -> bool: return u not in wave and u.unit_type.guid() not in protect)
		var enemies := visible_enemies()
		var mine := buildings()
		var threats := enemies.filter(func(e: Unit) -> bool:
			if home != Vector2.INF and e.position.distance_to(home) < defend_radius:
				return true
			return mine.any(func(b: MapObject) -> bool: return b.position.distance_to(e.position) < 500.0))
		_watch_threats(threats)
		# Defend: everyone at home (and the kept heroes when it is close) goes at the intruders.
		if not threats.is_empty():
			var defenders := at_home.duplicate()
			for h: Unit in heroes_kept():
				if nearest(threats, h.position).position.distance_to(h.position) < 450.0:
					defenders.append(h)
			for d: Unit in defenders:
				if d.state != Unit.State.ATTACKING:
					Orders.unit(d, "attack_move", [nearest(threats, d.position).position])
		else:
			var rally := _rally()
			for d: Unit in at_home + heroes_kept():
				if d.state == Unit.State.IDLE and d.position.distance_to(rally) > 350.0:
					Orders.unit(d, "move_to", [rally + Vector2(Sim.randf_range(-120, 120), Sim.randf_range(-90, 90))])
		match mode:
			"home":
				if target != Vector2.INF and at_home.size() >= attack_size and threats.is_empty():
					wave = at_home.duplicate()
					wave_size = wave.size()
					mode = "gathering"
					_gather_started = now()
					_spread(wave, "move_to", _staging())
					note("gathers a wave of %d (%s) for (%d,%d)" % [wave.size(), _kinds(wave), target.x, target.y])
			"gathering":
				var st := _staging()
				var there := wave.filter(func(u: Unit) -> bool: return u.position.distance_to(st) < 350.0).size()
				if there >= wave.size() * 0.8 or now() - _gather_started > 60.0:
					mode = "attacking"
					_wave_ordered.clear()
					_spread(wave, "attack_move", target)
					note("attacks with %d" % wave.size())
			"attacking":
				_attack(enemies, at_home)

	func _attack(enemies: Array, at_home: Array) -> void:
		if wave.size() < maxi(2, int(wave_size * retreat_share)):
			note("wave beaten back: %d of %d left, retreating" % [wave.size(), wave_size])
			for u: Unit in wave:
				Orders.unit(u, "move_to", [_rally()])
			wave.clear()
			mode = "home"
			return
		# Reinforcements from home join the wave.
		if at_home.size() >= 5 and enemies.filter(func(e: Unit) -> bool: return home != Vector2.INF and e.position.distance_to(home) < defend_radius).is_empty():
			for u: Unit in at_home:
				wave.append(u)
				Orders.unit(u, "attack_move", [centre(wave)])
			wave_size = maxi(wave_size, wave.size())
		var c := centre(wave)
		var buildings_near := known_enemy_buildings().filter(func(o: MapObject) -> bool:
			return o.position.distance_to(c) < 900.0 and not WallLine.is_wall(o.guid))
		for u: Unit in wave:
			if u.state == Unit.State.ATTACKING:
				continue
			var last := float(_wave_ordered.get(u.get_instance_id(), -100.0))
			if u.state == Unit.State.MOVING and now() - last < 12.0:
				continue
			_wave_ordered[u.get_instance_id()] = now()
			var foe: Unit = nearest(enemies, u.position) as Unit
			if foe and foe.position.distance_to(u.position) < 700.0:
				Orders.unit(u, "attack_move", [foe.position])
			elif not buildings_near.is_empty():
				Orders.unit(u, "order_attack", [nearest(buildings_near, u.position)])
			elif u.position.distance_to(c) > 500.0:
				Orders.unit(u, "attack_move", [c])
			else:
				Orders.unit(u, "attack_move", [target + Vector2(Sim.randf_range(-150, 150), Sim.randf_range(-150, 150))])

	## Whether the target is taken: nothing hostile seen round it and the wave there.
	func target_clear() -> bool:
		if target == Vector2.INF:
			return true
		if known_enemy_buildings().any(func(o: MapObject) -> bool: return o.position.distance_to(target) < target_radius):
			return false
		if visible_enemies().any(func(u: Unit) -> bool: return u.position.distance_to(target) < target_radius):
			return false
		return main.fog.is_visible_at(target)

	func _rally() -> Vector2:
		if home == Vector2.INF:
			return centre(units())
		if target == Vector2.INF:
			return home + Vector2(0, 150)
		return home + (target - home).normalized() * 300.0

	func _staging() -> Vector2:
		return _rally()

	func _kinds(list: Array) -> String:
		var kinds := {}
		for u: Unit in list:
			kinds[u.display_name()] = kinds.get(u.display_name(), 0) + 1
		return ", ".join(kinds.keys().map(func(k: String) -> String: return "%d %s" % [kinds[k], k]))

	## Attacks on us: logged when they start (what is seen) and when they end.
	func _watch_threats(threats: Array) -> void:
		if not threats.is_empty():
			if not _threat_logged:
				_threat_logged = true
				_threat_peak = {}
				note("ATTACK on us near (%d,%d): %d seen (%s)" % [centre(threats).x, centre(threats).y, threats.size(), _kinds(threats)])
			for e: Unit in threats:
				_threat_peak[e.get_instance_id()] = e.display_name()
			_threat_since = now()
		elif _threat_logged and now() - _threat_since > 30.0:
			_threat_logged = false
			var kinds := {}
			for k in _threat_peak.values():
				kinds[k] = kinds.get(k, 0) + 1
			note("attack over: %d enemies took part (%s); we have %d soldiers" % [_threat_peak.size(), kinds, soldiers().size()])



# ------------------------------------------------------------------ running a mission

var bot: FairBot
var phase := ""
var fired := {}  ## trigger index -> game second it (last) fired
var _phase_at := 0.0


func _begin(mix: Array, plan: Array) -> FairBot:
	var mission := main.mission
	bot = FairBot.new(main)
	bot.army_mix = mix
	bot.plan = plan
	mission.message.connect(func(text: String, _seconds: float, _speech: String) -> void:
		print("FAIR t=%d MESSAGE %s" % [int(Sim.time()), text.replace("\n", " ").left(140)]))
	mission.fired.connect(func(index: int) -> void:
		fired[index] = Sim.time()
		print("FAIR t=%d (script: trigger %d fired)" % [int(Sim.time()), index]))
	mission.goal_changed.connect(func(text: String) -> void:
		print("FAIR t=%d GOAL %s" % [int(Sim.time()), text.replace("\n", " ").left(200)]))
	print("FAIR start %s difficulty %d seed %s; we have %s" % [Match.campaign.get("id", GameData.cmdline_option("mission")),
			Match.difficulty, GameData.cmdline_option("seed", "1"), bot.status()])
	return bot


func _set_phase(name: String) -> void:
	phase = name
	_phase_at = Sim.time()
	bot.note("PHASE %s" % name)


## Think every two game seconds, `step` (the mission's own plan) first, until the mission
## ends or --limit=<s> game seconds (default `limit`) have passed; then the result.
func _play(step: Callable, limit: float) -> void:
	var mission := main.mission
	limit = GameData.cmdline_option("limit", str(limit)).to_float()
	while mission.outcome == 0 and Sim.time() < limit:
		if not Orders.locked:
			step.call()
			bot.think()
		var until := Sim.time() + 2.0
		while Sim.time() < until and mission.outcome == 0:
			await get_tree().physics_frame
	print("FAIR " + bot.status())
	print("FAIR RESULT %s difficulty %d: %s at %d s (%d:%02d), phase %s, goal %d" % [GameData.cmdline_option("mission"),
			Match.difficulty, "WON" if mission.outcome > 0 else ("LOST" if mission.outcome < 0 else "UNDECIDED"),
			int(Sim.time()), int(Sim.time()) / 60, int(Sim.time()) % 60, phase, mission.goal])
	# For the report (not used to play): what the others have left.
	for index in main.players:
		if index == main.me:
			continue
		var kinds := {}
		for u: Unit in Unit.all_units:
			if u.team == index and u.is_alive():
				kinds[u.display_name()] = kinds.get(u.display_name(), 0) + 1
		var bs := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == index and o.is_building() and o.is_alive()).size()
		print("FAIR left P%d: %d buildings, units %s" % [index, bs, kinds])
	print("FAIR fired %s" % [mission.fired_log.map(func(e: PackedInt32Array) -> int: return e[1])])
	get_tree().quit()


func _area_centre(id: int) -> Vector2:
	return main.mission.area(id).get_center()


func _fired_any(index: int) -> bool:
	return fired.has(index)


## Units of `owner` (an independent people's) in sight: walking up to them takes them over.
func _neutral_buildings_seen() -> Array:
	return MapObject.structures.filter(func(o: MapObject) -> bool:
		return o.is_building() and o.is_alive() and o.owner_index > 0 and o.owner_index != main.me \
				and Diplomacy.neutral(main.me, o.owner_index) and main.fog.is_explored_at(o.position))


# ------------------------------------------------------------------ base/des_03

## --mission=base/des_03 "Bounty hunt": ride north into town (the duel plays), take over the
## US town (it joins), build a base and an army (deputy sheriffs from the town's office,
## whip crackers and barbers), then the western band town, the northern one, and the green
## band leader's camp across the river.
func _scenario_fair_des03() -> void:
	_begin([462, 363], [300, 308, 303, 308, 306, 309, 301, 303, 308, 301, 303, 301, 301])
	bot.extra_production = [303]
	bot.worker_target = 14
	bot.farmer_target = 5
	bot.protect = [350, 351]  # the band leader leads from behind
	bot.attack_size = GameData.cmdline_option("wave", "35").to_int()
	_set_phase("ride north")
	var start := bot.units()
	Orders.units(start, "move_to", [_area_centre(2)])
	await _play(_des03_step, 9000.0)


func _des03_step() -> void:
	var mission := main.mission
	match phase:
		"ride north":
			if _fired_any(3):  # the duel is over: the scene hands back the controls
				_set_phase("into town")
		"into town":
			# Walk through the town: its people and houses join whoever comes by.
			var neutral := _neutral_buildings_seen()
			var idle := bot.units().filter(func(u: Unit) -> bool: return u.state == Unit.State.IDLE)
			if not neutral.is_empty() and not idle.is_empty():
				var b: MapObject = FairBot.nearest(neutral, FairBot.centre(idle))
				Orders.units(idle, "move_to", [b.position + Vector2(0, 90)])
			elif neutral.is_empty() and Sim.time() - _phase_at > 30.0 and not idle.is_empty():
				Orders.units(idle, "move_to", [_area_centre(3)])  # the road through town
			if mission.goal == 826:
				var town := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == main.me and o.is_building())
				bot.home = FairBot.centre(town) if not town.is_empty() else FairBot.centre(bot.units())
				_set_phase("build up")
				var riders := bot.units().filter(func(u: Unit) -> bool: return u.unit_type.guid() == 361)
				if riders.is_empty():
					riders = bot.soldiers()
				bot.send_scout(riders[0], bot.ring(bot.home, 900.0) + bot.ring(bot.home, 1800.0, 10) + [bot.home])
		"build up", "west town":
			if phase == "build up":
				bot.target = _area_centre(4)  # the town in the west the cowboy showed
				_set_phase("west town")
			if mission.goal == 828:
				bot.target = _area_centre(8)
				_set_phase("north town")
		"north town":
			if mission.goal == 831:
				bot.target = _area_centre(10)
				_set_phase("green camp")
		"green camp":
			# The green band leader, once seen: everyone in the wave at him.
			for u: Unit in bot.visible_enemies():
				if u.unit_type.guid() in [350, 351] and u.team == 3 and bot.mode == "attacking":
					Orders.units(bot.wave, "order_attack", [u])
					break


## Conquest: the wave goes at the nearest enemy settlement we know of (its main or
## military buildings first); with none known, riders scout the unexplored map.
func _conquer_step(scouts: Array, owners := []) -> void:
	if bot.mode == "home" or bot.target_clear():
		var known := bot.known_enemy_buildings().filter(func(o: MapObject) -> bool: return owners.is_empty() or o.owner_index in owners)
		if known.is_empty():
			if bot.scout == null:
				var free := bot.units().filter(func(u: Unit) -> bool: return u.unit_type.guid() in scouts and u.state == Unit.State.IDLE)
				if not free.is_empty():
					var route := _unexplored_points(bot.home, 8)
					if not route.is_empty():
						bot.send_scout(free[0], route + [bot.home])
			if bot.target != Vector2.INF and bot.target_clear():
				bot.note("target (%d,%d) cleared" % [bot.target.x, bot.target.y])
				bot.target = Vector2.INF
			return
		var key := known.filter(func(o: MapObject) -> bool: return o.guid in MapObject.MAIN_BUILDINGS or bot_military(o.guid))
		var pick: MapObject = FairBot.nearest(key if not key.is_empty() else known, bot.home)
		if bot.target == Vector2.INF or pick.position.distance_to(bot.target) > bot.target_radius:
			bot.target = pick.position
			bot.note("next target: %s of P%d at (%d,%d)" % [pick.display_name(), pick.owner_index, pick.position.x, pick.position.y])


func bot_military(guid: int) -> bool:
	return guid in [103, 203, 217, 211, 303, 307, 403, 417, 411]


## Unexplored spots spread over the map, nearest to `from` first.
func _unexplored_points(from: Vector2, n: int) -> Array:
	var size: Vector2 = main.camera.bounds.size
	var out := []
	var step := 1200.0
	var y := step / 2
	while y < size.y:
		var x := step / 2
		while x < size.x:
			var p := Vector2(x, y)
			if not main.fog.is_explored_at(p) and main.nav.is_walkable(main.nav.cell_of(p)):
				out.append(p)
			x += step
		y += step
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(from) < b.distance_to(from))
	# A round trip: the nearest few, in the order a rider would take them.
	var route := []
	var at := from
	var left := out.slice(0, n)
	while not left.is_empty():
		left.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(at) < b.distance_to(at))
		at = left.pop_front()
		route.append(at)
	return route


# ------------------------------------------------------------------ base/usa_06

## --mission=base/usa_06 "Border conflict": five enemies round the American camp; their
## military and main buildings must all fall. Farm and fields, a sheriff's office, fort,
## training camps and a weapons factory; infantry, cavalry and cannons in waves at the
## nearest settlement known, scouts (the mounted cowboys) finding the next.
func _scenario_fair_usa06() -> void:
	_begin([462, 458, 458, 460, 465, 458], [408, 407, 401, 409, 401, 417, 403, 411, 401, 403, 401, 401, 401])
	bot.extra_production = [403]
	bot.worker_target = 12
	bot.farmer_target = 6
	bot.protect = [450, 451]
	bot.attack_size = GameData.cmdline_option("wave", "20").to_int()
	bot.home = bot.main_building().position
	_set_phase("conquest")
	var cowboys := bot.units().filter(func(u: Unit) -> bool: return u.unit_type.guid() == 464)
	if not cowboys.is_empty():
		bot.send_scout(cowboys[0], bot.ring(bot.home, 1500.0, 8) + [bot.home])
	await _play(func() -> void: _conquer_step([464, 463]), 9000.0)


# ------------------------------------------------------------------ base/des_06

var _robbers: Array = []
var _bank_spots: Array = []
var _rob_pause_until := 0.0


## --mission=base/des_06 "Sheriff's deadline": the three US settlements on our side of the
## river (red, green, turquoise; the opening shows them and their banks) must go, and our
## base must stand; the army across the river is left alone. Gunslingers, blasters, whip
## crackers and riflemen; a few gunslingers rob the banks for gold.
func _scenario_fair_des06() -> void:
	_begin([360, 359, 363, 356, 360, 359, 353], [301, 308, 306, 302, 305, 310, 301, 307, 314, 301, 308, 301])
	bot.extra_production = [307, 314]
	bot.only_when_poor = [353]
	bot.worker_target = 14
	bot.protect = [350, 351]
	bot.attack_size = GameData.cmdline_option("wave", "20").to_int()
	bot.home = bot.main_building().position
	_bank_spots = [_area_centre(3), _area_centre(5), _area_centre(7)]
	_bank_spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(bot.home) < b.distance_to(bot.home))
	_set_phase("settlements")
	await _play(_des06_step, 9000.0)


func _des06_step() -> void:
	# The towns the opening showed, nearest first, until they are gone.
	if bot.mode == "home" or bot.target_clear():
		var towns := [_area_centre(2), _area_centre(8), _area_centre(4)]
		var known := bot.known_enemy_buildings().filter(func(o: MapObject) -> bool: return o.owner_index in [3, 4, 8])
		var left := towns.filter(func(t: Vector2) -> bool:
			return not main.fog.is_visible_at(t) or known.any(func(o: MapObject) -> bool: return o.position.distance_to(t) < 1200.0))
		if not known.is_empty() and (left.is_empty() or bot.target_clear()):
			var pick: MapObject = FairBot.nearest(known, bot.home)
			if pick.position.distance_to(bot.target) > bot.target_radius:
				bot.target = pick.position
				bot.note("next target: %s of P%d at (%d,%d)" % [pick.display_name(), pick.owner_index, pick.position.x, pick.position.y])
		elif not left.is_empty():
			left.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(bot.home) < b.distance_to(bot.home))
			if bot.target == Vector2.INF or bot.target_clear():
				bot.target = left[0]
				bot.note("next town: (%d,%d)" % [bot.target.x, bot.target.y])
	_rob_banks()


## Three gunslingers (or outlaws) rob the nearest bank we know of while gold runs low.
func _rob_banks() -> void:
	var before := _robbers.size()
	_robbers = _robbers.filter(func(u) -> bool: return is_instance_valid(u) and u.is_alive())
	if before > 0 and _robbers.is_empty():
		_rob_pause_until = Sim.time() + 600.0  # the robbers were caught: wait a while
		bot.note("robbers lost; next try in 10 min")
	if int(bot.player.resources.get("gold", 0)) > 600 or _bank_spots.is_empty() or Sim.time() < _rob_pause_until:
		return
	if _robbers.is_empty():
		var picks := bot.soldiers().filter(func(u: Unit) -> bool: return u.work.can_rob() and u not in bot.wave)
		if picks.size() < 4:
			return  # a band of four, or nobody
		_robbers = picks.slice(0, 4)
		bot.reserved = _robbers
		if _robbers.is_empty():
			return
		bot.note("robbers: %d %s" % [_robbers.size(), _robbers[0].display_name()])
	var spot: Vector2 = _bank_spots[0]
	var bank: MapObject = null
	for o: MapObject in bot.known_enemy_buildings():
		if o.guid in BuildingProduction.INCOME_BUILDINGS and o.position.distance_to(spot) < 500.0:
			bank = o
	for r: Unit in _robbers:
		if r.state != Unit.State.IDLE:
			continue
		if bank:
			Orders.unit(r, "rob", [bank])
		elif main.fog.is_visible_at(spot):
			_bank_spots.pop_front()  # gone (or never there)
			return
		else:
			Orders.unit(r, "move_to", [spot + Vector2(0, 150)])


## Skirmish map (--ai=off): --na=<n> of --a=<guid> (people 1) against --nb=<m> of --b=<guid>
## (people 2), --dist=<px> apart, both attack-moving; the survivors and their energy.
## A check that a fight between equals is even (both without leaders: the same morale).
func _scenario_fair_duel() -> void:
	await get_tree().physics_frame
	var centre: Vector2 = main.camera.position
	var dist := GameData.cmdline_option("dist", "500").to_float()
	var a := GameData.cmdline_option("a", "462").to_int()
	var b := GameData.cmdline_option("b", "360").to_int()
	for u: Unit in Unit.all_units.duplicate():
		if u.team > 0:
			u.queue_free()
	await get_tree().physics_frame
	main._spawn_squad(a, 1, centre + Vector2(0, dist / 2), GameData.cmdline_option("na", "10").to_int())
	main._spawn_squad(b, 2, centre - Vector2(0, dist / 2), GameData.cmdline_option("nb", "10").to_int())
	await get_tree().physics_frame
	for team in [1, 2]:
		var side := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == team and u.is_alive())
		var other_centre := centre - Vector2(0, dist / 2) if team == 1 else centre + Vector2(0, dist / 2)
		Orders.local_player = team
		Orders.units(side, "attack_move", [other_centre])
	Orders.local_player = main.me
	var start := Sim.time()
	while Sim.time() - start < 180.0:
		var alive := [1, 2].map(func(t: int) -> int: return Unit.all_units.filter(func(u: Unit) -> bool: return u.team == t and u.is_alive()).size())
		if alive[0] == 0 or alive[1] == 0:
			break
		await get_tree().physics_frame
	for team in [1, 2]:
		var side := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == team and u.is_alive())
		print("DUEL team %d (%d): %d left, energy %s" % [team, a if team == 1 else b, side.size(),
				side.map(func(u: Unit) -> int: return int(u.health))])
	print("DUEL took %.0f s" % (Sim.time() - start))
	get_tree().quit()
