class_name UnitRemains
extends RefCounted
## What is left of a dead person or animal (assets: effects/decay): a few seconds after the
## death animation the body rots, turns to bones and the bones scatter, facing the way the
## unit fell. Riders who die on horseback leave rider and horse together. Vehicles, boats and
## the drowned leave nothing of the kind; a carcass with meat left stays whole until the
## hunters have picked it clean.

const STARTS_AFTER := 4.0
const ANIMALS := {
	"animal_buffalo": "effects/decay/buffalo/decay_buffalo.anims.json",
	"animal_cow": "effects/decay/cow/decay_cow.anims.json",
	"animal_horse": "effects/decay/horse/decay_horse.anims.json",
}
const PERSON := "effects/decay/human/decay_human.anims.json"
const RIDER := "effects/decay/rider/decay_human_from_horse.anims.json"
## Type name words of units that are machines or boats rather than living things.
const NOT_ALIVE := ["cannon", "wagon", "coach", "boat", "canoe", "raft", "travois", "gatling", "ironclad", "transport"]

var unit: Unit
var _set_path := ""
var _bob: BobFile
var _sprite: Sprite2D
var _step := -1
var _time := 0.0


## The remains a unit leaves, or null.
static func of(dead: Unit) -> UnitRemains:
	var type := ObjectTypes.get_type(dead.unit_type.type_id)
	var name := type.name if type else dead.unit_type.directory
	var path := ""
	for animal in ANIMALS:
		if name.begins_with(animal) or dead.unit_type.directory.ends_with(animal.trim_prefix("animal_")):
			path = ANIMALS[animal]
	if path.is_empty():
		if NOT_ALIVE.any(func(word: String) -> bool: return name.contains(word)) or dead._action.ends_with("water"):
			return null
		path = RIDER if dead.unit_type.mounted else PERSON
	var remains := UnitRemains.new()
	remains.unit = dead
	remains._set_path = path
	remains._bob = GameData.load_bob(path)
	return remains if remains._bob and not remains._bob.anims.is_empty() else null


## Advance by `delta` while the body lies (`lying` = seconds since death or since the
## hunters last worked it).
func update(delta: float, lying: float) -> void:
	if _step < 0:
		if lying < STARTS_AFTER or unit.animal.has_meat():
			return
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.region_enabled = true
		unit.add_child(_sprite)
		unit.hide_body()
		_step = 0
		_show()
		return
	var anim := _bob.anims[0]
	_time += delta * 1000.0
	if _step + 1 < anim.frames.size() and _time >= anim.durations_ms[_step]:
		_time = 0.0
		_step += 1
		_show()


func _show() -> void:
	var anim := _bob.anims[0]
	var sheet := GameData.load_set_sheet(_set_path, _bob, anim.sub_sprite)
	if sheet == null:
		return
	var frame := (unit.direction % anim.directions) * anim.frames_per_direction + anim.frames[_step]
	if frame < sheet.frame_count():
		SpriteMaterials.prepare(_sprite, sheet)
		sheet.apply(_sprite, frame)
