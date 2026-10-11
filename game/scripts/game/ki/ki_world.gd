class_name KiWorld
extends RefCounted
## The game as the KI modules see it: objects named by handles, with the original's class
## bits (what an object is) and state bits (what it is doing), the per-people claims that keep
## two modules from taking the same unit, and the searches (AmericaAddOn.exe 0x42bce0,
## 0x424c40, 0x4252e0 ...). docs/technical/ki.md lists the bits.

## A handle is owner<<24 | the object's sim id: as in the original, an object that changes
## hands gets a new handle and the old one stops working.
const OWNER_SHIFT := 24
const ID_MASK := 0xFFFFFF

# Class bits (obj+0x24).
const C_UNIT := 0x2
const C_BUILDING := 0x4
const C_MINE := 0x8
const C_TREE := 0x10
const C_LIVESTOCK := 0x20
const C_TENT := 0x40
const C_FOOD_STORE := 0x80
const C_GOLD_STORE := 0x100
const C_WOOD_STORE := 0x200
const C_ARMED := 0x400
const C_MINER := 0x800
const C_MILITARY := 0x1000
const C_RIDER := 0x2000
const C_GARRISON := 0x4000
const C_BUILDER := 0x8000
const C_GATHERER := 0x10000
const C_MAIN := 0x20000
const C_WAGON := 0x40000
const C_STORE := 0x80000
const C_FARM := 0x100000
const C_FALLOW := 0x200000
const C_FIELD := 0x400000
const C_WOMAN := 0x800000
const C_WOODCUTTER := 0x1000000
const C_HORSE := 0x2000000
const C_ANIMAL := 0x4000000
const C_TRANSPORT := 0x8000000
const C_HIDER := 0x10000000
const C_DETECTOR := 0x20000000
const C_CORRAL := 0x40000000
const C_LEADER := 0x80000000

# State bits (virtual +0x2c).
const S_IDLE := 0x4  ## units: idle; buildings: finished
const S_WORKING := 0x8
const S_PRODUCING := 0x10
const S_FALLOW := 0x40
const S_MOVING := 0x100
const S_SITE := 0x200
const S_IN_BUILDING := 0x400
const S_IN_TRANSPORT := 0x800
const S_WEAK := 0x1000
const S_FIGHTING := 0x2000
const S_HIDDEN := 0x10000
const S_DAMAGED := 0x20000
const S_FOLLOWING := 0x1000000
const S_WOOD := 0x2000000
const S_GOLD := 0x4000000
const S_FOOD := 0x8000000
const S_MOUNTED := 0x10000000
const S_ANIMAL := 0x40000000
const S_HERO := 0x80000000

const FARMS := [108, 208, 408]
const HEROES := [270, 300]  ## GUIDs 270..299

## Claims: object sim id -> bit per people (1 << people).
static var claims := {}
static var _unit_classes := {}  # unit type -> class bits


static func reset() -> void:
	claims.clear()


static func owner_of(node: Node) -> int:
	return node.team if node is Unit else (node as MapObject).owner_index


static func handle(node: Node) -> int:
	if node == null or not is_instance_valid(node) or node.sim_id == 0:
		return 0
	return (owner_of(node) << OWNER_SHIFT) | (node.sim_id & ID_MASK)


static func resolve(h: int) -> Node:
	if h <= 0:
		return null
	var node := Sim.find(h & ID_MASK)
	if node == null or owner_of(node) != h >> OWNER_SHIFT or not node.is_alive():
		return null
	return node


static func guid_of(node: Node) -> int:
	return node.unit_type.guid() if node is Unit else (node as MapObject).guid


static func position_of(node: Node) -> Vector2:
	return node.position


# ------------------------------------------------------------------ class and state

static func class_bits(node: Node) -> int:
	if node is Unit:
		return _unit_class(node)
	var object := node as MapObject
	if object.is_tree():
		return C_TREE
	if object.is_mine():
		return C_MINE
	if object.is_field():
		return C_BUILDING | C_FIELD | (C_FALLOW if _fallow(object) else 0)
	if not object.is_building():
		return 0x1
	var bits := C_BUILDING
	var guid := object.guid
	if guid in MapObject.MAIN_BUILDINGS:
		bits |= C_MAIN
	var accepts := MapObject.drop_off_for(guid)
	if "food" in accepts:
		bits |= C_FOOD_STORE
	if "gold" in accepts:
		bits |= C_GOLD_STORE
	if "wood" in accepts:
		bits |= C_WOOD_STORE
	if not accepts.is_empty():
		bits |= C_STORE
	if object.defence and object.defence.capacity() > 0:
		bits |= C_GARRISON
	if guid in FARMS:
		bits |= C_FARM
	if guid in BuildingProduction.HORSE_BUILDINGS:
		bits |= C_CORRAL
	if object.is_trap():
		bits |= C_ARMED
	if guid in [100, 101, 102, 103, 104, 109, 110, 111, 116]:
		bits |= C_TENT  # Native tepees, which travois pack
	return bits


static func _unit_class(unit: Unit) -> int:
	var type := unit.unit_type
	if _unit_classes.has(type):
		return _unit_classes[type]
	var guid := type.guid()
	var bits := C_UNIT
	if unit.animal.is_horse():
		bits |= C_HORSE | C_ANIMAL
	elif unit.animal.is_cow() or guid == Mission.BUFFALO:
		bits |= C_LIVESTOCK | C_ANIMAL
	else:
		var worker := type.is_farmer() or type.can_gather("wood") or type.can_gather("gold")
		if type.is_farmer():
			bits |= C_WOMAN
		if type.can_gather("wood"):
			bits |= C_WOODCUTTER | C_GATHERER
		if type.can_gather("gold"):
			bits |= C_MINER | C_GATHERER
		if type.anim_index("build") >= 0:
			bits |= C_BUILDER
		if type.is_transport():
			bits |= C_WAGON
		if unit.water.is_carrier():
			bits |= C_TRANSPORT
		if not type.attack_anims.is_empty() and not type.is_transport():
			bits |= C_ARMED
			if not worker:
				bits |= C_MILITARY | C_GARRISON
		if not type.mounted and GameData.mounted_of(guid) >= 0:
			bits |= C_RIDER
		if unit.stealth.can_hide():
			bits |= C_HIDER
		if guid in UnitStealth.DETECTORS:
			bits |= C_DETECTOR
		if guid in Player.COMMANDERS or (guid >= HEROES[0] and guid < HEROES[1]):
			bits |= C_LEADER
	_unit_classes[type] = bits
	return bits


static func _fallow(field: MapObject) -> bool:
	return field.stock != null and field.stock.amount <= 0


static func state_bits(node: Node) -> int:
	if node is Unit:
		var unit := node as Unit
		var bits := 0
		match unit.state:
			Unit.State.IDLE:
				bits |= S_IDLE
			Unit.State.MOVING:
				bits |= S_MOVING
			Unit.State.ATTACKING:
				bits |= S_FIGHTING
			Unit.State.GATHERING, Unit.State.BUILDING:
				bits |= S_WORKING
			Unit.State.QUARTERED:
				bits |= S_IN_TRANSPORT if unit.water.vessel else S_IN_BUILDING
		if unit.inside and not bits & (S_IN_BUILDING | S_IN_TRANSPORT):
			bits |= S_IN_BUILDING
		if unit.stealth.concealed:
			bits |= S_HIDDEN
		if unit.health < unit.max_health:
			bits |= S_DAMAGED
		if unit.follow_target:
			bits |= S_FOLLOWING
		match unit.work.carrying:
			"wood":
				bits |= S_WOOD
			"gold":
				bits |= S_GOLD
			"food":
				bits |= S_FOOD
		if unit.unit_type.mounted:
			bits |= S_MOUNTED
		var cls := _unit_class(unit)
		if cls & C_ANIMAL:
			bits |= S_ANIMAL
		if cls & C_LEADER:
			bits |= S_HERO
		return bits
	var object := node as MapObject
	if not object.is_building() and not object.is_field():
		return 0
	var bits := S_IDLE if object.complete else S_SITE
	if object.production and not object.production.queue.is_empty():
		bits |= S_PRODUCING
	if object.max_health > 0.0:
		if object.health < object.max_health * 0.4:
			bits |= S_WEAK
		if object.health < object.max_health:
			bits |= S_DAMAGED
	if object.is_field() and _fallow(object):
		bits |= S_FALLOW
	return bits


# ------------------------------------------------------------------ claims

static func claimed(node: Node, people: int) -> bool:
	return int(claims.get(node.sim_id, 0)) & (1 << people) != 0


static func claim(node: Node, people: int) -> void:
	claims[node.sim_id] = int(claims.get(node.sim_id, 0)) | (1 << people)


static func release(node: Node, people: int) -> void:
	var bits := int(claims.get(node.sim_id, 0)) & ~(1 << people)
	if bits == 0:
		claims.erase(node.sim_id)
	else:
		claims[node.sim_id] = bits


# ------------------------------------------------------------------ the peoples' objects

## Everything people `player` owns (0: the loose objects: animals, mines, stores), as the
## original's per-player lists hold them; trees are apart (tree_list).
static func objects_of(player: int) -> Array:
	var out := []
	for unit in Unit.all_units:
		if unit.team == player and unit.is_alive():
			out.append(unit)
	if player == 0:
		for object in MapObject.all_objects:
			if object.owner_index == 0 and not object.is_tree() and not object.is_ghost and object.is_alive() \
					and (object.is_mine() or object.is_abandoned_store() or object.is_building()):
				out.append(object)
	else:
		for object in MapObject.structures:
			if object.owner_index == player and object.is_alive():
				out.append(object)
	return out


static func trees() -> Array:
	return MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.is_tree() and o.stock.amount > 0)


## The nearest of `candidates` to `at` that `accept` takes (ties: the earlier one).
static func nearest(candidates: Array, at: Vector2, accept: Callable) -> Node:
	var best: Node = null
	var best_distance := INF
	for node in candidates:
		var d: float = at.distance_squared_to(node.position)
		if d < best_distance and accept.call(node):
			best = node
			best_distance = d
	return best


## Searches with a class mask and a state any-of filter (0: any), skipping and taking
## claims for `me` (107-109, 200-202). A mask with the tree or tent bit looks for trees.
static func find_claiming(me: int, player: int, mask: int, at: Vector2, state: int) -> int:
	if mask & (C_TREE | C_TENT):
		var tree := nearest(trees(), at, func(_n: Node) -> bool: return true)
		return handle(tree)
	var found := nearest(objects_of(player), at, func(n: Node) -> bool:
		return class_bits(n) & mask == mask and (state == 0 or state_bits(n) & state != 0) and not claimed(n, me))
	if found:
		claim(found, me)
	return handle(found)


## Searches by type with a state any-of filter, claiming (139-141, 203-205).
static func find_type_claiming(me: int, player: int, guid: int, at: Vector2, state: int, owned_by := -1) -> int:
	var list := objects_of(player)
	if owned_by >= 0:
		list = objects_of(owned_by).filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() in [Mission.HORSE, Mission.COW])
	var found := nearest(list, at, func(n: Node) -> bool:
		return _is_type(n, guid) and (state == 0 or state_bits(n) & state != 0) and not claimed(n, me))
	if found:
		claim(found, me)
	return handle(found)


static func _is_type(node: Node, guid: int) -> bool:
	if node is Unit:
		return Mission.unit_matches(node, guid)
	return Mission.matches(guid_of(node), guid)


## Claiming search with a "none of these states" filter (383, 384).
static func claim_nearest(me: int, player: int, at: Vector2, mask: int, guid: int, notstate: int) -> int:
	var found := nearest(objects_of(player), at, func(n: Node) -> bool:
		return (guid < 0 or _is_type(n, guid)) and (mask == 0 or class_bits(n) & mask == mask) \
				and state_bits(n) & notstate == 0 and not claimed(n, me))
	if found:
		claim(found, me)
	return handle(found)


## Nearest without claims: any-of `state` (or none of `notstate`) (368, 370, 371, 389, 392).
static func nearest_plain(player: int, at: Vector2, mask: int, guid: int, state: int, notstate: int) -> int:
	if player < 0 or player > 8:
		return 0
	return handle(nearest(objects_of(player), at, func(n: Node) -> bool:
		return (guid < 0 or _is_type(n, guid)) and (mask == 0 or class_bits(n) & mask == mask) \
				and (state == 0 or state_bits(n) & state != 0) and state_bits(n) & notstate == 0))


## A foe of `me` within 500 px of `at` with any of `classany` and none of `notstate` (387).
static func enemy_near(me: int, at: Vector2, classany: int, notstate: int) -> int:
	var best: Node = null
	var best_distance := 500.0 * 500.0
	for unit: Unit in UnitGrid.near(at, 500.0):
		var d := at.distance_squared_to(unit.position)
		if d < best_distance and unit.is_alive() and Diplomacy.hostile(me, unit.team) \
				and (classany == 0 or class_bits(unit) & classany != 0) and state_bits(unit) & notstate == 0:
			best = unit
			best_distance = d
	if best == null:
		for object in MapObject.structures:
			var d := at.distance_squared_to(object.position)
			if d < best_distance and object.is_alive() and Diplomacy.hostile(me, object.owner_index) \
					and (classany == 0 or class_bits(object) & classany != 0) and state_bits(object) & notstate == 0:
				best = object
				best_distance = d
	return handle(best)
