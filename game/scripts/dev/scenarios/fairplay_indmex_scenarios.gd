extends Scenario
## Native and Mexican campaign missions played fairly (start with --mission=... and
## --difficulty=0..3): a bot gives only the orders a player could give through Orders
## (move, attack, build, train, research, gather, cast...), decides only on what the
## player knows (his own people, explored ground, enemies in sight through the fog, the
## mission's goal and message texts), and prints what happens, to judge whether the
## missions can be won and how hard they are at each difficulty.
##
##   --scenario=indmex_play  the bot plays the --mission given (a plan per mission below)
##   --limit=<s>           game seconds before giving up (default 5400)
##   --log-every=<s>       status lines (default 60)
## Lines: "FAIR t=..." status, "ATTACK ..." an enemy force in sight of our buildings,
## "MSG" the mission's messages, and at the end "FAIR RESULT <mission> d<difficulty> WON|LOST|TIMEOUT at <s>".
## After the end a "DIAG" block reads hidden state (enemy armies) for the report only.


## Any mission: what the human has and may make, the full goal texts; then (for the tester,
## not the bot) every player's buildings and units by kind.
func _scenario_indmex_info() -> void:
	await _wait(2.0)
	var me := main.me
	var player: Player = main.players[me]
	print("INFO human P%d %s resources %s pop %d/%d" % [me, player.faction, player.resources, player.population(), player.population_cap()])
	print("INFO goal: %s" % main.mission.goal_text().replace("\n", " | "))
	var said := {}
	for t in main.mission.data.triggers:
		for a in t.actions:
			if a[0] in [5, 27] and not said.has(Mission._param(a, 1)):
				said[Mission._param(a, 1)] = true
				print("TEXT %d: %s" % [Mission._param(a, 1), main.mission.text(Mission._param(a, 1)).replace("\n", " | ")])
	for guid in GameData.stats_guids():
		var s := GameData.stats(guid)
		if s.get("faction") != player.faction or s.get("kind") not in ["unit", "structure", "upgrade"]:
			continue
		print("INFO %s %d %s allowed %s cost %s at %s prereq %s hp %s dmg %s housing %s" % [s.kind, guid, s.get("name"),
				MapRules.allows(me, guid), MapRules.stats(me, guid).get("cost", {}), s.get("produced_at", "-"),
				Array(GameData.prerequisites(guid)), MapRules.stats(me, guid).get("health", "-"),
				MapRules.stats(me, guid).get("damage", "-"), MapRules.stats(me, guid).get("housing", "-")])
	var field_type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.FIELD_GUID, main.terrain.biome))
	var stores := MapObject.structures.filter(func(o: MapObject) -> bool: return o.owner_index == me and o.guid in MapObject.FOOD_STORES)
	var spot := AiBuilder.find_spot(field_type, stores[0].position, 110) if not stores.is_empty() and field_type else Vector2.INF
	print("INFO fields allowed %s allowance %d cost %s; a spot by the first food store %s placeable %s explored %s" % [MapRules.allows(me, MapObject.FIELD_GUID),
			MapObject.field_allowance(me), MapRules.stats(me, MapObject.FIELD_GUID).get("cost", {}), spot,
			BuildController.can_place_for(field_type, spot, me) if spot != Vector2.INF else false, main.fog.is_explored_at(spot)])
	var seen_types := {}
	for u: Unit in Unit.all_units:
		if u.team == me and not seen_types.has(u.unit_type.guid()):
			seen_types[u.unit_type.guid()] = true
			var t := u.unit_type
			print("INFO type %d %s wood %s gold %s food %s build %s farmer %s hunter %s transport %s attacks %d healer %s sight %.0f range %.0f" % [t.guid(),
					u.display_name(), t.can_gather("wood"), t.can_gather("gold"), t.can_gather("food"), t.can_build(), t.is_farmer(),
					t.is_hunter(), t.is_transport(), t.attack_anims.size(), u.magic.is_healer(), u.sight(), u.attack_range()])
	for p in main.players:
		_diag_player(p)
	get_tree().quit()


## Any mission: screenshots of the map at --look=x,y;x,y;... (start with --fog=off, --zoom=...;
## not headless), to see how a place is laid out.
func _scenario_indmex_look() -> void:
	await _wait(1.0)
	_label = "%s/%s" % [Match.campaign.get("set", "?"), Match.campaign.get("code", "?")]
	for pair in GameData.cmdline_option("paths", "").split(";", false):
		var v := Array(pair.split(",")).map(func(t: String) -> float: return t.to_float())
		var path := main.nav.find_path(Vector2(v[0], v[1]), Vector2(v[2], v[3]))
		print("PATH %s -> %s: %d points, ends %s (%.0f px short)" % [Vector2i(v[0], v[1]), Vector2i(v[2], v[3]), path.size(),
				Vector2i(path[path.size() - 1]) if path.size() > 0 else Vector2i.ZERO,
				path[path.size() - 1].distance_to(Vector2(v[2], v[3])) if path.size() > 0 else -1.0])
	for spot in GameData.cmdline_option("look", "").split(";", false):
		var xy := spot.split(",")
		await _shot(Vector2(xy[0].to_float(), xy[1].to_float()), "look_%s_%s" % [xy[0], xy[1]])
	get_tree().quit()


func _diag_player(p: int) -> void:
	var kinds := {}
	for o: MapObject in MapObject.structures:
		if o.owner_index == p and o.is_building() and o.is_alive():
			kinds.get_or_add(o.display_name(), []).append("(%d,%d)" % [o.position.x, o.position.y])
	var units := {}
	for u: Unit in Unit.all_units:
		if u.team == p and u.is_alive():
			units[u.display_name()] = units.get(u.display_name(), 0) + 1
	print("DIAG P%d %s res %s buildings %s" % [p, main.players[p].faction, main.players[p].resources,
			"; ".join(kinds.keys().map(func(k: String) -> String: return "%s x%d %s" % [k, kinds[k].size(), " ".join(kinds[k].slice(0, 6))]))])
	print("DIAG P%d units %s" % [p, units])


# ================================================================== the fair game

var bot: FairBot
var _label := ""
var _episodes: Array[Dictionary] = []  # enemy forces seen near our buildings
var _episode: Dictionary = {}
var _quiet_since := 0.0


func _scenario_indmex_play() -> void:
	var mission := main.mission
	if mission == null:
		print("FAIR needs --mission")
		get_tree().quit()
		return
	_label = "%s/%s" % [Match.campaign.get("set", "?"), Match.campaign.get("code", "?")]
	bot = FairBot.new(main)
	mission.message.connect(func(text: String, _s: float, _sp: String) -> void:
		print("MSG t=%.0f %s" % [Sim.time(), text.replace("\n", " | ").left(160)]))
	mission.goal_changed.connect(func(text: String) -> void:
		print("GOAL t=%.0f %s" % [Sim.time(), text.replace("\n", " | ").left(200)]))
	var plan := "_plan_" + String(Match.campaign.get("set", "")) + "_" + String(Match.campaign.get("code", ""))
	if not has_method(plan):
		plan = "_plan_generic"
	print("FAIR %s difficulty %d (%s) plan %s" % [_label, Match.difficulty, Match.DIFFICULTY_NAMES[Match.difficulty], plan])
	var limit := GameData.cmdline_option("limit", "5400").to_float()
	var shots := Array(GameData.cmdline_option("shots", "").split(",", false)).map(func(t: String) -> float: return t.to_float())
	var log_every := GameData.cmdline_option("log-every", "60").to_float()
	var next_log := 0.0
	var next_think := 1.0
	while mission.outcome == 0 and Sim.time() < limit:
		await get_tree().physics_frame
		if Sim.time() < next_think:
			continue
		next_think = Sim.time() + 1.5
		bot.sense()
		_watch_attacks()
		if Orders.locked:
			continue  # a scene: the player cannot give orders either
		call(plan)
		bot.run_economy()
		bot.run_army()
		if Sim.time() >= next_log:
			next_log += log_every
			print(bot.status())
		if not shots.is_empty() and Sim.time() >= shots[0]:
			shots.pop_front()
			await _shot(bot.army_centre())
	_close_episode()
	var outcome := "WON" if mission.outcome > 0 else ("LOST" if mission.outcome < 0 else "TIMEOUT")
	print("FAIR RESULT %s d%d %s at %.0f s (%.1f min); trained %s; lost %d units, %d buildings" % [_label, Match.difficulty, outcome,
			Sim.time(), Sim.time() / 60.0, bot.trained, bot.lost_units, bot.lost_buildings])
	print("FAIR attacks seen: %d" % _episodes.size())
	for e in _episodes:
		print("  ATTACK from %.0f to %.0f s: peak %d units %s near %s" % [e.start, e.end, e.peak, e.kinds, e.where])
	print(bot.status())
	print("FAIR fired %s" % [mission.fired_log.map(func(e: PackedInt32Array) -> String: return "%d@%d" % [e[1], e[0] / 1000])])
	for p in main.players:
		if p != main.me:
			_diag_player(p)
	var ki := main.ki
	if ki:
		for p in ki.players:
			print("DIAG P%d KI modules: %s" % [p, ki.players[p].running()])
	get_tree().quit()


## A screenshot of the view at `at` (--shot-dir; not headless).
func _shot(at: Vector2, name := "") -> void:
	if DisplayServer.get_name() == "headless":
		return
	main.camera.position = at
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file := "%s/%s_%s.png" % [GameData.cmdline_option("shot-dir", "/tmp"), _label.replace("/", "_"), name if name else str(int(Sim.time()))]
	get_viewport().get_texture().get_image().save_png(file)
	print("FAIR shot %s at %s" % [file, Vector2i(at)])


## An enemy force in sight within reach of our buildings: one episode while it lasts.
func _watch_attacks() -> void:
	var near := bot.threats(1400.0)
	var now := Sim.time()
	if near.is_empty():
		if not _episode.is_empty() and now - _quiet_since > 30.0:
			_close_episode()
		return
	_quiet_since = now
	if _episode.is_empty():
		_episode = {"start": now, "end": now, "peak": 0, "kinds": {}, "where": ""}
		print("ATTACK t=%.0f begins: %d enemies near %s" % [now, near.size(), _centre(near)])
	_episode.end = now
	if near.size() > _episode.peak:
		_episode.peak = near.size()
		_episode.where = str(_centre(near))
		var kinds := {}
		for u: Unit in near:
			kinds["P%d %s" % [u.team, u.display_name()]] = kinds.get("P%d %s" % [u.team, u.display_name()], 0) + 1
		_episode.kinds = kinds


func _close_episode() -> void:
	if _episode.is_empty():
		return
	print("ATTACK ends t=%.0f: %.0f s, peak %d %s" % [_episode.end, _episode.end - _episode.start, _episode.peak, _episode.kinds])
	_episodes.append(_episode)
	_episode = {}


static func _centre(units: Array) -> Vector2i:
	var c := Vector2.ZERO
	for u in units:
		c += u.position / units.size()
	return Vector2i(c)


# ------------------------------------------------------------------ mission plans
# Each plan only sets what the bot aims at (bot.mode, bot.rally, bot.target...), from the
# goal texts and what the player has seen.

func _plan_generic() -> void:
	if bot.army().size() >= 15 and not bot.known_targets().is_empty():
		bot.mode = "attack"
		bot.target = bot.nearest_known(bot.known_targets(), bot.home)
	else:
		bot.mode = "home"


## Native 1, The Santee Sioux Uprising: five general stores somewhere in the west, New Ulm's
## houses in the northwest; Little Crow stays back; Fort Ridgely (south) is avoided.
func _plan_base_ind_01() -> void:
	if bot.plan_once("ind01"):
		bot.keep_back = [270, 271]
		bot.worker_target = 8
		bot.farmer_target = 6
		bot.soldier_cap = 40
		bot.build_plan = [[108, 1], [103, 1], [101, 2], [109, 1], [101, 4], [103, 2], [101, 8]]
		bot.soldier_kinds = [156]
		bot.home_guard = 4
		# The goal: the map's west, New Ulm in the northwest. Scout along the north edge,
		# then the middle, then the south-west (staying clear of the fort in the south-east).
		bot.scout_route = [Vector2(5600, 500), Vector2(4200, 600), Vector2(3000, 900), Vector2(1800, 900),
				Vector2(700, 700), Vector2(1400, 1700), Vector2(2600, 1600), Vector2(3700, 1900), Vector2(3600, 2900),
				Vector2(2600, 3500), Vector2(1500, 3000), Vector2(600, 2400)]
		bot.rally = bot.home + Vector2(-500, 150)
	var stores := bot.known_of([410])
	var houses := bot.known_of([401]).filter(func(o: Dictionary) -> bool: return o.pos.y < 1200 and o.pos.x < 3200)
	var targets := stores + houses
	if bot.army().size() >= 14 or (bot.mode == "attack" and bot.army().size() >= 6):
		if not targets.is_empty():
			bot.mode = "attack"
			bot.target = bot.nearest_known(targets, bot.army_centre())
			return
	bot.mode = "home"


## Mexican 5, Battle of Monterrey: hold out 45 minutes; the command post must stand.
func _plan_base_mex_05() -> void:
	if bot.plan_once("mex05"):
		bot.worker_target = 16
		bot.farmer_target = 6
		bot.soldier_cap = 90
		bot.build_plan = [[201, 2], [211, 2], [201, 4]]
		bot.soldier_kinds = [258, 265, 259, 261]
		bot.gun_reserve = 10
		bot.defend_radius = 1600.0
		bot.research = [925, 929, 926, 930, 932, 931]
		bot.income_buildings = 4
		bot.rally = bot.home
	bot.mode = "home"


var _custer_since := -1.0
var _ind08_south := [Vector2(1900, 7600), Vector2(1600, 8400), Vector2(900, 8900), Vector2(800, 9800), Vector2(2600, 8600)]


## Native 8, Little Big Horn: get ready (Reno attacks), then destroy the training camps and
## trappers' cabins in the south, stop Capt. Weirs before the river, destroy Custer's camp
## (everyone of his); Crazy Horse and Gall must live.
func _plan_base_ind_08() -> void:
	var mission := main.mission
	if bot.plan_once("ind08"):
		bot.heroes_behind = true  # both must live: they keep behind the army, out of the fighting
		bot.worker_target = 12
		bot.farmer_target = 14
		bot.hunters_wanted = 2
		bot.soldier_cap = 80
		bot.build_plan = [[104, 1], [107, 1], [115, 1], [101, 1]]
		bot.soldier_kinds = [163, 158, 160, 162, 156]
		bot.research = [900, 903, 917, 919, 901, 904]
		bot.casters_wanted = 2
		bot.max_production = 4
		bot.defend_outposts = false  # the tepees by the enemy camps in the south are lost
		bot.defend_radius = 2400.0
		bot.scout_route = [Vector2(2000, 6500), Vector2(1600, 8000), Vector2(800, 9000), Vector2(1200, 10000)]
		bot.rally = bot.home + Vector2(0, 300)
	var goal := mission.goal
	if goal == 434:  # Weirs: south, heading for the river in the north-east
		var weirs := bot.visible_enemies().filter(func(u: Unit) -> bool: return u.unit_type.guid() in [290, 291])
		bot.mode = "hunt"
		bot.hunt_units = weirs
		bot.hunt_point = Vector2(6300, 6500) if weirs.is_empty() else weirs[0].position
		return
	if goal == 435 and _custer_since < 0.0:
		_custer_since = Sim.time()
	if goal == 435 and Sim.time() - _custer_since < 150.0:  # "Attack!": Custer comes first
		bot.mode = "home"
		return
	if goal == 435:  # Custer's camp, in the north-east where the camera showed him
		bot.scout_route = [Vector2(4500, 2500), Vector2(6000, 1600), Vector2(6800, 1000), Vector2(7600, 600)]
		var custer := bot.visible_enemies().filter(func(u: Unit) -> bool: return u.team == 2)
		if bot.army().size() >= 18 or (bot.mode == "hunt" and bot.army().size() >= 8):
			bot.mode = "hunt"
			bot.hunt_units = custer
			bot.hunt_point = Vector2(6700, 1050) if custer.is_empty() else bot.nearest_unit(custer, bot.army_centre()).position
			return
		bot.mode = "home"
		return
	var camps := bot.known_of([403, 406]).filter(func(o: Dictionary) -> bool: return o.pos.x < 3500)
	var going := bot.mode != "home" and bot.army().size() >= 10
	if goal == 430 and (bot.army().size() >= 25 or going):
		if not camps.is_empty():
			bot.mode = "attack"
			bot.target = bot.nearest_known(camps, bot.army_centre())
			return
		# "In the south": the army walks there and looks.
		bot.mode = "hunt"
		bot.hunt_units = bot.visible_enemies()
		bot.hunt_point = bot.next_look(_ind08_south)
		return
	bot.mode = "home"


## Waits `seconds` of game time.
func _wait(seconds: float) -> void:
	var until := Sim.time() + seconds
	while Sim.time() < until:
		await get_tree().physics_frame


# ================================================================== the player bot

## A reasonably competent player: keeps the workers busy, builds houses before the people
## run out of room, a food store and fields, the plan's buildings, trains soldiers, keeps
## the army at a rally point, answers enemies that come into sight near home, and attacks
## (or hunts down units) as the mission plan says. Every order goes through Orders.
class FairBot:
	extends RefCounted

	const HEROES := [150, 151, 250, 251, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279]
	const HOUSES := {"ind": 101, "mex": 201}
	const FOOD_STORE := {"ind": 108, "mex": 208}
	const WORKER := {"ind": 152, "mex": 252}
	const FARMER := {"ind": 153, "mex": 253}
	const GOLD_STORE := {"ind": 104, "mex": 206}
	const PRODUCTION := {"ind": 103, "mex": 203}
	const BREAKERS := [154, 158, 159, 265]
	const LIGHTNING := 919

	var main: Main
	var me := 0
	var player: Player
	var faction := ""
	var biome := ""
	var home := Vector2.ZERO
	var rally := Vector2.INF
	var mode := "home"  ## home, attack (a building: target), hunt (units: hunt_units / hunt_point)
	var target: Dictionary = {}  ## a known building {o, pos, guid, owner}
	var hunt_units: Array = []
	var hunt_point := Vector2.INF
	var keep_back: Array = []  ## heroes that stay home
	var hero_retreat := 0.5  ## heroes with less health than this go home
	var heroes_behind := false  ## heroes walk behind the army (not fighting in front) instead of with it
	var worker_target := 10
	var farmer_target := 5
	var soldier_cap := 50
	var hunters_wanted := 0
	var casters_wanted := 0
	var gun_reserve := 0
	var max_food_stores := 3
	var max_production := 3  ## training tepees / barracks to have when rich
	var defend_outposts := true  ## also answer enemies near buildings far from home
	var home_guard := 0  ## soldiers that stay at the rally point when the army goes out
	var defend_radius := 1200.0
	var build_plan: Array = []  ## [guid, how many] in order
	var soldier_kinds: Array = []  ## what to train, best first
	var research: Array = []
	var scout_route: Array = []
	var trained := {}
	var lost_units := 0
	var lost_buildings := 0
	var _plans := {}
	var _known := {}  ## sim_id -> {o, pos, guid, owner, name}: enemy buildings the player has seen
	var _mine := {}  ## sim_ids of ours, to count losses
	var _my_buildings := {}
	var _scout: Unit
	var _scout_leg := 0
	var _orders := {}  ## sim_id -> [kind, key] last ordered (not to repeat the same order)
	var _cache_units: Array = []
	var _stall_target: MapObject
	var _stall_best := INF
	var _stall_since := 0.0
	var _breach: MapObject
	var trade_wood_above := 1500  ## sell wood for gold above this much (at a trading post)
	var buy_food_below := 200
	var income_buildings := 0  ## missions (Mexican gold income) to put up with spare wood
	var _visible: Array = []


	func _init(game: Main) -> void:
		main = game
		me = main.me
		player = main.players[me]
		faction = player.faction
		biome = main.terrain.biome
		var hq := main_building()
		home = hq.position if hq else _centroid(_units())
		rally = home


	func plan_once(key: String) -> bool:
		if _plans.has(key):
			return false
		_plans[key] = true
		return true


	# -------------------------------------------------------------- what the player knows

	func sense() -> void:
		_cache_units = Unit.all_units.filter(func(u: Unit) -> bool: return u.team == me and u.is_alive())
		var fog := main.fog
		_visible = Unit.all_units.filter(func(u: Unit) -> bool:
			return u.is_alive() and u.team != me and u.team > 0 and Diplomacy.hostile(me, u.team) and not u.inside \
					and u.state != Unit.State.QUARTERED and not u.animal.is_cow() and not u.animal.is_horse() \
					and fog.is_visible_at(u.position) and not (u.stealth.concealed and not u.stealth.detected_by(me)))
		for o: MapObject in MapObject.structures:
			if o.is_building() and o.is_alive() and o.owner_index > 0 and o.owner_index != me \
					and Diplomacy.hostile(me, o.owner_index) and fog.is_visible_at(o.position) and not o.is_trap():
				_known[o.sim_id] = {"o": o, "pos": o.position, "guid": o.guid, "owner": o.owner_index, "name": o.display_name()}
		for id in _known.keys():
			var k: Dictionary = _known[id]
			var gone: bool = not is_instance_valid(k.o) or not k.o.is_alive() or k.o.owner_index != k.owner
			if gone and fog.is_visible_at(k.pos):
				_known.erase(id)
		# Our losses.
		var now_ids := {}
		for u: Unit in _cache_units:
			now_ids[u.sim_id] = true
		for id in _mine.keys():
			if not now_ids.has(id):
				lost_units += 1
				_mine.erase(id)
		for u: Unit in _cache_units:
			_mine[u.sim_id] = true
		var b_ids := {}
		for b: MapObject in my_buildings():
			b_ids[b.sim_id] = true
		for id in _my_buildings.keys():
			if not b_ids.has(id):
				lost_buildings += 1
				_my_buildings.erase(id)
		for id in b_ids:
			_my_buildings[id] = true
		var hq := main_building()
		if hq:
			home = hq.position


	func visible_enemies() -> Array:
		return _visible


	## Enemies in sight within `radius` of home, or near one of our buildings.
	func threats(radius: float) -> Array:
		var mine := my_buildings()
		return _visible.filter(func(u: Unit) -> bool:
			if u.position.distance_to(home) < radius:
				return true
			if not defend_outposts:
				return false
			for b: MapObject in mine:
				if b.position.distance_to(u.position) < radius * 0.6:
					return true
			return false)


	## The first of `points` the army has not been near yet (looking for what the goal names).
	func next_look(points: Array) -> Vector2:
		var c := army_centre()
		while not points.is_empty() and (c.distance_to(points[0]) < 300.0 or main.fog.is_visible_at(points[0])):
			points.pop_front()
		return points[0] if not points.is_empty() else home


	func known_targets() -> Array:
		return _known.values()


	func known_of(guids: Array) -> Array:
		return _known.values().filter(func(k: Dictionary) -> bool: return k.guid in guids)


	func nearest_known(list: Array, from: Vector2) -> Dictionary:
		var best: Dictionary = {}
		for k: Dictionary in list:
			if best.is_empty() or from.distance_to(k.pos) < from.distance_to(best.pos):
				best = k
		return best


	func nearest_unit(list: Array, from: Vector2) -> Unit:
		var best: Unit = null
		for u: Unit in list:
			if best == null or from.distance_to(u.position) < from.distance_to(best.position):
				best = u
		return best


	# -------------------------------------------------------------- our people

	func _units() -> Array:
		if _cache_units.is_empty():
			_cache_units = Unit.all_units.filter(func(u: Unit) -> bool: return u.team == me and u.is_alive())
		return _cache_units.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())


	func my_buildings() -> Array:
		return MapObject.structures.filter(func(o: MapObject) -> bool:
			return o.is_building() and o.owner_index == me and o.is_alive())


	func main_building() -> MapObject:
		for b: MapObject in my_buildings():
			if b.guid in MapObject.MAIN_BUILDINGS and b.complete:
				return b
		return null


	func workers() -> Array:
		return _units().filter(func(u: Unit) -> bool: return not u.inside and u.unit_type.can_gather("wood") and u.unit_type.can_build())


	func farmers() -> Array:
		return _units().filter(func(u: Unit) -> bool: return not u.inside and u.unit_type.is_farmer())


	func is_hero(u: Unit) -> bool:
		return u.unit_type.guid() in HEROES


	func army() -> Array:
		return _units().filter(func(u: Unit) -> bool:
			var t := u.unit_type
			return not u.inside and not t.attack_anims.is_empty() and not t.can_gather("wood") and not t.is_farmer() \
					and not t.is_transport() and not is_hero(u) and not u.animal.is_cow() and not u.animal.is_horse() \
					and t.guid() != UnitWater.CANOE and not (t.is_hunter() and u.work.hunting))


	func heroes() -> Array:
		return _units().filter(func(u: Unit) -> bool: return is_hero(u) and not u.inside)


	func support() -> Array:
		return _units().filter(func(u: Unit) -> bool: return not u.inside and (u.magic.is_healer() or u.unit_type.guid() == UnitMagic.MEDICINE_MAN))


	func army_centre() -> Vector2:
		var a := army()
		return _centroid(a) if not a.is_empty() else home


	static func _centroid(list: Array) -> Vector2:
		var c := Vector2.ZERO
		for u in list:
			c += u.position / list.size()
		return c


	# -------------------------------------------------------------- economy

	func run_economy() -> void:
		var hq := main_building()
		_staff_sites()
		_assign_workers()
		_farm()
		_hunt()
		_haul()
		if hq:
			_train_civilians(hq)
		_build_houses()
		_build_plan()
		_train_army()
		_research()
		_trade()
		_scout_ahead()


	func _type(guid: int) -> ObjectTypes.ObjectType:
		return ObjectTypes.get_type(GameData.type_for_guid(guid, biome))


	func _cost(guid: int) -> Dictionary:
		var cost: Dictionary = MapRules.stats(me, guid).get("cost", {}).duplicate()
		cost.erase("population")
		return cost


	func _may_build(guid: int) -> bool:
		# Fields need only a food store (field_allowance), whatever people (as the build menu).
		return guid >= 0 and MapRules.allows(me, guid) and (guid == MapObject.FIELD_GUID or player.meets_prerequisites(guid)) \
				and player.can_afford(_cost(guid))


	func count_buildings(guid: int, with_sites := true) -> int:
		return my_buildings().filter(func(b: MapObject) -> bool: return b.guid == guid and (with_sites or b.complete)).size()


	## Put down a site of `guid` near `around` (the build menu and a click), with the
	## nearest idle-ish builders.
	func place(guid: int, around: Vector2, min_radius := 200, builders_wanted := 2) -> bool:
		if not _may_build(guid):
			return false
		var type := _type(guid)
		if type == null:
			return false
		var spot := AiBuilder.find_spot(type, around, min_radius)
		if spot == Vector2.INF or not BuildController.can_place_for(type, spot, me) or not main.fog.is_explored_at(spot):
			return false
		var builders := _builders_for(spot, builders_wanted, guid == MapObject.FIELD_GUID)
		if builders.is_empty():
			return false
		Orders.place(type.id, spot, false, null, builders)
		for b: Unit in builders:
			_orders[b.sim_id] = ["build", spot]
		return true


	func _builders_for(spot: Vector2, n: int, field: bool) -> Array:
		var pool := farmers() if field else _units().filter(func(u: Unit) -> bool: return not u.inside and u.unit_type.can_build())
		pool = pool.filter(func(u: Unit) -> bool: return u.work.build_site == null)
		pool.sort_custom(func(a: Unit, b: Unit) -> bool:
			var ia := 0 if a.state == Unit.State.IDLE else 1
			var ib := 0 if b.state == Unit.State.IDLE else 1
			if ia != ib:
				return ia < ib
			return a.position.distance_to(spot) < b.position.distance_to(spot))
		return pool.slice(0, n)


	## Sites nobody builds get the nearest builders.
	func _staff_sites() -> void:
		for site: MapObject in my_buildings():
			if site.complete:
				continue
			var on_it := _units().filter(func(u: Unit) -> bool: return u.work.build_site == site)
			if on_it.size() < 2:
				var more := _builders_for(site.position, 2 - on_it.size(), false)
				if not more.is_empty():
					Orders.units(more, "build", [site])


	func _assign_workers() -> void:
		var ws := workers()
		var idle := ws.filter(func(u: Unit) -> bool: return u.state == Unit.State.IDLE and u.work.build_site == null)
		if idle.is_empty():
			return
		var on_gold := ws.filter(func(u: Unit) -> bool: return u.work.gather_resource == "gold").size()
		var mine := _gold_mine() if _needs_gold() else null
		for w: Unit in idle:
			if mine and on_gold < int(ws.size() * 0.4):
				Orders.unit(w, "gather", [mine])
				on_gold += 1
				continue
			var tree := w.work.nearest_source("wood", 2500.0)
			if tree and main.fog.is_explored_at(tree.position):
				Orders.unit(w, "gather", [tree])


	func _needs_gold() -> bool:
		for g in soldier_kinds + research:
			if int(_cost(g).get("gold", 0)) > 0 and MapRules.allows(me, g):
				return true
		return false


	## The nearest explored gold mine with gold left and no enemy in sight by it; a gold
	## store goes up by a far one.
	func _gold_mine() -> MapObject:
		var best: MapObject = null
		for o: MapObject in MapObject.all_objects:
			if o.is_mine() and o.stock.amount > 0 and main.fog.is_explored_at(o.position) \
					and o.position.distance_to(home) < 3500.0 \
					and not _visible.any(func(u: Unit) -> bool: return u.position.distance_to(o.position) < 500.0):
				if best == null or o.position.distance_to(home) < best.position.distance_to(home):
					best = o
		if best and best.position.distance_to(home) > 700.0:
			var stores := my_buildings().filter(func(b: MapObject) -> bool: return "gold" in b.accepts and b.position.distance_to(best.position) < 600.0)
			if stores.is_empty():
				place(GOLD_STORE.get(faction, -1), best.position, 120, 2)
		return best


	func _farm() -> void:
		var store: int = FOOD_STORE.get(faction, -1)
		var fs := farmers()
		if count_buildings(store) == 0:
			place(store, home, 260, 2)
			return
		var fields := MapObject.structures.filter(func(o: MapObject) -> bool: return o.is_field() and o.owner_index == me and o.is_alive())
		# Short of food with wood to spare: another food store for five more fields.
		if MapObject.field_allowance(me) <= 0 and int(player.resources.get("wood", 0)) >= 500 \
				and int(player.resources.get("food", 0)) < 600 and count_buildings(store) < max_food_stores \
				and my_buildings().filter(func(b: MapObject) -> bool: return b.guid == store and not b.complete).is_empty():
			place(store, home, 300, 2)
		# Farmers who are not on a field (idle, or cutting wood) are the ones to work one.
		var idle := fs.filter(func(u: Unit) -> bool: return u.work.build_site == null \
				and (u.state == Unit.State.IDLE or (u.state == Unit.State.GATHERING and u.work.gather_resource != "food")))
		for f: Unit in idle:
			var free_field: MapObject = null
			for field: MapObject in fields:
				if UnitWork.field_worker(field) == null:
					free_field = field
					break
			if free_field:
				Orders.unit(f, "gather", [free_field])
				continue
			if MapObject.field_allowance(me) > 0 and int(player.resources.get("wood", 0)) >= 250:
				var stores := my_buildings().filter(func(b: MapObject) -> bool: return b.guid == store and b.complete)
				if not stores.is_empty() and place(MapObject.FIELD_GUID, stores[0].position, 110, 1):
					return
			elif f.unit_type.can_gather("wood") and f.state == Unit.State.IDLE:
				var tree := f.work.nearest_source("wood", 2500.0)
				if tree:
					Orders.unit(f, "gather", [tree])


	func _hunt() -> void:
		if hunters_wanted <= 0:
			return
		var hunting := _units().filter(func(u: Unit) -> bool: return u.unit_type.is_hunter() and u.work.hunting)
		if hunting.size() >= hunters_wanted:
			return
		for u: Unit in army():
			if u.unit_type.is_hunter() and u.state == Unit.State.IDLE:
				var prey := u.work.nearest_animal()
				if prey and main.fog.is_explored_at(prey.position) and prey.position.distance_to(home) < 1500:
					Orders.unit(u, "hunt", [prey])
					return


	func _haul() -> void:
		for u: Unit in _units():
			if u.unit_type.is_transport() and u.state == Unit.State.IDLE:
				var stores := my_buildings().filter(func(b: MapObject) -> bool: return b.is_gold_warehouse() and b.complete)
				if not stores.is_empty():
					Orders.unit(u, "haul", [stores[0]])


	func _train_civilians(hq: MapObject) -> void:
		if hq.production.queue.size() >= 2:
			return
		var w: int = WORKER.get(faction, -1)
		var f: int = FARMER.get(faction, -1)
		var food := int(player.resources.get("food", 0))
		var wood := int(player.resources.get("wood", 0))
		# Farmers for every field there is or may be planted (five per finished food store).
		var stores := my_buildings().filter(func(b: MapObject) -> bool: return b.guid == FOOD_STORE.get(faction, -1) and b.complete).size()
		var farmers_wanted := maxi(farmer_target, mini(stores * MapObject.FIELDS_PER_STORE, farmer_target + 10))
		var short_of_food := food < 150 and wood > 400
		if farmers().size() < farmers_wanted and MapRules.allows(me, f) and food >= 50 and (short_of_food or workers().size() >= worker_target):
			Orders.building(hq, "enqueue", [f])
		elif workers().size() < worker_target and MapRules.allows(me, w) and food >= 50:
			Orders.building(hq, "enqueue", [w])


	func _build_houses() -> void:
		var house: int = HOUSES.get(faction, -1)
		var cap := player.population_cap()
		var sites := my_buildings().filter(func(b: MapObject) -> bool: return b.guid == house and not b.complete).size()
		if player.population() + player.queued_units() + 3 >= cap + sites * 8 and sites < 2 and cap < Match.population_limit:
			place(house, home, 220, 2)


	func _build_plan() -> void:
		if my_buildings().filter(func(b: MapObject) -> bool: return not b.complete).size() >= 2:
			return
		for step: Array in build_plan:
			var guid: int = step[0]
			if count_buildings(guid) < int(step[1]) and MapRules.allows(me, guid):
				if not player.meets_prerequisites(guid):
					continue
				place(guid, home, 250, 3)
				return  # one thing at a time, in order
		# Rich and short of soldiers: more places to train them.
		var barracks: int = PRODUCTION.get(faction, -1)
		if count_buildings(barracks) < max_production and army().size() < soldier_cap \
				and int(player.resources.get("food", 0)) > 800 and int(player.resources.get("wood", 0)) > 600:
			place(barracks, home, 300, 3)


	func _train_army() -> void:
		var a := army()
		if a.size() + player.queued_units() >= soldier_cap:
			return
		# Guns for those who need them.
		if gun_reserve > 0 and int(player.resources.get("guns", 0)) < gun_reserve:
			for b: MapObject in my_buildings():
				if b.complete and BuildingProduction.GUN_GUID in b.production.trainable_units() and b.production.queue.is_empty():
					if b.production.can_enqueue(BuildingProduction.GUN_GUID):
						Orders.building(b, "enqueue", [BuildingProduction.GUN_GUID])
					break
		if casters_wanted > 0:
			var men := _units().filter(func(u: Unit) -> bool: return u.unit_type.guid() == UnitMagic.MEDICINE_MAN).size()
			if men < casters_wanted:
				for b: MapObject in my_buildings():
					if b.complete and UnitMagic.MEDICINE_MAN in b.production.trainable_units() and b.production.queue.is_empty() \
							and b.production.can_enqueue(UnitMagic.MEDICINE_MAN):
						Orders.building(b, "enqueue", [UnitMagic.MEDICINE_MAN])
		if not player.has_room():
			return
		var breakers := a.filter(func(u: Unit) -> bool: return u.unit_type.guid() in BREAKERS).size()
		for b: MapObject in my_buildings():
			if not b.complete or b.production.queue.size() >= 2:
				continue
			var can := b.production.trainable_units()
			# A mixed army: of the kinds that can be had now, the one we have fewest of.
			var best := -1
			var best_have := 1 << 30
			for guid: int in soldier_kinds:
				if guid not in can or not MapRules.allows(me, guid) or not b.production.can_enqueue(guid):
					continue
				if guid in BREAKERS and breakers > a.size() / 3:
					continue  # a third of building breakers is enough
				var have := a.filter(func(u: Unit) -> bool: return u.unit_type.guid() == guid).size()
				if have < best_have:
					best = guid
					best_have = have
			if best >= 0:
				Orders.building(b, "enqueue", [best])
				var name: String = GameData.stats(best).get("name", str(best))
				trained[name] = trained.get(name, 0) + 1


	## Spare wood sold for gold, gold for food when the people go hungry.
	func _trade() -> void:
		var post: MapObject = null
		for b: MapObject in my_buildings():
			if b.complete and b.guid in BuildingProduction.TRADE_BUILDINGS and b.production.queue.size() < 2:
				post = b
		if income_buildings > 0 and int(player.resources.get("wood", 0)) > 900 and count_buildings(216) < income_buildings:
			place(216, home, 300, 3)
		if post == null:
			return
		var sell_wood := BuildingProduction.TRADE_GUID + 3
		var buy_food := BuildingProduction.TRADE_GUID + 0
		var gold := int(player.resources.get("gold", 0))
		if int(player.resources.get("food", 0)) < (buy_food_below * 3 if gold > 1500 else buy_food_below) and gold > 400 \
				and MapRules.allows(me, buy_food) and post.production.can_enqueue(buy_food):
			Orders.building(post, "enqueue", [buy_food])
		elif int(player.resources.get("wood", 0)) > trade_wood_above and MapRules.allows(me, sell_wood) and post.production.can_enqueue(sell_wood):
			Orders.building(post, "enqueue", [sell_wood])


	func _research() -> void:
		for guid: int in research:
			if not MapRules.allows(me, guid) or not player.can_research(guid):
				continue
			for b: MapObject in my_buildings():
				if b.complete and b.production.queue.is_empty() and guid in b.production.researchable_upgrades() \
						and b.production.can_enqueue(guid):
					var cost := _cost(guid)
					# Only from what is left over after the army's next few soldiers (all of it
					# when the people are at their limit).
					var keep := 0 if not player.has_room() else 1
					if int(player.resources.get("food", 0)) - int(cost.get("food", 0)) >= 200 * keep \
							and int(player.resources.get("gold", 0)) - int(cost.get("gold", 0)) >= 150 * keep \
							and int(player.resources.get("wood", 0)) >= int(cost.get("wood", 0)):
						Orders.building(b, "enqueue", [guid])
						return


	## One soldier walks the scouting route while there is one.
	func _scout_ahead() -> void:
		if scout_route.is_empty() or _scout_leg >= scout_route.size():
			return
		if _scout == null or not is_instance_valid(_scout) or not _scout.is_alive():
			var a := army()
			if a.size() < 4:
				return
			a.sort_custom(func(x: Unit, y: Unit) -> bool: return x.sight() > y.sight())
			_scout = a[0]
		var goal: Vector2 = scout_route[_scout_leg]
		var hurt := _scout.health < _scout.max_health * 0.6
		if _scout.position.distance_to(goal) < 250.0 or hurt \
				or (_scout.state == Unit.State.IDLE and _orders.get(_scout.sim_id, []) == ["scout", goal]):
			_scout_leg += 1
			if _scout_leg >= scout_route.size() or hurt:
				Orders.unit(_scout, "move_to", [rally])
				print("FAIR t=%.0f scouting %s; known enemy buildings %d" % [Sim.time(), "cut short (scout hurt)" if hurt else "done", _known.size()])
				_scout = null
				return
			goal = scout_route[_scout_leg]
		if _orders.get(_scout.sim_id, []) != ["scout", goal]:
			_orders[_scout.sim_id] = ["scout", goal]
			Orders.unit(_scout, "move_to", [goal])


	# -------------------------------------------------------------- the army

	func run_army() -> void:
		var a := army()
		if _scout and is_instance_valid(_scout):
			a.erase(_scout)
		_heroes(a)
		_support(a)
		var near := threats(defend_radius)
		if not near.is_empty() and (mode == "home" or army_centre().distance_to(home) < defend_radius * 1.2):
			_defend(a, near)
			return
		if mode != "home" and home_guard > 0 and a.size() > home_guard * 2:
			a.sort_custom(func(x: Unit, y: Unit) -> bool: return x.position.distance_to(rally) < y.position.distance_to(rally))
			_hold(a.slice(0, home_guard))
			a = a.slice(home_guard)
		match mode:
			"attack":
				_attack(a)
			"hunt":
				_hunt_units(a)
			_:
				_hold(a)


	func _order(u: Unit, kind: String, args: Array, key: Variant) -> void:
		if _orders.get(u.sim_id, []) == [kind, key] and u.state != Unit.State.IDLE:
			return
		_orders[u.sim_id] = [kind, key]
		Orders.unit(u, kind, args)


	func _defend(a: Array, near: Array) -> void:
		for u: Unit in a:
			if u.state == Unit.State.ATTACKING:
				continue
			var foe := nearest_unit(near, u.position)
			_order(u, "attack_move", [foe.position], Vector2i(foe.position / 200.0))


	func _hold(a: Array) -> void:
		for u: Unit in a:
			if u.state == Unit.State.IDLE and u.position.distance_to(rally) > 350.0:
				_order(u, "attack_move", [rally + Vector2(Sim.randf_range(-150, 150), Sim.randf_range(-150, 150))], "rally")


	func _attack(a: Array) -> void:
		if target.is_empty() or not is_instance_valid(target.o) or not _known.has(target.o.sim_id):
			mode = "home"
			return
		var goal: Vector2 = target.pos
		var centre := _centroid(a)
		# Not getting closer (a palisade in the way): break through the nearest piece of it.
		var d_now := centre.distance_to(goal)
		if target.o != _stall_target or d_now < _stall_best - 100.0:
			_stall_target = target.o
			_stall_best = d_now
			_stall_since = Sim.time()
		if _breach and (not is_instance_valid(_breach) or not _breach.is_alive()):
			_breach = null
			_stall_since = Sim.time()
		if _breach == null and d_now > 300.0 and Sim.time() - _stall_since > 25.0:
			var best: MapObject = null
			for k: Dictionary in _known.values():
				if is_instance_valid(k.o) and k.o.is_alive() and k.o != target.o and k.pos.distance_to(centre) < 700.0 \
						and (WallLine.is_wall(k.guid) or k.name.to_lower().contains("stockade") or k.name.to_lower().contains("palisade")):
					if best == null or k.pos.distance_to(centre) < best.position.distance_to(centre):
						best = k.o
			if best:
				_breach = best
				print("FAIR t=%.0f army stuck %.0f px from %s: breaking through %s at %s" % [Sim.time(), d_now, target.name, best.display_name(), Vector2i(best.position)])
				for u: Unit in a.slice(0, 6):
					print("  unit at %s %s target %s path %d" % [Vector2i(u.position), Unit.State.keys()[u.state],
							u.target.display_name() if is_instance_valid(u.target) else "-", u.path.size()])
		if _breach:
			for u: Unit in a:
				if u.state != Unit.State.ATTACKING or u.target == null:
					_order(u, "order_attack", [_breach], _breach.sim_id)
			return
		# The target clicked (an attack order walks there and ignores palisades on the way);
		# enemy soldiers that come close are fought first; stragglers catch up.
		for u: Unit in a:
			var foe := nearest_unit(_visible, u.position)
			if foe and foe.position.distance_to(u.position) < 350.0:
				if not (u.state == Unit.State.ATTACKING and u.target is Unit):
					_order(u, "attack_move", [foe.position], Vector2i(foe.position / 100.0))
				continue
			if u.state == Unit.State.ATTACKING and u.target is Unit:
				continue
			if u.position.distance_to(centre) > 700.0 and centre.distance_to(goal) < u.position.distance_to(goal) - 300.0:
				_order(u, "move_to", [centre], "catch up")
			elif u.target != target.o:
				_order(u, "order_attack", [target.o], target.o.sim_id)


	func _hunt_units(a: Array) -> void:
		var goal := hunt_point
		var visible_targets := hunt_units.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive() and u in _visible)
		for u: Unit in a:
			if u.state == Unit.State.ATTACKING and (u.target in visible_targets or visible_targets.is_empty()):
				continue
			var foe := nearest_unit(visible_targets, u.position)
			if foe and foe.position.distance_to(u.position) < 700.0:
				_order(u, "order_attack", [foe], foe.sim_id)
			elif goal != Vector2.INF:
				_order(u, "attack_move", [goal], Vector2i(goal / 150.0))


	func _heroes(a: Array) -> void:
		for h: Unit in heroes():
			var hurt := h.health < h.max_health * hero_retreat
			var army_away := mode != "home" and not a.is_empty() and _centroid(a).distance_to(home) > 1500.0
			if h.unit_type.guid() in keep_back or hurt or (heroes_behind and not army_away):
				if h.position.distance_to(home) > 300.0 or (hurt and h.state == Unit.State.ATTACKING):
					_order(h, "move_to", [home + Vector2(60, 60)], "home")
				continue
			if a.is_empty():
				continue
			var c := _centroid(a)
			if heroes_behind:
				# Behind the army on the side of home, away from the enemies in sight.
				var away := (home - c).normalized() if home.distance_to(c) > 1.0 else Vector2.ZERO
				var spot := c + away * 450.0
				var foe := nearest_unit(_visible, h.position)
				if foe and foe.position.distance_to(h.position) < 300.0 and h.health < h.max_health * 0.8:
					_order(h, "move_to", [c + (c - foe.position).normalized() * 150.0], "dodge")
				elif h.position.distance_to(spot) > 300.0 and h.state != Unit.State.ATTACKING:
					_order(h, "move_to", [spot], Vector2i(spot / 200.0))
				continue
			# A fighting hero keeps with the army.
			if h.state == Unit.State.IDLE and h.position.distance_to(c) > 300.0:
				_order(h, "attack_move", [c], "with army")


	func _support(a: Array) -> void:
		var centre := _centroid(a) if not a.is_empty() else rally
		for s: Unit in support():
			# Lightning on a crowd of enemies near the army.
			if LIGHTNING in s.magic.known_spells() and s.magic.magic_energy >= UnitMagic.SPELLS[LIGHTNING].cost and s.magic.spell < 0:
				var crowd := _visible.filter(func(e: Unit) -> bool: return e.position.distance_to(s.position) < 600.0)
				if crowd.size() >= 4:
					var c := _centroid(crowd)
					Orders.unit(s, "cast", [LIGHTNING, c])
					print("FAIR t=%.0f lightning on %d enemies at %s" % [Sim.time(), crowd.size(), Vector2i(c)])
					continue
			if s.state == Unit.State.IDLE and s.position.distance_to(centre) > 250.0:
				_order(s, "move_to", [centre + Vector2(0, 80)], "behind army")


	# -------------------------------------------------------------- reporting

	func status() -> String:
		var a := army()
		var kinds := {}
		for u: Unit in a:
			kinds[u.display_name()] = kinds.get(u.display_name(), 0) + 1
		var hs := heroes().map(func(h: Unit) -> String: return "%s %d%%" % [h.display_name(), roundi(100.0 * h.health / h.max_health)])
		var aim := mode
		if mode == "attack" and not target.is_empty():
			aim += "->%s%s hp %.0f" % [target.get("name", ""), Vector2i(target.pos), target.o.health if is_instance_valid(target.o) else -1.0]
			var states := {}
			for u: Unit in a:
				var key := "%s:%s" % [Unit.State.keys()[u.state], u.target.display_name() if is_instance_valid(u.target) else "-"]
				states[key] = states.get(key, 0) + 1
			aim += " %s" % states
		var fields := MapObject.structures.filter(func(o: MapObject) -> bool: return o.is_field() and o.owner_index == me and o.is_alive())
		var worked := fields.filter(func(f: MapObject) -> bool: return UnitWork.field_worker(f) != null).size()
		return "FAIR t=%.0f mode %s goal %d res %s pop %d/%d workers %d farmers %d fields %d/%d army %d %s heroes %s support %d known %d visible %d buildings %d lost %d/%d" % [
				Sim.time(), aim, main.mission.goal, player.resources, player.population(), player.population_cap(), workers().size(),
				farmers().size(), worked, fields.size(), a.size(), kinds, hs, support().size(), _known.size(), _visible.size(), my_buildings().size(),
				lost_units, lost_buildings]
