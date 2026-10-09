class_name ObjectTypes
extends RefCounted
## The original object type table, BobListe.blf ("RDBF").
##
## Part 1: u32 capacity, then `capacity` x { u32 ?; char bob_path[80]; i32 ? } -- .bob file list.
## Part 2: one record per object type id (the ids maps and GUIDS.INI use, 0..434):
##   char name[0x50]; u32 bob_id @0x50; u32 kind @0x54; i32 anim @0x6c; i32 shadow_anim @0x70
##   (0x104 bytes in total, partly uninitialised memory in the original file), then a
##   "BARY" footprint: i32 anchor_x, anchor_y; u32 width, height, cols, rows, count; u32 cells[count]
##   on a 16 px grid.

enum Kind { NONE = 0, UNIT = 1, BUILDING = 2, ELEMENT = 3 }

const PATH := "BobListe.blf"
const HEADER_SIZE := 0x104
const FOOTPRINT_CELL := 16


class ObjectType:
	var id := 0
	var name := ""
	var bob_path := ""
	var kind := Kind.NONE
	var anim := 0
	var shadow_anim := -1
	var footprint_anchor := Vector2i.ZERO
	var footprint_size := Vector2i.ZERO
	var footprint_grid := Vector2i.ZERO
	var footprint_cells := PackedInt32Array()

	func directory() -> String:
		return bob_path.get_base_dir()

	func is_meadow() -> bool:
		return name.ends_with("_Wi")


static var _types: Array[ObjectType] = []


static func get_type(id: int) -> ObjectType:
	if _types.is_empty():
		_load()
	return _types[id] if id >= 0 and id < _types.size() else null


static func count() -> int:
	if _types.is_empty():
		_load()
	return _types.size()


static func _load() -> void:
	var d := GameData.read(PATH)
	if d.slice(0, 4).get_string_from_ascii() != "RDBF":
		push_error("BobListe.blf missing or invalid")
		return
	var capacity := d.decode_u32(4)
	var bobs := PackedStringArray()
	for i in capacity:
		bobs.append(_c_string(d, 8 + i * 88 + 4, 80).replace("\\", "/").to_lower())
	var pos := 8 + capacity * 88
	while pos + HEADER_SIZE + 32 <= d.size():
		var bary := pos + HEADER_SIZE
		var t := ObjectType.new()
		if d.decode_u32(pos + 0x54) == 0xFFFFFFFF:
			# Expansion placeholder records have no footprint (and no usable graphics).
			t.id = _types.size()
			t.name = _c_string(d, pos, 0x50)
			_types.append(t)
			pos = bary
			continue
		if d.slice(bary, bary + 4).get_string_from_ascii() != "BARY":
			break  # trailing data after the last record
		t.id = _types.size()
		t.name = _c_string(d, pos, 0x50)
		var bob_id := d.decode_u32(pos + 0x50)
		t.bob_path = bobs[bob_id] if bob_id < bobs.size() else ""
		t.kind = d.decode_u32(pos + 0x54) as Kind
		t.anim = d.decode_s32(pos + 0x6C)
		t.shadow_anim = d.decode_s32(pos + 0x70)
		t.footprint_anchor = Vector2i(d.decode_s32(bary + 4), d.decode_s32(bary + 8))
		t.footprint_size = Vector2i(d.decode_u32(bary + 12), d.decode_u32(bary + 16))
		t.footprint_grid = Vector2i(d.decode_u32(bary + 20), d.decode_u32(bary + 24))
		var cells := d.decode_u32(bary + 28)
		t.footprint_cells.resize(cells)
		for i in cells:
			t.footprint_cells[i] = d.decode_u32(bary + 32 + i * 4)
		_types.append(t)
		pos = bary + 32 + cells * 4


static func _c_string(d: PackedByteArray, offset: int, size: int) -> String:
	var raw := d.slice(offset, offset + size)
	var end := raw.find(0)
	return raw.slice(0, end if end >= 0 else size).get_string_from_ascii()
