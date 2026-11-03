class_name UnitAnimal
extends UnitPart
## Animals: meat for the hunters (buffalo, cows, horses), cattle (manual 2.5) and loose
## horses (manual 2.6). Also the herders' side: cowboys, gauchos and the like take over
## wild or enemy cows by coming close.

## Food from a hunted animal, by object name prefix: max(1, property 111) of Defaults.bin's
## neutral block (AmericaAddOn.exe 0x401de0): buffalo (481) 100, cow (482) 70, horse (480) 50.
const MEAT := {"animal_buffalo": 100, "animal_cow": 70, "animal_horse": 50}
## A dead animal lies 3 s (0x419190) unless a hunter is on it (keep), 30 s after each cut
## that leaves meat (0x401e1c); picked clean, 6 s (0x401e3f; ours rots to bones, Unit).
const CARCASS_SECONDS := 3.0
const CUT_CARCASS_SECONDS := 30.0
## Cattle (class 0x4a3c2c): a cow starts worth 10 food and no gold (0x43fbd0) and every
## 12.02 s of its life, wild or owned, gains 2 food up to 50 and 1 gold up to 25 (0x43fb70).
## Driven to a building that takes cows (the animal-processing ones), within 80 px of it,
## it pays both to that building's owner (0x43fca0).
const COW_DIR := "animals/cow"
const COW_MAX_VALUE := 25.0
const COW_START_FOOD := 10
const COW_MAX_FOOD := 50
const COW_GROW_SECONDS := 12.02  # a step: +1 gold, +2 food
const HERDERS := [463, 464, 263, 264, 156, 157, 353, 354]
## A riderless horse stays its people's for 20 s (0x4614e8, counted down by 0x461670; lead
## it into a corral, hacienda or ranch to add it to the horses) before running wild again.
const HORSE_DIR := "animals/horse"
const OWNED_HORSE_SECONDS := 20.0

var hunted := false  ## the meat has been taken
var meat_left := -1  ## a carcass's remaining food (-1 = not yet butchered: its full value)
var cattle_value := 0.0  ## a cow's gold
var cattle_food := COW_START_FOOD
var _cow_timer := 0.0
var _cut := false  # a hunter has cut from this carcass
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
	_cut = true
	unit._corpse_timer = 0.0
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
	if not has_meat():
		return Unit.CORPSE_SECONDS
	return CUT_CARCASS_SECONDS if _cut else CARCASS_SECONDS


# ------------------------------------------------------------------ cattle

## Drive a cow into an animal-processing building to sell it.
func deliver(building: MapObject) -> void:
	if not _is_cow or unit.team <= 0:
		return
	unit.move_to(building.work_rect().get_center())
	_deliver_to = building


func _update_cow(delta: float) -> void:
	_cow_timer += delta
	if _cow_timer > COW_GROW_SECONDS:
		_cow_timer = 0.0
		cattle_value = minf(COW_MAX_VALUE, cattle_value + 1.0)
		cattle_food = mini(COW_MAX_FOOD, cattle_food + 2)
	if is_instance_valid(_deliver_to) and _deliver_to.near_walls(unit.position, 80.0):
		var owner: Player = Player.by_index.get(_deliver_to.owner_index)
		if owner:
			owner.add("food", cattle_food)
			owner.add("gold", int(cattle_value))
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
			Unit.roster_version += 1
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
