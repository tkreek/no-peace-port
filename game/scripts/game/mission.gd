class_name Mission
extends Node
## A campaign map's script (MissionData.triggers) at work, as the original runs it
## (AmericaAddOn.exe 0x464ed0): every 20 ms the 50 timers count down and the next armed
## trigger in turn is checked; when its conditions hold it disarms and does its actions.
## Everything here is game state, stepped by Sim, so a mission plays the same on every
## machine; what the local player sees and hears goes through `messages` (the interface).
##
## docs/technical/missions.md lists the conditions and actions.

signal ended(won: bool)
## A text (and maybe speech) for the local player: text, seconds on screen, speech asset.
signal message(text: String, seconds: float, speech: String)
signal goal_changed(text: String)

## The original's script step.
const STEP_MS := 20
const TIMERS := 50
const FLAGS := 100
const VARIABLES := 20
## People who join a unit of a people neutral to theirs that comes this close (0x42c580).
const JOIN_REACH := 96.0
const JOIN_CHECK_STEPS := 25
## The original's end of a mission: won or lost, the game goes on this long.
const END_DELAY_MS := 6000

## Resource selector in conditions and actions (2 wood: the first tutorial's 100 wood more).
const RESOURCES := {1: "food", 2: "wood", 3: "horses", 4: "gold", 5: "guns"}
## Object categories below 100 (0x42a0b0): units, buildings, soldiers; all peoples or one.
const UNIT_RANGES := [[150, 173], [250, 267], [350, 380], [450, 469]]
const BUILDING_RANGES := [[100, 117], [200, 222], [300, 319], [400, 428]]
const SOLDIERS := [
	[150, 151, 156, 157, 158, 159, 160, 161, 162, 163, 164, 172],
	[250, 251, 258, 259, 260, 261, 262, 263, 264, 265, 266],
	[350, 351, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 369],
	[450, 451, 458, 459, 460, 461, 462, 463, 464, 465, 468],
]
## GUIDs that count a unit on foot and on horseback together.
const EITHER := {165: [150, 151], 166: [156, 157], 167: [158, 159], 168: [160, 161],
		267: [259, 260], 268: [263, 264], 269: [250, 251], 365: [350, 351], 366: [353, 354],
		367: [356, 357], 368: [361, 362], 475: [450, 451], 476: [459, 460], 477: [463, 464],
		478: [466, 467]}
const HORSE := 480
const BUFFALO := 481
const COW := 482
const WILD_HORSE := 483  ## a horse of nobody's
const ANIMALS := [HORSE, BUFFALO, COW, WILD_HORSE]

var data: MissionData
var main: Main
## Texts the script shows (text2.eng of its campaign) and its speech folder.
var texts := {}
var speech_dir := ""
var goal := -1  ## the text id the "Mission goals" button shows
var clock_shown := false
var countdown := 0  ## seconds
var countdown_running := false
var outcome := 0  ## 1 won, -1 lost (the local player's)

var _armed: Array[bool] = []
var _cursor := 0
var _running := true
var _timers := PackedInt32Array()
var _flags := PackedByteArray()
var _variables := PackedInt32Array()
var _countdown_ms := 1000
var _budget := 0  # thirds of a millisecond of script time owed
var _join_wait := 0
var _end_at := -1
## AI modules the script started: [player, module number].
var started_modules: Array[PackedInt32Array] = []
var _sim_on := false
var _sim_listed := false
var _trace := GameData.cmdline_option("trace-mission") != ""  ## --trace-mission=1: print what fires


func setup(mission: MissionData, game: Main, text_table: Dictionary, speech_folder: String) -> void:
	data = mission
	main = game
	texts = text_table
	speech_dir = speech_folder
	_armed.resize(data.triggers.size())
	_armed.fill(true)
	_timers.resize(TIMERS)
	_timers.fill(-1)
	_flags.resize(FLAGS)
	_variables.resize(VARIABLES)
	_variables.fill(-1)
	Sim.activate(self)


func text(id: int) -> String:
	return String(texts.get(str(id), "")).replace("@", "\n").replace("#", " ")


func goal_text() -> String:
	return text(goal) if goal >= 0 else ""


## One game step: the script time it covers, in the original's 20 ms steps.
func sim_tick(_delta: float) -> void:
	if _end_at >= 0 and Sim.msec() >= _end_at:
		_end_at = -1
		ended.emit(outcome > 0)
	_budget += 1000  # a game step in 1/30 ms (Sim.RATE steps a second)
	while _budget >= STEP_MS * Sim.RATE:
		_budget -= STEP_MS * Sim.RATE
		_step()
	_join_wait -= 1
	if _join_wait <= 0:
		_join_wait = JOIN_CHECK_STEPS
		_join_neutrals()


func _step() -> void:
	for i in TIMERS:
		if _timers[i] > 0:
			_timers[i] = maxi(0, _timers[i] - STEP_MS)
	if countdown_running:
		_countdown_ms -= STEP_MS
		if _countdown_ms <= 0:
			_countdown_ms = 1000
			if countdown > 0:
				countdown -= 1
	if not _running or data.triggers.is_empty():
		return
	var count := data.triggers.size()
	var at := _cursor
	while not _armed[at]:
		at = (at + 1) % count
		if at == _cursor:
			_running = false  # nothing armed: the script is over
			return
	_check(at)
	_cursor = (at + 1) % count


func _check(index: int) -> void:
	var trigger: MissionData.Trigger = data.triggers[index]
	var any := false  # an OR condition switches from all to any
	var result := (index & 0xFF) != 0  # no conditions at all: what the original's register held
	for condition in trigger.conditions:
		if condition[0] == 17:  # a variable: unset is false, another value disarms the trigger
			var value := _variables[_param(condition, 1)] if _param(condition, 1) < VARIABLES else -1
			if value != -1 and value != _param(condition, 2):
				_armed[index] = false
				return
			result = value != -1
		else:
			result = _condition(condition)
			if condition[0] == 15:
				any = true
		if not any and not result:
			return
		if any and result:
			break
	if not result:
		return
	_armed[index] = false
	if _trace:
		print("MISSION t=%.1f trigger %d %s: %s" % [Sim.time(), index, trigger.name,
				", ".join(trigger.actions.map(func(a: PackedInt32Array) -> String: return str(Array(a))))])
	for action in trigger.actions:
		if _action(action):
			_armed[index] = true


static func _param(item: PackedInt32Array, at: int) -> int:
	return item[at] if at < item.size() else 0


# ------------------------------------------------------------------ conditions

func _condition(c: PackedInt32Array) -> bool:
	var p1 := _param(c, 1)
	var p2 := _param(c, 2)
	var p3 := _param(c, 3)
	match c[0]:
		1:
			return true
		2:
			return _resource(p1, _param(c, 3)) >= p2
		3, 11:
			return count(p1, p3, area(_param(c, 4))) == p2
		4:
			return countdown_running and countdown < p1
		5:
			return p1 >= 0 and p1 < FLAGS and _flags[p1] != 0
		6:
			return sees(p1, area(p2))
		7, 9:
			return count(p1, p3) < p2
		8, 10:
			return count(p1, p3) > p2
		12:
			return _resource(p1, p3) < p2
		13:
			return count(p1, p3, area(_param(c, 4))) > p2
		14:
			return count(p1, p3, area(_param(c, 4))) < p2
		15:
			return false
		16:
			return p1 >= 0 and p1 < TIMERS and _timers[p1] == 0
		18:
			return p1 >= 0 and p1 < FLAGS and _flags[p1] == 0
	push_warning("Mission: unknown condition %d" % c[0])
	return false


func area(id: int) -> Rect2:
	return data.area(id, Vector2(main.terrain.map.pixel_size()))


func _resource(player: int, which: int) -> int:
	var people: Player = Player.by_index.get(player)
	return int(people.resources.get(RESOURCES.get(which, ""), 0)) if people else 0


## How many of `what` (a GUID, a GUID for mounted and on foot, or a category below 100)
## people `player` has, within `rect` when one is given; buildings once they stand
## (the first tutorial's "now the chief's tepee is standing"). Animals: horses and cows by
## owner, buffalo whoever they belong to.
func count(player: int, what: int, rect := Rect2()) -> int:
	var within := rect.has_area()
	var total := 0
	if what < 100 or _is_unit(what) or EITHER.has(what) or what in ANIMALS:
		for unit in Unit.all_units:
			if unit.is_alive() and (unit.team == player or what == BUFFALO) and unit_matches(unit, what) \
					and (not within or rect.has_point(unit.position)):
				total += 1
	if what < 100 or not (_is_unit(what) or what in ANIMALS):  # buildings and fields
		for object in MapObject.structures:
			if object.owner_index == player and (object.is_building() or object.is_field()) and object.is_alive() and object.complete \
					and matches(object.guid, what) and (not within or rect.has_point(object.position)):
				total += 1
	return total


## Whether `unit` counts as `what` (animals by their kind).
static func unit_matches(unit: Unit, what: int) -> bool:
	match what:
		HORSE, WILD_HORSE:
			return unit.animal.is_horse()
		COW:
			return unit.animal.is_cow()
		BUFFALO:
			return unit.unit_type.guid() == BUFFALO
	return matches(unit.unit_type.guid(), what)


static func _is_unit(guid: int) -> bool:
	return guid % 100 >= 50 and guid < 500


static func _in(guid: int, ranges: Array) -> bool:
	for r in ranges:
		if guid >= r[0] and guid < r[1]:
			return true
	return false


## Whether an object of `guid` counts as `what`.
static func matches(guid: int, what: int) -> bool:
	if what >= 100:
		return guid == what or (EITHER.has(what) and guid in EITHER[what])
	match what:
		0:
			return _in(guid, UNIT_RANGES)
		1, 2, 3, 4:
			return _in(guid, [UNIT_RANGES[what - 1]])
		5:
			return _in(guid, BUILDING_RANGES)
		6, 7, 8, 9:
			return _in(guid, [BUILDING_RANGES[what - 6]])
		16:
			return SOLDIERS.any(func(list: Array) -> bool: return guid in list)
		17, 18, 19, 20:
			return guid in SOLDIERS[what - 17]
	return false


## Whether anything of people `player` has part of `rect` in sight.
func sees(player: int, rect: Rect2) -> bool:
	for unit in Unit.all_units:
		if unit.team == player and unit.is_alive() \
				and unit.position.distance_to(unit.position.clamp(rect.position, rect.end)) <= unit.sight():
			return true
	for object in MapObject.structures:
		if object.owner_index == player and object.is_building() and object.is_alive():
			var at := object.footprint_rect().get_center()
			if at.distance_to(at.clamp(rect.position, rect.end)) <= FogOfWar.building_sight(object):
				return true
	return false


# ------------------------------------------------------------------ actions

## Does one action; true when the trigger should stay armed.
func _action(a: PackedInt32Array) -> bool:
	var p1 := _param(a, 1)
	var p2 := _param(a, 2)
	var p3 := _param(a, 3)
	var p4 := _param(a, 4)
	match a[0]:
		1:
			started_modules.append(PackedInt32Array([p1, p2]))
			main.start_ai_module(p1, p2)
		2:
			if p1 == main.me:
				main.camera.position = area(p2).get_center()
		3:
			spawn(p1, p2, p3, area(p4).get_center())
		4:
			_finish(p1, false)
		5:
			if p2 == main.me:
				message.emit(text(p1), float(p3), "")
		6, 34:
			remove(p1, p2, area(p3))
		9:
			if main.me > 0:
				var speech := "%s/%03d.mp3" % [speech_dir, p1]
				message.emit(text(p1), -1.0, speech if speech_dir != "" and GameData.exists(speech) else "")
		10:
			return true
		11:
			countdown = p1
			countdown_running = true
			_countdown_ms = 1000
		12:
			if p1 >= 0 and p1 < FLAGS:
				_flags[p1] = 1
		13:
			_finish(p1, true)
		14:
			create(p1, 0, Vector2(p2, p3))
		15:
			clock_shown = true
		16:
			clock_shown = false
		17:
			pass  # pause the world for a while: no mission uses it
		18:
			Orders.locked = true
		19:
			Orders.locked = false
		20:
			if p1 == main.me and main.fog:
				main.fog.revealed_areas[p2] = area(p2)
				main.fog.update_now()
		21, 22:
			var people: Player = Player.by_index.get(p1)
			if people and RESOURCES.has(p3):
				people.add(RESOURCES[p3], p2 if a[0] == 21 else -p2)
		23:
			if p1 >= 0 and p1 < FLAGS:
				_flags[p1] = 0
		24:
			if p1 == main.me and main.fog:
				main.fog.revealed_areas.erase(p2)
				main.fog.update_now()
		25:
			if p1 >= 0 and p1 < TIMERS:
				_timers[p1] = p2 * 1000
		26:
			if p1 >= 0 and p1 < TIMERS:
				_timers[p1] = -1
		27:
			goal = p1
			goal_changed.emit(goal_text())
		28, 29:
			Diplomacy.share_vision(p1, p2, a[0] == 28)
		30:
			Diplomacy.set_stance(p1, p2, Diplomacy.ALLY)
		31:
			Diplomacy.set_stance(p1, p2, Diplomacy.ENEMY)
		32:
			Diplomacy.set_stance(p1, p2, Diplomacy.NEUTRAL)
		33:
			if p1 >= 0 and p1 < VARIABLES and p2 > 0:
				_variables[p1] = Sim.randi_below(p2)
		35:
			convert_owner(p1, area(p2), p3)
		36:
			create(p1, p4, Vector2(p2, p3))
		7, 8:
			pass
		_:
			push_warning("Mission: unknown action %d" % a[0])
	return false


func _finish(player: int, won: bool) -> void:
	if player != main.me or outcome != 0:
		return
	outcome = 1 if won else -1
	_end_at = Sim.msec() + END_DELAY_MS
	Sound.play_mission_result(won)


## `amount` units of `guid` for people `player` around `at`.
func spawn(player: int, amount: int, guid: int, at: Vector2) -> void:
	if guid in [BUFFALO, COW, WILD_HORSE]:  # nobody's (0x42c710); a horse keeps its owner
		player = 0
		if guid == WILD_HORSE:
			guid = HORSE
	var unit_type := UnitType.for_guid(guid)
	if unit_type == null:
		push_warning("Mission: no unit for GUID %d" % guid)
		return
	var nav := main.nav
	var centre := nav.cell_of(at)
	var placed := 0
	var ring := 0
	while placed < amount and ring < 30:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if placed >= amount or (absi(dx) != ring and absi(dy) != ring):
					continue
				var cell := centre + Vector2i(dx, dy)
				if not nav.is_walkable(cell) or _occupied(cell):
					continue
				var unit := Unit.new()
				unit.position = nav.center_of(cell)
				main.units_root.add_child(unit)
				unit.setup(unit_type, player)
				placed += 1
		ring += 1


func _occupied(cell: Vector2i) -> bool:
	var at := main.nav.center_of(cell)
	for unit: Unit in UnitGrid.near(at, 12.0):
		if unit.is_alive() and unit.position.distance_to(at) < 12.0:
			return true
	return false


## An object (building or unit) of `guid` for `player` standing at `at`, complete.
func create(guid: int, player: int, at: Vector2) -> void:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	if type == null:
		push_warning("Mission: no object for GUID %d" % guid)
		return
	if type.kind == ObjectTypes.Kind.UNIT:
		spawn(player, 1, guid, at)
		return
	var object := MapObject.new()
	object.position = at
	if not object.setup(type, player):
		object.free()
		return
	main.units_root.add_child(object)
	main.nav.block_footprint(type, at)


## Takes `what` of people `player` inside `rect` off the map.
func remove(player: int, what: int, rect: Rect2) -> void:
	for unit in Unit.all_units.duplicate():
		if unit.team == player and unit.is_alive() and rect.has_point(unit.position) and unit_matches(unit, what):
			unit.selected = false
			unit.queue_free()
	for object in MapObject.structures.duplicate():
		if object.owner_index == player and object.is_building() and rect.has_point(object.position) \
				and matches(object.guid, what):
			main.nav.unblock_footprint(object.object_type, object.position)
			object.forget()
			object.queue_free()


## Everything of `what` inside `rect` that belongs to another people goes over to `player`.
func convert_owner(what: int, rect: Rect2, player: int) -> void:
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team > 0 and unit.team != player and rect.has_point(unit.position) \
				and unit_matches(unit, what):
			unit.change_team(player)
	for object in MapObject.structures:
		if object.is_building() and object.owner_index > 0 and object.owner_index != player \
				and rect.has_point(object.position) and matches(object.guid, what):
			object.capture(player)


## Units of a people neutral to a passer-by's join the passer-by (the original's
## independent tribesmen: a unit of yours walks up and they are yours).
func _join_neutrals() -> void:
	var any := false
	for p in data.players:
		for q in data.players:
			if Diplomacy.neutral(p.index, q.index):
				any = true
	if not any:
		return
	for unit in Unit.all_units:
		if not unit.is_alive() or unit.team <= 0:
			continue
		var slot := data.player(unit.team)
		if slot and slot.control == MissionData.Seat.INDEPENDENT:
			continue
		for other: Unit in UnitGrid.near(unit.position, JOIN_REACH):
			if other.is_alive() and Diplomacy.neutral(unit.team, other.team) \
					and other.position.distance_to(unit.position) <= JOIN_REACH:
				other.change_team(unit.team)


# ------------------------------------------------------------------ saving

func save_state() -> Dictionary:
	return {"armed": _armed.map(func(b: bool) -> int: return int(b)), "cursor": _cursor, "running": _running,
			"timers": Array(_timers), "flags": Array(_flags), "vars": Array(_variables), "goal": goal,
			"clock": clock_shown, "countdown": countdown, "counting": countdown_running,
			"countdown_ms": _countdown_ms, "budget": _budget, "outcome": outcome, "end_at": _end_at,
			"modules": started_modules.map(func(m: PackedInt32Array) -> Array: return Array(m))}


func restore_state(state: Dictionary) -> void:
	for i in mini(_armed.size(), state.armed.size()):
		_armed[i] = int(state.armed[i]) != 0
	_cursor = int(state.cursor)
	_running = bool(state.running)
	_timers = PackedInt32Array(state.timers)
	_flags = PackedByteArray(state.flags)
	_variables = PackedInt32Array(state.vars)
	goal = int(state.goal)
	clock_shown = bool(state.clock)
	countdown = int(state.countdown)
	countdown_running = bool(state.counting)
	_countdown_ms = int(state.countdown_ms)
	_budget = int(state.budget)
	outcome = int(state.outcome)
	_end_at = int(state.end_at)
	started_modules.clear()
	for m in state.get("modules", []):
		started_modules.append(PackedInt32Array(m))
	goal_changed.emit(goal_text())
