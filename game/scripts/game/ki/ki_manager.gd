class_name KiManager
extends Node
## The original's AI scripts at work in a campaign mission (AmericaAddOn.exe CKIManager,
## 0x4383c0): every people in the mission has a KiPlayer, and the mission's script starts
## modules for them (its action 1). In the campaign the skirmish AI module is not started:
## what computer players do is what the mission's modules tell them. Stepped by Sim, so it
## plays the same on every machine; 20 ms steps, as the original's.

static var current: KiManager

var players := {}  # people -> KiPlayer
var map_size := Vector2i.ZERO
var biome := "steppe"
var _budget := 0
var _sim_on := false
var _sim_listed := false
## --trace-ki=1: modules started; 2: also what they try to build.
var trace_level := GameData.cmdline_option("trace-ki", "0").to_int()


func setup(peoples: Array, map_pixels: Vector2i, map_biome: String) -> void:
	current = self
	map_size = map_pixels
	biome = map_biome
	KiWorld.reset()
	for index in peoples:
		players[index] = KiPlayer.new(index)
	Sim.activate(self)


func _exit_tree() -> void:
	if current == self:
		current = null


func start(people: int, module: int) -> void:
	var ki: KiPlayer = players.get(people)
	var task := ki.start(module) if ki else null
	if trace_level >= 1:
		print("KI t=%.1f player %d module %08d %s" % [Sim.time(), people, module, "started" if task else "NOT started"])


func sim_tick(_delta: float) -> void:
	var clock := Time.get_ticks_usec() if MissionStats.on else 0
	_budget += 1000  # a game step in 1/30 ms
	while _budget >= KiPlayer.STEP_MS * Sim.RATE:
		_budget -= KiPlayer.STEP_MS * Sim.RATE
		for index in players:
			players[index].step()
	if MissionStats.on:
		MissionStats.cost(0, clock)


## Called when something of a people is hurt (the scripts' "attacked" queues).
static func note_hurt(node: Node) -> void:
	if current == null:
		return
	var ki: KiPlayer = current.players.get(KiWorld.owner_of(node))
	if ki:
		ki.note_hurt(KiWorld.handle(node), node is MapObject)


func running() -> int:
	var total := 0
	for index in players:
		total += players[index].running()
	return total


func save_state() -> Dictionary:
	var out := {"budget": _budget, "claims": {}, "players": {}}
	for id in KiWorld.claims:
		out.claims[str(id)] = KiWorld.claims[id]
	for index in players:
		out.players[str(index)] = players[index].save_state()
	return out


func restore_state(state: Dictionary) -> void:
	_budget = int(state.budget)
	KiWorld.claims.clear()
	for id in state.claims:
		KiWorld.claims[int(id)] = int(state.claims[id])
	for index in state.players:
		if players.has(int(index)):
			players[int(index)].restore_state(state.players[index])
