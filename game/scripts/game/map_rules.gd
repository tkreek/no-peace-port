class_name MapRules
extends RefCounted
## A map's own rules per player, on top of the game's defaults: what each player may build,
## train and research (the EINHEIT chunk) and the object properties it changes for each
## (EIGENSCH). Read as AmericaAddOn.exe's level loader does (0x442b08..0x442e5b, see
## docs/technical/file-formats.md "Per-player tables"):
##
## * both chunks hold 9 blocks: the neutral player's, then one per SPIELER record, which
##   counts for the record's player number (for player 1 when the record is unused);
## * EINHEIT: `u32 count` + `{i32 id, i32 value}`; a later record for the same player and
##   object replaces an earlier one. Value 0 takes the object's button out of that player's
##   menus (0x42c3d0, asked by 0x46a600 for structures, units and upgrades; horses, cows,
##   guns, liquor and fields ask the neutral player's table). Objects a map does not list
##   keep Defaults.bin's value, which is 1 for everything the game makes;
## * EIGENSCH: `u32 count` + `{i32 id, i32 property, i32 value, i32 use_default}`; records
##   with use_default 0 set the property for that player (the first one for a property
##   counts), the rest of its table comes from Defaults.bin.
##
## Ids are IDS.INI's (data/ids.json), not GUIDs; a few GUIDs share one (wall pieces).
## Only the interface asks `allows`: the original's computer players are not held to it.
##
## The base game's campaign maps were made for, and played with, the base game's own stat
## table (global/guids/Defaults.bin), not the expansion's that the remake runs on
## (defaults.json): for them its values (data/defaults_base.json, where the two differ)
## come under the map's own.

## Things made from the neutral player's table, by the remake's queue GUID (0x46a600).
const NEUTRAL_MADE := {BuildingProduction.HORSE_GUID: 480, BuildingProduction.COW_GUID: 482,
		BuildingProduction.GUN_GUID: 710, BuildingProduction.LIQUOR_GUID: 711, MapObject.FIELD_GUID: 149}
const BLOCKS := 9

static var _ids := {}  # GUID -> id
static var _guids := {}  # id -> GUIDs
static var _switched := {}  # player -> {id: value}
static var _properties := {}  # player -> {GUID: {property: value}}
static var _base := {}  # GUID -> {property: value}: the base game's table, in a base campaign map
static var _merged := {}  # Vector2i(player, GUID) -> the properties that differ from defaults.json
static var _stats := {}  # Vector2i(player, GUID) -> stats with the player's properties
static var _unit_types := {}  # [UnitType instance id, player] -> that player's version


## Read `map`'s tables (none: everything as the defaults); `base_game`: a map of the base
## game's campaign, played with the base game's stat table.
static func setup(map: AlfMap, base_game := false) -> void:
	clear()
	if base_game:
		var table = GameData.read_json("data/defaults_base.json")
		if table is Dictionary:
			for key in table:
				var props := {}
				for id in table[key]:
					props[id.to_int()] = int(table[key][id])
				_base[key.to_int()] = props
	if _ids.is_empty():
		var ids = GameData.read_json("data/ids.json")
		if ids is Dictionary:
			for key in ids:
				_ids[key.to_int()] = int(ids[key])
				if not _guids.has(int(ids[key])):
					_guids[int(ids[key])] = []
				_guids[int(ids[key])].append(key.to_int())
	if map == null or _ids.is_empty():
		return
	var owners := _block_owners(map.chunks.get("SPIELER", PackedByteArray()))
	var units: PackedByteArray = map.chunks.get("EINHEIT", PackedByteArray())
	var at := 0
	for block in BLOCKS:
		if at + 4 > units.size():
			break
		var count := units.decode_s32(at)
		at += 4
		var table: Dictionary = _switched.get_or_add(owners[block], {})
		for i in maxi(0, count):
			if at + 8 > units.size():
				break
			table[units.decode_s32(at)] = units.decode_s32(at + 4)
			at += 8
	var properties: PackedByteArray = map.chunks.get("EIGENSCH", PackedByteArray())
	at = 0
	for block in BLOCKS:
		if at + 4 > properties.size():
			break
		var count := properties.decode_s32(at)
		at += 4
		var table: Dictionary = _properties.get_or_add(owners[block], {})
		for i in maxi(0, count):
			if at + 16 > properties.size():
				break
			var id := properties.decode_s32(at)
			if properties.decode_s32(at + 12) == 0:
				for guid in _guids.get(id, []):
					var own: Dictionary = table.get_or_add(guid, {})
					if not own.has(properties.decode_s32(at + 4)):
						own[properties.decode_s32(at + 4)] = properties.decode_s32(at + 8)
			at += 16


static func clear() -> void:
	_switched.clear()
	_properties.clear()
	_base.clear()
	_merged.clear()
	_stats.clear()
	_unit_types.clear()


## The player number each block counts for: 0 for the neutral block, then each SPIELER
## record's (1 for records without a people or a player number from 1 to 8).
static func _block_owners(players: PackedByteArray) -> PackedInt32Array:
	var owners := PackedInt32Array([0, 1, 1, 1, 1, 1, 1, 1, 1])
	for slot in mini(8, players.size() / MissionData.PLAYER_RECORD):
		var at := slot * MissionData.PLAYER_RECORD
		var number := players.decode_s32(at)
		if players.decode_s32(at + 0x10C) >= 0 and number >= 1 and number <= 8:
			owners[slot + 1] = number
	return owners


## Whether `player`'s menus offer `guid` in this map.
static func allows(player: int, guid: int) -> bool:
	if NEUTRAL_MADE.has(guid):
		player = 0
		guid = NEUTRAL_MADE[guid]
	var table: Dictionary = _switched.get(player, {})
	return table.is_empty() or not _ids.has(guid) or int(table.get(_ids[guid], 1)) != 0


## The properties `player`'s `guid` has here that differ from defaults.json (property id
## -> value): the base game's table, then the map's own.
static func properties(player: int, guid: int) -> Dictionary:
	var key := Vector2i(player, guid)
	if not _merged.has(key):
		var own: Dictionary = _base.get(guid, {}).duplicate()
		if NEUTRAL_MADE.has(guid) and guid != MapObject.FIELD_GUID:
			own.merge(_properties.get(0, {}).get(NEUTRAL_MADE[guid], {}), true)
		else:
			own.merge(_properties.get(player, {}).get(guid, {}), true)
		_merged[key] = own
	return _merged[key]


## GameData.stats(guid) as `player` has them in this map.
static func stats(player: int, guid: int) -> Dictionary:
	var own := properties(player, guid)
	if own.is_empty():
		return GameData.stats(guid)
	var key := Vector2i(player, guid)
	if not _stats.has(key):
		var changed := GameData.stats(guid).duplicate(true)
		DefaultsData.apply_properties(changed, own)
		_stats[key] = changed
	return _stats[key]


## `type` as `player`'s units have it: its own combat values where the map changes them.
static func unit_type(type: UnitType, player: int) -> UnitType:
	if type == null or properties(player, type.guid()).is_empty():
		return type
	var key := [type.get_instance_id(), player]
	if not _unit_types.has(key):
		_unit_types[key] = type.for_player(player)
	return _unit_types[key]
