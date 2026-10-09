class_name ObjectTypes
extends RefCounted
## The object types (assets: data/object_types.json, made from the original BobListe.blf):
## one entry per type id (the ids maps and the GUID table use), with its English name (the
## original German one translated, e.g. tree_deciduous_large_01_prairie), kind, animation
## set and the animations it shows, and its footprint on the 16 px collision grid.
## Names end in _prairie or _meadow for the landscape variants of buildings and nature.

enum Kind { NONE = 0, UNIT = 1, BUILDING = 2, ELEMENT = 3 }

const PATH := "data/object_types.json"
const FOOTPRINT_CELL := 16


class ObjectType:
	var id := 0
	var name := ""
	var anims := ""  ## animation set (.anims.json); empty for placeholders
	var kind := Kind.NONE
	var anim := 0
	var shadow_anim := -1
	var footprint_anchor := Vector2i.ZERO
	var footprint_size := Vector2i.ZERO
	var footprint_grid := Vector2i.ZERO
	var footprint_cells := PackedInt32Array()

	func directory() -> String:
		return anims.get_base_dir()

	func is_meadow() -> bool:
		return name.ends_with("_meadow")

	## Units on horseback (and loose horses) use the riding sheets.
	func is_mounted() -> bool:
		return name.ends_with("_mounted") or name == "animal_horse"


static var _types: Array[ObjectType] = []


static func get_type(id: int) -> ObjectType:
	if _types.is_empty():
		_load()
	return _types[id] if id >= 0 and id < _types.size() else null


static func count() -> int:
	if _types.is_empty():
		_load()
	return _types.size()


## The first type with this name, or -1.
static func named(name: String) -> int:
	for id in count():
		if _types[id].name == name:
			return id
	return -1


static func _load() -> void:
	var data = GameData.read_json(PATH)
	if not data is Array:
		push_error("%s missing or invalid" % PATH)
		return
	for entry: Dictionary in data:
		var t := ObjectType.new()
		t.id = int(entry.id)
		t.name = entry.name
		t.anims = entry.get("anims", "")
		t.kind = int(entry.get("kind", 0)) as Kind
		t.anim = int(entry.get("anim", 0))
		t.shadow_anim = int(entry.get("shadow_anim", -1))
		if entry.has("footprint"):
			var f: Dictionary = entry.footprint
			t.footprint_anchor = Vector2i(f.anchor[0], f.anchor[1])
			t.footprint_size = Vector2i(f.size[0], f.size[1])
			t.footprint_grid = Vector2i(f.grid[0], f.grid[1])
			t.footprint_cells = PackedInt32Array(f.cells)
		_types.append(t)
