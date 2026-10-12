class_name MissionStats
extends RefCounted
## --mission-stats=<json path>: what a campaign mission's script and its KI modules did, for
## tools/campaign/runtime_report.py. Triggers checked and fired, actions done, natives called
## and the ones that came to nothing (a dead handle, no building spot, a refused order, a
## search that found nothing), modules started and where they are at the end, semaphores
## left taken, wall-clock cost per game minute and what every people has at the start and
## the end. Written when DevTools ends the run.
##
## Only observes: nothing here feeds back into the game (the wall-clock times included), and
## with the option off the hooks are a test of `on`.

static var on := false
static var path := ""

## Natives whose first argument is a unit given an order, and those that also name a target
## (the kind it has to be: "unit", "object" or "" for any).
const UNIT_ORDERS := [130, 131, 133, 135, 143, 144, 145, 146, 147, 148, 149, 211, 212, 213, 214,
		215, 216, 250, 251, 252, 253, 292, 311, 320, 321, 322, 323, 324, 325, 326, 327, 328, 336,
		341, 342, 343, 344, 346, 358, 360, 361, 374]
const TARGETS := {130: "object", 131: "object", 133: "object", 144: "object", 145: "", 149: "",
		211: "object", 212: "object", 213: "unit", 250: "", 251: "", 252: "object", 253: "unit",
		322: "", 323: "", 324: "", 325: "object", 326: "unit", 343: "object", 344: "object",
		346: "unit", 360: "object", 361: "object", 374: "unit"}
const BUILDING_ORDERS := [138, 142, 210, 338, 348, 351, 355]
## Questions about one object (the existence tests 110-112 are left out: a dead handle is
## what they are for).
const QUERIES := [101, 102, 103, 104, 105, 106, 113, 114, 115, 116, 117, 118, 123, 124, 125, 132,
		217, 218, 295, 296, 297, 300, 303, 306, 307, 312, 337, 353, 356, 359, 365, 366, 367, 373,
		379, 380, 394]
## Searches: 0 found nothing.
const SEARCHES := [107, 108, 109, 120, 121, 122, 139, 140, 141, 200, 201, 202, 203, 204, 205,
		228, 368, 370, 371, 372, 383, 384, 385, 386, 387, 389, 392, 393, 394, 395, 398]
## "Can I have this": 0 is a refusal worth seeing per GUID.
const CAN_HAVE := [136, 137, 290, 291]
## Natives the remake answers with a constant or ignores on purpose.
const STUBS := [229, 230, 231, 232, 345, 347, 357, 399, 400, 401]

static var _mission: Mission
static var _checked := PackedInt32Array()
static var _fired := PackedInt32Array()
static var _first := PackedFloat32Array()
static var _actions := {}  # opcode -> count
static var _endings: Array = []  # {t, op, player}
static var _script_modules: Array = []  # [player, module] the script started (its action 1)
static var _natives := {}  # id -> calls
static var _native_usec := {}  # id -> wall-clock usec spent in it
static var _native_clock := 0
static var _failures := {}  # id -> {reason -> {module -> count}}
static var _unimplemented := {}  # id -> {module -> count}
static var _modules := {}  # module number -> counters (see _module)
static var _waits := {}  # KiTask -> game time it began waiting for a semaphore
static var _locks := {}  # "player:sem" -> [module, game time] of the last taker
static var _cost := {}  # game minute -> [KI usec, trigger usec]
static var _start_state := {}
static var _depth := 0  # stack depth after a native popped its arguments


## A mission begins (Main._start_mission): on when --mission-stats names a file.
static func begin(mission: Mission, file: String) -> void:
	path = file
	on = file != ""
	if not on:
		return
	_mission = mission
	var n := mission.data.triggers.size()
	_checked = PackedInt32Array()
	_checked.resize(n)
	_fired = PackedInt32Array()
	_fired.resize(n)
	_first = PackedFloat32Array()
	_first.resize(n)
	_first.fill(-1.0)
	for d in [_actions, _natives, _native_usec, _failures, _unimplemented, _modules, _waits, _locks, _cost]:
		d.clear()
	_endings.clear()
	_script_modules.clear()
	_start_state = _peoples()


# ------------------------------------------------------------------ the script

static func checked(index: int) -> void:
	_checked[index] += 1


static func fired(index: int) -> void:
	_fired[index] += 1
	if _first[index] < 0.0:
		_first[index] = Sim.time()


static func action(a: PackedInt32Array) -> void:
	_actions[a[0]] = _actions.get(a[0], 0) + 1
	if a[0] == 1 and a.size() > 2:
		_script_modules.append([a[1], a[2]])
	if a[0] == 4 or a[0] == 13:
		_endings.append({"t": Sim.time(), "op": a[0], "player": a[1] if a.size() > 1 else 0})


## Wall-clock time since `since` (usec) spent on the KI (0) or the triggers (1).
static func cost(which: int, since: int) -> void:
	var minute := int(Sim.time() / 60.0)
	if not _cost.has(minute):
		_cost[minute] = [0, 0]
	_cost[minute][which] += Time.get_ticks_usec() - since


# ------------------------------------------------------------------ modules

static func _module(number: int) -> Array:
	if not _modules.has(number):
		# started, not found, slots full, instructions, ticks blocked, ticks asleep,
		# ticks paused by another's atomic section, finished, gosubs to a missing module,
		# started for a player who is not in the mission
		_modules[number] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	return _modules[number]


static func started(number: int, why_not: String) -> void:
	_module(number)[{"": 0, "missing": 1, "full": 2, "no player": 9}[why_not]] += 1


static func stepped(task: KiTask) -> void:
	_module(task.module.number)[3] += 1


static func blocked(task: KiTask) -> void:
	_module(task.module.number)[4] += 1
	if not _waits.has(task):
		_waits[task] = Sim.time()


static func acquired(task: KiTask, semaphore: int) -> void:
	_waits.erase(task)
	_locks["%d:%d" % [task.player.index, semaphore]] = [task.module.number, Sim.time()]


static func asleep(task: KiTask) -> void:
	_module(task.module.number)[5] += 1


static func paused(task: KiTask) -> void:
	_module(task.module.number)[6] += 1


static func finished(task: KiTask) -> void:
	_module(task.module.number)[7] += 1


static func gosub_missing(number: int) -> void:
	_module(number)[8] += 1


# ------------------------------------------------------------------ natives

static func _fail(id: int, task: KiTask, reason: String) -> void:
	var by_reason: Dictionary = _failures.get_or_add(id, {})
	var by_module: Dictionary = by_reason.get_or_add(reason, {})
	by_module[task.module.number] = by_module.get(task.module.number, 0) + 1


static func _handle(h: int, kind: String) -> String:
	if h == 0:
		return "null handle"
	var node := KiWorld.resolve(h)
	if node == null:
		return "dead handle" if h > 0 and Sim.find(h & KiWorld.ID_MASK) == null else "stale handle"
	if kind == "unit" and not node is Unit or kind == "object" and not node is MapObject:
		return "wrong kind"
	return ""


## A native with its arguments popped, before it runs.
static func native(id: int, task: KiTask, a: PackedInt32Array) -> void:
	_natives[id] = _natives.get(id, 0) + 1
	_depth = task.stack.size()
	var why := ""
	if id in UNIT_ORDERS:
		why = _handle(a[0], "unit")
		if why != "":
			_fail(id, task, "unit: " + why)
		elif TARGETS.has(id):
			why = _handle(a[1], TARGETS[id])
			if why != "":
				_fail(id, task, "target: " + why)
	elif id in BUILDING_ORDERS:
		why = _handle(a[0], "object")
		if why != "":
			_fail(id, task, "building: " + why)
	elif id in QUERIES:
		why = _handle(a[0], "")
		if why != "":
			_fail(id, task, "object: " + why)
	_native_clock = Time.get_ticks_usec()
	if id in STUBS:
		_fail(id, task, "stub")
	if id == 221 and a[0] >= 0 and a[0] < KiPlayer.SEMAPHORES and task.player.semaphores[a[0]] == 0:
		_locks["%d:%d" % [task.player.index, a[0]]] = [task.module.number, Sim.time()]
	elif id == 222:
		_locks.erase("%d:%d" % [task.player.index, a[0]])


## The native has run: what it pushed tells whether a search found anything.
static func native_done(id: int, task: KiTask, a: PackedInt32Array) -> void:
	_native_usec[id] = _native_usec.get(id, 0) + Time.get_ticks_usec() - _native_clock
	if task.stack.size() <= _depth:
		return
	var result: int = task.stack.back()
	if result == 0 and id in SEARCHES:
		_fail(id, task, "found nothing")
	elif result == 0 and id in CAN_HAVE:
		_fail(id, task, "no: GUID %d" % a[0])


static func unimplemented(id: int, task: KiTask) -> void:
	var by_module: Dictionary = _unimplemented.get_or_add(id, {})
	by_module[task.module.number] = by_module.get(task.module.number, 0) + 1


## build_near (135, 292) came to nothing.
static func build_failed(id: int, task: KiTask, guid: int, reason: String) -> void:
	_fail(id, task, "%s (GUID %d)" % [reason, guid])


## A site could not be placed: whether the people could pay for it.
static func site_refused(id: int, task: KiTask, owner: int, type: ObjectTypes.ObjectType, guid: int) -> void:
	var people: Player = Player.by_index.get(owner)
	var affordable := people != null and people.can_afford(BuildController._cost_of(type, owner))
	build_failed(id, task, guid, "site refused" if affordable else "site refused: cannot pay")


## No spot within reach: the placement test also wants the price, so say when it was that.
static func no_spot(id: int, task: KiTask, owner: int, type: ObjectTypes.ObjectType, guid: int) -> void:
	var people: Player = Player.by_index.get(owner)
	var affordable := people != null and people.can_afford(BuildController._cost_of(type))
	build_failed(id, task, guid, "no spot" if affordable else "no spot: cannot pay")


static func refused(id: int, task: KiTask, reason: String) -> void:
	_fail(id, task, reason)


# ------------------------------------------------------------------ the end

static func _peoples() -> Dictionary:
	var out := {}
	for index in Player.by_index:
		out[str(index)] = {"faction": Player.by_index[index].faction,
				"resources": Player.by_index[index].resources.duplicate(), "units": {}, "buildings": {}, "sites": {}}
	for unit in Unit.all_units:
		if unit.is_alive() and out.has(str(unit.team)):
			var units: Dictionary = out[str(unit.team)].units
			var guid := str(unit.unit_type.guid())
			units[guid] = units.get(guid, 0) + 1
	for object in MapObject.structures:
		if object.is_alive() and (object.is_building() or object.is_field()) and out.has(str(object.owner_index)):
			var list: Dictionary = out[str(object.owner_index)].buildings if object.complete else out[str(object.owner_index)].sites
			list[str(object.guid)] = list.get(str(object.guid), 0) + 1
	return out


static func _task_state(task: KiTask) -> Dictionary:
	var out := {"module": task.module.number, "pc": task.pc, "sleep": task.sleep_ms, "waits": task.waits_for}
	if task.waits_for >= 0:
		out.waiting_since = _waits.get(task, -1.0)
	if task.child:
		out.child = _task_state(task.child)
	return out


static func write(main: Main) -> void:
	if not on:
		return
	var mission := _mission
	var triggers := []
	for i in mission.data.triggers.size():
		var t: MissionData.Trigger = mission.data.triggers[i]
		triggers.append({"name": t.name, "checked": _checked[i], "fired": _fired[i], "first": _first[i],
				"armed": mission._armed[i], "conditions": t.conditions.map(func(c: PackedInt32Array) -> Array: return Array(c)),
				"actions": t.actions.map(func(c: PackedInt32Array) -> Array: return Array(c))})
	var running := []
	var semaphores := []
	if main.ki:
		for index in main.ki.players:
			var ki: KiPlayer = main.ki.players[index]
			for slot in KiPlayer.SLOTS:
				if ki.slots[slot]:
					var state := _task_state(ki.slots[slot])
					state.player = index
					state.slot = slot
					running.append(state)
			for sem in KiPlayer.SEMAPHORES:
				if ki.semaphores[sem] != 0:
					var taker: Array = _locks.get("%d:%d" % [index, sem], [0, -1.0])
					semaphores.append({"player": index, "sem": sem, "module": taker[0], "since": taker[1]})
	var modules := {}
	for number in _modules:
		var m: Array = _modules[number]
		modules[str(number)] = {"started": m[0], "missing": m[1], "full": m[2], "instructions": m[3],
				"blocked": m[4], "asleep": m[5], "paused": m[6], "finished": m[7], "gosub_missing": m[8],
				"no_player": m[9]}
	var failures := {}
	for id in _failures:
		var reasons := {}
		for reason in _failures[id]:
			var by_module := {}
			for number in _failures[id][reason]:
				by_module[str(number)] = _failures[id][reason][number]
			reasons[reason] = by_module
		failures[str(id)] = reasons
	var unimplemented := {}
	for id in _unimplemented:
		var by_module := {}
		for number in _unimplemented[id]:
			by_module[str(number)] = _unimplemented[id][number]
		unimplemented[str(id)] = by_module
	var out := {
		"mission": Match.campaign.get("set", "") + "/" + Match.campaign.get("code", ""),
		"title": Match.campaign.get("title", ""),
		"me": main.me,
		"game_time": Sim.time(),
		"outcome": mission.outcome,
		"over": main._game_over,
		"script_running": mission._running,
		"endings": _endings,
		"players": mission.data.players.map(func(p: MissionData.PlayerSlot) -> Dictionary:
			return {"index": p.index, "faction": p.faction, "control": p.control}),
		"triggers": triggers,
		"actions": _keys_to_str(_actions),
		"started_modules": _script_modules,
		"modules": modules,
		"running": running,
		"semaphores": semaphores,
		"natives": _keys_to_str(_natives),
		"native_ms": _native_usec.keys().reduce(func(out: Dictionary, id: int) -> Dictionary:
			out[str(id)] = _native_usec[id] / 1000.0
			return out, {}),
		"failures": failures,
		"unimplemented": unimplemented,
		"cost": _cost.keys().map(func(minute: int) -> Array: return [minute, _cost[minute][0] / 1000.0, _cost[minute][1] / 1000.0]),
		"start": _start_state,
		"end": _peoples(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % path)
		return
	file.store_string(JSON.stringify(out))
	file.close()
	print("MISSION STATS written to %s" % path)
	on = false


static func _keys_to_str(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		out[str(key)] = d[key]
	return out
