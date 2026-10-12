class_name MissionDriver
extends Node
## A test tool for campaign missions (--scenario=drive with any --mission): pushes the
## mission to its win by cheating the script's conditions true, step by step, and watches
## the script answer. Instead of a playthrough bot per mission, it reads the triggers
## (MissionData) and works backwards from the ones that win (action 13 for the human):
## a condition on a flag, timer, variable or the countdown waits for the triggers that set
## it, so those are wanted too; a trigger whose such conditions all hold gets the rest
## cheated: units spawned or teleported into areas, enemies killed, resources added, a unit
## sent to look. Nothing is cheated that a losing trigger counts on (the human's heroes,
## a main building that must stand), and those are kept alive.
##
## Prints every trigger that fires and every message, and at the end one line:
##   DRIVE <set>/<code> WON at <t> s
##   DRIVE <set>/<code> STUCK at trigger <i> <name>: <condition>
##   DRIVE <set>/<code> LOST at <t> s: trigger <i> <name>
## (tools/campaign/drive_all.py runs it over the campaign.) Cheats change the game outside
## Sim steps: fine for a test, never for a game.

const CHECK_EVERY := 1.0  ## game seconds between looks at the script
const STUCK_AFTER := 300.0  ## game seconds without a trigger firing: stuck
const GIVE_UP_AFTER := 10800.0
const TIMER_CAP_MS := 15000  ## timers (and the countdown) the win waits for are cut to this
const DANGER_SECONDS := 60.0  ## a losing trigger this close to the end is never set off
const MAX_TRIES := 30  ## cheats of one condition that leave it false before giving up on it
const STORY_QUIET := 40.0  ## story mode: game seconds without a trigger firing before going for the win

const DEPENDENCIES := [4, 5, 16, 17, 18]  ## conditions other triggers make true
const COUNTS := [3, 7, 8, 9, 10, 11, 13, 14]
const IN_AREA := [3, 11, 13, 14]
const PEOPLES := ["ind", "mex", "des", "usa"]
const ARMY := {"ind": 160, "mex": 258, "des": 356, "usa": 458}
const MAIN_BUILDING := {"ind": 100, "mex": 200, "des": 300, "usa": 400}
const CATEGORIES := {0: "units", 1: "Native units", 2: "Mexican units", 3: "outlaw units", 4: "American units",
		5: "buildings", 6: "Native buildings", 7: "Mexican buildings", 8: "outlaw buildings",
		9: "American buildings", 16: "soldiers", 17: "Native soldiers", 18: "Mexican soldiers",
		19: "outlaw soldiers", 20: "American soldiers"}

var main: Main
var mission: Mission
var data: MissionData
var me := 0
var label := ""
## --drive=story: first every trigger the script may still fire on its way (that neither wins
## nor loses), then the win; the default goes straight for the win.
var story := false
## Triggers that win for the human, and those that only ever lead to losing.
var win: Array[int] = []
var lose: Array[int] = []
var lose_only := {}
var winning := {}  ## the win's triggers and those they wait on
## What sets what: "t<n>" timer, "f<n>" flag set, "c<n>" flag cleared, "v<n>" variable,
## "cd" the countdown -> trigger indices.
var _producers := {}
var fired: Array = []  ## [game seconds, trigger index]
var _last_progress := 0.0
var _tries := {}  ## "<trigger>:<condition>" -> cheats that left it false
var _notes := {}  ## "<trigger>:<condition>" -> why its cheat does not take
var _said := {}  ## cheats logged once
var _delays := {}
var _goals_shown := ""


func run() -> void:
	mission = main.mission
	if mission == null:
		print("DRIVE no mission (start with --mission=<set>/<code>)")
		return
	data = mission.data
	me = main.me
	label = "%s/%s" % [Match.campaign.get("set", "?"), Match.campaign.get("code", "?")]
	story = GameData.cmdline_option("drive") == "story"
	_analyse()
	mission.fired.connect(_on_fired)
	mission.message.connect(func(text: String, _seconds: float, _speech: String) -> void:
		print("DRIVE t=%.0f message: %s" % [Sim.time(), text.replace("\n", " ").left(110)]))
	print("DRIVE %s: human P%d, %d triggers; win %s, lose %s, lose-only %s" % [label, me, data.triggers.size(),
			win, lose, lose_only.keys()])
	_census()
	var next_check := 0.0
	var seen_fired := 0
	while true:
		await get_tree().physics_frame
		if fired.size() != seen_fired:  # after the triggers' actions (a new goal text)
			seen_fired = fired.size()
			_show_goals()
		if mission.outcome != 0:
			break
		var now := Sim.time()
		if now < next_check:
			continue
		next_check = now + CHECK_EVERY
		_protect()
		if now < data.triggers.size() * Mission.STEP_MS / 1000.0 + 1.0:
			continue  # the script's first pass (its opening triggers set flags) comes first
		var wanted := _plan()
		if wanted.is_empty():
			_finish_stuck(wanted, "no armed trigger leads to the win")
			return
		for i: int in wanted:
			if _can_cheat(i):
				_cheat_trigger(i)
		if now - _last_progress > STUCK_AFTER or now > GIVE_UP_AFTER:
			_finish_stuck(wanted, "")
			return
	if mission.outcome > 0:
		print("DRIVE %s WON at %.0f s" % [label, Sim.time()])
	else:
		var last := _last_fired_with(4)
		print("DRIVE %s LOST at %.0f s: trigger %d %s; fired before it: %s" % [label, Sim.time(), last,
				_name(last), _path_text(6)])


# ------------------------------------------------------------------ the script's graph

func _analyse() -> void:
	for i in data.triggers.size():
		for a in data.triggers[i].actions:
			var key := ""
			match a[0]:
				25: key = "t%d" % Mission._param(a, 1)
				12: key = "f%d" % Mission._param(a, 1)
				23: key = "c%d" % Mission._param(a, 1)
				33: key = "v%d" % Mission._param(a, 1)
				11: key = "cd"
				13:
					if Mission._param(a, 1) == me and i not in win:
						win.append(i)
				4:
					if Mission._param(a, 1) == me and i not in lose:
						lose.append(i)
			if key != "":
				if not _producers.has(key):
					_producers[key] = []
				if i not in _producers[key]:
					_producers[key].append(i)
	winning = _closure(win)
	for i: int in _closure(lose):
		if not winning.has(i):
			lose_only[i] = true


## The triggers `start` need, through the flags, timers, variables and countdown they wait for.
func _closure(start: Array[int]) -> Dictionary:
	var seen := {}
	var queue := start.duplicate()
	while not queue.is_empty():
		var i: int = queue.pop_front()
		if seen.has(i):
			continue
		seen[i] = true
		for c in data.triggers[i].conditions:
			for p: int in _producers.get(_need_key(c), []):
				queue.append(p)
	return seen


static func _need_key(c: PackedInt32Array) -> String:
	match c[0]:
		4: return "cd"
		5: return "f%d" % Mission._param(c, 1)
		16: return "t%d" % Mission._param(c, 1)
		17: return "v%d" % Mission._param(c, 1)
		18: return "c%d" % Mission._param(c, 1)
	return ""


## The armed triggers on the way to the win, the win's own first.
func _plan() -> Dictionary:
	var wanted := {}
	var queue: Array[int] = []
	if story and Sim.time() - _last_progress > STORY_QUIET:
		story = false
		print("DRIVE t=%.0f story told: on to the win" % Sim.time())
	if story:
		for i in data.triggers.size():
			if _story_trigger(i):
				queue.append(i)
		if queue.is_empty():
			story = false
	if not story:
		for i in win:
			if mission._armed[i]:
				queue.append(i)
	while not queue.is_empty():
		var i: int = queue.pop_front()
		if wanted.has(i):
			continue
		wanted[i] = true
		for c in _open_conditions(i):
			if c[0] not in DEPENDENCIES or _running(c):
				continue
			for p: int in _producers.get(_need_key(c), []):
				if mission._armed[p] and not lose_only.has(p) and not wanted.has(p):
					queue.append(p)
	return wanted


## In story mode, the armed triggers off the way to the win that neither lose, nor keep
## firing (stay armed), nor need the human's own people killed (the win's own come after).
func _story_trigger(i: int) -> bool:
	if not mission._armed[i] or winning.has(i) or lose_only.has(i):
		return false
	for a in data.triggers[i].actions:
		if a[0] == 10:
			return false
	for c in _open_conditions(i):
		if c[0] in [3, 11, 7, 9, 14] and (Mission._param(c, 1) == me or Diplomacy.allied(me, Mission._param(c, 1))) \
				and Mission.count(Mission._param(c, 1), Mission._param(c, 3), mission.area(Mission._param(c, 4)) if c[0] in IN_AREA else Rect2()) >= Mission._param(c, 2):
			return false
	return true


## The conditions of trigger `i` still to come true: all of those before an OR condition,
## and of those after it one (none when one holds already).
func _open_conditions(i: int) -> Array[PackedInt32Array]:
	var required: Array[PackedInt32Array] = []
	var options: Array[PackedInt32Array] = []
	var any := false
	for c in data.triggers[i].conditions:
		if c[0] == 15:
			any = true
		elif any:
			options.append(c)
		else:
			required.append(c)
	var open: Array[PackedInt32Array] = []
	for c in required:
		if not _holds(c):
			open.append(c)
	if not options.is_empty() and not options.any(_holds):
		open.append(_choose(i, options))
	return open


## Of the alternatives after an OR, the first a cheat may still make true.
func _choose(i: int, options: Array[PackedInt32Array]) -> PackedInt32Array:
	for c in options:
		if c[0] not in DEPENDENCIES and not _notes.has(_key(i, c)):
			return c
	for c in options:
		if c[0] in DEPENDENCIES and _producers.get(_need_key(c), []).any(func(p: int) -> bool: return mission._armed[p]):
			return c
	return options[0]


func _holds(c: PackedInt32Array) -> bool:
	if c[0] == 17:
		var v := Mission._param(c, 1)
		return v >= 0 and v < Mission.VARIABLES and mission._variables[v] == Mission._param(c, 2)
	if c[0] == 15:
		return false
	return mission._condition(c)


## A timer or the countdown that runs: wait for it (cut short when only the win waits on it).
func _running(c: PackedInt32Array) -> bool:
	if c[0] == 16:
		var t := Mission._param(c, 1)
		if t < 0 or t >= Mission.TIMERS or mission._timers[t] <= 0:
			return false
		if mission._timers[t] > TIMER_CAP_MS and not _lose_needs("t%d" % t):
			_say("timer %d cut from %d s to %d s" % [t, mission._timers[t] / 1000, TIMER_CAP_MS / 1000])
			mission._timers[t] = TIMER_CAP_MS
		return true
	if c[0] == 4:
		if not mission.countdown_running:
			return false
		var target := Mission._param(c, 1) + TIMER_CAP_MS / 1000
		if mission.countdown > target and not _lose_needs("cd"):
			_say("countdown cut from %d s to %d s" % [mission.countdown, target])
			mission.countdown = target
		return true
	return false


func _lose_needs(key: String) -> bool:
	for i: int in lose_only:
		for c in data.triggers[i].conditions:
			if _need_key(c) == key:
				return true
	return false


## Whether everything trigger `i` waits on from other triggers holds, so its own conditions
## may be cheated.
func _can_cheat(i: int) -> bool:
	for c in _open_conditions(i):
		if c[0] in DEPENDENCIES:
			return false
	return true


# ------------------------------------------------------------------ cheats

func _cheat_trigger(i: int) -> void:
	for c in _open_conditions(i):
		var key := _key(i, c)
		if _notes.has(key) and int(_tries.get(key, 0)) >= MAX_TRIES:
			continue
		var before := describe(c)
		var why := ""
		match c[0]:
			2, 12:
				why = _cheat_resource(c)
			6:
				why = _cheat_sight(c)
			3, 7, 8, 9, 10, 11, 13, 14:
				why = _cheat_count(c)
			1:
				pass
			_:
				why = "condition %d cannot be cheated" % c[0]
		if why == "" and not _holds(c):
			why = "still false after the cheat: " + describe(c)
		if why == "":
			print("DRIVE t=%.0f cheat for trigger %d %s: %s -> %s" % [Sim.time(), i, _name(i), before,
					describe(c).get_slice("(now ", 1).trim_suffix(")")])
		else:
			_notes[key] = why
		_tries[key] = int(_tries.get(key, 0)) + 1
		if int(_tries[key]) >= MAX_TRIES and not _notes.has(key):
			_notes[key] = "cheated %d times, still false" % MAX_TRIES


func _cheat_resource(c: PackedInt32Array) -> String:
	var people: Player = Player.by_index.get(Mission._param(c, 1))
	var resource: String = Mission.RESOURCES.get(Mission._param(c, 3), "")
	if people == null or resource == "":
		return "no player %d or resource %d" % [Mission._param(c, 1), Mission._param(c, 3)]
	var have := int(people.resources.get(resource, 0))
	var amount := Mission._param(c, 2)
	people.add(resource, amount - have if c[0] == 2 else amount - 1 - have)
	return ""


func _cheat_sight(c: PackedInt32Array) -> String:
	var player := Mission._param(c, 1)
	var rect := mission.area(Mission._param(c, 2))
	var unit := _pick_unit(player, -1, Rect2(), true)
	if unit == null:
		return "P%d has no unit to send" % player
	_teleport(unit, rect.get_center(), rect)
	return ""


## Counts: more of `what` (teleported in, else spawned) or fewer (killed; the human's own
## walk out of the area instead).
func _cheat_count(c: PackedInt32Array) -> String:
	var player := Mission._param(c, 1)
	var n := Mission._param(c, 2)
	var what := Mission._param(c, 3)
	var rect := mission.area(Mission._param(c, 4)) if c[0] in IN_AREA else Rect2()
	var now := Mission.count(player, what, rect)
	var low := n
	var high := n
	match c[0]:
		7, 9, 14:
			low = 0
			high = n - 1
		8, 10, 13:
			low = n + 1
			high = 1 << 30
	if now < low:
		return _add(player, what, rect, low - now)
	if now > high:
		return _remove(player, what, rect, now - high)
	return ""


func _add(player: int, what: int, rect: Rect2, amount: int) -> String:
	if _is_building(what):
		var guid: int = what if what >= 100 else MAIN_BUILDING.get(_people_of(player, what - 5), 100)
		var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
		if type == null:
			return "no building type for GUID %d" % guid
		var around := rect.get_center() if rect.has_area() else _home(player)
		for k in amount:
			var spot := _building_spot(type, rect, player) if rect.has_area() else AiBuilder.find_spot(type, around, 0)
			if spot == Vector2.INF:
				return "no room for %s in %s" % [_type_name(guid), _area_text(rect)]
			var risk := _would_lose([[player, guid, spot, 1]])
			if risk != "":
				return risk
			mission.create(guid, player, spot)
		return ""
	var left := amount
	var at := rect.get_center() if rect.has_area() else _home(player)
	if rect.has_area():
		while left > 0:
			var unit := _pick_unit(player, what, rect, false)
			if unit == null:
				break
			var risk := _would_lose([[player, unit.unit_type.guid(), unit.position, -1], [player, unit.unit_type.guid(), at, 1]])
			if risk != "":
				return risk
			_teleport(unit, at, rect)
			left -= 1
	if left <= 0:
		return ""
	var guid := _spawn_guid(player, what)
	if guid < 0:
		return "nothing to spawn for %s" % _type_name(what)
	var risk := _would_lose([[player, guid, at, left]])
	if risk != "":
		return risk
	var placed := _spawn(player, guid, at, rect, left)
	if placed == 0:
		return "%s for P%d: no unit type, or no walkable cell in %s" % [_type_name(guid), player, _area_text(rect)]
	return ""


## Where a building of `type` may go with its position inside `rect`, nearest the centre
## first; the centre itself when nothing fits (a cheat may squeeze it in).
func _building_spot(type: ObjectTypes.ObjectType, rect: Rect2, player: int) -> Vector2:
	var spots: Array[Vector2] = []
	for y in range(int(rect.position.y) + 16, int(rect.end.y), 32):
		for x in range(int(rect.position.x) + 16, int(rect.end.x), 32):
			spots.append(Vector2(x, y))
	var centre := rect.get_center()
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(centre) < b.distance_to(centre))
	for spot in spots:
		if BuildController.can_place_for(type, spot, player, true):  # where the player could put it
			return spot
	_say("no free ground for %s in %s: put at its centre" % [type.name, _area_text(rect)])
	return (centre / NavGrid.CELL).round() * NavGrid.CELL


func _remove(player: int, what: int, rect: Rect2, amount: int) -> String:
	var left := amount
	var risk := ""
	for unit: Unit in Unit.all_units.duplicate():
		if left <= 0:
			break
		if not unit.is_alive() or unit.team != player or not Mission.unit_matches(unit, what) \
				or (rect.has_area() and not rect.has_point(unit.position)):
			continue
		var guid := unit.unit_type.guid()
		var walk_out := (player == me or Diplomacy.allied(me, player)) and rect.has_area()
		var change := [[player, guid, unit.position, -1]]
		if walk_out:
			change.append([player, guid, _outside(rect), 1])
		var why := _would_lose(change)
		if why != "":
			risk = why
			continue
		if walk_out:
			_teleport(unit, _outside(rect), Rect2())
		else:
			_kill(unit)
		left -= 1
	if what < 100 or not (Mission._is_unit(what) or what in Mission.ANIMALS):
		for object: MapObject in MapObject.structures.duplicate():
			if left <= 0:
				break
			if object.owner_index != player or not object.is_alive() or not object.complete \
					or not (object.is_building() or object.is_field()) or not Mission.matches(object.guid, what) \
					or (rect.has_area() and not rect.has_point(object.position)):
				continue
			var why := _would_lose([[player, object.guid, object.position, -1]])
			if why != "":
				risk = why
				continue
			if object.is_building():
				object.take_damage(object.health + 1.0)
			else:
				object.forget()
				object.queue_free()
			left -= 1
	if left > 0:
		return "%d left: %s" % [left, risk] if risk != "" else "%d could not be removed" % left
	return ""


func _kill(unit: Unit) -> void:
	if unit.state == Unit.State.QUARTERED and unit.quarters and is_instance_valid(unit.quarters):
		unit.quarters.defence.release(unit)
	if unit.state == Unit.State.QUARTERED:
		unit.leave_quarters(unit.position)
	unit.take_damage(unit.health + 1e6, null, true)
	if unit.is_alive():
		unit.die()


func _teleport(unit: Unit, at: Vector2, within: Rect2) -> void:
	if unit.state == Unit.State.QUARTERED and unit.quarters and is_instance_valid(unit.quarters):
		unit.quarters.defence.release(unit)
	var cell := _free_cell(at, within)
	if cell.x < 0:
		cell = main.nav.nearest_walkable(main.nav.cell_of(at))
	unit.stop()
	unit.position = main.nav.center_of(cell)
	unit.guard_position = unit.position
	unit.reset_physics_interpolation()
	UnitGrid.invalidate()


## A walkable, empty cell near `at` (inside `within` when it is given).
func _free_cell(at: Vector2, within: Rect2) -> Vector2i:
	var nav := main.nav
	var centre := nav.cell_of(at)
	for ring in 40:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var cell := centre + Vector2i(dx, dy)
				if within.has_area() and not within.has_point(nav.center_of(cell)):
					continue
				if nav.is_walkable(cell) and not mission._occupied(cell):
					return cell
	return Vector2i(-1, -1)


func _spawn(player: int, guid: int, at: Vector2, within: Rect2, amount: int) -> int:
	var unit_type: UnitType = UnitType.load_type(UnitAnimal.COW_DIR) if guid == Mission.COW else UnitType.for_guid(guid)
	if unit_type == null:
		return 0
	var placed := 0
	for k in amount:
		var cell := _free_cell(at, within)
		if cell.x < 0:
			break
		var unit := Unit.new()
		unit.position = main.nav.center_of(cell)
		main.units_root.add_child(unit)
		unit.setup(unit_type, 0 if guid in [Mission.BUFFALO, Mission.WILD_HORSE] else player)
		if unit.animal.is_horse() and unit.team > 0:
			unit.animal.wild_timer = 1e9  # an owned riderless horse would run wild at once
		placed += 1
	return placed


## A unit of `player` matching `what` (-1: any) outside `rect`, the ones no losing trigger
## counts on first; `any_place` takes one anywhere.
func _pick_unit(player: int, what: int, rect: Rect2, any_place: bool) -> Unit:
	var best: Unit = null
	for unit in Unit.all_units:
		if not unit.is_alive() or unit.team != player or unit.water.is_boat():
			continue
		if what >= 0 and not Mission.unit_matches(unit, what):
			continue
		if not any_place and rect.has_point(unit.position):
			continue
		if what < 0 and unit.animal.is_horse() or what < 0 and unit.animal.is_cow():
			continue
		if best == null or (_protected(player, best.unit_type.guid(), best.position) \
				and not _protected(player, unit.unit_type.guid(), unit.position)):
			best = unit
	return best


## A point just outside `rect`, below it.
func _outside(rect: Rect2) -> Vector2:
	return Vector2(rect.get_center().x, rect.end.y + 48.0)


func _home(player: int) -> Vector2:
	for object in MapObject.structures:
		if object.owner_index == player and object.is_building() and object.guid in MapObject.MAIN_BUILDINGS:
			return object.position + Vector2(0, 96)
	for unit in Unit.all_units:
		if unit.team == player and unit.is_alive():
			return unit.position
	return Vector2(main.terrain.map.pixel_size()) / 2.0


func _people_of(player: int, category: int) -> String:
	if category >= 1 and category <= 4:
		return PEOPLES[category - 1]
	var people: Player = Player.by_index.get(player)
	return people.faction if people else "usa"


static func _is_building(what: int) -> bool:
	if what < 100:
		return what >= 5 and what <= 9
	return not Mission._is_unit(what) and what not in Mission.ANIMALS and not Mission.EITHER.has(what)


func _spawn_guid(player: int, what: int) -> int:
	if what >= 100:
		if Mission.EITHER.has(what):
			return Mission.EITHER[what][0]
		return Mission.HORSE if what == Mission.WILD_HORSE else what
	match what:
		0, 16:
			return ARMY.get(_people_of(player, 0), 458)
		1, 2, 3, 4:
			return ARMY[PEOPLES[what - 1]]
		17, 18, 19, 20:
			return ARMY[PEOPLES[what - 17]]
	return -1


# ------------------------------------------------------------------ what losing counts on

## Whether a losing trigger counts on objects of `guid` of `player` at `at` (fewer of them,
## or exactly some): those are kept whole, and teleported last.
func _protected(player: int, guid: int, at: Vector2) -> bool:
	for i: int in lose_only:
		for c in data.triggers[i].conditions:
			if c[0] in [3, 11, 7, 9, 14] and Mission._param(c, 1) == player and Mission.matches(guid, Mission._param(c, 3)):
				if c[0] in IN_AREA and not mission.area(Mission._param(c, 4)).has_point(at):
					continue
				return true
	return false


## The losing trigger a change would set off ("" none): `changes` are [player, guid, at,
## how many more (or fewer)]; only the triggers that lose soon (_dangerous) count.
func _would_lose(changes: Array) -> String:
	for i: int in lose_only:
		if _dangerous(i) and _holds_after(i, changes):
			return "losing trigger %d %s would fire" % [i, _name(i)]
	return ""


## Whether trigger `i`'s conditions would hold with `changes` made.
func _holds_after(i: int, changes: Array) -> bool:
	var any := false
	var result := false
	for c in data.triggers[i].conditions:
		if c[0] == 15:
			any = true
			continue
		result = _holds_with(c, changes)
		if not any and not result:
			return false
		if any and result:
			return true
	return result


func _holds_with(c: PackedInt32Array, changes: Array) -> bool:
	if c[0] not in COUNTS:
		return _holds(c)
	var player := Mission._param(c, 1)
	var what := Mission._param(c, 3)
	var rect := mission.area(Mission._param(c, 4)) if c[0] in IN_AREA else Rect2()
	var n := Mission.count(player, what, rect)
	for change: Array in changes:
		if change[0] == player and Mission.matches(change[1], what) and (not rect.has_area() or rect.has_point(change[2])):
			n += int(change[3])
	match c[0]:
		3, 11:
			return n == Mission._param(c, 2)
		7, 9, 14:
			return n < Mission._param(c, 2)
	return n > Mission._param(c, 2)


## Whether losing trigger `i` could lose the mission soon: what it waits on from other
## triggers (flags, timers) holds now, and from its firing to the end screen takes under DANGER_SECONDS
## (a countdown of eighteen minutes started on the way leaves time to win first).
func _dangerous(i: int) -> bool:
	if not mission._armed[i]:
		return false
	if not _delays.has(i):
		_delays[i] = _delay(i, {})
	if _delays[i] >= DANGER_SECONDS:
		return false
	for c in data.triggers[i].conditions:
		if c[0] in DEPENDENCIES and not _holds(c):
			return false
	return true


## Game seconds from trigger `i` firing to the human losing, the quickest way: through each
## losing trigger that waits on something `i` sets, as long as the longest of those waits.
func _delay(i: int, seen: Dictionary) -> float:
	if _delays.has(i):
		return _delays[i]
	if i in lose:
		return 0.0
	if seen.has(i):
		return INF
	seen[i] = true
	var sets := {}  # what `i` sets -> seconds until it holds
	for a in data.triggers[i].actions:
		match a[0]:
			25: sets["t%d" % Mission._param(a, 1)] = float(Mission._param(a, 2))
			12: sets["f%d" % Mission._param(a, 1)] = 0.0
			23: sets["c%d" % Mission._param(a, 1)] = 0.0
			33: sets["v%d" % Mission._param(a, 1)] = 0.0
			11: sets["cd"] = float(Mission._param(a, 1))
	var best := INF
	for j: int in lose_only:
		var wait := -1.0
		for c in data.triggers[j].conditions:
			var key := _need_key(c)
			if sets.has(key):
				wait = maxf(wait, maxf(0.0, sets[key] - (Mission._param(c, 1) if c[0] == 4 else 0.0)))
		if wait >= 0.0:
			best = minf(best, wait + _delay(j, seen))
	seen.erase(i)
	return best


## Units and buildings losing triggers count on stay whole.
func _protect() -> void:
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team > 0 and unit.health < unit.max_health * 0.6 \
				and _protected(unit.team, unit.unit_type.guid(), unit.position):
			unit.health = unit.max_health
			_say("keeping P%d's %s alive" % [unit.team, unit.display_name()])
	for object in MapObject.structures:
		if object.is_building() and object.is_alive() and object.complete and object.owner_index > 0 \
				and object.health < object.max_health * 0.6 and _protected(object.owner_index, object.guid, object.position):
			object.health = object.max_health
			_say("keeping P%d's %s standing" % [object.owner_index, object.display_name()])


# ------------------------------------------------------------------ reporting

## What every player has at the start, by GUID (* under construction).
func _census() -> void:
	for slot in data.players:
		var have := {}
		for unit in Unit.all_units:
			if unit.is_alive() and unit.team == slot.index:
				var g := unit.unit_type.guid()
				have[g] = int(have.get(g, 0)) + 1
		for object in MapObject.structures:
			if object.owner_index == slot.index and object.is_building() and object.is_alive():
				var g := "%d%s" % [object.guid, "" if object.complete else "*"]
				have[g] = int(have.get(g, 0)) + 1
		print("DRIVE P%d %s %s: %s" % [slot.index, slot.faction, MissionData.Seat.keys()[slot.control],
				" ".join(have.keys().map(func(g: Variant) -> String: return "%s:%d" % [g, have[g]]))])


func _on_fired(index: int) -> void:
	fired.append([Sim.time(), index])
	_last_progress = Sim.time()
	print("DRIVE t=%.0f fired %d %s%s: %s" % [Sim.time(), index, _name(index),
			" (lose)" if index in lose else (" (win)" if index in win else ""),
			", ".join(data.triggers[index].actions.map(func(a: PackedInt32Array) -> String: return str(Array(a))))])


## The goals page's list when it changed: "[x]" crossed out (data/campaign_goals.json).
func _show_goals() -> void:
	var line := " | ".join(MissionGoals.of(mission).goals.map(func(g: Dictionary) -> String:
		return ("[x] " if g.done else "[ ] ") + String(g.text).left(60)))
	if line != _goals_shown:
		_goals_shown = line
		print("DRIVE t=%.0f goals: %s" % [Sim.time(), line])


func _finish_stuck(wanted: Dictionary, why: String) -> void:
	print("DRIVE diagnosis at %.0f s (fired: %s)" % [Sim.time(), _path_text(12)])
	var blame := -1
	var blame_condition := why
	var order := wanted.keys()
	order.reverse()  # the deepest first: what the rest waits for
	for i: int in order:
		var open := _open_conditions(i)
		print("  trigger %d %s%s: ready %s" % [i, _name(i), " (win)" if i in win else "", _can_cheat(i)])
		for c in open:
			var text := describe(c) + _why(i, c)
			print("    false: " + text)
			if blame < 0:
				blame = i
				blame_condition = text
	if blame < 0 and not win.is_empty():
		blame = win[0]
		if blame_condition == "":
			blame_condition = "all conditions hold but it does not fire"
	print("DRIVE %s STUCK at trigger %d %s: %s" % [label, blame, _name(blame), blame_condition])


func _why(i: int, c: PackedInt32Array) -> String:
	var key := _key(i, c)
	if _notes.has(key):
		return " (%s)" % _notes[key]
	if c[0] in DEPENDENCIES:
		var by: Array = _producers.get(_need_key(c), [])
		if by.is_empty():
			return " (no trigger sets it)"
		var states := by.map(func(p: int) -> String:
			return "%d %s" % [p, "armed" if mission._armed[p] else ("fired" if fired.any(func(f: Array) -> bool: return f[1] == p) else "disarmed")] \
					+ (" lose-only" if lose_only.has(p) else ""))
		return " (set by %s)" % ", ".join(states)
	if c[0] in COUNTS:
		var what := Mission._param(c, 3)
		if what >= 100 and Mission.count(Mission._param(c, 1), what) == 0 and not _is_building(what) \
				and _spawn_guid(Mission._param(c, 1), what) >= 0 and UnitType.for_guid(_spawn_guid(Mission._param(c, 1), what)) == null:
			return " (no such unit exists and none can be made)"
	return ""


func describe(c: PackedInt32Array) -> String:
	var p1 := Mission._param(c, 1)
	var p2 := Mission._param(c, 2)
	var p3 := Mission._param(c, 3)
	match c[0]:
		1:
			return "always"
		2, 12:
			var people: Player = Player.by_index.get(p1)
			var resource: String = Mission.RESOURCES.get(p3, "?")
			return "P%d %s %s %d (now %d)" % [p1, resource, ">=" if c[0] == 2 else "<", p2,
					int(people.resources.get(resource, 0)) if people else 0]
		3, 11, 7, 9, 8, 10, 13, 14:
			var rect := mission.area(Mission._param(c, 4)) if c[0] in IN_AREA else Rect2()
			var where := " in area %d '%s'" % [Mission._param(c, 4), data.area_names.get(Mission._param(c, 4), "whole map")] \
					if c[0] in IN_AREA else ""
			var op := "==" if c[0] in [3, 11] else ("<" if c[0] in [7, 9, 14] else ">")
			return "count(P%d, %s%s) %s %d (now %d)" % [p1, _type_name(p3), where, op, p2, Mission.count(p1, p3, rect)]
		4:
			return "countdown < %d s (now %s)" % [p1, str(mission.countdown) if mission.countdown_running else "not running"]
		5:
			return "flag %d set" % p1
		18:
			return "flag %d clear" % p1
		6:
			return "P%d sees area %d '%s'" % [p1, p2, data.area_names.get(p2, "whole map")]
		15:
			return "or"
		16:
			var t := mission._timers[p1] if p1 >= 0 and p1 < Mission.TIMERS else -1
			return "timer %d run out (now %s)" % [p1, "stopped" if t < 0 else "%.1f s" % (t / 1000.0)]
		17:
			return "variable %d == %d (now %d)" % [p1, p2, mission._variables[p1] if p1 >= 0 and p1 < Mission.VARIABLES else -1]
	return "condition %s" % str(Array(c))


func _type_name(what: int) -> String:
	if what < 100:
		return CATEGORIES.get(what, "category %d" % what)
	var name := String(GameData.stats(what).get("name", ""))
	match what:
		Mission.HORSE: name = "horses"
		Mission.BUFFALO: name = "buffalo"
		Mission.COW: name = "cows"
		Mission.WILD_HORSE: name = "wild horses"
	if Mission.EITHER.has(what):
		name = "%s (on foot or mounted)" % String(GameData.stats(Mission.EITHER[what][0]).get("name", "?"))
	return "%d %s" % [what, name if name != "" else "?"]


func _area_text(rect: Rect2) -> String:
	return "the area at %s" % rect if rect.has_area() else "the map"


func _name(i: int) -> String:
	if i < 0 or i >= data.triggers.size():
		return ""
	return "'%s'" % data.triggers[i].name.replace("\n", " ").replace("\r", "").left(40)


func _path_text(last: int) -> String:
	return ", ".join(fired.slice(maxi(0, fired.size() - last)).map(func(f: Array) -> String: return "%d@%.0f" % [f[1], f[0]]))


func _last_fired_with(action: int) -> int:
	for k in range(fired.size() - 1, -1, -1):
		for a in data.triggers[fired[k][1]].actions:
			if a[0] == action:
				return fired[k][1]
	return -1


func _say(text: String) -> void:
	if not _said.has(text):
		_said[text] = true
		print("DRIVE t=%.0f cheat: %s" % [Sim.time(), text])


static func _key(i: int, c: PackedInt32Array) -> String:
	return "%d:%s" % [i, str(Array(c))]
