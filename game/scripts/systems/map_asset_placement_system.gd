@tool
extends Node
class_name MapAssetPlacementSystem

const RTSUnitScript := preload("res://scripts/unit.gd")
const EditorTerrainSystemScript := preload("res://scripts/systems/editor_terrain_system.gd")
const MexicanTechTreeScript := preload("res://scripts/data/mexican_tech_tree.gd")
const TerrainServiceScript := preload("res://scripts/terrain/terrain_service.gd")
const EDITOR_RAMP_LENGTH := 5.0
const EDITOR_RAMP_DEPTH := 5.0
const EDITOR_PLATEAU_WIDTH := 10.0
const EDITOR_PLATEAU_DEPTH := 8.0
const SURFACE_LAND := "land"
const SURFACE_WATER := "water"
const PAINT_BRUSH_RADIUS := 2.25
const PAINT_BRUSH_CELL_SIZE := 0.45
const TERRAIN_BRUSH_RADIUS := 4.0
const TERRAIN_BRUSH_CELL_SIZE := 2.0
const TERRAIN_BRUSH_MESH_CELL_SIZE := 1.0
const TREE_BRUSH_RADIUS := 2.4
const TREE_BRUSH_COUNT := 7
const TREE_BRUSH_MIN_SPACING := 0.95
const PAINT_HEIGHT_TOLERANCE := 0.28
const PAINT_SURFACE_OFFSET := 0.05
const BRUSH_TOP_OFFSET := 0.02
const WALL_UV_WORLD_SCALE := 4.0

var world_root: Node3D
var map_editor_system: Node
var editor_terrain_system: Node
var callbacks := {}
var _global_terrain_mesh: MeshInstance3D

func place_asset(asset_id: String, position: Vector3, record_placement := false) -> Dictionary:
	var placed_node: Node3D
	var result := {}
	if is_texture_paint_asset(asset_id):
		placed_node = _paint_terrain_tile(asset_id, position)
	elif is_terrain_brush_asset(asset_id):
		placed_node = _paint_terrain_brush(asset_id, position)
	else:
		match asset_id:
			"terrain_ramp":
				placed_node = _create_editor_ramp(position)
			"single_tree":
				placed_node = _call_node("create_tree", [position])
			"tree_brush":
				placed_node = _paint_tree_brush(position, record_placement)
			"rock":
				placed_node = _call_node("create_rock", [position])
			"gold_mine":
				var mine_transform: Dictionary = editor_terrain_system.cliff_face_placement_for(position)
				if not bool(mine_transform.get("valid", false)):
					return result
				placed_node = _call_node("create_goldmine_resource", [mine_transform["position"]])
				_orient_gold_mine_to_terrain_face(placed_node, mine_transform["direction"])
			"garden":
				placed_node = _call_node("create_garden_resource", [position])
			"worker":
				placed_node = _call_node("create_worker_unit", [position])
			"infantryman", "cavalryman", "militiaman", "gunslinger", "priest":
				placed_node = _call_node("create_mexican_unit", [asset_id, position])
			"enemy":
				placed_node = _call_node("create_enemy_unit", [position])
			"cannon":
				placed_node = _call_node("create_cannon_unit", [position])
			"american_worker":
				placed_node = _create_editor_unit("american", "American Worker", "worker", position, Color(0.42, 0.54, 0.70))
			"american_soldier":
				placed_node = _create_editor_unit("american", "American Soldier", "infantry", position, Color(0.26, 0.42, 0.66))
			"indian_brave":
				placed_node = _create_editor_unit("indian", "Indian Brave", "infantry", position, Color(0.50, 0.32, 0.18))
			"indian_rider":
				placed_node = _create_editor_unit("indian", "Indian Rider", "cavalry", position, Color(0.44, 0.27, 0.13))
			"outlaw_gunslinger":
				placed_node = _create_editor_unit("enemy", "Outlaw Gunslinger", "gunslinger", position, Color(0.68, 0.18, 0.14))
			"outlaw_raider":
				placed_node = _create_editor_unit("enemy", "Outlaw Raider", "infantry", position, Color(0.48, 0.16, 0.12))
			"command_post":
				placed_node = _call_node("create_command_post", [position])
				result["headquarters"] = placed_node
			"weapons_factory":
				placed_node = _call_node("create_completed_building", [asset_id, position])
				result["cannon_factory"] = placed_node
			_:
				if not MexicanTechTreeScript.BUILDINGS.has(asset_id):
					return result
				placed_node = _call_node("create_completed_building", [asset_id, position])

	if placed_node != null:
		placed_node.add_to_group("map_editor_assets")
		if asset_id != "tree_brush":
			placed_node.set_meta("map_asset_id", asset_id)
			placed_node.set_meta("map_asset_position", position)
			if record_placement and map_editor_system != null and map_editor_system.has_method("record_placement"):
				map_editor_system.record_placement(asset_id, position)
		result["node"] = placed_node
	return result

func create_preview(asset_id: String) -> Node3D:
	if is_texture_paint_asset(asset_id) or is_terrain_brush_asset(asset_id):
		return _create_paint_preview(asset_id)
	if asset_id == "tree_brush":
		return _create_tree_brush_preview()

	if MexicanTechTreeScript.BUILDINGS.has(asset_id):
		var preview := _call_node("create_building_preview", [asset_id])
		if preview != null:
			_set_preview_color(preview, Color(0.25, 0.65, 1.0, 0.34))
			return preview

	var root := Node3D.new()
	root.name = "%s Preview" % asset_name(asset_id)
	var color := Color(0.25, 0.65, 1.0, 0.34)
	var footprint_size := Vector3(1.4, 0.08, 1.4)
	var height := 1.2
	if is_texture_paint_asset(asset_id):
		footprint_size = Vector3(PAINT_BRUSH_RADIUS * 2.0, 0.08, PAINT_BRUSH_RADIUS * 2.0)
		height = 0.12
		var paint_color := terrain_paint_color(asset_id)
		color = Color(paint_color.r, paint_color.g, paint_color.b, 0.38)
	else:
		match asset_id:
			"terrain_plateau", "terrain_high_plateau":
				footprint_size = Vector3(10.0, 0.08, 8.0)
				height = 2.2
				color = Color(0.43, 0.55, 0.25, 0.34)
			"terrain_low_plateau":
				footprint_size = Vector3(10.0, 0.08, 8.0)
				height = 0.25
				color = Color(0.35, 0.55, 0.28, 0.34)
			"terrain_water":
				footprint_size = Vector3(10.0, 0.08, 8.0)
				height = 0.12
				color = Color(0.12, 0.36, 0.58, 0.42)
			"terrain_ramp":
				footprint_size = Vector3(EDITOR_RAMP_LENGTH, 0.08, EDITOR_RAMP_DEPTH)
				height = EditorTerrainSystemScript.HIGH_ELEVATION
				color = Color(0.46, 0.42, 0.26, 0.34)
			"single_tree":
				footprint_size = Vector3(1.6, 0.08, 1.6)
				height = 2.4
				color = Color(0.20, 0.65, 0.24, 0.34)
			"gold_mine":
				footprint_size = Vector3(4.8, 0.08, 3.2)
				height = EditorTerrainSystemScript.HIGH_ELEVATION
				color = Color(0.94, 0.72, 0.20, 0.34)
			"garden":
				footprint_size = Vector3(5.4, 0.08, 4.2)
				height = 0.7
				color = Color(0.50, 0.80, 0.24, 0.34)
			"worker", "enemy", "infantryman", "militiaman", "gunslinger", "priest", "american_worker", "american_soldier", "indian_brave", "outlaw_gunslinger", "outlaw_raider":
				footprint_size = Vector3(0.9, 0.08, 0.9)
				height = 1.7
			"cavalryman", "indian_rider":
				footprint_size = Vector3(1.5, 0.08, 1.5)
				height = 2.2
			"cannon":
				footprint_size = Vector3(1.8, 0.08, 2.2)
				height = 1.0
			"command_post":
				footprint_size = Vector3(4.4, 0.08, 3.6)
				height = 2.8
				color = Color(0.78, 0.50, 0.25, 0.34)
			"weapons_factory":
				footprint_size = Vector3(5.0, 0.08, 3.8)
				height = 2.8
				color = Color(0.78, 0.38, 0.20, 0.34)

	var footprint := MeshInstance3D.new()
	var footprint_mesh := BoxMesh.new()
	footprint_mesh.size = footprint_size
	footprint.mesh = footprint_mesh
	footprint.position.y = 0.04
	footprint.material_override = _make_transparent_material(color)
	root.add_child(footprint)

	var marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(footprint_size.x * 0.65, height, footprint_size.z * 0.65)
	marker.mesh = marker_mesh
	marker.position.y = height * 0.5
	marker.material_override = _make_transparent_material(Color(color.r, color.g, color.b, 0.18))
	root.add_child(marker)
	return root

func _create_tree_brush_preview() -> Node3D:
	var root := Node3D.new()
	root.name = "Tree Brush Preview"
	var brush := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = TREE_BRUSH_RADIUS
	mesh.bottom_radius = TREE_BRUSH_RADIUS
	mesh.height = 0.06
	mesh.radial_segments = 32
	brush.mesh = mesh
	brush.position.y = 0.03
	brush.material_override = _make_transparent_material(Color(0.18, 0.55, 0.20, 0.32))
	root.add_child(brush)
	return root

func _create_paint_preview(asset_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "%s Brush Preview" % asset_name(asset_id)
	var color := terrain_paint_color(asset_id)
	var radius := TERRAIN_BRUSH_RADIUS if is_terrain_brush_asset(asset_id) else PAINT_BRUSH_RADIUS
	var brush := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06
	mesh.radial_segments = 32
	brush.mesh = mesh
	brush.position.y = 0.03
	brush.material_override = _make_transparent_material(Color(color.r, color.g, color.b, 0.34))
	root.add_child(brush)
	return root

func preview_position_for(asset_id: String, position: Vector3) -> Dictionary:
	if is_terrain_brush_asset(asset_id):
		var snapped := _snap_to_terrain_grid(position)
		return {"position": _with_terrain_height(snapped), "valid": true}
	if asset_id == "terrain_ramp":
		return editor_terrain_system.ramp_placement_for(position, EDITOR_RAMP_LENGTH)
	if asset_id == "gold_mine":
		return editor_terrain_system.cliff_face_placement_for(position)
	return {"position": _with_terrain_height(position), "valid": true}

func asset_name(asset_id: String) -> String:
	if map_editor_system != null and map_editor_system.has_method("asset_name"):
		var building_names := {}
		for building_type in MexicanTechTreeScript.BUILDINGS.keys():
			building_names[building_type] = MexicanTechTreeScript.BUILDINGS[building_type]["name"]
		return map_editor_system.asset_name(asset_id, building_names)
	if MexicanTechTreeScript.BUILDINGS.has(asset_id):
		return str(MexicanTechTreeScript.BUILDINGS[asset_id]["name"])
	return asset_id.capitalize()

func is_texture_paint_asset(asset_id: String) -> bool:
	return asset_id.begins_with("paint_")

func is_terrain_brush_asset(asset_id: String) -> bool:
	return asset_id in ["terrain_plateau", "terrain_high_plateau", "terrain_low_plateau", "terrain_water"]

func is_brush_asset(asset_id: String) -> bool:
	return is_texture_paint_asset(asset_id) or is_terrain_brush_asset(asset_id)

func _create_terrain_paint_tile(asset_id: String, position: Vector3) -> Node3D:
	var tile := MeshInstance3D.new()
	tile.name = asset_name(asset_id)
	var mesh := _make_paint_brush_mesh(position, PAINT_BRUSH_RADIUS, PAINT_BRUSH_CELL_SIZE)
	if mesh.get_surface_count() == 0:
		return null
	tile.mesh = mesh
	tile.position = _with_terrain_height(position) + Vector3(0.0, PAINT_SURFACE_OFFSET, 0.0)
	tile.material_override = make_terrain_paint_material(asset_id, Vector2(PAINT_BRUSH_RADIUS * 2.0, PAINT_BRUSH_RADIUS * 2.0), true)
	tile.add_to_group("terrain_paint_patches")
	tile.set_meta("paint_key", _terrain_paint_key(position))
	tile.set_meta("paint_radius", PAINT_BRUSH_RADIUS)
	tile.set_meta("paint_asset_id", asset_id)
	tile.set_meta("paint_source_position", position)
	return tile

func _paint_terrain_tile(asset_id: String, position: Vector3) -> Node3D:
	var paint_key := _terrain_paint_key(position)
	for node in get_tree().get_nodes_in_group("terrain_paint_patches"):
		var patch := node as Node3D
		if patch == null:
			continue
		if str(patch.get_meta("paint_key", "")) == paint_key:
			patch.queue_free()
			continue
		var patch_source: Vector3 = patch.get_meta("paint_source_position", patch.global_position)
		if Vector2(patch_source.x - position.x, patch_source.z - position.z).length() <= PAINT_BRUSH_CELL_SIZE * 0.5:
			patch.queue_free()
	var tile := _create_terrain_paint_tile(asset_id, position)
	if tile == null:
		return null
	world_root.add_child(tile)
	return tile

func _paint_terrain_brush(asset_id: String, position: Vector3) -> Node3D:
	var snapped := _snap_to_terrain_grid(position)
	var elevation := EditorTerrainSystemScript.HIGH_ELEVATION if asset_id in ["terrain_plateau", "terrain_high_plateau"] else EditorTerrainSystemScript.LOW_ELEVATION
	var surface := SURFACE_WATER if asset_id == "terrain_water" else SURFACE_LAND
	var paint_records := _extract_overlapping_texture_patches(snapped, TERRAIN_BRUSH_RADIUS)
	if editor_terrain_system != null and editor_terrain_system.has_method("stamp_brush"):
		editor_terrain_system.stamp_brush(snapped, TERRAIN_BRUSH_RADIUS, elevation, surface)
	_rebuild_global_terrain_mesh()
	_reproject_texture_patches(paint_records)
	# Return a lightweight invisible marker so place_asset records the placement
	var marker := Node3D.new()
	marker.name = "TerrainBrushMarker_%s" % asset_id
	marker.position = snapped
	marker.add_to_group("terrain_brush_patches")
	marker.set_meta("paint_radius", TERRAIN_BRUSH_RADIUS)
	marker.set_meta("terrain_asset_id", asset_id)
	marker.set_meta("paint_source_position", snapped)
	marker.set_meta("terrain_elevation", elevation)
	marker.set_meta("terrain_surface", surface)
	world_root.add_child(marker)
	return marker

const GLOBAL_CAP_TILE := 2.0

func _paint_tree_brush(position: Vector3, record_placement: bool) -> Node3D:
	var trees: Array[Node3D] = []
	var attempts := 0
	while trees.size() < TREE_BRUSH_COUNT and attempts < TREE_BRUSH_COUNT * 8:
		attempts += 1
		var angle := randf() * TAU
		var dist := sqrt(randf()) * TREE_BRUSH_RADIUS
		var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var candidate := position + offset
		var too_close := false
		for existing in trees:
			if existing.position.distance_to(candidate) < TREE_BRUSH_MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue
		# Also check existing nearby trees in the scene to keep painting tight but not stacked.
		var nearby_blocked := false
		for node in get_tree().get_nodes_in_group("resource_nodes"):
			var existing_tree := node as Node3D
			if existing_tree == null:
				continue
			if str(existing_tree.get_meta("resource_type", "")) != "wood":
				continue
			if existing_tree.global_position.distance_to(candidate) < TREE_BRUSH_MIN_SPACING:
				nearby_blocked = true
				break
		if nearby_blocked:
			continue
		var tree := _call_node("create_tree", [candidate])
		if tree == null:
			continue
		tree.add_to_group("map_editor_assets")
		tree.set_meta("map_asset_id", "single_tree")
		tree.set_meta("map_asset_position", candidate)
		trees.append(tree)
	if trees.is_empty():
		return null
	# Record each tree as its own placement so save/load preserves them.
	if record_placement and map_editor_system != null and map_editor_system.has_method("record_placement"):
		for tree in trees:
			map_editor_system.record_placement("single_tree", tree.position)
	return trees[0]

func _ensure_global_terrain_mesh() -> void:
	if _global_terrain_mesh != null and is_instance_valid(_global_terrain_mesh):
		return
	if world_root == null:
		return
	_global_terrain_mesh = MeshInstance3D.new()
	_global_terrain_mesh.name = "GlobalEditorTerrain"
	world_root.add_child(_global_terrain_mesh)

func _rebuild_global_terrain_mesh() -> void:
	_ensure_global_terrain_mesh()
	if _global_terrain_mesh == null or editor_terrain_system == null:
		return
	var elev_cells: Dictionary = editor_terrain_system._elevation_cells
	var surface_cells: Dictionary = editor_terrain_system._surface_cells
	var cell_size: float = EditorTerrainSystemScript.ELEVATION_CELL_SIZE
	var half_cell := cell_size * 0.5
	var land_v := PackedVector3Array(); var land_n := PackedVector3Array(); var land_uv := PackedVector2Array(); var land_i := PackedInt32Array()
	var water_v := PackedVector3Array(); var water_n := PackedVector3Array(); var water_uv := PackedVector2Array(); var water_i := PackedInt32Array()
	var wall_v := PackedVector3Array(); var wall_n := PackedVector3Array(); var wall_uv := PackedVector2Array(); var wall_i := PackedInt32Array()
	var bottom_y: float = EditorTerrainSystemScript.LOW_ELEVATION
	for cell_key in elev_cells.keys():
		var parts := str(cell_key).split(":")
		if parts.size() < 2:
			continue
		var ix := int(parts[0])
		var iz := int(parts[1])
		var elevation := float(elev_cells[cell_key])
		var surface := str(surface_cells.get(cell_key, SURFACE_LAND))
		var cx := float(ix) * cell_size
		var cz := float(iz) * cell_size
		var top_y := elevation + BRUSH_TOP_OFFSET
		if surface == SURFACE_WATER:
			_emit_cap_quad(water_v, water_n, water_uv, water_i, cx, cz, half_cell, top_y)
		elif elevation > EditorTerrainSystemScript.LOW_ELEVATION:
			_emit_cap_quad(land_v, land_n, land_uv, land_i, cx, cz, half_cell, top_y)
		if elevation > EditorTerrainSystemScript.LOW_ELEVATION and surface != SURFACE_WATER:
			for delta in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nkey := "%d:%d" % [ix + delta.x, iz + delta.y]
				var n_elev: float = float(elev_cells.get(nkey, EditorTerrainSystemScript.LOW_ELEVATION))
				if n_elev < elevation - 0.001:
					_emit_wall_quad(wall_v, wall_n, wall_uv, wall_i, cx, cz, half_cell, delta, bottom_y, top_y)
	var mesh := ArrayMesh.new()
	_add_surface(mesh, land_v, land_n, land_uv, land_i)
	_add_surface(mesh, water_v, water_n, water_uv, water_i)
	_add_surface(mesh, wall_v, wall_n, wall_uv, wall_i)
	_global_terrain_mesh.mesh = mesh
	var s := 0
	if not land_v.is_empty():
		_global_terrain_mesh.set_surface_override_material(s, _make_opaque_terrain_material(Color(0.56, 0.50, 0.28), terrain_paint_texture_path("paint_steppe"), GLOBAL_CAP_TILE))
		s += 1
	if not water_v.is_empty():
		_global_terrain_mesh.set_surface_override_material(s, _make_water_material())
		s += 1
	if not wall_v.is_empty():
		var wall_mat := _make_opaque_terrain_material(Color(0.55, 0.52, 0.48), terrain_paint_texture_path("paint_cliff"), WALL_UV_WORLD_SCALE)
		wall_mat.roughness = 0.95
		wall_mat.metallic = 0.0
		_global_terrain_mesh.set_surface_override_material(s, wall_mat)

func _add_surface(mesh: ArrayMesh, v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, i: PackedInt32Array) -> void:
	if v.is_empty():
		return
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_INDEX] = i
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)

func _emit_cap_quad(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, i: PackedInt32Array, cx: float, cz: float, half: float, y: float) -> void:
	var base := v.size()
	var min_x := cx - half; var max_x := cx + half
	var min_z := cz - half; var max_z := cz + half
	v.append(Vector3(min_x, y, min_z)); v.append(Vector3(max_x, y, min_z)); v.append(Vector3(max_x, y, max_z)); v.append(Vector3(min_x, y, max_z))
	for _k in range(4):
		n.append(Vector3.UP)
	uv.append(Vector2(min_x, min_z)); uv.append(Vector2(max_x, min_z)); uv.append(Vector2(max_x, max_z)); uv.append(Vector2(min_x, max_z))
	i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

func _emit_wall_quad(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, i: PackedInt32Array, cx: float, cz: float, half: float, delta: Vector2i, bottom: float, top: float) -> void:
	var min_x := cx - half; var max_x := cx + half
	var min_z := cz - half; var max_z := cz + half
	var a: Vector3; var b: Vector3; var c: Vector3; var d: Vector3; var nrm: Vector3
	var u_a: float; var u_b: float
	if delta == Vector2i(-1, 0):
		a = Vector3(min_x, bottom, min_z); b = Vector3(min_x, bottom, max_z); c = Vector3(min_x, top, max_z); d = Vector3(min_x, top, min_z); nrm = Vector3.LEFT
		u_a = min_z; u_b = max_z
	elif delta == Vector2i(1, 0):
		a = Vector3(max_x, bottom, max_z); b = Vector3(max_x, bottom, min_z); c = Vector3(max_x, top, min_z); d = Vector3(max_x, top, max_z); nrm = Vector3.RIGHT
		u_a = max_z; u_b = min_z
	elif delta == Vector2i(0, -1):
		a = Vector3(max_x, bottom, min_z); b = Vector3(min_x, bottom, min_z); c = Vector3(min_x, top, min_z); d = Vector3(max_x, top, min_z); nrm = Vector3.FORWARD
		u_a = max_x; u_b = min_x
	else:
		a = Vector3(min_x, bottom, max_z); b = Vector3(max_x, bottom, max_z); c = Vector3(max_x, top, max_z); d = Vector3(min_x, top, max_z); nrm = Vector3.BACK
		u_a = min_x; u_b = max_x
	var base := v.size()
	v.append(a); v.append(b); v.append(c); v.append(d)
	for _k in range(4):
		n.append(nrm)
	uv.append(Vector2(u_a, bottom)); uv.append(Vector2(u_b, bottom)); uv.append(Vector2(u_b, top)); uv.append(Vector2(u_a, top))
	i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

func _create_terrain_brush_patch(asset_id: String, position: Vector3, elevation: float, surface: String) -> Node3D:
	var mesh := _make_terrain_brush_mesh(position, TERRAIN_BRUSH_RADIUS, TERRAIN_BRUSH_MESH_CELL_SIZE, elevation, surface)
	if mesh.get_surface_count() == 0:
		return null
	var patch := MeshInstance3D.new()
	patch.name = asset_name(asset_id)
	patch.mesh = mesh
	patch.position = Vector3(position.x, 0.0, position.z)
	var top_material: Material = _make_water_material() if surface == SURFACE_WATER else make_terrain_paint_material("paint_steppe" if elevation > EditorTerrainSystemScript.LOW_ELEVATION else "paint_meadow", Vector2(TERRAIN_BRUSH_RADIUS * 2.0, TERRAIN_BRUSH_RADIUS * 2.0), surface == SURFACE_LAND)
	patch.set_surface_override_material(0, top_material)
	if mesh.get_surface_count() > 1:
		var wall_color := Color(0.42, 0.36, 0.27) if surface == SURFACE_LAND else Color(0.18, 0.32, 0.46)
		var wall_texture_path := terrain_paint_texture_path("paint_cliff") if surface == SURFACE_LAND else ""
		patch.set_surface_override_material(1, _make_opaque_terrain_material(wall_color, wall_texture_path, WALL_UV_WORLD_SCALE))
	patch.add_to_group("terrain_brush_patches")
	patch.set_meta("paint_key", _terrain_brush_key(position))
	patch.set_meta("paint_radius", TERRAIN_BRUSH_RADIUS)
	patch.set_meta("terrain_asset_id", asset_id)
	patch.set_meta("paint_source_position", position)
	patch.set_meta("terrain_elevation", elevation)
	patch.set_meta("terrain_surface", surface)
	return patch

func _extract_overlapping_terrain_brush_patches(center: Vector3, radius: float) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("terrain_brush_patches"):
		var patch := node as Node3D
		if patch == null or not _patch_overlaps_circle(patch, center, radius):
			continue
		var terrain_asset_id := str(patch.get_meta("terrain_asset_id", patch.get_meta("map_asset_id", "")))
		if terrain_asset_id.is_empty():
			continue
		records.append({
			"asset_id": terrain_asset_id,
			"position": _patch_source_position(patch),
			"elevation": float(patch.get_meta("terrain_elevation", EditorTerrainSystemScript.LOW_ELEVATION)),
			"surface": str(patch.get_meta("terrain_surface", SURFACE_LAND))
		})
		patch.queue_free()
	return records

func _rebuild_terrain_brush_patches(records: Array[Dictionary]) -> void:
	for record in records:
		var terrain_asset_id := str(record.get("asset_id", ""))
		var source_position: Vector3 = record.get("position", Vector3.ZERO)
		var elevation := float(record.get("elevation", EditorTerrainSystemScript.LOW_ELEVATION))
		var surface := str(record.get("surface", SURFACE_LAND))
		if terrain_asset_id.is_empty():
			continue
		var patch := _create_terrain_brush_patch(terrain_asset_id, source_position, elevation, surface)
		if patch == null:
			continue
		patch.add_to_group("map_editor_assets")
		patch.set_meta("map_asset_id", terrain_asset_id)
		patch.set_meta("map_asset_position", source_position)
		world_root.add_child(patch)

func _extract_overlapping_texture_patches(center: Vector3, radius: float) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("terrain_paint_patches"):
		var patch := node as Node3D
		if patch == null or not _patch_overlaps_circle(patch, center, radius):
			continue
		var paint_asset_id := str(patch.get_meta("paint_asset_id", patch.get_meta("map_asset_id", "")))
		if paint_asset_id.is_empty():
			continue
		var source_position: Vector3 = patch.get_meta("paint_source_position", patch.get_meta("map_asset_position", patch.global_position))
		records.append({"asset_id": paint_asset_id, "position": source_position})
		patch.queue_free()
	return records

func _reproject_texture_patches(records: Array[Dictionary]) -> void:
	for record in records:
		var paint_asset_id := str(record.get("asset_id", ""))
		var source_position: Vector3 = record.get("position", Vector3.ZERO)
		if paint_asset_id.is_empty():
			continue
		if _surface_at(source_position) == SURFACE_WATER:
			continue
		var tile := _create_terrain_paint_tile(paint_asset_id, source_position)
		if tile == null:
			continue
		tile.add_to_group("map_editor_assets")
		tile.set_meta("map_asset_id", paint_asset_id)
		tile.set_meta("map_asset_position", source_position)
		world_root.add_child(tile)

func _patch_overlaps_circle(patch: Node3D, center: Vector3, radius: float) -> bool:
	var patch_radius := float(patch.get_meta("paint_radius", 0.0))
	var patch_position := _patch_source_position(patch)
	var distance := Vector2(patch_position.x - center.x, patch_position.z - center.z).length()
	return distance <= radius + patch_radius

func _patch_source_position(patch: Node3D) -> Vector3:
	if patch.has_meta("paint_source_position"):
		return patch.get_meta("paint_source_position")
	if patch.has_meta("map_asset_position"):
		return patch.get_meta("map_asset_position")
	return patch.global_position

func _terrain_paint_key(position: Vector3) -> String:
	var terrain_height := _with_terrain_height(position).y
	return "%d:%d:%d" % [
		roundi(position.x / PAINT_BRUSH_CELL_SIZE),
		roundi(position.z / PAINT_BRUSH_CELL_SIZE),
		roundi(terrain_height / PAINT_HEIGHT_TOLERANCE)
	]

func _terrain_brush_key(position: Vector3) -> String:
	return "%d:%d" % [
		roundi(position.x / TERRAIN_BRUSH_CELL_SIZE),
		roundi(position.z / TERRAIN_BRUSH_CELL_SIZE)
	]

func _snap_to_terrain_grid(position: Vector3) -> Vector3:
	return Vector3(
		roundf(position.x / TERRAIN_BRUSH_CELL_SIZE) * TERRAIN_BRUSH_CELL_SIZE,
		position.y,
		roundf(position.z / TERRAIN_BRUSH_CELL_SIZE) * TERRAIN_BRUSH_CELL_SIZE
	)

func _make_terrain_brush_mesh(center: Vector3, radius: float, cell_size: float, elevation: float, surface: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var top_vertices := PackedVector3Array()
	var top_normals := PackedVector3Array()
	var top_uvs := PackedVector2Array()
	var top_colors := PackedColorArray()
	var top_indices := PackedInt32Array()
	var wall_vertices := PackedVector3Array()
	var wall_normals := PackedVector3Array()
	var wall_uvs := PackedVector2Array()
	var wall_colors := PackedColorArray()
	var wall_indices := PackedInt32Array()
	var top_y := elevation + BRUSH_TOP_OFFSET
	var bottom_y := EditorTerrainSystemScript.LOW_ELEVATION
	var half_cell := cell_size * 0.5
	var occupied := {}
	var span := ceili(radius / cell_size)
	for x_index in range(-span, span + 1):
		for z_index in range(-span, span + 1):
			var cell_center := Vector2(float(x_index) * cell_size, float(z_index) * cell_size)
			if cell_center.length() > radius:
				continue
			var world_sample := center + Vector3(cell_center.x, 0.0, cell_center.y)
			if not _terrain_cell_matches(world_sample, elevation, surface):
				continue
			occupied["%d:%d" % [x_index, z_index]] = true
			var local_x := cell_center.x - half_cell
			var local_z := cell_center.y - half_cell
			_add_paint_quad(top_vertices, top_normals, top_uvs, top_colors, top_indices, local_x, local_z, cell_size, top_y, radius)
	if elevation > EditorTerrainSystemScript.LOW_ELEVATION:
		for key in occupied.keys():
			var parts := str(key).split(":")
			var x_index := int(parts[0])
			var z_index := int(parts[1])
			var cx := float(x_index) * cell_size
			var cz := float(z_index) * cell_size
			var min_x := cx - half_cell
			var max_x := cx + half_cell
			var min_z := cz - half_cell
			var max_z := cz + half_cell
			if _neighbor_is_lower(center, occupied, x_index - 1, z_index, cell_size, elevation):
				_add_vertical_quad(wall_vertices, wall_normals, wall_uvs, wall_colors, wall_indices, Vector3(min_x, bottom_y, min_z), Vector3(min_x, bottom_y, max_z), Vector3(min_x, top_y, max_z), Vector3(min_x, top_y, min_z), WALL_UV_WORLD_SCALE)
			if _neighbor_is_lower(center, occupied, x_index + 1, z_index, cell_size, elevation):
				_add_vertical_quad(wall_vertices, wall_normals, wall_uvs, wall_colors, wall_indices, Vector3(max_x, bottom_y, max_z), Vector3(max_x, bottom_y, min_z), Vector3(max_x, top_y, min_z), Vector3(max_x, top_y, max_z), WALL_UV_WORLD_SCALE)
			if _neighbor_is_lower(center, occupied, x_index, z_index - 1, cell_size, elevation):
				_add_vertical_quad(wall_vertices, wall_normals, wall_uvs, wall_colors, wall_indices, Vector3(max_x, bottom_y, min_z), Vector3(min_x, bottom_y, min_z), Vector3(min_x, top_y, min_z), Vector3(max_x, top_y, min_z), WALL_UV_WORLD_SCALE)
			if _neighbor_is_lower(center, occupied, x_index, z_index + 1, cell_size, elevation):
				_add_vertical_quad(wall_vertices, wall_normals, wall_uvs, wall_colors, wall_indices, Vector3(min_x, bottom_y, max_z), Vector3(max_x, bottom_y, max_z), Vector3(max_x, top_y, max_z), Vector3(min_x, top_y, max_z), WALL_UV_WORLD_SCALE)
	if not top_vertices.is_empty():
		var top_arrays := []
		top_arrays.resize(Mesh.ARRAY_MAX)
		top_arrays[Mesh.ARRAY_VERTEX] = top_vertices
		top_arrays[Mesh.ARRAY_NORMAL] = top_normals
		top_arrays[Mesh.ARRAY_TEX_UV] = top_uvs
		top_arrays[Mesh.ARRAY_COLOR] = top_colors
		top_arrays[Mesh.ARRAY_INDEX] = top_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, top_arrays)
	if not wall_vertices.is_empty():
		var wall_arrays := []
		wall_arrays.resize(Mesh.ARRAY_MAX)
		wall_arrays[Mesh.ARRAY_VERTEX] = wall_vertices
		wall_arrays[Mesh.ARRAY_NORMAL] = wall_normals
		wall_arrays[Mesh.ARRAY_TEX_UV] = wall_uvs
		wall_arrays[Mesh.ARRAY_COLOR] = wall_colors
		wall_arrays[Mesh.ARRAY_INDEX] = wall_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wall_arrays)
	return mesh

func _neighbor_is_lower(center: Vector3, occupied: Dictionary, x_index: int, z_index: int, cell_size: float, elevation: float) -> bool:
	if occupied.has("%d:%d" % [x_index, z_index]):
		return false
	if editor_terrain_system == null or not editor_terrain_system.has_method("height_at"):
		return true
	var sample := center + Vector3(float(x_index) * cell_size, 0.0, float(z_index) * cell_size)
	var neighbor_height := float(editor_terrain_system.height_at(sample))
	return neighbor_height < elevation - 0.001

func _terrain_cell_matches(world_position: Vector3, elevation: float, surface: String) -> bool:
	if editor_terrain_system == null:
		return true
	var terrain_height := _with_terrain_height(world_position).y
	if absf(terrain_height - elevation) > PAINT_HEIGHT_TOLERANCE:
		return false
	if editor_terrain_system.has_method("surface_at"):
		return str(editor_terrain_system.surface_at(world_position)) == surface
	return true

func _surface_at(world_position: Vector3) -> String:
	if editor_terrain_system != null and editor_terrain_system.has_method("surface_at"):
		return str(editor_terrain_system.surface_at(world_position))
	return SURFACE_LAND

func _add_vertical_quad(
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		uvs: PackedVector2Array,
		colors: PackedColorArray,
		indices: PackedInt32Array,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		uv_world_scale: float
) -> void:
	var base_index := vertices.size()
	var normal := (b - a).cross(c - a).normalized()
	var horiz_origin := Vector2(a.x, a.z)
	var horiz_axis := Vector2(b.x, b.z) - horiz_origin
	var horiz_length := horiz_axis.length()
	if horiz_length <= 0.0001:
		horiz_axis = Vector2.RIGHT
		horiz_length = 1.0
	else:
		horiz_axis = horiz_axis / horiz_length
	for vertex in [a, b, c, d]:
		vertices.append(vertex)
		normals.append(normal)
		var horiz_offset := (Vector2(vertex.x, vertex.z) - horiz_origin).dot(horiz_axis)
		uvs.append(Vector2(horiz_offset / uv_world_scale, vertex.y / uv_world_scale))
		colors.append(Color.WHITE)
	indices.append_array(PackedInt32Array([base_index, base_index + 1, base_index + 2, base_index, base_index + 2, base_index + 3]))

func _make_paint_brush_mesh(center: Vector3, radius: float, cell_size: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var center_on_terrain := _with_terrain_height(center)
	var center_height := center_on_terrain.y
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var steps := ceili((radius * 2.0) / cell_size)
	var start := -steps * cell_size * 0.5
	for x_index in range(steps):
		for z_index in range(steps):
			var local_x := start + float(x_index) * cell_size
			var local_z := start + float(z_index) * cell_size
			var cell_center := Vector2(local_x + cell_size * 0.5, local_z + cell_size * 0.5)
			if cell_center.length() > radius:
				continue
			var world_sample := center + Vector3(cell_center.x, 0.0, cell_center.y)
			if _surface_at(world_sample) == SURFACE_WATER:
				continue
			var sample_height := _with_terrain_height(world_sample).y
			if absf(sample_height - center_height) > PAINT_HEIGHT_TOLERANCE:
				continue
			_add_paint_quad(vertices, normals, uvs, colors, indices, local_x, local_z, cell_size, sample_height - center_height, radius)
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_paint_quad(
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		uvs: PackedVector2Array,
		colors: PackedColorArray,
		indices: PackedInt32Array,
		local_x: float,
		local_z: float,
		cell_size: float,
		local_y: float,
		radius: float
) -> void:
	var base_index := vertices.size()
	var corners := [
		Vector2(local_x, local_z),
		Vector2(local_x + cell_size, local_z),
		Vector2(local_x + cell_size, local_z + cell_size),
		Vector2(local_x, local_z + cell_size)
	]
	for corner in corners:
		var distance_ratio := clampf(corner.length() / radius, 0.0, 1.0)
		var alpha := 1.0 - smoothstep(0.35, 1.0, distance_ratio)
		vertices.append(Vector3(corner.x, local_y, corner.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2((corner.x / (radius * 2.0)) + 0.5, (corner.y / (radius * 2.0)) + 0.5))
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	indices.append_array(PackedInt32Array([base_index, base_index + 1, base_index + 2, base_index, base_index + 2, base_index + 3]))

func _create_editor_plateau(position: Vector3, elevation: float, surface := SURFACE_LAND) -> Node3D:
	var plateau := StaticBody3D.new()
	plateau.name = "Editor Water" if surface == SURFACE_WATER else ("Editor High Plateau" if elevation > EditorTerrainSystemScript.LOW_ELEVATION else "Editor Low Ground")
	plateau.position = Vector3(position.x, 0.0, position.z)
	plateau.add_to_group("ground")
	plateau.add_to_group("editor_terrain")
	plateau.set_meta("terrain_kind", "plateau")
	plateau.set_meta("terrain_surface", surface)
	plateau.set_meta("terrain_width", EDITOR_PLATEAU_WIDTH)
	plateau.set_meta("terrain_depth", EDITOR_PLATEAU_DEPTH)
	plateau.set_meta("terrain_elevation", elevation)
	editor_terrain_system.stamp_terrain(plateau)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var terrain_thickness := 0.18 if elevation <= EditorTerrainSystemScript.LOW_ELEVATION else elevation
	shape.size = Vector3(EDITOR_PLATEAU_WIDTH, terrain_thickness, EDITOR_PLATEAU_DEPTH)
	collision.shape = shape
	collision.position.y = terrain_thickness * 0.5
	plateau.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_instance.mesh = mesh
	mesh_instance.position.y = terrain_thickness * 0.5
	if surface == SURFACE_WATER:
		mesh_instance.material_override = _make_water_material()
	else:
		mesh_instance.material_override = make_terrain_paint_material("paint_steppe" if elevation > EditorTerrainSystemScript.LOW_ELEVATION else "paint_meadow", Vector2(EDITOR_PLATEAU_WIDTH, EDITOR_PLATEAU_DEPTH))
	plateau.add_child(mesh_instance)
	world_root.add_child(plateau)
	return plateau

func _replace_overlapping_height_terrain(position: Vector3, width: float, depth: float, update_records: bool) -> void:
	for node in get_tree().get_nodes_in_group("editor_terrain"):
		var terrain := node as Node3D
		if terrain == null or not is_instance_valid(terrain):
			continue
		if str(terrain.get_meta("terrain_kind", "")) not in ["plateau", "ramp"]:
			continue
		var terrain_width := float(terrain.get_meta("terrain_width", width))
		var terrain_depth := float(terrain.get_meta("terrain_depth", depth))
		if _terrain_rects_overlap(position, width, depth, terrain.global_position, terrain_width, terrain_depth):
			if editor_terrain_system != null and editor_terrain_system.has_method("clear_terrain"):
				editor_terrain_system.clear_terrain(terrain)
			terrain.queue_free()
	if update_records and map_editor_system != null and map_editor_system.has_method("remove_overlapping_terrain_placements"):
		map_editor_system.remove_overlapping_terrain_placements(position, width, depth)

func _terrain_rects_overlap(a_position: Vector3, a_width: float, a_depth: float, b_position: Vector3, b_width: float, b_depth: float) -> bool:
	return absf(a_position.x - b_position.x) < (a_width + b_width) * 0.5 \
		and absf(a_position.z - b_position.z) < (a_depth + b_depth) * 0.5

func _create_editor_ramp(position: Vector3) -> Node3D:
	var ramp_transform: Dictionary = editor_terrain_system.ramp_placement_for(position, EDITOR_RAMP_LENGTH)
	if not bool(ramp_transform.get("valid", false)):
		return null
	var ramp_position: Vector3 = ramp_transform["position"]
	var low_to_high: Vector3 = ramp_transform["direction"]
	var ramp_angle := rad_to_deg(atan2(-low_to_high.z, low_to_high.x))

	var ramp := StaticBody3D.new()
	ramp.name = "Editor Ramp"
	ramp.position = Vector3(ramp_position.x, 0.0, ramp_position.z)
	ramp.add_to_group("ground")
	ramp.add_to_group("editor_terrain")
	ramp.set_meta("terrain_kind", "ramp")
	ramp.set_meta("terrain_width", EDITOR_RAMP_LENGTH)
	ramp.set_meta("terrain_depth", EDITOR_RAMP_DEPTH)
	ramp.set_meta("terrain_direction_x", low_to_high.x)
	ramp.set_meta("terrain_direction_z", low_to_high.z)
	ramp.set_meta("terrain_low_elevation", EditorTerrainSystemScript.LOW_ELEVATION)
	ramp.set_meta("terrain_high_elevation", EditorTerrainSystemScript.HIGH_ELEVATION)
	editor_terrain_system.stamp_terrain(ramp)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(EDITOR_RAMP_LENGTH, 0.24, EDITOR_RAMP_DEPTH)
	collision.shape = shape
	collision.position.y = EditorTerrainSystemScript.HIGH_ELEVATION * 0.5
	collision.rotation_degrees.z = rad_to_deg(atan2(EditorTerrainSystemScript.HIGH_ELEVATION, EDITOR_RAMP_LENGTH))
	collision.rotation_degrees.y = ramp_angle
	ramp.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_instance.mesh = mesh
	mesh_instance.position.y = EditorTerrainSystemScript.HIGH_ELEVATION * 0.5
	mesh_instance.rotation_degrees.z = rad_to_deg(atan2(EditorTerrainSystemScript.HIGH_ELEVATION, EDITOR_RAMP_LENGTH))
	mesh_instance.rotation_degrees.y = ramp_angle
	mesh_instance.material_override = make_terrain_paint_material("paint_cliff", Vector2(EDITOR_RAMP_LENGTH, EDITOR_RAMP_DEPTH))
	ramp.add_child(mesh_instance)
	world_root.add_child(ramp)
	return ramp

func _orient_gold_mine_to_terrain_face(gold_mine: Node3D, low_to_high := Vector3.INF) -> void:
	if gold_mine == null:
		return
	if low_to_high == Vector3.INF:
		low_to_high = editor_terrain_system.low_to_high_direction(gold_mine.global_position)
	var high_to_low: Vector3 = -low_to_high
	gold_mine.rotation_degrees.y = rad_to_deg(atan2(high_to_low.z, -high_to_low.x))

func _create_editor_unit(team: String, display_name: String, role: String, position: Vector3, color: Color) -> Node3D:
	var unit := RTSUnitScript.new()
	unit.team = team
	unit.display_name = display_name
	unit.unit_role = role
	unit.max_health = 70
	unit.health = 70
	unit.attack_damage = 9
	unit.attack_range = 12.0
	unit.move_speed = 5.6
	unit.position = _with_terrain_height(position)
	unit.set_meta("editor_color", color)
	world_root.add_child(unit)
	return unit

func make_terrain_paint_material(asset_id: String, terrain_size: Vector2, soft_edges := false) -> Material:
	var color := terrain_paint_color(asset_id)
	var texture_path := terrain_paint_texture_path(asset_id)
	if soft_edges:
		return _make_soft_paint_material(color, texture_path, terrain_size)
	var material := _make_material(color)
	if texture_path.is_empty():
		return material
	if not ResourceLoader.exists(texture_path):
		return material
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return material
	material.albedo_texture = texture
	material.texture_repeat = 1
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var tile_world_size := 4.0
	material.uv1_scale = Vector3(maxf(terrain_size.x / tile_world_size, 1.0), maxf(terrain_size.y / tile_world_size, 1.0), 1.0)
	return material

func _make_opaque_terrain_material(color: Color, texture_path: String, tile_world_size: float) -> StandardMaterial3D:
	var material := _make_material(color)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return material
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return material
	material.albedo_texture = texture
	material.texture_repeat = 1
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var inv := 1.0 / maxf(tile_world_size, 0.1)
	material.uv1_scale = Vector3(inv, inv, 1.0)
	return material

func _make_soft_paint_material(color: Color, texture_path: String, terrain_size: Vector2) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

uniform sampler2D paint_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec2 uv_scale = vec2(1.0);

void fragment() {
	vec4 tex = texture(paint_texture, UV * uv_scale);
	ALBEDO = tex.rgb;
	ALPHA = tex.a * COLOR.a;
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
}
"""
	material.shader = shader
	var texture: Texture2D = null
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D
	if texture == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(color)
		texture = ImageTexture.create_from_image(image)
	material.set_shader_parameter("paint_texture", texture)
	var tile_world_size := 3.0
	material.set_shader_parameter("uv_scale", Vector2(maxf(terrain_size.x / tile_world_size, 1.0), maxf(terrain_size.y / tile_world_size, 1.0)))
	return material

func terrain_paint_texture_path(asset_id: String) -> String:
	var asset_definition := _map_asset_definition(asset_id)
	var asset_texture := str(asset_definition.get("texture_path", ""))
	if not asset_texture.is_empty():
		return asset_texture
	match asset_id:
		"paint_meadow":
			return "res://assets/visuals/imported/america0/meadow/graphics/terrain/small_meadow_20.png"
		"paint_steppe":
			return "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe20.png"
		"paint_cliff":
			return "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe28.png"
		"paint_ford":
			return "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe5.png"
	return ""

func terrain_paint_color(asset_id: String) -> Color:
	var asset_definition := _map_asset_definition(asset_id)
	if asset_definition.has("icon_color"):
		return asset_definition["icon_color"]
	match asset_id:
		"paint_meadow":
			return Color(0.35, 0.58, 0.28)
		"paint_steppe":
			return Color(0.56, 0.50, 0.28)
		"paint_cliff":
			return Color(0.42, 0.36, 0.27)
		"paint_ford":
			return Color(0.58, 0.48, 0.29)
	return Color(0.35, 0.55, 0.28)

func _map_asset_definition(asset_id: String) -> Dictionary:
	if map_editor_system == null or not map_editor_system.has_method("asset_definitions"):
		return {}
	for asset in map_editor_system.asset_definitions():
		if str(asset.get("id", "")) == asset_id:
			return asset
	return {}

func _with_terrain_height(position: Vector3) -> Vector3:
	if callbacks.has("with_terrain_height") and callbacks["with_terrain_height"].is_valid():
		return callbacks["with_terrain_height"].call(position)
	return position

func _call_node(callback_name: String, args: Array) -> Node3D:
	if not callbacks.has(callback_name):
		return null
	var callback: Callable = callbacks[callback_name]
	if not callback.is_valid():
		return null
	return callback.callv(args) as Node3D

func _set_preview_color(root: Node3D, color: Color) -> void:
	for child in root.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = _make_transparent_material(color)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material

func _make_transparent_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.roughness = 0.82
	return material

func _make_water_material() -> StandardMaterial3D:
	return TerrainServiceScript.make_water_material()
