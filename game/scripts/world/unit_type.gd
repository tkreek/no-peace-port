class_name UnitType
extends RefCounted
## Graphics for one original unit kind, loaded from its folder's .bob descriptor.
## Actions map to the original animation file names (laufen = walk, stehen = idle, ...).

## Actions and the original animation file names that play them, in order of preference
## (laufen = walk, fahren = drive, stehen = idle, ...). Vehicles drive, a few units carry
## their attack under another name (archers "kaempfen", throwers "werfen").
const ACTION_STEMS := {
	"walk": ["laufen", "fahren"],
	"idle": ["stehen"],
	"die": ["sterben", "dest", "_des"],
	"shoot": ["schiessen", "kaempfen_fern", "werfen", "kaempfen", "mpfen"],
	"melee": ["stechen", "kaempfen", "mpfen"],
	"fight": ["kaempfen", "mpfen"],
	"chop": ["hacken"],
	"build": ["haemmern", "bauen"],
	"carry_wood": ["holz_tragen"],
	"carry_wood_idle": ["holz_stehen", "stehen_holz", "holz_pause"],
	"carry_gold": ["gold_tragen", "sack_tragen", "gold_schleppen"],
	"carry_gold_idle": ["gold_stehen", "sack_stehen", "stehen_gold"],
	"harvest": ["ernten"],
	"carry_food": ["korb_tragen"],
	"carry_food_idle": ["korb_stehen"],
	"butcher": ["erlegen", "ausbeinen"],
	"heal": ["heilen", "tanzen"],
	"hide": ["tarnen", "einbuddeln"],
	"swim": ["swim"],
	"paddle": ["paddeln"],
	"idle_water": ["stehen_wasser"],
	"die_water": ["destroy_wasser"],
}
## Projectile sheets in a unit's folder (arrows, knives, tomahawks, cannonballs, dynamite).
const PROJECTILE_STEMS := ["pfeil", "messer", "tomahawk", "kugel", "dynamit"]
## The manual's hunting unit of each people.
const HUNTER_NAMES := ["Militiaman", "Trapper", "Arrow shooter", "Hunter"]
## Load per trip when the editor data gives none ("Tragkapazität": workers 15, wagons 100+).
const CARRY_AMOUNT := 10
const UNNAMED_VEHICLE := {"walk": 0, "idle": 2, "die": 4}

## Riding versions of the actions (commanders, cavalry and other units with horse sheets).
## The original files misspell a few of them (sterebn, stehen_reiten).
const MOUNTED_STEMS := {
	"walk": ["reiten"],
	"idle": ["stehen_pferd", "stehen_reiten"],
	"die": ["sterben_pferd", "sterebn_pferd"],
	"shoot": ["pferd_schiessen", "schiessen_pferd", "kaempfen_pferd"],
	"melee": ["stechen_pferd", "kaempfen_pferd", "mpfen_pferd"],
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
var min_range := 0.0  ## ranged units cannot fire at enemies closer than this
var projectile_anim := -1
var carry := CARRY_AMOUNT  ## resources carried per trip  ## a flying arrow, knife, tomahawk, cannonball or stick of dynamite


func guid() -> int:
	return GameData.guid_for_type(type_id)


func display_name() -> String:
	return GameData.type_name(type_id) if type_id >= 0 else directory.get_file().capitalize()


## The unit kind for a GUID, with that GUID's own stats (heroes share their sheets with
## ordinary units, and the mounted version uses the riding sheets).
static func for_guid(unit_guid: int) -> UnitType:
	var type := ObjectTypes.get_type(GameData.type_for_guid(unit_guid))
	if type == null:
		return null
	return load_type(type.directory(), type.name.contains("Pferd"), type.id)


static func load_type(dir: String, riding := false, forced_type_id := -1) -> UnitType:
	var key := dir + ("#mounted" if riding else "") + ("#%d" % forced_type_id if forced_type_id >= 0 else "")
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
	unit_type.type_id = forced_type_id
	if forced_type_id < 0:
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
## ms for ranged; walk speed in the original's units, ~0.6 px/s each). A range tier of 0
## means the unit fights hand to hand, whatever its attack is called.
func _setup_combat() -> void:
	var stats := GameData.stats(guid())
	health = stats.get("health", health)
	if int(stats.get("carry", 0)) > 0:
		carry = int(stats.carry)
	damage = stats.get("damage", damage)
	sight = GameData.def_value("Sichtweite%d" % int(stats.get("sight_tier", 1)), 320)
	speed = GameData.def_value("LaufenSpeed%d" % int(stats.get("speed_tier", 2)), 100) * 0.6
	ranged = int(stats.get("range_tier", 0)) >= 1 and int(stats.get("ranged", 0)) > 0
	var attack := anim_index("shoot" if ranged else "melee")
	if attack < 0 and ranged:
		attack = anim_index("melee")
	if ranged:
		attack_range = GameData.def_value("ReichweiteFernwaffe%d" % int(stats.get("range_tier", 2)), 200)
		min_range = GameData.def_value("MindestReichweite%d" % maxi(0, int(stats.get("min_range_tier", 0))), 0)
		reload_ms = GameData.def_value("KampffrequenzFern%d" % int(stats.get("ranged_rate_tier", 2)), 4000)
	else:
		attack_range = 36.0
		reload_ms = GameData.def_value("KampffrequenzNah%d" % int(stats.get("melee_rate_tier", 1)), 300) * 10
	if attack >= 0:
		# Attack sheets hold one to three blocks (aim, fire, reload) played in file order.
		var sheet := bob.anims[attack].sub_sprite
		for i in bob.anims.size():
			if bob.anims[i].sub_sprite == sheet:
				attack_anims.append(i)
		fire_step = mini(1, attack_anims.size() - 1)
	for stem in PROJECTILE_STEMS:
		var index := _find(stem, false, true)
		if index >= 0:
			projectile_anim = index
			break


## Animation index for an action name, or -1.
func anim_index(action: String) -> int:
	if action == "sow":
		return _sow_anim()
	if mounted and MOUNTED_STEMS.has(action):
		for stem in MOUNTED_STEMS[action]:
			var riding := _find(stem, true)
			if riding >= 0:
				return riding
	for stem in ACTION_STEMS.get(action, [action]):
		var index := _find(stem, false)
		if index >= 0:
			return index
	# Loose horses only have riding sheets.
	if not mounted and MOUNTED_STEMS.has(action):
		for stem in MOUNTED_STEMS[action]:
			var riding := _find(stem, true)
			if riding >= 0:
				return riding
	# The Mexican transport wagon's sheets are unnamed; wagons all use drive, stand, wreck.
	if UNNAMED_VEHICLE.has(action) and bob.sub_sprites.size() > 0 and bob.sub_sprites[0].to_lower().begins_with("bilderliste") \
			and bob.anims.size() > UNNAMED_VEHICLE[action]:
		return UNNAMED_VEHICLE[action]
	return -1


## First body animation whose file name contains `stem`. Unless `riding`, sheets that show
## the unit on horseback are skipped, so a cavalryman on foot never uses his mounted lance.
## `projectile` also accepts single-direction sheets (arrows in flight).
func _find(stem: String, riding: bool, projectile := false) -> int:
	for i in bob.anims.size():
		var sub := bob.anims[i].sub_sprite
		if sub >= bob.sub_sprites.size() or bob.sub_sprite_is_shadow[sub]:
			continue
		var file := bob.sub_sprites[sub].to_lower()
		if not file.contains(stem):
			continue
		if projectile:
			return i
		var on_horse := (file.contains("pferd") and not file.contains("ohne_pferd")) or file.contains("reiten")
		if on_horse and not riding:
			continue
		return i
	return -1


## Women and similar units that work fields rather than cutting wood for construction.
func is_farmer() -> bool:
	return can_gather("food") and not (can_gather("wood") and anim_index("build") >= 0)


## Builders (hammering animation) put up every structure (`guid`, or anything with -1).
## Women who farm without one (Mexican and American) only lay out fields (is_farmer).
func can_build(_guid := -1) -> bool:
	return anim_index("build") >= 0


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


## Wagons, travois and stagecoaches haul gold from gold warehouses to the main building.
func is_transport() -> bool:
	return carry >= 50 and attack_anims.is_empty()


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
