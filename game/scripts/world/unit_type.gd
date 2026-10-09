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
	"fight": "kaempfen",
	"chop": "hacken",
	"build": "haemmern",
	"carry_wood": "holz_tragen",
	"carry_wood_idle": "holz_stehen",
	"carry_gold": "gold_tragen",
	"carry_gold_idle": "gold_stehen",
	"harvest": "ernten",
	"carry_food": "korb_tragen",
	"carry_food_idle": "korb_stehen",
}
## The manual's hunting unit of each people.
const HUNTER_NAMES := ["Militiaman", "Trapper", "Arrow shooter", "Hunter"]
## Alternative file names some factions use for the same action.
const ACTION_FALLBACKS := {
	"carry_gold": ["sack_tragen", "gold_schleppen"],
	"carry_gold_idle": ["sack_stehen", "stehen_gold"],
	"carry_wood_idle": ["stehen_holz"],
	"melee": ["kaempfen", "mpfen"],  # "kämpfen" with the umlaut in some file names
	"fight": ["mpfen"],
	"build": ["bauen"],
}
const CARRY_AMOUNT := 10

## Riding versions of the actions (commanders, cavalry and other units with horse sheets).
const MOUNTED_STEMS := {
	"walk": ["reiten"],
	"idle": ["stehen_pferd"],
	"die": ["sterben_pferd"],
	"shoot": ["pferd_schiessen", "schiessen_pferd"],
	"melee": ["kaempfen_pferd", "mpfen_pferd"],
	"fight": ["kaempfen_pferd", "mpfen_pferd"],
}

static var _cache := {}

var directory := ""
var bob: BobFile
var palette: ImageTexture
var ramps: Texture2D
var speed := 60.0
var type_id := -1  ## object type id (BobListe.blf), for names and stats
var mounted := false  ## uses the riding sheets and the "+Pferd" type's stats
var health := 50.0
var damage := 5
var ranged := false
var attack_range := 40.0
var sight := 320.0
var reload_ms := 1500
## Body animation indices played in order for one attack (e.g. aim, fire, reload).
var attack_anims := PackedInt32Array()
var fire_step := 0  ## index into attack_anims at which the shot/blow lands


func guid() -> int:
	return GameData.guid_for_type(type_id)


func display_name() -> String:
	return GameData.type_name(type_id) if type_id >= 0 else directory.get_file().capitalize()


static func load_type(dir: String, riding := false) -> UnitType:
	var key := dir + ("#mounted" if riding else "")
	if _cache.has(key):
		return _cache[key]
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
	unit_type.mounted = riding
	unit_type.bob = GameData.load_bob(bob_path)
	unit_type.palette = GameData.load_palette_texture(dir, unit_type.bob.palettes)
	unit_type.ramps = GameData.load_ramps(bob_path)
	for id in ObjectTypes.count():
		var t := ObjectTypes.get_type(id)
		if t.kind == ObjectTypes.Kind.UNIT and t.bob_path == bob_path \
				and t.name.contains("Pferd") == riding:
			unit_type.type_id = id
			break
	unit_type._setup_combat()
	_cache[key] = unit_type
	return unit_type


## Combat and movement values from the unit's stats. Defaults.dat gives tiers that index
## DEFS.INI's tables (sight and ranges in pixels; attack rates in 1/100 s for melee and
## ms for ranged; walk speed in the original's units, ~0.6 px/s each).
func _setup_combat() -> void:
	var stats := GameData.stats(guid())
	health = stats.get("health", health)
	damage = stats.get("damage", damage)
	sight = GameData.def_value("Sichtweite%d" % int(stats.get("sight_tier", 1)), 320)
	speed = GameData.def_value("LaufenSpeed%d" % int(stats.get("speed_tier", 2)), 100) * 0.6
	# Ranged units have a firing sheet: its body blocks are aim, fire, reload (in file order).
	var shoot := anim_index("shoot")
	if shoot >= 0:
		ranged = true
		if stats.has("ranged"):
			damage = maxi(1, int(stats.ranged))
		attack_range = GameData.def_value("ReichweiteFernwaffe%d" % int(stats.get("range_tier", 2)), 200)
		reload_ms = GameData.def_value("KampffrequenzFern%d" % int(stats.get("ranged_rate_tier", 2)), 4000)
		var sheet := bob.anims[shoot].sub_sprite
		for i in bob.anims.size():
			if bob.anims[i].sub_sprite == sheet:
				attack_anims.append(i)
		fire_step = mini(1, attack_anims.size() - 1)
	else:
		var melee := anim_index("melee")
		if melee >= 0:
			attack_anims.append(melee)
		if int(stats.get("melee", 0)) > 0:
			damage = int(stats.melee)
		attack_range = 36.0
		reload_ms = GameData.def_value("KampffrequenzNah%d" % int(stats.get("melee_rate_tier", 1)), 300) * 10


## Animation index for an action name, or -1.
func anim_index(action: String) -> int:
	if action == "sow":
		return _sow_anim()
	if mounted and MOUNTED_STEMS.has(action):
		for stem in MOUNTED_STEMS[action]:
			var riding := bob.find_anim(stem)
			if riding >= 0:
				return riding
	var index := bob.find_anim(ACTION_STEMS.get(action, action))
	for alternative in ACTION_FALLBACKS.get(action, []):
		if index >= 0:
			break
		index = bob.find_anim(alternative)
	return index


## Women and similar units that work fields rather than cutting wood for construction.
func is_farmer() -> bool:
	return can_gather("food") and not (can_gather("wood") and anim_index("build") >= 0)


## Builders (hammering animation) put up every structure; women who farm can also put up
## their people's grain store (granary, finca, farm), which they need before fields.
## guid -1 asks whether the unit can build anything at all.
func can_build(guid := -1) -> bool:
	if anim_index("build") >= 0:
		return true
	return is_farmer() and (guid < 0 or guid in MapObject.FOOD_STORES)


## "säen" is spelled several ways in the file names (saehen, sähen, sähene).
func _sow_anim() -> int:
	for i in bob.anims.size():
		var sub := bob.anims[i].sub_sprite
		if bob.sub_sprite_is_shadow[sub]:
			continue
		var file := bob.sub_sprites[sub].to_lower()
		if file.contains("aehen") or (file.contains("_s") and file.contains("hen") and not file.contains("stehen")):
			return i
	return -1


func is_hunter() -> bool:
	return GameData.stats(guid()).get("name", "") in HUNTER_NAMES


func can_gather(resource: String) -> bool:
	match resource:
		"food":
			return anim_index("harvest") >= 0
		"wood":
			return anim_index("chop") >= 0 and anim_index("carry_wood") >= 0
		"gold":
			return anim_index("carry_gold") >= 0
	return false


func sprite_for(anim_index_value: int) -> RdSprite:
	var anim := bob.anims[anim_index_value]
	return GameData.load_sprite(directory.path_join(bob.sub_sprites[anim.sub_sprite]))
