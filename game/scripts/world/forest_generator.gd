class_name ForestGenerator
extends RefCounted
## Grows the forests painted into a map, as the original level loader's "terraforming
## laubwald / nadelwald" step does: forests are not stored as objects but as forest terrain
## tiles, and the game plants tree objects on them when the level loads.
##
## Forest tiles are the last rows of the biome atlas: 6760..7079 deciduous (Laubwald) and
## 7080..7399 coniferous (Nadelwald) edge/fill tiles. Inside them palette index 5 is forest
## floor, 31 the open ground outside and 6 the dithered border between.

const DECIDUOUS := Vector2i(6760, 7080)
const CONIFEROUS := Vector2i(7080, 7400)
const FLOOR_INDEX := 5
const BORDER_INDEX := 6
const SPACING := 56.0
const JITTER := 18.0
const KEEP_CLEAR := 96.0  # around mines and other objects
const START_CLEAR := 320.0  # around player start points
## Wood per tree from Defaults.dat (Rohstoffe 302): large 250, small 200, bare 150.
const WOOD := {"gr": 250, "kl": 200, "ohne": 150}


class PlantedTree:
	var position := Vector2.ZERO
	var type_id := 0
	var wood := 200


static func is_forest_tile(tile: int) -> bool:
	return tile >= DECIDUOUS.x and tile < CONIFEROUS.y


static func generate(map: AlfMap, biome: String, avoid: Array[Vector2], starts: Array) -> Array[PlantedTree]:
	var trees: Array[PlantedTree] = []
	var atlas := RdImage.read_indexed_pic(GameData.read("%s/gfx/landschaft/steppe.pic" % biome))
	if atlas.is_empty():
		return trees
	var pixels: PackedByteArray = atlas.pixels
	var width: int = atlas.width
	var per_row := width / AlfMap.CELL_SIZE
	var kinds := {"laub": _tree_types("Baum_Laub", biome), "nadel": _tree_types("Baum_Nadel", biome)}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map.title)
	var size := Vector2(map.pixel_size())
	var y := SPACING / 2.0
	while y < size.y:
		var x := SPACING / 2.0
		while x < size.x:
			var p := Vector2(x + rng.randf_range(-JITTER, JITTER), y + rng.randf_range(-JITTER, JITTER))
			x += SPACING
			var cell := Vector2i(clampi(int(p.x) / AlfMap.CELL_SIZE, 0, map.columns - 1),
					clampi(int(p.y) / AlfMap.CELL_SIZE, 0, map.rows - 1))
			var tile := map.tile_ids[cell.y * map.columns + cell.x]
			if not is_forest_tile(tile):
				continue
			var local := Vector2i(int(p.x) % AlfMap.CELL_SIZE, int(p.y) % AlfMap.CELL_SIZE)
			var index := pixels[((tile / per_row) * AlfMap.CELL_SIZE + local.y) * width
					+ (tile % per_row) * AlfMap.CELL_SIZE + local.x]
			if index != FLOOR_INDEX and not (index == BORDER_INDEX and rng.randf() < 0.4):
				continue
			if NavGrid.current and not NavGrid.current.is_walkable(NavGrid.current.cell_of(p)):
				continue
			if _near(p, avoid, KEEP_CLEAR) or _near(p, starts, START_CLEAR):
				continue
			var options: Array = kinds.laub if tile < DECIDUOUS.y else kinds.nadel
			if options.is_empty():
				continue
			var tree := PlantedTree.new()
			tree.position = p.round()
			tree.type_id = options[rng.randi() % options.size()]
			var name := ObjectTypes.get_type(tree.type_id).name
			for size_key in WOOD:
				if name.contains("_%s" % size_key):
					tree.wood = WOOD[size_key]
			trees.append(tree)
		y += SPACING
	return trees


## Tree object types of one kind for the biome (all sizes and colour variants a/b/c).
static func _tree_types(prefix: String, biome: String) -> Array:
	var suffix := "_Wi" if biome == "wiese" else "_St"
	var out := []
	for id in ObjectTypes.count():
		var type := ObjectTypes.get_type(id)
		if type and type.name.begins_with(prefix) and type.name.ends_with(suffix) and not type.bob_path.is_empty():
			out.append(id)
	return out


static func _near(p: Vector2, points: Array, radius: float) -> bool:
	for q in points:
		if p.distance_to(q) < radius:
			return true
	return false
