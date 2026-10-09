extends Node
## Autoload "Match": the settings chosen in the skirmish menu, read by the game scene.
## When nothing was chosen (the game was started straight from the command line),
## `configured` is false and the game falls back to its command-line options.

const FACTIONS := ["mex", "usa", "ind", "des"]
const FACTION_TEXT := {"ind": 1910, "mex": 1911, "des": 1912, "usa": 1913}

var configured := false
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
