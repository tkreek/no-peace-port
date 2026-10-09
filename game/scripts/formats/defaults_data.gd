class_name DefaultsData
extends RefCounted
## The expansion level editor's default object data (assets: data/defaults.json, made from
## the original Defaults.dat): per GUID {name_de, faction, kind, types, icon, properties,
## values}. Property ids come from the editor's .cfg files: buildings 1 food, 2 wood,
## 4 gold, 5 guns, 6 production time, 7 energy, 8 capacity, 9 housing, 10 sight tier;
## units 101 food, 102 wood, 103 horses, 104 gold, 105 guns, 106 production time, 107 hit
## points, 110 speed tier, 111 carry capacity, 112 sight tier, 113 melee attack, 114
## ranged attack, 115 range tier, 116/117 melee/ranged attack rate tiers, 119 living space,
## 120 minimum range tier. `properties` holds the values the editor shows ("+"), `values`
## also the switched-off ones, which still carry rate and minimum range tiers.

const PATH := "data/defaults.json"


## GUID -> entry (property ids as ints).
static func load() -> Dictionary:
	var data = GameData.read_json(PATH)
	var out := {}
	if not data is Dictionary:
		return out
	for key in data:
		var entry: Dictionary = data[key]
		for table in ["properties", "values"]:
			var by_id := {}
			for id in entry.get(table, {}):
				by_id[int(id)] = int(entry[table][id])
			entry[table] = by_id
		entry.types = Array(entry.get("types", [])).map(func(t) -> int: return int(t))
		out[int(key)] = entry
	return out


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
