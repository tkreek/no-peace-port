@tool
extends StaticBody3D
class_name RTSResourceNode

enum VisualKind { WOOD, GOLD, GARDEN, SINGLE_TREE }

@export var resource_type := "wood"
@export var display_name := "Resource"
@export var collision_size := Vector3(4.0, 1.0, 4.0)
@export var remaining_gathers := 8
@export var visual_kind := VisualKind.WOOD

var depleted := false
var wood_state := "standing"

func _ready() -> void:
	_setup_metadata()
	_create_collision()
	_create_label()
	_create_command_indicator()
	_create_visuals()

func gather_once() -> void:
	if depleted:
		return
	if resource_type != "wood":
		return

	remaining_gathers -= 1
	set_meta("remaining_gathers", remaining_gathers)
	var new_state := _wood_state_for_remaining(remaining_gathers)
	if remaining_gathers <= 0:
		depleted = true
		set_meta("depleted", true)
	_set_wood_resource_state(new_state)
	_refresh_resource_label()

func _wood_state_for_remaining(remaining: int) -> String:
	var max_gathers := int(get_meta("max_gathers", remaining_gathers if remaining_gathers > 0 else 1))
	if remaining <= 0:
		return "stump"
	if remaining <= max(1, max_gathers / 2):
		return "chopped"
	return "standing"

func _refresh_resource_label() -> void:
	var label := get_node_or_null("ResourceLabel") as Label3D
	if label == null:
		return
	if depleted:
		label.text = "%s (Empty)" % display_name
	else:
		label.text = "%s (%d)" % [display_name, remaining_gathers]

func _setup_metadata() -> void:
	name = display_name
	set_meta("resource_type", resource_type)
	set_meta("display_name", display_name)
	set_meta("depleted", depleted)
	set_meta("remaining_gathers", remaining_gathers)
	set_meta("max_gathers", remaining_gathers)
	add_to_group("resource_nodes")

func _create_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = collision_size
	collision.shape = shape
	collision.position.y = collision_size.y * 0.5
	add_child(collision)

func _create_label() -> void:
	var label := Label3D.new()
	label.name = "ResourceLabel"
	label.text = "%s (%d)" % [display_name, remaining_gathers]
	label.position = Vector3(0.0, collision_size.y + 0.85, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.modulate = Color(0.95, 0.89, 0.62)
	add_child(label)

func _create_command_indicator() -> void:
	var indicator := MeshInstance3D.new()
	indicator.name = "CommandIndicator"
	var indicator_mesh := TorusMesh.new()
	indicator_mesh.inner_radius = maxf(collision_size.x, collision_size.z) * 0.42
	indicator_mesh.outer_radius = maxf(collision_size.x, collision_size.z) * 0.48
	indicator.mesh = indicator_mesh
	indicator.position.y = 0.08
	indicator.material_override = _make_material(Color(0.96, 0.84, 0.26, 0.95))
	indicator.visible = false
	add_child(indicator)

func _create_visuals() -> void:
	match visual_kind:
		VisualKind.WOOD:
			_create_wood_visuals()
		VisualKind.GOLD:
			_create_goldmine_visuals()
		VisualKind.GARDEN:
			_create_garden_visuals()
		VisualKind.SINGLE_TREE:
			_create_single_tree_visuals()

func _create_single_tree_visuals() -> void:
	var standing := _get_or_create_visual_group("StandingTrees")
	_add_single_tree(standing, Vector3.ZERO)
	var felled := _get_or_create_visual_group("FelledTrees")
	_add_single_felled_tree(felled, Vector3.ZERO)
	var stumps := _get_or_create_visual_group("Stumps")
	_add_stump(Vector3.ZERO, "Stumps")
	_set_wood_resource_state(_wood_state_for_remaining(remaining_gathers))

func _add_single_tree(parent: Node3D, local_position: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.13
	trunk_mesh.bottom_radius = 0.20
	trunk_mesh.height = 1.6
	trunk.mesh = trunk_mesh
	trunk.position = local_position + Vector3(0.0, 0.80, 0.0)
	trunk.material_override = _make_material(Color(0.30, 0.19, 0.09))
	parent.add_child(trunk)

	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	var crown_radius := randf_range(0.70, 0.95)
	crown_mesh.radius = crown_radius
	crown_mesh.height = crown_radius * 2.0
	crown.mesh = crown_mesh
	crown.position = local_position + Vector3(0.0, 1.85, 0.0)
	crown.scale = Vector3(1.0, randf_range(0.95, 1.30), 1.0)
	crown.material_override = _make_material(Color(randf_range(0.12, 0.22), randf_range(0.34, 0.52), randf_range(0.13, 0.22)))
	parent.add_child(crown)

func _add_single_felled_tree(parent: Node3D, local_position: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 2.2
	trunk.mesh = trunk_mesh
	trunk.position = local_position + Vector3(0.55, 0.22, 0.0)
	trunk.rotation_degrees = Vector3(0.0, 0.0, 88.0)
	trunk.material_override = _make_material(Color(0.34, 0.20, 0.09))
	parent.add_child(trunk)

	var foliage := MeshInstance3D.new()
	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius = 0.55
	foliage_mesh.height = 0.85
	foliage.mesh = foliage_mesh
	foliage.position = local_position + Vector3(1.55, 0.32, 0.05)
	foliage.scale = Vector3(1.5, 0.55, 0.95)
	foliage.material_override = _make_material(Color(0.12, 0.32, 0.14))
	parent.add_child(foliage)

func _create_wood_visuals() -> void:
	for i in range(5):
		var angle := TAU * float(i) / 5.0
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 1.4
		_add_tree(offset, "StandingTrees")
		_add_felled_tree(offset.rotated(Vector3.UP, 0.45), "FelledTrees")
		_add_stump(offset * 0.86, "Stumps")
	_set_wood_resource_state("standing")

func _create_goldmine_visuals() -> void:
	# Materials. Local +X points into the cliff (away from the player).
	var rock_dark := _make_material(Color(0.34, 0.32, 0.30))
	var rock_mid := _make_material(Color(0.46, 0.43, 0.40))
	var rock_light := _make_material(Color(0.58, 0.55, 0.51))
	var shadow := _make_material(Color(0.03, 0.025, 0.02))
	var wood := _make_material(Color(0.30, 0.18, 0.09))
	var wood_dark := _make_material(Color(0.18, 0.10, 0.05))
	var iron := _make_material(Color(0.18, 0.17, 0.15))
	var gold := _make_material(Color(0.94, 0.72, 0.20))
	var gold_dim := _make_material(Color(0.74, 0.55, 0.16))
	gold.roughness = 0.32
	gold.metallic = 0.65
	gold_dim.roughness = 0.45
	gold_dim.metallic = 0.55

	# Wide rocky outcrop that visually wraps around the mine and blends with the cliff face.
	_add_box("OutcropMain", Vector3(1.6, 2.3, 4.8), Vector3(0.55, 1.15, 0.0), rock_mid)
	_add_box("OutcropLeft", Vector3(1.10, 1.95, 1.6), Vector3(0.20, 0.97, -1.7), rock_dark)
	_add_box("OutcropRight", Vector3(1.10, 1.95, 1.6), Vector3(0.20, 0.97, 1.7), rock_dark)
	_add_box("OutcropCap", Vector3(1.7, 0.35, 5.1), Vector3(0.55, 2.42, 0.0), rock_light)
	# Random rocky bumps to break up the cliff face silhouette.
	for z in [-2.05, -0.55, 0.55, 2.05]:
		_add_box("RockBump", Vector3(0.32, randf_range(0.55, 1.05), 0.55), Vector3(-0.04, randf_range(0.55, 1.20), z), rock_light)

	# Recessed mine entrance: arched opening into the cliff.
	var entrance_h := 1.45
	_add_box("EntranceShadow", Vector3(0.95, entrance_h, 1.55), Vector3(-0.42, entrance_h * 0.5, 0.0), shadow)
	_add_cylinder("EntranceArch", 0.78, 0.30, Vector3(-0.42, entrance_h, 0.0), shadow, Vector3(0.0, 0.0, 90.0))
	# Inner darkness so the camera can't see straight through to the back.
	_add_box("EntranceDeep", Vector3(0.30, entrance_h + 0.30, 1.20), Vector3(-0.75, (entrance_h + 0.30) * 0.5, 0.0), shadow)

	# Wooden support frame around the entrance.
	for z in [-0.78, 0.78]:
		_add_box("FramePost", Vector3(0.20, entrance_h + 0.18, 0.20), Vector3(-0.18, (entrance_h + 0.18) * 0.5, z), wood)
	_add_box("FrameLintel", Vector3(0.30, 0.24, 1.95), Vector3(-0.18, entrance_h + 0.18, 0.0), wood)
	_add_box("FrameLintelCap", Vector3(0.40, 0.10, 2.10), Vector3(-0.18, entrance_h + 0.34, 0.0), wood_dark)
	# Diagonal cross braces above the lintel.
	for sign_z in [-1.0, 1.0]:
		var brace := _add_box("CrossBrace", Vector3(0.10, 0.05, 0.95), Vector3(-0.18, entrance_h + 0.55, sign_z * 0.50), wood)
		brace.rotation_degrees = Vector3(0.0, 0.0, 0.0)
		brace.rotation = Vector3(sign_z * 0.45, 0.0, 0.0)

	# Gold veins glittering on and around the entrance.
	for spec in [
		[Vector3(-0.16, 1.92, -1.05), Vector3(0.32, 0.10, 0.55), -12.0, gold],
		[Vector3(-0.18, 1.78, 0.50), Vector3(0.28, 0.08, 0.42), 10.0, gold],
		[Vector3(-0.18, 1.20, -1.55), Vector3(0.30, 0.08, 0.40), 6.0, gold_dim],
		[Vector3(-0.18, 0.95, 1.55), Vector3(0.26, 0.07, 0.45), -8.0, gold_dim],
		[Vector3(-0.20, 0.40, -0.95), Vector3(0.18, 0.05, 0.30), 0.0, gold_dim]
	]:
		var pos: Vector3 = spec[0]
		var size: Vector3 = spec[1]
		var rotation_z: float = spec[2]
		var material: StandardMaterial3D = spec[3]
		var vein := _add_box("GoldVein", size, pos, material)
		vein.rotation_degrees.z = rotation_z

	# Mine cart rails extending from the entrance.
	for rail_z in [-0.30, 0.30]:
		_add_box("Rail", Vector3(2.2, 0.04, 0.05), Vector3(-1.40, 0.06, rail_z), iron)
	for tie_x in [-2.0, -1.4, -0.8]:
		_add_box("RailTie", Vector3(0.15, 0.05, 0.85), Vector3(tie_x, 0.04, 0.0), wood_dark)

	# Spoils piled at the cliff base, with a few gold nuggets visible.
	for z in [-1.95, -1.15, 1.20, 1.95]:
		var pile := MeshInstance3D.new()
		var pile_mesh := SphereMesh.new()
		pile_mesh.radius = 0.42
		pile_mesh.height = 0.55
		pile.mesh = pile_mesh
		pile.position = Vector3(-0.55, 0.20, z)
		pile.scale = Vector3(randf_range(1.05, 1.40), randf_range(0.45, 0.60), randf_range(0.85, 1.10))
		pile.material_override = rock_dark
		add_child(pile)
	for z in [-1.5, 1.5]:
		var nugget := MeshInstance3D.new()
		var nugget_mesh := SphereMesh.new()
		nugget_mesh.radius = 0.10
		nugget_mesh.height = 0.14
		nugget.mesh = nugget_mesh
		nugget.position = Vector3(-0.55, 0.18, z)
		nugget.material_override = gold
		add_child(nugget)

	# A weathered pickaxe leaning against the frame.
	var handle := _add_box("PickaxeHandle", Vector3(0.05, 0.95, 0.05), Vector3(-0.18, 0.55, 1.10), wood)
	handle.rotation_degrees = Vector3(0.0, 0.0, 18.0)
	var head := _add_box("PickaxeHead", Vector3(0.06, 0.10, 0.40), Vector3(-0.34, 1.00, 1.10), iron)
	head.rotation_degrees = Vector3(0.0, 0.0, 18.0)

func _add_box(part_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = position
	mi.material_override = material
	add_child(mi)
	return mi

func _add_cylinder(part_name: String, radius: float, height: float, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mi.mesh = mesh
	mi.position = position
	mi.rotation_degrees = rotation
	mi.material_override = material
	add_child(mi)
	return mi

func _create_garden_visuals() -> void:
	var bed := MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(5.2, 0.12, 4.0)
	bed.mesh = bed_mesh
	bed.position = Vector3(0.0, 0.06, 0.0)
	bed.material_override = _make_material(Color(0.25, 0.16, 0.08))
	add_child(bed)

	for row in range(3):
		for column in range(5):
			var crop := MeshInstance3D.new()
			var crop_mesh := SphereMesh.new()
			crop_mesh.radius = 0.22
			crop_mesh.height = 0.36
			crop.mesh = crop_mesh
			crop.position = Vector3(-1.9 + column * 0.95, 0.32, -1.05 + row * 1.05)
			crop.scale.y = 1.5
			crop.material_override = _make_material(Color(0.18, 0.50, 0.18))
			add_child(crop)

func _add_tree(local_position: Vector3, group_name: String) -> void:
	var holder := _get_or_create_visual_group(group_name)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height = 1.4
	trunk.mesh = trunk_mesh
	trunk.position = local_position + Vector3(0.0, 0.7, 0.0)
	trunk.material_override = _make_material(Color(0.30, 0.19, 0.09))
	holder.add_child(trunk)

	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.75
	crown_mesh.height = 1.5
	crown.mesh = crown_mesh
	crown.position = local_position + Vector3(0.0, 1.65, 0.0)
	crown.material_override = _make_material(Color(0.12, 0.42, 0.16))
	holder.add_child(crown)

func _add_felled_tree(local_position: Vector3, group_name: String) -> void:
	var holder := _get_or_create_visual_group(group_name)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 2.0
	trunk.mesh = trunk_mesh
	trunk.position = local_position + Vector3(0.0, 0.22, 0.0)
	trunk.rotation_degrees = Vector3(88.0, randf_range(0.0, 180.0), 0.0)
	trunk.material_override = _make_material(Color(0.34, 0.20, 0.09))
	holder.add_child(trunk)

	var brush := MeshInstance3D.new()
	var brush_mesh := SphereMesh.new()
	brush_mesh.radius = 0.45
	brush_mesh.height = 0.8
	brush.mesh = brush_mesh
	brush.position = local_position + Vector3(0.65, 0.28, 0.25)
	brush.scale = Vector3(1.4, 0.45, 0.8)
	brush.material_override = _make_material(Color(0.10, 0.32, 0.12))
	holder.add_child(brush)

func _add_stump(local_position: Vector3, group_name: String) -> void:
	var holder := _get_or_create_visual_group(group_name)
	var stump := MeshInstance3D.new()
	var stump_mesh := CylinderMesh.new()
	stump_mesh.top_radius = 0.20
	stump_mesh.bottom_radius = 0.26
	stump_mesh.height = 0.42
	stump.mesh = stump_mesh
	stump.position = local_position + Vector3(0.0, 0.21, 0.0)
	stump.material_override = _make_material(Color(0.30, 0.18, 0.08))
	holder.add_child(stump)

func _get_or_create_visual_group(group_name: String) -> Node3D:
	var existing := get_node_or_null(group_name) as Node3D
	if existing != null:
		return existing
	var holder := Node3D.new()
	holder.name = group_name
	add_child(holder)
	return holder

func _set_wood_resource_state(state: String) -> void:
	wood_state = state
	set_meta("wood_state", state)
	for group_name in ["StandingTrees", "FelledTrees", "Stumps"]:
		var holder := get_node_or_null(group_name) as Node3D
		if holder != null:
			holder.visible = group_name == _wood_state_group(state)

func _wood_state_group(state: String) -> String:
	match state:
		"chopped":
			return "FelledTrees"
		"stump":
			return "Stumps"
	return "StandingTrees"

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material
