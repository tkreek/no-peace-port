class_name Player
extends RefCounted
## One side in a match: team colour slot, faction and stockpile.

signal resources_changed

## Team colours (the most saturated entry of each original team palette), for UI and minimap.
const TEAM_COLORS := [
	Color("#808080"), Color("#ffbd00"), Color("#4a84ff"), Color("#31b500"), Color("#de0800"),
	Color("#9c00ff"), Color("#f739ef"), Color("#ef6300"), Color("#00dead"),
]
## Resource keys with their original text ids and status icon frames.
const RESOURCES := {
	"food": {"text": 72, "icon": 4, "def": "Nahrung"},
	"wood": {"text": 73, "icon": 2, "def": "Holz"},
	"leather": {"text": 74, "icon": 3, "def": "Leder"},
	"gold": {"text": 75, "icon": 1, "def": "Gold"},
	"guns": {"text": 76, "icon": 0, "def": "Gewehre"},
}

static var by_index := {}

var index := 1
var faction := ""
var resources := {}


func _init(player_index: int, faction_name: String) -> void:
	index = player_index
	faction = faction_name
	by_index[index] = self
	for key in RESOURCES:
		resources[key] = GameData.def_value(RESOURCES[key].def, 0)


func color() -> Color:
	return TEAM_COLORS[index] if index < TEAM_COLORS.size() else Color.WHITE


## Living units of this player.
func population() -> int:
	var count := 0
	for unit in Unit.all_units:
		if unit.team == index and unit.is_alive():
			count += 1
	return count


## Housing from completed buildings ("Residence for N units" in the manual).
func population_cap() -> int:
	var cap := 0
	for object in MapObject.all_objects:
		if object.owner_index == index and object.complete and object.is_alive():
			cap += int(GameData.stats(object.guid).get("housing", 0))
	return cap


func queued_units() -> int:
	var count := 0
	for object in MapObject.all_objects:
		if object.owner_index == index:
			count += object.queue.size()
	return count


## Commanders (on foot or mounted): a people may only ever have one.
const COMMANDERS := [150, 151, 250, 251, 350, 351, 450, 451]


func has_commander() -> bool:
	for unit in Unit.all_units:
		if unit.team == index and unit.is_alive() and unit.unit_type.guid() in COMMANDERS:
			return true
	for object in MapObject.all_objects:
		if object.owner_index == index:
			for queued in object.queue:
				if queued in COMMANDERS:
					return true
	return false


func has_room() -> bool:
	return population() + queued_units() < population_cap()


func has_building(guid: int) -> bool:
	for object in MapObject.all_objects:
		if object.owner_index == index and object.guid == guid and object.complete and object.is_alive():
			return true
	return false


func meets_prerequisites(guid: int) -> bool:
	for required in GameData.prerequisites(guid):
		if not has_building(required):
			return false
	return true


func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if resources.get(key, 0) < cost[key]:
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for key in cost:
		resources[key] = int(resources.get(key, 0)) - int(cost[key])
	resources_changed.emit()
	return true


func add(key: String, amount: int) -> void:
	resources[key] = int(resources.get(key, 0)) + amount
	resources_changed.emit()
