class_name BuildingProduction
extends RefCounted
## What a building makes: its production queue (units, upgrades, horses, cows, guns, liquor
## and trades), the assembly location for what it trains, and the work some buildings do
## on their own: banks and missions earn gold, the saloon looks over the land.

## Orders a building holds, trades included (AmericaAddOn.exe 0x40cd10).
const QUEUE_LIMIT := 10
## Production time when the data has none (AmericaAddOn.exe, 0x40ce30).
const DEFAULT_PRODUCTION_TIME := 10
## Horses are raised at the corral (Native, outlaw), hacienda and ranch, which shelter five
## each ("zero of five possible horses"); mounted units cost one.
const HORSE_GUID := 9001
const HORSE_BUILDINGS := [105, 205, 305, 405]
const HORSES_PER_BUILDING := 5
## "Our horses need more room!": a finished horse waits for room (AmericaAddOn.exe 0x40cf98).
const HORSE_ROOM_ALERT := 823
## Cattle (manual 2.5): raised at the hacienda and ranch, sold alive at animal processing.
const COW_GUID := 9002
const COW_BUILDINGS := [205, 405]
const ANIMAL_PROCESSING := [102, 202, 302, 402]
## Guns (manual 4.3): "Americans and Mexicans produce guns in their weapons factories".
const GUN_GUID := 9003
const GUNS_PER_BATCH := 10
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
## Banks (interest) and missions (donations) pay gold on their own; more of them pay more,
## up to five each (manual).
const INCOME_BUILDINGS := [416, 216]
const INCOME_GOLD := 15
const INCOME_SECONDS := 12.0
const INCOME_MAX_BUILDINGS := 5
## The outlaws' distillery makes liquor, which feeds them: Defaults.bin's "Liquor" (711),
## queued like a unit and paid when ordered; done, it adds 40 food (AmericaAddOn.exe 0x40cf40).
const DISTILLERY_GUID := 308
const LIQUOR_GUID := 9004
const LIQUOR_FOOD := 40
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
var look_ready_at := 0.0  ## game msec (Sim.msec) when the saloon can look again
var spirit_energy := SPIRIT_COST  ## the tepee of the ancestors' magic energy
var _trade_terms: Array[Dictionary] = []  # what each queued trade was paid with, in order
var _income_timer := 0.0
var _room_alerted := false  # the finished unit waiting for living space has been announced


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
	if guid == DISTILLERY_GUID:
		out.append(LIQUOR_GUID)
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


## How long the original takes over something of production time `time` (seconds, property
## 106). AmericaAddOn.exe (0x40ce30) counts to 0x7000 in whole steps of
## (0x7000 / time) * 20 / 1000 every 20 ms tick, so long times run over: 20 s takes 20.5 s,
## 60 s 63.7 s, 90 s 95.6 s, 120 s 143.4 s.
static func production_seconds(time: int) -> float:
	var step := floori(floori(28672.0 / maxi(1, time)) * 20 / 1000.0)
	return ceili(28672.0 / step) * 0.02 if step > 0 else INF


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


## Why the original's produce order would turn `item` away here, "" when it takes it
## (AmericaAddOn.exe 0x40cd10): only a full queue, a second leader (0x590a63, 0x42c1f0) and
## an upgrade its people has researched or is researching at any building (0x590b18,
## 0x590e38). Unlike the build menu (0x4750a0, which offers the next level of an upgrade
## only when no level is in research) it asks nothing about the level before or the
## prerequisites, so the KI's next level waits behind the one in research.
func order_refusal(item: int) -> String:
	var player := owner()
	if player == null:
		return "no owner"
	if queue.size() >= QUEUE_LIMIT:
		return "queue full"
	if GameData.stats(item).get("kind") == "upgrade":
		if player.researched.has(item):
			return "researched"
		if player.is_researching(item):
			return "in research"
	elif item in Player.COMMANDERS and player.has_commander():
		return "leader"
	return ""


## Queue `item` as the produce order does (0x4564a0 -> 0x40cd10), which is how the KI
## produces: the price (props 101-105) is taken whether or not it can be paid (0x422580; the
## scripts ask can_train first), living space and the horses' room are needed only when it
## is done. False when order_refusal turns it away.
func order(item: int) -> bool:
	if is_trade(item):
		return enqueue(item)
	if not order_refusal(item).is_empty():
		return false
	var player := owner()
	var cost: Dictionary = GameData.stats(item).get("cost", {})
	for key in cost:
		if Player.RESOURCES.has(key):
			player.resources[key] = int(player.resources.get(key, 0)) - int(cost[key])
	player.resources_changed.emit()
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
		var trade: Dictionary = TRADES[item - TRADE_GUID]
		return {"cost": {"gold": player.buy_price(trade.good)} if trade.buy else {trade.good: Player.TRADE_PACKAGE[trade.good]}}
	if item == COW_GUID or item == GUN_GUID or item == LIQUOR_GUID:
		return {"cost": stats.cost}
	if item == HORSE_GUID:
		if int(player.resources.get("horses", 0)) + player.queued_horses() >= player.horse_capacity():
			return {}
		return {"cost": stats.cost}
	if item in Player.COMMANDERS and player.has_commander():
		return {}
	# Living space is not needed yet: a finished unit waits for it (see _train).
	var cost: Dictionary = stats.get("cost", {}).duplicate()
	cost.erase("population")
	return {"cost": cost}


## The assembly location for what this building trains.
func set_rally(point: Vector2) -> void:
	rally_point = point


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
	progress += delta / production_seconds(int(stats.get("build_time", DEFAULT_PRODUCTION_TIME)))
	if progress < 1.0:
		return
	var player := owner()
	# A finished unit waits in the building until its people have living space for it,
	# announced once (AmericaAddOn.exe 0x40d103, alert 805).
	# A finished horse waits the same way while its people's corrals are full (0x40cf78,
	# alert 823); the produce order does not ask for room.
	var no_room: bool = stats.get("kind") == "unit" and player != null and not player.can_house(int(stats.get("cost", {}).get("population", 1)))
	var no_stable: bool = item == HORSE_GUID and player != null and int(player.resources.get("horses", 0)) >= player.horse_capacity()
	if no_room or no_stable:
		progress = 1.0
		if not _room_alerted:
			_room_alerted = true
			player.alert(Player.LIVING_SPACE_ALERT if no_room else HORSE_ROOM_ALERT, building.position, 0)
		return
	_room_alerted = false
	progress = 0.0
	queue.remove_at(0)
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
	if building.owner_index == Orders.local_player:  # the new unit announces itself, ours only
		Sound.play_event(item, Sound.Event.UNIT_READY, building.position, 0)
	if item == HORSE_GUID or item == GUN_GUID or item == LIQUOR_GUID:
		if player:
			match item:
				HORSE_GUID: player.add("horses", 1)
				GUN_GUID: player.add("guns", GUNS_PER_BATCH)
				LIQUOR_GUID: player.add("food", LIQUOR_FOOD)
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


func restore(entry: Dictionary) -> void:
	queue = PackedInt32Array(entry.get("queue", []).map(func(v) -> int: return int(v)))
	progress = float(entry.get("train", 0.0))
	var rally = entry.get("rally")
	rally_point = Vector2(rally[0], rally[1]) if rally != null else Vector2.INF
	# Saves don't keep what queued trades were paid; refund them at today's prices.
	_trade_terms.clear()
	var player := owner()
	for item in queue:
		if is_trade(item) and player:
			var trade: Dictionary = TRADES[item - TRADE_GUID]
			_trade_terms.append({"gold": player.buy_price(trade.good)} if trade.buy else {trade.good: Player.TRADE_PACKAGE[trade.good]})
