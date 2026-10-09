class_name UnitType
extends RefCounted
## Graphics for one original unit kind, loaded from its folder's .bob descriptor.
## Actions map to the original animation file names (laufen = walk, stehen = idle, ...).

const ACTION_STEMS := {
	"walk": "laufen",
	"idle": "stehen",
	"die": "sterben",
	"shoot": "schiessen",
	"melee": "stechen",
}

static var _cache := {}

var directory := ""
var bob: BobFile
var palette: ImageTexture
var ramps: Texture2D
var speed := 60.0
var type_id := -1  ## object type id (BobListe.blf), for names and stats


func guid() -> int:
	return GameData.guid_for_type(type_id)


func display_name() -> String:
	return GameData.type_name(type_id) if type_id >= 0 else directory.get_file().capitalize()


static func load_type(dir: String) -> UnitType:
	if _cache.has(dir):
		return _cache[dir]
	var bob_path := ""
	for archive in GameData.archives:
		for path in archive.list(dir + "/"):
			if path.ends_with(".bob") and path.count("/") == dir.count("/") + 1:
				bob_path = path
	if bob_path.is_empty():
		push_error("No .bob in %s" % dir)
		return null
	var unit_type := UnitType.new()
	unit_type.directory = dir
	unit_type.bob = GameData.load_bob(bob_path)
	unit_type.palette = GameData.load_palette_texture(dir, unit_type.bob.palettes)
	unit_type.ramps = GameData.load_ramps(bob_path)
	for id in ObjectTypes.count():
		var t := ObjectTypes.get_type(id)
		if t.kind == ObjectTypes.Kind.UNIT and t.bob_path == bob_path:
			unit_type.type_id = id
			break
	_cache[dir] = unit_type
	return unit_type


## Animation index for an action name, or -1.
func anim_index(action: String) -> int:
	return bob.find_anim(ACTION_STEMS.get(action, action))


func sprite_for(anim_index_value: int) -> RdSprite:
	var anim := bob.anims[anim_index_value]
	return GameData.load_sprite(directory.path_join(bob.sub_sprites[anim.sub_sprite]))
