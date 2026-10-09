class_name Unit
extends Node2D
## A unit drawn with its original 8-direction sprite animations, team palette and shadow.
## Behaviour is a small state machine: idle (auto-engage enemies in sight), moving,
## attacking (chase into range, play the attack animation sequence, deal damage), dead.

signal died(unit: Unit)

enum State { IDLE, MOVING, ATTACKING, GATHERING, BUILDING, DEAD, QUARTERED }
enum Gather { TO_SOURCE, WORKING, TO_DROP_OFF }
## Rules of conduct for military units (manual 4.1): aggressive units pursue relentlessly,
## defensive ones only a short way before returning, units holding ground never leave their
## spot, and passive units neither move nor fight back.
enum Stance { AGGRESSIVE, DEFENSIVE, HOLD, PASSIVE }
## Formations from the command menu (manual 4.2), used when a group is given a move order.
enum Formation { COLUMN, DOUBLE_COLUMN, WEDGE, DOUBLE_LINE, SQUARE, RELAXED }

const ARRIVE_DISTANCE := 3.0
const REPATH_MS := 600
const CORPSE_SECONDS := 20.0
const SEPARATION_RADIUS := 14.0
const SCAN_INTERVAL := 0.4
const WORK_SECONDS := {"wood": 4.0, "gold": 5.0, "food": 5.0}
## Food from a hunted animal, by object name prefix.
const MEAT := {"Tier_B": 150, "Tier_K": 100, "Tier_P": 60}  # buffalo, cow, horse
const HUNT_RANGE := 1500.0
const REACH := 20.0
const DEFENSIVE_PURSUIT := 160.0  # how far defensive units chase before returning
const FOLLOW_DISTANCE := 48.0
const BUTCHER_SECONDS := 2.5
const HEAL_PER_SECOND := 4.0
const HEAL_REACH := 40.0

static var debug_paths := false
static var all_units: Array[Unit] = []

var unit_type: UnitType
var team := 1
var selected := false:
	set(value):
		selected = value
		queue_redraw()
		if is_instance_valid(_overlay):
			_overlay.queue_redraw()
var direction := 1  # sprite direction row: 0 = SE, then clockwise (1 = S ... 7 = E)
var max_health := 100.0
var health := 100.0
var path := PackedVector2Array()
var state := State.IDLE
var target: Node2D  ## Unit or MapObject building
var attack_moving := false  ## moving, but engage enemies met on the way
var stance := Stance.AGGRESSIVE
var formation := Formation.RELAXED
var follow_target: Unit  ## keep close to this unit until given another order
var _patrol := PackedVector2Array()  ## the two ends of a patrol route
var quarters: MapObject  ## the building this unit is heading into or sitting in
var heal_target: Unit  ## a wounded friend this nurse, nun, priest or medicine man is tending
var _ordered := false  ## the current target was picked by the player, not by the stance
var hunting := false  ## target is an animal; carry the meat home after the kill
var guard_position := Vector2.ZERO  # where an idle unit returns after chasing
## Hidden by the fog of war (enemy out of sight) / inside a building such as a gold mine.
var fogged := false:
	set(value):
		fogged = value
		visible = not fogged and not inside
var inside := false:
	set(value):
		inside = value
		visible = not fogged and not inside
var carrying := ""  # resource in hand ("" when empty-handed)
var gather_resource := ""  # what this worker is assigned to collect
var hunted := false  ## an animal whose meat has been taken
var carried := 0
var gather_source: MapObject
var _gather_phase := Gather.TO_SOURCE
var _work_timer := 0.0
var _drop_off: MapObject
var build_site: MapObject

var _overlay := DrawOverlay.new()
var _body := Sprite2D.new()
var _shadow := Sprite2D.new()
var _action := ""
var _anim := -1
var _shadow_anim := -1
var _step := 0
var _step_time := 0.0
var _anim_finished := false
var _attack_step := -1  # position in unit_type.attack_anims, -1 = not in an attack
var _cooldown := 0.0
var _scan_timer := randf() * SCAN_INTERVAL
var _last_repath := 0
var _corpse_timer := 0.0


func setup(type: UnitType, team_index: int) -> void:
	unit_type = type
	team = team_index
	max_health = type.health
	health = max_health
	refresh_upgrades.call_deferred()
	guard_position = position
	for sprite: Sprite2D in [_shadow, _body]:
		sprite.centered = false
		sprite.region_enabled = true
	SpriteMaterials.make_shadow(_shadow)
	add_child(_shadow)
	add_child(_body)
	add_child(_overlay)
	_body.set_instance_shader_parameter("palette_row", clampi(team, 0, type.bob.palettes.size() - 1))
	all_units.append(self)
	play("idle")


func _exit_tree() -> void:
	all_units.erase(self)


var _flash_time := 0.0


## Briefly tint the unit to confirm it was picked as an attack target.
func flash(color := Color(1.0, 0.35, 0.3)) -> void:
	_flash_time = 0.8
	_body.self_modulate = color


## Researched upgrades of this unit's player (see Player.bonus).
func _bonus(effect: String) -> float:
	var player: Player = Player.by_index.get(team)
	return player.bonus(unit_type.guid(), effect, unit_type.mounted) if player else 0.0


## Re-apply life-energy upgrades, keeping the current health ratio.
func refresh_upgrades() -> void:
	if not is_alive():
		return
	var ratio := health / max_health if max_health > 0 else 1.0
	max_health = unit_type.health * (1.0 + _bonus("health_pct") / 100.0)
	health = max_health * ratio
	_overlay.queue_redraw()


func attack_damage() -> float:
	return unit_type.damage + _bonus("attack")


func attack_range() -> float:
	return unit_type.attack_range * (1.0 + _bonus("range_pct") / 100.0)


func sight() -> float:
	return unit_type.sight * (1.0 + _bonus("sight_pct") / 100.0)


func move_speed() -> float:
	var tiers := int(_bonus("speed_tiers"))
	if tiers == 0:
		return unit_type.speed
	var tier := int(GameData.stats(unit_type.guid()).get("speed_tier", 2)) + tiers
	return GameData.def_value("LaufenSpeed%d" % mini(tier, 5), 100) * 0.6


func display_name() -> String:
	return unit_type.display_name()


func is_alive() -> bool:
	return state != State.DEAD


func set_stance(value: Stance) -> void:
	stance = value
	if stance == Stance.PASSIVE and state == State.ATTACKING and not _ordered:
		stop()


## How far an idle unit looks for enemies to engage on its own.
func _engage_radius() -> float:
	match stance:
		Stance.PASSIVE:
			return 0.0
		Stance.HOLD:
			return attack_range()
	return sight()


func _may_engage(enemy: Node2D) -> bool:
	match stance:
		Stance.PASSIVE:
			return false
		Stance.HOLD:
			return position.distance_to(_aim_point(enemy)) <= attack_range()
	return true


func is_enemy_of(other: Unit) -> bool:
	if other.state == State.QUARTERED:
		return false  # out of reach behind the walls
	return other.team != team and other.team > 0 and team > 0


# ------------------------------------------------------------------ orders

## Move, fighting any enemy that comes within sight on the way.
func attack_move(destination: Vector2, keep_orders := false) -> void:
	move_to(destination, keep_orders)
	attack_moving = true


## Walk back and forth between here and `destination`, engaging enemies met on the way.
func patrol(destination: Vector2) -> void:
	if not is_alive():
		return
	var start := position
	attack_move(destination)
	_patrol = PackedVector2Array([start, destination])


func follow(leader: Unit) -> void:
	if not is_alive() or leader == null or leader == self or not leader.is_alive():
		return
	stop()
	follow_target = leader


func _clear_orders() -> void:
	_patrol.clear()
	follow_target = null
	heal_target = null
	if state != State.QUARTERED:
		quarters = null


## Walk to one of our buildings with room (fort, tower) and take quarters inside.
func take_quarters(building: MapObject) -> void:
	if not is_alive() or building == null or not building.has_room_for(self):
		return
	move_to(building.work_rect().get_center())
	quarters = building


func enter_quarters(building: MapObject) -> void:
	quarters = building
	path.clear()
	target = null
	state = State.QUARTERED
	inside = true
	selected = false
	position = building.work_rect().get_center()


func leave_quarters(at: Vector2) -> void:
	quarters = null
	inside = false
	position = at
	state = State.IDLE
	guard_position = at
	play("idle")


func ready_to_fire() -> bool:
	return _cooldown <= 0.0


## A shot from inside quarters: no animation (the unit is out of sight), just the report.
func fire_from_quarters(enemy: Node2D, from: Vector2) -> void:
	_cooldown = unit_type.reload_ms / 1000.0
	Sound.play_event(unit_type.guid(), Sound.Event.SHOOT, from, 60)
	var accuracy := clampf(1.1 - from.distance_to(enemy.position) / ((attack_range() + 60.0) * 1.6), 0.4, 0.95)
	if randf() <= accuracy:
		enemy.take_damage(attack_damage(), self)


func move_to(destination: Vector2, keep_orders := false) -> void:
	if not is_alive():
		return
	if not keep_orders:
		_clear_orders()
	attack_moving = false
	target = null
	gather_source = null
	inside = false
	_attack_step = -1
	guard_position = destination
	path = _find_path(destination)
	state = State.MOVING if not path.is_empty() else State.IDLE


## Fight `enemy`. `ordered` when the player gave the order (ignores the stance's limits).
func attack(enemy: Node2D, ordered := false) -> void:
	if not is_alive() or enemy == null or not enemy.is_alive() or unit_type.attack_anims.is_empty():
		return
	if state != State.ATTACKING:
		guard_position = position if state != State.MOVING else guard_position
	_ordered = ordered
	if ordered:
		_clear_orders()
	hunting = false
	target = enemy
	gather_source = null
	inside = false
	state = State.ATTACKING
	path.clear()


## Kill an animal and carry its meat to a butcher or the main building, then hunt again.
func hunt(animal: Unit) -> void:
	if not unit_type.is_hunter() or animal == null or not animal.is_alive() or animal.team != 0:
		return
	_clear_orders()
	attack(animal)
	hunting = true


func meat_value() -> int:
	var type := ObjectTypes.get_type(unit_type.type_id)
	for prefix in MEAT:
		if type and type.name.begins_with(prefix):
			return MEAT[prefix]
	return 60


## Walk to a construction site and work on it until it is finished.
func build(site: MapObject) -> void:
	if not is_alive() or site == null or site.complete or not unit_type.can_build(site.guid):
		return
	_clear_orders()
	build_site = site
	target = null
	gather_source = null
	inside = false
	state = State.BUILDING
	path = _find_path(site.position)


## Harvest `source` repeatedly, carrying loads to the nearest drop-off.
func gather(source: MapObject) -> void:
	if not is_alive() or source == null or not unit_type.can_gather(source.resource):
		return
	if carrying != "" and carrying != source.resource:
		carrying = ""
		carried = 0
	_clear_orders()
	gather_source = source
	gather_resource = source.resource
	target = null
	state = State.GATHERING
	_gather_phase = Gather.TO_DROP_OFF if carried >= UnitType.CARRY_AMOUNT else Gather.TO_SOURCE
	_route_gather()


func stop() -> void:
	_clear_orders()
	path.clear()
	target = null
	gather_source = null
	build_site = null
	inside = false
	_attack_step = -1
	guard_position = position
	if is_alive():
		state = State.IDLE


func take_damage(amount: float, attacker: Node2D = null) -> void:
	if not is_alive() or state == State.QUARTERED:
		return
	health = maxf(0.0, health - amount)
	_overlay.queue_redraw()
	if health <= 0.0:
		_die()
	elif state == State.IDLE and attacker and attacker.is_alive() and _may_engage(attacker):
		attack(attacker)  # fight back


# ------------------------------------------------------------------ behaviour

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if state == State.QUARTERED:
		return
	if quarters != null and (state == State.MOVING or state == State.IDLE) and is_instance_valid(quarters) \
			and quarters.work_rect().grow(REACH * 2.0).has_point(position):
		if not quarters.enter(self):
			quarters = null
			stop()
		return
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_body.self_modulate = Color.WHITE
	if follow_target != null and (state == State.IDLE or state == State.MOVING):
		_update_follow()
	if heal_target != null and (state == State.IDLE or state == State.MOVING):
		_update_heal(delta)
		_advance(delta)
		return
	match state:
		State.IDLE:
			_scan_timer -= delta
			if _scan_timer <= 0.0:
				_scan_timer = SCAN_INTERVAL
				if is_healer():
					heal_target = _nearest_wounded()
				else:
					var enemy := _nearest_enemy(_engage_radius())
					if enemy:
						attack(enemy)
			play("idle")
		State.MOVING:
			if attack_moving:
				_scan_timer -= delta
				if _scan_timer <= 0.0:
					_scan_timer = SCAN_INTERVAL
					var enemy := _nearest_target(sight())
					if enemy:
						var resume := guard_position
						attack(enemy)
						guard_position = resume
						return
			_follow_path(delta)
			if path.is_empty() and _patrol.size() == 2:
				# Turn round at the end of the route.
				var back := _patrol[0] if position.distance_to(_patrol[1]) < position.distance_to(_patrol[0]) else _patrol[1]
				attack_move(back, true)
			elif path.is_empty():
				state = State.IDLE
				attack_moving = false
			play(_walk_action() if state == State.MOVING else _idle_action())
		State.GATHERING:
			_update_gather(delta)
		State.BUILDING:
			_update_build(delta)
		State.ATTACKING:
			_update_attack(delta)
		State.DEAD:
			_corpse_timer += delta
			if _corpse_timer > CORPSE_SECONDS:
				modulate.a = maxf(0.0, 1.0 - (_corpse_timer - CORPSE_SECONDS) / 3.0)
				if modulate.a <= 0.0:
					queue_free()
	if state != State.DEAD and not inside:
		_separate(delta)
	if debug_paths:
		_overlay.queue_redraw()
	_advance(delta)


func is_healer() -> bool:
	return unit_type.attack_anims.is_empty() and unit_type.anim_index("heal") >= 0


func _nearest_wounded() -> Unit:
	var best: Unit = null
	var best_distance := sight()
	for other in all_units:
		if other != self and other.team == team and other.is_alive() and not other.inside \
				and other.health < other.max_health:
			var distance := position.distance_to(other.position)
			if distance < best_distance:
				best = other
				best_distance = distance
	return best


## Walk up to the wounded unit and tend it until it is whole again.
func _update_heal(delta: float) -> void:
	if not is_instance_valid(heal_target) or not heal_target.is_alive() or heal_target.inside \
			or heal_target.health >= heal_target.max_health:
		heal_target = null
		state = State.IDLE
		return
	if position.distance_to(heal_target.position) > HEAL_REACH:
		var now := Time.get_ticks_msec()
		if path.is_empty() or now - _last_repath > REPATH_MS:
			_last_repath = now
			path = _find_path(heal_target.position)
		_follow_path(delta)
		play("walk")
		state = State.MOVING
		return
	path.clear()
	state = State.IDLE
	face(heal_target.position - position)
	play_repeating("heal")
	heal_target.health = minf(heal_target.max_health, heal_target.health + HEAL_PER_SECOND * delta)
	heal_target._overlay.queue_redraw()


func _update_follow() -> void:
	if not is_instance_valid(follow_target) or not follow_target.is_alive():
		follow_target = null
		return
	if position.distance_to(follow_target.position) < FOLLOW_DISTANCE:
		if state == State.MOVING:
			path.clear()
			state = State.IDLE
		return
	var now := Time.get_ticks_msec()
	if state == State.IDLE or now - _last_repath > REPATH_MS:
		_last_repath = now
		path = _find_path(follow_target.position)
		state = State.MOVING if not path.is_empty() else State.IDLE


func _update_attack(delta: float) -> void:
	if hunting and is_instance_valid(target) and target is Unit and not target.is_alive() and _attack_step < 0:
		_butcher(target, delta)
		return
	if target == null or not is_instance_valid(target) or not target.is_alive():
		target = null
		if hunting and _attack_step < 0:
			var animal := _nearest_animal()  # someone else took this carcass
			if animal:
				hunt(animal)
			else:
				stop()
			return
		if _attack_step < 0:
			# Look for the next enemy nearby before standing down.
			var enemy := _nearest_target(_engage_radius())
			if enemy:
				target = enemy
			elif (position.distance_to(guard_position) > 64.0 or _patrol.size() == 2) and guard_position != Vector2.ZERO:
				attack_move(guard_position, true)  # carry on to where we were heading
				return
			else:
				state = State.IDLE
				return
	if _attack_step >= 0:
		_continue_attack()
		return
	var to_target := _aim_point(target) - position
	# Cannons cannot fire point-blank: roll back out to their minimum range first.
	if unit_type.min_range > 0.0 and unit_type.attack_range >= 350.0 and to_target.length() < unit_type.min_range:
		if path.is_empty():
			path = _find_path(position - to_target.normalized() * (unit_type.min_range - to_target.length() + 30.0))
		_follow_path(delta)
		face(-to_target)
		play("walk")
		return
	if to_target.length() > attack_range() and not _ordered and not hunting:
		# The stance limits how far a unit goes after enemies it picked itself.
		var leash := INF
		if stance == Stance.HOLD or stance == Stance.PASSIVE:
			leash = 0.0
		elif stance == Stance.DEFENSIVE:
			leash = DEFENSIVE_PURSUIT
		if position.distance_to(guard_position) >= leash:
			target = null
			if stance == Stance.DEFENSIVE and position.distance_to(guard_position) > 16.0:
				var home := guard_position
				move_to(home)
			else:
				state = State.IDLE
			return
	if to_target.length() > attack_range():
		var now := Time.get_ticks_msec()
		if path.is_empty() or now - _last_repath > REPATH_MS:
			_last_repath = now
			path = _find_path(target.position)
		_follow_path(delta)
		play("walk")
		return
	path.clear()
	face(to_target)
	if _cooldown <= 0.0:
		_attack_step = 0
		_play_index(unit_type.attack_anims[0])
	else:
		play("idle")


func _continue_attack() -> void:
	if is_instance_valid(target):
		face(_aim_point(target) - position)
	if not _anim_finished:
		return
	if _attack_step == unit_type.fire_step:
		_strike()
	_attack_step += 1
	if _attack_step >= unit_type.attack_anims.size():
		_attack_step = -1
		_cooldown = unit_type.reload_ms / 1000.0
		play("idle")
	else:
		_play_index(unit_type.attack_anims[_attack_step])


func _strike() -> void:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	var event := Sound.Event.SHOOT if unit_type.ranged else Sound.Event.MELEE
	Sound.play_event(unit_type.guid(), event, position, 60)
	# Ranged hits are not certain; distance makes them less likely.
	var hit := true
	if unit_type.ranged:
		var accuracy := clampf(1.1 - position.distance_to(_aim_point(target)) / (attack_range() * 1.6), 0.4, 0.95)
		hit = randf() <= accuracy
	if unit_type.ranged and unit_type.projectile_anim >= 0:
		Projectile.launch(self, target, attack_damage(), hit)  # damage lands with it
	elif hit:
		target.take_damage(attack_damage(), self)


func _die() -> void:
	state = State.DEAD
	target = null
	path.clear()
	selected = false
	Sound.play_event(unit_type.guid(), Sound.Event.DIE, position, 0)
	play("die")
	z_index = -1  # corpses lie under the living
	died.emit(self)


func _walk_action() -> String:
	if carrying != "" and unit_type.anim_index("carry_" + carrying) >= 0:
		return "carry_" + carrying
	return "walk"


func _idle_action() -> String:
	if carrying != "" and unit_type.anim_index("carry_%s_idle" % carrying) >= 0:
		return "carry_%s_idle" % carrying
	return "idle"


func _update_gather(delta: float) -> void:
	match _gather_phase:
		Gather.TO_SOURCE:
			if not _source_valid():
				gather_source = _nearest_source(_last_resource(), 1200.0)
				if gather_source == null:
					state = State.IDLE
					return
				_route_gather()
			_follow_path(delta)
			play(_walk_action())
			if gather_source.work_rect().grow(REACH).has_point(position) or path.is_empty():
				path.clear()
				_gather_phase = Gather.WORKING
				var faster := _bonus("chop_pct") if gather_source.resource == "wood" else _bonus("mine_pct")
				if gather_source.resource == "food":
					faster = 0.0
				_work_timer = WORK_SECONDS.get(gather_source.resource, 4.0) / (1.0 + faster / 100.0)
				face(gather_source.work_rect().get_center() - position)
				if gather_source.resource == "gold":
					inside = true  # workers go inside the mine
		Gather.WORKING:
			if not _source_valid():
				# Felled or emptied by someone else: find the next source.
				inside = false
				gather_source = null
				_gather_phase = Gather.TO_SOURCE
				return
			if gather_source.is_field() and gather_source.field_state != MapObject.Field.RIPE:
				if gather_source.field_state == MapObject.Field.FALLOW:
					play_repeating("sow")
					gather_source.sow(delta)
				else:
					play("idle")  # wait for the crop to ripen
				return
			if gather_source.resource == "food":
				play_repeating("harvest")
			elif gather_source.is_mine():
				gather_source.add_mine_work(delta)
			_work_timer -= delta
			if gather_source.resource == "wood":
				if play_repeating("chop"):
					Sound.play_event(unit_type.guid(), Sound.Event.CHOP, position, 300, get_instance_id(), Sound.WORK_RANGE)
			if _work_timer > 0.0:
				return
			var resource := gather_source.resource
			var got := gather_source.harvest(UnitType.CARRY_AMOUNT)
			inside = false
			if got > 0:
				carrying = resource
				carried = got
			_gather_phase = Gather.TO_DROP_OFF if carried > 0 else Gather.TO_SOURCE
			_route_gather()
		Gather.TO_DROP_OFF:
			if _drop_off == null or not is_instance_valid(_drop_off):
				_route_gather()
				if _drop_off == null:
					state = State.IDLE
					return
			_follow_path(delta)
			play(_walk_action())
			if _drop_off.work_rect().grow(REACH).has_point(position) or path.is_empty():
				path.clear()
				var player: Player = Player.by_index.get(team)
				if player and carried > 0:
					player.add(carrying, carried)
				carried = 0
				carrying = ""  # walk back empty-handed
				if gather_resource == "meat":
					var next := _nearest_animal()
					gather_resource = ""
					if next:
						hunt(next)
					else:
						state = State.IDLE
					return
				_gather_phase = Gather.TO_SOURCE
				_route_gather()


func _update_build(delta: float) -> void:
	if build_site == null or not is_instance_valid(build_site) or build_site.complete:
		build_site = null
		state = State.IDLE
		return
	if not build_site.work_rect().grow(REACH).has_point(position):
		if path.is_empty():
			path = _find_path(build_site.position)
		_follow_path(delta)
		play(_walk_action())
		if not path.is_empty():
			return
	path.clear()
	face(build_site.work_rect().get_center() - position)
	# Women without a hammering animation swing their axe instead.
	play_repeating("build" if unit_type.anim_index("build") >= 0 else "chop")
	build_site.add_build_work(delta)


## Walk up to the kill and gut it (the hunters' "erlegen"/"ausbeinen" animation), then
## carry the meat home.
func _butcher(animal: Unit, delta: float) -> void:
	if unit_type.anim_index("butcher") < 0:
		_carry_meat(animal)
		return
	if position.distance_to(animal.position) > 26.0:
		if path.is_empty():
			path = _find_path(animal.position)
			_work_timer = BUTCHER_SECONDS
		_follow_path(delta)
		play("walk")
		if not path.is_empty():
			return
	path.clear()
	face(animal.position - position)
	play_repeating("butcher")
	_work_timer -= delta
	if _work_timer <= 0.0:
		_carry_meat(animal)


func _carry_meat(animal: Unit) -> void:
	carrying = "food"
	carried = animal.meat_value()
	animal.hunted = true
	animal.queue_free()  # the carcass is carried away
	target = null
	hunting = false
	gather_resource = "meat"
	gather_source = null
	state = State.GATHERING
	_gather_phase = Gather.TO_DROP_OFF
	_route_gather()


func _nearest_animal() -> Unit:
	var best: Unit = null
	var best_distance := HUNT_RANGE
	for other in all_units:
		if other.team == 0 and other.is_alive():
			var distance := position.distance_to(other.position)
			if distance < best_distance:
				best = other
				best_distance = distance
	return best


func _route_gather() -> void:
	if _gather_phase == Gather.TO_DROP_OFF:
		_drop_off = _nearest_drop_off(carrying)
		path = _find_path(_drop_off.position) if _drop_off else PackedVector2Array()
	elif _source_valid():
		path = _find_path(gather_source.position)


func _source_valid() -> bool:
	if gather_source == null or not is_instance_valid(gather_source) or gather_source.resource == "":
		return false
	return gather_source.is_field() or gather_source.amount > 0


func _last_resource() -> String:
	if gather_resource != "":
		return gather_resource
	return "wood" if unit_type.can_gather("wood") else "gold"


func _nearest_source(resource: String, max_distance := INF) -> MapObject:
	var best: MapObject = null
	var best_distance := max_distance
	for object in MapObject.all_objects:
		var usable := object.resource == resource and (object.amount > 0 or object.is_field())
		if usable and object.is_field() and object.owner_index != team:
			usable = false
		if usable:
			var distance := position.distance_to(object.position)
			if distance < best_distance:
				best = object
				best_distance = distance
	return best


func _nearest_drop_off(resource: String) -> MapObject:
	var best: MapObject = null
	var best_distance := INF
	for object in MapObject.all_objects:
		if object.owner_index == team and resource in object.accepts:
			var distance := position.distance_to(object.position)
			if distance < best_distance:
				best = object
				best_distance = distance
	return best


## Closest point of a target: a unit's feet, or the nearest edge of a building's footprint.
func _aim_point(node: Node2D) -> Vector2:
	if node is MapObject:
		var rect: Rect2 = node.work_rect()
		return Vector2(clampf(position.x, rect.position.x, rect.end.x), clampf(position.y, rect.position.y, rect.end.y))
	return node.position


## Nearest enemy unit in sight, else nearest enemy building.
func _nearest_target(radius: float) -> Node2D:
	var unit := _nearest_enemy(radius)
	if unit:
		return unit
	var best: MapObject = null
	var best_distance := radius
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index > 0 and object.owner_index != team and object.is_alive():
			var distance := position.distance_to(_aim_point(object))
			if distance < best_distance:
				best = object
				best_distance = distance
	return best


func _nearest_enemy(radius: float) -> Unit:
	var best: Unit = null
	var best_distance := radius
	for other in all_units:
		if other.is_alive() and is_enemy_of(other):
			var distance := position.distance_to(other.position)
			if distance < best_distance:
				best = other
				best_distance = distance
	return best


func _find_path(destination: Vector2) -> PackedVector2Array:
	if NavGrid.current:
		return NavGrid.current.find_path(position, destination)
	return PackedVector2Array([destination])


func _follow_path(delta: float) -> void:
	if path.is_empty():
		return
	var to_point := path[0] - position
	var step := move_speed() * delta
	if to_point.length() <= maxf(step, ARRIVE_DISTANCE):
		position = path[0]
		path.remove_at(0)
	else:
		face(to_point)
		position += to_point.normalized() * step


## Idle units drift apart so groups don't stand inside each other.
func _separate(delta: float) -> void:
	var push := Vector2.ZERO
	for other in all_units:
		if other == self or not other.is_alive():
			continue
		var offset := position - other.position
		var distance := offset.length()
		if distance < SEPARATION_RADIUS and distance > 0.01:
			push += offset / distance * (SEPARATION_RADIUS - distance)
	if push != Vector2.ZERO:
		var next := position + push.limit_length(20.0) * delta * 3.0
		if NavGrid.current == null or NavGrid.current.is_walkable(NavGrid.current.cell_of(next)):
			position = next


func face(vector: Vector2) -> void:
	if vector.length_squared() > 0.01:
		direction = posmod(roundi((rad_to_deg(vector.angle()) - 45.0) / 45.0), 8)


# ------------------------------------------------------------------ animation

func play(action: String) -> void:
	if action == _action:
		return
	var index := unit_type.anim_index(action)
	if index < 0:
		if _anim >= 0:
			return
		index = 0  # e.g. animals without walk/idle sheets: show their first animation
	_action = action
	_start_anim(index)


## Work animations (chopping, building, sowing...) are single swings in the .bob files;
## the original repeats them for as long as the work goes on. True when a swing starts.
func play_repeating(action: String) -> bool:
	if action != _action:
		play(action)
		return _action == action
	if _anim_finished:
		_start_anim(_anim)
		return true
	return false


func _play_index(index: int) -> void:
	_action = "#%d" % index
	_start_anim(index)


func _start_anim(index: int) -> void:
	if unit_type.bob.sub_sprite_is_shadow[unit_type.bob.anims[index].sub_sprite]:
		return
	_anim = index
	_shadow_anim = unit_type.bob.shadow_for(index)
	_step = 0
	_step_time = 0.0
	_anim_finished = false
	_apply_frame()


func _advance(delta: float) -> void:
	var anim := unit_type.bob.anims[_anim]
	_step_time += delta * 1000.0
	while _step_time >= anim.durations_ms[_step]:
		_step_time -= anim.durations_ms[_step]
		if _step + 1 < anim.frames.size():
			_step += 1
		elif anim.loops():
			_step = clampi(anim.frames.size() - anim.loop_back, 0, anim.frames.size() - 1)
			_anim_finished = true  # one full cycle played (attack sequences wait for this)
		else:
			_step_time = 0.0
			_anim_finished = true
			break
	_apply_frame()


func _apply_frame() -> void:
	_set_frame(_body, _anim)
	if _shadow_anim >= 0:
		_set_frame(_shadow, _shadow_anim)


func _set_frame(sprite: Sprite2D, anim_index: int) -> void:
	var anim := unit_type.bob.anims[anim_index]
	var sheet := unit_type.sprite_for(anim_index)
	if sheet == null:
		return
	var dir := direction % anim.directions
	var frame := dir * anim.frames_per_direction + anim.frames[mini(_step, anim.frames.size() - 1)]
	if frame >= sheet.frame_count():
		return
	if sprite.texture != sheet.texture:
		SpriteMaterials.prepare(sprite, sheet)
		if sprite == _body:
			sprite.material = SpriteMaterials.body(sheet, unit_type.palette, unit_type.ramps)
	sheet.apply(sprite, frame)


func _draw() -> void:
	# The selection ring belongs on the ground, under the unit's own sprite.
	if selected and is_alive():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color(1, 1, 1, 0.85), 1.5, true)
		draw_set_transform(Vector2.ZERO)


func _draw_overlay(canvas: Node2D) -> void:
	if debug_paths and not path.is_empty():
		var points := PackedVector2Array([Vector2.ZERO])
		for p in path:
			points.append(p - position)
		canvas.draw_polyline(points, Color(1, 0.9, 0.2, 0.8), 2.0)
	if not is_alive() or inside:
		return
	if selected or health < max_health:
		var bar := Rect2(-12, -58, 24, 3)
		var ratio := health / max_health
		canvas.draw_rect(bar, Color(0.1, 0.1, 0.1, 0.8))
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
				Color(0.85, 0.2, 0.1).lerp(Color(0.3, 0.9, 0.2), ratio))
