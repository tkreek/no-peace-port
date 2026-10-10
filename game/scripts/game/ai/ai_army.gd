class_name AiArmy
extends RefCounted
## The AI's soldiers: training (and horses, rifles and a few canoes), healers, casters and
## boats, research, magic; defending the base, and attacking in growing waves once the
## difficulty's first-attack time has passed. A wave gathers at an assembly point, then
## marches in a double line; the badly wounded turn back; fresh troops follow it out; a
## fifth of the army stays home on the defensive, manning towers or lying in wait. Robbers
## rob and thieves steal what they come across. When the enemy cannot be reached on foot,
## boats ferry the waves, or the Native Americans learn to swim.

const RETREAT_BELOW := 0.3  # energy share at which a unit in a wave turns back
const RETREAT_SECONDS := 60.0  # time at home before it rejoins
const GUARD_SHARE := 0.2
const GATHER_SECONDS := 30.0
const GATHER_DISTANCE := 380.0  # the assembly point, out from the HQ toward the enemy
const DEFEND_RADIUS := 700.0
const BOAT_TARGET := 2
const CANOE_TARGET := 3  # canoes fight only on the water
const SWIM := 914
const ROUTE_CHECK_SECONDS := 120.0

enum Wave { HOME, GATHERING, ATTACKING }

var ai: AiPlayer
var attack_wave := 0  ## waves sent so far
var last_attack := -1000.0
var land_route := true  ## can the army walk to the enemy?
var _state := Wave.HOME
var _wave: Array = []
var _wave_size := 0
var _wave_target := Vector2.INF
var _gather_point := Vector2.INF
var _gather_started := 0.0
var _guard := {}  # instance id -> true: stays home on the defensive
var _retreating := {}  # instance id -> when it turned back
var _route_checked := -1000.0
var _ferry_started := 0.0


func _init(owner: AiPlayer) -> void:
	ai = owner


func think(units: Array, soldiers: Array, hq: MapObject) -> void:
	_train()
	_train_specialists(units, soldiers)
	if ai.level().research or ai.rich() or not land_route:
		_research()
	_magic(units, soldiers)
	_command(soldiers, hq)


# ------------------------------------------------------------------ training

func _train() -> void:
	var player := ai.player
	var canoes := ai.my_units().filter(func(u: Unit) -> bool: return u.unit_type.guid() == UnitWater.CANOE).size()
	var want_canoes := NavGrid.current != null and NavGrid.current.has_water and canoes < CANOE_TARGET
	for building: MapObject in ai.my_buildings():
		var production := building.production
		if not building.complete or production.queue.size() >= 2 or building.guid in MapObject.MAIN_BUILDINGS:
			continue
		# Raise horses for the mounted units while there is room and food to spare.
		if building.guid in BuildingProduction.HORSE_BUILDINGS and int(player.resources.get("food", 0)) > 400 \
				and int(player.resources.get("horses", 0)) < player.horse_capacity() and Sim.randf() < 0.5 \
				and production.enqueue(BuildingProduction.HORSE_GUID):
			continue
		# Rifles for the infantry, while gold allows.
		if building.guid in BuildingProduction.GUN_FACTORIES and int(player.resources.get("guns", 0)) < 8 \
				and int(player.resources.get("gold", 0)) > 250 and production.enqueue(BuildingProduction.GUN_GUID):
			continue
		var options := Array(production.trainable_units()).filter(func(guid: int) -> bool:
			return GameData.stats(guid).get("damage", 0) >= 5 and guid not in Player.COMMANDERS \
					and (guid != UnitWater.CANOE or want_canoes))
		Sim.shuffle(options)
		for guid in options:
			if production.enqueue(guid):
				break


## Healers, casters and boats, which the trainer above leaves out (they don't fight).
func _train_specialists(units: Array, soldiers: Array) -> void:
	for building: MapObject in ai.my_buildings():
		if not building.complete or building.production.queue.size() >= 1:
			continue
		for guid in building.production.trainable_units():
			var unit_type := UnitType.for_guid(guid)
			if unit_type == null or not unit_type.attack_anims.is_empty() or guid in Player.COMMANDERS:
				continue
			var have := units.filter(func(u: Unit) -> bool: return u.unit_type.guid() == guid).size()
			var wanted := 0
			if guid in UnitWater.BOATS:
				wanted = BOAT_TARGET if not land_route else 0
			elif UnitMagic.CASTERS.has(guid):
				wanted = 1 if soldiers.size() >= 6 else 0
			elif unit_type.anim_index("heal") >= 0 and not unit_type.is_transport():
				wanted = soldiers.size() / 8
			if have < wanted and building.production.enqueue(guid):
				return


## Spend spare food and gold on upgrades, one at a time; across the water the Native
## Americans learn to swim first.
func _research() -> void:
	var player := ai.player
	if player.faction == "ind" and not land_route and player.can_research(SWIM):
		for building: MapObject in ai.my_buildings():
			if building.production.queue.is_empty() and SWIM in building.production.researchable_upgrades():
				building.production.enqueue(SWIM)
				return
	if int(player.resources.get("gold", 0)) < 600 or int(player.resources.get("food", 0)) < 800:
		return
	for building: MapObject in ai.my_buildings():
		if not building.production.queue.is_empty():
			continue
		var options := building.production.researchable_upgrades()
		if not options.is_empty():
			building.production.enqueue(Sim.pick(options))
			return


## Medicine men dance (lightning on enemies fighting ours, a shield for a hurt soldier,
## rain on our fields); priests convert enemy soldiers who come close.
func _magic(units: Array, soldiers: Array) -> void:
	for caster: Unit in units:
		var magic := caster.magic
		if caster.state != Unit.State.IDLE or magic.spell >= 0:
			continue
		var spells := magic.known_spells()
		if spells.is_empty():
			continue
		var enemy := caster.nearest_enemy(700.0)
		if 919 in spells and enemy and magic.magic_energy >= UnitMagic.SPELLS[919].cost:
			caster.cast(919, enemy.position)
		elif 948 in spells and enemy and magic.convertible(enemy) and magic.magic_energy >= UnitMagic.SPELLS[948].cost:
			caster.cast(948, enemy.position, enemy)
		elif 922 in spells and magic.magic_energy >= UnitMagic.SPELLS[922].cost:
			for soldier: Unit in soldiers:
				if soldier.state == Unit.State.ATTACKING and soldier.health < soldier.max_health * 0.6 \
						and soldier.magic.shield_time <= 0.0 and soldier.position.distance_to(caster.position) < 600.0:
					caster.cast(922, soldier.position, soldier)
					break
		elif 921 in spells and magic.magic_energy >= magic.magic_pool() * 0.9:
			for field in MapObject.structures:
				if field.is_field() and field.owner_index == ai.player.index \
						and field.stock.field_state == ObjectStock.Field.GROWING and not field.stock.is_rained():
					caster.cast(921, field.position)
					break


# ------------------------------------------------------------------ defence and attack

func _command(soldiers: Array, hq: MapObject) -> void:
	_check_route()
	_retreat_wounded(soldiers)
	var ready := soldiers.filter(func(u: Unit) -> bool: return not _retreating.has(u.get_instance_id()))
	_keep_guard(ready, hq)
	var intruder := _intruder(hq)
	if intruder:
		for unit: Unit in ready:
			if (unit.state == Unit.State.IDLE or unit.state == Unit.State.MOVING) \
					and (_state != Wave.ATTACKING or unit not in _wave):
				unit.attack_move(intruder.position)
		if _state == Wave.GATHERING:
			_state = Wave.HOME  # stay and fight
		return
	_raid(ready.filter(func(u: Unit) -> bool: return not _guard.has(u.get_instance_id())))
	match _state:
		Wave.HOME:
			_form_wave(ready, hq)
		Wave.GATHERING:
			_gather_wave()
		Wave.ATTACKING:
			_reinforce(ready)
			_press_attack()


func _check_route() -> void:
	if ai.elapsed - _route_checked < ROUTE_CHECK_SECONDS:
		return
	_route_checked = ai.elapsed
	if GameData.cmdline_option("ai-ferry") != "":
		land_route = false  # test: behave as if the enemy were across the water
		return
	var target := ai.enemy_base()
	if target == Vector2.INF or NavGrid.current == null or not NavGrid.current.has_water:
		land_route = true
		return
	var path := NavGrid.current.find_path(ai.home, target)
	land_route = not path.is_empty() and path[path.size() - 1].distance_to(target) < 320.0


func _intruder(hq: MapObject) -> Unit:
	var buildings := ai.my_buildings()
	for unit in Unit.all_units:
		if unit.team > 0 and unit.team != ai.player.index and unit.is_alive() and not unit.inside:
			for building: MapObject in buildings:
				if building.position.distance_to(unit.position) < DEFEND_RADIUS * (1.0 if building == hq else 0.5):
					return unit
	return null


## Units below RETREAT_BELOW energy leave the wave and go home for a while.
func _retreat_wounded(soldiers: Array) -> void:
	for unit: Unit in soldiers:
		var id := unit.get_instance_id()
		if _retreating.has(id):
			if ai.elapsed - float(_retreating[id]) > RETREAT_SECONDS or unit.health >= unit.max_health * 0.8:
				_retreating.erase(id)
			continue
		if unit.health < unit.max_health * RETREAT_BELOW and unit.position.distance_to(ai.home) > 600.0 \
				and unit.state != Unit.State.QUARTERED:
			_retreating[id] = ai.elapsed
			_wave.erase(unit)
			unit.move_to(_near_home())


func _near_home() -> Vector2:
	return ai.home + Vector2(Sim.randf_range(-80, 80), Sim.randf_range(60, 140))


## A fifth of the army (at least two) stays home on the defensive; ranged guards man the
## towers and the Native scouts lie in wait camouflaged.
func _keep_guard(soldiers: Array, hq: MapObject) -> void:
	for id in _guard.keys():
		if not is_instance_valid(instance_from_id(id)):
			_guard.erase(id)
	var wanted := maxi(2, int(soldiers.size() * GUARD_SHARE)) if soldiers.size() >= 4 else 0
	for unit: Unit in soldiers:
		if _guard.size() >= wanted:
			break
		if not _guard.has(unit.get_instance_id()) and unit not in _wave:
			_guard[unit.get_instance_id()] = true
			unit.set_stance(Unit.Stance.DEFENSIVE)
	var towers := ai.my_buildings().filter(func(b: MapObject) -> bool:
		return b.complete and b.defence.capacity() > 0 and b.guid not in MapObject.MAIN_BUILDINGS)
	var enemy := ai.enemy_base()
	var toward := (enemy - hq.position).normalized() if enemy != Vector2.INF else Vector2.DOWN
	for unit: Unit in soldiers:
		if not _guard.has(unit.get_instance_id()) or unit.state != Unit.State.IDLE:
			continue
		for tower: MapObject in towers:
			if unit.unit_type.ranged and tower.defence.has_room_for(unit):
				unit.take_quarters(tower)
				break
		if unit.state == Unit.State.IDLE and unit.quarters == null:
			if unit.position.distance_to(hq.position) > 500.0:
				unit.move_to(hq.position + toward * 220.0 + Vector2(Sim.randf_range(-90, 90), Sim.randf_range(-60, 60)))
			elif unit.stealth.can_hide() and not unit.stealth.concealed:
				unit.conceal()


func _form_wave(soldiers: Array, hq: MapObject) -> void:
	var free := soldiers.filter(func(u: Unit) -> bool: return not _guard.has(u.get_instance_id()))
	var wave_size: int = ai.level().wave + attack_wave * 2
	if ai.elapsed < ai.level().first_attack or free.size() < wave_size or ai.elapsed - last_attack < 60.0:
		return
	var target := ai.enemy_base()
	if target == Vector2.INF:
		return
	_wave = free
	_wave_size = free.size()
	_wave_target = target
	_gather_point = hq.position + (target - hq.position).normalized() * GATHER_DISTANCE
	if not land_route:
		_gather_point = _shore_near(hq.position)
		_ferry_started = ai.elapsed
	_gather_started = ai.elapsed
	_state = Wave.GATHERING
	for unit: Unit in _wave:
		unit.set_stance(Unit.Stance.AGGRESSIVE)
		unit.stealth.uncover()
	_march(_gather_point, false)


## Wait at the assembly point until most of the wave is there (or long enough), then go.
## Across the water the boats take them: board, then sail for the enemy's shore.
func _gather_wave() -> void:
	_wave = _wave.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive())
	if _wave.is_empty():
		_state = Wave.HOME
		return
	if not land_route and not _can_cross_alone():
		_ferry()
		return
	var there := _wave.filter(func(u: Unit) -> bool: return u.position.distance_to(_gather_point) < 220.0).size()
	if there < _wave.size() * 0.75 and ai.elapsed - _gather_started < GATHER_SECONDS:
		return
	_set_out()
	ai.trace("attacks with %d units (wave %d%s)" % [_wave.size(), attack_wave, "" if land_route else ", swimming"])
	_march(_wave_target, true)


func _set_out() -> void:
	attack_wave += 1
	last_attack = ai.elapsed
	_state = Wave.ATTACKING


## While a wave is out, fresh troops at home follow it once there are enough of them.
func _reinforce(soldiers: Array) -> void:
	if not land_route:
		return
	var free := soldiers.filter(func(u: Unit) -> bool:
		return not _guard.has(u.get_instance_id()) and u not in _wave and u.state == Unit.State.IDLE)
	if free.size() < maxi(4, ai.level().wave / 2):
		return
	for unit: Unit in free:
		unit.set_stance(Unit.Stance.AGGRESSIVE)
		unit.attack_move(_wave_target + Vector2(Sim.randf_range(-80, 80), Sim.randf_range(-80, 80)))
	_wave.append_array(free)


## The wave presses on to the next enemy building once its target falls; when it has
## melted away the survivors come home.
func _press_attack() -> void:
	_wave = _wave.filter(func(u: Object) -> bool: return is_instance_valid(u) and u.is_alive())
	if _wave.size() < maxi(1, _wave_size / 4):
		for unit: Unit in _wave:
			if not unit.inside:
				unit.move_to(_near_home())
		_state = Wave.HOME
		return
	var target := ai.enemy_base()
	if target == Vector2.INF:
		return
	if target.distance_to(_wave_target) > 64.0:
		_wave_target = target
		_march(target, true)
		return
	for unit: Unit in _wave:
		if unit.state == Unit.State.IDLE and not unit.inside:
			unit.attack_move(target + Vector2(Sim.randf_range(-60, 60), Sim.randf_range(-60, 60)))
	# Boats that have put their troops ashore go back for more.
	for boat: Unit in ai.my_units().filter(func(u: Unit) -> bool: return u.water.is_boat() and u.water.passengers.is_empty()):
		if boat.state == Unit.State.IDLE and boat.position.distance_to(ai.home) > 900.0:
			boat.move_to(_shore_near(ai.home))


## Move the wave to `point` in a double line facing it.
func _march(point: Vector2, fighting: bool) -> void:
	var units := _wave.filter(func(u: Unit) -> bool: return not u.inside)
	if units.is_empty():
		return
	var centre := SelectionController._centre(units)
	var facing := (point - centre).normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN
	var side := facing.orthogonal()
	units.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.dot(side) < b.position.dot(side))
	var slots := SelectionController.formation_slots(units.size(), Unit.Formation.DOUBLE_LINE)
	for i in units.size():
		var unit: Unit = units[i]
		unit.formation = Unit.Formation.DOUBLE_LINE
		var spot := point + (side * slots[i].x - facing * slots[i].y) * SelectionController.FORMATION_SPACING
		if fighting:
			unit.attack_move(spot)
		else:
			unit.move_to(spot)


# ------------------------------------------------------------------ across the water

## The Native Americans swim once they know how (mounted units stay behind).
func _can_cross_alone() -> bool:
	if ai.player.faction != "ind":
		return false
	var swimmers := _wave.filter(func(u: Unit) -> bool: return u.water.nav_layer() != NavGrid.Layer.GROUND)
	if swimmers.size() < ai.level().wave / 2:
		return false
	_wave = swimmers
	return true


func _ferry() -> void:
	var boats := ai.my_units().filter(func(u: Unit) -> bool: return u.water.is_boat())
	if boats.is_empty():
		if ai.elapsed - _ferry_started > 240.0:
			_state = Wave.HOME  # no boats came: try again later
		return
	var aboard := 0
	for boat: Unit in boats:
		aboard += boat.water.passengers.size()
	var waiting := _wave.filter(func(u: Unit) -> bool: return not u.inside)
	for boat: Unit in boats:
		var water := boat.water
		if boat.state == Unit.State.IDLE and water.passengers.is_empty() and boat.position.distance_to(_gather_point) > 200.0:
			boat.move_to(_gather_point)
		var room := water.capacity() - water.passengers.size()
		for unit: Unit in waiting.duplicate():
			if room <= 0:
				break
			if unit.water.vessel == null and unit.state == Unit.State.IDLE:
				unit.board(boat)
				waiting.erase(unit)
				room -= 1
	var full := boats.all(func(b: Unit) -> bool: return b.water.passengers.size() >= b.water.capacity())
	if aboard > 0 and (waiting.is_empty() or full or ai.elapsed - _ferry_started > 90.0):
		_set_out()
		ai.trace("ferries %d units (wave %d)" % [aboard, attack_wave])
		var landing := _shore_near(_wave_target)
		for boat: Unit in boats:
			if not boat.water.passengers.is_empty():
				boat.unload_at(landing)
		_wave = _wave.filter(func(u: Unit) -> bool: return u.inside)
		_wave_size = _wave.size()


## The water's edge nearest `point` (on the water), or the point itself on a dry map.
func _shore_near(point: Vector2) -> Vector2:
	var nav := NavGrid.current
	if nav == null or not nav.has_water:
		return point
	var cell := nav.nearest_passable(nav.cell_of(point), 60, NavGrid.Layer.WATER)
	return nav.center_of(cell) if cell.x >= 0 else point


## Robbers rob enemy banks, missions and gold warehouses in reach; thieves steal the enemy's
## wagons when they see one.
func _raid(soldiers: Array) -> void:
	for unit: Unit in soldiers:
		if unit.state != Unit.State.IDLE and unit.state != Unit.State.MOVING:
			continue
		if unit.work.can_steal():
			for other in Unit.all_units:
				if other.is_alive() and other.team > 0 and other.team != ai.player.index and other.unit_type.is_transport() \
						and other.position.distance_to(unit.position) < unit.sight():
					unit.steal(other)
					break
		if unit.work.can_rob() and unit.state != Unit.State.GATHERING:
			for object in MapObject.structures:
				if object.is_building() and object.owner_index > 0 and object.owner_index != ai.player.index \
						and object.is_alive() and UnitWork.loot_of(object) > 0 and object.position.distance_to(unit.position) < 900.0:
					unit.rob(object)
					break
