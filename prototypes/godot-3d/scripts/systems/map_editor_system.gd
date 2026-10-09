@tool
extends Node
class_name MapEditorSystem

const BUNDLED_MAPS_DIR := "res://maps"
const USER_MAPS_DIR := "user://maps"
const DEFAULT_MAP_PATH := "user://maps/map_editor_autosave.json"
const PAINT_RECORD_CELL_SIZE := 0.45
const PAINT_RECORD_HEIGHT_SIZE := 0.28
const TERRAIN_RECORD_CELL_SIZE := 2.0

var enabled := false
var pending_asset := ""
var placed_assets: Array[Dictionary] = []
var map_name := "Untitled Map"

func asset_categories() -> Array[Dictionary]:
	return [
		{"id": "textures", "label": "Textures"},
		{"id": "terrain", "label": "Terrain"},
		{"id": "nature", "label": "Nature"},
		{"id": "buildings", "label": "Buildings"},
		{"id": "units_american", "label": "Units: Americans"},
		{"id": "units_mexican", "label": "Units: Mexicans"},
		{"id": "units_indian", "label": "Units: Indian"},
		{"id": "units_outlaw", "label": "Units: Outlaw"}
	]

func asset_definitions() -> Array[Dictionary]:
	var assets: Array[Dictionary] = []
	assets.append_array(_texture_asset_definitions())
	assets.append_array([
		{"id": "terrain_low_plateau", "category": "terrain", "label": "Low\nGround", "tip": "Place a low elevation terrain piece.", "icon_shape": "plateau", "icon_color": Color(0.35, 0.55, 0.28)},
		{"id": "terrain_water", "category": "terrain", "label": "Water", "tip": "Place low elevation water terrain.", "icon_shape": "plateau", "icon_color": Color(0.12, 0.36, 0.58)},
		{"id": "terrain_high_plateau", "category": "terrain", "label": "High\nPlateau", "tip": "Place a high elevation plateau terrain piece.", "icon_shape": "plateau", "icon_color": Color(0.43, 0.55, 0.25)},
		{"id": "terrain_ramp", "category": "terrain", "label": "Ramp\nLow-High", "tip": "Place a ramp between low and high elevation.", "icon_shape": "ramp", "icon_color": Color(0.46, 0.42, 0.26)},
		{"id": "gold_mine", "category": "terrain", "label": "Gold\nMine", "tip": "Place a cliff-face gold mine.", "icon_shape": "mine", "icon_color": Color(0.90, 0.66, 0.18)},
		{"id": "single_tree", "category": "nature", "label": "Tree", "tip": "Place a single gatherable tree.", "icon_shape": "tree", "icon_color": Color(0.18, 0.48, 0.18)},
		{"id": "tree_brush", "category": "nature", "label": "Tree\nBrush", "tip": "Paint a tight cluster of individual trees.", "icon_shape": "tree", "icon_color": Color(0.10, 0.36, 0.12)},
		{"id": "rock", "category": "nature", "label": "Rock", "tip": "Place a small rock cluster.", "icon_shape": "rock", "icon_color": Color(0.48, 0.48, 0.44)},
		{"id": "garden", "category": "nature", "label": "Garden", "tip": "Place a gatherable food garden.", "icon_shape": "field", "icon_color": Color(0.30, 0.62, 0.20)},
		{"id": "american_soldier", "category": "units_american", "label": "Soldier", "tip": "Place an American soldier.", "icon_shape": "unit", "icon_color": Color(0.26, 0.42, 0.66)},
		{"id": "american_worker", "category": "units_american", "label": "Worker", "tip": "Place an American worker.", "icon_shape": "unit", "icon_color": Color(0.42, 0.54, 0.70)},
		{"id": "worker", "category": "units_mexican", "label": "Farmhand", "tip": "Place a Mexican farmhand worker unit.", "icon_shape": "unit", "icon_color": Color(0.62, 0.44, 0.20)},
		{"id": "infantryman", "category": "units_mexican", "label": "Infantry", "tip": "Place a Mexican infantryman unit.", "icon_shape": "unit", "icon_color": Color(0.42, 0.54, 0.64)},
		{"id": "cavalryman", "category": "units_mexican", "label": "Cavalry", "tip": "Place a Mexican cavalryman unit.", "icon_shape": "cavalry", "icon_color": Color(0.48, 0.32, 0.16)},
		{"id": "militiaman", "category": "units_mexican", "label": "Militia", "tip": "Place a Mexican militiaman unit.", "icon_shape": "unit", "icon_color": Color(0.58, 0.48, 0.30)},
		{"id": "gunslinger", "category": "units_mexican", "label": "Gunslinger", "tip": "Place a Mexican gunslinger unit.", "icon_shape": "unit", "icon_color": Color(0.64, 0.34, 0.24)},
		{"id": "priest", "category": "units_mexican", "label": "Priest", "tip": "Place a Mexican priest unit.", "icon_shape": "unit", "icon_color": Color(0.78, 0.74, 0.56)},
		{"id": "cannon", "category": "units_mexican", "label": "Cannon", "tip": "Place a Mexican cannon.", "icon_shape": "cannon", "icon_color": Color(0.16, 0.16, 0.15)},
		{"id": "indian_brave", "category": "units_indian", "label": "Brave", "tip": "Place an Indian brave.", "icon_shape": "unit", "icon_color": Color(0.50, 0.32, 0.18)},
		{"id": "indian_rider", "category": "units_indian", "label": "Rider", "tip": "Place an Indian rider.", "icon_shape": "cavalry", "icon_color": Color(0.44, 0.27, 0.13)},
		{"id": "outlaw_gunslinger", "category": "units_outlaw", "label": "Gunslinger", "tip": "Place an outlaw gunslinger.", "icon_shape": "unit", "icon_color": Color(0.68, 0.18, 0.14)},
		{"id": "outlaw_raider", "category": "units_outlaw", "label": "Raider", "tip": "Place an outlaw raider.", "icon_shape": "unit", "icon_color": Color(0.48, 0.16, 0.12)},
		{"id": "command_post", "category": "buildings", "label": "Command\nPost", "tip": "Place a Mexican command post.", "icon_shape": "building", "icon_color": Color(0.50, 0.33, 0.18)},
		{"id": "house", "category": "buildings", "label": "House", "tip": "Place a completed house.", "icon_shape": "building", "icon_color": Color(0.48, 0.31, 0.17)},
		{"id": "hacienda", "category": "buildings", "label": "Hacienda", "tip": "Place a completed hacienda.", "icon_shape": "building", "icon_color": Color(0.68, 0.50, 0.30)},
		{"id": "cantina", "category": "buildings", "label": "Cantina", "tip": "Place a completed cantina.", "icon_shape": "building", "icon_color": Color(0.40, 0.20, 0.13)},
		{"id": "butcher", "category": "buildings", "label": "Butcher", "tip": "Place a completed butcher.", "icon_shape": "building", "icon_color": Color(0.48, 0.16, 0.12)},
		{"id": "barracks", "category": "buildings", "label": "Barracks", "tip": "Place completed barracks.", "icon_shape": "building", "icon_color": Color(0.38, 0.34, 0.26)},
		{"id": "gold_warehouse", "category": "buildings", "label": "Gold\nStore", "tip": "Place a completed gold warehouse.", "icon_shape": "building", "icon_color": Color(0.52, 0.43, 0.22)},
		{"id": "finca", "category": "buildings", "label": "Finca", "tip": "Place a completed finca.", "icon_shape": "field", "icon_color": Color(0.63, 0.46, 0.25)},
		{"id": "field", "category": "buildings", "label": "Field", "tip": "Place a completed field.", "icon_shape": "field", "icon_color": Color(0.22, 0.48, 0.18)},
		{"id": "sawmill", "category": "buildings", "label": "Sawmill", "tip": "Place a completed sawmill.", "icon_shape": "building", "icon_color": Color(0.45, 0.29, 0.14)},
		{"id": "trading_post", "category": "buildings", "label": "Trading\nPost", "tip": "Place a completed trading post.", "icon_shape": "building", "icon_color": Color(0.40, 0.30, 0.16)},
		{"id": "weapons_factory", "category": "buildings", "label": "Weapons\nFactory", "tip": "Place a completed weapons factory.", "icon_shape": "building", "icon_color": Color(0.42, 0.29, 0.18)},
		{"id": "wall", "category": "buildings", "label": "Wall", "tip": "Place a completed wall.", "icon_shape": "wall", "icon_color": Color(0.36, 0.24, 0.13)},
		{"id": "tower", "category": "buildings", "label": "Tower", "tip": "Place a completed tower.", "icon_shape": "tower", "icon_color": Color(0.34, 0.24, 0.16)},
		{"id": "wharf", "category": "buildings", "label": "Wharf", "tip": "Place a completed wharf.", "icon_shape": "dock", "icon_color": Color(0.30, 0.19, 0.09)},
		{"id": "church", "category": "buildings", "label": "Church", "tip": "Place a completed church.", "icon_shape": "church", "icon_color": Color(0.62, 0.58, 0.48)},
		{"id": "mission", "category": "buildings", "label": "Mission", "tip": "Place a completed mission.", "icon_shape": "church", "icon_color": Color(0.52, 0.45, 0.34)},
		{"id": "fort", "category": "buildings", "label": "Fort", "tip": "Place a completed fort.", "icon_shape": "fort", "icon_color": Color(0.31, 0.26, 0.19)}
	])
	return assets

func _texture_asset_definitions() -> Array[Dictionary]:
	var assets: Array[Dictionary] = []
	_add_texture_asset(assets, "paint_meadow", "Meadow 20", "res://assets/visuals/imported/america0/meadow/graphics/terrain/small_meadow_20.png", Color(0.35, 0.58, 0.28))
	_add_texture_asset(assets, "paint_steppe", "Steppe 20", "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe20.png", Color(0.56, 0.50, 0.28))
	_add_texture_asset(assets, "paint_cliff", "Cliff 28", "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe28.png", Color(0.42, 0.36, 0.27))
	_add_texture_asset(assets, "paint_ford", "Ford 5", "res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe5.png", Color(0.58, 0.48, 0.29))
	for index in range(7, 40):
		_add_texture_asset(
			assets,
			"paint_meadow_%d" % index,
			"Meadow %02d" % index,
			"res://assets/visuals/imported/america0/meadow/graphics/terrain/small_meadow_%d.png" % index,
			Color(0.35, 0.58, 0.28)
		)
	for index in range(5, 40):
		_add_texture_asset(
			assets,
			"paint_steppe_%d" % index,
			"Steppe %02d" % index,
			"res://assets/visuals/imported/america0/steppe/graphics/terrain/steppe%d.png" % index,
			Color(0.56, 0.50, 0.28)
		)
	for index in range(7, 40):
		_add_texture_asset(
			assets,
			"paint_small_steppe_%d" % index,
			"Small Steppe %02d" % index,
			"res://assets/visuals/imported/america0/steppe/graphics/terrain/small_steppe_%d.png" % index,
			Color(0.50, 0.47, 0.26)
		)
	return assets

func _add_texture_asset(assets: Array[Dictionary], asset_id: String, label: String, texture_path: String, color: Color) -> void:
	if ResourceLoader.exists(texture_path):
		assets.append(_texture_asset(asset_id, label, texture_path, color))

func _texture_asset(asset_id: String, label: String, texture_path: String, color: Color) -> Dictionary:
	return {
		"id": asset_id,
		"category": "textures",
		"label": label,
		"tip": "Paint %s from the original terrain texture set." % label,
		"icon_shape": "texture",
		"icon_color": color,
		"texture_path": texture_path
	}

func assets_for_category(category_id: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for asset in asset_definitions():
		if str(asset.get("category", "")) == category_id:
			filtered.append(asset)
	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	return filtered

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		cancel_placement()

func begin_placement(asset_id: String) -> void:
	enabled = true
	pending_asset = asset_id

func cancel_placement() -> void:
	pending_asset = ""

func has_pending_asset() -> bool:
	return pending_asset != ""

func record_placement(asset_id: String, position: Vector3) -> void:
	if _is_brush_record_asset(asset_id):
		var paint_key := _brush_position_key(asset_id, position)
		var asset_family := _brush_record_family(asset_id)
		for index in range(placed_assets.size() - 1, -1, -1):
			var existing := placed_assets[index]
			var existing_id := str(existing.get("id", ""))
			if _is_brush_record_asset(existing_id) and _brush_record_family(existing_id) == asset_family and _brush_position_key(existing_id, asset_position(existing)) == paint_key:
				placed_assets.remove_at(index)
	placed_assets.append({
		"id": asset_id,
		"position": [position.x, position.y, position.z]
	})

func remove_overlapping_terrain_placements(position: Vector3, width: float, depth: float) -> void:
	for index in range(placed_assets.size() - 1, -1, -1):
		var existing := placed_assets[index]
		if not _is_height_terrain_asset(str(existing.get("id", ""))):
			continue
		if _terrain_rects_overlap(position, width, depth, asset_position(existing), width, depth):
			placed_assets.remove_at(index)

func remove_placement(asset_id: String, position: Vector3) -> bool:
	var removed := false
	var target_key := _placement_key(asset_id, position)
	for index in range(placed_assets.size() - 1, -1, -1):
		var existing := placed_assets[index]
		if str(existing.get("id", "")) == asset_id and _placement_key(asset_id, asset_position(existing)) == target_key:
			placed_assets.remove_at(index)
			removed = true
	return removed

func _paint_position_key(position: Vector3) -> String:
	return "%d:%d:%d" % [
		roundi(position.x / PAINT_RECORD_CELL_SIZE),
		roundi(position.z / PAINT_RECORD_CELL_SIZE),
		roundi(position.y / PAINT_RECORD_HEIGHT_SIZE)
	]

func _placement_key(asset_id: String, position: Vector3) -> String:
	if _is_brush_record_asset(asset_id):
		return _brush_position_key(asset_id, position)
	return "%d:%d:%d" % [roundi(position.x * 10.0), roundi(position.y * 10.0), roundi(position.z * 10.0)]

func _brush_position_key(asset_id: String, position: Vector3) -> String:
	if asset_id.begins_with("paint_"):
		return _paint_position_key(position)
	return "%d:%d" % [
		roundi(position.x / TERRAIN_RECORD_CELL_SIZE),
		roundi(position.z / TERRAIN_RECORD_CELL_SIZE)
	]

func _is_brush_record_asset(asset_id: String) -> bool:
	return asset_id.begins_with("paint_") or asset_id in ["terrain_plateau", "terrain_high_plateau", "terrain_low_plateau", "terrain_water"]

func _brush_record_family(asset_id: String) -> String:
	return "texture" if asset_id.begins_with("paint_") else "terrain"

func _is_height_terrain_asset(asset_id: String) -> bool:
	return asset_id in ["terrain_plateau", "terrain_high_plateau", "terrain_low_plateau", "terrain_water", "terrain_ramp"]

func _terrain_rects_overlap(a_position: Vector3, a_width: float, a_depth: float, b_position: Vector3, b_width: float, b_depth: float) -> bool:
	return absf(a_position.x - b_position.x) < (a_width + b_width) * 0.5 \
		and absf(a_position.z - b_position.z) < (a_depth + b_depth) * 0.5

func map_entries() -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	_add_maps_from_dir(maps, BUNDLED_MAPS_DIR, false)
	_add_maps_from_dir(maps, USER_MAPS_DIR, true)
	maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("editable", false)) != bool(b.get("editable", false)):
			return not bool(a.get("editable", false))
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	return maps

func make_user_map_path(name: String) -> String:
	var safe_name := _sanitize_map_name(name)
	if safe_name.is_empty():
		safe_name = "new_map"
	return "%s/%s.json" % [USER_MAPS_DIR, safe_name]

func new_empty_map(name := "New Map") -> Dictionary:
	map_name = name
	placed_assets.clear()
	return {"name": map_name, "assets": placed_assets.duplicate(true)}

func save_map(path := DEFAULT_MAP_PATH, name := map_name, river := {}) -> bool:
	if not _ensure_user_maps_dir():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	map_name = name
	var map_data := {"name": map_name, "assets": placed_assets}
	if not river.is_empty():
		map_data["river"] = river
	file.store_string(JSON.stringify(map_data, "\t"))
	return true

func load_map(path := DEFAULT_MAP_PATH) -> Array[Dictionary]:
	var map_data := load_map_data(path)
	placed_assets = map_data.get("assets", []).duplicate(true)
	map_name = str(map_data.get("name", path.get_file().get_basename().capitalize()))
	return placed_assets.duplicate(true)

func load_map_data(path := DEFAULT_MAP_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"name": path.get_file().get_basename().capitalize(), "assets": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"name": path.get_file().get_basename().capitalize(), "assets": []}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"name": path.get_file().get_basename().capitalize(), "assets": []}
	var assets: Variant = parsed.get("assets", [])
	if typeof(assets) != TYPE_ARRAY:
		assets = []
	var loaded_assets: Array[Dictionary] = []
	for asset in assets:
		if typeof(asset) == TYPE_DICTIONARY:
			loaded_assets.append(asset)
	return {
		"name": str(parsed.get("name", path.get_file().get_basename().capitalize())),
		"assets": loaded_assets,
		"path": path
	}

func _add_maps_from_dir(maps: Array[Dictionary], path: String, editable: bool) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "json":
			var map_path := "%s/%s" % [path, file_name]
			var map_data := load_map_data(map_path)
			maps.append({
				"name": str(map_data.get("name", file_name.get_basename().capitalize())),
				"path": map_path,
				"editable": editable
			})
		file_name = dir.get_next()
	dir.list_dir_end()

func _ensure_user_maps_dir() -> bool:
	var global_path := ProjectSettings.globalize_path(USER_MAPS_DIR)
	if DirAccess.dir_exists_absolute(global_path):
		return true
	return DirAccess.make_dir_recursive_absolute(global_path) == OK

func _sanitize_map_name(name: String) -> String:
	var safe := name.strip_edges().to_lower()
	var output := ""
	for index in range(safe.length()):
		var character := safe[index]
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			output += character
		elif character == " " or character == "-" or character == "_":
			output += "_"
	while output.contains("__"):
		output = output.replace("__", "_")
	return output.strip_edges().trim_suffix("_")

func asset_name(asset_id: String, building_names := {}) -> String:
	if asset_id.begins_with("paint_"):
		for asset in _texture_asset_definitions():
			if str(asset.get("id", "")) == asset_id:
				return str(asset.get("label", asset_id.capitalize()))
	match asset_id:
		"paint_meadow":
			return "Meadow Paint"
		"paint_steppe":
			return "Steppe Paint"
		"paint_cliff":
			return "Cliff Paint"
		"paint_ford":
			return "Ford Paint"
		"terrain_plateau", "terrain_high_plateau":
			return "High Plateau"
		"terrain_low_plateau":
			return "Low Ground"
		"terrain_water":
			return "Water"
		"terrain_ramp":
			return "Ramp"
		"single_tree":
			return "Tree"
		"tree_brush":
			return "Tree Brush"
		"rock":
			return "Rock"
		"rock_cluster":
			return "Rock Cluster"
		"gold_mine":
			return "Gold Mine"
		"garden":
			return "Garden"
		"worker":
			return "Mexican Farmhand"
		"infantryman":
			return "Mexican Infantryman"
		"cavalryman":
			return "Mexican Cavalryman"
		"militiaman":
			return "Mexican Militiaman"
		"gunslinger":
			return "Mexican Gunslinger"
		"priest":
			return "Mexican Priest"
		"enemy":
			return "Enemy Warrior"
		"cannon":
			return "Mexican Cannon"
		"american_worker":
			return "American Worker"
		"american_soldier":
			return "American Soldier"
		"indian_brave":
			return "Indian Brave"
		"indian_rider":
			return "Indian Rider"
		"outlaw_gunslinger":
			return "Outlaw Gunslinger"
		"outlaw_raider":
			return "Outlaw Raider"
		"command_post":
			return "Command Post"
		"weapons_factory":
			return "Weapons Factory"
	if building_names.has(asset_id):
		return str(building_names[asset_id])
	return asset_id.capitalize()

func asset_position(asset: Dictionary) -> Vector3:
	var raw_position: Array = asset.get("position", [0.0, 0.0, 0.0])
	if raw_position.size() < 3:
		return Vector3.ZERO
	return Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2]))
