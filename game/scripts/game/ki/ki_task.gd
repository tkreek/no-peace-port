class_name KiTask
extends RefCounted
## A KI module running for a people (AmericaAddOn.exe CKIModuleObject): its place in the
## code, its operand stack (100 ints, shared with a subroutine it calls), its variables,
## and what it waits for. KiPlayer ticks it every 20 ms of game time; each tick it does one
## instruction (Tick 0x43e650, Step 0x43e860):
##   0 push v   1 pop v (0x0FFFFFFF: drop)   2 push the number itself (a variable passed by
##   reference)   3 pop into the slot itself   4 call native   5 call a module as a
##   subroutine   6 start a module of its own   7 jump   8 jump if zero   9 jump if not zero.

const STACK_LIMIT := 100
const DROP := 0x0FFFFFFF
## Spawned modules get this many values from the top of their creator's stack.
const SPAWN_ARGUMENTS := 10

var player: KiPlayer
var module: KiModule
var pc := 0
var stack: Array = []  ## shared with a running subroutine
var store: KiStore
var child: KiTask  ## the subroutine running (opcode 5)
var finished := false
var sleep_ms := 0
var waits_for := -1  ## semaphore it is blocked on
## Natives' results kept for later natives: last building spot, water found, reachable
## point, the handle taken from an event queue.
var build_spot := Vector2i.ZERO
var found_spot := Vector2i.ZERO
var reachable_spot := Vector2i.ZERO
var event_handle := 0


func _init(owner: KiPlayer, code: KiModule, shared_stack: Array, parent_store: KiStore) -> void:
	player = owner
	module = code
	stack = shared_stack
	store = KiStore.new(code, parent_store)


## One 20 ms tick (`paused`: another module of the people runs an atomic section).
func tick(paused: bool) -> void:
	if waits_for >= 0:
		if player.semaphores[waits_for] != 0:
			return
		player.semaphores[waits_for] = 1
		waits_for = -1
	if child:
		child.tick(paused)
		if child.finished:
			child = null
		return
	if sleep_ms > 0:
		sleep_ms -= KiPlayer.STEP_MS
		return
	if paused:
		return
	if pc >= module.code.size():
		finished = true
		return
	step()


func step() -> void:
	var word := module.code[pc]
	pc += 1
	var operand := word & 0x0FFFFFFF
	match (word >> 28) & 0xF:
		0:
			push(store.read(operand))
		1:
			var value := pop()
			if operand != DROP:
				store.write(operand, value)
		2:
			push(operand)
		3:
			store.write_raw(operand, pop())
		4:
			KiNatives.call_native(operand, self)
		5:
			var code := KiModule.load(operand)
			if code:
				child = KiTask.new(player, code, stack, store)
		6:
			player.start(operand, stack.slice(maxi(0, stack.size() - SPAWN_ARGUMENTS)))
		7:
			pc = operand
		8:
			if pop() == 0:
				pc = operand
		9:
			if pop() != 0:
				pc = operand


func push(value: int) -> void:
	if stack.size() < STACK_LIMIT:
		stack.append(value)


func pop() -> int:
	return stack.pop_back() if not stack.is_empty() else 0


## The array a variable id passed by reference names (resolving reference parameters).
func array(id: int) -> PackedInt32Array:
	return store.array(id)


func set_array(id: int, values: PackedInt32Array) -> void:
	store.set_array(id, values)


# ------------------------------------------------------------------ saving

func save_state() -> Dictionary:
	return {"module": module.number, "pc": pc, "stack": stack.duplicate(), "store": store.save_state(),
			"child": child.save_state() if child else {}, "sleep": sleep_ms, "waits": waits_for,
			"build": [build_spot.x, build_spot.y], "found": [found_spot.x, found_spot.y],
			"reach": [reachable_spot.x, reachable_spot.y], "event": event_handle}


static func restore(owner: KiPlayer, state: Dictionary, shared_stack: Variant, parent_store: KiStore) -> KiTask:
	var code := KiModule.load(int(state.module))
	if code == null:
		return null
	var stack: Array = shared_stack if shared_stack != null else []
	if shared_stack == null:
		for v in state.stack:
			stack.append(int(v))
	var task := KiTask.new(owner, code, stack, parent_store)
	task.pc = int(state.pc)
	task.store.restore_state(state.store)
	task.sleep_ms = int(state.sleep)
	task.waits_for = int(state.waits)
	task.build_spot = Vector2i(int(state.build[0]), int(state.build[1]))
	task.found_spot = Vector2i(int(state.found[0]), int(state.found[1]))
	task.reachable_spot = Vector2i(int(state.reach[0]), int(state.reach[1]))
	task.event_handle = int(state.event)
	if not state.child.is_empty():
		task.child = restore(owner, state.child, stack, task.store)
	return task
