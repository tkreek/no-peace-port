class_name Unit
extends UnitSprite
## A unit on the map. Its behaviour is a small state machine: idle (engaging enemies in
## sight as its stance allows), moving, attacking (chase into range, play the attack
## sequence, deal damage), gathering and building (see UnitWork), quartered (inside a
## fort, tower or boat) and dead.
##
## The rules for particular kinds of unit live in parts: work, riding, animal (horses,
## cattle, meat), magic (spells, healing), stealth, water (boats, swimming) and tepees.
## The orders the interface and the AI give are methods here; they pass the part-specific
## ones on.

signal died(unit: Unit)

enum State { IDLE, MOVING, ATTACKING, GATHERING, BUILDING, DEAD, QUARTERED }
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
const REACH := 20.0
const DEFENSIVE_PURSUIT := 160.0  # how far defensive units chase before returning
const FOLLOW_DISTANCE := 48.0

static var debug_paths := false
static var all_units: Array[Unit] = []

var team := 1
var max_health := 100.0
var health := 100.0
var path := PackedVector2Array()
var state := State.IDLE
var target: Node2D  ## Unit or MapObject being attacked
var attack_moving := false  ## moving, but engage enemies met on the way
var stance := Stance.AGGRESSIVE
var formation := Formation.RELAXED
var follow_target: Unit  ## keep close to this unit until given another order
var quarters: MapObject  ## the building this unit is heading into or sitting in
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

var work: UnitWork
var riding: UnitRiding
var animal: UnitAnimal
var magic: UnitMagic
var stealth: UnitStealth
var water: UnitWater
var tepees: UnitTepees
var _parts: Array[UnitPart] = []  # in the order they get the frame

var _patrol := PackedVector2Array()  ## the two ends of a patrol route
var _ordered := false  ## the current target was picked by the player, not by the stance
var _attack_step := -1  # position in unit_type.attack_anims, -1 = not in an attack
var _cooldown := 0.0
var _scan_timer := randf() * SCAN_INTERVAL
var _last_repath := 0
var _corpse_timer := 0.0


func setup(type: UnitType, team_index: int) -> void:
	team = team_index
	_setup_sprites(type, team)
	max_health = type.health
	health = max_health
	refresh_upgrades.call_deferred()
	guard_position = position
	work = UnitWork.new(self)
	riding = UnitRiding.new(self)
	animal = UnitAnimal.new(self)
	magic = UnitMagic.new(self)
	stealth = UnitStealth.new(self)
	water = UnitWater.new(self)
	tepees = UnitTepees.new(self)
	_parts = [riding, animal, magic, work, tepees, water, stealth]
	all_units.append(self)
	play("idle")


func _exit_tree() -> void:
	all_units.erase(self)


func is_alive() -> bool:
	return state != State.DEAD


func display_name() -> String:
	return unit_type.display_name()


func _variant(action: String) -> String:
	return water.variant(action) if water else action


# ------------------------------------------------------------------ condition and stats

## Researched upgrades of this unit's player (see Player.bonus).
func bonus(effect: String) -> float:
	var player: Player = Player.by_index.get(team)
	return player.bonus(unit_type.guid(), effect, unit_type.mounted) if player else 0.0


## Re-apply life-energy upgrades, keeping the current health ratio.
func refresh_upgrades() -> void:
	if not is_alive():
		return
	var ratio := health / max_health if max_health > 0 else 1.0
	max_health = unit_type.health * (1.0 + bonus("health_pct") / 100.0)
	health = max_health * ratio
	_overlay.queue_redraw()


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	_overlay.queue_redraw()


func attack_damage() -> float:
	return (unit_type.damage + bonus("attack")) * morale() * effectiveness()


func attack_range() -> float:
	return unit_type.attack_range * (1.0 + bonus("range_pct") / 100.0)


func sight() -> float:
	return unit_type.sight * (1.0 + bonus("sight_pct") / 100.0)


func move_speed() -> float:
	var tiers := int(bonus("speed_tiers"))
	if tiers == 0:
		return unit_type.speed
	var tier := int(GameData.stats(unit_type.guid()).get("speed_tier", 2)) + tiers
	return GameData.def_tier("walk_speed", mini(tier, 5), 100) * 0.6


## Experience (manual 4.4): from 0%, earned by doing the job well (kills for fighters,
## loads delivered for workers); it makes a unit up to a fifth more effective.
const EXPERIENCE_PER_KILL := 0.1
const EXPERIENCE_PER_LOAD := 0.01
var experience := 0.0


func gain_experience(amount_gained: float) -> void:
	experience = minf(1.0, experience + amount_gained)


func effectiveness() -> float:
	return 1.0 + 0.2 * experience


## Spear fighters and whip crackers are "very effective against mounted units"; flaming
## arrows, dynamite and cannon fire set about buildings, which bullets and blades barely dent.
const ANTI_CAVALRY := [162, 363]
const BUILDING_BREAKERS := [154, 158, 159, 276, 277, 265, 465, 359, 468]


func damage_factor(against: Node2D) -> float:
	var me := unit_type.guid()
	if against is MapObject:
		return 3.0 if me in BUILDING_BREAKERS else 0.5
	if against is Unit and against.unit_type.mounted and me in ANTI_CAVALRY:
		return 2.0
	return 1.0


## Morale (manual 4.4): 80% .. 120%. The leader's falls the further he is from the main
## building; everyone else's depends on how close the leader is, and drops to 80% when he
## is dead. It scales fighting and working alike.
const MORALE_MIN := 0.8
const MORALE_MAX := 1.2
const LEADER_REACH := 1200.0  # beyond this the leader's presence no longer helps
const HOME_REACH := 2400.0  # the leader's own morale is lowest this far from home
var _morale := 1.0
var _morale_timer := 0.0


func morale() -> float:
	if team <= 0:
		return 1.0
	var now := Time.get_ticks_msec() / 1000.0
	if now - _morale_timer < 0.5:
		return _morale
	_morale_timer = now
	var player: Player = Player.by_index.get(team)
	if player == null:
		return 1.0
	var leader := player.leader()
	if leader == null:
		_morale = MORALE_MIN
	elif leader == self:
		var home := player.main_building()
		var away := position.distance_to(home.position) if home else HOME_REACH
		_morale = lerpf(MORALE_MAX, MORALE_MIN, clampf(away / HOME_REACH, 0.0, 1.0))
	else:
		var closeness := 1.0 - clampf(position.distance_to(leader.position) / LEADER_REACH, 0.0, 1.0)
		_morale = MORALE_MIN + (leader.morale() - MORALE_MIN) * closeness
	return _morale


## Native Americans heal over time with herb blends; outlaws once Self-healing is researched.
const SELF_HEALING_UPGRADE := 957
const SELF_HEAL_PER_SECOND := 0.6
var _heal_timer := 0.0


func _self_heal(delta: float) -> void:
	_heal_timer -= delta
	if _heal_timer > 0.0 or health >= max_health or team <= 0:
		return
	_heal_timer = 1.0
	var player: Player = Player.by_index.get(team)
	if player and (player.faction == "ind" or (player.faction == "des" and player.researched.has(SELF_HEALING_UPGRADE))):
		heal(SELF_HEAL_PER_SECOND)


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
			return position.distance_to(aim_point(enemy)) <= attack_range()
	return true


func is_enemy_of(other: Unit) -> bool:
	if other.team == team or other.team <= 0 or team <= 0:
		return false
	var other_player: Player = Player.by_index.get(other.team)
	if other_player and other_player.surrendered:
		return false  # laid down their arms
	if other.state == State.QUARTERED:
		return false  # out of reach behind the walls
	if other.stealth.concealed and not other.stealth.detected_by(team):
		return false
	return true


## The unit now belongs to another people (a stolen wagon, a converted soldier).
func change_team(new_team: int) -> void:
	stop()
	selected = false
	team = new_team
	set_palette_row(team)
	flash(Color(1.0, 0.9, 0.4))


# ------------------------------------------------------------------ orders

func move_to(destination: Vector2, keep_orders := false) -> void:
	if not is_alive():
		return
	if not keep_orders:
		clear_orders()
	animal.clear_orders()
	attack_moving = false
	target = null
	work.gather_source = null
	inside = false
	_attack_step = -1
	guard_position = destination
	path = find_path(destination)
	state = State.MOVING if not path.is_empty() else State.IDLE


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


## Fight `enemy`. `ordered` when the player gave the order (ignores the stance's limits).
func attack(enemy: Node2D, ordered := false) -> void:
	if not is_alive() or enemy == null or not enemy.is_alive() or unit_type.attack_anims.is_empty() \
			or not water.can_fight_here():
		return
	if state != State.ATTACKING:
		guard_position = position if state != State.MOVING else guard_position
	_ordered = ordered
	if ordered:
		clear_orders()
	work.hunting = false
	riding.aim_at_horse = false
	target = enemy
	work.gather_source = null
	inside = false
	state = State.ATTACKING
	path.clear()


func stop() -> void:
	clear_orders()
	path.clear()
	target = null
	work.stop()
	inside = false
	_attack_step = -1
	guard_position = position
	if is_alive():
		state = State.IDLE


## Any new order cancels what the parts were doing (pursuits, casting, boarding...).
func clear_orders() -> void:
	for part in _parts:
		part.clear_orders()
	_patrol.clear()
	follow_target = null
	if state != State.QUARTERED:
		quarters = null


# Orders the parts carry out (see each part).
func gather(source: MapObject) -> void:
	work.gather(source)


func haul(warehouse: MapObject) -> void:
	work.haul(warehouse)


func build(site: MapObject) -> void:
	work.build(site)


func hunt(prey: Unit) -> void:
	work.hunt(prey)


func rob(building: MapObject) -> void:
	work.rob(building)


func steal(vehicle: Unit) -> void:
	work.steal(vehicle)


func mount(horse: Unit) -> void:
	riding.mount(horse)


func dismount() -> void:
	riding.dismount()


func cast(spell: int, point: Vector2, on_unit: Unit = null) -> void:
	magic.cast(spell, point, on_unit)


func conceal() -> void:
	stealth.conceal()


func board(boat: Unit) -> void:
	water.board(boat)


func unload_at(point: Vector2) -> void:
	water.unload_at(point)


func pack(tepee: MapObject) -> void:
	tepees.pack(tepee)


func unpack(site: MapObject) -> void:
	tepees.unpack(site)


# ------------------------------------------------------------------ quarters

## Walk to one of our buildings with room (fort, tower) and take quarters inside.
func take_quarters(building: MapObject) -> void:
	if not is_alive() or building == null or not building.defence.has_room_for(self):
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


## A shot from inside quarters or a boat: no animation (the unit is out of sight), just the report.
func fire_from_quarters(enemy: Node2D, from: Vector2) -> void:
	_cooldown = unit_type.reload_ms / 1000.0
	Sound.play_event(unit_type.guid(), Sound.Event.SHOOT, from, 60)
	var accuracy := clampf(1.1 - from.distance_to(enemy.position) / ((attack_range() + 60.0) * 1.6), 0.4, 0.95)
	if randf() <= accuracy:
		enemy.take_damage(attack_damage(), self)


# ------------------------------------------------------------------ damage

## `horse_too`: the blow takes the horse with the rider (cannon fire, dynamite, pitfalls).
func take_damage(amount: float, attacker: Node2D = null, horse_too := false) -> void:
	if not is_alive() or state == State.QUARTERED:
		return
	if magic.shield_time > 0.0:
		amount *= 0.5  # the medicine man's protective shield
	health = maxf(0.0, health - amount)
	_overlay.queue_redraw()
	if health <= 0.0:
		if attacker is Unit and is_instance_valid(attacker) and team > 0:
			attacker.gain_experience(EXPERIENCE_PER_KILL)
			var victor: Player = Player.by_index.get(attacker.team)
			if victor:
				victor.stats.kills += 1
		if not horse_too and riding.shot_from_saddle():
			return
		die()
	elif state == State.IDLE and attacker and attacker.is_alive() and _may_engage(attacker):
		attack(attacker)  # fight back


## Damage this unit's blow or shot does on arrival: to the mount when told to shoot horses.
func deal_damage(victim: Node2D, damage: float, horse_too := false) -> void:
	if riding.aim_at_horse and victim is Unit and victim.unit_type.mounted and not horse_too:
		victim.riding.hit_horse(damage, self)
	else:
		victim.take_damage(damage, self, horse_too)


func die() -> void:
	if not water.passengers.is_empty():
		water.sink()
	state = State.DEAD
	target = null
	path.clear()
	selected = false
	Sound.play_event(unit_type.guid(), Sound.Event.DIE, position, 0)
	play("die")
	z_index = -1  # corpses lie under the living
	died.emit(self)


# ------------------------------------------------------------------ the frame

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if state == State.QUARTERED:
		return
	if quarters != null and (state == State.MOVING or state == State.IDLE) and is_instance_valid(quarters) \
			and quarters.work_rect().grow(REACH * 2.0).has_point(position):
		if not quarters.defence.enter(self):
			quarters = null
			stop()
		return
	_fade_flash(delta)
	for part in _parts:
		if part.busy and part.update(delta):
			if state != State.QUARTERED:
				_advance(delta)
			return
	if follow_target != null and (state == State.IDLE or state == State.MOVING):
		_update_follow()
	match state:
		State.IDLE:
			_scan_timer -= delta
			if _scan_timer <= 0.0:
				_scan_timer = SCAN_INTERVAL
				if magic.is_healer():
					magic.look_for_wounded()
				else:
					var enemy := nearest_enemy(_engage_radius())
					if enemy:
						attack(enemy)
			play("idle")
		State.MOVING:
			if attack_moving:
				_scan_timer -= delta
				if _scan_timer <= 0.0:
					_scan_timer = SCAN_INTERVAL
					var enemy := nearest_target(sight()) if water.can_fight_here() else null
					if enemy:
						var resume := guard_position
						attack(enemy)
						guard_position = resume
						return
			follow_path(delta)
			if path.is_empty() and _patrol.size() == 2:
				# Turn round at the end of the route.
				var back := _patrol[0] if position.distance_to(_patrol[1]) < position.distance_to(_patrol[0]) else _patrol[1]
				attack_move(back, true)
			elif path.is_empty():
				state = State.IDLE
				attack_moving = false
			play(work.walk_action() if state == State.MOVING else work.idle_action())
		State.GATHERING:
			work.update_gathering(delta)
		State.BUILDING:
			work.update_building(delta)
		State.ATTACKING:
			_update_attack(delta)
		State.DEAD:
			_corpse_timer += delta
			var lasts := animal.corpse_seconds()
			if _corpse_timer > lasts:
				modulate.a = maxf(0.0, 1.0 - (_corpse_timer - lasts) / 3.0)
				if modulate.a <= 0.0:
					queue_free()
	if state != State.DEAD and not inside:
		_separate(delta)
	if state != State.DEAD:
		_self_heal(delta)
	if debug_paths:
		_overlay.queue_redraw()
	_advance(delta)


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
		path = find_path(follow_target.position)
		state = State.MOVING if not path.is_empty() else State.IDLE


# ------------------------------------------------------------------ combat

func _update_attack(delta: float) -> void:
	if _attack_step < 0 and not water.can_fight_here():
		target = null
		state = State.IDLE
		return
	if work.hunting and is_instance_valid(target) and target is Unit and not target.is_alive() and _attack_step < 0:
		work.butcher(target, delta)
		return
	if target == null or not is_instance_valid(target) or not target.is_alive():
		target = null
		if work.hunting and _attack_step < 0:
			var prey := work.nearest_animal()  # someone else took this carcass
			if prey:
				work.hunt(prey)
			else:
				stop()
			return
		if _attack_step < 0:
			# Look for the next enemy nearby before standing down.
			var enemy := nearest_target(_engage_radius())
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
	var to_target := aim_point(target) - position
	# Cannons cannot fire point-blank: roll back out to their minimum range first.
	if unit_type.min_range > 0.0 and unit_type.attack_range >= 350.0 and to_target.length() < unit_type.min_range:
		if path.is_empty():
			path = find_path(position - to_target.normalized() * (unit_type.min_range - to_target.length() + 30.0))
		follow_path(delta)
		face(-to_target)
		play("walk")
		return
	if to_target.length() > attack_range() and not _ordered and not work.hunting:
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
			path = find_path(target.position)
		follow_path(delta)
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
		face(aim_point(target) - position)
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
		var accuracy := clampf(1.1 - position.distance_to(aim_point(target)) / (attack_range() * 1.6), 0.4, 0.95)
		hit = randf() <= accuracy
	var damage := attack_damage() * damage_factor(target)
	if unit_type.ranged and unit_type.projectile_anim >= 0:
		Projectile.launch(self, target, damage, hit)  # damage lands with it
	elif hit:
		deal_damage(target, damage)


## Closest point of a target: a unit's feet, or the nearest edge of a building's footprint.
func aim_point(node: Node2D) -> Vector2:
	if node is MapObject:
		var rect: Rect2 = node.work_rect()
		return Vector2(clampf(position.x, rect.position.x, rect.end.x), clampf(position.y, rect.position.y, rect.end.y))
	return node.position


## Nearest enemy unit in sight, else nearest enemy building (traps only if a detector sees them).
func nearest_target(radius: float) -> Node2D:
	var unit := nearest_enemy(radius)
	if unit:
		return unit
	var best: MapObject = null
	var best_distance := radius
	for object in MapObject.structures:
		if object.is_building() and object.owner_index > 0 and object.owner_index != team and object.is_alive() \
				and not (object.is_trap() and not UnitStealth.detected(object.position, team)):
			var distance := position.distance_to(aim_point(object))
			if distance < best_distance:
				best = object
				best_distance = distance
	return best


func nearest_enemy(radius: float) -> Unit:
	var best: Unit = null
	var best_distance := radius
	for other: Unit in UnitGrid.near(position, radius):
		if other.is_alive() and is_enemy_of(other):
			var distance := position.distance_to(other.position)
			if distance < best_distance:
				best = other
				best_distance = distance
	return best


# ------------------------------------------------------------------ movement

func find_path(destination: Vector2) -> PackedVector2Array:
	if NavGrid.current:
		return NavGrid.current.find_path(position, destination, water.nav_layer() if NavGrid.current.has_water else NavGrid.Layer.GROUND)
	return PackedVector2Array([destination])


func follow_path(delta: float) -> void:
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
	for other: Unit in UnitGrid.near(position, SEPARATION_RADIUS):
		if other == self or not other.is_alive():
			continue
		var offset := position - other.position
		var distance := offset.length()
		if distance < SEPARATION_RADIUS and distance > 0.01:
			push += offset / distance * (SEPARATION_RADIUS - distance)
	if push != Vector2.ZERO:
		var next := position + push.limit_length(20.0) * delta * 3.0
		if NavGrid.current == null or NavGrid.current.is_walkable(NavGrid.current.cell_of(next), water.nav_layer()):
			position = next


# ------------------------------------------------------------------ drawing

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
		if selected and team > 0:
			# Morale below the energy (manual 4.4): 80% empty .. 120% full, blue.
			var low := bar.position + Vector2(0, 4)
			var level := (morale() - MORALE_MIN) / (MORALE_MAX - MORALE_MIN)
			canvas.draw_rect(Rect2(low, bar.size), Color(0.1, 0.1, 0.1, 0.8))
			canvas.draw_rect(Rect2(low, Vector2(bar.size.x * level, bar.size.y)), Color(0.35, 0.6, 1.0))
