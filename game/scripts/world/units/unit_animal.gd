class_name UnitAnimal
extends UnitPart
## Animals: meat for the hunters (buffalo, cows, horses), cattle (manual 2.5) and loose
## horses (manual 2.6). Also the herders' side: cowboys, gauchos and the like take over
## wild or enemy cows by coming close.

## Food from a hunted animal, by object name prefix: buffalo, cow, horse.
const MEAT := {"animal_buffalo": 150, "animal_cow": 100, "animal_horse": 60}
const CARCASS_SECONDS := 120.0  # a carcass with meat left that nobody comes back to stays this long
## Cattle: cows graze up to 25 gold of value; driven alive to an animal-processing building
## they are paid out (the Native facility pays food as well).
const COW_DIR := "animals/cow"
const COW_MAX_VALUE := 25.0
const COW_GRAZE_SECONDS := 200.0  # from nothing to full value
const HERDERS := [463, 464, 263, 264, 156, 157, 353, 354]
## A riderless horse stays its people's for a minute (lead it into a corral, hacienda or
## ranch to add it to the horses) before running wild again.
const HORSE_DIR := "animals/horse"
const OWNED_HORSE_SECONDS := 60.0

var hunted := false  ## the meat has been taken
var meat_left := -1  ## a carcass's remaining food (-1 = not yet butchered: its full value)
var cattle_value := 0.0
var wild_timer := 0.0
var _deliver_to: MapObject
var _stable: MapObject
var _herd_scan := 0.0
var _is_horse := false
var _is_cow := false


func _init(owner: Unit) -> void:
	super(owner)
	var dir := unit.unit_type.directory
	_is_horse = dir == HORSE_DIR
	_is_cow = dir == COW_DIR
	busy = _is_horse or _is_cow or unit.unit_type.guid() in HERDERS


func is_horse() -> bool:
	return _is_horse


func is_cow() -> bool:
	return _is_cow


func clear_orders() -> void:
	_deliver_to = null
	_stable = null


func update(delta: float) -> bool:
	if not unit.is_alive():
		return false
	if _is_horse:
		_update_horse(delta)
	elif _is_cow:
		_update_cow(delta)
	elif unit.team > 0:
		_herd(delta)
	return false


# ------------------------------------------------------------------ meat

func has_meat() -> bool:
	return unit.team == 0 and not hunted and (unit.is_alive() or meat_left != 0)


func meat_value() -> int:
	var type := ObjectTypes.get_type(unit.unit_type.type_id)
	for prefix in MEAT:
		if type and type.name.begins_with(prefix):
			return MEAT[prefix]
	return 60


## Cut off up to `wanted` food; a carcass picked clean starts to fade.
func cut_meat(wanted: int) -> int:
	if meat_left < 0:
		meat_left = meat_value()
	var cut := mini(wanted, meat_left)
	meat_left -= cut
	if meat_left <= 0:
		hunted = true
		unit._corpse_timer = Unit.CORPSE_SECONDS
	return cut


## A hunter is at work on this carcass or on his way back to it: it stays until picked clean.
func keep() -> void:
	if not unit.is_alive() and has_meat():
		unit._corpse_timer = 0.0
		unit.modulate.a = 1.0


## How long the body lies before it fades.
func corpse_seconds() -> float:
	return CARCASS_SECONDS if has_meat() else Unit.CORPSE_SECONDS


# ------------------------------------------------------------------ cattle

## Drive a cow into an animal-processing building to sell it.
func deliver(building: MapObject) -> void:
	if not _is_cow or unit.team <= 0:
		return
	unit.move_to(building.work_rect().get_center())
	_deliver_to = building


func _update_cow(delta: float) -> void:
	if unit.team > 0 and unit.state == Unit.State.IDLE:
		cattle_value = minf(COW_MAX_VALUE, cattle_value + COW_MAX_VALUE / COW_GRAZE_SECONDS * delta)
	if is_instance_valid(_deliver_to) and _deliver_to.near_walls(unit.position, Unit.REACH * 3):
		var owner := player()
		if owner:
			owner.add("gold", int(cattle_value))
			if _deliver_to.guid == 102:
				owner.add("food", int(cattle_value) * 2)
		Sound.play_event(_deliver_to.guid, Sound.Event.SELECT, _deliver_to.position, 0)
		unit.queue_free()


func _herd(delta: float) -> void:
	_herd_scan -= delta
	if _herd_scan > 0.0:
		return
	_herd_scan = 0.5
	for other: Unit in UnitGrid.near(unit.position, 60.0):
		if other.is_alive() and other.animal.is_cow() and other.team != unit.team \
				and other.position.distance_to(unit.position) < 60.0:
			other.change_team(unit.team)


# ------------------------------------------------------------------ horses

## Lead an owned horse into a horse building, where it joins the people's horses.
func stable(building: MapObject) -> void:
	if not _is_horse or unit.team <= 0:
		return
	unit.move_to(building.work_rect().get_center())
	_stable = building


func _update_horse(delta: float) -> void:
	if unit.team <= 0:
		return
	if is_instance_valid(_stable) and _stable.near_walls(unit.position, Unit.REACH * 3):
		var owner := player()
		if owner and int(owner.resources.get("horses", 0)) < owner.horse_capacity():
			owner.add("horses", 1)
			Unit.all_units.erase(unit)
			unit.queue_free()
			return
		_stable = null
	wild_timer -= delta
	if wild_timer <= 0.0:
		unit.change_team(0)  # runs wild again


## A riderless horse at `at` (owned for a while by `owner`, or wild with 0).
static func loose_horse(parent: Node, at: Vector2, owner: int) -> Unit:
	var horse := Unit.new()
	horse.position = at
	parent.add_child(horse)
	horse.setup(UnitType.load_type(HORSE_DIR), owner)
	return horse
