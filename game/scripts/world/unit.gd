class_name Unit
extends Node2D
## A unit drawn with its original 8-direction sprite animations, team palette and shadow.
## Behaviour is a small state machine: idle (auto-engage enemies in sight), moving,
## attacking (chase into range, play the attack animation sequence, deal damage), dead.

signal died(unit: Unit)

enum State { IDLE, MOVING, ATTACKING, DEAD }

const ARRIVE_DISTANCE := 3.0
const REPATH_MS := 600
const CORPSE_SECONDS := 20.0
const SEPARATION_RADIUS := 14.0
const SCAN_INTERVAL := 0.4

static var debug_paths := false
static var all_units: Array[Unit] = []

var unit_type: UnitType
var team := 1
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var direction := 1  # sprite direction row: 0 = SE, then clockwise (1 = S ... 7 = E)
var max_health := 100.0
var health := 100.0
var path := PackedVector2Array()
var state := State.IDLE
var target: Unit
var guard_position := Vector2.ZERO  # where an idle unit returns after chasing

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

func move_to(destination: Vector2) -> void:
	if not is_alive():
		return
	target = null
	_attack_step = -1
	guard_position = destination
	path = _find_path(destination)
	state = State.MOVING if not path.is_empty() else State.IDLE


func attack(enemy: Unit) -> void:
	if not is_alive() or enemy == null or not enemy.is_alive() or unit_type.attack_anims.is_empty():
		return
	target = enemy
	state = State.ATTACKING
	path.clear()


func stop() -> void:
	path.clear()
	target = null
	_attack_step = -1
	guard_position = position
	if is_alive():
		state = State.IDLE


func take_damage(amount: float, attacker: Unit = null) -> void:
	if not is_alive():
		return
	health = maxf(0.0, health - amount)
	queue_redraw()
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
			_follow_path(delta)
			if path.is_empty():
				state = State.IDLE
			play("walk" if state == State.MOVING else "idle")
		State.ATTACKING:
			_update_attack(delta)
		State.DEAD:
			_corpse_timer += delta
			if _corpse_timer > CORPSE_SECONDS:
				modulate.a = maxf(0.0, 1.0 - (_corpse_timer - CORPSE_SECONDS) / 3.0)
				if modulate.a <= 0.0:
					queue_free()
	if state != State.DEAD:
		_separate(delta)
	if debug_paths:
		queue_redraw()
	_advance(delta)


func _update_attack(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		target = null
		if _attack_step < 0:
			# Look for the next enemy nearby before standing down.
			var enemy := _nearest_enemy(unit_type.sight)
			if enemy:
				target = enemy
			else:
				state = State.IDLE
				return
	if _attack_step >= 0:
		_continue_attack()
		return
	var to_target := target.position - position
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
		face(target.position - position)
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
		var accuracy := clampf(1.1 - position.distance_to(target.position) / (unit_type.attack_range * 1.6), 0.4, 0.95)
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
	if debug_paths and not path.is_empty():
		var points := PackedVector2Array([Vector2.ZERO])
		for p in path:
			points.append(p - position)
		draw_polyline(points, Color(1, 0.9, 0.2, 0.8), 2.0)
	if not is_alive():
		return
	if selected:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color(1, 1, 1, 0.85), 1.5, true)
		draw_set_transform(Vector2.ZERO)
	if selected or health < max_health:
		var bar := Rect2(-12, -58, 24, 3)
		var ratio := health / max_health
		draw_rect(bar, Color(0.1, 0.1, 0.1, 0.8))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
				Color(0.85, 0.2, 0.1).lerp(Color(0.3, 0.9, 0.2), ratio))
