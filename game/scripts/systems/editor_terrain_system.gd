@tool
extends Node
class_name EditorTerrainSystem

const LOW_ELEVATION := 0.0
const HIGH_ELEVATION := 2.2
const RAMP_EDGE_TOLERANCE := 0.6
const RAMP_EDGE_SEARCH_RADIUS := 5.0
const ELEVATION_CELL_SIZE := 2.0
const SURFACE_LAND := "land"
const SURFACE_WATER := "water"

var base_height_provider: Callable
var _terrain_stamp := 0
var _elevation_cells := {}
var _surface_cells := {}

func stamp_terrain(terrain: Node3D) -> void:
	_terrain_stamp += 1
	terrain.set_meta("terrain_stamp", _terrain_stamp)
	_stamp_elevation_from_terrain(terrain)

func clear_terrain(terrain: Node3D) -> void:
	var terrain_kind := str(terrain.get_meta("terrain_kind", ""))
	if terrain_kind not in ["plateau", "ramp"]:
		return
	var terrain_position := _terrain_position(terrain)
	var half_width := float(terrain.get_meta("terrain_width", 0.0)) * 0.5
	var half_depth := float(terrain.get_meta("terrain_depth", 0.0)) * 0.5
	var direction := _terrain_direction(terrain)
	var side := Vector3(-direction.z, 0.0, direction.x)
	for x in _cell_range(terrain_position.x - half_width, terrain_position.x + half_width):
		for z in _cell_range(terrain_position.z - half_depth, terrain_position.z + half_depth):
			var position := Vector3(_cell_center(x), 0.0, _cell_center(z))
			if terrain_kind == "ramp":
				var delta := Vector3(position.x - terrain_position.x, 0.0, position.z - terrain_position.z)
				if absf(delta.dot(direction)) > half_width or absf(delta.dot(side)) > half_depth:
					continue
			var cell_key := _cell_key_from_indices(x, z)
			_elevation_cells.erase(cell_key)
			_surface_cells.erase(cell_key)

func stamp_brush(center: Vector3, radius: float, elevation: float, surface := SURFACE_LAND) -> void:
	for x in _cell_range(center.x - radius, center.x + radius):
		for z in _cell_range(center.z - radius, center.z + radius):
			var cell_position := Vector2(_cell_center(x), _cell_center(z))
			if cell_position.distance_to(Vector2(center.x, center.z)) > radius:
				continue
			var cell_key := _cell_key_from_indices(x, z)
			_elevation_cells[cell_key] = elevation
			_surface_cells[cell_key] = surface

func height_at(world_position: Vector3, include_ramps := true) -> Variant:
	var cell_key := _cell_key(world_position)
	if _elevation_cells.has(cell_key):
		return _elevation_cells[cell_key]
	return _base_height(world_position)

func surface_at(world_position: Vector3) -> String:
	var cell_key := _cell_key(world_position)
	if _surface_cells.has(cell_key):
		return str(_surface_cells[cell_key])
	return SURFACE_LAND

func _legacy_height_at(world_position: Vector3, include_ramps := true) -> Variant:
	var selected_height: Variant = null
	var selected_stamp := -1
	for node in get_tree().get_nodes_in_group("editor_terrain"):
		var terrain := node as Node3D
		if terrain == null or not is_instance_valid(terrain):
			continue
		var terrain_kind := str(terrain.get_meta("terrain_kind", ""))
		if terrain_kind == "ramp" and not include_ramps:
			continue

		var half_width := float(terrain.get_meta("terrain_width", 0.0)) * 0.5
		var half_depth := float(terrain.get_meta("terrain_depth", 0.0)) * 0.5
		var delta := Vector3(world_position.x - terrain.global_position.x, 0.0, world_position.z - terrain.global_position.z)
		var direction := Vector3(float(terrain.get_meta("terrain_direction_x", 1.0)), 0.0, float(terrain.get_meta("terrain_direction_z", 0.0))).normalized()
		if direction.length_squared() <= 0.001:
			direction = Vector3.RIGHT
		var side := Vector3(-direction.z, 0.0, direction.x)
		var local_x := delta.dot(direction)
		var local_z := delta.dot(side)
		if terrain_kind != "ramp":
			local_x = delta.x
			local_z = delta.z
		if absf(local_x) > half_width or absf(local_z) > half_depth:
			continue

		var terrain_stamp := int(terrain.get_meta("terrain_stamp", 0))
		if terrain_stamp < selected_stamp:
			continue
		selected_stamp = terrain_stamp
		if terrain_kind == "ramp":
			var low := float(terrain.get_meta("terrain_low_elevation", LOW_ELEVATION))
			var high := float(terrain.get_meta("terrain_high_elevation", HIGH_ELEVATION))
			selected_height = lerpf(low, high, clampf((local_x + half_width) / maxf(half_width * 2.0, 0.01), 0.0, 1.0))
		else:
			selected_height = float(terrain.get_meta("terrain_elevation", terrain.global_position.y))
	return selected_height

func height_without_ramps(world_position: Vector3) -> float:
	return float(height_at(world_position, false))

func ramp_placement_for(position: Vector3, ramp_length := 5.0) -> Dictionary:
	var cell_result := _cell_edge_placement_for(position, ramp_length * 0.5, RAMP_EDGE_SEARCH_RADIUS)
	if bool(cell_result.get("valid", false)):
		var edge_position: Vector3 = cell_result["edge_position"]
		var direction: Vector3 = cell_result["direction"]
		return {
			"position": edge_position - direction * (ramp_length * 0.5),
			"direction": direction,
			"valid": true
		}

	var best_position := Vector3(position.x, 0.0, position.z)
	var best_direction := Vector3.RIGHT
	var best_distance := INF
	var best_valid := false
	for node in get_tree().get_nodes_in_group("editor_terrain"):
		var terrain := node as Node3D
		if terrain == null or not is_instance_valid(terrain):
			continue
		if str(terrain.get_meta("terrain_kind", "")) != "plateau":
			continue
		var elevation := float(terrain.get_meta("terrain_elevation", LOW_ELEVATION))
		if elevation < (HIGH_ELEVATION + LOW_ELEVATION) * 0.5:
			continue
		var half_width := float(terrain.get_meta("terrain_width", 0.0)) * 0.5
		var half_depth := float(terrain.get_meta("terrain_depth", 0.0)) * 0.5
		var local := Vector3(position.x - terrain.global_position.x, 0.0, position.z - terrain.global_position.z)
		var clamped := Vector3(clampf(local.x, -half_width, half_width), 0.0, clampf(local.z, -half_depth, half_depth))
		var edge_position := Vector3(terrain.global_position.x + clamped.x, 0.0, terrain.global_position.z + clamped.z)
		var distance := Vector2(position.x - edge_position.x, position.z - edge_position.z).length_squared()
		if distance > RAMP_EDGE_TOLERANCE * RAMP_EDGE_TOLERANCE or distance >= best_distance:
			continue
		best_distance = distance
		var edge_distance_x := minf(absf(clamped.x - -half_width), absf(clamped.x - half_width))
		var edge_distance_z := minf(absf(clamped.z - -half_depth), absf(clamped.z - half_depth))
		if edge_distance_x <= edge_distance_z:
			var x_edge_sign := 1.0 if local.x >= 0.0 else -1.0
			best_direction = Vector3(-x_edge_sign, 0.0, 0.0)
			edge_position.x = terrain.global_position.x + (half_width * x_edge_sign)
		else:
			var z_edge_sign := 1.0 if local.z >= 0.0 else -1.0
			best_direction = Vector3(0.0, 0.0, -z_edge_sign)
			edge_position.z = terrain.global_position.z + (half_depth * z_edge_sign)
		best_direction = best_direction.normalized()
		best_position = edge_position - best_direction * (ramp_length * 0.5)
		var low_sample := edge_position - best_direction * (ramp_length + 0.5)
		var high_sample := edge_position + best_direction * 0.5
		var low_height := height_without_ramps(low_sample)
		var high_height := height_without_ramps(high_sample)
		best_valid = low_height < (HIGH_ELEVATION + LOW_ELEVATION) * 0.5 and high_height >= (HIGH_ELEVATION + LOW_ELEVATION) * 0.5
	return {"position": best_position, "direction": best_direction.normalized(), "valid": best_valid}

func cliff_face_placement_for(position: Vector3, face_offset := 0.25) -> Dictionary:
	var cell_result := _cell_edge_placement_for(position, face_offset, RAMP_EDGE_SEARCH_RADIUS)
	if bool(cell_result.get("valid", false)):
		var edge_position: Vector3 = cell_result["edge_position"]
		var direction: Vector3 = cell_result["direction"]
		return {
			"position": edge_position - direction * face_offset,
			"direction": direction,
			"valid": true
		}

	var best_position := Vector3(position.x, 0.0, position.z)
	var best_direction := Vector3.RIGHT
	var best_distance := INF
	var best_valid := false
	for node in get_tree().get_nodes_in_group("editor_terrain"):
		var terrain := node as Node3D
		if terrain == null or not is_instance_valid(terrain):
			continue
		if str(terrain.get_meta("terrain_kind", "")) != "plateau":
			continue
		var elevation := float(terrain.get_meta("terrain_elevation", LOW_ELEVATION))
		if elevation < (HIGH_ELEVATION + LOW_ELEVATION) * 0.5:
			continue
		var half_width := float(terrain.get_meta("terrain_width", 0.0)) * 0.5
		var half_depth := float(terrain.get_meta("terrain_depth", 0.0)) * 0.5
		var local := Vector3(position.x - terrain.global_position.x, 0.0, position.z - terrain.global_position.z)
		var clamped := Vector3(clampf(local.x, -half_width, half_width), 0.0, clampf(local.z, -half_depth, half_depth))
		var edge_position := Vector3(terrain.global_position.x + clamped.x, 0.0, terrain.global_position.z + clamped.z)
		var distance := Vector2(position.x - edge_position.x, position.z - edge_position.z).length_squared()
		if distance > RAMP_EDGE_TOLERANCE * RAMP_EDGE_TOLERANCE or distance >= best_distance:
			continue
		best_distance = distance
		var edge_distance_x := minf(absf(clamped.x - -half_width), absf(clamped.x - half_width))
		var edge_distance_z := minf(absf(clamped.z - -half_depth), absf(clamped.z - half_depth))
		if edge_distance_x <= edge_distance_z:
			var x_edge_sign := 1.0 if local.x >= 0.0 else -1.0
			best_direction = Vector3(-x_edge_sign, 0.0, 0.0)
			edge_position.x = terrain.global_position.x + (half_width * x_edge_sign)
		else:
			var z_edge_sign := 1.0 if local.z >= 0.0 else -1.0
			best_direction = Vector3(0.0, 0.0, -z_edge_sign)
			edge_position.z = terrain.global_position.z + (half_depth * z_edge_sign)
		best_direction = best_direction.normalized()
		best_position = edge_position - best_direction * face_offset
		var low_sample := edge_position - best_direction * 1.0
		var high_sample := edge_position + best_direction * 0.5
		var low_height := height_without_ramps(low_sample)
		var high_height := height_without_ramps(high_sample)
		best_valid = low_height < (HIGH_ELEVATION + LOW_ELEVATION) * 0.5 and high_height >= (HIGH_ELEVATION + LOW_ELEVATION) * 0.5
	return {"position": best_position, "direction": best_direction.normalized(), "valid": best_valid}

func _cell_edge_placement_for(position: Vector3, _offset: float, search_radius: float) -> Dictionary:
	var best_edge := Vector3(position.x, 0.0, position.z)
	var best_direction := Vector3.RIGHT
	var best_distance := INF
	var min_index_x := floori((position.x - search_radius) / ELEVATION_CELL_SIZE)
	var max_index_x := ceili((position.x + search_radius) / ELEVATION_CELL_SIZE)
	var min_index_z := floori((position.z - search_radius) / ELEVATION_CELL_SIZE)
	var max_index_z := ceili((position.z + search_radius) / ELEVATION_CELL_SIZE)
	for x in range(min_index_x, max_index_x + 1):
		for z in range(min_index_z, max_index_z + 1):
			var east_result := _cell_edge_candidate(position, Vector2i(x, z), Vector2i(x + 1, z))
			if bool(east_result.get("valid", false)) and float(east_result.get("distance", INF)) < best_distance:
				best_distance = float(east_result["distance"])
				best_edge = east_result["edge_position"]
				best_direction = east_result["direction"]
			var south_result := _cell_edge_candidate(position, Vector2i(x, z), Vector2i(x, z + 1))
			if bool(south_result.get("valid", false)) and float(south_result.get("distance", INF)) < best_distance:
				best_distance = float(south_result["distance"])
				best_edge = south_result["edge_position"]
				best_direction = south_result["direction"]
	if best_distance == INF:
		return {"position": best_edge, "direction": best_direction, "valid": false}
	return {"edge_position": best_edge, "direction": best_direction.normalized(), "valid": true}

func _cell_edge_candidate(
		position: Vector3,
		a_index: Vector2i,
		b_index: Vector2i
) -> Dictionary:
	var a_position := Vector3(_cell_center(a_index.x), 0.0, _cell_center(a_index.y))
	var b_position := Vector3(_cell_center(b_index.x), 0.0, _cell_center(b_index.y))
	if surface_at(a_position) == SURFACE_WATER or surface_at(b_position) == SURFACE_WATER:
		return {"valid": false}
	var a_height := height_without_ramps(a_position)
	var b_height := height_without_ramps(b_position)
	var threshold := (HIGH_ELEVATION + LOW_ELEVATION) * 0.5
	if absf(a_height - b_height) < threshold:
		return {"valid": false}
	var low_position := a_position if a_height < b_height else b_position
	var high_position := b_position if a_height < b_height else a_position
	if height_without_ramps(low_position) >= threshold or height_without_ramps(high_position) < threshold:
		return {"valid": false}
	var edge_position := (low_position + high_position) * 0.5
	var distance := Vector2(position.x - edge_position.x, position.z - edge_position.z).length_squared()
	return {
		"edge_position": edge_position,
		"direction": (high_position - low_position).normalized(),
		"distance": distance,
		"valid": true
	}

func low_to_high_direction(position: Vector3) -> Vector3:
	var sample_distance := 4.0
	var east := height_without_ramps(position + Vector3(sample_distance, 0.0, 0.0))
	var west := height_without_ramps(position + Vector3(-sample_distance, 0.0, 0.0))
	var south := height_without_ramps(position + Vector3(0.0, 0.0, sample_distance))
	var north := height_without_ramps(position + Vector3(0.0, 0.0, -sample_distance))
	var x_delta := east - west
	var z_delta := south - north
	if absf(x_delta) >= absf(z_delta) and absf(x_delta) > 0.1:
		return Vector3.RIGHT if x_delta > 0.0 else Vector3.LEFT
	if absf(z_delta) > 0.1:
		return Vector3.BACK if z_delta > 0.0 else Vector3.FORWARD
	return Vector3.RIGHT

func _base_height(world_position: Vector3) -> float:
	if base_height_provider.is_valid():
		return float(base_height_provider.call(world_position))
	return LOW_ELEVATION

func _stamp_elevation_from_terrain(terrain: Node3D) -> void:
	var terrain_kind := str(terrain.get_meta("terrain_kind", ""))
	if terrain_kind not in ["plateau", "ramp"]:
		return
	var terrain_position := _terrain_position(terrain)
	var half_width := float(terrain.get_meta("terrain_width", 0.0)) * 0.5
	var half_depth := float(terrain.get_meta("terrain_depth", 0.0)) * 0.5
	if half_width <= 0.0 or half_depth <= 0.0:
		return
	var direction := _terrain_direction(terrain)
	var side := Vector3(-direction.z, 0.0, direction.x)
	for x in _cell_range(terrain_position.x - half_width, terrain_position.x + half_width):
		for z in _cell_range(terrain_position.z - half_depth, terrain_position.z + half_depth):
			var position := Vector3(_cell_center(x), 0.0, _cell_center(z))
			var height := float(terrain.get_meta("terrain_elevation", terrain_position.y))
			if terrain_kind == "ramp":
				var delta := Vector3(position.x - terrain_position.x, 0.0, position.z - terrain_position.z)
				var local_x := delta.dot(direction)
				var local_z := delta.dot(side)
				if absf(local_x) > half_width or absf(local_z) > half_depth:
					continue
				var low := float(terrain.get_meta("terrain_low_elevation", LOW_ELEVATION))
				var high := float(terrain.get_meta("terrain_high_elevation", HIGH_ELEVATION))
				height = lerpf(low, high, clampf((local_x + half_width) / maxf(half_width * 2.0, 0.01), 0.0, 1.0))
			var cell_key := _cell_key_from_indices(x, z)
			_elevation_cells[cell_key] = height
			_surface_cells[cell_key] = str(terrain.get_meta("terrain_surface", SURFACE_LAND))

func _terrain_direction(terrain: Node3D) -> Vector3:
	var direction := Vector3(float(terrain.get_meta("terrain_direction_x", 1.0)), 0.0, float(terrain.get_meta("terrain_direction_z", 0.0))).normalized()
	if direction.length_squared() <= 0.001:
		return Vector3.RIGHT
	return direction

func _terrain_position(terrain: Node3D) -> Vector3:
	return terrain.global_position if terrain.is_inside_tree() else terrain.position

func _cell_key(position: Vector3) -> String:
	return _cell_key_from_indices(roundi(position.x / ELEVATION_CELL_SIZE), roundi(position.z / ELEVATION_CELL_SIZE))

func _cell_key_from_indices(x: int, z: int) -> String:
	return "%d:%d" % [x, z]

func _cell_center(index: int) -> float:
	return float(index) * ELEVATION_CELL_SIZE

func _cell_range(min_value: float, max_value: float) -> Array[int]:
	var cells: Array[int] = []
	for index in range(floori(min_value / ELEVATION_CELL_SIZE), ceili(max_value / ELEVATION_CELL_SIZE) + 1):
		cells.append(index)
	return cells
