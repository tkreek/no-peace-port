@tool
extends Node3D

const RTSCameraScript := preload("res://scripts/rts_camera.gd")
const RTSUnitScript := preload("res://scripts/unit.gd")
const ModernChurchScene := preload("res://scenes/assets/mexican_church_modern.tscn")
const ModernMexicanFarmhandScene := preload("res://scenes/assets/mexican_farmhand_modern.tscn")
const ModernMexicanInfantrymanScene := preload("res://scenes/assets/mexican_infantryman_modern.tscn")
const ModernMexicanCavalrymanScene := preload("res://scenes/assets/mexican_cavalryman_modern.tscn")
const ModernMexicanMilitiamanScene := preload("res://scenes/assets/mexican_militiaman_modern.tscn")
const ModernMexicanGunslingerScene := preload("res://scenes/assets/mexican_gunslinger_modern.tscn")
const ModernMexicanPriestScene := preload("res://scenes/assets/mexican_priest_modern.tscn")
const ModernMexicanCannonScene := preload("res://scenes/assets/mexican_cannon_modern.tscn")
const TerrainServiceScript := preload("res://scripts/terrain/terrain_service.gd")
const ResourceNodeScript := preload("res://scripts/entities/resource_node.gd")
const ConstructionSiteScript := preload("res://scripts/entities/construction_site.gd")
const ClassicSpriteAssetScript := preload("res://scripts/visuals/classic_sprite_asset.gd")
const EconomySystemScript := preload("res://scripts/systems/economy_system.gd")
const BuildSystemScript := preload("res://scripts/systems/build_system.gd")
const CommandSystemScript := preload("res://scripts/systems/command_system.gd")
const SelectionSystemScript := preload("res://scripts/systems/selection_system.gd")
const MapEditorSystemScript := preload("res://scripts/systems/map_editor_system.gd")
const EditorTerrainSystemScript := preload("res://scripts/systems/editor_terrain_system.gd")
const MapAssetPlacementSystemScript := preload("res://scripts/systems/map_asset_placement_system.gd")
const MexicanTechTreeScript := preload("res://scripts/data/mexican_tech_tree.gd")
const MinimapPanelScript := preload("res://scripts/ui/minimap_panel.gd")
const ResourceBarScript := preload("res://scripts/ui/resource_bar.gd")
const RESOURCE_VISUAL_WOOD := 0
const RESOURCE_VISUAL_GOLD := 1
const RESOURCE_VISUAL_GARDEN := 2
const MEXICAN_FACTION_THEME_PATH := "res://assets/audio/music/mexican_faction_theme.mp3"
const SFX_PATHS := {
	"build": "res://assets/audio/sfx/build_building.wav",
	"building_complete": "res://assets/audio/sfx/mexican_building_complete.wav",
	"building_burning": "res://assets/audio/sfx/burning_building.wav",
	"building_collapse_small": "res://assets/audio/sfx/small_building_collapse.wav",
	"building_collapse_large": "res://assets/audio/sfx/large_building_collapse_1.wav",
	"chop": "res://assets/audio/sfx/chop_wood.wav",
	"mine": "res://assets/audio/sfx/goldmine.wav",
	"garden": "res://assets/audio/sfx/harvest_field.wav",
	"rifle": "res://assets/audio/sfx/rifle_shot_1.wav",
	"rifle_alt": "res://assets/audio/sfx/rifle_shot_2.wav",
	"pistol": "res://assets/audio/sfx/pistol_shot_1.wav",
	"melee": "res://assets/audio/sfx/stab.wav",
	"cannon": "res://assets/audio/sfx/mexican_cannon.wav",
	"unit_death": "res://assets/audio/voices/common/man_death_short.wav",
	"horse_death": "res://assets/audio/sfx/horse_death.wav"
}
const RESOURCE_GATHER_SOUNDS := {
	"wood": "res://assets/audio/sfx/chop_wood.wav",
	"gold": "res://assets/audio/sfx/goldmine.wav",
	"food": "res://assets/audio/sfx/harvest_field.wav"
}
const UNIT_TRAIN_QUEUE_LIMIT := 10
const DEFAULT_UNIT_SOUND_PROFILE := {
	"selection": "",
	"movement": "",
	"attack": "",
	"death": "res://assets/audio/voices/common/man_death_short.wav",
	"actions": {
		"building": "res://assets/audio/sfx/build_building.wav",
		"gather_food": "res://assets/audio/sfx/harvest_field.wav",
		"gather_gold": "res://assets/audio/sfx/goldmine.wav",
		"gather_wood": "res://assets/audio/sfx/chop_wood.wav"
	}
}
const DEFAULT_BUILDING_SOUND_PROFILE := {
	"selection": "res://assets/audio/sfx/build_building.wav",
	"burning": "res://assets/audio/sfx/burning_building.wav",
	"collapse": "res://assets/audio/sfx/large_building_collapse_1.wav",
	"building": "res://assets/audio/sfx/build_building.wav"
}
const BUILDING_SOUND_OVERRIDES := {
	"command_post": {"selection": "res://assets/audio/sfx/mexican_hq.wav"},
	"house": {"selection": "res://assets/audio/sfx/door.wav", "collapse": "res://assets/audio/sfx/small_building_collapse.wav"},
	"hacienda": {"selection": "res://assets/audio/sfx/field.wav"},
	"cantina": {"selection": "res://assets/audio/sfx/mexican_cantina.wav"},
	"butcher": {"selection": "res://assets/audio/sfx/hay.wav"},
	"barracks": {"selection": "res://assets/audio/sfx/mexican_barracks.wav"},
	"gold_warehouse": {"selection": "res://assets/audio/sfx/gold_storage.wav", "collapse": "res://assets/audio/sfx/small_building_collapse.wav"},
	"finca": {"selection": "res://assets/audio/sfx/field.wav"},
	"field": {"selection": "res://assets/audio/sfx/field.wav", "collapse": "res://assets/audio/sfx/small_building_collapse.wav"},
	"sawmill": {"selection": "res://assets/audio/sfx/sawmill.wav"},
	"trading_post": {"selection": "res://assets/audio/sfx/trading_post.wav"},
	"weapons_factory": {"selection": "res://assets/audio/sfx/weapons_factory.wav"},
	"wall": {"selection": "res://assets/audio/sfx/palisade.wav", "collapse": "res://assets/audio/sfx/small_building_collapse.wav"},
	"tower": {"selection": "res://assets/audio/sfx/mexican_fort.wav"},
	"wharf": {"selection": "res://assets/audio/sfx/boathouse.wav"},
	"church": {"selection": "res://assets/audio/sfx/usa_kirche.wav"},
	"mission": {"selection": "res://assets/audio/sfx/mexican_monastery.wav"},
	"fort": {"selection": "res://assets/audio/sfx/mexican_fort.wav"}
}
const MEXICAN_FARMHAND_SOUND_PROFILE := {
	"selection": "res://assets/audio/voices/mexican/farmhand_select.wav",
	"movement": "res://assets/audio/voices/mexican/farmhand_command.wav"
}
const MEXICAN_UNIT_ASSETS := {
	"infantryman": {
		"scene": ModernMexicanInfantrymanScene,
		"sounds": {
			"selection": "res://assets/audio/voices/mexican/infantry_select.wav",
			"movement": "res://assets/audio/voices/mexican/infantry_command.wav",
			"attack": "res://assets/audio/sfx/rifle_shot_1.wav"
		}
	},
	"cavalryman": {
		"scene": ModernMexicanCavalrymanScene,
		"sounds": {
			"selection": "res://assets/audio/voices/mexican/cavalry_select.wav",
			"movement": "res://assets/audio/voices/mexican/cavalry_command.wav",
			"attack": "res://assets/audio/sfx/stab.wav",
			"death": "res://assets/audio/sfx/horse_death.wav"
		}
	},
	"militiaman": {
		"scene": ModernMexicanMilitiamanScene,
		"sounds": {
			"selection": "res://assets/audio/voices/mexican/militia_select.wav",
			"movement": "res://assets/audio/voices/mexican/militia_command.wav",
			"attack": "res://assets/audio/sfx/rifle_shot_2.wav"
		}
	},
	"gunslinger": {
		"scene": ModernMexicanGunslingerScene,
		"sounds": {
			"selection": "res://assets/audio/voices/mexican/gunslinger_select.wav",
			"movement": "res://assets/audio/voices/mexican/gunslinger_command.wav",
			"attack": "res://assets/audio/sfx/pistol_shot_1.wav"
		}
	},
	"priest": {
		"scene": ModernMexicanPriestScene,
		"sounds": {
			"selection": "res://assets/audio/voices/mexican/priest_select.wav",
			"movement": "res://assets/audio/voices/mexican/priest_command.wav"
		}
	},
	"cannon": {
		"scene": ModernMexicanCannonScene,
		"sounds": {
			"selection": "res://assets/audio/voices/mexican/infantry_select.wav",
			"movement": "res://assets/audio/sfx/move_cannon.wav",
			"attack": "res://assets/audio/sfx/mexican_cannon.wav",
			"death": "res://assets/audio/sfx/transport_collapse.wav"
		}
	}
}
enum AppMode { GAMEPLAY, MAP_MAKER }

var camera_rig: Node3D
var selected_units: Array[Node] = []
var selected_building: Node3D
var selected_resource: Node3D
var drag_start := Vector2.ZERO
var dragging := false
var selection_box: ColorRect
var world_root: Node3D
var terrain_service: Node
var economy_system: Node
var build_system: Node
var command_system: Node
var selection_system: Node
var map_editor_system: Node
var editor_terrain_system: Node
var map_asset_placement_system: Node
var ui_layer: CanvasLayer
var unit_details_label: Label
var unit_details_body: Label
var minimap_panel: Panel
var headquarters: Node3D
var cannon_factory: Node3D
var active_resource_target: Node3D
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var unit_train_palette: GridContainer
var unit_train_palette_signature := ""
var behavior_buttons: Array[Button] = []
var save_map_button: Button
var load_map_button: Button
var map_picker_button: Button
var delete_map_asset_button: Button
var building_picker: OptionButton
var build_menu_button: Button
var build_button: Button
var build_palette: GridContainer
var map_maker_button: Button
var close_map_maker_button: Button
var map_asset_category_picker: OptionButton
var map_asset_palette_scroll: ScrollContainer
var map_asset_palette: GridContainer
var map_asset_ghost: Node3D
var building_ghost: Node3D
var ghost_valid := false
var pending_building_type := ""
var build_menu_open := false
var current_mode := AppMode.GAMEPLAY
var resource_bar: Panel
var map_select_overlay: Panel
var map_list: ItemList
var map_name_edit: LineEdit
var current_map_path := "res://maps/default_frontier.json"
var current_map_name := "Default Frontier"
var current_map_editable := false
var current_map_river := {}
var active_map_assets: Array[Dictionary] = []
var map_delete_mode := false
var map_brush_painting := false

func _ready() -> void:
	_rebuild_generated_content()
	if not Engine.is_editor_hint():
		call_deferred("_show_map_selector")

func _rebuild_generated_content() -> void:
	for child in get_children():
		if child.name == "GeneratedWorld" or child.name == "GeneratedUI":
			child.queue_free()
	selected_units.clear()

	world_root = Node3D.new()
	world_root.name = "GeneratedWorld"
	add_child(world_root)

	terrain_service = TerrainServiceScript.new()
	terrain_service.name = "TerrainService"
	world_root.add_child(terrain_service)

	economy_system = EconomySystemScript.new()
	economy_system.name = "EconomySystem"
	economy_system.resources_changed.connect(_on_economy_resources_changed)
	world_root.add_child(economy_system)

	build_system = BuildSystemScript.new()
	build_system.name = "BuildSystem"
	build_system.terrain_service = terrain_service
	world_root.add_child(build_system)

	command_system = CommandSystemScript.new()
	command_system.name = "CommandSystem"
	world_root.add_child(command_system)

	selection_system = SelectionSystemScript.new()
	selection_system.name = "SelectionSystem"
	world_root.add_child(selection_system)

	map_editor_system = MapEditorSystemScript.new()
	map_editor_system.name = "MapEditorSystem"
	world_root.add_child(map_editor_system)

	editor_terrain_system = EditorTerrainSystemScript.new()
	editor_terrain_system.name = "EditorTerrainSystem"
	editor_terrain_system.base_height_provider = Callable(self, "_terrain_height_without_editor")
	world_root.add_child(editor_terrain_system)
	if terrain_service != null:
		terrain_service.set("elevation_provider", Callable(editor_terrain_system, "height_at"))
		terrain_service.set("surface_provider", Callable(editor_terrain_system, "surface_at"))

	map_asset_placement_system = MapAssetPlacementSystemScript.new()
	map_asset_placement_system.name = "MapAssetPlacementSystem"
	map_asset_placement_system.world_root = world_root
	map_asset_placement_system.map_editor_system = map_editor_system
	map_asset_placement_system.editor_terrain_system = editor_terrain_system
	map_asset_placement_system.callbacks = _map_asset_placement_callbacks()
	world_root.add_child(map_asset_placement_system)

	_create_world()
	if not Engine.is_editor_hint():
		_create_ui()
		_create_sfx_player()
		_start_faction_music()

func _map_asset_placement_callbacks() -> Dictionary:
	return {
		"create_tree": Callable(self, "_create_tree"),
		"create_rock": Callable(self, "_create_rock"),
		"create_wood_resource": Callable(self, "_create_wood_resource"),
		"create_goldmine_resource": Callable(self, "_create_goldmine_resource"),
		"create_garden_resource": Callable(self, "_create_garden_resource"),
		"create_worker_unit": Callable(self, "_create_worker_unit"),
		"create_mexican_unit": Callable(self, "_create_mexican_unit"),
		"create_enemy_unit": Callable(self, "_create_enemy_unit"),
		"create_cannon_unit": Callable(self, "_create_cannon_unit"),
		"create_command_post": Callable(self, "_create_command_post_map_asset"),
		"create_completed_building": Callable(self, "_create_completed_mexican_building"),
		"create_building_preview": Callable(self, "_create_building_preview"),
		"with_terrain_height": Callable(self, "_with_terrain_height")
	}

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if _is_map_maker_mode():
		_handle_map_maker_input(event)
	else:
		_handle_gameplay_input(event)

func _handle_map_maker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and map_delete_mode:
			_try_delete_map_asset(event.position)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _has_pending_map_asset():
			map_brush_painting = _is_brush_map_asset(_pending_map_asset())
			_try_place_map_asset(event.position)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			map_brush_painting = false
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and map_delete_mode:
			map_brush_painting = false
			_set_map_delete_mode(false)
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _has_pending_map_asset():
			map_brush_painting = false
			_cancel_map_asset_placement()
			return

	if event is InputEventMouseMotion and _has_pending_map_asset():
		_update_map_asset_ghost(event.position)
		if map_brush_painting and _is_brush_map_asset(_pending_map_asset()):
			_try_place_map_asset(event.position, false)

func _handle_gameplay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if pending_building_type != "":
				if event.pressed:
					_try_place_pending_building(event.position)
				return

			if event.pressed:
				drag_start = event.position
				dragging = true
				selection_box.visible = true
				_update_selection_box(event.position)
			else:
				dragging = false
				selection_box.visible = false
				if drag_start.distance_to(event.position) < 8.0:
					_handle_left_click(event.position)
				else:
					_select_units_in_rect(drag_start, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if pending_building_type != "":
				_cancel_build_placement()
				return

			var clicked_resource: Node3D = _screen_to_resource(event.position)
			if clicked_resource != null and not selected_units.is_empty():
				_issue_gather(clicked_resource)
				return

			var clicked_enemy: Node3D = _screen_to_enemy(event.position)
			if clicked_enemy != null and not selected_units.is_empty():
				_issue_attack(clicked_enemy)
				return

			var point: Variant = _screen_to_ground(event.position)
			if point != null:
				_issue_move(point)

	if event is InputEventMouseMotion and dragging:
		_update_selection_box(event.position)
	elif event is InputEventMouseMotion and pending_building_type != "":
		_update_building_ghost(event.position)

func _is_map_maker_mode() -> bool:
	return current_mode == AppMode.MAP_MAKER

func _is_gameplay_mode() -> bool:
	return current_mode == AppMode.GAMEPLAY

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_training_queues(delta)
	_update_minimap()
	_refresh_selected_details()
	if pending_building_type != "":
		_update_building_ghost(get_viewport().get_mouse_position())
	if _has_pending_map_asset():
		_update_map_asset_ghost(get_viewport().get_mouse_position())

func _handle_left_click(screen_position: Vector2) -> void:
	var clicked_unit: Node = _screen_to_unit(screen_position)
	if clicked_unit != null:
		_select_single_unit(clicked_unit)
		return

	var clicked_building: Node3D = _screen_to_building(screen_position)
	if clicked_building != null:
		_select_building(clicked_building)
		return

	var clicked_resource: Node3D = _screen_to_resource(screen_position)
	if clicked_resource != null:
		if not selected_units.is_empty():
			_issue_gather(clicked_resource)
		else:
			_select_resource_node(clicked_resource)
		return

	var clicked_enemy: Node3D = _screen_to_enemy(screen_position)
	if clicked_enemy != null and not selected_units.is_empty():
		_issue_attack(clicked_enemy)
		return

	var point: Variant = _screen_to_ground(screen_position)
	if point != null and not selected_units.is_empty():
		_issue_move(point)

func _create_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.70, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.62, 0.68)
	environment.ambient_light_energy = 0.9
	world.environment = environment
	world_root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -36.0, 0.0)
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	world_root.add_child(sun)

	camera_rig = RTSCameraScript.new()
	camera_rig.position = Vector3(0.0, 0.0, 8.0)
	world_root.add_child(camera_rig)

	_create_ground()
	var map_data := _load_current_map_data()
	if terrain_service != null and terrain_service.has_method("configure_river"):
		terrain_service.configure_river(map_data.get("river", {}))
	if terrain_service != null and terrain_service.has_method("create_water_and_fords"):
		terrain_service.create_water_and_fords(world_root)
	_load_current_map_into_world(map_data)

func _create_ground() -> void:
	if terrain_service != null:
		terrain_service.create_base_terrain(world_root)
		return

func _load_current_map_data() -> Dictionary:
	if map_editor_system != null and map_editor_system.has_method("load_map_data"):
		var map_data: Dictionary = map_editor_system.load_map_data(current_map_path)
		current_map_name = str(map_data.get("name", current_map_name))
		current_map_river = map_data.get("river", {})
		return map_data
	return {"name": current_map_name, "assets": []}

func _load_current_map_into_world(map_data: Dictionary) -> void:
	active_map_assets.clear()
	var assets: Variant = map_data.get("assets", [])
	if typeof(assets) == TYPE_ARRAY:
		for asset in assets:
			if typeof(asset) == TYPE_DICTIONARY:
				active_map_assets.append(asset)
	if map_editor_system != null:
		map_editor_system.set("placed_assets", active_map_assets.duplicate(true))
		map_editor_system.set("map_name", current_map_name)
	for asset in active_map_assets:
		_place_map_definition_asset(asset)

func _place_map_definition_asset(asset: Dictionary) -> void:
	var asset_id := str(asset.get("id", ""))
	if asset_id == "":
		return
	match asset_id:
		"tree_cluster":
			_create_tree_cluster(_asset_position(asset), int(asset.get("count", 12)), asset_id, _asset_position(asset))
		"rock_cluster":
			_create_rock_cluster(_asset_position(asset), int(asset.get("count", 6)), asset_id, _asset_position(asset))
		_:
			var placed_node := _place_default_map_asset(asset_id, _asset_position(asset))
			if placed_node != null and asset.has("rotation_y"):
				placed_node.rotation_degrees.y = float(asset["rotation_y"])

func _asset_position(asset: Dictionary) -> Vector3:
	if map_editor_system != null and map_editor_system.has_method("asset_position"):
		return map_editor_system.asset_position(asset)
	return Vector3.ZERO

func _create_tree_cluster(center: Vector3, count: int, source_asset_id := "", source_position := Vector3.INF) -> void:
	for i in range(count):
		var offset := Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0))
		var tree := _create_tree(_with_terrain_height(center + offset))
		_tag_generated_map_source(tree, source_asset_id, source_position)

func _create_tree(position: Vector3) -> Node3D:
	var tree := ResourceNodeScript.new()
	tree.resource_type = "wood"
	tree.display_name = "Tree"
	tree.collision_size = Vector3(0.9, 2.4, 0.9)
	tree.visual_kind = ResourceNodeScript.VisualKind.SINGLE_TREE
	tree.remaining_gathers = 4
	tree.position = _with_terrain_height(position)
	tree.add_to_group("map_content")
	world_root.add_child(tree)
	return tree

func _create_rock_cluster(center: Vector3, count: int, source_asset_id := "", source_position := Vector3.INF) -> void:
	for i in range(count):
		var rock_position := _with_terrain_height(center + Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0)))
		var rock := _create_rock(rock_position)
		_tag_generated_map_source(rock, source_asset_id, source_position)

func _tag_generated_map_source(node: Node3D, asset_id: String, source_position: Vector3) -> void:
	if asset_id.is_empty() or source_position == Vector3.INF:
		return
	node.set_meta("map_asset_id", asset_id)
	node.set_meta("map_asset_position", source_position)

func _create_rock(position: Vector3) -> Node3D:
	var rock := StaticBody3D.new()
	rock.name = "Rock"
	rock.position = _with_terrain_height(position)
	rock.add_to_group("map_content")

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.85
	collision.shape = shape
	collision.position.y = 0.35
	rock.add_child(collision)

	var visual := MeshInstance3D.new()
	visual.name = "RockVisual"
	var mesh := SphereMesh.new()
	mesh.radius = randf_range(0.35, 0.9)
	mesh.height = mesh.radius * randf_range(0.7, 1.1)
	visual.mesh = mesh
	visual.position = Vector3(0.0, mesh.height * 0.35, 0.0)
	visual.scale = Vector3(randf_range(1.0, 1.6), randf_range(0.35, 0.65), randf_range(0.8, 1.4))
	visual.material_override = _make_material(Color(0.42, 0.43, 0.40))
	rock.add_child(visual)
	world_root.add_child(rock)
	return rock

func _create_building(position: Vector3, color: Color, label_text: String) -> Node3D:
	var building := StaticBody3D.new()
	building.name = label_text
	building.position = position
	building.add_to_group("buildings")
	building.set_meta("display_name", label_text)
	building.set_meta("building_type", _building_type_from_name(label_text))
	building.set_meta("sound_profile", _building_sound_profile(str(building.get_meta("building_type"))))
	var manual_energy := int(MexicanTechTreeScript.MANUAL_BUILDING_ENERGY_BY_NAME.get(label_text, 1000))
	building.set_meta("health", manual_energy)
	building.set_meta("max_health", manual_energy)
	_initialize_building_training_queue(building)
	world_root.add_child(building)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.4, 2.6, 3.6)
	collision.shape = shape
	collision.position.y = 1.3
	building.add_child(collision)

	_add_box_part(building, "Foundation", Vector3(4.2, 0.18, 3.4), Vector3(0.0, 0.09, 0.0), Color(0.36, 0.32, 0.27))
	_add_box_part(building, "Base", Vector3(4.0, 2.0, 3.2), Vector3(0.0, 0.18 + 1.0, 0.0), color)
	_add_box_part(building, "EaveTrim", Vector3(4.1, 0.12, 3.3), Vector3(0.0, 0.18 + 2.0 + 0.06, 0.0), Color(color.r * 0.6, color.g * 0.58, color.b * 0.54))
	_add_prism_part(building, "Roof", Vector3(4.7, 0.95, 3.9), Vector3(0.0, 0.18 + 2.0 + 0.12, 0.0), Color(0.30, 0.13, 0.08))
	_add_box_part(building, "DoorFrame", Vector3(0.82, 1.3, 0.05), Vector3(0.0, 0.18 + 0.65, -1.62), Color(0.78, 0.66, 0.45))
	_add_box_part(building, "Door", Vector3(0.68, 1.18, 0.06), Vector3(0.0, 0.18 + 0.59, -1.605), Color(0.20, 0.11, 0.05))
	for sign_x in [-1.0, 1.0]:
		_add_box_part(building, "WindowFrame", Vector3(0.04, 0.56, 0.62), Vector3(sign_x * 2.02, 0.18 + 1.1, 0.4), Color(0.78, 0.66, 0.45))
		_add_emissive_box_part(building, "Window", Vector3(0.05, 0.46, 0.50), Vector3(sign_x * 2.005, 0.18 + 1.1, 0.4), Color(0.22, 0.46, 0.62))
		_add_box_part(building, "WindowFrame2", Vector3(0.04, 0.56, 0.62), Vector3(sign_x * 2.02, 0.18 + 1.1, -0.6), Color(0.78, 0.66, 0.45))
		_add_emissive_box_part(building, "Window2", Vector3(0.05, 0.46, 0.50), Vector3(sign_x * 2.005, 0.18 + 1.1, -0.6), Color(0.22, 0.46, 0.62))
	_add_box_part(building, "Chimney", Vector3(0.45, 1.0, 0.45), Vector3(1.35, 0.18 + 2.5, 0.65), Color(0.50, 0.46, 0.42))

	var label := Label3D.new()
	label.text = label_text
	label.position = Vector3(0.0, 3.35, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 34
	label.modulate = Color(0.95, 0.86, 0.58)
	building.add_child(label)
	_add_building_selection_indicator(building, Vector3(4.8, 2.6, 4.0))

	return building

func _create_command_post_map_asset(position: Vector3) -> Node3D:
	return _create_building(position, Color(0.50, 0.33, 0.18), "Command Post")

func _create_cannon_factory(position: Vector3) -> Node3D:
	var factory := _create_building(position, Color(0.42, 0.29, 0.18), "Weapons Factory")

	var chimney := MeshInstance3D.new()
	var chimney_mesh := CylinderMesh.new()
	chimney_mesh.top_radius = 0.25
	chimney_mesh.bottom_radius = 0.35
	chimney_mesh.height = 2.4
	chimney.mesh = chimney_mesh
	chimney.position = Vector3(1.35, 3.3, 0.85)
	chimney.material_override = _make_material(Color(0.12, 0.10, 0.09))
	factory.add_child(chimney)

	var forge := MeshInstance3D.new()
	var forge_mesh := BoxMesh.new()
	forge_mesh.size = Vector3(1.2, 0.55, 1.0)
	forge.mesh = forge_mesh
	forge.position = Vector3(-1.05, 2.35, -1.0)
	forge.material_override = _make_material(Color(0.48, 0.10, 0.05))
	factory.add_child(forge)

	var label := Label3D.new()
	label.text = "Train Cannon: 100W 150G"
	label.position = Vector3(0.0, 4.05, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 22
	label.modulate = Color(0.88, 0.78, 0.55)
	factory.add_child(label)

	return factory

func _create_classic_cantina(position: Vector3) -> Node3D:
	var cantina := StaticBody3D.new()
	cantina.name = "Classic Cantina"
	cantina.position = position
	cantina.add_to_group("buildings")
	cantina.set_meta("display_name", "Classic Cantina")
	cantina.set_meta("building_type", "cantina")
	cantina.set_meta("sound_profile", _building_sound_profile("cantina"))
	cantina.set_meta("health", 900)
	cantina.set_meta("max_health", 900)
	world_root.add_child(cantina)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.2, 2.0, 3.2)
	collision.shape = shape
	collision.position.y = 1.0
	cantina.add_child(collision)

	_add_box_part(cantina, "AdobeBase", Vector3(4.2, 1.55, 3.2), Vector3(0.0, 0.78, 0.0), Color(0.48, 0.24, 0.15))
	_add_box_part(cantina, "Porch", Vector3(4.7, 0.3, 0.8), Vector3(0.0, 1.18, -1.85), Color(0.24, 0.14, 0.08))
	_add_box_part(cantina, "Roof", Vector3(4.8, 0.42, 3.6), Vector3(0.0, 1.78, 0.0), Color(0.16, 0.10, 0.06))

	var classic_sign := ClassicSpriteAssetScript.new()
	classic_sign.name = "ClassicSpriteSign"
	classic_sign.manifest_path = "res://assets/classic_buildings/mexican_cantina_sign.json"
	classic_sign.animation_name = "idle"
	classic_sign.position = Vector3(0.0, 2.45, -1.98)
	cantina.add_child(classic_sign)

	var label := Label3D.new()
	label.text = "Classic Cantina"
	label.position = Vector3(0.0, 3.15, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 26
	label.modulate = Color(0.95, 0.86, 0.58)
	cantina.add_child(label)
	_add_building_selection_indicator(cantina, Vector3(4.2, 2.0, 3.2))

	return cantina

func _create_modern_church_showcase(position: Vector3) -> Node3D:
	var church := StaticBody3D.new()
	church.name = "Modern Mexican Church"
	church.position = position
	church.add_to_group("buildings")
	church.set_meta("display_name", "Modern Mexican Church")
	church.set_meta("building_type", "church")
	church.set_meta("sound_profile", _building_sound_profile("church"))
	church.set_meta("health", MexicanTechTreeScript.BUILDINGS["church"]["energy"])
	church.set_meta("max_health", MexicanTechTreeScript.BUILDINGS["church"]["energy"])
	world_root.add_child(church)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.6, 3.6, 3.7)
	collision.shape = shape
	collision.position.y = 1.8
	church.add_child(collision)

	var visual := ModernChurchScene.instantiate() as Node3D
	visual.name = "ModernChurchVisual"
	church.add_child(visual)
	_add_building_selection_indicator(church, Vector3(4.6, 3.6, 3.7))
	return church

func _create_building_preview(building_type: String) -> Node3D:
	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
	var root := Node3D.new()
	root.name = "%s Preview" % definition["name"]

	var size: Vector3 = definition["size"]
	var footprint := MeshInstance3D.new()
	footprint.name = "PreviewFootprint"
	var footprint_mesh := BoxMesh.new()
	footprint_mesh.size = Vector3(size.x, 0.08, size.z)
	footprint.mesh = footprint_mesh
	footprint.position.y = 0.04
	footprint.material_override = _make_transparent_material(Color(0.25, 0.95, 0.40, 0.34))
	root.add_child(footprint)

	var shell := MeshInstance3D.new()
	shell.name = "PreviewShell"
	var shell_mesh := BoxMesh.new()
	shell_mesh.size = size
	shell.mesh = shell_mesh
	shell.position.y = size.y * 0.5
	shell.material_override = _make_transparent_material(Color(0.25, 0.95, 0.40, 0.18))
	root.add_child(shell)

	return root

func _create_completed_mexican_building(building_type: String, position: Vector3) -> Node3D:
	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
	var building := StaticBody3D.new()
	building.name = str(definition["name"])
	building.position = position
	building.add_to_group("buildings")
	building.set_meta("building_type", building_type)
	building.set_meta("display_name", definition["name"])
	building.set_meta("sound_profile", _building_sound_profile(building_type))
	building.set_meta("health", int(definition["energy"]))
	building.set_meta("max_health", int(definition["energy"]))
	_initialize_building_training_queue(building)
	world_root.add_child(building)

	var size: Vector3 = definition["size"]
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, maxf(size.y, 0.6), size.z)
	collision.shape = shape
	collision.position.y = maxf(size.y, 0.6) * 0.5
	building.add_child(collision)

	_add_custom_building_meshes(building, building_type)

	var label := Label3D.new()
	label.text = str(definition["name"])
	label.position = Vector3(0.0, size.y + 0.75, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 26
	label.modulate = Color(0.95, 0.86, 0.58)
	building.add_child(label)
	_add_building_selection_indicator(building, size)

	if building_type == "weapons_factory":
		cannon_factory = building

	return building

func _add_custom_building_meshes(parent: Node3D, building_type: String) -> void:
	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
	var size: Vector3 = definition["size"]
	var color: Color = definition["color"]
	var pitched := not (building_type in ["field", "wall", "wharf", "tower"])

	if pitched:
		var wall_height := size.y * 0.72
		_add_box_part(parent, "Foundation", Vector3(size.x + 0.18, 0.16, size.z + 0.18), Vector3(0.0, 0.08, 0.0), Color(0.36, 0.32, 0.27))
		_add_box_part(parent, "Base", Vector3(size.x, wall_height, size.z), Vector3(0.0, 0.16 + wall_height * 0.5, 0.0), color)
		var trim_color := Color(color.r * 0.62, color.g * 0.6, color.b * 0.56)
		_add_box_part(parent, "EaveTrim", Vector3(size.x + 0.05, 0.10, size.z + 0.05), Vector3(0.0, 0.16 + wall_height + 0.05, 0.0), trim_color)
		_add_prism_part(parent, "Roof", Vector3(size.x + 0.35, 0.68, size.z + 0.35), Vector3(0.0, 0.16 + wall_height + 0.10, 0.0), Color(0.30, 0.13, 0.08))
		var door_h := minf(1.05, wall_height * 0.72)
		_add_box_part(parent, "Door", Vector3(0.55, door_h, 0.06), Vector3(0.0, 0.16 + door_h * 0.5, -size.z * 0.5 - 0.005), Color(0.20, 0.11, 0.05))
		_add_box_part(parent, "DoorFrame", Vector3(0.70, door_h + 0.12, 0.03), Vector3(0.0, 0.16 + (door_h + 0.12) * 0.5, -size.z * 0.5 - 0.02), Color(0.78, 0.66, 0.45))
		if size.x > 3.0:
			for sign_x in [-1.0, 1.0]:
				_add_box_part(parent, "WindowFrame", Vector3(0.03, 0.50, 0.52), Vector3(sign_x * (size.x * 0.5 + 0.02), 0.16 + wall_height * 0.62, size.z * 0.28), Color(0.78, 0.66, 0.45))
				_add_emissive_box_part(parent, "Window", Vector3(0.05, 0.40, 0.42), Vector3(sign_x * (size.x * 0.5 + 0.005), 0.16 + wall_height * 0.62, size.z * 0.28), Color(0.20, 0.44, 0.58))
		_add_box_part(parent, "FrontWindowFrame", Vector3(0.62, 0.46, 0.03), Vector3(size.x * 0.30, 0.16 + wall_height * 0.62, -size.z * 0.5 - 0.02), Color(0.78, 0.66, 0.45))
		_add_emissive_box_part(parent, "FrontWindow", Vector3(0.52, 0.36, 0.05), Vector3(size.x * 0.30, 0.16 + wall_height * 0.62, -size.z * 0.5 - 0.005), Color(0.20, 0.44, 0.58))
	else:
		_add_box_part(parent, "Base", Vector3(size.x, size.y * 0.72, size.z), Vector3(0.0, size.y * 0.36, 0.0), color)
		_add_box_part(parent, "Roof", Vector3(size.x + 0.35, 0.42, size.z + 0.35), Vector3(0.0, size.y * 0.78, 0.0), Color(0.16, 0.10, 0.06))

	match building_type:
		"house":
			_add_box_part(parent, "Porch", Vector3(size.x * 0.82, 0.25, 0.55), Vector3(0.0, 0.32, -size.z * 0.58), Color(0.30, 0.18, 0.09))
		"hacienda":
			_add_box_part(parent, "CourtyardWall", Vector3(size.x * 0.9, 0.55, 0.28), Vector3(0.0, 0.38, -size.z * 0.68), Color(0.78, 0.64, 0.42))
			_add_box_part(parent, "Stable", Vector3(1.1, 1.0, 1.4), Vector3(size.x * 0.34, 0.5, size.z * 0.22), Color(0.36, 0.22, 0.11))
		"cantina":
			_add_box_part(parent, "Sign", Vector3(1.5, 0.34, 0.12), Vector3(0.0, size.y + 0.22, -size.z * 0.54), Color(0.75, 0.54, 0.24))
		"butcher":
			_add_box_part(parent, "Smokehouse", Vector3(0.9, 1.3, 0.9), Vector3(size.x * 0.28, 0.65, size.z * 0.22), Color(0.26, 0.12, 0.08))
		"barracks":
			_add_box_part(parent, "DrillYard", Vector3(size.x * 0.85, 0.14, 1.4), Vector3(0.0, 0.08, -size.z * 0.72), Color(0.24, 0.22, 0.16))
		"gold_warehouse":
			_add_box_part(parent, "Vault", Vector3(size.x * 0.58, size.y * 0.55, size.z * 0.45), Vector3(0.0, size.y * 0.42, 0.0), Color(0.72, 0.60, 0.24))
		"finca":
			for x in [-1.2, 0.0, 1.2]:
				_add_box_part(parent, "FieldRow", Vector3(0.28, 0.22, size.z * 0.82), Vector3(x, 0.18, -size.z * 0.62), Color(0.16, 0.44, 0.16))
		"field":
			for x in [-1.2, -0.4, 0.4, 1.2]:
				_add_box_part(parent, "CropRow", Vector3(0.22, 0.22, size.z * 0.9), Vector3(x, 0.2, 0.0), Color(0.18, 0.54, 0.18))
		"sawmill":
			_add_cylinder_part(parent, "SawWheel", 0.65, 0.20, Vector3(size.x * 0.38, 0.9, -size.z * 0.42), Color(0.58, 0.50, 0.40), Vector3(90.0, 0.0, 0.0))
			_add_box_part(parent, "LogPile", Vector3(1.8, 0.35, 0.75), Vector3(-size.x * 0.3, 0.28, -size.z * 0.58), Color(0.33, 0.18, 0.08))
		"trading_post":
			_add_box_part(parent, "Awning", Vector3(size.x * 0.9, 0.20, 0.85), Vector3(0.0, size.y * 0.72, -size.z * 0.62), Color(0.72, 0.52, 0.22))
		"weapons_factory":
			_add_cylinder_part(parent, "Chimney", 0.32, 2.25, Vector3(size.x * 0.28, size.y + 0.7, size.z * 0.25), Color(0.10, 0.09, 0.08))
			_add_box_part(parent, "ForgeGlow", Vector3(1.15, 0.45, 0.95), Vector3(-size.x * 0.25, size.y * 0.78, -size.z * 0.25), Color(0.55, 0.12, 0.05))
		"wall":
			_add_box_part(parent, "PalisadeTop", Vector3(size.x, 0.28, size.z * 0.7), Vector3(0.0, size.y + 0.05, 0.0), Color(0.22, 0.14, 0.07))
		"tower":
			_add_box_part(parent, "WatchDeck", Vector3(size.x * 1.25, 0.42, size.z * 1.25), Vector3(0.0, size.y * 0.88, 0.0), Color(0.20, 0.13, 0.07))
		"wharf":
			for x in [-1.8, -0.6, 0.6, 1.8]:
				_add_box_part(parent, "PierPlank", Vector3(0.35, 0.22, size.z), Vector3(x, 0.25, 0.0), Color(0.24, 0.15, 0.07))
		"church":
			_add_box_part(parent, "BellTower", Vector3(1.05, size.y * 1.05, 1.05), Vector3(-size.x * 0.26, size.y * 0.52, -size.z * 0.18), Color(0.58, 0.54, 0.44))
			_add_box_part(parent, "Cross", Vector3(0.16, 0.9, 0.16), Vector3(-size.x * 0.26, size.y + 0.9, -size.z * 0.18), Color(0.86, 0.78, 0.48))
		"mission":
			_add_box_part(parent, "CloisterWing", Vector3(size.x * 0.32, size.y * 0.72, size.z), Vector3(size.x * 0.34, size.y * 0.36, 0.0), Color(0.45, 0.38, 0.28))
		"fort":
			for x in [-size.x * 0.42, size.x * 0.42]:
				for z in [-size.z * 0.42, size.z * 0.42]:
					_add_box_part(parent, "Bastion", Vector3(1.25, size.y * 0.9, 1.25), Vector3(x, size.y * 0.45, z), Color(0.24, 0.20, 0.14))

func _add_box_part(parent: Node3D, part_name: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = position
	part.material_override = _make_material(color)
	parent.add_child(part)
	return part

func _add_emissive_box_part(parent: Node3D, part_name: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = position
	part.material_override = _emissive_material(color)
	parent.add_child(part)
	return part

func _add_prism_part(parent: Node3D, part_name: String, size: Vector3, position: Vector3, color: Color, rotation := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = 0.5
	part.mesh = mesh
	part.position = position
	part.rotation_degrees = rotation
	part.material_override = _make_material(color)
	parent.add_child(part)
	return part

func _emissive_material(color: Color) -> StandardMaterial3D:
	var material := _make_material(color)
	material.emission_enabled = true
	material.emission = Color(color.r * 0.45, color.g * 0.45, color.b * 0.45)
	material.emission_energy_multiplier = 0.65
	material.roughness = 0.45
	return material

func _add_cylinder_part(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, color: Color, rotation := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	part.mesh = mesh
	part.position = position
	part.rotation_degrees = rotation
	part.material_override = _make_material(color)
	parent.add_child(part)
	return part

func _add_building_selection_indicator(parent: Node3D, size: Vector3) -> void:
	var indicator := MeshInstance3D.new()
	indicator.name = "SelectionIndicator"
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(size.x, size.z) * 0.52
	mesh.outer_radius = maxf(size.x, size.z) * 0.58
	indicator.mesh = mesh
	indicator.position.y = 0.07
	indicator.material_override = _make_material(Color(0.96, 0.85, 0.30))
	indicator.visible = false
	parent.add_child(indicator)

func _create_resource_assets() -> void:
	_seed_default_tree_grove(Vector3(-23.0, 0.0, -12.0))
	_place_default_map_asset("gold_mine", Vector3(-17.0, 0.0, -4.0))
	_place_default_map_asset("gold_mine", Vector3(-20.0, 0.0, 10.0))
	_create_garden_resource(_with_terrain_height(Vector3(-18.0, 0.0, 17.0)))

func _seed_default_tree_grove(center: Vector3) -> void:
	var positions: Array[Vector3] = []
	var attempts := 0
	while positions.size() < 9 and attempts < 80:
		attempts += 1
		var angle := randf() * TAU
		var dist := sqrt(randf()) * 3.0
		var candidate := center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var too_close := false
		for existing in positions:
			if existing.distance_to(candidate) < 1.0:
				too_close = true
				break
		if too_close:
			continue
		positions.append(candidate)
		_create_tree(_with_terrain_height(candidate))

func _create_wood_resource(position: Vector3) -> Node3D:
	var resource := _create_resource_node("wood", "Wood Stand", _with_terrain_height(position), Vector3(4.5, 2.4, 4.5), RESOURCE_VISUAL_WOOD)
	resource.remaining_gathers = 8
	return resource

func _create_goldmine_resource(position: Vector3) -> Node3D:
	return _create_resource_node("gold", "Gold Mine", _with_terrain_height(position), Vector3(4.8, 2.0, 3.2), RESOURCE_VISUAL_GOLD)

func _create_garden_resource(position: Vector3) -> Node3D:
	return _create_resource_node("food", "Garden", _with_terrain_height(position), Vector3(5.4, 0.5, 4.2), RESOURCE_VISUAL_GARDEN)

func _create_resource_node(resource_type: String, display_name: String, position: Vector3, collision_size: Vector3, visual_kind: int) -> Node3D:
	var resource := ResourceNodeScript.new()
	resource.resource_type = resource_type
	resource.display_name = display_name
	resource.collision_size = collision_size
	resource.visual_kind = visual_kind
	resource.position = position
	world_root.add_child(resource)
	return resource

func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "GeneratedUI"
	add_child(ui_layer)

	_create_resource_bar()
	_create_bottom_hud()

	selection_box = ColorRect.new()
	selection_box.color = Color(0.95, 0.82, 0.25, 0.20)
	selection_box.visible = false
	ui_layer.add_child(selection_box)

	var border := Panel.new()
	border.name = "SelectionBorder"
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.add_child(border)
	border.set_anchors_preset(Control.PRESET_FULL_RECT)

func _start_faction_music() -> void:
	if is_instance_valid(music_player):
		if not music_player.playing:
			music_player.play()
		return
	var theme_bytes := FileAccess.get_file_as_bytes(MEXICAN_FACTION_THEME_PATH)
	if theme_bytes.is_empty():
		push_warning("Mexican faction music could not be loaded: %s" % MEXICAN_FACTION_THEME_PATH)
		return

	var theme := AudioStreamMP3.new()
	theme.data = theme_bytes
	theme.loop = true

	music_player = AudioStreamPlayer.new()
	music_player.name = "MexicanFactionMusic"
	music_player.stream = theme
	music_player.volume_db = -12.0
	add_child(music_player)
	music_player.play()

func _create_sfx_player() -> void:
	if is_instance_valid(sfx_player):
		return
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "GameplaySFX"
	sfx_player.volume_db = -2.0
	add_child(sfx_player)

func _play_sfx(audio_path: String) -> void:
	if Engine.is_editor_hint() or audio_path.is_empty():
		return
	if sfx_player == null:
		_create_sfx_player()
	var stream := _load_audio_stream(audio_path)
	if stream != null:
		sfx_player.stream = stream
		sfx_player.play()

func _load_audio_stream(audio_path: String) -> AudioStream:
	if audio_path.is_empty():
		return null
	if audio_path.get_extension().to_lower() == "wav":
		return AudioStreamWAV.load_from_file(audio_path)
	if audio_path.get_extension().to_lower() == "mp3":
		var audio_bytes := FileAccess.get_file_as_bytes(audio_path)
		if audio_bytes.is_empty():
			return null
		var stream := AudioStreamMP3.new()
		stream.data = audio_bytes
		return stream
	return load(audio_path) as AudioStream

func _unit_sound_profile(overrides: Dictionary) -> Dictionary:
	return _merged_profile(DEFAULT_UNIT_SOUND_PROFILE, overrides)

func _building_sound_profile(building_type: String) -> Dictionary:
	var overrides: Dictionary = BUILDING_SOUND_OVERRIDES.get(building_type, {})
	return _merged_profile(DEFAULT_BUILDING_SOUND_PROFILE, overrides)

func _merged_profile(defaults: Dictionary, overrides: Dictionary) -> Dictionary:
	var profile := defaults.duplicate(true)
	for key in overrides.keys():
		var value: Variant = overrides[key]
		if value is Dictionary and profile.get(key, {}) is Dictionary:
			var nested: Dictionary = profile.get(key, {}).duplicate(true)
			for nested_key in value.keys():
				nested[nested_key] = value[nested_key]
			profile[key] = nested
		else:
			profile[key] = value
	return profile

func _building_sound_path(building: Node3D, slot: String) -> String:
	if not is_instance_valid(building):
		return ""
	var profile: Dictionary = building.get_meta("sound_profile", _building_sound_profile(str(building.get_meta("building_type", ""))))
	return str(profile.get(slot, ""))

func _create_resource_bar() -> void:
	resource_bar = ResourceBarScript.new()
	resource_bar.name = "ResourceBar"
	resource_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	resource_bar.offset_left = 0.0
	resource_bar.offset_top = 0.0
	resource_bar.offset_right = 0.0
	resource_bar.offset_bottom = 34.0
	ui_layer.add_child(resource_bar)
	if resource_bar.has_method("configure") and economy_system != null and economy_system.has_method("snapshot"):
		resource_bar.configure(economy_system.snapshot())

func _create_bottom_hud() -> void:
	var details_panel := Panel.new()
	details_panel.name = "UnitDetailsPanel"
	details_panel.anchor_left = 0.0
	details_panel.anchor_top = 1.0
	details_panel.anchor_right = 1.0
	details_panel.anchor_bottom = 1.0
	details_panel.offset_left = 0.0
	details_panel.offset_top = -190.0
	details_panel.offset_right = -330.0
	details_panel.offset_bottom = 0.0
	details_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.15, 0.09, 0.045, 0.88), Color(0.34, 0.21, 0.11, 0.94)))
	ui_layer.add_child(details_panel)

	var detail_title := Label.new()
	detail_title.text = "No unit selected"
	detail_title.position = Vector2(18.0, 14.0)
	detail_title.add_theme_font_size_override("font_size", 20)
	detail_title.add_theme_color_override("font_color", Color(0.95, 0.89, 0.74))
	details_panel.add_child(detail_title)
	unit_details_label = detail_title

	var detail_body := Label.new()
	detail_body.text = "Left-click a unit, then left-click the ground to move it."
	detail_body.position = Vector2(18.0, 52.0)
	detail_body.size = Vector2(320.0, 84.0)
	detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_body.add_theme_font_size_override("font_size", 15)
	detail_body.add_theme_color_override("font_color", Color(0.82, 0.76, 0.62))
	details_panel.add_child(detail_body)
	unit_details_body = detail_body

	var command_row := HBoxContainer.new()
	command_row.position = Vector2(18.0, 142.0)
	command_row.add_theme_constant_override("separation", 10)
	details_panel.add_child(command_row)
	for command_name in ["Move", "Stop", "Gather"]:
		command_row.add_child(_make_command_button(command_name))

	for mode in ["Passive", "Defensive", "Aggressive"]:
		var behavior_button := Button.new()
		behavior_button.text = mode
		behavior_button.custom_minimum_size = Vector2(98.0, 42.0)
		behavior_button.disabled = true
		behavior_button.pressed.connect(func() -> void:
			_set_selected_behavior(mode.to_lower())
		)
		behavior_buttons.append(behavior_button)
		command_row.add_child(behavior_button)

	build_menu_button = Button.new()
	build_menu_button.text = "Build"
	build_menu_button.custom_minimum_size = Vector2(88.0, 42.0)
	build_menu_button.toggle_mode = true
	build_menu_button.visible = false
	build_menu_button.toggled.connect(_on_build_menu_toggled)
	command_row.add_child(build_menu_button)

	map_maker_button = Button.new()
	map_maker_button.text = "Map Maker"
	map_maker_button.custom_minimum_size = Vector2(112.0, 42.0)
	map_maker_button.toggle_mode = true
	map_maker_button.toggled.connect(_on_map_maker_toggled)
	command_row.add_child(map_maker_button)

	save_map_button = Button.new()
	save_map_button.text = "Save Map"
	save_map_button.custom_minimum_size = Vector2(96.0, 42.0)
	save_map_button.pressed.connect(_on_save_map_pressed)
	command_row.add_child(save_map_button)

	load_map_button = Button.new()
	load_map_button.text = "Load Map"
	load_map_button.custom_minimum_size = Vector2(96.0, 42.0)
	load_map_button.pressed.connect(_on_load_map_pressed)
	command_row.add_child(load_map_button)

	delete_map_asset_button = Button.new()
	delete_map_asset_button.text = "Delete"
	delete_map_asset_button.custom_minimum_size = Vector2(86.0, 42.0)
	delete_map_asset_button.toggle_mode = true
	delete_map_asset_button.toggled.connect(_set_map_delete_mode)
	command_row.add_child(delete_map_asset_button)

	map_picker_button = Button.new()
	map_picker_button.text = "Maps"
	map_picker_button.custom_minimum_size = Vector2(76.0, 42.0)
	map_picker_button.pressed.connect(_show_map_selector)
	command_row.add_child(map_picker_button)

	close_map_maker_button = Button.new()
	close_map_maker_button.text = "Close Map"
	close_map_maker_button.custom_minimum_size = Vector2(104.0, 42.0)
	close_map_maker_button.pressed.connect(_close_map_maker)
	command_row.add_child(close_map_maker_button)

	build_palette = GridContainer.new()
	build_palette.name = "BuildPalette"
	build_palette.columns = 8
	build_palette.position = Vector2(360.0, 12.0)
	build_palette.add_theme_constant_override("h_separation", 6)
	build_palette.add_theme_constant_override("v_separation", 6)
	details_panel.add_child(build_palette)
	_create_build_palette_buttons()
	_update_build_palette_visibility()

	unit_train_palette = GridContainer.new()
	unit_train_palette.name = "UnitTrainPalette"
	unit_train_palette.columns = 4
	unit_train_palette.position = Vector2(360.0, 100.0)
	unit_train_palette.add_theme_constant_override("h_separation", 6)
	unit_train_palette.add_theme_constant_override("v_separation", 6)
	details_panel.add_child(unit_train_palette)
	_update_unit_train_palette()

	map_asset_category_picker = OptionButton.new()
	map_asset_category_picker.name = "MapAssetCategoryPicker"
	map_asset_category_picker.position = Vector2(360.0, 12.0)
	map_asset_category_picker.custom_minimum_size = Vector2(210.0, 32.0)
	map_asset_category_picker.item_selected.connect(_on_map_asset_category_selected)
	details_panel.add_child(map_asset_category_picker)
	_create_map_asset_categories()

	map_asset_palette_scroll = ScrollContainer.new()
	map_asset_palette_scroll.name = "MapAssetPaletteScroll"
	map_asset_palette_scroll.position = Vector2(360.0, 48.0)
	map_asset_palette_scroll.size = Vector2(610.0, 126.0)
	map_asset_palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_asset_palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	details_panel.add_child(map_asset_palette_scroll)

	map_asset_palette = GridContainer.new()
	map_asset_palette.name = "MapAssetPalette"
	map_asset_palette.columns = 6
	map_asset_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_asset_palette.add_theme_constant_override("h_separation", 6)
	map_asset_palette.add_theme_constant_override("v_separation", 6)
	map_asset_palette_scroll.add_child(map_asset_palette)
	_create_map_asset_palette_buttons()
	_update_map_asset_palette_visibility()
	_update_mode_control_visibility()

	minimap_panel = MinimapPanelScript.new()
	minimap_panel.name = "MiniMapPanel"
	minimap_panel.anchor_left = 1.0
	minimap_panel.anchor_top = 1.0
	minimap_panel.anchor_right = 1.0
	minimap_panel.anchor_bottom = 1.0
	minimap_panel.offset_left = -320.0
	minimap_panel.offset_top = -240.0
	minimap_panel.offset_right = -12.0
	minimap_panel.offset_bottom = -12.0
	ui_layer.add_child(minimap_panel)

func _make_command_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(84.0, 42.0)
	button.disabled = true
	return button

func _create_map_asset_categories() -> void:
	if map_asset_category_picker == null:
		return
	map_asset_category_picker.clear()
	var categories: Array = []
	if map_editor_system != null and map_editor_system.has_method("asset_categories"):
		categories = map_editor_system.asset_categories()
	for category in categories:
		map_asset_category_picker.add_item(str(category.get("label", "Category")))
		map_asset_category_picker.set_item_metadata(map_asset_category_picker.item_count - 1, str(category.get("id", "")))
	if map_asset_category_picker.item_count > 0:
		map_asset_category_picker.select(0)

func _on_map_asset_category_selected(_index: int) -> void:
	_create_map_asset_palette_buttons()
	_cancel_map_asset_placement()

func _selected_map_asset_category() -> String:
	if map_asset_category_picker == null or map_asset_category_picker.item_count == 0:
		return ""
	return str(map_asset_category_picker.get_item_metadata(map_asset_category_picker.selected))

func _create_map_asset_palette_buttons() -> void:
	if map_asset_palette == null:
		return
	for child in map_asset_palette.get_children():
		child.queue_free()

	var assets: Array = []
	if map_editor_system != null:
		if map_editor_system.has_method("assets_for_category"):
			assets = map_editor_system.assets_for_category(_selected_map_asset_category())
		elif map_editor_system.has_method("asset_definitions"):
			assets = map_editor_system.asset_definitions()

	for asset in assets:
		var button := Button.new()
		button.text = str(asset["label"])
		button.icon = _make_map_asset_icon(asset)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.tooltip_text = str(asset["tip"])
		button.custom_minimum_size = Vector2(92.0, 64.0)
		button.pressed.connect(func() -> void:
			_begin_map_asset_placement(str(asset["id"]))
		)
		map_asset_palette.add_child(button)

func _make_map_asset_icon(asset: Dictionary) -> Texture2D:
	if str(asset.get("icon_shape", "")) == "texture":
		var texture_path := str(asset.get("texture_path", ""))
		if ResourceLoader.exists(texture_path):
			var texture := load(texture_path) as Texture2D
			if texture != null:
				return texture

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.11, 0.09, 0.06, 0.92))
	var color: Color = asset.get("icon_color", Color(0.75, 0.65, 0.42))
	var shape := str(asset.get("icon_shape", "building"))
	match shape:
		"tree":
			_fill_rect(image, Rect2i(14, 18, 4, 8), Color(0.30, 0.18, 0.08))
			_fill_circle(image, Vector2i(16, 13), 9, color)
		"rock":
			_fill_circle(image, Vector2i(12, 18), 7, color)
			_fill_circle(image, Vector2i(20, 16), 8, color.lightened(0.12))
			_fill_rect(image, Rect2i(8, 19, 18, 5), color.darkened(0.12))
		"logs":
			_fill_rect(image, Rect2i(7, 12, 18, 5), color)
			_fill_rect(image, Rect2i(5, 18, 22, 5), color.lightened(0.12))
			_fill_circle(image, Vector2i(8, 14), 3, Color(0.68, 0.48, 0.24))
			_fill_circle(image, Vector2i(8, 20), 3, Color(0.68, 0.48, 0.24))
		"mine":
			_fill_rect(image, Rect2i(7, 18, 18, 7), Color(0.32, 0.30, 0.26))
			_fill_circle(image, Vector2i(16, 16), 10, Color(0.42, 0.40, 0.34))
			_fill_rect(image, Rect2i(13, 16, 6, 9), Color(0.08, 0.07, 0.06))
			_fill_circle(image, Vector2i(22, 10), 3, color)
		"texture":
			_fill_rect(image, Rect2i(6, 7, 20, 18), color.darkened(0.10))
			for y in [10, 16, 22]:
				_fill_rect(image, Rect2i(7, y, 18, 2), color.lightened(0.18))
			for x in [11, 18]:
				_fill_rect(image, Rect2i(x, 8, 2, 16), color.darkened(0.18))
		"plateau":
			_fill_rect(image, Rect2i(6, 17, 20, 8), color.darkened(0.25))
			_fill_rect(image, Rect2i(8, 10, 16, 8), color)
			_fill_rect(image, Rect2i(10, 7, 12, 4), color.lightened(0.12))
		"ramp":
			for y in range(9, 25):
				var width := y - 6
				_fill_rect(image, Rect2i(7, y, mini(width, 19), 1), color)
			_fill_rect(image, Rect2i(7, 24, 20, 2), color.darkened(0.18))
		"field":
			_fill_rect(image, Rect2i(6, 9, 20, 16), color.darkened(0.10))
			for x in [10, 16, 22]:
				_fill_rect(image, Rect2i(x, 10, 2, 14), color.lightened(0.22))
		"unit":
			_fill_circle(image, Vector2i(16, 10), 5, color.lightened(0.20))
			_fill_rect(image, Rect2i(11, 16, 10, 10), color)
		"cavalry":
			_fill_rect(image, Rect2i(8, 17, 17, 7), color)
			_fill_circle(image, Vector2i(13, 11), 4, color.lightened(0.20))
			_fill_rect(image, Rect2i(19, 11, 4, 7), color.darkened(0.18))
		"cannon":
			_fill_rect(image, Rect2i(9, 15, 15, 5), color)
			_fill_rect(image, Rect2i(19, 12, 8, 3), color.lightened(0.15))
			_fill_circle(image, Vector2i(12, 23), 4, Color(0.05, 0.05, 0.05))
			_fill_circle(image, Vector2i(23, 23), 4, Color(0.05, 0.05, 0.05))
		"wall":
			for x in [6, 12, 18, 24]:
				_fill_rect(image, Rect2i(x, 10, 5, 16), color)
		"tower":
			_fill_rect(image, Rect2i(11, 9, 10, 17), color)
			_fill_rect(image, Rect2i(8, 7, 16, 5), color.lightened(0.10))
		"church":
			_fill_rect(image, Rect2i(8, 14, 17, 11), color)
			_fill_rect(image, Rect2i(11, 9, 6, 7), color.lightened(0.10))
			_fill_rect(image, Rect2i(13, 5, 2, 7), Color(0.86, 0.78, 0.48))
			_fill_rect(image, Rect2i(11, 7, 6, 2), Color(0.86, 0.78, 0.48))
		"fort":
			_fill_rect(image, Rect2i(7, 11, 18, 15), color)
			_fill_rect(image, Rect2i(5, 8, 6, 7), color.lightened(0.10))
			_fill_rect(image, Rect2i(21, 8, 6, 7), color.lightened(0.10))
		"dock":
			for x in [8, 14, 20]:
				_fill_rect(image, Rect2i(x, 8, 3, 18), color)
			_fill_rect(image, Rect2i(6, 18, 21, 4), color.lightened(0.10))
		_:
			_fill_rect(image, Rect2i(8, 13, 16, 12), color)
			_fill_rect(image, Rect2i(11, 9, 10, 5), color.lightened(0.12))
	_add_icon_border(image)
	return ImageTexture.create_from_image(image)

func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)

func _fill_circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	var radius_squared := radius * radius
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy <= radius_squared:
				image.set_pixel(x, y, color)

func _add_icon_border(image: Image) -> void:
	var border_color := Color(0.86, 0.74, 0.46, 0.82)
	for x in range(image.get_width()):
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, image.get_height() - 1, border_color)
	for y in range(image.get_height()):
		image.set_pixel(0, y, border_color)
		image.set_pixel(image.get_width() - 1, y, border_color)

func _update_map_asset_palette_visibility() -> void:
	if map_asset_category_picker != null:
		map_asset_category_picker.visible = _is_map_maker_mode()
	if map_asset_palette_scroll != null:
		map_asset_palette_scroll.visible = _is_map_maker_mode()
	if map_asset_palette != null:
		map_asset_palette.visible = _is_map_maker_mode()

func _update_mode_control_visibility() -> void:
	if save_map_button != null:
		save_map_button.visible = _is_map_maker_mode()
	if load_map_button != null:
		load_map_button.visible = _is_map_maker_mode()
	if delete_map_asset_button != null:
		delete_map_asset_button.visible = _is_map_maker_mode()
	if map_picker_button != null:
		map_picker_button.visible = true
	if close_map_maker_button != null:
		close_map_maker_button.visible = _is_map_maker_mode()
	if unit_train_palette != null and _is_map_maker_mode():
		unit_train_palette.visible = false

func _on_save_map_pressed() -> void:
	if map_editor_system == null or not map_editor_system.has_method("save_map"):
		return
	var save_path := current_map_path
	if not current_map_editable:
		save_path = map_editor_system.make_user_map_path(current_map_name)
	var ok: bool = map_editor_system.save_map(save_path, current_map_name, current_map_river)
	if ok:
		current_map_path = save_path
		current_map_editable = true
	if unit_details_label != null:
		unit_details_label.text = "Map Maker"
	if unit_details_body != null:
		if ok:
			unit_details_body.text = "Map saved to %s." % current_map_path
		else:
			unit_details_body.text = "Map save failed."

func _on_load_map_pressed() -> void:
	_show_map_selector()

func _show_map_selector() -> void:
	if ui_layer == null or map_editor_system == null:
		return
	if is_instance_valid(map_select_overlay):
		map_select_overlay.queue_free()
	map_select_overlay = Panel.new()
	map_select_overlay.name = "MapSelectOverlay"
	map_select_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_select_overlay.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.05, 0.035, 0.92), Color(0.54, 0.39, 0.18, 0.95)))
	ui_layer.add_child(map_select_overlay)

	var panel := VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260.0
	panel.offset_top = -250.0
	panel.offset_right = 260.0
	panel.offset_bottom = 250.0
	panel.add_theme_constant_override("separation", 10)
	map_select_overlay.add_child(panel)

	var title := Label.new()
	title.text = "Choose Map"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.96, 0.89, 0.68))
	panel.add_child(title)

	map_list = ItemList.new()
	map_list.custom_minimum_size = Vector2(520.0, 280.0)
	map_list.item_activated.connect(func(_index: int) -> void:
		_on_play_selected_map_pressed()
	)
	panel.add_child(map_list)
	_populate_map_list()

	map_name_edit = LineEdit.new()
	map_name_edit.placeholder_text = "New map name"
	map_name_edit.text = "New Map"
	panel.add_child(map_name_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(_make_map_dialog_button("Play", _on_play_selected_map_pressed))
	row.add_child(_make_map_dialog_button("Create New", _on_create_new_map_pressed))
	row.add_child(_make_map_dialog_button("Save Current", _on_save_map_pressed))
	row.add_child(_make_map_dialog_button("Close", _close_map_selector))

func _populate_map_list() -> void:
	if map_list == null or map_editor_system == null:
		return
	map_list.clear()
	var entries: Array = map_editor_system.map_entries()
	for entry in entries:
		var label := str(entry.get("name", "Map"))
		if bool(entry.get("editable", false)):
			label += "  [user]"
		map_list.add_item(label)
		map_list.set_item_metadata(map_list.item_count - 1, entry)
		if str(entry.get("path", "")) == current_map_path:
			map_list.select(map_list.item_count - 1)
	if map_list.item_count > 0 and map_list.get_selected_items().is_empty():
		map_list.select(0)

func _make_map_dialog_button(label_text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(120.0, 38.0)
	button.pressed.connect(action)
	return button

func _on_play_selected_map_pressed() -> void:
	if map_list == null:
		return
	var selection := map_list.get_selected_items()
	if selection.is_empty():
		return
	var entry: Dictionary = map_list.get_item_metadata(selection[0])
	current_map_path = str(entry.get("path", current_map_path))
	current_map_name = str(entry.get("name", current_map_name))
	current_map_editable = bool(entry.get("editable", false))
	_close_map_selector()
	_rebuild_generated_content()

func _on_create_new_map_pressed() -> void:
	if map_editor_system == null:
		return
	var new_name := "New Map"
	if map_name_edit != null and not map_name_edit.text.strip_edges().is_empty():
		new_name = map_name_edit.text.strip_edges()
	current_map_name = new_name
	current_map_path = map_editor_system.make_user_map_path(current_map_name)
	current_map_editable = true
	map_editor_system.new_empty_map(current_map_name)
	map_editor_system.save_map(current_map_path, current_map_name, current_map_river)
	_close_map_selector()
	_rebuild_generated_content()
	_on_map_maker_toggled(true)

func _close_map_selector() -> void:
	if is_instance_valid(map_select_overlay):
		map_select_overlay.queue_free()
	map_select_overlay = null

func _clear_map_editor_assets() -> void:
	for node in get_tree().get_nodes_in_group("map_editor_assets"):
		var node_3d := node as Node3D
		if node_3d != null:
			node_3d.queue_free()

func _create_build_palette_buttons() -> void:
	if build_palette == null:
		return
	for child in build_palette.get_children():
		child.queue_free()

	var ordered_types := [
		"house", "hacienda", "finca", "field", "sawmill",
		"gold_warehouse", "butcher", "barracks", "cantina",
		"trading_post", "weapons_factory", "wall", "tower",
		"wharf", "church", "mission", "fort"
	]
	for building_type in ordered_types:
		var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
		var button := Button.new()
		button.set_meta("building_type", building_type)
		button.text = _building_button_text(building_type)
		button.tooltip_text = _building_tooltip(building_type)
		button.custom_minimum_size = Vector2(92.0, 46.0)
		button.pressed.connect(func() -> void:
			_begin_build_placement(building_type)
		)
		build_palette.add_child(button)

func _building_button_text(building_type: String) -> String:
	var name := str(MexicanTechTreeScript.BUILDINGS[building_type]["name"])
	match building_type:
		"gold_warehouse":
			return "Gold\nStore"
		"trading_post":
			return "Trading\nPost"
		"weapons_factory":
			return "Weapons\nFactory"
	return name.replace(" ", "\n")

func _building_tooltip(building_type: String) -> String:
	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
	var lines := ["%s\nCost: %s" % [definition["name"], _format_cost(definition["cost"])]]
	var requirements := _required_building_names(building_type)
	if not requirements.is_empty():
		lines.append("Requires: %s" % ", ".join(requirements))
	return "\n".join(lines)

func _format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for resource_type in ["food", "wood", "gold"]:
		if cost.has(resource_type):
			parts.append("%d %s" % [int(cost[resource_type]), resource_type])
	return ", ".join(parts)

func _has_resource(resource_type: String) -> bool:
	if economy_system != null and economy_system.has_method("has_resource"):
		return economy_system.has_resource(resource_type)
	return false

func _spawn_units() -> void:
	var worker_positions := [
		Vector3(-4.0, 0.0, 2.0),
		Vector3(-2.8, 0.0, 3.5),
		Vector3(-1.3, 0.0, 1.8),
		Vector3(-5.4, 0.0, 4.0),
		Vector3(-6.2, 0.0, 1.3)
	]
	for position in worker_positions:
		_create_worker_unit(_with_terrain_height(position))

	var roster_positions := {
		"infantryman": Vector3(-9.4, 0.0, 2.2),
		"cavalryman": Vector3(-11.3, 0.0, 4.1),
		"militiaman": Vector3(-10.8, 0.0, 0.1),
		"gunslinger": Vector3(-8.1, 0.0, 5.2),
		"priest": Vector3(-7.4, 0.0, 0.0)
	}
	for unit_type in roster_positions.keys():
		_create_mexican_unit(unit_type, _with_terrain_height(roster_positions[unit_type]))
	_create_cannon_unit(_with_terrain_height(Vector3(-12.7, 0.0, 1.8)))

func _spawn_enemy_units() -> void:
	var positions := [
		Vector3(26.0, 0.0, 4.0),
		Vector3(28.0, 0.0, 6.2),
		Vector3(30.0, 0.0, 3.4),
		Vector3(27.5, 0.0, 0.8)
	]
	for position in positions:
		_create_enemy_unit(_with_terrain_height(position))

func _spawn_cannon() -> void:
	_create_cannon_unit(_with_terrain_height(cannon_factory.global_position + Vector3(4.5, 0.0, 1.5)))

func _create_worker_unit(position: Vector3) -> Node3D:
	var unit := RTSUnitScript.new()
	_configure_mexican_farmhand(unit)
	unit.visual_scene = ModernMexicanFarmhandScene
	unit.position = _with_terrain_height(position)
	unit.resource_deposited.connect(_on_worker_resource_deposited)
	unit.resource_gathered.connect(_on_worker_resource_gathered)
	unit.construction_work.connect(_on_worker_construction_work)
	world_root.add_child(unit)
	return unit

func _configure_mexican_farmhand(unit: Node) -> void:
	unit.display_name = "Mexican Farmhand"
	unit.team = "mexican"
	unit.unit_role = "worker"
	unit.sound_profile = _unit_sound_profile(MEXICAN_FARMHAND_SOUND_PROFILE)
	unit.max_health = 30
	unit.health = 30
	unit.attack_damage = 4

func _create_mexican_unit(unit_type: String, position: Vector3) -> Node3D:
	var unit := RTSUnitScript.new()
	_configure_mexican_unit(unit, unit_type)
	unit.position = _with_terrain_height(position)
	world_root.add_child(unit)
	return unit

func _configure_mexican_unit(unit: Node, unit_type: String) -> void:
	var definition: Dictionary = MexicanTechTreeScript.UNITS[unit_type]
	var assets: Dictionary = MEXICAN_UNIT_ASSETS[unit_type]
	unit.display_name = str(definition["name"])
	unit.team = "mexican"
	unit.unit_role = str(definition["role"])
	unit.visual_scene = assets["scene"]
	unit.sound_profile = _unit_sound_profile(assets.get("sounds", {}))
	unit.max_health = int(definition["health"])
	unit.health = int(definition["health"])
	unit.move_speed = float(definition["speed"])
	unit.attack_range = float(definition["range"])
	unit.attack_damage = int(definition["damage"])
	unit.attack_cooldown = float(definition["cooldown"])
	unit.attack_acquire_range = maxf(float(definition["range"]) + 6.0, 8.0)
	unit.defensive_acquire_range = maxf(float(definition["range"]) * 0.75, 6.0)
	unit.defensive_leash_range = maxf(float(definition["range"]) + 4.0, 10.0)
	unit.behavior_mode = "passive" if str(definition["role"]) == "support" else "defensive"

func _create_enemy_unit(position: Vector3) -> Node3D:
	var enemy := RTSUnitScript.new()
	enemy.team = "enemy"
	enemy.unit_role = "warrior"
	enemy.display_name = "Enemy Warrior"
	enemy.max_health = 100
	enemy.move_speed = 4.2
	enemy.attack_range = 2.4
	enemy.attack_damage = 9
	enemy.attack_cooldown = 1.4
	enemy.sound_profile = _unit_sound_profile({
		"selection": "res://assets/audio/voices/native/warrior_select.wav",
		"movement": "res://assets/audio/voices/native/warrior_command.wav",
		"attack": "res://assets/audio/sfx/stab.wav"
	})
	enemy.attack_acquire_range = 14.0
	enemy.defensive_acquire_range = 8.0
	enemy.defensive_leash_range = 10.0
	enemy.behavior_mode = "aggressive"
	enemy.position = _with_terrain_height(position)
	enemy.died.connect(_on_enemy_died)
	world_root.add_child(enemy)
	return enemy

func _create_cannon_unit(position: Vector3) -> Node3D:
	var cannon := _create_mexican_unit("cannon", position)
	cannon.position = _with_terrain_height(position)
	cannon.cannon_fired.connect(_spawn_cannonball)
	return cannon

func _update_selection_box(current: Vector2) -> void:
	var top_left := Vector2(minf(drag_start.x, current.x), minf(drag_start.y, current.y))
	var size := Vector2(absf(current.x - drag_start.x), absf(current.y - drag_start.y))
	selection_box.position = top_left
	selection_box.size = size

func _select_units_in_rect(start: Vector2, end: Vector2) -> void:
	var rect := Rect2(Vector2(minf(start.x, end.x), minf(start.y, end.y)), Vector2(absf(end.x - start.x), absf(end.y - start.y)))
	if rect.size.length() < 8.0:
		rect = Rect2(end - Vector2(8.0, 8.0), Vector2(16.0, 16.0))

	_clear_selection()

	var camera: Camera3D = camera_rig.get_camera()
	if selection_system != null and selection_system.has_method("select_units_in_rect"):
		selected_units = selection_system.select_units_in_rect(get_tree(), camera, rect)
	build_menu_open = false
	_update_unit_details()

func _select_single_unit(unit: Node) -> void:
	_clear_selection()
	if selection_system != null and selection_system.has_method("select_single_unit"):
		selected_units = selection_system.select_single_unit(unit)
	build_menu_open = false
	_update_unit_details()

func _select_building(building: Node3D) -> void:
	_clear_selection()
	build_menu_open = false
	selected_building = building
	_set_building_selected(selected_building, true)
	_play_sfx(_building_sound_path(selected_building, "selection"))
	_update_unit_details()

func _select_resource_node(resource_node: Node3D) -> void:
	_clear_selection()
	selected_resource = resource_node
	_update_unit_details()

func _clear_selection() -> void:
	if selection_system != null and selection_system.has_method("clear_units"):
		selection_system.clear_units(selected_units)
	selected_units.clear()
	if is_instance_valid(selected_building):
		_set_building_selected(selected_building, false)
	selected_building = null
	selected_resource = null
	build_menu_open = false
	_update_unit_details()

func _update_unit_details() -> void:
	if unit_details_label == null:
		return
	if is_instance_valid(selected_building):
		unit_details_label.text = _selection_name(selected_building)
		if unit_details_body != null:
			var building_type := _selected_building_type()
			unit_details_body.text = _selected_building_status_text(building_type)
	elif is_instance_valid(selected_resource):
		unit_details_label.text = _selection_name(selected_resource)
		if unit_details_body != null:
			unit_details_body.text = _selected_resource_status_text(selected_resource)
	elif selected_units.is_empty():
		unit_details_label.text = "No unit selected"
		if unit_details_body != null:
			unit_details_body.text = "Train cannons, gather resources, or select a unit."
	elif selected_units.size() == 1:
		unit_details_label.text = _selection_name(selected_units[0])
		if unit_details_body != null:
			var health_text := "Health: %d / %d" % [_selection_health(selected_units[0]), _selection_max_health(selected_units[0])]
			var behavior_text := "Behavior: %s" % str(selected_units[0].get("behavior_mode")).capitalize()
			if str(selected_units[0].get("unit_role")) == "cannon":
				unit_details_body.text = "%s\n%s\nClick an enemy warrior to attack with cannon fire." % [health_text, behavior_text]
			elif str(selected_units[0].get("unit_role")) in ["infantry", "cavalry", "militia", "gunslinger"]:
				unit_details_body.text = "%s\n%s\nClick an enemy warrior to attack." % [health_text, behavior_text]
			elif str(selected_units[0].get("unit_role")) == "support":
				unit_details_body.text = "%s\n%s\nSupport unit: move with the army and hold position." % [health_text, behavior_text]
			else:
				unit_details_body.text = "%s\nClick Wood Stand, Gold Mine, or Garden to gather." % health_text
	else:
		unit_details_label.text = "%d units selected" % selected_units.size()
		if unit_details_body != null:
			var total_health := 0
			var total_max_health := 0
			for unit in selected_units:
				total_health += _selection_health(unit)
				total_max_health += _selection_max_health(unit)
			unit_details_body.text = "Combined health: %d / %d\nClick resources with workers or enemies with combat units." % [total_health, total_max_health]
	_update_build_palette_visibility()
	_update_behavior_buttons()
	_update_unit_train_palette()

func _refresh_selected_details() -> void:
	if pending_building_type != "" or _has_pending_map_asset():
		return
	if is_instance_valid(selected_building) or not selected_units.is_empty():
		_update_unit_details()

func _set_building_selected(building: Node3D, value: bool) -> void:
	if selection_system != null and selection_system.has_method("set_building_selected"):
		selection_system.set_building_selected(building, value)

func _selection_name(node: Node) -> String:
	if node.has_meta("display_name"):
		return str(node.get_meta("display_name"))
	return str(node.get("display_name"))

func _building_type_from_name(display_name: String) -> String:
	var normalized := display_name.to_lower().replace(" ", "_")
	if normalized == "weapons_factory":
		return "weapons_factory"
	if normalized == "command_post":
		return "command_post"
	for building_type in MexicanTechTreeScript.BUILDINGS.keys():
		if str(MexicanTechTreeScript.BUILDINGS[building_type]["name"]).to_lower().replace(" ", "_") == normalized:
			return building_type
	return normalized

func _selected_building_type() -> String:
	if not is_instance_valid(selected_building):
		return ""
	return str(selected_building.get_meta("building_type", _building_type_from_name(_selection_name(selected_building))))

func _selection_health(node: Node) -> int:
	if node.has_meta("health"):
		return int(node.get_meta("health"))
	return int(node.get("health"))

func _selection_max_health(node: Node) -> int:
	if node.has_meta("max_health"):
		return int(node.get_meta("max_health"))
	return int(node.get("max_health"))

func _update_build_palette_visibility() -> void:
	var has_worker := _has_selected_worker()
	if build_menu_button != null:
		build_menu_button.visible = has_worker and _is_gameplay_mode()
		build_menu_button.disabled = not has_worker or _is_map_maker_mode()
		build_menu_button.set_pressed_no_signal(build_menu_open and has_worker and _is_gameplay_mode())
	if not has_worker or _is_map_maker_mode():
		build_menu_open = false
		if pending_building_type != "":
			_cancel_build_placement(false)
	if build_palette == null:
		return
	build_palette.visible = build_menu_open and has_worker and _is_gameplay_mode()
	for child in build_palette.get_children():
		var button := child as Button
		if button == null:
			continue
		var building_type := _button_to_building_type(button)
		if building_type != "":
			button.tooltip_text = _building_tooltip(building_type)
			button.disabled = not _can_afford(MexicanTechTreeScript.BUILDINGS[building_type]["cost"]) or not _building_unlocked(building_type)

func _button_to_building_type(button: Button) -> String:
	return str(button.get_meta("building_type", ""))

func _building_unlocked(building_type: String) -> bool:
	return _missing_requirements(building_type).is_empty()

func _missing_requirements(building_type: String) -> Array[String]:
	var missing: Array[String] = []
	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
	for requirement in definition.get("requires", []):
		var required_type := str(requirement)
		if not _has_completed_building(required_type):
			missing.append(required_type)
	return missing

func _required_building_names(building_type: String) -> Array[String]:
	var names: Array[String] = []
	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
	for requirement in definition.get("requires", []):
		names.append(_building_type_name(str(requirement)))
	return names

func _missing_requirement_names(building_type: String) -> Array[String]:
	var names: Array[String] = []
	for requirement in _missing_requirements(building_type):
		names.append(_building_type_name(requirement))
	return names

func _building_type_name(building_type: String) -> String:
	if building_type == "command_post":
		return "Command Post"
	if MexicanTechTreeScript.BUILDINGS.has(building_type):
		return str(MexicanTechTreeScript.BUILDINGS[building_type]["name"])
	return building_type.capitalize()

func _has_completed_building(building_type: String) -> bool:
	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as Node
		if building != null and not building.is_in_group("construction_sites") and str(building.get_meta("building_type", "")) == building_type:
			return true
	return false

func _building_production_text(building_type: String) -> String:
	if not MexicanTechTreeScript.PRODUCTION.has(building_type):
		return ""
	var unit_names: Array[String] = []
	for unit_type in MexicanTechTreeScript.PRODUCTION[building_type]:
		unit_names.append(_unit_display_name(str(unit_type)))
	return "Trains: %s" % ", ".join(unit_names)

func _selected_resource_status_text(resource_node: Node3D) -> String:
	var resource_type := str(resource_node.get_meta("resource_type", "wood")).capitalize()
	var remaining := int(resource_node.get_meta("remaining_gathers", 0))
	var max_gathers := int(resource_node.get_meta("max_gathers", remaining))
	var lines: Array[String] = [
		"%s remaining: %d / %d" % [resource_type, remaining, max_gathers]
	]
	if bool(resource_node.get_meta("depleted", false)):
		lines.append("Depleted.")
	else:
		lines.append("Select a worker, then right-click to harvest.")
	return "\n".join(lines)

func _selected_building_status_text(building_type: String) -> String:
	var lines: Array[String] = [
		"Health: %d / %d" % [_selection_health(selected_building), _selection_max_health(selected_building)]
	]
	if selected_building.is_in_group("construction_sites"):
		lines.append("Construction: %d%%" % _building_construction_percent(selected_building))
	var production_text := _building_production_text(building_type)
	if production_text != "":
		lines.append(production_text)
		lines.append(_building_training_status_text(selected_building))
	return "\n".join(lines)

func _building_construction_percent(building: Node3D) -> int:
	var build_time := maxf(float(building.get_meta("build_time", 0.0)), 0.001)
	var build_progress := float(building.get_meta("build_progress", 0.0))
	return int(clampf(build_progress / build_time, 0.0, 1.0) * 100.0)

func _initialize_building_training_queue(building: Node3D) -> void:
	if not is_instance_valid(building):
		return
	if not building.has_meta("training_queue"):
		building.set_meta("training_queue", [])

func _building_training_queue(building: Node3D) -> Array:
	if not is_instance_valid(building):
		return []
	_initialize_building_training_queue(building)
	var queue: Array = building.get_meta("training_queue", [])
	return queue

func _building_training_progress_for(building: Node3D, unit_type: String) -> int:
	var queue := _building_training_queue(building)
	if queue.is_empty():
		return -1
	var current: Dictionary = queue[0]
	if str(current.get("unit_type", "")) != unit_type:
		return -1
	var train_time := maxf(float(current.get("time", 1.0)), 0.001)
	var progress := float(current.get("progress", 0.0))
	return int(clampf(progress / train_time, 0.0, 1.0) * 100.0)

func _building_training_status_text(building: Node3D) -> String:
	var queue := _building_training_queue(building)
	if queue.is_empty():
		return "Queue: 0 / %d" % UNIT_TRAIN_QUEUE_LIMIT
	var current: Dictionary = queue[0]
	var unit_type := str(current.get("unit_type", ""))
	var train_time := maxf(float(current.get("time", 1.0)), 0.001)
	var progress := float(current.get("progress", 0.0))
	var queue_names: Array[String] = []
	for item in queue:
		queue_names.append(_short_unit_button_name(str(item.get("unit_type", ""))))
	return "Queue: %d / %d\nCurrent: %s %d%%\nWaiting: %s" % [
		queue.size(),
		UNIT_TRAIN_QUEUE_LIMIT,
		_unit_display_name(unit_type),
		int(clampf(progress / train_time, 0.0, 1.0) * 100.0),
		", ".join(queue_names)
	]

func _is_training_queue_full(building: Node3D) -> bool:
	return _building_training_queue(building).size() >= UNIT_TRAIN_QUEUE_LIMIT

func _update_training_queues(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("buildings"):
		var building := node as Node3D
		if building == null or building.is_in_group("construction_sites"):
			continue
		var building_type := str(building.get_meta("building_type", ""))
		if not MexicanTechTreeScript.PRODUCTION.has(building_type):
			continue
		var queue := _building_training_queue(building)
		if queue.is_empty():
			continue
		var current: Dictionary = queue[0]
		current["progress"] = float(current.get("progress", 0.0)) + delta
		queue[0] = current
		var train_time := maxf(float(current.get("time", 1.0)), 0.001)
		if float(current["progress"]) >= train_time:
			queue.pop_front()
			_spawn_trained_unit(building, str(current.get("unit_type", "")))
		building.set_meta("training_queue", queue)

func _update_unit_train_palette() -> void:
	if unit_train_palette == null:
		return
	var signature := _unit_train_palette_signature()
	if signature == unit_train_palette_signature:
		return
	unit_train_palette_signature = signature
	for child in unit_train_palette.get_children():
		child.queue_free()

	if _is_map_maker_mode():
		unit_train_palette.visible = false
		return

	var building_type := _selected_building_type()
	unit_train_palette.visible = is_instance_valid(selected_building) and MexicanTechTreeScript.PRODUCTION.has(building_type)
	if not unit_train_palette.visible:
		return

	for unit_type in MexicanTechTreeScript.PRODUCTION[building_type]:
		var train_type := str(unit_type)
		var definition := _trainable_unit_definition(train_type)
		var cost := _spendable_cost(definition.get("cost", {}))
		var queue := _building_training_queue(selected_building)
		var current_progress := _building_training_progress_for(selected_building, train_type)
		var button := Button.new()
		if current_progress >= 0:
			button.text = "%s %d%%\nQueue %d/%d" % [_short_unit_button_name(train_type), current_progress, queue.size(), UNIT_TRAIN_QUEUE_LIMIT]
		else:
			button.text = "Train %s\n%s" % [_short_unit_button_name(train_type), _format_cost(cost)]
		button.tooltip_text = "%s\nCost: %s\nTime: %.0fs\nProduced at: %s" % [_unit_display_name(train_type), _format_cost(cost), float(definition.get("time", 5.0)), _building_type_name(building_type)]
		button.custom_minimum_size = Vector2(122.0, 48.0)
		button.disabled = not _can_afford(cost) or _is_training_queue_full(selected_building)
		button.pressed.connect(func() -> void:
			_train_unit_from_selected_building(train_type)
		)
		unit_train_palette.add_child(button)

func _unit_train_palette_signature() -> String:
	if _is_map_maker_mode():
		return "map_maker"
	if not is_instance_valid(selected_building):
		return "none"
	var building_type := _selected_building_type()
	if not MexicanTechTreeScript.PRODUCTION.has(building_type):
		return "no_production:%s:%d" % [building_type, selected_building.get_instance_id()]
	var queue_parts: Array[String] = []
	for item in _building_training_queue(selected_building):
		var unit_type := str(item.get("unit_type", ""))
		var train_time := maxf(float(item.get("time", 1.0)), 0.001)
		var progress := int(clampf(float(item.get("progress", 0.0)) / train_time, 0.0, 1.0) * 100.0)
		queue_parts.append("%s:%d" % [unit_type, progress])
	var afford_parts: Array[String] = []
	for unit_type in MexicanTechTreeScript.PRODUCTION[building_type]:
		var definition := _trainable_unit_definition(str(unit_type))
		afford_parts.append("%s:%s" % [str(unit_type), str(_can_afford(_spendable_cost(definition.get("cost", {}))))])
	return "%d:%s:%s:%s" % [
		selected_building.get_instance_id(),
		building_type,
		"|".join(queue_parts),
		"|".join(afford_parts)
	]

func _trainable_unit_definition(unit_type: String) -> Dictionary:
	if unit_type == "farmhand":
		return {
			"name": "Mexican Farmhand",
			"cost": {"food": 50, "housing": 1},
			"time": 4.0
		}
	return MexicanTechTreeScript.UNITS.get(unit_type, {})

func _unit_display_name(unit_type: String) -> String:
	return str(_trainable_unit_definition(unit_type).get("name", unit_type.capitalize()))

func _short_unit_button_name(unit_type: String) -> String:
	match unit_type:
		"infantryman":
			return "Infantry"
		"cavalryman":
			return "Cavalry"
	return _unit_display_name(unit_type).replace("Mexican ", "")

func _spendable_cost(cost: Dictionary) -> Dictionary:
	var spendable := {}
	for resource_type in MexicanTechTreeScript.SPENDABLE_RESOURCES:
		if cost.has(resource_type):
			spendable[resource_type] = cost[resource_type]
	return spendable

func _train_unit_from_selected_building(unit_type: String) -> void:
	if not is_instance_valid(selected_building):
		return
	if _is_training_queue_full(selected_building):
		if unit_details_body != null:
			unit_details_body.text = "Training queue is full: %d / %d." % [UNIT_TRAIN_QUEUE_LIMIT, UNIT_TRAIN_QUEUE_LIMIT]
		return
	var definition := _trainable_unit_definition(unit_type)
	var cost := _spendable_cost(definition.get("cost", {}))
	if not _can_afford(cost):
		if unit_details_body != null:
			unit_details_body.text = "Need %s to train %s." % [_format_cost(cost), _unit_display_name(unit_type)]
		return

	_spend_resources(cost)
	var training_building := selected_building
	var queue := _building_training_queue(selected_building)
	queue.append({
		"unit_type": unit_type,
		"progress": 0.0,
		"time": float(definition.get("time", 5.0))
	})
	training_building.set_meta("training_queue", queue)
	if unit_details_body != null:
		unit_details_body.text = "%s queued at %s.\nQueue: %d / %d" % [
			_unit_display_name(unit_type),
			_selection_name(training_building),
			queue.size(),
			UNIT_TRAIN_QUEUE_LIMIT
		]
	_update_unit_train_palette()

func _spawn_trained_unit(building: Node3D, unit_type: String) -> void:
	if not is_instance_valid(building) or unit_type == "":
		return
	var spawn_position := _with_terrain_height(building.global_position + Vector3(4.5, 0.0, 1.5))
	match unit_type:
		"farmhand":
			_create_worker_unit(spawn_position)
		"cannon":
			_create_cannon_unit(spawn_position)
		_:
			_create_mexican_unit(unit_type, spawn_position)
	if unit_details_body != null:
		unit_details_body.text = "%s trained at %s." % [_unit_display_name(unit_type), _selection_name(building)]
	_update_unit_train_palette()

func _has_selected_worker() -> bool:
	if command_system != null and command_system.has_method("has_worker"):
		return command_system.has_worker(selected_units)
	return false

func _has_selected_combat_unit() -> bool:
	for unit in selected_units:
		if str(unit.get("unit_role")) in ["infantry", "cavalry", "militia", "gunslinger", "cannon"]:
			return true
	return false

func _update_behavior_buttons() -> void:
	var has_combat := not selected_units.is_empty()
	for button in behavior_buttons:
		if button != null:
			button.disabled = not has_combat

func _set_selected_behavior(mode: String) -> void:
	if command_system == null or not command_system.has_method("set_behavior"):
		return
	var changed: int = command_system.set_behavior(selected_units, mode)
	if changed > 0 and unit_details_body != null:
		unit_details_body.text = "%d unit(s) set to %s behavior." % [changed, mode.capitalize()]
	_update_unit_details()

func _on_build_menu_toggled(enabled: bool) -> void:
	if enabled and not _has_selected_worker():
		build_menu_open = false
		if build_menu_button != null:
			build_menu_button.set_pressed_no_signal(false)
		return
	build_menu_open = enabled
	if not enabled and pending_building_type != "":
		_cancel_build_placement(false)
	_update_build_palette_visibility()
	if unit_details_body != null and build_menu_open:
		unit_details_body.text = "Choose a building, then left-click the map to place it."

func _on_map_maker_toggled(enabled: bool) -> void:
	current_mode = AppMode.MAP_MAKER if enabled else AppMode.GAMEPLAY
	if map_editor_system != null and map_editor_system.has_method("set_enabled"):
		map_editor_system.set_enabled(enabled)
	if map_maker_button != null:
		map_maker_button.set_pressed_no_signal(enabled)
	if enabled:
		_set_map_delete_mode(false)
		_cancel_build_placement()
		_clear_selection()
		if unit_details_label != null:
			unit_details_label.text = "Map Maker"
		if unit_details_body != null:
			unit_details_body.text = "Choose an asset, left-click the map to place it, right-click to cancel placement."
	else:
		_set_map_delete_mode(false)
		_cancel_map_asset_placement()
		if unit_details_label != null:
			unit_details_label.text = "No unit selected"
		if unit_details_body != null:
			unit_details_body.text = "Train cannons, gather resources, or select a unit."
	_update_map_asset_palette_visibility()
	_update_build_palette_visibility()
	_update_mode_control_visibility()

func _close_map_maker() -> void:
	if not _is_map_maker_mode():
		return
	_on_map_maker_toggled(false)

func _begin_map_asset_placement(asset_id: String) -> void:
	if not _is_map_maker_mode():
		current_mode = AppMode.MAP_MAKER
		if map_editor_system != null and map_editor_system.has_method("set_enabled"):
			map_editor_system.set_enabled(true)
		if map_maker_button != null:
			map_maker_button.set_pressed_no_signal(true)
	_set_map_delete_mode(false)
	if map_editor_system != null and map_editor_system.has_method("begin_placement"):
		map_editor_system.begin_placement(asset_id)
	if is_instance_valid(map_asset_ghost):
		map_asset_ghost.queue_free()
	map_asset_ghost = _create_map_asset_preview(asset_id)
	world_root.add_child(map_asset_ghost)
	_update_map_asset_ghost(get_viewport().get_mouse_position())
	if unit_details_label != null:
		unit_details_label.text = "Map Maker"
	if unit_details_body != null:
		unit_details_body.text = "Placing %s. Left-click to place, right-click to cancel." % _map_asset_name(asset_id)

func _cancel_map_asset_placement() -> void:
	map_brush_painting = false
	if map_editor_system != null and map_editor_system.has_method("cancel_placement"):
		map_editor_system.cancel_placement()
	if is_instance_valid(map_asset_ghost):
		map_asset_ghost.queue_free()
	map_asset_ghost = null
	if _is_map_maker_mode() and unit_details_body != null:
		unit_details_body.text = "Choose an asset to place."

func _set_map_delete_mode(enabled: bool) -> void:
	if enabled:
		map_brush_painting = false
	map_delete_mode = enabled
	if delete_map_asset_button != null:
		delete_map_asset_button.set_pressed_no_signal(enabled)
	if enabled:
		_cancel_map_asset_placement()
		if unit_details_label != null:
			unit_details_label.text = "Map Maker"
		if unit_details_body != null:
			unit_details_body.text = "Delete mode: left-click a map element to remove it, right-click to cancel."

func _update_map_asset_ghost(screen_position: Vector2) -> void:
	if not _has_pending_map_asset() or not is_instance_valid(map_asset_ghost):
		return
	var point: Variant = _screen_to_ground(screen_position)
	if point == null:
		map_asset_ghost.visible = false
		return
	var asset_id := _pending_map_asset()
	var snapped := _snap_to_grid(point)
	if _is_brush_map_asset(asset_id):
		snapped = _with_terrain_height(point)
	var preview_position := snapped
	var placement_valid := true
	if map_asset_placement_system != null and map_asset_placement_system.has_method("preview_position_for"):
		var preview_result: Dictionary = map_asset_placement_system.preview_position_for(asset_id, snapped)
		placement_valid = bool(preview_result.get("valid", true))
		preview_position = preview_result.get("position", snapped)
	map_asset_ghost.visible = placement_valid
	map_asset_ghost.global_position = preview_position

func _try_place_map_asset(screen_position: Vector2, show_status := true) -> void:
	var asset_id := _pending_map_asset()
	if asset_id == "":
		return
	var point: Variant = _screen_to_ground(screen_position)
	if point == null:
		return
	var placement := _snap_to_grid(point)
	if _is_brush_map_asset(asset_id):
		placement = _with_terrain_height(point)
	var placed_node := _place_map_asset(asset_id, placement, true)
	if show_status and unit_details_body != null:
		if placed_node == null and asset_id == "terrain_ramp":
			unit_details_body.text = "Ramp must be near an edge between low and high ground."
		elif placed_node == null and asset_id == "gold_mine":
			unit_details_body.text = "Gold mine must line up exactly with a high-ground cliff face."
		else:
			unit_details_body.text = "%s placed." % _map_asset_name(asset_id)
	_update_map_asset_ghost(screen_position)

func _try_delete_map_asset(screen_position: Vector2) -> void:
	var target := _screen_to_deletable_map_asset(screen_position)
	if target == null:
		if unit_details_body != null:
			unit_details_body.text = "No removable map element under cursor."
		return
	var asset_id := str(target.get_meta("map_asset_id", ""))
	var asset_position := _map_asset_record_position(target)
	if asset_id.is_empty():
		return
	if map_editor_system != null and map_editor_system.has_method("remove_placement"):
		map_editor_system.remove_placement(asset_id, asset_position)
	if target == selected_building:
		selected_building = null
	if target == headquarters:
		headquarters = null
	if target == cannon_factory:
		cannon_factory = null
	_delete_matching_map_asset_nodes(target, asset_id, asset_position)
	if unit_details_label != null:
		unit_details_label.text = "Map Maker"
	if unit_details_body != null:
		unit_details_body.text = "%s deleted." % _map_asset_name(asset_id)

func _map_asset_record_position(target: Node3D) -> Vector3:
	var raw_position: Variant = target.get_meta("map_asset_position", target.global_position)
	if typeof(raw_position) == TYPE_VECTOR3:
		return raw_position
	return target.global_position

func _delete_matching_map_asset_nodes(target: Node3D, asset_id: String, asset_position: Vector3) -> void:
	if asset_id in ["tree_cluster", "rock_cluster"]:
		for node in get_tree().get_nodes_in_group("map_content"):
			var map_node := node as Node3D
			if map_node == null or not map_node.has_meta("map_asset_id"):
				continue
			if str(map_node.get_meta("map_asset_id", "")) != asset_id:
				continue
			if _map_asset_record_position(map_node).distance_squared_to(asset_position) <= 0.01:
				map_node.queue_free()
		return
	target.queue_free()

func _place_map_asset(asset_id: String, position: Vector3, record_placement := false) -> Node3D:
	if map_asset_placement_system == null or not map_asset_placement_system.has_method("place_asset"):
		return null
	var result: Dictionary = map_asset_placement_system.place_asset(asset_id, position, record_placement)
	if result.has("headquarters"):
		headquarters = result["headquarters"]
	if result.has("cannon_factory"):
		cannon_factory = result["cannon_factory"]
	return result.get("node", null)

func _place_default_map_asset(asset_id: String, position: Vector3) -> Node3D:
	var placed_node := _place_map_asset(asset_id, position, false)
	if placed_node != null:
		placed_node.remove_from_group("map_editor_assets")
		placed_node.add_to_group("map_content")
	return placed_node

func _create_map_asset_preview(asset_id: String) -> Node3D:
	if map_asset_placement_system != null and map_asset_placement_system.has_method("create_preview"):
		return map_asset_placement_system.create_preview(asset_id)
	return Node3D.new()

func _map_asset_name(asset_id: String) -> String:
	if map_editor_system != null and map_editor_system.has_method("asset_name"):
		var building_names := {}
		for building_type in MexicanTechTreeScript.BUILDINGS.keys():
			building_names[building_type] = MexicanTechTreeScript.BUILDINGS[building_type]["name"]
		return map_editor_system.asset_name(asset_id, building_names)
	match asset_id:
		"tree_cluster":
			return "Tree Cluster"
		"rock_cluster":
			return "Rock Cluster"
		"single_tree":
			return "Tree"
		"rock":
			return "Rock"
		"wood_stand":
			return "Wood Stand"
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
		"command_post":
			return "Command Post"
		"weapons_factory":
			return "Weapons Factory"
	if MexicanTechTreeScript.BUILDINGS.has(asset_id):
		return str(MexicanTechTreeScript.BUILDINGS[asset_id]["name"])
	return asset_id.capitalize()

func _has_pending_map_asset() -> bool:
	return map_editor_system != null and map_editor_system.has_method("has_pending_asset") and map_editor_system.has_pending_asset()

func _pending_map_asset() -> String:
	if map_editor_system != null:
		return str(map_editor_system.get("pending_asset"))
	return ""

func _is_brush_map_asset(asset_id: String) -> bool:
	if asset_id.begins_with("paint_"):
		return true
	if map_asset_placement_system != null and map_asset_placement_system.has_method("is_brush_asset"):
		return map_asset_placement_system.is_brush_asset(asset_id)
	return asset_id in ["terrain_plateau", "terrain_high_plateau", "terrain_low_plateau", "terrain_water"]

func _update_minimap() -> void:
	if minimap_panel != null and minimap_panel.has_method("update_blips"):
		minimap_panel.update_blips(get_tree(), camera_rig)

func _issue_move(point: Vector3) -> void:
	if command_system != null and command_system.has_method("issue_move"):
		command_system.issue_move(selected_units, point)

func _issue_gather(resource_node: Node3D) -> void:
	if bool(resource_node.get_meta("depleted", false)):
		if unit_details_body != null:
			unit_details_body.text = "%s is depleted." % str(resource_node.get_meta("display_name", resource_node.name))
		return
	_set_active_resource_target(resource_node)
	if command_system != null and command_system.has_method("issue_gather"):
		command_system.issue_gather(selected_units, resource_node, headquarters)
	var resource_type := str(resource_node.get_meta("resource_type", "resource"))
	_play_sfx(str(RESOURCE_GATHER_SOUNDS.get(resource_type, "")))
	if unit_details_body != null:
		unit_details_body.text = "Gathering %s: workers will carry +10 to the Command Post." % resource_type.capitalize()

func _issue_attack(enemy: Node3D) -> void:
	var attackers := 0
	if command_system != null and command_system.has_method("issue_attack"):
		attackers = command_system.issue_attack(selected_units, enemy)
	if unit_details_body != null:
		if attackers > 0:
			unit_details_body.text = "%d unit(s) attacking enemy warriors." % attackers
		else:
			unit_details_body.text = "Select a combat unit, then click an enemy warrior."

func _begin_build_placement(building_type: String) -> void:
	if not _has_selected_worker():
		if unit_details_body != null:
			unit_details_body.text = "Select a worker before placing a building."
		return
	if not _can_afford(MexicanTechTreeScript.BUILDINGS[building_type]["cost"]):
		if unit_details_body != null:
			unit_details_body.text = "Need %s to build %s." % [_format_cost(MexicanTechTreeScript.BUILDINGS[building_type]["cost"]), MexicanTechTreeScript.BUILDINGS[building_type]["name"]]
		return
	if not _building_unlocked(building_type):
		if unit_details_body != null:
			unit_details_body.text = "Build %s first to unlock %s." % [", ".join(_missing_requirement_names(building_type)), MexicanTechTreeScript.BUILDINGS[building_type]["name"]]
		return

	build_menu_open = true
	pending_building_type = building_type
	if is_instance_valid(building_ghost):
		building_ghost.queue_free()
	building_ghost = _create_building_preview(building_type)
	world_root.add_child(building_ghost)
	_update_building_ghost(get_viewport().get_mouse_position())
	if unit_details_body != null:
		unit_details_body.text = "Place %s: move the outline, left-click to build, right-click to cancel." % MexicanTechTreeScript.BUILDINGS[building_type]["name"]

func _cancel_build_placement(show_message := true) -> void:
	pending_building_type = ""
	ghost_valid = false
	if is_instance_valid(building_ghost):
		building_ghost.queue_free()
	building_ghost = null
	if show_message and unit_details_body != null:
		unit_details_body.text = "Build placement cancelled."

func _update_building_ghost(screen_position: Vector2) -> void:
	if pending_building_type == "" or not is_instance_valid(building_ghost):
		return
	var point: Variant = _screen_to_ground(screen_position)
	if point == null:
		ghost_valid = false
		building_ghost.visible = false
		return

	building_ghost.visible = true
	building_ghost.global_position = _snap_to_grid(point)
	ghost_valid = _is_build_location_valid(building_ghost.global_position, MexicanTechTreeScript.BUILDINGS[pending_building_type]["size"])
	_set_preview_color(building_ghost, Color(0.25, 0.95, 0.40, 0.42) if ghost_valid else Color(0.95, 0.18, 0.12, 0.42))

func _try_place_pending_building(screen_position: Vector2) -> void:
	if pending_building_type == "":
		return
	_update_building_ghost(screen_position)
	if not ghost_valid:
		if unit_details_body != null:
			unit_details_body.text = "Cannot build there."
		return

	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[pending_building_type]
	if not _can_afford(definition["cost"]):
		if unit_details_body != null:
			unit_details_body.text = "Need %s to build %s." % [_format_cost(definition["cost"]), definition["name"]]
		_cancel_build_placement()
		return

	var build_position := building_ghost.global_position
	_spend_resources(definition["cost"])
	var site := _create_construction_site(pending_building_type, build_position)
	_assign_workers_to_build(site)
	_play_sfx(str(_building_sound_profile(pending_building_type).get("building", "")))
	var placed_name := str(definition["name"])
	_cancel_build_placement()
	if unit_details_body != null:
		unit_details_body.text = "%s placed. Workers assigned; more workers build faster." % placed_name

func _assign_workers_to_build(site: Node3D) -> void:
	if build_system != null and build_system.has_method("assign_workers"):
		build_system.assign_workers(selected_units, site)

func _create_construction_site(building_type: String, position: Vector3) -> Node3D:
	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
	var site := ConstructionSiteScript.new()
	site.position = position
	site.set_meta("building_type", building_type)
	site.set_meta("sound_profile", _building_sound_profile(building_type))
	site.completed.connect(_on_construction_site_completed)
	world_root.add_child(site)
	site.configure(building_type, definition)
	return site

func _on_worker_construction_work(site: Node3D, amount: float) -> void:
	if not is_instance_valid(site):
		return
	if site.has_method("add_progress"):
		site.add_progress(amount)

func _on_construction_site_completed(site: Node3D, building_type: String, build_position: Vector3) -> void:
	if not is_instance_valid(site):
		return
	var was_selected := site == selected_building
	site.queue_free()
	var completed := _create_completed_mexican_building(building_type, build_position)
	if was_selected:
		selected_building = completed
		_set_building_selected(selected_building, true)
	var definition: Dictionary = MexicanTechTreeScript.BUILDINGS[building_type]
	if unit_details_body != null:
		unit_details_body.text = "%s complete." % definition["name"]
	_play_sfx(_building_sound_path(completed, "building"))

func _snap_to_grid(position: Vector3) -> Vector3:
	return _with_terrain_height(Vector3(roundf(position.x), position.y, roundf(position.z)))

func _is_build_location_valid(position: Vector3, size: Vector3) -> bool:
	if build_system != null and build_system.has_method("can_place"):
		return build_system.can_place(position, size, ["buildings", "resource_nodes", "construction_sites"], get_tree())
	return false

func _set_preview_color(root: Node3D, color: Color) -> void:
	for child in root.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = _make_transparent_material(color)

func _on_enemy_died(_unit: Node) -> void:
	if unit_details_body != null:
		unit_details_body.text = "Enemy warrior defeated."

func _spawn_cannonball(from_position: Vector3, to_position: Vector3) -> void:
	var ball := MeshInstance3D.new()
	ball.name = "Cannonball"
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	ball.mesh = mesh
	ball.position = from_position
	ball.material_override = _make_material(Color(0.03, 0.03, 0.03))
	world_root.add_child(ball)

	var tween := create_tween()
	tween.tween_property(ball, "position", to_position, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		_spawn_impact(to_position)
		if is_instance_valid(ball):
			ball.queue_free()
	)

func _spawn_impact(position: Vector3) -> void:
	var impact := MeshInstance3D.new()
	impact.name = "CannonImpact"
	var mesh := SphereMesh.new()
	mesh.radius = 0.45
	mesh.height = 0.9
	impact.mesh = mesh
	impact.position = position
	impact.material_override = _make_material(Color(0.18, 0.17, 0.15, 0.85))
	world_root.add_child(impact)

	var tween := create_tween()
	tween.tween_property(impact, "scale", Vector3(1.8, 0.4, 1.8), 0.24)
	tween.parallel().tween_property(impact, "modulate", Color(0.18, 0.17, 0.15, 0.0), 0.24)
	tween.tween_callback(func() -> void:
		if is_instance_valid(impact):
			impact.queue_free()
	)

func _on_worker_resource_deposited(resource_type: String, amount: int) -> void:
	if not _has_resource(resource_type):
		return
	if economy_system != null and economy_system.has_method("deposit"):
		economy_system.deposit(resource_type, amount)
	if unit_details_body != null:
		unit_details_body.text = "+%d %s delivered to the Command Post." % [amount, resource_type.capitalize()]

func _on_worker_resource_gathered(resource_node: Node3D) -> void:
	if not is_instance_valid(resource_node):
		return
	if resource_node.has_method("gather_once"):
		resource_node.gather_once()

func _update_resource_bar() -> void:
	if resource_bar != null and resource_bar.has_method("update_resources") and economy_system != null and economy_system.has_method("snapshot"):
		resource_bar.update_resources(economy_system.snapshot())
	_update_build_palette_visibility()
	_update_unit_train_palette()

func _can_afford(cost: Dictionary) -> bool:
	if economy_system != null and economy_system.has_method("can_afford"):
		return economy_system.can_afford(cost)
	return false

func _spend_resources(cost: Dictionary) -> void:
	if economy_system != null and economy_system.has_method("spend"):
		economy_system.spend(cost)

func _on_economy_resources_changed(_resources: Dictionary) -> void:
	_update_resource_bar()

func _set_active_resource_target(resource_node: Node3D) -> void:
	if is_instance_valid(active_resource_target):
		var old_indicator := active_resource_target.get_node_or_null("CommandIndicator") as MeshInstance3D
		if old_indicator != null:
			old_indicator.visible = false

	active_resource_target = resource_node
	var indicator := active_resource_target.get_node_or_null("CommandIndicator") as MeshInstance3D
	if indicator != null:
		indicator.visible = true

func _screen_to_ground(screen_position: Vector2) -> Variant:
	var camera: Camera3D = camera_rig.get_camera()
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 500.0)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		if collider != null and collider.is_in_group("ground"):
			return hit.get("position")

	if absf(direction.y) < 0.001:
		return null
	var distance: float = -origin.y / direction.y
	if distance < 0.0:
		return null
	var flat_hit := origin + direction * distance
	return _with_terrain_height(flat_hit)

func _screen_to_unit(screen_position: Vector2) -> Node:
	var camera: Camera3D = camera_rig.get_camera()
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 500.0)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _closest_unit_at_screen_position(screen_position)

	var collider := hit.get("collider") as Node
	if collider != null and collider.is_in_group("units"):
		return collider

	return _closest_unit_at_screen_position(screen_position)

func _closest_unit_at_screen_position(screen_position: Vector2) -> Node:
	var camera: Camera3D = camera_rig.get_camera()
	var closest_unit: Node
	var closest_distance := 34.0
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Node
		var unit_3d := node as Node3D
		if unit == null or unit_3d == null:
			continue
		var sample_height := 1.25
		if str(unit.get("unit_role")) == "cavalry":
			sample_height = 1.65
		var sample_position := unit_3d.global_position + Vector3.UP * sample_height
		if camera.is_position_behind(sample_position):
			continue
		var projected := camera.unproject_position(sample_position)
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_unit = unit
	return closest_unit

func _screen_to_resource(screen_position: Vector2) -> Node3D:
	var camera: Camera3D = camera_rig.get_camera()
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 500.0)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var collider := hit.get("collider") as Node3D
	if collider != null and collider.is_in_group("resource_nodes"):
		return collider

	return null

func _screen_to_enemy(screen_position: Vector2) -> Node3D:
	var camera: Camera3D = camera_rig.get_camera()
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 500.0)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var collider := hit.get("collider") as Node3D
	if collider != null and collider.is_in_group("enemy_units"):
		return collider

	return null

func _screen_to_building(screen_position: Vector2) -> Node3D:
	var camera: Camera3D = camera_rig.get_camera()
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 500.0)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var collider := hit.get("collider") as Node3D
	if collider == null:
		return null
	if collider.has_meta("selection_owner"):
		var owner := collider.get_meta("selection_owner") as Node3D
		if owner != null:
			return owner
	if collider.is_in_group("buildings"):
		return collider

	return null

func _screen_to_deletable_map_asset(screen_position: Vector2) -> Node3D:
	var camera: Camera3D = camera_rig.get_camera()
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 500.0)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider := hit.get("collider") as Node3D
		var candidate := _map_asset_owner_for(collider)
		if candidate != null:
			return candidate

	var ground_position: Variant = _screen_to_ground(screen_position)
	if ground_position == null:
		return null
	return _paint_patch_at(ground_position)

func _map_asset_owner_for(node: Node3D) -> Node3D:
	var current := node
	while current != null:
		if current.has_meta("selection_owner"):
			var selection_owner := current.get_meta("selection_owner") as Node3D
			if selection_owner != null and selection_owner.has_meta("map_asset_id"):
				return selection_owner
		if current.has_meta("map_asset_id"):
			return current
		current = current.get_parent() as Node3D
	return null

func _paint_patch_at(position: Vector3) -> Node3D:
	var closest_patch: Node3D
	var closest_distance := INF
	for group_name in ["terrain_paint_patches", "terrain_brush_patches"]:
		for node in get_tree().get_nodes_in_group(group_name):
			var patch := node as Node3D
			if patch == null or not patch.has_meta("map_asset_id"):
				continue
			var radius := float(patch.get_meta("paint_radius", 2.25))
			var flat_distance := Vector2(patch.global_position.x - position.x, patch.global_position.z - position.z).length()
			var height_distance := absf(patch.global_position.y - _with_terrain_height(position).y)
			if flat_distance <= radius and height_distance <= 2.5 and flat_distance < closest_distance:
				closest_distance = flat_distance
				closest_patch = patch
	return closest_patch

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

func _with_terrain_height(position: Vector3) -> Vector3:
	if terrain_service != null:
		return terrain_service.with_height(position)
	return Vector3(position.x, _terrain_height_at(position), position.z)

func _terrain_height_at(world_position: Vector3) -> float:
	if terrain_service != null:
		return terrain_service.height_at(world_position)
	if editor_terrain_system != null:
		return float(editor_terrain_system.height_at(world_position))
	return 0.0

func _terrain_height_without_editor(world_position: Vector3) -> float:
	if terrain_service != null and terrain_service.has_method("base_height_at"):
		return terrain_service.base_height_at(world_position)
	return 0.0

func _make_panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
