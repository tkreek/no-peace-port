class_name KiStore
extends RefCounted
## A module's variables (AmericaAddOn.exe 0x40ef40). A variable id is class<<24 | type<<16 |
## index: class 0 a number, 2 an array (growable, used through natives), 1 and 3 references
## to a number or array of the calling module (parameters of a subroutine); type 0..4 int,
## bool, building, unit, neutral object (only a tag). Literals are variables too, set up by
## the module's CONSTDAT. Reading or writing a reference follows it into the caller's store
## (0x40f270, 0x40f220).

const REFERENCE := 0x1000000
const ARRAY := 0x2000000
## Array natives grow an array to index + 10 for indices up to this (0x459e80).
const ARRAY_LIMIT := 1000

var parent: KiStore
var values := {}  # variable id -> int
var arrays := {}  # variable id -> PackedInt32Array


func _init(module: KiModule, parent_store: KiStore) -> void:
	parent = parent_store
	for block in module.blocks:
		if block[0] & ARRAY and not block[0] & REFERENCE:
			for i in block[1]:
				arrays[block[0] | i] = PackedInt32Array([0])
	for id in module.initial:
		values[id] = module.initial[id]


func read(id: int) -> int:
	var at := self
	while id & REFERENCE:
		if at.parent == null:
			return 0
		var next: int = at.values.get(id, 0)
		at = at.parent
		id = next
	return at.values.get(id, 0)


func write(id: int, value: int) -> void:
	var at := self
	while id & REFERENCE:
		if at.parent == null:
			return
		var next: int = at.values.get(id, 0)
		at = at.parent
		id = next
	if id & ARRAY:
		return  # arrays are written element by element through natives
	at.values[id] = value


## The slot itself, references not followed: a subroutine receiving a reference parameter.
func write_raw(id: int, value: int) -> void:
	if id & ARRAY and not id & REFERENCE:
		return
	values[id] = value


func _resolve(id: int) -> Array:
	var at := self
	while id & REFERENCE:
		if at.parent == null:
			return [null, 0]
		var next: int = at.values.get(id, 0)
		at = at.parent
		id = next
	return [at, id]


func array(id: int) -> PackedInt32Array:
	var found := _resolve(id)
	if found[0] == null:
		return PackedInt32Array()
	return found[0].arrays.get(found[1], PackedInt32Array())


func set_array(id: int, list: PackedInt32Array) -> void:
	var found := _resolve(id)
	if found[0] != null and found[0].arrays.has(found[1]):
		found[0].arrays[found[1]] = list


func get_element(id: int, index: int) -> int:
	if index < 0 or index > ARRAY_LIMIT:
		return 0
	var list := array(id)
	if index >= list.size():
		list.resize(index + 10)
		set_array(id, list)
	return list[index]


func set_element(id: int, index: int, value: int) -> void:
	if index < 0 or index > ARRAY_LIMIT:
		return
	var list := array(id)
	if index >= list.size():
		list.resize(index + 10)
	list[index] = value
	set_array(id, list)


func save_state() -> Dictionary:
	var a := {}
	for id in arrays:
		a[str(id)] = Array(arrays[id])
	var v := {}
	for id in values:
		v[str(id)] = values[id]
	return {"values": v, "arrays": a}


func restore_state(state: Dictionary) -> void:
	values.clear()
	for id in state.values:
		values[int(id)] = int(state.values[id])
	for id in state.arrays:
		arrays[int(id)] = PackedInt32Array(state.arrays[id])
