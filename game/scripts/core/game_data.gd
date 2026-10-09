extends Node
## Autoload "GameData": locates the original installation and serves files from its
## .rda archives. Nothing from the original game is shipped with this project; the
## player points the game at their own copy.
##
## Install dir resolution: --install-dir=<path> on the command line, then
## user://settings.cfg [paths] install_dir, then ../original/install/Programm (dev checkout).
## The expansion pack (america5..9.rda) is found in the install dir itself (a normal
## installation), or --addon-dir / [paths] addon_dir / ../original/expansion/install/Programm.
## Its archives take priority, and its data tables (global/guids2) replace the base ones.

const ARCHIVES := ["america0.rda", "america1.rda", "america2.rda", "america3.rda", "america4.rda"]
const ADDON_ARCHIVES := ["america5.rda", "america6.rda", "america7.rda", "america8.rda", "america9.rda"]
## Base data file -> expansion replacement.
const ADDON_TABLES := {
	"BobListe.blf": "global/guids2/BobListe2.blf",
	"global/guids/GUIDS.INI": "global/guids2/GUIDS.INI",
	"global/guids/Guids2.ini": "global/guids2/Guids2.ini",
	"global/guids/DEFS.INI": "global/guids2/DEFS.INI",
	"global/guids/rules.def": "global/guids2/rules.def",
}
const SETTINGS_PATH := "user://settings.cfg"

var install_dir := ""
var addon_dir := ""
var has_expansion := false
## Folder with the upscaled set from tools/upscale/hd_sprites.py; empty = classic graphics only.
var enhanced_dir := ""
var archives: Array[RdaArchive] = []
var _bob_cache := {}
var _sprite_cache := {}
var _palette_cache := {}
var _texts := {}       # text id -> String (TEXTE.eng, text2.eng)
var _guids := {}       # object type id -> GUID (GUIDS.INI steppe + Guids2.ini meadow)
var _defs := {}        # DEFS.INI key -> value
var _stats := {}
## Expansion units' production places (from the expansion manual), filled in by GUID.
const EXPANSION_PRODUCTION := {
	172: 103,  # tomahawk thrower: training tepee
	266: 221,  # armoured stagecoach: wood mill (coach factory)
	369: 318,  # saboteur: restaurant
	468: 427,  # pioneer: boot camp
}       # GUID -> stats from res://data/stats.json (extracted from the manual)


func _ready() -> void:
	install_dir = _resolve_install_dir()
	addon_dir = _resolve_addon_dir()
	enhanced_dir = _resolve_enhanced_dir()
	if not addon_dir.is_empty():
		for name in ADDON_ARCHIVES:
			var archive := RdaArchive.new()
			if archive.open(addon_dir.path_join(name)) == OK:
				archives.append(archive)
		has_expansion = not archives.is_empty()
	for name in ARCHIVES:
		var archive := RdaArchive.new()
		if archive.open(install_dir.path_join(name)) == OK:
			archives.append(archive)
	if not archives.is_empty():
		_load_tables()
	if archives.is_empty():
		push_error("No original game archives found in '%s'. Pass --install-dir=<folder with america0.rda>." % install_dir)


func is_ready() -> bool:
	return not archives.is_empty()


func cmdline_option(name: String, default: String = "") -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return default


func _resolve_install_dir() -> String:
	var from_args := cmdline_option("install-dir")
	if not from_args.is_empty():
		return from_args
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK and config.has_section_key("paths", "install_dir"):
		return config.get_value("paths", "install_dir")
	return ProjectSettings.globalize_path("res://").path_join("../original/install/Programm").simplify_path()


func _resolve_addon_dir() -> String:
	if cmdline_option("expansion") == "off":
		return ""
	if FileAccess.file_exists(install_dir.path_join("america5.rda")):
		return install_dir
	var dir := cmdline_option("addon-dir")
	if dir.is_empty():
		var config := ConfigFile.new()
		if config.load(SETTINGS_PATH) == OK and config.has_section_key("paths", "addon_dir"):
			dir = config.get_value("paths", "addon_dir")
		else:
			dir = ProjectSettings.globalize_path("res://").path_join("../original/expansion/install/Programm").simplify_path()
	return dir if FileAccess.file_exists(dir.path_join("america5.rda")) else ""


## A data table, from the expansion when it replaces it.
func table_path(base_path: String) -> String:
	if has_expansion and ADDON_TABLES.has(base_path) and exists(ADDON_TABLES[base_path]):
		return ADDON_TABLES[base_path]
	return base_path


func _resolve_enhanced_dir() -> String:
	if cmdline_option("graphics") == "classic":
		return ""
	var dir := cmdline_option("hd-dir")
	if dir.is_empty():
		var config := ConfigFile.new()
		if config.load(SETTINGS_PATH) == OK and config.has_section_key("paths", "hd_dir"):
			dir = config.get_value("paths", "hd_dir")
		else:
			dir = ProjectSettings.globalize_path("res://").path_join("../original/hd").simplify_path()
	return dir if DirAccess.dir_exists_absolute(dir) else ""


func read(path: String) -> PackedByteArray:
	for archive in archives:
		if archive.has(path):
			return archive.read(path)
	return PackedByteArray()


func exists(path: String) -> bool:
	for archive in archives:
		if archive.has(path):
			return true
	return false


func read_text(path: String) -> String:
	return read(path).get_string_from_ascii()


func load_image(path: String) -> Image:
	var bytes := read(path)
	return RdImage.pic_to_image(bytes) if not bytes.is_empty() else null


func load_bob(path: String) -> BobFile:
	var key := RdaArchive.normalize(path)
	if not _bob_cache.has(key):
		var text := read_text(path)
		_bob_cache[key] = BobFile.parse(text) if not text.is_empty() else null
	return _bob_cache[key]


func load_sprite(path: String) -> RdSprite:
	var key := RdaArchive.normalize(path)
	if not _sprite_cache.has(key):
		var enhanced := enhanced_dir.path_join(key)
		if not enhanced_dir.is_empty() and FileAccess.file_exists(enhanced + ".json"):
			_sprite_cache[key] = RdSprite.load_enhanced(enhanced)
		else:
			var bytes := read(path)
			_sprite_cache[key] = RdSprite.load_bytes(bytes) if not bytes.is_empty() else null
	return _sprite_cache[key]


## A 256 x N RGBA texture with one row per palette file (row 0 = base, 1..8 = teams).
func load_palette_texture(directory: String, files: PackedStringArray) -> ImageTexture:
	var key := RdaArchive.normalize(directory.path_join(",".join(files)))
	if _palette_cache.has(key):
		return _palette_cache[key]
	var image := Image.create_empty(256, maxi(1, files.size()), false, Image.FORMAT_RGBA8)
	for row in files.size():
		var colors := RdImage.read_palette(read(directory.path_join(files[row])))
		for i in colors.size():
			image.set_pixel(i, row, colors[i])
	var texture := ImageTexture.create_from_image(image)
	_palette_cache[key] = texture
	return texture


## Team colour ramps for an upscaled .bob (64 x 9), or null.
func load_ramps(bob_path: String) -> Texture2D:
	var path := enhanced_dir.path_join(RdaArchive.normalize(bob_path)) + ".ramps.png"
	if enhanced_dir.is_empty() or not FileAccess.file_exists(path):
		return null
	if not _palette_cache.has(path):
		_palette_cache[path] = ImageTexture.create_from_image(Image.load_from_file(path))
	return _palette_cache[path]


func _load_tables() -> void:
	for file in ["global/guids2/texte-Add-on.eng", "global/guids2/text2-Add-on.eng",
			"global/guids/TEXTE.eng", "global/guids/text2.eng"]:
		for line in read_latin1(file).split("\n"):
			var id := line.get_slice("=", 0).strip_edges()
			if "=" in line and id.is_valid_int() and not _texts.has(id.to_int()):
				_texts[id.to_int()] = line.substr(line.find("=") + 1).strip_edges()
	var stats_json = JSON.parse_string(FileAccess.get_file_as_string("res://data/stats.json"))
	if stats_json is Dictionary:
		for key in stats_json:
			_stats[int(key)] = stats_json[key]
	# The editor's Defaults.dat (expansion) holds the real values; the manual data still
	# supplies production places and prerequisite names.
	var defaults := DefaultsData.load()
	for guid in defaults:
		var entry: Dictionary = defaults[guid]
		if entry.kind in ["unit", "hero", "structure"]:
			_stats[guid] = DefaultsData.to_stats(entry, _stats.get(guid, {}))
			if _texts.has(guid):
				_stats[guid].name = _texts[guid]
	for guid in EXPANSION_PRODUCTION:
		if _stats.has(guid):
			_stats[guid].produced_at = EXPANSION_PRODUCTION[guid]
	for file in [table_path("global/guids/GUIDS.INI"), table_path("global/guids/Guids2.ini")]:
		for line in read_latin1(file).split("\n"):
			var parts := line.strip_edges().split("=")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				_guids[parts[0].to_int()] = parts[1].to_int()
	for line in read_latin1(table_path("global/guids/DEFS.INI")).split("\n"):
		var clean := line.get_slice("//", 0).strip_edges()
		if "=" in clean:
			_defs[clean.get_slice("=", 0).strip_edges()] = clean.get_slice("=", 1).strip_edges()


## Original files are Windows-1252/Latin-1; decode byte-for-byte.
func read_latin1(path: String) -> String:
	var bytes := read(path)
	var chars := PackedInt32Array()
	chars.resize(bytes.size())
	for i in bytes.size():
		chars[i] = bytes[i]
	return chars.to_byte_array().get_string_from_utf32().replace("\r", "")


func text(id: int, fallback: String = "") -> String:
	return _texts.get(id, fallback)


func guid_for_type(type_id: int) -> int:
	return _guids.get(type_id, -1)


## Display name of an object type (via its GUID), e.g. "Command post".
func type_name(type_id: int) -> String:
	var type := ObjectTypes.get_type(type_id)
	return text(guid_for_type(type_id), type.name if type else "?")


## Stats for a GUID: {name, faction, kind, cost, health, damage, produced_at, ...} or {}.
func stats(guid: int) -> Dictionary:
	return _stats.get(guid, {})


## GUIDs of the structures a GUID requires (parsed from the manual's prerequisite names).
func prerequisites(guid: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var stats := stats(guid)
	var text: String = stats.get("prerequisites", "")
	if text.is_empty():
		return out
	for raw in text.split(","):
		var wanted := _name_key(raw)
		for other in _stats:
			var candidate: Dictionary = _stats[other]
			if candidate.faction == stats.faction and candidate.kind == "structure" \
					and _name_key(candidate.name) == wanted:
				out.append(other)
				break
	return out


static func _name_key(name: String) -> String:
	var key := ""
	for c in name.to_lower():
		if c >= "a" and c <= "z":
			key += c
	return key


func stats_guids() -> Array:
	return _stats.keys()


## Object type id for a GUID in a biome (buildings and scenery differ per biome; units don't).
func type_for_guid(guid: int, biome: String = "steppe") -> int:
	var meadow := biome == "wiese"
	var fallback := -1
	for type_id in _guids:
		if _guids[type_id] != guid:
			continue
		var type := ObjectTypes.get_type(type_id)
		if type == null or type.bob_path.is_empty():
			continue
		if type.is_meadow() == meadow:
			return type_id
		fallback = type_id
	return fallback


func def_value(key: String, fallback := 0) -> int:
	return str(_defs.get(key, fallback)).to_int()


func maps_dir() -> String:
	return install_dir.path_join("Levels")


## Skirmish maps from both installs: base .alf and expansion .ulf.
func map_files() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in [install_dir.path_join("Levels"), addon_dir.path_join("Levels") if not addon_dir.is_empty() else ""]:
		if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() in ["alf", "ulf"]:
				out.append(dir.path_join(file))
	return out
