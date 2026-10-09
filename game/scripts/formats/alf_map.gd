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
	var matrix: PackedByteArray = chunks.get("LVMATRIX", PackedByteArray())
	tile_ids.resize(columns * rows)
	for i in mini(tile_ids.size(), matrix.size() / 4):
		tile_ids[i] = matrix.decode_u16(i * 4)


func pixel_size() -> Vector2i:
	return Vector2i(columns * CELL_SIZE, rows * CELL_SIZE)
