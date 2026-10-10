class_name BuildingProduction
extends RefCounted
## What a building makes: its production queue (units, upgrades, horses, cows, rifles and
## trades), the assembly location for what it trains, and the work some buildings do on
## their own: banks and missions earn gold, the distillery turns wood into food, the
## saloon looks over the land.

const TRAIN_SECONDS := {"default": 14.0, "worker": 9.0}
const QUEUE_LIMIT := 5
const UPGRADE_SECONDS := 60.0
## Horses are raised at the corral (Native, outlaw), hacienda and ranch, which shelter five
## each ("zero of five possible horses"); mounted units cost one.
const HORSE_GUID := 9001
const HORSE_BUILDINGS := [105, 205, 305, 405]
const HORSES_PER_BUILDING := 5
## Cattle (manual 2.5): raised at the hacienda and ranch, sold alive at animal processing.
const COW_GUID := 9002
const COW_BUILDINGS := [205, 405]
const ANIMAL_PROCESSING := [102, 202, 302, 402]
## Guns (manual 4.3): "Americans and Mexicans produce guns in their weapons factories".
const GUN_GUID := 9003
const GUN_FACTORIES := [211, 411]
const STAGECOACH := 456
const STAGECOACH_UPGRADE := 990
## The trading buildings (Native and Mexican trading post, outlaw drugstore, American
## general store) and their six trades.
const TRADE_BUILDINGS := [106, 210, 310, 410]
const TRADE_GUID := 9101
const TRADES := [
	{"good": "food", "buy": true, "icon": 50}, {"good": "food", "buy": false, "icon": 42},
	{"good": "wood", "buy": true, "icon": 46}, {"good": "wood", "buy": false, "icon": 38},
	{"good": "guns", "buy": true, "icon": 52}, {"good": "guns", "buy": false, "icon": 44},
]
const TRADE_QUEUE_LIMIT := 10
## Banks (interest) and missions (donations) pay gold on their own; more of them pay more,
## up to five each (manual).
const INCOME_BUILDINGS := [416, 216]
const INCOME_GOLD := 15
const INCOME_SECONDS := 12.0
const INCOME_MAX_BUILDINGS := 5
## The distillery turns wood into food (the outlaws' liquor) while wood lasts.
const DISTILLERY_GUID := 308
const DISTILL_SECONDS := 15.0
const DISTILL_WOOD := 20
const DISTILL_FOOD := 40
## The outlaws' saloon looks over the land once Lift fog of war is researched.
## The Natives' tepee of the ancestors (expansion manual 4.1) invokes the warrior spirit:
## for 75 units of its magic energy, which builds back up slowly, every military unit of
## its people gains 5, 10 or 20% morale for a while (Warrior spirit 1, 2 or 3).
const SPIRIT_TEPEE := 116
const SPIRIT_UPGRADES := [968, 969, 970]
const SPIRIT_BOOST := [0.05, 0.10, 0.20]
const SPIRIT_COST := 75.0
const SPIRIT_MAX := 150.0
const SPIRIT_REGEN := 0.5  # magic energy per second
const SPIRIT_SECONDS := 30.0

const SALOON := 303
const LIFT_FOG_UPGRADE := 965
const LOOK_RECHARGE := 60.0

static var _trained_at := {}  # building GUID -> unit GUIDs whose place of production it is

var building: MapObject
var queue: PackedInt32Array = []  ## unit, upgrade or trade GUIDs waiting their turn
var progress := 0.0  ## 0..1 for queue[0]
var rally_point := Vector2.INF  ## where trained units gather; INF = just outside
var distilling := true  ## its owner can let a distillery rest, keeping the wood
var look_ready_at := 0.0  ## game msec (Sim.msec) when the saloon can look again
var spirit_energy := SPIRIT_COST  ## the tepee of the ancestors' magic energy
var _trade_terms: Array[Dictionary] = []  # what each queued trade was paid with, in order
var _income_timer := 0.0
var _distill_timer := 0.0


func _init(owner: MapObject) -> void:
	building = owner


func owner() -> Player:
	return Player.by_index.get(building.owner_index)


## Units this building can train (GUIDs from the manual's "place of production").
func trainable_units() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not building.complete:
		return out
	var guid := building.guid
	if guid in HORSE_BUILDINGS:
		out.append(HORSE_GUID)
	if guid in COW_BUILDINGS:
		out.append(COW_GUID)
	if guid in GUN_FACTORIES:
		out.append(GUN_GUID)
	if guid in TRADE_BUILDINGS:
		for i in TRADES.size():
			out.append(TRADE_GUID + i)
	var player := owner()
	for unit_guid in units_trained_at(guid):
		if unit_guid == STAGECOACH and (player == null or not player.researched.has(STAGECOACH_UPGRADE)):
			continue  # needs the Stagecoach upgrade
		out.append(unit_guid)
	return out


static func units_trained_at(building_guid: int) -> PackedInt32Array:
	if not _trained_at.has(building_guid):
		var found := PackedInt32Array()
		for unit_guid in GameData.stats_guids():
			var stats := GameData.stats(unit_guid)
			if stats.get("kind") == "unit" and int(stats.get("produced_at", -1)) == building_guid:
				found.append(unit_guid)
		_trained_at[building_guid] = found
	return _trained_at[building_guid]


## Upgrades researched here that the owner can start now.
func researchable_upgrades() -> PackedInt32Array:
	var out := PackedInt32Array()
	var player := owner()
	if not building.complete or player == null:
		return out
	var ids := GameData.stats_guids()
	ids.sort()
	for upgrade in ids:
		var stats := GameData.stats(upgrade)
		if stats.get("kind") == "upgrade" and int(stats.get("produced_at", -1)) == building.guid \
				and (player.can_research(upgrade) or upgrade in queue):
			out.append(upgrade)
	return out


## The highest Warrior spirit level the owner has researched (0 = none).
func spirit_level() -> int:
	var player := owner()
	var level := 0
	for i in SPIRIT_UPGRADES.size():
		if player and player.researched.has(SPIRIT_UPGRADES[i]):
			level = i + 1
	return level


## Invoke the warrior spirit over the people's fighting units; false when it can't be now.
func invoke_spirit() -> bool:
	var level := spirit_level()
	if building.guid != SPIRIT_TEPEE or level == 0 or spirit_energy < SPIRIT_COST or not building.complete:
		return false
	spirit_energy -= SPIRIT_COST
	for unit in Unit.all_units:
		# Everyone who fights (the Natives' warriors also gather and build), not the women.
		if unit.team == building.owner_index and unit.is_alive() and not unit.unit_type.attack_anims.is_empty() \
				and not unit.unit_type.is_farmer():
			unit.inspire(SPIRIT_BOOST[level - 1], SPIRIT_SECONDS)
	return true


static func is_trade(item: int) -> bool:
	return item >= TRADE_GUID and item < TRADE_GUID + TRADES.size()


## Whether `item` could be queued now (what enqueue checks, without paying).
func can_enqueue(item: int) -> bool:
	var price := _price(item)
	return not price.is_empty() and owner().can_afford(price.cost)


## Pay for `item` and add it to the queue; false when it cannot be had now.
func enqueue(item: int) -> bool:
	var price := _price(item)
	if price.is_empty() or not owner().spend(price.cost):
		return false
	if is_trade(item):
		_trade_terms.append(price.cost)
	queue.append(item)
	return true


## {"cost": what `item` takes now}, or {} when it cannot be queued at all.
func _price(item: int) -> Dictionary:
	var player := owner()
	if queue.size() >= QUEUE_LIMIT or player == null:
		return {}
	var stats := GameData.stats(item)
	if stats.get("kind") == "upgrade":
		return {"cost": stats.get("cost", {})} if player.can_research(item) else {}
	if is_trade(item):
		# Buying pays the gold now; selling hands over the goods now; the other side of the
		# deal arrives when the trade completes.
		if queue.size() >= TRADE_QUEUE_LIMIT:
			return {}
		var trade: Dictionary = TRADES[item - TRADE_GUID]
		return {"cost": {"gold": player.buy_price(trade.good)} if trade.buy else {trade.good: Player.TRADE_PACKAGE[trade.good]}}
	if item == COW_GUID or item == GUN_GUID:
		return {"cost": stats.cost}
	if item == HORSE_GUID:
		if int(player.resources.get("horses", 0)) + player.queued_horses() >= player.horse_capacity():
			return {}
		return {"cost": stats.cost}
	if item in Player.COMMANDERS and player.has_commander():
		return {}
	var cost: Dictionary = stats.get("cost", {}).duplicate()
	cost.erase("population")
	return {"cost": cost} if player.has_room() else {}


## The assembly location for what this building trains.
func set_rally(point: Vector2) -> void:
	rally_point = point


func set_distilling(on: bool) -> void:
	distilling = on


## The saloon's look over the land: lifts the fog round `point` for a while, for its owner.
func look(point: Vector2) -> void:
	if building.guid != SALOON or Sim.msec() < look_ready_at:
		return
	look_ready_at = Sim.msec() + LOOK_RECHARGE * 1000.0
	if FogOfWar.current and building.owner_index == Orders.local_player:
		FogOfWar.current.reveal_for(point, 450.0, 20.0)


## Take entry `index` off the queue and refund what it cost.
func cancel(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	var item := queue[index]
	var refund: Dictionary = GameData.stats(item).get("cost", {})
	if is_trade(item):
		var position_in_trades := 0
		for k in index:
			if is_trade(queue[k]):
				position_in_trades += 1
		refund = _trade_terms[position_in_trades]
		_trade_terms.remove_at(position_in_trades)
	queue.remove_at(index)
	if index == 0:
		progress = 0.0
	var player := owner()
	if player:
		for key in refund:
			if Player.RESOURCES.has(key):
				player.add(key, int(refund[key]))


func cancel_all() -> void:
	while not queue.is_empty():
		cancel(queue.size() - 1)


func update(delta: float) -> void:
	var guid := building.guid
	if guid == SPIRIT_TEPEE and building.complete and building.health > 0.0:
		spirit_energy = minf(SPIRIT_MAX, spirit_energy + SPIRIT_REGEN * delta)
	if guid == DISTILLERY_GUID:
		_distill(delta)
	if guid in INCOME_BUILDINGS and building.health > 0.0:
		_earn(delta)
	if guid in TRADE_BUILDINGS:
		var market := owner()
		if market:
			market.settle_prices(delta)
	if not queue.is_empty():
		_train(delta)


func _train(delta: float) -> void:
	var item := queue[0]
	var stats := GameData.stats(item)
	var seconds: float = TRAIN_SECONDS.default if stats.get("damage", 0) > 4 else TRAIN_SECONDS.worker
	seconds = float(stats.get("build_time", seconds))
	if stats.get("kind") == "upgrade":
		# The editor data gives 60 s for level 1 and 90 s for level 2 of an upgrade.
		var name: String = stats.get("name", "")
		var level := name.get_slice(" ", name.get_slice_count(" ") - 1)
		seconds = 30.0 + 30.0 * level.to_int() if level.is_valid_int() else UPGRADE_SECONDS
	progress += delta / seconds
	if progress < 1.0:
		return
	progress = 0.0
	queue.remove_at(0)
	var player := owner()
	if stats.get("kind") == "upgrade":
		if player:
			player.complete_research(item)
		return
	if is_trade(item):
		var trade: Dictionary = TRADES[item - TRADE_GUID]
		_trade_terms.pop_front()
		if player:
			if trade.buy:
				player.add(trade.good, Player.TRADE_PACKAGE[trade.good])
			else:
				player.add("gold", player.sell_price(trade.good))
			player.move_price(trade.good, trade.buy)
		return
	Sound.play_event(building.guid, Sound.Event.UNIT_READY, building.position, 0)
	if item == HORSE_GUID or item == GUN_GUID:
		if player:
			player.add("horses" if item == HORSE_GUID else "guns", 1)
		return
	if player:
		player.stats.produced += 1
	building.unit_trained.emit(building, item)


func _earn(delta: float) -> void:
	_income_timer += delta
	if _income_timer < INCOME_SECONDS:
		return
	_income_timer = 0.0
	var same := 0
	for object in MapObject.structures:
		if object.guid == building.guid and object.owner_index == building.owner_index and object.complete and object.is_alive():
			same += 1
			if object == building and same > INCOME_MAX_BUILDINGS:
				return
	var player := owner()
	if player:
		player.add("gold", INCOME_GOLD)


func _distill(delta: float) -> void:
	var player := owner()
	if player == null or not distilling or int(player.resources.get("wood", 0)) < DISTILL_WOOD:
		return
	_distill_timer += delta
	if _distill_timer >= DISTILL_SECONDS:
		_distill_timer = 0.0
		player.spend({"wood": DISTILL_WOOD})
		player.add("food", DISTILL_FOOD)


func restore(entry: Dictionary) -> void:
	queue = PackedInt32Array(entry.get("queue", []).map(func(v) -> int: return int(v)))
	progress = float(entry.get("train", 0.0))
	var rally = entry.get("rally")
	rally_point = Vector2(rally[0], rally[1]) if rally != null else Vector2.INF
	distilling = bool(entry.get("distilling", true))
	# Saves don't keep what queued trades were paid; refund them at today's prices.
	_trade_terms.clear()
	var player := owner()
	for item in queue:
		if is_trade(item) and player:
			var trade: Dictionary = TRADES[item - TRADE_GUID]
			_trade_terms.append({"gold": player.buy_price(trade.good)} if trade.buy else {trade.good: Player.TRADE_PACKAGE[trade.good]})
