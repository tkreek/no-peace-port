class_name Unit
extends Node2D
## A unit drawn with its original 8-direction sprite animations, team palette and shadow.
## Behaviour is a small state machine: idle (auto-engage enemies in sight), moving,
## attacking (chase into range, play the attack animation sequence, deal damage), dead.

signal died(unit: Unit)

enum State { IDLE, MOVING, ATTACKING, GATHERING, BUILDING, DEAD }
enum Gather { TO_SOURCE, WORKING, TO_DROP_OFF }

const ARRIVE_DISTANCE := 3.0
const REPATH_MS := 600
const CORPSE_SECONDS := 20.0
const SEPARATION_RADIUS := 14.0
const SCAN_INTERVAL := 0.4
const WORK_SECONDS := {"wood": 4.0, "gold": 5.0}
const REACH := 20.0

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


func display_name() -> String:
	return unit_type.display_name()


func is_alive() -> bool:
	return state != State.DEAD


func is_enemy_of(other: Unit) -> bool:
	return other.team != team and other.team > 0 and team > 0


# ------------------------------------------------------------------ orders

## Move, fighting any enemy that comes within sight on the way.
func attack_move(destination: Vector2) -> void:
	move_to(destination)
	attack_moving = true


func move_to(destination: Vector2) -> void:
	if not is_alive():
		return
	attack_moving = false
	target = null
	gather_source = null
	inside = false
	_attack_step = -1
	guard_position = destination
	path = _find_path(destination)
	state = State.MOVING if not path.is_empty() else State.IDLE


func attack(enemy: Node2D) -> void:
	if not is_alive() or enemy == null or not enemy.is_alive() or unit_type.attack_anims.is_empty():
		return
	target = enemy
	gather_source = null
	inside = false
	state = State.ATTACKING
	path.clear()


## Walk to a construction site and work on it until it is finished.
func build(site: MapObject) -> void:
	if not is_alive() or site == null or site.complete or unit_type.anim_index("build") < 0:
		return
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
	gather_source = source
	gather_resource = source.resource
	target = null
	state = State.GATHERING
	_gather_phase = Gather.TO_DROP_OFF if carried >= UnitType.CARRY_AMOUNT else Gather.TO_SOURCE
	_route_gather()


func stop() -> void:
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
	if not is_alive():
		return
	health = maxf(0.0, health - amount)
	_overlay.queue_redraw()
	if health <= 0.0:
		_die()
	elif state == State.IDLE and attacker and attacker.is_alive():
		attack(attacker)  # fight back


# ------------------------------------------------------------------ behaviour

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	match state:
		State.IDLE:
			_scan_timer -= delta
			if _scan_timer <= 0.0:
				_scan_timer = SCAN_INTERVAL
				var enemy := _nearest_enemy(unit_type.sight)
				if enemy:
					attack(enemy)
			play("idle")
		State.MOVING:
			if attack_moving:
				_scan_timer -= delta
				if _scan_timer <= 0.0:
					_scan_timer = SCAN_INTERVAL
					var enemy := _nearest_target(unit_type.sight)
					if enemy:
						var resume := guard_position
						attack(enemy)
						guard_position = resume
						return
			_follow_path(delta)
			if path.is_empty():
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


func _update_attack(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		target = null
		if _attack_step < 0:
			# Look for the next enemy nearby before standing down.
			var enemy := _nearest_target(unit_type.sight)
			if enemy:
				target = enemy
			elif position.distance_to(guard_position) > 64.0 and guard_position != Vector2.ZERO:
				attack_move(guard_position)  # carry on to where we were heading
				return
			else:
				state = State.IDLE
				return
	if _attack_step >= 0:
		_continue_attack()
		return
	var to_target := _aim_point(target) - position
	if to_target.length() > unit_type.attack_range:
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
	if target and is_instance_valid(target):
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
	if unit_type.ranged:
		var accuracy := clampf(1.1 - position.distance_to(_aim_point(target)) / (unit_type.attack_range * 1.6), 0.4, 0.95)
		if randf() > accuracy:
			return
	target.take_damage(unit_type.damage, self)


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
	return "carry_" + carrying if carrying != "" else "walk"


func _idle_action() -> String:
	return "carry_%s_idle" % carrying if carrying != "" else "idle"


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
			if gather_source.footprint_rect().grow(REACH).has_point(position) or path.is_empty():
				path.clear()
				_gather_phase = Gather.WORKING
				_work_timer = WORK_SECONDS.get(gather_source.resource, 4.0)
				face(gather_source.position - position)
				if gather_source.resource == "gold":
					inside = true  # workers go inside the mine
		Gather.WORKING:
			_work_timer -= delta
			if gather_source.resource == "wood":
				play("chop")
				if _anim_finished or _step == 0:
					Sound.play_event(unit_type.guid(), Sound.Event.CHOP, position, 900)
			if _work_timer > 0.0:
				return
			var resource := gather_source.resource if _source_valid() else _last_resource()
			var got := gather_source.harvest(UnitType.CARRY_AMOUNT) if _source_valid() else 0
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
			if _drop_off.footprint_rect().grow(REACH).has_point(position) or path.is_empty():
				path.clear()
				var player: Player = Player.by_index.get(team)
				if player and carried > 0:
					player.add(carrying, carried)
				carried = 0
				carrying = ""  # walk back empty-handed
				_gather_phase = Gather.TO_SOURCE
				_route_gather()


func _update_build(delta: float) -> void:
	if build_site == null or not is_instance_valid(build_site) or build_site.complete:
		build_site = null
		state = State.IDLE
		return
	if not build_site.footprint_rect().grow(REACH).has_point(position):
		if path.is_empty():
			path = _find_path(build_site.position)
		_follow_path(delta)
		play(_walk_action())
		if not path.is_empty():
			return
	path.clear()
	face(build_site.footprint_rect().get_center() - position)
	play("build")
	Sound.play_event(build_site.guid, Sound.Event.BUILD, build_site.position, 2500)
	build_site.add_build_work(delta)


func _route_gather() -> void:
	if _gather_phase == Gather.TO_DROP_OFF:
		_drop_off = _nearest_drop_off(carrying)
		path = _find_path(_drop_off.position) if _drop_off else PackedVector2Array()
	elif _source_valid():
		path = _find_path(gather_source.position)


func _source_valid() -> bool:
	return gather_source != null and is_instance_valid(gather_source) and gather_source.resource != "" \
			and gather_source.amount > 0


func _last_resource() -> String:
	if gather_resource != "":
		return gather_resource
	return "wood" if unit_type.can_gather("wood") else "gold"


func _nearest_source(resource: String, max_distance := INF) -> MapObject:
	var best: MapObject = null
	var best_distance := max_distance
	for object in MapObject.all_objects:
		if object.resource == resource and object.amount > 0:
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
		var rect: Rect2 = node.footprint_rect()
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
	var step := unit_type.speed * delta
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
