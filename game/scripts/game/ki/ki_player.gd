class_name KiPlayer
extends RefCounted
## One people's KI (AmericaAddOn.exe CKIPlayer): up to 200 modules running side by side,
## each doing one instruction every 20 ms of game time in slot order (0x439f80), and what
## they share: 256 globals, 100 tables of 256 numbers, 256 semaphores, an atomic section
## that stops the others, and the queues of its units and buildings that were hurt.

const SLOTS := 200
const STEP_MS := 20
const GLOBALS := 256
const TABLES := 100
const TABLE_SIZE := 256
const SEMAPHORES := 256
const EVENT_LIMIT := 256

var index := 0  ## the people (the scripts' "me")
var slots: Array = []  # KiTask or null
var globals := PackedInt32Array()
var tables: Array[PackedInt32Array] = []
var semaphores := PackedByteArray()
var atomic := false
var atomic_slot := -1
var current_slot := -1
var hurt_units: Array[int] = []  ## handles, oldest first
var hurt_buildings: Array[int] = []


func _init(people: int) -> void:
	index = people
	slots.resize(SLOTS)
	globals.resize(GLOBALS)
	for i in TABLES:
		var table := PackedInt32Array()
		table.resize(TABLE_SIZE)
		tables.append(table)
	semaphores.resize(SEMAPHORES)


## Starts module `number` in the first free slot, its stack holding `arguments`; nothing
## when all slots are taken or there is no such module (0x43d900).
func start(number: int, arguments: Array = []) -> KiTask:
	var slot := slots.find(null)
	if slot < 0:
		return null
	var module := KiModule.load(number)
	if module == null:
		return null
	var task := KiTask.new(self, module, arguments.duplicate(), null)
	slots[slot] = task
	return task


func step() -> void:
	for slot in SLOTS:
		var task: KiTask = slots[slot]
		if task == null:
			continue
		current_slot = slot
		task.tick(atomic and slot != atomic_slot)
		if task.finished:
			slots[slot] = null
	current_slot = -1


func running() -> int:
	return SLOTS - slots.count(null)


## One of this people's units or buildings was hurt (each handle queued once).
func note_hurt(handle: int, building: bool) -> void:
	var queue := hurt_buildings if building else hurt_units
	if queue.size() < EVENT_LIMIT and handle not in queue:
		queue.append(handle)


func save_state() -> Dictionary:
	var tasks := []
	for slot in SLOTS:
		if slots[slot]:
			tasks.append({"slot": slot, "task": slots[slot].save_state()})
	return {"globals": Array(globals), "tables": tables.map(func(t: PackedInt32Array) -> Array: return Array(t)),
			"semaphores": Array(semaphores), "atomic": atomic, "atomic_slot": atomic_slot,
			"hurt_units": hurt_units, "hurt_buildings": hurt_buildings, "tasks": tasks}


func restore_state(state: Dictionary) -> void:
	globals = PackedInt32Array(state.globals)
	for i in mini(TABLES, state.tables.size()):
		tables[i] = PackedInt32Array(state.tables[i])
	semaphores = PackedByteArray(state.semaphores)
	atomic = bool(state.atomic)
	atomic_slot = int(state.atomic_slot)
	hurt_units.assign(state.hurt_units.map(func(h) -> int: return int(h)))
	hurt_buildings.assign(state.hurt_buildings.map(func(h) -> int: return int(h)))
	slots.fill(null)
	for entry in state.tasks:
		slots[int(entry.slot)] = KiTask.restore(self, entry.task, null, null)
