class_name Campaign
extends RefCounted
## The campaigns as the asset builder lists them (data/campaign.json): per set (the base
## game's, the expansion's) and people, the missions in order with their maps, titles,
## stories, narration and pictures, plus the texts their scripts show. Also which missions
## the player has won (user://campaign.json): each people's campaign opens one mission at a
## time, as the original's does.

const PROGRESS := "user://campaign.json"
const SETS := ["base", "expansion"]
## The peoples in the order the campaign screen shows them, and the tutorials.
const PEOPLES := ["ind", "mex", "des", "usa"]
const TUTORIAL := "tut"

static var _data := {}
static var _progress := {}


static func data() -> Dictionary:
	if _data.is_empty() and GameData.exists("data/campaign.json"):
		_data = GameData.read_json("data/campaign.json")
	return _data


static func has_set(set_name: String) -> bool:
	return data().has(set_name)


## The missions of `people` in a set, in order.
static func missions(set_name: String, people: String) -> Array:
	return data().get(set_name, {}).get("missions", {}).get(people, [])


static func texts(set_name: String) -> Dictionary:
	return data().get(set_name, {}).get("texts", {})


## The entry for "base/ind_01" (a set and a mission code), with "set" and "people" added.
static func mission_entry(id: String) -> Dictionary:
	var parts := id.split("/")
	var set_name := parts[0] if parts.size() > 1 else "base"
	var code := parts[-1]
	var people := code.split("_")[0]
	for m in missions(set_name, people):
		if m.code == code:
			var entry: Dictionary = m.duplicate()
			entry["set"] = set_name
			entry["people"] = people
			return entry
	push_error("No campaign mission %s" % id)
	return {}


static func title(entry: Dictionary) -> String:
	if entry.get("people") == TUTORIAL:
		return "Tutorial %d" % int(entry.get("number", 1))
	return String(entry.get("title", entry.get("code", "")))


## The briefing: the old storyteller's tale, "@" being a line break.
static func story(entry: Dictionary) -> String:
	return String(entry.get("story", "")).replace(" @ @", "\n\n").replace("@", "\n").strip_edges()


static func people_name(set_name: String, people: String) -> String:
	var index := PEOPLES.find(people)
	if index < 0:
		return "Tutorials"
	return String(data().get(set_name, {}).get("titles", {}).get(str(40 + index), Match.faction_name(people)))


static func art(key: String) -> String:
	return String(data().get("art", {}).get(key, ""))


# ------------------------------------------------------------------ progress

static func _load_progress() -> void:
	if not _progress.is_empty() or not FileAccess.file_exists(PROGRESS):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS))
	if parsed is Dictionary:
		_progress = parsed


static func won(set_name: String, code: String) -> bool:
	_load_progress()
	return bool(_progress.get("%s/%s" % [set_name, code], false))


## Missions the player may start: every one won, and the first not yet won.
static func unlocked(set_name: String, people: String) -> int:
	var list := missions(set_name, people)
	var n := 0
	while n < list.size() and won(set_name, list[n].code):
		n += 1
	return mini(n + 1, list.size())


static func record_won(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	_load_progress()
	_progress["%s/%s" % [entry.set, entry.code]] = true
	_save_progress()


## The difficulty chosen for campaign missions (Match.DIFFICULTY_NAMES; medium at first).
static func difficulty() -> int:
	_load_progress()
	return clampi(int(_progress.get("difficulty", 2)), 0, Match.DIFFICULTY_TEXT.size() - 1)


static func set_difficulty(level: int) -> void:
	_load_progress()
	_progress["difficulty"] = level
	_save_progress()


static func _save_progress() -> void:
	var file := FileAccess.open(PROGRESS, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_progress))


## The mission after `entry` in its campaign, or empty after the last.
static func next(entry: Dictionary) -> Dictionary:
	var list := missions(entry.get("set", "base"), entry.get("people", ""))
	for i in list.size() - 1:
		if list[i].code == entry.get("code"):
			return mission_entry("%s/%s" % [entry.set, list[i + 1].code])
	return {}
