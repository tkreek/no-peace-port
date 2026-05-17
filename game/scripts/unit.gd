@tool
extends CharacterBody3D
class_name RTSUnit

@export var unit_role := "worker"
@export var team := "mexican"
@export var display_name := "Frontier Worker"
@export var move_speed := 6.5
@export var acceleration := 18.0
@export var arrive_distance := 0.25
@export var waypoint_arrive_distance := 0.42
@export var navigation_clearance := 1.05
@export var stuck_repath_seconds := 0.85
@export var gather_range := 3.2
@export var deposit_range := 3.6
@export var gather_seconds := 2.0
@export var carry_amount := 10
@export var build_rate := 1.0
@export var separation_radius := 1.15
@export var separation_strength := 3.0
@export var max_health := 100
@export var attack_range := 18.0
@export var attack_damage := 45
@export var attack_cooldown := 2.4
@export_enum("passive", "defensive", "aggressive") var behavior_mode := "defensive"
@export var attack_acquire_range := 18.0
@export var defensive_acquire_range := 9.0
@export var defensive_leash_range := 12.0
@export var visual_scene: PackedScene
@export var sound_profile := {
	"selection": "",
	"movement": "",
	"attack": "",
	"death": "",
	"actions": {
		"building": "res://assets/audio/sfx/build_building.wav",
		"gather_food": "res://assets/audio/sfx/harvest_field.wav",
		"gather_gold": "res://assets/audio/sfx/goldmine.wav",
		"gather_wood": "res://assets/audio/sfx/chop_wood.wav"
	}
}
@export var voice_volume_db := 8.0
@export var voice_unit_size := 14.0
@export var voice_max_distance := 80.0

signal resource_deposited(resource_type: String, amount: int)
signal resource_gathered(resource_node: Node3D)
signal construction_work(site: Node3D, amount: float)
signal cannon_fired(from_position: Vector3, to_position: Vector3)
signal died(unit: Node)

enum WorkerState { IDLE, MOVING, MOVING_TO_RESOURCE, GATHERING, RETURNING_TO_HEADQUARTERS, MOVING_TO_BUILD, BUILDING }

var selected := false:
	set(value):
		var was_selected := selected
		selected = value
		if is_instance_valid(_selection_ring):
			_selection_ring.visible = value
		if value and not was_selected:
			_play_select_voice()

var target_position: Vector3
var health := 100
var _has_target := false
var _route_destination := Vector3.ZERO
var _route_state := WorkerState.IDLE
var _route_waypoints: Array[Vector3] = []
var _route_waypoint_index := 0
var _has_route := false
var _target_is_waypoint := false
var _stuck_timer := 0.0
var _last_progress_position := Vector3.ZERO
var _worker_state := WorkerState.IDLE
var _gather_timer := 0.0
var _attack_timer := 0.0
var _attack_target: Node3D
var _manual_attack_target := false
var _home_position := Vector3.ZERO
var _pending_route_target := Vector3.ZERO
var _pending_route_state := WorkerState.IDLE
var _has_pending_route := false
var _resource_type := ""
var _resource_target: Node3D
var _headquarters: Node3D
var _build_site: Node3D
var _build_slot := Vector3.ZERO
var _resource_slot := Vector3.ZERO
var _deposit_slot := Vector3.ZERO
var _selection_ring: MeshInstance3D
var _carry_pack: MeshInstance3D
var _status_label: Label3D
var _terrain_service: Node
var _sound_players := {}

func _ready() -> void:
	health = max_health
	target_position = global_position
	_home_position = global_position
	_terrain_service = _find_terrain_service()
	if team == "enemy":
		add_to_group("enemy_units")
	else:
		add_to_group("units")
	_create_visuals()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	if is_instance_valid(_attack_target):
		_process_attack(delta)
		return
	elif _can_auto_acquire_target():
		_acquire_behavior_target()
		if is_instance_valid(_attack_target):
			_process_attack(delta)
			return

	if _worker_state == WorkerState.BUILDING:
		if is_instance_valid(_build_site):
			velocity = Vector3.ZERO
			move_and_slide()
			emit_signal("construction_work", _build_site, delta * build_rate)
			_set_status("Building")
		else:
			_worker_state = WorkerState.IDLE
			_set_status("")
		return

	if _worker_state == WorkerState.GATHERING:
		_gather_timer -= delta
		if _gather_timer <= 0.0:
			if is_instance_valid(_resource_target):
				emit_signal("resource_gathered", _resource_target)
			_set_carrying(true)
			if is_instance_valid(_headquarters):
				_set_status("Returning")
				_set_move_target(_headquarters.global_position + _deposit_slot, WorkerState.RETURNING_TO_HEADQUARTERS)
			else:
				_worker_state = WorkerState.IDLE
		return

	if _worker_state == WorkerState.MOVING_TO_RESOURCE and is_instance_valid(_resource_target):
		if _flat_distance_to(_resource_target.global_position + _resource_slot) <= arrive_distance + 0.2:
			_begin_gathering()
			return

	if _worker_state == WorkerState.RETURNING_TO_HEADQUARTERS and is_instance_valid(_headquarters):
		if _flat_distance_to(_headquarters.global_position + _deposit_slot) <= arrive_distance + 0.2:
			_deposit_resource()
			return

	if _worker_state == WorkerState.MOVING_TO_BUILD and is_instance_valid(_build_site):
		if _flat_distance_to(_build_site.global_position + _build_slot) <= arrive_distance + 0.2:
			_begin_building()
			return

	if not _has_target:
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
		move_and_slide()
		return

	_move_toward_target(delta)

func move_to(world_position: Vector3) -> void:
	_attack_target = null
	_manual_attack_target = false
	_resource_target = null
	_headquarters = null
	_build_site = null
	_resource_type = ""
	_set_carrying(false)
	_set_status("")
	_play_command_voice()
	_set_move_target(world_position, WorkerState.MOVING)

func gather_from(resource_node: Node3D, headquarters: Node3D, slot_index := 0) -> void:
	if unit_role != "worker":
		return
	if bool(resource_node.get_meta("depleted", false)):
		_set_status("Empty")
		return
	_attack_target = null
	_manual_attack_target = false
	_resource_target = resource_node
	_headquarters = headquarters
	_resource_type = str(resource_node.get_meta("resource_type", "wood"))
	_resource_slot = _slot_offset(slot_index, gather_range)
	_deposit_slot = _slot_offset(slot_index + 3, deposit_range)
	_set_carrying(false)
	_set_status("To %s" % _resource_type.capitalize())
	_play_command_voice()
	_set_move_target(resource_node.global_position + _resource_slot, WorkerState.MOVING_TO_RESOURCE)

func build(site: Node3D, slot_index := 0) -> void:
	if unit_role != "worker":
		return
	_attack_target = null
	_manual_attack_target = false
	_resource_target = null
	_headquarters = null
	_resource_type = ""
	_build_site = site
	_build_slot = _slot_offset(slot_index, 2.8)
	_set_carrying(false)
	_set_status("To build")
	_play_command_voice()
	_set_move_target(site.global_position + _build_slot, WorkerState.MOVING_TO_BUILD)

func attack(target: Node3D) -> void:
	if unit_role in ["worker", "support"]:
		return
	_resource_target = null
	_headquarters = null
	_resource_type = ""
	_set_carrying(false)
	_attack_target = target
	_manual_attack_target = true
	_set_status("Attacking")
	_play_command_voice()

func set_behavior_mode(mode: String) -> void:
	if mode not in ["passive", "defensive", "aggressive"]:
		return
	behavior_mode = mode
	if behavior_mode == "passive" and not _manual_attack_target:
		_attack_target = null
		_set_status("")

func take_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	_set_status("%d/%d" % [health, max_health])
	if health <= 0:
		_play_one_shot_at_parent(_sound_path("death"))
		emit_signal("died", self)
		queue_free()

func _set_move_target(world_position: Vector3, worker_state: WorkerState) -> void:
	if _has_route and _route_state == worker_state and _flat_distance_between(_route_destination, world_position) < 0.25:
		_worker_state = worker_state
		return
	if _terrain_service != null and _terrain_service.has_method("route_target_through_ford"):
		var routed_target: Vector3 = _terrain_service.route_target_through_ford(global_position, world_position)
		if routed_target.distance_squared_to(world_position) > 0.25:
			_begin_route_to(routed_target, WorkerState.MOVING)
			_worker_state = WorkerState.MOVING
			_pending_route_target = world_position
			_pending_route_state = worker_state
			_has_pending_route = true
			return
	_begin_route_to(world_position, worker_state)

func _begin_route_to(world_position: Vector3, worker_state: WorkerState) -> void:
	_route_destination = world_position
	_route_state = worker_state
	_route_waypoints = _build_obstacle_route(global_position, world_position)
	_route_waypoint_index = 0
	_has_route = true
	_stuck_timer = 0.0
	_last_progress_position = global_position
	_worker_state = worker_state
	_advance_to_next_route_point()

func _advance_to_next_route_point() -> void:
	if _route_waypoint_index < _route_waypoints.size():
		target_position = _route_waypoints[_route_waypoint_index]
		_route_waypoint_index += 1
		_target_is_waypoint = true
	else:
		target_position = _route_destination
		_target_is_waypoint = false
	_has_target = true

func _move_toward_target(delta: float) -> void:
	var to_target := target_position - global_position
	to_target.y = 0.0
	var target_arrive_distance := arrive_distance
	if _is_following_route_waypoint():
		target_arrive_distance = waypoint_arrive_distance
	if to_target.length() <= target_arrive_distance:
		if _is_following_route_waypoint():
			_advance_to_next_route_point()
			return
		_has_target = false
		_has_route = false
		velocity = Vector3.ZERO
		move_and_slide()
		_on_arrived()
		return

	var move_direction := to_target.normalized()
	var desired := (move_direction + _get_separation_vector() * 0.65).normalized() * move_speed
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()
	_update_stuck_repath(delta)

	if velocity.length() > 0.05:
		look_at(global_position + Vector3(velocity.x, 0.0, velocity.z), Vector3.UP)
	global_position.y = _terrain_height_at(global_position)

func _update_stuck_repath(delta: float) -> void:
	if not _has_target or not _has_route:
		return
	var moved := _flat_distance_between(global_position, _last_progress_position)
	if moved >= 0.08:
		_stuck_timer = 0.0
		_last_progress_position = global_position
		return
	if _flat_distance_between(global_position, target_position) <= waypoint_arrive_distance + 0.2:
		return
	_stuck_timer += delta
	if _stuck_timer < stuck_repath_seconds:
		return
	_begin_route_to(_route_destination, _route_state)

func _is_following_route_waypoint() -> bool:
	return _target_is_waypoint

func _build_obstacle_route(from_position: Vector3, to_position: Vector3) -> Array[Vector3]:
	var route: Array[Vector3] = []
	var cursor := from_position
	var destination := to_position
	cursor.y = _terrain_height_at(cursor)
	destination.y = _terrain_height_at(destination)
	var obstacles := _navigation_obstacles()

	for _step in range(6):
		var blocking_obstacle := _first_blocking_obstacle(cursor, destination, obstacles)
		if blocking_obstacle.is_empty():
			break
		var waypoint := _best_waypoint_around_obstacle(cursor, destination, blocking_obstacle, obstacles)
		if waypoint == Vector3.INF or _flat_distance_between(cursor, waypoint) < 0.25:
			break
		waypoint.y = _terrain_height_at(waypoint)
		route.append(waypoint)
		cursor = waypoint

	return route

func _navigation_obstacles() -> Array[Dictionary]:
	var obstacles: Array[Dictionary] = []
	var groups := ["buildings", "resource_nodes", "construction_sites", "terrain_blockers"]
	for group_name in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			var obstacle := node as Node3D
			if obstacle == null or obstacle == self or not is_instance_valid(obstacle):
				continue
			var size := _obstacle_size(obstacle)
			if size.x <= 0.0 or size.z <= 0.0:
				continue
			obstacles.append({
				"node": obstacle,
				"center": obstacle.global_position,
				"half": Vector2(size.x * 0.5 + navigation_clearance, size.z * 0.5 + navigation_clearance)
			})
	return obstacles

func _obstacle_size(obstacle: Node3D) -> Vector3:
	if _has_property(obstacle, "collision_size"):
		return obstacle.get("collision_size")
	if _has_property(obstacle, "size"):
		return obstacle.get("size")
	for child in obstacle.get_children():
		var collision := child as CollisionShape3D
		if collision == null:
			continue
		var box := collision.shape as BoxShape3D
		if box != null:
			return Vector3(
				box.size.x * absf(obstacle.global_basis.get_scale().x),
				box.size.y * absf(obstacle.global_basis.get_scale().y),
				box.size.z * absf(obstacle.global_basis.get_scale().z)
			)
	return Vector3.ZERO

func _has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false

func _first_blocking_obstacle(from_position: Vector3, to_position: Vector3, obstacles: Array[Dictionary]) -> Dictionary:
	var closest := {}
	var closest_distance := INF
	for obstacle in obstacles:
		if _point_inside_obstacle(from_position, obstacle) or _point_inside_obstacle(to_position, obstacle):
			continue
		if not _segment_intersects_obstacle(from_position, to_position, obstacle):
			continue
		var center: Vector3 = obstacle["center"]
		var distance := _flat_distance_between(from_position, center)
		if distance < closest_distance:
			closest_distance = distance
			closest = obstacle
	return closest

func _best_waypoint_around_obstacle(from_position: Vector3, to_position: Vector3, obstacle: Dictionary, obstacles: Array[Dictionary]) -> Vector3:
	var center: Vector3 = obstacle["center"]
	var half: Vector2 = obstacle["half"]
	var extra := maxf(navigation_clearance * 0.65, 0.55)
	var candidates: Array[Vector3] = [
		Vector3(center.x - half.x - extra, 0.0, center.z - half.y - extra),
		Vector3(center.x + half.x + extra, 0.0, center.z - half.y - extra),
		Vector3(center.x - half.x - extra, 0.0, center.z + half.y + extra),
		Vector3(center.x + half.x + extra, 0.0, center.z + half.y + extra),
		Vector3(center.x - half.x - extra, 0.0, to_position.z),
		Vector3(center.x + half.x + extra, 0.0, to_position.z),
		Vector3(to_position.x, 0.0, center.z - half.y - extra),
		Vector3(to_position.x, 0.0, center.z + half.y + extra)
	]

	var best := Vector3.INF
	var best_score := INF
	for candidate in candidates:
		candidate.y = _terrain_height_at(candidate)
		if _point_blocked(candidate, obstacles):
			continue
		if _line_blocked(from_position, candidate, obstacles):
			continue
		var score := _flat_distance_between(from_position, candidate) + _flat_distance_between(candidate, to_position)
		if _line_blocked(candidate, to_position, obstacles):
			score += 8.0
		if score < best_score:
			best_score = score
			best = candidate
	return best

func _line_blocked(from_position: Vector3, to_position: Vector3, obstacles: Array[Dictionary]) -> bool:
	for obstacle in obstacles:
		if _point_inside_obstacle(from_position, obstacle) or _point_inside_obstacle(to_position, obstacle):
			continue
		if _segment_intersects_obstacle(from_position, to_position, obstacle):
			return true
	return false

func _point_blocked(point: Vector3, obstacles: Array[Dictionary]) -> bool:
	for obstacle in obstacles:
		if _point_inside_obstacle(point, obstacle):
			return true
	return false

func _point_inside_obstacle(point: Vector3, obstacle: Dictionary) -> bool:
	var center: Vector3 = obstacle["center"]
	var half: Vector2 = obstacle["half"]
	return point.x >= center.x - half.x \
		and point.x <= center.x + half.x \
		and point.z >= center.z - half.y \
		and point.z <= center.z + half.y

func _segment_intersects_obstacle(from_position: Vector3, to_position: Vector3, obstacle: Dictionary) -> bool:
	var center: Vector3 = obstacle["center"]
	var half: Vector2 = obstacle["half"]
	var min_x := center.x - half.x
	var max_x := center.x + half.x
	var min_z := center.z - half.y
	var max_z := center.z + half.y
	var direction := to_position - from_position
	var t_min := 0.0
	var t_max := 1.0

	if absf(direction.x) < 0.0001:
		if from_position.x < min_x or from_position.x > max_x:
			return false
	else:
		var tx1 := (min_x - from_position.x) / direction.x
		var tx2 := (max_x - from_position.x) / direction.x
		t_min = maxf(t_min, minf(tx1, tx2))
		t_max = minf(t_max, maxf(tx1, tx2))

	if absf(direction.z) < 0.0001:
		if from_position.z < min_z or from_position.z > max_z:
			return false
	else:
		var tz1 := (min_z - from_position.z) / direction.z
		var tz2 := (max_z - from_position.z) / direction.z
		t_min = maxf(t_min, minf(tz1, tz2))
		t_max = minf(t_max, maxf(tz1, tz2))

	return t_max >= t_min and t_max >= 0.0 and t_min <= 1.0

func _process_attack(delta: float) -> void:
	if not is_instance_valid(_attack_target):
		_attack_target = null
		_manual_attack_target = false
		return
	if behavior_mode == "defensive" and not _manual_attack_target and _flat_distance_to(_home_position) > defensive_leash_range:
		_attack_target = null
		_set_move_target(_home_position, WorkerState.MOVING)
		_set_status("Holding")
		return

	var enemy_position := _attack_target.global_position
	var distance := _flat_distance_to(enemy_position)
	if distance > attack_range:
		if behavior_mode == "passive" and not _manual_attack_target:
			_attack_target = null
			return
		if behavior_mode == "defensive" and not _manual_attack_target and enemy_position.distance_to(_home_position) > defensive_leash_range:
			_attack_target = null
			_set_status("Holding")
			return
		var direction := global_position - enemy_position
		direction.y = 0.0
		if direction.length() < 0.01:
			direction = Vector3.FORWARD
		_set_move_target(enemy_position + direction.normalized() * (attack_range * 0.75), WorkerState.MOVING)
		_move_toward_target(delta)
		return

	_has_target = false
	velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
	move_and_slide()
	look_at(Vector3(enemy_position.x, global_position.y, enemy_position.z), Vector3.UP)

	if _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		_play_attack_sound()
		if unit_role == "cannon":
			emit_signal("cannon_fired", global_position + Vector3(0.0, 1.0, 0.0), enemy_position + Vector3(0.0, 0.8, 0.0))
		if _attack_target.has_method("take_damage"):
			_attack_target.take_damage(attack_damage)

func _can_auto_acquire_target() -> bool:
	if unit_role in ["worker", "support"] or attack_damage <= 0 or attack_range <= 0.0:
		return false
	if behavior_mode == "passive":
		return false
	if _worker_state not in [WorkerState.IDLE, WorkerState.MOVING]:
		return false
	return true

func _acquire_behavior_target() -> void:
	var acquire_range := attack_acquire_range
	if behavior_mode == "defensive":
		acquire_range = minf(defensive_acquire_range, attack_acquire_range)
	var target := _find_closest_enemy(acquire_range)
	if target == null:
		return
	_attack_target = target
	_manual_attack_target = false
	_set_status("Guarding" if behavior_mode == "defensive" else "Attacking")

func _find_closest_enemy(max_distance: float) -> Node3D:
	var closest: Node3D
	var closest_distance := max_distance
	for node in get_tree().get_nodes_in_group(_enemy_group_name()):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var distance := _flat_distance_to(enemy.global_position)
		if distance <= closest_distance:
			closest_distance = distance
			closest = enemy
	return closest

func _enemy_group_name() -> String:
	return "units" if team == "enemy" else "enemy_units"

func _on_arrived() -> void:
	if _has_pending_route:
		var final_target := _pending_route_target
		var final_state := _pending_route_state
		_has_pending_route = false
		_set_move_target(final_target, final_state)
		return
	if _worker_state == WorkerState.MOVING_TO_RESOURCE:
		_begin_gathering()
	elif _worker_state == WorkerState.RETURNING_TO_HEADQUARTERS:
		_deposit_resource()
	elif _worker_state == WorkerState.MOVING_TO_BUILD:
		_begin_building()
	else:
		_worker_state = WorkerState.IDLE

func _begin_building() -> void:
	_has_target = false
	velocity = Vector3.ZERO
	_worker_state = WorkerState.BUILDING
	_set_status("Building")
	_play_action_sound("building")

func _begin_gathering() -> void:
	_has_target = false
	velocity = Vector3.ZERO
	_worker_state = WorkerState.GATHERING
	_gather_timer = gather_seconds
	_set_status("Gathering %s" % _resource_type.capitalize())
	_play_action_sound("gather_%s" % _resource_type)

func _deposit_resource() -> void:
	_has_target = false
	velocity = Vector3.ZERO
	emit_signal("resource_deposited", _resource_type, carry_amount)
	_set_carrying(false)
	if is_instance_valid(_resource_target) and not bool(_resource_target.get_meta("depleted", false)):
		_set_status("To %s" % _resource_type.capitalize())
		_set_move_target(_resource_target.global_position + _resource_slot, WorkerState.MOVING_TO_RESOURCE)
	else:
		_worker_state = WorkerState.IDLE
		_set_status("")

func _flat_distance_to(world_position: Vector3) -> float:
	return _flat_distance_between(global_position, world_position)

func _flat_distance_between(from_position: Vector3, to_position: Vector3) -> float:
	var offset := to_position - from_position
	offset.y = 0.0
	return offset.length()

func _slot_offset(slot_index: int, radius: float) -> Vector3:
	var ring_count := 8
	var angle := TAU * float(slot_index % ring_count) / float(ring_count)
	var ring := float(slot_index / ring_count)
	var slot_radius := radius + ring * 1.1
	return Vector3(cos(angle), 0.0, sin(angle)) * slot_radius

func _get_separation_vector() -> Vector3:
	var separation := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Node3D
		if other == null or other == self:
			continue
		var offset := global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 0.001 and distance < separation_radius:
			separation += offset.normalized() * ((separation_radius - distance) / separation_radius)
	return separation * separation_strength

func _create_visuals() -> void:
	if team == "enemy":
		_create_enemy_visuals()
	elif visual_scene != null:
		_create_unit_visuals()
	elif unit_role == "cannon":
		_create_cannon_visuals()
	else:
		_create_unit_visuals()

func _create_unit_visuals() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var is_mounted := unit_role == "cavalry"
	var is_cannon := unit_role == "cannon"
	capsule.radius = 0.48 if is_mounted else 0.35
	capsule.height = 1.95 if is_mounted else 1.5
	if is_cannon:
		capsule.radius = 0.72
		capsule.height = 1.1
	collision.shape = capsule
	collision.position.y = 0.98 if is_mounted else 0.75
	if is_cannon:
		collision.position.y = 0.55
	add_child(collision)

	if visual_scene != null:
		var visual := visual_scene.instantiate() as Node3D
		visual.name = "ModernUnitVisual"
		visual.position = Vector3.ZERO
		add_child(visual)
	else:
		_add_capsule_body(Color(0.20, 0.42, 0.82), Color(0.82, 0.66, 0.48))

	if unit_role == "worker":
		_carry_pack = MeshInstance3D.new()
		var pack_mesh := BoxMesh.new()
		pack_mesh.size = Vector3(0.38, 0.32, 0.24)
		_carry_pack.mesh = pack_mesh
		_carry_pack.position = Vector3(0.0, 1.02, 0.42)
		_carry_pack.material_override = _make_material(Color(0.72, 0.43, 0.18))
		_carry_pack.visible = false
		add_child(_carry_pack)

	_add_selection_ring(0.90 if is_cannon else (0.76 if is_mounted else 0.52))
	_add_status_label(1.75 if is_cannon else (2.65 if is_mounted else 2.15))
	_create_sound_players()

func _create_cannon_visuals() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.7, 1.0, 2.1)
	collision.shape = shape
	collision.position.y = 0.55
	add_child(collision)

	var carriage := MeshInstance3D.new()
	var carriage_mesh := BoxMesh.new()
	carriage_mesh.size = Vector3(1.5, 0.35, 1.7)
	carriage.mesh = carriage_mesh
	carriage.position.y = 0.45
	carriage.material_override = _make_material(Color(0.25, 0.16, 0.08))
	add_child(carriage)

	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.22
	barrel_mesh.bottom_radius = 0.30
	barrel_mesh.height = 2.1
	barrel.mesh = barrel_mesh
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0.0, 0.88, -0.45)
	barrel.material_override = _make_material(Color(0.08, 0.08, 0.075))
	add_child(barrel)

	for x in [-0.72, 0.72]:
		var wheel := MeshInstance3D.new()
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.34
		wheel_mesh.bottom_radius = 0.34
		wheel_mesh.height = 0.18
		wheel.mesh = wheel_mesh
		wheel.rotation_degrees.z = 90.0
		wheel.position = Vector3(x, 0.36, 0.38)
		wheel.material_override = _make_material(Color(0.12, 0.08, 0.04))
		add_child(wheel)

	_add_selection_ring(0.92)
	_add_status_label(1.65)

func _create_enemy_visuals() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.45
	collision.shape = capsule
	collision.position.y = 0.72
	add_child(collision)

	_add_capsule_body(Color(0.55, 0.18, 0.14), Color(0.60, 0.40, 0.27))

	var spear := MeshInstance3D.new()
	var spear_mesh := CylinderMesh.new()
	spear_mesh.top_radius = 0.035
	spear_mesh.bottom_radius = 0.035
	spear_mesh.height = 1.7
	spear.mesh = spear_mesh
	spear.rotation_degrees.z = 24.0
	spear.position = Vector3(0.42, 1.0, 0.0)
	spear.material_override = _make_material(Color(0.25, 0.16, 0.08))
	add_child(spear)

	_add_status_label(2.05)
	_set_status("%d/%d" % [health, max_health])

func _add_capsule_body(body_color: Color, head_color: Color) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.32
	body_mesh.height = 1.25
	body.mesh = body_mesh
	body.position.y = 0.78
	body.material_override = _make_material(body_color)
	add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head.mesh = head_mesh
	head.position.y = 1.58
	head.material_override = _make_material(head_color)
	add_child(head)

func _add_selection_ring(radius: float) -> void:
	_selection_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius
	ring_mesh.outer_radius = radius + 0.08
	_selection_ring.mesh = ring_mesh
	_selection_ring.position.y = 0.04
	_selection_ring.material_override = _make_material(Color(0.96, 0.85, 0.30))
	_selection_ring.visible = false
	add_child(_selection_ring)

func _add_status_label(height: float) -> void:
	_status_label = Label3D.new()
	_status_label.text = ""
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.position = Vector3(0.0, height, 0.0)
	_status_label.font_size = 22
	_status_label.modulate = Color(0.95, 0.89, 0.62)
	add_child(_status_label)

func _set_carrying(value: bool) -> void:
	if is_instance_valid(_carry_pack):
		_carry_pack.visible = value

func _set_status(text: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = text

func _create_sound_players() -> void:
	for slot in ["selection", "movement", "attack", "work"]:
		_create_sound_player(slot)

func _create_sound_player(slot: String) -> void:
	if _sound_players.has(slot):
		return
	var player := _create_spatial_audio_player("%sSound" % slot.capitalize(), _sound_path(slot))
	_sound_players[slot] = player
	add_child(player)

func _create_spatial_audio_player(player_name: String, audio_path: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.volume_db = voice_volume_db
	player.unit_size = voice_unit_size
	player.max_distance = voice_max_distance
	var stream := _load_audio_stream(audio_path)
	if stream != null:
		player.stream = stream
	return player

func _play_select_voice() -> void:
	_play_sound_slot("selection")

func _play_command_voice() -> void:
	_play_sound_slot("movement")

func _play_attack_sound() -> void:
	_play_sound_slot("attack")

func _play_action_sound(action_name: String) -> void:
	var actions: Variant = sound_profile.get("actions", {})
	if not actions is Dictionary:
		return
	var action_sounds := actions as Dictionary
	_play_sound_slot("work", str(action_sounds.get(action_name, "")))

func _play_sound_slot(slot: String, audio_path := "") -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	var path := audio_path if not audio_path.is_empty() else _sound_path(slot)
	if path.is_empty():
		return
	if not _sound_players.has(slot) or not is_instance_valid(_sound_players[slot]):
		_create_sound_player(slot)
	var player := _sound_players[slot] as AudioStreamPlayer3D
	var stream := _load_audio_stream(path)
	if player != null and stream != null:
		player.stream = stream
		player.play()

func _play_one_shot_at_parent(audio_path: String) -> void:
	if not is_inside_tree() or Engine.is_editor_hint() or audio_path.is_empty():
		return
	var stream := _load_audio_stream(audio_path)
	var parent_node := get_parent()
	if stream == null or parent_node == null:
		return
	var player := _create_spatial_audio_player("DeathSound", audio_path)
	player.stream = stream
	player.global_position = global_position
	parent_node.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _sound_path(slot: String) -> String:
	return str(sound_profile.get(slot, ""))

func _load_audio_stream(audio_path: String) -> AudioStream:
	if audio_path.is_empty():
		return null

	if audio_path.get_extension().to_lower() == "wav":
		return AudioStreamWAV.load_from_file(audio_path)

	var imported_stream := load(audio_path) as AudioStream
	if imported_stream != null:
		return imported_stream

	return null

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	return material

func _terrain_height_at(world_position: Vector3) -> float:
	if _terrain_service == null:
		_terrain_service = _find_terrain_service()
	if _terrain_service != null:
		return _terrain_service.height_at(world_position)
	if world_position.z >= -13.0 and world_position.z <= -5.0 and world_position.x >= 8.0 and world_position.x <= 14.0:
		return inverse_lerp(8.0, 14.0, world_position.x) * 2.2
	if world_position.x >= 14.0 and world_position.x <= 45.0 and world_position.z >= -32.0 and world_position.z <= 4.0:
		return 2.2
	return 0.0

func _find_terrain_service() -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("TerrainService")
