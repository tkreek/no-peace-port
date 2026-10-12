class_name MissionGoals
extends RefCounted
## The "Mission goals" page's contents: the goals given so far as one numbered list, the
## done ones crossed out, and the tips. A goal text ("MISSION GOALS: @ @1. ... @ @2. ...
## @ @TIP: ...") gives one goal per numbered paragraph (unnumbered paragraphs belong to the
## goal before them, or make one goal) and its TIP paragraphs are tips, as are the TIP
## messages. A goal is done when a later goal text no longer has it, or when a trigger that
## data/campaign_goals.json names for it has fired: {"set/code": {"<goal text id>":
## [[trigger, ...] per numbered goal]}} (the triggers that tell the player it is done).

const TABLE := "res://data/campaign_goals.json"
const HEADER := "^\\s*(MISSION GOALS?|GOAL CHANGES?|MISSION OBJECTIVES?)\\s*:?\\s*"
const NUMBER := "^\\s*\\d+\\s*[.)]\\s*"

static var _table := {}
static var _header := RegEx.create_from_string("(?i)" + HEADER)
static var _number := RegEx.create_from_string(NUMBER)


## {"goals": [{"text", "done"}], "tips": [text]}.
static func of(mission: Mission) -> Dictionary:
	var goals: Array[Dictionary] = []
	var tips: Array[String] = []
	var where := {}  # goal's key -> index in goals
	var history := mission.goals if not mission.goals.is_empty() \
			else (PackedInt32Array([mission.goal]) if mission.goal >= 0 else PackedInt32Array())
	var finished := _finishing(mission)
	for g in history.size():
		var parsed := parse(mission.text(history[g]))
		var current := g == history.size() - 1
		var done_by: Array = finished.get(str(history[g]), [])
		for i in parsed.goals.size():
			var text: String = parsed.goals[i]
			var key := _key(text)
			var done := not current
			if i < done_by.size():
				for trigger in done_by[i]:
					if int(trigger) < mission.ever_fired.size() and mission.ever_fired[int(trigger)]:
						done = true
			if where.has(key):
				goals[where[key]].done = done  # given again: as the latest text has it
			else:
				where[key] = goals.size()
				goals.append({"text": text, "done": done})
		for tip in parsed.tips:
			_add_tip(tips, tip)
	for m in mission.told:
		var text := _plain(mission.text(m[1]))
		if text.to_upper().begins_with("TIP"):
			_add_tip(tips, text)
	if mission.outcome > 0:
		for goal in goals:
			goal.done = true
	return {"goals": goals, "tips": tips}


## A goal text's goals and tips (without the header and numbers).
static func parse(text: String) -> Dictionary:
	var goals: Array[String] = []
	var tips: Array[String] = []
	var last := ""  # what the line before went to: "goal", "tip"
	var gap := false  # a blank line since
	for raw in text.split("\n"):
		var line := _plain(_header.sub(raw.strip_edges(), ""))
		if line == "":
			gap = true
			continue
		if line.to_upper().begins_with("TIP"):
			tips.append(line)
			last = "tip"
		elif _number.search(line):
			goals.append(_number.sub(line, ""))
			last = "goal"
		elif last == "tip" and not gap:
			tips[-1] += " " + line
		elif goals.is_empty():
			goals.append(line)
			last = "goal"
		else:
			goals[-1] += " " + line
			last = "goal"
		gap = false
	return {"goals": goals, "tips": tips}


## One line, a stray closing quote dropped (826: '... deputy sheriffs."').
static func _plain(text: String) -> String:
	var line := " ".join(Array(text.split("\n")).map(func(l: String) -> String: return l.strip_edges()).filter(
			func(l: String) -> bool: return l != ""))
	return line.trim_suffix("\"").strip_edges() if line.count("\"") % 2 == 1 else line


static func _key(text: String) -> String:
	var key := ""
	for c in text.to_lower():
		if c >= "a" and c <= "z":
			key += c
	return key


static func _add_tip(tips: Array[String], tip: String) -> void:
	var text := tip.substr(tip.find(":") + 1).strip_edges() if tip.find(":") >= 0 and tip.find(":") < 6 else tip
	if text != "" and text not in tips:
		tips.append(text)


## The table's entry for the mission being played.
static func _finishing(mission: Mission) -> Dictionary:
	if _table.is_empty() and FileAccess.file_exists(TABLE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		_table = parsed if parsed is Dictionary else {"": {}}
	var entry: Dictionary = Match.campaign
	return _table.get("%s/%s" % [entry.get("set", ""), entry.get("code", "")], {})
