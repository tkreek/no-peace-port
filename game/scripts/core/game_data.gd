extends Node
## Autoload "GameData": serves the game's assets and data tables from the asset folder
## (made from the original game by tools/assets/build_assets.py; nothing from the original
## game is shipped with this project).
##
## Asset folder: --assets-dir=<path> on the command line, then user://settings.cfg
## [paths] assets_dir, then assets/ beside the game folder (a project checkout) or beside
## the executable (an exported build).
##
## Paths are relative to the asset folder: sprite sheets without extension (RdSprite),
## animation sets as <name>.anims.json (BobFile), pictures as .png.

const SETTINGS_PATH := "user://settings.cfg"
const OBJECT_TYPES := "data/object_types.json"

var assets_dir := ""
## The expansion's data (editor defaults, terrain painting rules) is part of the assets.
var has_expansion := false
var _bob_cache := {}
var _sprite_cache := {}
var _ramps_cache := {}
var _texts := {}       # text id -> String
var _menu_texts := {}  # text id -> String (menu captions, a separate numbering)
var _guids := {}       # object type id -> GUID
var _defs := {}        # game constants: name -> value or list by tier
var _stats := {}
## Expansion units' production places (from the expansion manual), filled in by GUID.
const EXPANSION_PRODUCTION := {
	172: 103,  # tomahawk thrower: training tepee
	266: 221,  # armoured stagecoach: wood mill (coach factory)
	369: 318,  # saboteur: restaurant
	468: 427,  # pioneer: boot camp
}       # GUID -> stats from res://data/stats.json (extracted from the manual)


func _ready() -> void:
	assets_dir = _resolve_assets_dir()
	if is_ready():
		has_expansion = exists("data/defaults.json")
		_load_tables()
	else:
		push_error("No asset folder at '%s'. Build it with tools/assets/build_assets.py or pass --assets-dir=<folder>." % assets_dir)


func is_ready() -> bool:
	return FileAccess.file_exists(assets_dir.path_join(OBJECT_TYPES))


func cmdline_option(name: String, default: String = "") -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return default


func _resolve_assets_dir() -> String:
	var from_args := cmdline_option("assets-dir")
	if not from_args.is_empty():
		return from_args
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK and config.has_section_key("paths", "assets_dir"):
		return config.get_value("paths", "assets_dir")
	var base := ProjectSettings.globalize_path("res://").path_join("..") if OS.has_feature("editor") \
			else OS.get_executable_path().get_base_dir()
	return base.path_join("assets").simplify_path()


## Absolute path of an asset.
func path(asset: String) -> String:
	return assets_dir.path_join(asset)


func read(asset: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path(asset))


func exists(asset: String) -> bool:
	return FileAccess.file_exists(path(asset))


func read_text(asset: String) -> String:
	return FileAccess.get_file_as_string(path(asset))


func read_json(asset: String) -> Variant:
	return JSON.parse_string(read_text(asset)) if exists(asset) else null


## The asset files in a folder (names only).
func list(folder: String) -> PackedStringArray:
	return DirAccess.get_files_at(path(folder)) if DirAccess.dir_exists_absolute(path(folder)) else PackedStringArray()


func load_image(asset: String) -> Image:
	return Image.load_from_file(path(asset)) if exists(asset) else null


## An animation set (<name>.anims.json).
func load_bob(asset: String) -> BobFile:
	if not _bob_cache.has(asset):
		_bob_cache[asset] = BobFile.from_json(read_text(asset)) if exists(asset) else null
	return _bob_cache[asset]


## A sprite sheet: <asset>.png with its frames in <asset>.json.
func load_sprite(asset: String) -> RdSprite:
	if not _sprite_cache.has(asset):
		_sprite_cache[asset] = RdSprite.load_sheet(path(asset)) if exists(asset + ".json") else null
	return _sprite_cache[asset]


## A sheet of an animation set, by the set's path and the sheet's index.
func load_set_sheet(set_path: String, bob: BobFile, sheet: int) -> RdSprite:
	return load_sprite(set_path.get_base_dir().path_join(bob.sub_sprites[sheet]).simplify_path())


## Team colour ramps of an animation set (64 x 9: row t = team t's colour by shading), or null.
func load_ramps(set_path: String) -> Texture2D:
	var ramps := set_path.trim_suffix(".anims.json") + ".ramps.png"
	if not _ramps_cache.has(ramps):
		_ramps_cache[ramps] = ImageTexture.create_from_image(load_image(ramps)) if exists(ramps) else null
	return _ramps_cache[ramps]


func _load_tables() -> void:
	var texts: Dictionary = read_json("data/texts.json")
	for key in texts:
		_texts[key.to_int()] = texts[key]
	var menu: Dictionary = read_json("data/menu_texts.json")
	for key in menu:
		_menu_texts[key.to_int()] = menu[key]
	var stats_json = JSON.parse_string(FileAccess.get_file_as_string("res://data/stats.json"))
	if stats_json is Dictionary:
		for key in stats_json:
			var entry: Dictionary = stats_json[key]
			# JSON numbers load as floats; GUID lists must be ints to match unit GUIDs.
			if entry.has("applies_to_guids"):
				entry.applies_to_guids = entry.applies_to_guids.map(func(g) -> int: return int(g))
			if entry.has("produced_at") and entry.produced_at is float:
				entry.produced_at = int(entry.produced_at)
			_stats[int(key)] = entry
	# The expansion editor's defaults (data/defaults.json) hold the real values; the manual
	# data still supplies production places and prerequisite names.
	var defaults := DefaultsData.load()
	for guid in defaults:
		var entry: Dictionary = defaults[guid]
		if entry.kind in ["unit", "hero", "structure"]:
			_stats[guid] = DefaultsData.to_stats(entry, _stats.get(guid, {}))
			if _texts.has(guid):
				_stats[guid].name = _texts[guid]
		elif entry.kind == "upgrade" and _stats.has(guid) and entry.has("icon"):
			_stats[guid].icon = entry.icon  # upgrade stats come from the manual; take the picture
	# Mounted units are trained where their foot version is ("mounted: + 1 horse").
	var by_name := {}
	for guid in _stats:
		if _stats[guid].get("kind") == "unit":
			by_name["%s|%s" % [_stats[guid].get("faction"), String(_stats[guid].get("name", "")).to_lower()]] = guid
	for guid in _stats:
		var st: Dictionary = _stats[guid]
		var name := String(st.get("name", ""))
		if st.get("kind") == "unit" and name.begins_with("Mounted "):
			var rider_on_foot: int = by_name.get("%s|%s" % [st.get("faction"), name.substr(8).to_lower()], -1)
			if rider_on_foot >= 0:
				_mounted_of[rider_on_foot] = guid
				_foot_of[guid] = rider_on_foot
		if st.get("kind") == "unit" and name.begins_with("Mounted ") and not st.has("produced_at"):
			var foot: int = by_name.get("%s|%s" % [st.get("faction"), name.substr(8).to_lower()], -1)
			if foot >= 0 and _stats[foot].has("produced_at"):
				st.produced_at = _stats[foot].produced_at
	# Trades at the trading post (buy: green arrow, sell: red arrow icons in SonstigeIcons).
	for i in BuildingProduction.TRADES.size():
		var trade: Dictionary = BuildingProduction.TRADES[i]
		_stats[BuildingProduction.TRADE_GUID + i] = {"kind": "trade", "name": "%s %s" % ["Buy" if trade.buy else "Sell", trade.good],
				"faction": "", "build_time": 6, "cost": {}, "icon_frame": trade.icon}
	_stats[BuildingProduction.COW_GUID] = {"kind": "cow", "name": "Cow", "faction": "", "build_time": 15,
			"cost": {"food": 40}, "icon": "portraits/other/z_08_cow.png",
			"function": "Raises a cow; it gains up to 25 gold of value while grazing"}
	# The American "Stagecoach" upgrade (editor GUID 990) the manual lists at the sawmill.
	if not _stats.has(BuildingProduction.STAGECOACH_UPGRADE):
		_stats[BuildingProduction.STAGECOACH_UPGRADE] = {"kind": "upgrade", "faction": "usa", "name": "Stagecoach",
				"produced_at": 409, "cost": {"food": 150, "wood": 150, "gold": 250}, "effects": {},
				"function": "Allows stagecoaches to be built", "applies_to": "Stagecoaches", "applies_to_guids": [456]}
	# Making a rifle at the weapons factory (manual 4.3; GUID 710 "Guns" has no editor entry).
	_stats[BuildingProduction.GUN_GUID] = {"kind": "gun", "name": "Rifle",
			"faction": "", "build_time": 12, "cost": {"wood": 40, "gold": 40},
			"function": "Makes a rifle for the units that need one", "icon_frame": 52}
	# Raising a horse (manual: corral, hacienda, ranch; "costs food"; no editor entry).
	_stats[BuildingProduction.HORSE_GUID] = {"kind": "horse", "name": "Horse", "faction": "", "build_time": 20,
			"cost": {"food": 50}, "icon": "portraits/other/z_02_horse.png",
			"function": "Raises a horse for mounted units (each horse building shelters %d)" % BuildingProduction.HORSES_PER_BUILDING}
	for guid in EXPANSION_PRODUCTION:
		if _stats.has(guid):
			_stats[guid].produced_at = EXPANSION_PRODUCTION[guid]
	# The expansion manual's values for its new units, structures and upgrades (the editor's
	# defaults differ for some): res://data/expansion_manual.json, applied last.
	var manual = JSON.parse_string(FileAccess.get_file_as_string("res://data/expansion_manual.json"))
	if manual is Dictionary and has_expansion:
		for key in manual:
			if not key.is_valid_int():
				continue
			var entry: Dictionary = _stats.get(key.to_int(), {})
			for field in manual[key]:
				var value = manual[key][field]
				if field == "cost":
					value = (value as Dictionary).duplicate()
					for k in value:
						value[k] = int(value[k])
				elif value is float:
					value = int(value)
				elif field == "applies_to_guids":
					value = value.map(func(g) -> int: return int(g))
				entry[field] = value
			if not entry.has("icon") and defaults.has(key.to_int()):
				entry.icon = defaults[key.to_int()].get("icon", "")
			_stats[key.to_int()] = entry
	var guids: Dictionary = read_json("data/guids.json")
	for key in guids:
		_guids[key.to_int()] = int(guids[key])
	_defs = read_json("data/defs.json")


func text(id: int, fallback: String = "") -> String:
	return _texts.get(id, fallback)


## A caption from the menus' own text table (Menu.eng).
func menu_text(id: int, fallback: String = "") -> String:
	return _menu_texts.get(id, fallback)


func guid_for_type(type_id: int) -> int:
	return _guids.get(type_id, -1)


## Display name of an object type (via its GUID), e.g. "Command post".
func type_name(type_id: int) -> String:
	var type := ObjectTypes.get_type(type_id)
	return text(guid_for_type(type_id), type.name if type else "?")


## Stats for a GUID: {name, faction, kind, cost, health, damage, produced_at, ...} or {}.
var _mounted_of := {}  # foot unit GUID -> its mounted version
var _foot_of := {}


## The riding version of a unit (-1 if it cannot ride) and back.
func mounted_of(guid: int) -> int:
	return _mounted_of.get(guid, -1)


func foot_of(guid: int) -> int:
	return _foot_of.get(guid, -1)


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
		if type == null or type.anims.is_empty():
			continue
		if type.is_meadow() == meadow:
			return type_id
		fallback = type_id
	return fallback


## A game constant by tier, e.g. def_tier("sight_range", 2) (sight, ranges, attack rates,
## walking speeds; from the original DEFS.INI).
func def_tier(table: String, tier: int, fallback := 0) -> int:
	var values: Array = _defs.get(table, [])
	return int(values[tier]) if tier >= 0 and tier < values.size() else fallback


func maps_dir() -> String:
	return path("maps")


## Where the map editor saves: maps/ next to the game folder (beside assets/) when run
## from the project, next to the executable in an exported build.
func custom_maps_dir() -> String:
	var base := ProjectSettings.globalize_path("res://").path_join("..") if OS.has_feature("editor") \
			else OS.get_executable_path().get_base_dir()
	return base.path_join("maps").simplify_path()


## Skirmish maps: the original ones (assets/maps) and the map editor's.
func map_files() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in [maps_dir(), custom_maps_dir()]:
		if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() in ["alf", "ulf"]:
				out.append(dir.path_join(file))
	return out
