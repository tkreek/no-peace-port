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
var researched := {}  # upgrade GUID -> true

const UPGRADE_READY_SOUNDS := {"des": 13, "ind": 31, "mex": 46, "usa": 131}


func _init(player_index: int, faction_name: String) -> void:
	index = player_index
	faction = faction_name
	by_index[index] = self
	for key in RESOURCES:
		resources[key] = 0


func set_start_resources(amounts: Dictionary) -> void:
	for key in RESOURCES:
		resources[key] = int(amounts.get(key, 0))
	resources_changed.emit()


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


## Upgrades: is `upgrade` available to research now (level order + tech-tree rules)?
func can_research(upgrade: int) -> bool:
	if researched.has(upgrade) or is_researching(upgrade):
		return false
	var previous := previous_level(upgrade)
	if previous >= 0 and not researched.has(previous):
		return false
	return meets_prerequisites(upgrade)


func is_researching(upgrade: int) -> bool:
	for object in MapObject.all_objects:
		if object.owner_index == index and upgrade in object.queue:
			return true
	return false


## "Rifle 2" requires "Rifle 1" of the same people.
static func previous_level(upgrade: int) -> int:
	var stats := GameData.stats(upgrade)
	var name: String = stats.get("name", "")
	var level := name.get_slice(" ", name.get_slice_count(" ") - 1)
	if not level.is_valid_int() or level.to_int() <= 1:
		return -1
	var wanted := "%s %d" % [name.substr(0, name.length() - level.length() - 1), level.to_int() - 1]
	for other in GameData.stats_guids():
		var o := GameData.stats(other)
		if o.get("kind") == "upgrade" and o.get("faction") == stats.get("faction") and o.get("name") == wanted:
			return other
	return -1


func complete_research(upgrade: int) -> void:
	researched[upgrade] = true
	var effects: Dictionary = GameData.stats(upgrade).get("effects", {})
	if effects.has("health_pct"):
		for unit in Unit.all_units:
			if unit.team == index and unit.is_alive():
				unit.refresh_upgrades()
		for object in MapObject.all_objects:
			if object.owner_index == index and object.is_building():
				object.refresh_upgrades()
	Sound.play_sound(UPGRADE_READY_SOUNDS.get(faction, 46))
	resources_changed.emit()


## Sum of an effect over researched upgrades that apply to `target_guid`.
func bonus(target_guid: int, effect: String, mounted := false) -> float:
	var total := 0.0
	for upgrade in researched:
		var stats := GameData.stats(upgrade)
		var effects: Dictionary = stats.get("effects", {})
		if not effects.has(effect):
			continue
		var targets: Array = stats.get("applies_to_guids", [])
		# Mounted units are listed by their foot version (GUID - 1).
		var everyone := targets.is_empty() or effect == "field_yield"  # field upgrades apply to all fields
		if everyone or target_guid in targets or (mounted and target_guid - 1 in targets):
			total += float(effects[effect])
	return total


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
