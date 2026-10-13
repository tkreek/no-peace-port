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
const S_GATHERING := 0x1  ## worker task bits (the field and wood managers take these as free hands)
const S_BUILDING := 0x2
const S_IDLE := 0x4  ## units: idle; buildings: finished
const S_WORKING := 0x8
const S_PRODUCING := 0x10
const S_FALLOW := 0x40
const S_MOVING := 0x100
const S_SITE := 0x200
## Inside something (unit+0x3f0): aboard a boat or wagon when +0x3a0 is set (boarding,
## 0x41aacb), else quartered in a building (0x41a814); the unit's state at 0x41a37e.
const S_IN_TRANSPORT := 0x400
const S_IN_BUILDING := 0x800
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
static var _building_classes := {}  # building GUID -> class bits but the garrison's
## objects_of's lists, the dead in them too: units by list (all_units order), and by people
## the structures or (0) the loose objects; rebuilt when Unit.roster_version or
## MapObject.roster_version moves. Being alive is asked at every search, so a search finds
## what a scan of everything would.
static var _units_by_list := {}  # list -> Array of units
static var _objects_by_player := {}  # people -> Array of map objects
static var _tree_list: Array[MapObject] = []
## _tree_list by 256 px cell, each tree with its place in the list (built when first asked).
static var _tree_cells := {}  # Vector2i -> Array of [index, tree]
static var _tree_extent := Rect2i()  # the cells there are
const TREE_CELL := 256.0
## Parts of those lists, the dead in them too: Vector3i(list, 0, GUID) what is of that type
## (as Mission counts it), Vector3i(list, 1, mask) what may have all the class bits of mask.
static var _parts := {}
static var _unit_roster := -1
static var _object_roster := -1


static func reset() -> void:
	claims.clear()


static func owner_of(node: Node) -> int:
	return node.team if node is Unit else (node as MapObject).owner_index


## Horses, cows and buffalo: the original keeps them in the loose objects' list whoever owns
## them (the owner is only a field), so their handles never change and the searches over
## people 0 find owned ones too.
static func is_animal(node: Node) -> bool:
	return node is Unit and (node.animal.is_horse() or node.animal.is_cow() or node.unit_type.guid() == Mission.BUFFALO)


## The list an object is in: its owner's, or 0 for animals.
static func list_of(node: Node) -> int:
	return 0 if is_animal(node) else owner_of(node)


static func handle(node: Node) -> int:
	if node == null or not is_instance_valid(node) or node.sim_id == 0:
		return 0
	return (list_of(node) << OWNER_SHIFT) | (node.sim_id & ID_MASK)


static func resolve(h: int) -> Node:
	if h <= 0:
		return null
	var node := Sim.find(h & ID_MASK)
	if node == null or list_of(node) != h >> OWNER_SHIFT or not node.is_alive():
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
	var bits: int = _building_classes.get(object.guid, -1)
	if bits < 0:
		bits = _building_class(object)
		_building_classes[object.guid] = bits
	if object.defence and object.defence.capacity() > 0:
		bits |= C_GARRISON
	return bits


## What a building is by its GUID (the garrison bit, which comes and goes, apart).
static func _building_class(object: MapObject) -> int:
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
			Unit.State.GATHERING:
				bits |= S_WORKING | S_GATHERING
			Unit.State.BUILDING:
				bits |= S_WORKING | S_BUILDING
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
	_refresh_lists()
	var out := []
	for unit: Unit in _units_by_list.get(player, []):
		if unit.is_alive():
			out.append(unit)
	for object: MapObject in _objects_by_player.get(player, []):
		if object.is_alive():
			out.append(object)
	return out


static func _refresh_lists() -> void:
	if _unit_roster != Unit.roster_version:
		_unit_roster = Unit.roster_version
		_parts.clear()
		_units_by_list.clear()
		for unit in Unit.all_units:
			_units_by_list.get_or_add(list_of(unit), []).append(unit)
	if _object_roster != MapObject.roster_version:
		_object_roster = MapObject.roster_version
		_parts.clear()
		_objects_by_player.clear()
		_tree_list.clear()
		_tree_cells.clear()
		var loose := []
		for object in MapObject.all_objects:
			if object.is_tree():
				_tree_list.append(object)
			elif object.owner_index == 0 and not object.is_ghost \
					and (object.is_mine() or object.is_abandoned_store() or object.is_building()):
				loose.append(object)
		_objects_by_player[0] = loose
		# Wall pieces are not in a people's list: the original keeps them in list 10
		# (AmericaAddOn.exe 0x42698e), which only nearest_wall looks through.
		for object in MapObject.structures:
			if object.owner_index != 0 and not WallLine.is_wall(object.guid):
				_objects_by_player.get_or_add(object.owner_index, []).append(object)


## What of list `player` is of type `guid` (by_class false) or may have every class bit of
## `guid` (true: the bits that come and go, garrison and fallow, taken as there), in the
## list's order: a search looks only at these, and asks the rest at the time.
static func _part(player: int, guid: int, by_class: bool) -> Array:
	_refresh_lists()
	var key := Vector3i(player, int(by_class), guid)
	var part = _parts.get(key)
	if part == null:
		part = []
		for list: Array in [_units_by_list.get(player, []), _objects_by_player.get(player, [])]:
			for node: Node in list:
				if (_class_bound(node) & guid == guid) if by_class else _is_type(node, guid):
					part.append(node)
		_parts[key] = part
	return part


## Every class bit `node` may have.
static func _class_bound(node: Node) -> int:
	if node is MapObject and (node as MapObject).is_field():
		return C_BUILDING | C_FIELD | C_FALLOW
	if node is MapObject and (node as MapObject).is_building():
		return class_bits(node) | C_GARRISON
	return class_bits(node)


static func trees() -> Array:
	_refresh_lists()
	return _tree_list.filter(func(o: MapObject) -> bool: return o.stock.amount > 0)


## The nearest tree with wood left (ties: the earlier one).
static func nearest_tree(at: Vector2) -> MapObject:
	_refresh_lists()
	if _tree_list.is_empty():
		return null
	if _tree_cells.is_empty():
		var low := Vector2i(1 << 30, 1 << 30)
		var high := -low
		for i in _tree_list.size():
			var cell := Vector2i((_tree_list[i].position / TREE_CELL).floor())
			_tree_cells.get_or_add(cell, []).append([i, _tree_list[i]])
			low = low.min(cell)
			high = high.max(cell)
		_tree_extent = Rect2i(low, high - low + Vector2i.ONE)
	# Rings of cells round `at` until no nearer tree can be left; what nearest over the whole
	# list gives: the least distance, of equals the earliest in the list.
	var centre := Vector2i((at / TREE_CELL).floor())
	var best: MapObject = null
	var best_distance := INF
	var best_index := -1
	var rings := maxi(maxi(absi(centre.x - _tree_extent.position.x), absi(centre.x - _tree_extent.end.x)),
			maxi(absi(centre.y - _tree_extent.position.y), absi(centre.y - _tree_extent.end.y)))
	for r in rings + 1:
		if best and (r - 1) * TREE_CELL - 1.0 > 0.0 and ((r - 1) * TREE_CELL - 1.0) ** 2 > best_distance:
			break  # every cell of this ring is further off than the best found
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1, 1 if absi(dy) == r else maxi(1, 2 * r)):
				for entry: Array in _tree_cells.get(centre + Vector2i(dx, dy), []):
					var tree: MapObject = entry[1]
					var d := at.distance_squared_to(tree.position)
					if (d < best_distance or (d == best_distance and entry[0] < best_index)) and tree.stock.amount > 0:
						best = tree
						best_distance = d
						best_index = entry[0]
	return best


## The nearest of `candidates` to `at` that `accept` takes (ties: the earlier one).
static func nearest(candidates: Array, at: Vector2, accept: Callable) -> Node:
	var best: Node = null
	var best_distance := INF
	for node: Node2D in candidates:
		var d := at.distance_squared_to(node.position)
		if d < best_distance and accept.call(node):
			best = node
			best_distance = d
	return best


## A flag mask as the scripts hold it (a signed 32-bit value: the leader/hero bit 0x80000000
## arrives as -2147483648) as the unsigned bits class_bits and state_bits give.
static func bits32(value: int) -> int:
	return value & 0xFFFFFFFF


## Searches with a class mask and a state any-of filter (0: any), skipping and taking
## claims for `me` (107-109, 200-202). A mask with the tree or tent bit looks for trees.
static func find_claiming(me: int, player: int, mask: int, at: Vector2, state: int) -> int:
	mask = bits32(mask)
	if mask & (C_TREE | C_TENT):
		return handle(nearest_tree(at))
	var found := nearest(_part(player, mask, true), at, func(n: Node) -> bool:
		return n.is_alive() and class_bits(n) & mask == mask and (state == 0 or state_bits(n) & state != 0) \
				and not claimed(n, me))
	if found:
		claim(found, me)
	return handle(found)


## Searches by type with a state any-of filter, claiming (139-141, 203-205).
static func find_type_claiming(me: int, player: int, guid: int, at: Vector2, state: int, owned_by := -1) -> int:
	var list := _part(0 if owned_by >= 0 else player, guid, false)
	var found := nearest(list, at, func(n: Node) -> bool:
		return n.is_alive() and (owned_by < 0 or is_animal(n) and owner_of(n) == owned_by) \
				and (state == 0 or state_bits(n) & state != 0) and not claimed(n, me))
	if found:
		claim(found, me)
	return handle(found)


static func _is_type(node: Node, guid: int) -> bool:
	if node is Unit:
		return Mission.unit_matches(node, guid)
	return Mission.matches(guid_of(node), guid)


## Claiming search with a "none of these states" filter (383, 384).
static func claim_nearest(me: int, player: int, at: Vector2, mask: int, guid: int, notstate: int) -> int:
	mask = bits32(mask)
	var found := nearest(_candidates(player, mask, guid), at, func(n: Node) -> bool:
		return n.is_alive() and (guid < 0 or _is_type(n, guid)) and (mask == 0 or class_bits(n) & mask == mask) \
				and state_bits(n) & notstate == 0 and not claimed(n, me))
	if found:
		claim(found, me)
	return handle(found)


## Nearest without claims: any-of `state` (or none of `notstate`) (368, 370, 371, 389, 392).
static func nearest_plain(player: int, at: Vector2, mask: int, guid: int, state: int, notstate: int) -> int:
	if player < 0 or player > 8:
		return 0
	mask = bits32(mask)
	return handle(nearest(_candidates(player, mask, guid), at, func(n: Node) -> bool:
		if not n.is_alive() or not (guid < 0 or _is_type(n, guid)) or not (mask == 0 or class_bits(n) & mask == mask):
			return false
		var bits := state_bits(n)
		return (state == 0 or bits & state != 0) and bits & notstate == 0))


## What of list `player` a search for type `guid` (-1: any) with class `mask` (0: any) looks at.
static func _candidates(player: int, mask: int, guid: int) -> Array:
	if guid >= 0:
		return _part(player, guid, false)
	if mask != 0:
		return _part(player, mask, true)
	_refresh_lists()
	return _units_by_list.get(player, []) + _objects_by_player.get(player, [])


## A foe of `me` within 500 px of `at` with any of `classany` and none of `notstate` (387).
static func enemy_near(me: int, at: Vector2, classany: int, notstate: int) -> int:
	var best: Node = null
	var best_distance := 500.0 * 500.0
	for unit: Unit in UnitGrid.near(at, 500.0):
		var d := at.distance_squared_to(unit.position)
		if d < best_distance and unit.is_alive() and Diplomacy.hostile(me, unit.team) and not is_animal(unit) \
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
