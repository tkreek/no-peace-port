class_name UnitType
extends RefCounted
## Graphics for one unit kind, loaded from its animation set (BobFile). Actions map to the
## sheet names (walk, idle, die, ...: the original file names, translated).

## Actions and the sheet names that play them, in order of preference. Vehicles drive, a
## few units carry their attack under another name (archers "fight", throwers "throw").
const ACTION_STEMS := {
	"walk": ["walk", "drive"],
	"idle": ["idle"],
	"die": ["die", "destroyed"],
	"shoot": ["shoot", "fight_ranged", "throw", "fight"],
	"melee": ["stab", "fight"],
	"fight": ["fight"],
	"chop": ["chop"],
	"build": ["hammer", "build"],
	"carry_wood": ["wood_carry"],
	"carry_wood_idle": ["wood_idle", "idle_wood", "wood_pause"],
	"carry_gold": ["gold_carry", "sack_carry", "gold_drag"],
	"carry_gold_idle": ["gold_idle", "sack_idle", "idle_gold"],
	"harvest": ["harvest"],
	"carry_food": ["basket_carry"],
	"carry_food_idle": ["basket_idle"],
	"butcher": ["butcher", "debone"],
	"heal": ["heal", "dance"],
	"hide": ["hide", "dig_in"],
	"swim": ["swim"],
	"paddle": ["paddle"],
	"idle_water": ["idle_water"],
	"die_water": ["destroyed_water"],
}
## Projectile sheets in a unit's set (arrows, knives, tomahawks, cannonballs, dynamite).
const PROJECTILE_STEMS := ["arrow", "knife", "tomahawk", "ball", "dynamite"]
## The manual's hunting unit of each people.
const HUNTER_NAMES := ["Militiaman", "Trapper", "Arrow shooter", "Hunter"]
## Load per trip when the editor data gives none ("Tragkapazität": workers 15, wagons 100+).
const CARRY_AMOUNT := 10
const UNNAMED_VEHICLE := {"walk": 0, "idle": 2, "die": 4}

## Riding versions of the actions (commanders, cavalry and other units with horse sheets).
const MOUNTED_STEMS := {
	"walk": ["ride"],
	"idle": ["idle_horse", "ride_idle"],
	"die": ["die_horse"],
	"shoot": ["horse_shoot", "shoot_horse", "fight_horse"],
	"melee": ["stab_horse", "fight_horse"],
	"fight": ["fight_horse"],
}

static var _cache := {}

var directory := ""
var set_path := ""  ## the animation set (.anims.json)
var bob: BobFile
var ramps: Texture2D
## A walk speed of 100 (workers, foot soldiers) covers 100 px a second: measured from a
## recording of the original, where workers cross about 100 px of the map each second.
const PX_PER_SPEED := 1.0
## Fighting keeps pace with the walking (which went from 0.6 to 1 px/s per speed point):
## the pause between attacks from DEFS.INI's rates is shortened in proportion.
const RELOAD_SCALE := 0.6
var speed := 100.0
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
## Frame of the firing animation at which the shot leaves (-1: when it has played out).
## A cannon's sheet opens with the muzzle flash, so its ball is away at once.
var release_frame := -1
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
	return load_type(type.directory(), type.is_mounted(), type.id)


## The unit kind drawn from the animation sets in `dir`: the one of object type
## `forced_type_id`, else the first unit type there (riding or not), else the folder's
## first set.
static func load_type(dir: String, riding := false, forced_type_id := -1) -> UnitType:
	var key := dir + ("#mounted" if riding else "") + ("#%d" % forced_type_id if forced_type_id >= 0 else "")
	if _cache.has(key):
		return _cache[key]
	var set_path := ""
	var type_id := forced_type_id
	if forced_type_id >= 0 and ObjectTypes.get_type(forced_type_id) and ObjectTypes.get_type(forced_type_id).directory() == dir:
		set_path = ObjectTypes.get_type(forced_type_id).anims
	else:
		for id in ObjectTypes.count():
			var t := ObjectTypes.get_type(id)
			if t.kind == ObjectTypes.Kind.UNIT and t.directory() == dir and t.is_mounted() == riding:
				set_path = t.anims
				if type_id < 0:
					type_id = id
				break
	if set_path.is_empty():
		for file in GameData.list(dir):
			if file.ends_with(".anims.json"):
				set_path = dir.path_join(file)
				break
	if set_path.is_empty():
		push_error("No animation set in %s" % dir)
		return null
	var unit_type := UnitType.new()
	unit_type.directory = dir
	unit_type.set_path = set_path
	unit_type.mounted = riding
	unit_type.bob = GameData.load_bob(set_path)
	unit_type.ramps = GameData.load_ramps(set_path)
	unit_type.type_id = type_id
	unit_type._setup_combat()
	_cache[key] = unit_type
	return unit_type


## Combat and movement values from the unit's stats. Defaults.dat gives tiers that index
## DEFS.INI's tables (sight and ranges in pixels; attack rates in 1/100 s for melee and
## ms for ranged; walk speed in px/s, PX_PER_SPEED each). A range tier of 0
## means the unit fights hand to hand, whatever its attack is called.
func _setup_combat() -> void:
	var stats := GameData.stats(guid())
	health = stats.get("health", health)
	if int(stats.get("carry", 0)) > 0:
		carry = int(stats.carry)
	damage = stats.get("damage", damage)
	sight = GameData.def_tier("sight_range", int(stats.get("sight_tier", 1)), 320)
	speed = GameData.def_tier("walk_speed", int(stats.get("speed_tier", 2)), 100) * PX_PER_SPEED
	ranged = int(stats.get("range_tier", 0)) >= 1 and int(stats.get("ranged", 0)) > 0
	var attack := anim_index("shoot" if ranged else "melee")
	if attack < 0 and ranged:
		attack = anim_index("melee")
	if ranged:
		attack_range = GameData.def_tier("ranged_range", int(stats.get("range_tier", 2)), 200)
		min_range = GameData.def_tier("min_range", maxi(0, int(stats.get("min_range_tier", 0))), 0)
		reload_ms = int(GameData.def_tier("ranged_rate", int(stats.get("ranged_rate_tier", 2)), 4000) * RELOAD_SCALE)
	else:
		attack_range = 36.0
		reload_ms = int(GameData.def_tier("melee_rate", int(stats.get("melee_rate_tier", 1)), 300) * 10 * RELOAD_SCALE)
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
			if stem == "ball":
				release_frame = 1
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
	if UNNAMED_VEHICLE.has(action) and bob.sub_sprites.size() > 0 and bob.sub_sprites[0].get_file().begins_with("sheet") \
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
		var file := bob.sub_sprites[sub].get_file()
		if not file.contains(stem):
			continue
		if projectile:
			return i
		var on_horse := (file.contains("horse") and not file.contains("without_horse")) or file.contains("ride")
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


func _sow_anim() -> int:
	return _find("sow", false)


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
	return GameData.load_set_sheet(set_path, bob, anim.sub_sprite)
