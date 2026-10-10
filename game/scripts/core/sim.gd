class_name Sim
extends RefCounted
## The match's clock: the game advances in fixed steps of TICK seconds, never by the frame's
## own delta, so the same orders always give the same game on every machine (the ground work
## for lockstep multiplayer and replays). Main steps it from _physics_process, which runs
## RATE times a second at normal speed (faster or slower with the game speed), and physics
## interpolation smooths what moves between steps on screen.
##
## Everything that changes the game is driven from here, in a fixed order:
##   - nodes that `activate` themselves get `sim_tick(TICK)` each step, in the order they
##     were first activated (they keep `_sim_on` and `_sim_listed` for this);
##   - `after` runs a call once a number of game seconds have passed;
##   - `rng` is the only randomness the game itself may use, seeded per match.
## Purely cosmetic things (sounds, birds, the camera, the interface) keep using the frame.

const RATE := 30
const TICK := 1.0 / RATE

static var tick := 0
static var rng := RandomNumberGenerator.new()
static var _nodes: Array[Node] = []
static var _timers: Array[Array] = []  # [due tick, order, Callable], kept sorted
static var _timer_count := 0


## A new match: clock at zero, nothing ticking, randomness seeded.
static func reset(seed_value: int) -> void:
	tick = 0
	_nodes.clear()
	_timers.clear()
	_timer_count = 0
	rng.seed = seed_value
	UnitGrid.invalidate()


## Game speed: steps per real second (RATE at 1.0); frame-driven effects keep pace through
## Engine.time_scale, while each step stays TICK long.
static func set_speed(scale: float) -> void:
	Engine.time_scale = scale
	Engine.physics_ticks_per_second = maxi(1, roundi(RATE * scale))
	Engine.max_physics_steps_per_frame = maxi(8, ceili(scale * 4.0))


## Game seconds since the match began.
static func time() -> float:
	return tick * TICK


## Game milliseconds since the match began (for timers kept in whole milliseconds).
static func msec() -> int:
	return tick * 1000 / RATE


static func activate(node: Node) -> void:
	if node._sim_on:
		return
	node._sim_on = true
	if not node._sim_listed:
		node._sim_listed = true
		_nodes.append(node)


static func deactivate(node: Node) -> void:
	node._sim_on = false


static func set_active(node: Node, on: bool) -> void:
	if on:
		activate(node)
	else:
		deactivate(node)


## Calls `callable` once `seconds` of game time have passed (on the step that reaches it).
static func after(seconds: float, callable: Callable) -> void:
	var due := tick + maxi(1, ceili(seconds * RATE - 0.0001))
	_timer_count += 1
	var entry := [due, _timer_count, callable]
	var at := _timers.bsearch_custom(entry, func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	_timers.insert(at, entry)


## One step of the game.
static func step() -> void:
	tick += 1
	while not _timers.is_empty() and _timers[0][0] <= tick:
		var callable: Callable = _timers.pop_front()[2]
		if callable.is_valid():
			callable.call()
	# Nodes activated during this step start on the next one.
	var count := _nodes.size()
	for i in count:
		var node := _nodes[i]
		if is_instance_valid(node) and node._sim_on and node.is_inside_tree() and not node.is_queued_for_deletion():
			node.sim_tick(TICK)
	var kept: Array[Node] = []
	for node in _nodes:
		if is_instance_valid(node) and node._sim_on and not node.is_queued_for_deletion():
			kept.append(node)
		elif is_instance_valid(node):
			node._sim_listed = false
	_nodes = kept


## A fingerprint of the game's state: every unit's place, health and doing, every building's
## and resource's state, each people's stockpile and the randomness. Machines running the
## same match must agree on it at every step; when they do not, the games have drifted apart.
static func checksum() -> String:
	var numbers := PackedFloat64Array([tick, rng.state])
	for unit in Unit.all_units:
		numbers.append_array([unit.position.x, unit.position.y, unit.health, unit.state, unit.team])
	for object in MapObject.structures:
		numbers.append_array([object.position.x, object.position.y, object.health, object.owner_index,
				object.stock.amount if object.stock else 0])
	for index in Player.by_index:
		var people: Player = Player.by_index[index]
		for resource in people.resources:
			numbers.append(float(people.resources[resource]))
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	hashing.update(numbers.to_byte_array())
	return hashing.finish().hex_encode()


# ------------------------------------------------------------------ the game's own randomness

static func randf() -> float:
	return rng.randf()


static func randf_range(from: float, to: float) -> float:
	return rng.randf_range(from, to)


## A whole number in 0..count-1.
static func randi_below(count: int) -> int:
	return rng.randi() % count if count > 0 else 0


static func pick(options: Array) -> Variant:
	return options[randi_below(options.size())]


static func shuffle(options: Array) -> void:
	for i in range(options.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = options[i]
		options[i] = options[j]
		options[j] = swap
