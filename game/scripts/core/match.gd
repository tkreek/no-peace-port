extends Node
## Autoload "Match": the settings chosen in the skirmish menu, read by the game scene.
## When nothing was chosen (the game was started straight from the command line),
## `configured` is false and the game falls back to its command-line options.

const FACTIONS := ["mex", "usa", "ind", "des"]
const FACTION_TEXT := {"ind": 1910, "mex": 1911, "des": 1912, "usa": 1913}

## Raw materials setting from the menu (texts 275..278): the map's own amounts or a preset.
const SUPPLY_TEXT := [275, 276, 277, 278]
const SUPPLY_NAMES := ["Map", "Low", "Normal", "High"]
const SUPPLY_PRESETS := [{}, {"food": 500, "wood": 500, "gold": 500, "guns": 5},
		{"food": 1000, "wood": 1000, "gold": 1000, "guns": 10},
		{"food": 2000, "wood": 2000, "gold": 2000, "guns": 20}]

## Computer AI level (Menu.eng 198..201: very easy, easy, medium, difficult).
const DIFFICULTY_TEXT := [198, 199, 200, 201]
const DIFFICULTY_NAMES := ["Very easy", "Easy", "Medium", "Difficult"]

var configured := false
var supply := 0
var difficulty := 2
var map_path := ""
## One entry per player in start-point order: {"faction": "mex", "ai": false}
var players: Array[Dictionary] = []


func setup(map: String, slots: Array[Dictionary]) -> void:
	configured = true
	map_path = map
	players = slots


func faction_name(faction: String) -> String:
	var names := {"ind": "Native Americans", "mex": "Mexicans", "des": "Outlaws", "usa": "Americans"}
	return names.get(faction, faction)


## Start stockpile for a map under the chosen raw materials setting.
func start_resources(map_amounts: Dictionary) -> Dictionary:
	var preset: Dictionary = SUPPLY_PRESETS[supply] if configured else {}
	var amounts := preset if not preset.is_empty() else map_amounts
	if amounts.is_empty():
		amounts = SUPPLY_PRESETS[2]
	return amounts
