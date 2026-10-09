class_name AlfMap
extends RefCounted
## Original level file (.alf): an RDCHUNK container.
##
## Header "RDCHUNK.VERSION\0", u32 version, u32 0, "RDLF", u32 ?. From 0x20, chunks:
## char[8] name, u32 next_chunk_offset (absolute), u32 packed,
## then (if packed) u32 unpacked_size + data: packed 1 = LZW (.alf, base game),
## packed 2 = zlib (.ulf, expansion maps).
##
## Known chunks: SPIELER (players), LVL_INFO (name, size, start resources),
## LVMATRIX (u32 per cell: low 16 bits = 32x32 terrain atlas tile, high 16 bits = the
## level editor's shape code, see TerrainRules), BITARRAY,
## PINSMATR, BOBLISTE (object types), EINHEIT (units), EIGENSCH (object properties),
## AREA/ABLAUF (mission trigger areas and scripts).

const CELL_SIZE := 32

var title := ""
var columns := 0
var rows := 0
## Start resources set in the level editor (LVL_INFO 0x120..0x12C; leather starts empty).
var start_resources := {}
var chunks := {}  # name -> PackedByteArray (first occurrence)
var tile_ids := PackedInt32Array()
var tile_codes := PackedInt32Array()  ## LVMATRIX high words (TerrainRules shape codes)
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
	var content := 0  # what `amount` is for an abandoned warehouse: 0x130 gold, 0x131 guns


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
		if packed == 1:
			body = Lzw.decompress(body.slice(4), body.decode_u32(0))
		elif packed == 2:
			body = body.slice(4).decompress(body.decode_u32(0), FileAccess.COMPRESSION_DEFLATE)
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
		# Base game maps keep the title at 0, the expansion's (and ours) at 0x10.
		var at := 0 if info[0] != 0 else 0x10
		var end := info.find(0, at)
		title = info.slice(at, end if end >= 0 else at + 64).get_string_from_ascii()
		columns = info.decode_u32(0x114)
		rows = info.decode_u32(0x118)
	if info.size() >= 0x130:
		start_resources = {"food": info.decode_u32(0x120), "wood": info.decode_u32(0x124),
				"gold": info.decode_u32(0x128), "guns": info.decode_u32(0x12C)}
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
			p.content = objects.decode_u32(o + 20)
			placements.append(p)
	var bits: PackedByteArray = chunks.get("BITARRAY", PackedByteArray())
	if bits.size() >= 32 and bits.slice(0, 4).get_string_from_ascii() == "BARY":
		grid_size = Vector2i(bits.decode_u32(20), bits.decode_u32(24))
		grid_flags = bits.slice(32, 32 + grid_size.x * grid_size.y * 4).to_int32_array()
	var matrix: PackedByteArray = chunks.get("LVMATRIX", PackedByteArray())
	tile_ids.resize(columns * rows)
	tile_codes.resize(columns * rows)
	for i in mini(tile_ids.size(), matrix.size() / 4):
		tile_ids[i] = matrix.decode_u16(i * 4)
		tile_codes[i] = matrix.decode_u16(i * 4 + 2)


## "wiese" if the map uses meadow object variants, otherwise "steppe".
func guess_biome() -> String:
	for p in placements:
		var t := ObjectTypes.get_type(p.type_id)
		if t and t.is_meadow():
			return "wiese"
	return "steppe"


func pixel_size() -> Vector2i:
	return Vector2i(columns * CELL_SIZE, rows * CELL_SIZE)


# ------------------------------------------------------------------ writing (map editor)

## An empty map of `columns` x `rows` 32 px cells (the terrain is left to the caller).
static func create(map_title: String, map_columns: int, map_rows: int) -> AlfMap:
	var map := AlfMap.new()
	map.title = map_title
	map.columns = map_columns
	map.rows = map_rows
	map.tile_ids.resize(map_columns * map_rows)
	map.tile_codes.resize(map_columns * map_rows)
	map.grid_size = Vector2i(map_columns * 2, map_rows * 2)
	map.grid_flags.resize(map.grid_size.x * map.grid_size.y)
	map.start_resources = {"food": 1000, "wood": 1000, "gold": 1000, "guns": 10}
	return map


## The map as an expansion level file (zlib-packed chunks, like the expansion editor's).
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("RDCHUNK.VERSION".to_ascii_buffer())
	out.append_array(PackedByteArray([0, 0x20, 0, 0, 0, 0, 0, 0, 0]))
	out.append_array("RDLF".to_ascii_buffer())
	out.append_array(_u32s([8]))
	var info := PackedByteArray()
	info.resize(0x130)
	var name_bytes := title.to_ascii_buffer().slice(0, 0x100 - 1)
	for i in name_bytes.size():
		info[0x10 + i] = name_bytes[i]
	info.encode_u32(0x110, 1)
	info.encode_u32(0x114, columns)
	info.encode_u32(0x118, rows)
	info.encode_u32(0x11C, 1)
	for key in ["food", "wood", "gold", "guns"]:
		info.encode_u32(0x120 + ["food", "wood", "gold", "guns"].find(key) * 4, int(start_resources.get(key, 0)))
	var objects := _u32s([placements.size()])
	for p in placements:
		objects.append_array(_u32s([int(p.position.x), int(p.position.y), p.type_id, p.owner, p.amount, p.content]))
	var matrix := PackedByteArray()
	matrix.resize(tile_ids.size() * 4)
	for i in tile_ids.size():
		matrix.encode_u16(i * 4, tile_ids[i])
		matrix.encode_u16(i * 4 + 2, tile_codes[i] if i < tile_codes.size() else 0)
	var bits := "BARY".to_ascii_buffer()
	bits.append_array(_u32s([0, 0, grid_size.x * 16, grid_size.y * 16, grid_size.x, grid_size.y, grid_flags.size()]))
	bits.append_array(grid_flags.to_byte_array())
	for chunk in [["LVL_INFO", info], ["BOBLISTE", objects], ["LVMATRIX", matrix], ["BITARRAY", bits]]:
		_append_chunk(out, chunk[0], chunk[1])
	return out


func save(file_path: String) -> bool:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write map %s" % file_path)
		return false
	file.store_buffer(to_bytes())
	return true


static func _append_chunk(out: PackedByteArray, name: String, body: PackedByteArray) -> void:
	var packed := body.compress(FileAccess.COMPRESSION_DEFLATE)
	var header := name.to_ascii_buffer()
	header.resize(8)
	var start := out.size()
	out.append_array(header)
	out.append_array(_u32s([start + 16 + 4 + packed.size(), 2, body.size()]))
	out.append_array(packed)


static func _u32s(values: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for i in values.size():
		bytes.encode_u32(i * 4, values[i])
	return bytes
