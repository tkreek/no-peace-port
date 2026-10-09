class_name RdaArchive
extends RefCounted
## Read-only access to an original "RDAR" archive (america0..4.rda).
##
## Layout: "RDAR", u32 ?, u32 count, then `count` records of
## { char name[124]; u32 offset } starting at byte 12. A file ends where the next
## one starts (or at the end of the archive). Data is stored uncompressed.

const RECORD_SIZE := 128
const NAME_SIZE := 124

var path: String
var _file: FileAccess
var _entries := {}  # normalized path -> Vector2i(offset, size)


static func normalize(name: String) -> String:
	return name.replace("\\", "/").trim_prefix("./").to_lower()


func open(archive_path: String) -> Error:
	path = archive_path
	_file = FileAccess.open(archive_path, FileAccess.READ)
	if _file == null:
		return FileAccess.get_open_error()
	if _file.get_buffer(4).get_string_from_ascii() != "RDAR":
		return ERR_FILE_UNRECOGNIZED
	_file.get_32()
	var count := _file.get_32()
	var names := PackedStringArray()
	var offsets := PackedInt64Array()
	for i in count:
		_file.seek(12 + i * RECORD_SIZE)
		var raw := _file.get_buffer(NAME_SIZE)
		var end := raw.find(0)
		names.append(raw.slice(0, end if end >= 0 else NAME_SIZE).get_string_from_ascii())
		offsets.append(_file.get_32())
	var length := _file.get_length()
	for i in count:
		var next := offsets[i + 1] if i + 1 < count else length
		_entries[normalize(names[i])] = Vector2i(offsets[i], next - offsets[i])
	return OK


func has(name: String) -> bool:
	return _entries.has(normalize(name))


func read(name: String) -> PackedByteArray:
	var entry: Vector2i = _entries.get(normalize(name), Vector2i(-1, 0))
	if entry.x < 0:
		return PackedByteArray()
	_file.seek(entry.x)
	return _file.get_buffer(entry.y)


func list(prefix: String = "") -> PackedStringArray:
	var wanted := normalize(prefix)
	var out := PackedStringArray()
	for key: String in _entries:
		if key.begins_with(wanted):
			out.append(key)
	return out
