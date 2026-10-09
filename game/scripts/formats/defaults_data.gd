class_name DefaultsData
extends RefCounted
## The level editor's default object data, Defaults.dat (text, shipped with the expansion):
##
##   GROUP "Mexikaner|1911" { GROUP "Einheiten|2183" {
##     UNIT "8. Infanterist|258" <index> TRUE -1 <kind> <steppe type> [<meadow type>]
##     { Einheiten.cfg  BILD "Potraits\einheiten_icons\mex\infanterist_icon.bmp"  ICONNR n
##       { <related GUIDs> }
##       <property> <+|-> <+|-> <value> "" ... } } }
##
## Property ids come from the editor's .cfg files: buildings 1 food, 2 wood, 4 gold, 5 guns,
## 6 production time, 7 energy, 8 capacity, 9 housing, 10 sight tier; units 101 food, 102 wood,
## 103 horses, 104 gold, 105 guns, 106 production time, 107 hit points, 110 speed tier,
## 111 carry capacity, 112 sight tier, 113 melee attack, 114 ranged attack, 115 range tier,
## 116/117 melee/ranged attack rate tiers, 119 living space, 120 minimum range tier.
## A "-" in the first flag column means the property doesn't apply.

const PATH := "Defaults.dat"
const FACTION_GROUPS := {"1910": "ind", "1911": "mex", "1912": "des", "1913": "usa"}
## Editor entries filed under the wrong GUID ("Rifle 2" reuses the Native Americans' "Steal").
const GUID_FIXES := {"Gewehr 2|923": 926}
const KIND_GROUPS := {"2182": "structure", "2183": "unit", "2184": "upgrade", "2185": "hero"}


## GUID -> stats dictionary in the same shape as data/stats.json (plus extra fields).
static func load() -> Dictionary:
	var text := GameData.read_latin1(PATH)
	if text.is_empty():
		return {}
	var out := {}
	var faction := ""
	var kind := ""
	var depth := 0
	var group_depth := {}  # depth -> "faction" | "kind"
	var current: Dictionary = {}
	var current_depth := -1
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "{":
			depth += 1
			continue
		if line == "}":
			if depth == current_depth:
				current = {}
				current_depth = -1
			if group_depth.get(depth - 1) == "faction":
				faction = ""
			elif group_depth.get(depth - 1) == "kind":
				kind = ""
			group_depth.erase(depth - 1)
			depth -= 1
			continue
		if line.begins_with("GROUP") or line.begins_with("NEUTRALGROUP") or line.begins_with("HIDDENGROUP"):
			var id := _label_id(line)
			if FACTION_GROUPS.has(id):
				faction = FACTION_GROUPS[id]
				group_depth[depth] = "faction"
			elif KIND_GROUPS.has(id):
				kind = KIND_GROUPS[id]
				group_depth[depth] = "kind"
			continue
		if line.begins_with("UNIT"):
			var guid := _label_id(line).to_int()
			if GUID_FIXES.has(line.get_slice("\"", 1)):
				guid = GUID_FIXES[line.get_slice("\"", 1)]
			var name := line.get_slice("\"", 1).get_slice("|", 0)
			name = name.substr(name.find(" ") + 1) if name.contains(". ") else name
			var fields := line.get_slice("\"", 2).strip_edges().split(" ", false)
			current = {"name_de": name, "faction": faction, "kind": kind, "properties": {}, "values": {},
					"types": []}
			for i in range(4, fields.size()):
				current.types.append(fields[i].to_int())
			out[guid] = current
			current_depth = depth + 1
			continue
		if current.is_empty():
			continue
		if line.begins_with("BILD"):
			current.icon = line.get_slice("\"", 1).replace("\\", "/")
			continue
		var parts := line.split(" ", false)
		if parts.size() >= 4 and parts[0].is_valid_int() and (parts[1] == "+" or parts[1] == "-"):
			# "+" marks the values the editor shows; switched-off ("-") entries still hold the
			# unit's rate and minimum range tiers.
			current.values[parts[0].to_int()] = parts[3].to_int()
			if parts[1] == "+":
				current.properties[parts[0].to_int()] = parts[3].to_int()
	return out


static func _label_id(line: String) -> String:
	return line.get_slice("|", 1).get_slice("\"", 0)


## Convert one Defaults entry into the stats shape the game uses (merging over `base`).
static func to_stats(entry: Dictionary, base: Dictionary) -> Dictionary:
	var stats := base.duplicate(true)
	var p: Dictionary = entry.properties
	var unit: bool = entry.kind in ["unit", "hero"]
	stats.faction = entry.faction if entry.faction != "" else stats.get("faction", "")
	stats.kind = "unit" if unit else ("structure" if entry.kind == "structure" else entry.kind)
	if not stats.has("name"):
		stats.name = entry.name_de
	var cost := {}
	var cost_ids := {"food": 101, "wood": 102, "horses": 103, "gold": 104, "guns": 105} if unit \
			else {"food": 1, "wood": 2, "gold": 4, "guns": 5}
	for key in cost_ids:
		if int(p.get(cost_ids[key], 0)) > 0:
			cost[key] = int(p[cost_ids[key]])
	if unit and p.has(119):
		cost["population"] = int(p[119])
	stats.cost = cost
	var health_id := 107 if unit else 7
	if p.has(health_id):
		stats.health = int(p[health_id])
	if p.has(106 if unit else 6):
		stats.build_time = int(p[106 if unit else 6])
	if unit:
		# Fighters keep their attack value in "Angriffswert Fern" (114) even when the range
		# tier (115) is 0, i.e. hand to hand; workers have only "Angriffswert Nah" (113).
		var v: Dictionary = entry.get("values", p)
		stats.melee = int(p.get(113, 0))
		stats.ranged = int(p.get(114, 0))
		stats.damage = stats.ranged if stats.ranged > 0 else stats.melee
		var tiers := {110: "speed_tier", 112: "sight_tier", 111: "carry"}
		for id in tiers:
			if p.has(id):
				stats[tiers[id]] = int(p[id])
		var combat_tiers := {115: "range_tier", 116: "melee_rate_tier", 117: "ranged_rate_tier", 120: "min_range_tier"}
		for id in combat_tiers:
			if v.has(id):
				stats[combat_tiers[id]] = int(v[id])
	else:
		if p.has(9):
			stats.housing = int(p[9])
		if p.has(8):
			stats.capacity = int(p[8])  # units that can take quarters inside (fort 10, tower 3)
		if p.has(10):
			stats.sight_tier = int(p[10])
	if entry.has("icon"):
		stats.icon = entry.icon
	stats.types = entry.types
	return stats
