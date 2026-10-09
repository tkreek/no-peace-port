class_name TerrainRules
extends RefCounted
## The expansion level editor's terrain rules, which the map editor paints with (assets:
## terrain/<landscape>/rules.json, made from the original Steppe.gfs / wiese.gfs; see
## docs/technical/file-formats.md):
##   flags     4 collision flags per atlas tile (one per 16 px quarter, as in a map's grid)
##   materials 18 material names
##   blocks    [{a, b (-1 = plain a), size [w, h], shape, grids: 8x8 tile id grids per variant}]
## Ordinary blocks are 2x2 tiles (64 px): a plain material, or a transition between two
## neighbouring materials whose shape code says which of the block's six lattice points
## (see TerrainPainter) lie in A or in B. The cliffs between ground and plateau use larger
## and differently coded pieces, which the editor does not paint yet.

const PLAIN := 35  ## shape code of a plain (single-material) block in a map's LVMATRIX
## Shape codes by the material at the block's lattice points TL, TR, ML, MR, BL, BR.
const SHAPES := {
	"BBBAAA": 1, "BBBABA": 2, "BABABA": 4, "BABAAA": 5, "AABABB": 7, "BABABB": 8,
	"AABABA": 11, "BBABAA": 13, "BBABAB": 14, "ABABAB": 16, "ABABAA": 17, "AAABBB": 19,
	"ABABBB": 20, "AAABAB": 23, "AAABAA": 25, "AABAAA": 26, "BBAAAA": 27, "AAAABB": 28,
	"BBBABB": 29, "BBABBB": 30, "AABBBB": 31, "BBBBAA": 32, "AABBAA": 33, "BBAABB": 34,
}
## English names of the materials (the .gfs names them in German: steppe, Ödland, Stein,
## Weg, Wüste, Ufer, Wasser, Höhe, Nadelwald, Laubwald).
const NAMES := ["Steppe", "Steppe (dry)", "Wasteland", "Wasteland (dry)", "Stone", "Path",
		"Desert", "Desert (dunes)", "Shore", "Shallow water", "Water", "Deep water",
		"Plateau", "Plateau grass", "Plateau grass (dry)", "High plateau", "Conifer forest",
		"Deciduous forest"]
const MEADOW_NAMES := {0: "Meadow", 1: "Meadow (lush)", 2: "Grassland", 3: "Grassland (lush)"}
## What the editor offers: everything but the plateau family, which needs cliff pieces.
const PAINTABLE := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 16, 17]
const UNKNOWN := 255

static var _cache := {}
var _routes := {}  # from * 64 + to -> path()

var biome := "steppe"
var flags := PackedInt32Array()  ## four per atlas tile
var plain := {}  ## material -> Array of [tl, tr, bl, br] tile ids
var blocks := {}  ## Vector2i(a, b) -> {shape code: Array of [tl, tr, bl, br]}
var neighbours := {}  ## material -> Array of materials it blends into
## Atlas tile -> Vector4i(material A, material B or -1, shape code, quarter 0..3).
var tile_shape := {}


## The rules for a biome, or null without the expansion's editor data.
static func for_biome(biome_name: String) -> TerrainRules:
	if _cache.has(biome_name):
		return _cache[biome_name]
	var rules: TerrainRules = null
	var data = GameData.read_json(Terrain.folder_for(biome_name).path_join("rules.json"))
	if data is Dictionary:
		rules = TerrainRules.new()
		rules.biome = biome_name
		rules._parse(data)
	_cache[biome_name] = rules
	return rules


func _parse(data: Dictionary) -> void:
	flags = PackedInt32Array(data.flags)
	for record: Dictionary in data.blocks:
		var a := int(record.a)
		var b := int(record.b)
		var code := int(record.shape)
		if int(record.size[0]) != 2 or int(record.size[1]) != 2 or (b >= 0 and not SHAPES.values().has(code)):
			continue
		var list: Array = []
		for grid: Array in record.grids:
			var block := [int(grid[0]), int(grid[1]), int(grid[8]), int(grid[9])]
			if block.has(-1):
				continue
			list.append(block)
			for q in 4:
				if not tile_shape.has(block[q]):
					tile_shape[block[q]] = Vector4i(a, b, code if b >= 0 else PLAIN, q)
		if list.is_empty():
			continue
		if b < 0:
			plain[a] = plain.get(a, []) + list
		else:
			var pair := Vector2i(a, b)
			if not blocks.has(pair):
				blocks[pair] = {}
				neighbours[a] = neighbours.get(a, []) + [b]
				neighbours[b] = neighbours.get(b, []) + [a]
			blocks[pair][code] = blocks[pair].get(code, []) + list


func material_name(material: int) -> String:
	if biome == "wiese" and MEADOW_NAMES.has(material):
		return MEADOW_NAMES[material]
	return NAMES[material] if material >= 0 and material < NAMES.size() else "?"


func tile_flags(tile: int, quarter: int) -> int:
	var index := tile * 4 + quarter
	return flags[index] if index >= 0 and index < flags.size() else 0x7


## The materials on the way from `from` to `to` through the blend graph (both included),
## or empty when they are not connected.
func path(from: int, to: int) -> Array:
	var key := from * 64 + to
	if not _routes.has(key):
		_routes[key] = _find_path(from, to)
	return _routes[key]


func _find_path(from: int, to: int) -> Array:
	if from == to:
		return [from]
	var came := {from: -1}
	var queue := [from]
	while not queue.is_empty():
		var at: int = queue.pop_front()
		for next: int in neighbours.get(at, []):
			if came.has(next):
				continue
			came[next] = at
			if next == to:
				var out := [to]
				while came[out[0]] != -1:
					out.push_front(came[out[0]])
				return out
			queue.append(next)
	return []


func distance(a: int, b: int) -> int:
	if a == b:
		return 0
	var route := path(a, b)
	return route.size() - 1 if not route.is_empty() else 99
