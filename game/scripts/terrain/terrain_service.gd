@tool
extends Node
class_name TerrainService

const UPPER_TERRAIN_HEIGHT := 2.2
const UPPER_TERRAIN_MIN_X := 14.0
const UPPER_TERRAIN_MAX_X := 45.0
const UPPER_TERRAIN_MIN_Z := -32.0
const UPPER_TERRAIN_MAX_Z := 4.0
const RAMP_X_START := 8.0
const RAMP_X_END := 14.0
const RAMP_Z_MIN := -13.0
const RAMP_Z_MAX := -5.0
const MEADOW_TERRAIN_TEXTURE := "res://assets/visuals/imported/america0/meadow/graphics/terrain/small_meadow_20.png"
const STEPPE_TERRAIN_TEXTURE := "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe20.png"
const RAMP_TERRAIN_TEXTURE := "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe14.png"
const CLIFF_TERRAIN_TEXTURE := "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe28.png"
const FORD_TERRAIN_TEXTURE := "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe5.png"
const DEFAULT_RIVER_CENTER := Vector3(8.0, 0.03, -8.0)
const DEFAULT_RIVER_ROTATION_DEGREES := -13.0
const DEFAULT_RIVER_WIDTH := 15.0
const DEFAULT_RIVER_LENGTH := 54.0
const DEFAULT_FORD_LENGTH := 9.0
const DEFAULT_FORD_MARGIN := 1.4
const DEFAULT_FORD_CROSSINGS := []
const RIVER_MESH_SEGMENTS := 32

var river_center := DEFAULT_RIVER_CENTER
var river_rotation_degrees := DEFAULT_RIVER_ROTATION_DEGREES
var river_width := DEFAULT_RIVER_WIDTH
var river_length := DEFAULT_RIVER_LENGTH
var ford_length := DEFAULT_FORD_LENGTH
var ford_margin := DEFAULT_FORD_MARGIN
var ford_crossings := DEFAULT_FORD_CROSSINGS.duplicate()
var elevation_provider: Callable
var surface_provider: Callable

func configure_river(config: Dictionary) -> void:
	river_center = _vector_from_array(config.get("center", [DEFAULT_RIVER_CENTER.x, DEFAULT_RIVER_CENTER.y, DEFAULT_RIVER_CENTER.z]), DEFAULT_RIVER_CENTER)
	river_rotation_degrees = float(config.get("rotation_degrees", DEFAULT_RIVER_ROTATION_DEGREES))
	river_width = float(config.get("width", DEFAULT_RIVER_WIDTH))
	river_length = float(config.get("length", DEFAULT_RIVER_LENGTH))
	ford_length = float(config.get("ford_length", DEFAULT_FORD_LENGTH))
	ford_margin = float(config.get("ford_margin", DEFAULT_FORD_MARGIN))
	ford_crossings.clear()
	var raw_crossings: Variant = config.get("ford_crossings", [])
	if typeof(raw_crossings) == TYPE_ARRAY:
		for crossing in raw_crossings:
			ford_crossings.append(_vector_from_array(crossing, DEFAULT_RIVER_CENTER))
	if ford_crossings.is_empty() and not config.has("ford_crossings"):
		ford_crossings = DEFAULT_FORD_CROSSINGS.duplicate()

func with_height(position: Vector3) -> Vector3:
	return Vector3(position.x, height_at(position), position.z)

func height_at(world_position: Vector3) -> float:
	if elevation_provider.is_valid():
		return float(elevation_provider.call(world_position))
	return base_height_at(world_position)

func base_height_at(_world_position: Vector3) -> float:
	return 0.0

func surface_at(world_position: Vector3) -> String:
	if surface_provider.is_valid():
		return str(surface_provider.call(world_position))
	return "land"

func is_on_upper_terrain(world_position: Vector3) -> bool:
	return height_at(world_position) >= 1.1

func is_on_ramp(world_position: Vector3) -> bool:
	return false

func blocks_building(position: Vector3) -> bool:
	if is_water(position) and not is_ford(position):
		return true
	return false

func is_water(world_position: Vector3) -> bool:
	if surface_at(world_position) == "water":
		return true
	var river_position := _to_river_local(world_position)
	return absf(_river_water_x(river_position)) <= _river_half_width_at(river_position.z) \
		and absf(river_position.z) <= river_length * 0.5

func is_ford(world_position: Vector3) -> bool:
	if ford_crossings.is_empty():
		return false
	var river_position := _to_river_local(world_position)
	if absf(_river_water_x(river_position)) > _river_half_width_at(river_position.z) + ford_margin:
		return false
	for crossing in ford_crossings:
		var crossing_local := _to_river_local(crossing)
		if absf(river_position.z - crossing_local.z) <= ford_length * 0.5:
			return true
	return false

func route_target_through_ford(from_position: Vector3, to_position: Vector3) -> Vector3:
	if surface_at(to_position) == "water" and not is_ford(to_position):
		return with_height(from_position)
	if not path_crosses_blocked_water(from_position, to_position):
		return to_position
	if ford_crossings.is_empty():
		return with_height(from_position)
	return nearest_ford_crossing(from_position, to_position)

func path_crosses_blocked_water(from_position: Vector3, to_position: Vector3) -> bool:
	if is_water(to_position) and not is_ford(to_position):
		return true
	if is_ford(from_position) or is_ford(to_position):
		return false
	var from_local := _to_river_local(from_position)
	var to_local := _to_river_local(to_position)
	if absf(from_local.z) > river_length * 0.58 and absf(to_local.z) > river_length * 0.58:
		return false
	var from_river_x := _river_water_x(from_local)
	var to_river_x := _river_water_x(to_local)
	if from_river_x == 0.0 or to_river_x == 0.0:
		return is_water(to_position) and not is_ford(to_position)
	if signf(from_river_x) == signf(to_river_x):
		return false
	var t := -from_river_x / (to_river_x - from_river_x)
	if t < 0.0 or t > 1.0:
		return false
	var crossing_z := lerpf(from_local.z, to_local.z, t)
	if absf(crossing_z) > river_length * 0.5:
		return false
	for crossing in ford_crossings:
		var crossing_local := _to_river_local(crossing)
		if absf(crossing_z - crossing_local.z) <= ford_length * 0.5:
			return false
	return true

func nearest_ford_crossing(from_position: Vector3, to_position := Vector3.INF) -> Vector3:
	if ford_crossings.is_empty():
		return with_height(from_position)
	var best: Vector3 = ford_crossings[0]
	var best_score := INF
	for crossing in ford_crossings:
		var score := from_position.distance_squared_to(crossing)
		if to_position != Vector3.INF:
			score += crossing.distance_squared_to(to_position) * 0.45
		if score < best_score:
			best_score = score
			best = crossing
	return with_height(best)

func create_water_and_fords(parent: Node3D) -> void:
	_create_river(parent)
	for crossing in ford_crossings:
		_create_ford(parent, crossing)

func create_base_terrain(parent: Node3D) -> void:
	_create_terrain_plate(parent, "LowerGround", Vector3(0.0, 0.0, 0.0), Vector2(100.0, 100.0), Color(0.35, 0.55, 0.28), MEADOW_TERRAIN_TEXTURE, 4.0)

func _create_terrain_plate(parent: Node3D, label: String, position: Vector3, size: Vector2, color: Color, texture_path := "", tile_world_size := 6.0) -> void:
	var ground := StaticBody3D.new()
	ground.name = label
	ground.position = position
	ground.add_to_group("ground")
	parent.add_child(ground)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 0.18, size.y)
	collision.shape = shape
	collision.position.y = -0.09
	ground.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = 18
	mesh.subdivide_depth = 18
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_terrain_material(color, texture_path, size, tile_world_size)
	ground.add_child(mesh_instance)

func _create_cliff_wall(parent: Node3D, position: Vector3, length: float) -> void:
	var cliff := StaticBody3D.new()
	cliff.name = "MesaCliff"
	cliff.position = position
	cliff.add_to_group("terrain_blockers")
	parent.add_child(cliff)

	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.9, UPPER_TERRAIN_HEIGHT, length)
	wall.mesh = wall_mesh
	wall.material_override = _make_terrain_material(Color(0.42, 0.36, 0.27), CLIFF_TERRAIN_TEXTURE, Vector2(UPPER_TERRAIN_HEIGHT, length), 5.0)
	cliff.add_child(wall)

func _create_ramp(parent: Node3D, position: Vector3) -> void:
	var ramp := StaticBody3D.new()
	ramp.name = "MesaRamp"
	ramp.position = position
	ramp.rotation_degrees.z = 20.0
	ramp.add_to_group("ground")
	parent.add_child(ramp)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(RAMP_X_END - RAMP_X_START + 0.8, 0.18, RAMP_Z_MAX - RAMP_Z_MIN)
	collision.shape = shape
	ramp.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_terrain_material(Color(0.46, 0.42, 0.26), RAMP_TERRAIN_TEXTURE, Vector2(shape.size.x, shape.size.z), 5.0)
	ramp.add_child(mesh_instance)

func _create_river(parent: Node3D) -> void:
	var river := MeshInstance3D.new()
	river.name = "River"
	river.mesh = _make_river_mesh()
	river.position = river_center
	river.rotation_degrees.y = river_rotation_degrees
	river.material_override = _make_water_material()
	parent.add_child(river)

func _create_ford(parent: Node3D, position: Vector3) -> void:
	var ford := StaticBody3D.new()
	ford.name = "Ford"
	ford.position = with_height(position) + Vector3(0.0, 0.07, 0.0)
	ford.rotation_degrees.y = river_rotation_degrees
	ford.add_to_group("ground")
	ford.add_to_group("fords")
	parent.add_child(ford)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(_river_half_width_at(_to_river_local(position).z) * 2.0 + ford_margin * 2.0, 0.12, ford_length)
	collision.shape = shape
	collision.position.y = -0.04
	ford.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(_river_half_width_at(_to_river_local(position).z) * 2.0 + ford_margin * 2.0, ford_length)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_terrain_material(Color(0.58, 0.48, 0.29), FORD_TERRAIN_TEXTURE, mesh.size, 4.0)
	ford.add_child(mesh_instance)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material

func _make_terrain_material(color: Color, texture_path: String, terrain_size: Vector2, tile_world_size: float) -> StandardMaterial3D:
	var material := _make_material(color)
	if texture_path.is_empty():
		return material
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_warning("Terrain texture could not be loaded: %s" % texture_path)
		return material
	material.albedo_texture = texture
	material.texture_repeat = 1
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var safe_tile_size := maxf(tile_world_size, 0.1)
	material.uv1_scale = Vector3(
		maxf(terrain_size.x / safe_tile_size, 1.0),
		maxf(terrain_size.y / safe_tile_size, 1.0),
		1.0
	)
	return material

func _make_water_material() -> StandardMaterial3D:
	return TerrainService.make_water_material()

static func make_water_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.30, 0.47, 0.86)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.roughness = 0.28
	material.metallic = 0.0
	return material

func _make_river_mesh() -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(RIVER_MESH_SEGMENTS):
		var z0 := lerpf(-river_length * 0.5, river_length * 0.5, float(index) / float(RIVER_MESH_SEGMENTS))
		var z1 := lerpf(-river_length * 0.5, river_length * 0.5, float(index + 1) / float(RIVER_MESH_SEGMENTS))
		var left0 := Vector3(_river_center_offset_at(z0) - _river_half_width_at(z0), 0.0, z0)
		var right0 := Vector3(_river_center_offset_at(z0) + _river_half_width_at(z0), 0.0, z0)
		var left1 := Vector3(_river_center_offset_at(z1) - _river_half_width_at(z1), 0.0, z1)
		var right1 := Vector3(_river_center_offset_at(z1) + _river_half_width_at(z1), 0.0, z1)
		var v0 := float(index) / float(RIVER_MESH_SEGMENTS)
		var v1 := float(index + 1) / float(RIVER_MESH_SEGMENTS)
		_add_river_vertex(surface, left0, Vector2(0.0, v0))
		_add_river_vertex(surface, left1, Vector2(0.0, v1))
		_add_river_vertex(surface, right1, Vector2(1.0, v1))
		_add_river_vertex(surface, left0, Vector2(0.0, v0))
		_add_river_vertex(surface, right1, Vector2(1.0, v1))
		_add_river_vertex(surface, right0, Vector2(1.0, v0))
	surface.generate_normals()
	return surface.commit()

func _add_river_vertex(surface: SurfaceTool, vertex: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(vertex)

func _river_water_x(river_local_position: Vector3) -> float:
	return river_local_position.x - _river_center_offset_at(river_local_position.z)

func _river_half_width_at(river_z: float) -> float:
	var progress := (river_z / maxf(river_length, 0.1)) + 0.5
	var variation := sin(progress * TAU * 1.8 + 0.35) * 0.13 + sin(progress * TAU * 4.2) * 0.05
	return river_width * (0.5 + variation)

func _river_center_offset_at(river_z: float) -> float:
	var progress := (river_z / maxf(river_length, 0.1)) + 0.5
	return sin(progress * TAU * 1.25 - 0.4) * river_width * 0.15

func _to_river_local(world_position: Vector3) -> Vector3:
	var offset := world_position - river_center
	var angle := deg_to_rad(-river_rotation_degrees)
	var cos_angle := cos(angle)
	var sin_angle := sin(angle)
	return Vector3(
		offset.x * cos_angle - offset.z * sin_angle,
		offset.y,
		offset.x * sin_angle + offset.z * cos_angle
	)

func _vector_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() < 3:
		return fallback
	return Vector3(float(array[0]), float(array[1]), float(array[2]))
