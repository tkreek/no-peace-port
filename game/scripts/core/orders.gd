class_name Orders
extends RefCounted
## The players' orders as data. The interface never changes the game itself: a click gives
## an order ({"t": step, "p": people, "op": kind, "ids": unit numbers, "a": arguments}) that
## is carried out at the start of a later game step (Sim). Units and objects travel as their
## sim_id, so the same order means the same thing on every machine; that is all lockstep
## multiplayer has to send, and all a replay has to keep.
##
## Kinds of order:
##   "unit"     each unit in "ids" (owned by "p") does a[0] (a name in UNIT_ORDERS) with a[1..]
##   "building" building ids[0] (owned by "p") does a[0] (a name in BUILDING_ORDERS) with a[1..]
##   "place"    put down a site: [type id, spot, keep placing, travois or null], builders in "ids"
## Feedback (sounds, flashes, markers) stays with the interface, at once.

## Steps between the one after giving an order and carrying it out: none alone, Net.DELAY
## in a network game (where the orders must reach everyone first).
static var delay := 0

## What a unit order may call ("" on the unit itself, or the name of one of its parts).
const UNIT_ORDERS := {
	"move_to": "", "attack_move": "", "patrol": "", "follow": "", "order_attack": "", "stop": "",
	"gather": "", "haul": "", "build": "", "hunt": "", "rob": "", "steal": "", "sabotage": "",
	"mount": "", "dismount": "", "cast": "", "conceal": "", "board": "", "unload_at": "", "pack": "",
	"take_quarters": "", "set_stance": "", "set_formation": "",
	"queue_build": "work", "deliver": "animal", "stable": "animal",
}
## What a building order may call, on which of its parts.
const BUILDING_ORDERS := {
	"enqueue": "production", "cancel": "production", "invoke_spirit": "production",
	"set_distilling": "production", "set_rally": "production", "look": "production",
	"release": "defence", "demolish": "condition",
}

## The people whose orders this machine gives.
static var local_player := 1
## Where placed sites go (BuildController.place_site).
static var build_controller: BuildController
## Every order carried out this match, in order (a replay of the match with its seed).
static var history: Array[Dictionary] = []
## While a replay plays, the interface's orders are ignored.
static var replaying := false
static var _pending: Array[Dictionary] = []
static var _outgoing := {}  # step -> this machine's orders for it, until Net sends them
static var _count := 0  # orders given this match (their "n": the order within a step)


static func reset() -> void:
	_pending.clear()
	_outgoing.clear()
	_count = 0
	history.clear()
	replaying = false


# ------------------------------------------------------------------ giving orders

## `units` do `method` (a name in UNIT_ORDERS) with `args`.
static func units(units: Array, method: String, args := []) -> void:
	var ids := _ids(units)
	if not ids.is_empty():
		give({"op": "unit", "ids": ids, "a": [method] + args})


static func unit(who: Unit, method: String, args := []) -> void:
	units([who], method, args)


## `building` does `method` (a name in BUILDING_ORDERS) with `args`.
static func building(which: MapObject, method: String, args := []) -> void:
	if is_instance_valid(which) and which.sim_id != 0:
		give({"op": "building", "ids": [which.sim_id], "a": [method] + args})


static func place(type_id: int, at: Vector2, keep_placing: bool, unpacker: Unit, builders: Array) -> void:
	give({"op": "place", "ids": _ids(builders), "a": [type_id, at, keep_placing, unpacker]})


## Queue an order from this machine's people for a coming step.
static func give(order: Dictionary) -> void:
	if replaying:
		return
	_count += 1
	order["t"] = Sim.tick + 1 + delay
	order["p"] = local_player
	order["n"] = _count
	order["a"] = order.a.map(_pack)
	queue(order)
	if delay > 0:
		var due: Array = _outgoing.get(order.t, [])
		due.append(order)
		_outgoing[order.t] = due


## This machine's orders for step `tick`, handed over once (Net sends them).
static func sealed(tick: int) -> Array:
	var due: Array = _outgoing.get(tick, [])
	_outgoing.erase(tick)
	return due


## Queue an order as it is (from a replay, or from another machine). Within a step they go
## by people and then in the order given, however they arrived.
static func queue(order: Dictionary) -> void:
	var at := _pending.size()
	while at > 0 and _after(_pending[at - 1], order):
		at -= 1
	_pending.insert(at, order)


static func _after(a: Dictionary, b: Dictionary) -> bool:
	if int(a.t) != int(b.t):
		return int(a.t) > int(b.t)
	if int(a.p) != int(b.p):
		return int(a.p) > int(b.p)
	return int(a.get("n", 0)) > int(b.get("n", 0))


static func _ids(nodes: Array) -> Array:
	var ids := []
	for node in nodes:
		if is_instance_valid(node) and node.sim_id != 0:
			ids.append(node.sim_id)
	return ids


## Arguments travel as plain values; a unit or object as {"id": its sim_id}.
static func _pack(value: Variant) -> Variant:
	if value is Node:
		return {"id": value.sim_id} if is_instance_valid(value) else null
	return value


# ------------------------------------------------------------------ replays

## The match so far as a replay: its seed and every order carried out.
static func write_replay(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(var_to_str({"version": 1, "seed": Sim.seed_value, "steps": Sim.tick, "orders": history}))


static func read_replay(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var data = str_to_var(FileAccess.get_file_as_string(path))
	return data if data is Dictionary and data.get("version") == 1 else {}


## Play `replay`'s orders back (after Sim.reset with its seed); the interface's are ignored.
static func play(replay: Dictionary) -> void:
	for order: Dictionary in replay.orders:
		queue(order)
	replaying = true


# ------------------------------------------------------------------ carrying them out

## The orders due on step `tick` (Sim.step calls this first).
static func run(tick: int) -> void:
	while not _pending.is_empty() and int(_pending[0].t) <= tick:
		var order: Dictionary = _pending.pop_front()
		history.append(order)
		execute(order)


static func execute(order: Dictionary) -> void:
	var people := int(order.p)
	var args := []
	for value in order.a:
		if value is Dictionary and value.has("id"):
			value = Sim.find(int(value.id))
			if value == null:
				return  # what it was about is gone
		args.append(value)
	match order.op:
		"unit":
			var method := String(args.pop_front())
			if not UNIT_ORDERS.has(method):
				return
			for who in _owned_units(order.ids, people):
				var target: Object = who if UNIT_ORDERS[method] == "" else who.get(UNIT_ORDERS[method])
				target.callv(method, args)
		"building":
			var method := String(args.pop_front())
			var which := Sim.find(int(order.ids[0])) as MapObject
			if not BUILDING_ORDERS.has(method) or which == null or which.owner_index != people or not which.is_building():
				return
			which.get(BUILDING_ORDERS[method]).callv(method, args)
		"place":
			if build_controller == null:
				return
			var unpacker: Unit = args[3]
			if unpacker != null and unpacker.team != people:
				return
			build_controller.place_site(people, int(args[0]), args[1], bool(args[2]), unpacker, _owned_units(order.ids, people))


static func _owned_units(ids: Array, people: int) -> Array[Unit]:
	var found: Array[Unit] = []
	for id in ids:
		var who := Sim.find(int(id)) as Unit
		if who != null and who.team == people and who.is_alive():
			found.append(who)
	return found
