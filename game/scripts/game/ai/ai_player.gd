class_name AiPlayer
extends Node
## A skirmish opponent playing by the same rules as the human player. Every few seconds
## (faster at higher difficulty) it thinks: AiEconomy runs the workers, fields, wagons,
## trading and animals; AiBuilder decides what to build and where; AiArmy trains, researches,
## defends and attacks. The four difficulty levels of the original (very easy .. difficult)
## set its pace and ambition. Without its main building it rebuilds it if it can, else it
## surrenders.

const DIFFICULTY := [
	# think s, workers, production buildings, first attack s, wave size, research, building sites at once
	{"think": 3.0, "workers": 8, "production": 1, "first_attack": 720.0, "wave": 4, "research": false, "sites": 1},
	{"think": 2.0, "workers": 12, "production": 2, "first_attack": 480.0, "wave": 6, "research": false, "sites": 1},
	{"think": 1.5, "workers": 16, "production": 3, "first_attack": 330.0, "wave": 8, "research": true, "sites": 2},
	{"think": 1.0, "workers": 22, "production": 4, "first_attack": 240.0, "wave": 10, "research": true, "sites": 2},
]
const RICH_WOOD := 1200
const RICH_OTHER := 1500  # gold and food together
const SURRENDER_GRACE := 20.0  # seconds to start rebuilding before giving up

var player: Player
var units_root: Node2D
var biome := "steppe"
var difficulty := 2
var elapsed := 0.0  ## seconds since the AI started
var home := Vector2.ZERO  ## where its main building stands (or stood)
var economy := AiEconomy.new(self)
var builder := AiBuilder.new(self)
var army := AiArmy.new(self)
var _timer := 0.0
var _lost_since := -1.0
var _units_cache: Array = []
var _buildings_cache: Array = []
var _cache_valid := false


func _process(delta: float) -> void:
	elapsed += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = level().think
	_cache_valid = false
	_think()


func level() -> Dictionary:
	return DIFFICULTY[clampi(difficulty, 0, DIFFICULTY.size() - 1)]


func _think() -> void:
	if player.surrendered:
		return
	var main := hq()
	if main == null:
		_without_main_building()
		return
	home = main.position
	_lost_since = -1.0
	var units := my_units()
	var workers := units.filter(is_worker)
	var soldiers := units.filter(is_soldier)
	economy.think(units, workers, main)
	builder.think(workers, main)
	army.think(units, soldiers, main)


## The main building has fallen: rebuild it if there are builders and the means, keep the
## workers at it, and surrender when that is no longer possible.
func _without_main_building() -> void:
	if _lost_since < 0.0:
		_lost_since = elapsed
	var main := faction_guid(MapObject.MAIN_BUILDINGS)
	var builders := my_units().filter(func(u: Unit) -> bool: return u.unit_type.can_build(main))
	if my_buildings().any(func(b: MapObject) -> bool: return b.guid == main):
		economy.assign_workers(builders)
		return
	if not builders.is_empty() and affordable(main) and builder.place(main, home, builders, 0):
		return
	if elapsed - _lost_since >= SURRENDER_GRACE:
		_surrender()


func _surrender() -> void:
	player.surrendered = true
	for unit: Unit in my_units():
		unit.stance = Unit.Stance.PASSIVE
		unit.stop()
	var main := get_parent()
	if main and main.has_method("on_surrender"):
		main.on_surrender(player)


# ------------------------------------------------------------------ what it has

## Our living units and standing buildings, gathered once per think (sites placed during
## a think drop the cache so they count at once).
func my_units() -> Array:
	_fill_cache()
	return _units_cache.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())


func my_buildings() -> Array:
	_fill_cache()
	return _buildings_cache.filter(func(b: MapObject) -> bool: return is_instance_valid(b) and b.is_alive())


func forget_buildings() -> void:
	_cache_valid = false


func _fill_cache() -> void:
	if _cache_valid:
		return
	_cache_valid = true
	_units_cache = Unit.all_units.filter(func(u: Unit) -> bool: return u.team == player.index and u.is_alive())
	_buildings_cache = MapObject.structures.filter(func(o: MapObject) -> bool:
		return o.is_building() and o.owner_index == player.index and o.is_alive())


func hq() -> MapObject:
	for building in my_buildings():
		if building.guid in MapObject.MAIN_BUILDINGS:
			return building
	return null


func is_worker(u: Unit) -> bool:
	return u.unit_type.can_gather("wood") and u.unit_type.anim_index("build") >= 0


func is_soldier(u: Unit) -> bool:
	return not u.inside and not u.unit_type.attack_anims.is_empty() and not u.unit_type.can_gather("wood") \
			and u.unit_type.guid() != UnitWater.CANOE \
			and not u.unit_type.can_gather("food") and not u.unit_type.is_transport() \
			and not (u.unit_type.is_hunter() and u.work.hunting)


func workers_ready() -> bool:
	return my_units().filter(is_worker).size() >= int(level().workers * 0.5)


## The first of `candidates` (one GUID per people) that belongs to ours, or -1.
func faction_guid(candidates: Array) -> int:
	for guid in candidates:
		if GameData.stats(guid).get("faction") == player.faction:
			return guid
	return -1


func rich() -> bool:
	return int(player.resources.get("wood", 0)) >= RICH_WOOD \
			and int(player.resources.get("gold", 0)) + int(player.resources.get("food", 0)) >= RICH_OTHER


func affordable(guid: int) -> bool:
	var cost: Dictionary = GameData.stats(guid).get("cost", {}).duplicate()
	cost.erase("population")
	return player.can_afford(cost)


func total_cost(guid: int) -> int:
	var total := 0
	for key in GameData.stats(guid).get("cost", {}):
		total += int(GameData.stats(guid).cost[key])
	return total


## Structures that train soldiers (not commanders, and not the canoe, which fights only on water).
func produces_army(structure_guid: int) -> bool:
	for guid in BuildingProduction.units_trained_at(structure_guid):
		if GameData.stats(guid).get("damage", 0) >= 5 and guid not in Player.COMMANDERS and guid != UnitWater.CANOE:
			return true
	return false


# ------------------------------------------------------------------ the others

func enemy_near(at: Vector2, radius: float) -> bool:
	for object in MapObject.structures:
		if object.is_building() and object.owner_index > 0 and object.owner_index != player.index \
				and object.position.distance_to(at) < radius:
			return true
	return false


## An enemy main building (else any enemy building), or INF when none is left.
func enemy_base() -> Vector2:
	var best := Vector2.INF
	for object in MapObject.structures:
		if object.is_building() and object.owner_index > 0 and object.owner_index != player.index and object.is_alive():
			if best == Vector2.INF or object.guid in MapObject.MAIN_BUILDINGS:
				best = object.position
	return best


## --trace-ai: print what the AI decides.
func trace(text: String) -> void:
	if GameData.cmdline_option("trace-ai") != "":
		print("t=%ds AI %d %s" % [elapsed, player.index, text])


# ------------------------------------------------------------------ saved games

func save_state() -> Dictionary:
	return {"elapsed": elapsed, "wave": army.attack_wave, "last_attack": army.last_attack, "difficulty": difficulty}


func restore_state(state: Dictionary) -> void:
	elapsed = float(state.elapsed)
	army.attack_wave = int(state.wave)
	army.last_attack = float(state.last_attack)
	difficulty = int(state.difficulty)
