class_name Patches
extends RefCounted
## The remake's own departures from the original's rules, in one place: res://data/patches.json
## lists each (title, why, default, values). The code keeps the original's values, cited by
## their addresses in AmericaAddOn.exe, and asks here whether a patch replaces them:
##
##     if Patches.on("very_easy_help"): ...
##     var seconds := Patches.value("faster_self_healing", "interval_seconds", ORIGINAL_SECONDS)
##
## A match fixes its set when it starts (begin): the player's choices from Settings for a new
## game, the save's for a loaded one, the replay's for a replay, the host's in a network game.
## Game logic reads only that set, so every machine plays by the same rules.
## docs/production/patches.md says how to add one.

const PATH := "res://data/patches.json"

static var _defs := {}  # id -> {title, why, default, values}
static var _active := {}  # id -> true: the patches this match plays with


## Every patch's definition, in file order.
static func definitions() -> Dictionary:
	if _defs.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			for id in data:
				if not String(id).begins_with("_") and data[id] is Dictionary:
					_defs[id] = data[id]
	return _defs


## The player's choice for each patch (Settings), its default where they made none.
static func preferred() -> Dictionary:
	var chosen := {}
	for id in definitions():
		chosen[id] = Settings.patch_enabled(id, bool(_defs[id].get("default", false)))
	return chosen


## The original's rules: every patch off.
static func none() -> Dictionary:
	var chosen := {}
	for id in definitions():
		chosen[id] = false
	return chosen


## Fix this match's set: {id: bool}. Patches it does not name keep their default (saves and
## replays from before a patch existed).
static func begin(chosen: Dictionary) -> void:
	_active.clear()
	for id in definitions():
		if bool(chosen.get(id, _defs[id].get("default", false))):
			_active[id] = true
	Match.patches = active()


## This match's set as {id: bool} (for saves, replays and the network).
static func active() -> Dictionary:
	var out := {}
	for id in definitions():
		out[id] = _active.has(id)
	return out


static func on(id: String) -> bool:
	return _active.has(id)


## The patch's value for `key` while it is on, else `original` (the original game's).
static func value(id: String, key: String, original: Variant) -> Variant:
	if not _active.has(id):
		return original
	return definitions()[id].get("values", {}).get(key, original)
