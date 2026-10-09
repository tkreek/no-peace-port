@tool
extends Node3D

const ROOT_NAME := "ModernChurchVisual"

@export var show_label := true :
	set(value):
		show_label = value
		if is_inside_tree():
			_rebuild()

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	var old_root := get_node_or_null(ROOT_NAME)
	if old_root != null:
		old_root.queue_free()

	var root := Node3D.new()
	root.name = ROOT_NAME
	add_child(root)
	if Engine.is_editor_hint():
		root.owner = get_tree().edited_scene_root

	_add_box(root, "Nave", Vector3(4.2, 2.0, 3.1), Vector3(0.0, 1.0, 0.0), _mat(Color(0.72, 0.61, 0.45), 0.92))
	_add_box(root, "Apse", Vector3(1.4, 1.8, 2.2), Vector3(2.45, 0.9, 0.15), _mat(Color(0.66, 0.55, 0.40), 0.92))
	_add_box(root, "BellTower", Vector3(1.12, 3.35, 1.08), Vector3(-1.58, 1.68, -0.72), _mat(Color(0.78, 0.70, 0.55), 0.88))
	_add_box(root, "TowerCap", Vector3(1.38, 0.42, 1.30), Vector3(-1.58, 3.56, -0.72), _mat(Color(0.50, 0.20, 0.11), 0.8))
	_add_box(root, "NaveRoof", Vector3(4.75, 0.55, 3.55), Vector3(0.0, 2.24, 0.0), _mat(Color(0.47, 0.17, 0.09), 0.72), Vector3(0.0, 0.0, 5.0))
	_add_box(root, "ApseRoof", Vector3(1.72, 0.46, 2.45), Vector3(2.45, 1.98, 0.15), _mat(Color(0.42, 0.14, 0.08), 0.72), Vector3(0.0, 0.0, -5.0))

	_add_box(root, "FrontDoor", Vector3(0.92, 1.2, 0.08), Vector3(-0.20, 0.62, -1.60), _mat(Color(0.20, 0.11, 0.05), 0.65))
	_add_cylinder(root, "DoorArch", 0.46, 0.10, Vector3(-0.20, 1.20, -1.64), _mat(Color(0.20, 0.11, 0.05), 0.65), Vector3(90.0, 0.0, 0.0))
	_add_box(root, "DoorFrame", Vector3(1.20, 1.46, 0.10), Vector3(-0.20, 0.78, -1.66), _mat(Color(0.86, 0.79, 0.64), 0.9))
	_move_child_to_front(root, "FrontDoor")
	_move_child_to_front(root, "DoorArch")

	for x in [-1.45, 1.05]:
		_add_box(root, "BlueWindow", Vector3(0.52, 0.64, 0.07), Vector3(x, 1.32, -1.62), _emissive_mat(Color(0.18, 0.46, 0.66), Color(0.05, 0.16, 0.22)))
		_add_box(root, "WindowTrim", Vector3(0.72, 0.82, 0.05), Vector3(x, 1.32, -1.66), _mat(Color(0.85, 0.79, 0.65), 0.9))

	for z in [-0.92, 0.92]:
		_add_box(root, "SideWindow", Vector3(0.07, 0.56, 0.46), Vector3(2.04, 1.18, z), _emissive_mat(Color(0.17, 0.36, 0.52), Color(0.03, 0.11, 0.16)))

	_add_box(root, "CrossVertical", Vector3(0.14, 0.95, 0.14), Vector3(-1.58, 4.16, -0.72), _mat(Color(0.90, 0.78, 0.42), 0.62))
	_add_box(root, "CrossHorizontal", Vector3(0.62, 0.14, 0.14), Vector3(-1.58, 4.28, -0.72), _mat(Color(0.90, 0.78, 0.42), 0.62))
	_add_box(root, "Bell", Vector3(0.42, 0.34, 0.30), Vector3(-1.58, 2.92, -1.28), _mat(Color(0.72, 0.55, 0.25), 0.45))

	var glow := OmniLight3D.new()
	glow.name = "WarmWindowGlow"
	glow.position = Vector3(-0.15, 1.25, -1.95)
	glow.light_color = Color(1.0, 0.68, 0.34)
	glow.light_energy = 0.75
	glow.omni_range = 4.0
	root.add_child(glow)

	var smoke := CPUParticles3D.new()
	smoke.name = "SoftDustMotes"
	smoke.amount = 28
	smoke.lifetime = 2.8
	smoke.emitting = true
	smoke.direction = Vector3(0.0, 1.0, 0.0)
	smoke.spread = 18.0
	smoke.gravity = Vector3(0.0, 0.18, 0.0)
	smoke.initial_velocity_min = 0.15
	smoke.initial_velocity_max = 0.35
	smoke.scale_amount_min = 0.02
	smoke.scale_amount_max = 0.06
	smoke.color = Color(0.95, 0.86, 0.68, 0.25)
	smoke.position = Vector3(-1.58, 3.78, -0.72)
	root.add_child(smoke)

	if show_label:
		var label := Label3D.new()
		label.name = "AssetLabel"
		label.text = "Modern Mexican Church"
		label.position = Vector3(0.0, 4.75, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 26
		label.modulate = Color(0.95, 0.86, 0.58)
		root.add_child(label)

func _add_box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_cylinder(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _move_child_to_front(parent: Node, child_name: String) -> void:
	var child := parent.get_node_or_null(child_name)
	if child != null:
		parent.move_child(child, parent.get_child_count() - 1)

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _emissive_mat(color: Color, emission: Color) -> StandardMaterial3D:
	var material := _mat(color, 0.55)
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 0.55
	return material
