class_name AlfMap
extends RefCounted
## Original level file (.alf): an RDCHUNK container.
##
## Header "RDCHUNK.VERSION\0", u32 version, u32 0, "RDLF", u32 ?. From 0x20, chunks:
## char[8] name, u32 next_chunk_offset (absolute), u32 packed,
## then (if packed) u32 unpacked_size + LZW data, else raw data.
##
## Known chunks: SPIELER (players), LVL_INFO (name, size, start resources),
## LVMATRIX (u32 per cell: low 16 bits = 32x32 terrain atlas tile), BITARRAY,
## PINSMATR, BOBLISTE (object types), EINHEIT (units), EIGENSCH (object properties),
## AREA/ABLAUF (mission trigger areas and scripts).

const CELL_SIZE := 32

var title := ""
var columns := 0
var rows := 0
var chunks := {}  # name -> PackedByteArray (first occurrence)
var tile_ids := PackedInt32Array()
var placements: Array[Placement] = []
## BITARRAY: map-wide "BARY" grid of 16 px cells, one u32 of flags each (see NavGrid).
var grid_size := Vector2i.ZERO
var grid_flags := PackedInt32Array()


## An object placed in the editor (BOBLISTE record: x, y, type, owner, amount, ?).
class Placement:
	var position := Vector2.ZERO
	var type_id := 0
	var owner := 0  # 0 = neutral, 1..8 = player
	var amount := 0  # e.g. gold in a mine


static func load_from_file(file_path: String) -> AlfMap:
	var bytes := FileAccess.get_file_as_bytes(file_path)
	if bytes.is_empty():
		push_error("Cannot read map %s" % file_path)
		return null
	return from_bytes(bytes)


static func from_bytes(bytes: PackedByteArray) -> AlfMap:
	if bytes.slice(0, 15).get_string_from_ascii() != "RDCHUNK.VERSION":
		push_error("Not an RDCHUNK map")
		return null
	var map := AlfMap.new()
	var pos := 0x20
	while pos + 16 <= bytes.size():
		var raw_name := bytes.slice(pos, pos + 8)
		var name_end := raw_name.find(0)
		var name := raw_name.slice(0, name_end if name_end >= 0 else 8).get_string_from_ascii()
		var next := bytes.decode_u32(pos + 8)
		var packed := bytes.decode_u32(pos + 12)
		var body := bytes.slice(pos + 16, next)
		if packed != 0:
			body = Lzw.decompress(body.slice(4), body.decode_u32(0))
		if not map.chunks.has(name):
			map.chunks[name] = body
		if next <= pos:
			break
		pos = next
	map._parse()
	return map


func _parse() -> void:
	var info: PackedByteArray = chunks.get("LVL_INFO", PackedByteArray())
	if info.size() >= 0x11C:
		var end := info.find(0)
		title = info.slice(0, end if end >= 0 else 64).get_string_from_ascii()
		columns = info.decode_u32(0x114)
		rows = info.decode_u32(0x118)
	var objects: PackedByteArray = chunks.get("BOBLISTE", PackedByteArray())
	if objects.size() >= 4:
		for i in objects.decode_u32(0):
			var o := 4 + i * 24
			if o + 24 > objects.size():
				break
			var p := Placement.new()
			p.position = Vector2(objects.decode_u32(o), objects.decode_u32(o + 4))
			p.type_id = objects.decode_u32(o + 8)
			p.owner = objects.decode_u32(o + 12)
			var amount := objects.decode_u32(o + 16)
			p.amount = amount if amount != 0xCDCDCDCD else 0
			placements.append(p)
	var bits: PackedByteArray = chunks.get("BITARRAY", PackedByteArray())
	if bits.size() >= 32 and bits.slice(0, 4).get_string_from_ascii() == "BARY":
		grid_size = Vector2i(bits.decode_u32(20), bits.decode_u32(24))
		grid_flags = bits.slice(32, 32 + grid_size.x * grid_size.y * 4).to_int32_array()
	var matrix: PackedByteArray = chunks.get("LVMATRIX", PackedByteArray())
	tile_ids.resize(columns * rows)
	for i in mini(tile_ids.size(), matrix.size() / 4):
		tile_ids[i] = matrix.decode_u16(i * 4)


## "wiese" if the map uses meadow object variants, otherwise "steppe".
func guess_biome() -> String:
	for p in placements:
		var t := ObjectTypes.get_type(p.type_id)
		if t and t.is_meadow():
			return "wiese"
	return "steppe"


func pixel_size() -> Vector2i:
	return Vector2i(columns * CELL_SIZE, rows * CELL_SIZE)
