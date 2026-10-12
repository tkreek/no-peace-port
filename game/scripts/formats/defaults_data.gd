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
## also the switched-off ones. The "+" set is exactly the expansion game's own
## guids2/Defaults.bin; the game reads a missing property as 0 and never reads the
## switched-off values, nor 117 (see docs/technical/file-formats.md, "Combat in the
## executable").

const PATH := "data/defaults.json"

## How often a fighter attacks, in ms. AmericaAddOn.exe hard-codes this per unit class
## rather than reading the ranged rate (117) and DEFS.INI's KampffrequenzFern: 1500 for
## units with a gun or bow, 1000 for the rest; the classes below are the exceptions.
const FIGHTER_RELOAD_MS := 1500
const RELOAD_MS := {
	150: 1000, 151: 1000, 162: 1000, 259: 1000, 260: 1000, 266: 1000, 270: 1000, 271: 1000,
	272: 1000, 273: 1000, 274: 1000, 275: 1000, 362: 1000, 454: 1000,  # chiefs, spearmen, lancers
	359: 2500, 468: 2500,  # dynamite
	265: 5000, 465: 5000,  # cannons
}
## Units of the game's worker classes: they hit with their melee attack (113) at the melee
## rate (116, DEFS.INI's KampffrequenzNah x 10 ms). Every other unit is a fighter, whose
## attack (114) reaches the range tier's distance (tier 0: 64 px) every RELOAD_MS.
const WORKERS := [152, 153, 155, 164, 252, 253, 254, 255, 256, 257, 352, 355, 364, 452, 453,
		455, 456, 457]


## What the game charges (AmericaAddOn.exe 0x4564a0 for units and upgrades, 0x40cc50 for
## structures); a unit's living space (119) is checked when it is done, not paid.
const UNIT_COST := {"food": 101, "wood": 102, "horses": 103, "gold": 104, "guns": 105}
const STRUCTURE_COST := {"food": 1, "wood": 2, "gold": 4, "guns": 5}


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
	var cost := _cost(p, UNIT_COST if unit else STRUCTURE_COST)
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
		stats.melee = int(p.get(113, 0))
		stats.ranged = int(p.get(114, 0))
		stats.damage = stats.ranged if stats.ranged > 0 else stats.melee
		var tiers := {110: "speed_tier", 112: "sight_tier", 111: "carry"}
		for id in tiers:
			if p.has(id):
				stats[tiers[id]] = int(p[id])
		var combat_tiers := {115: "range_tier", 116: "melee_rate_tier", 120: "min_range_tier"}
		for id in combat_tiers:
			stats[combat_tiers[id]] = int(p.get(id, 0))
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


## Properties a map changes (id -> value, see MapRules) into `stats` as to_stats reads them:
## structures 1-10, everything else (units, upgrades, horses, cows, guns, liquor) 101-120.
static func apply_properties(stats: Dictionary, p: Dictionary) -> void:
	var structure: bool = stats.get("kind") == "structure"
	var cost: Dictionary = stats.get("cost", {}).duplicate()
	var cost_ids := STRUCTURE_COST if structure else UNIT_COST
	for key in cost_ids:
		if p.has(cost_ids[key]):
			if int(p[cost_ids[key]]) > 0:
				cost[key] = int(p[cost_ids[key]])
			else:
				cost.erase(key)
	if not structure and p.has(119):
		cost["population"] = int(p[119])
	stats.cost = cost
	if p.has(7 if structure else 107):
		stats.health = int(p[7 if structure else 107])
	if p.has(6 if structure else 106):
		stats.build_time = int(p[6 if structure else 106])
	var fields := {8: "capacity", 9: "housing", 10: "sight_tier"} if structure else {110: "speed_tier",
			111: "carry", 112: "sight_tier", 113: "melee", 114: "ranged", 115: "range_tier",
			116: "melee_rate_tier", 120: "min_range_tier"}
	for id in fields:
		if p.has(id):
			stats[fields[id]] = int(p[id])
	if not structure and (p.has(113) or p.has(114)):
		stats.damage = int(stats.get("ranged", 0)) if int(stats.get("ranged", 0)) > 0 else int(stats.get("melee", 0))


## An upgrade's cost and production time (106) into `stats` (the manual's entry, which
## names it and says what it does; its costs and times are not the game's).
static func apply_upgrade(entry: Dictionary, stats: Dictionary) -> void:
	var p: Dictionary = entry.properties
	stats.cost = _cost(p, UNIT_COST)
	if p.has(106):
		stats.build_time = int(p[106])
	if entry.has("icon"):
		stats.icon = entry.icon


static func _cost(p: Dictionary, ids: Dictionary) -> Dictionary:
	var cost := {}
	for key in ids:
		if int(p.get(ids[key], 0)) > 0:
			cost[key] = int(p[ids[key]])
	return cost
