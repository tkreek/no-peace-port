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

var index := 1
var faction := ""
var resources := {}


func _init(player_index: int, faction_name: String) -> void:
	index = player_index
	faction = faction_name
	for key in RESOURCES:
		resources[key] = GameData.def_value(RESOURCES[key].def, 0)


func color() -> Color:
	return TEAM_COLORS[index] if index < TEAM_COLORS.size() else Color.WHITE


func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if resources.get(key, 0) < cost[key]:
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for key in cost:
		resources[key] -= cost[key]
	resources_changed.emit()
	return true


func add(key: String, amount: int) -> void:
	resources[key] = resources.get(key, 0) + amount
	resources_changed.emit()
