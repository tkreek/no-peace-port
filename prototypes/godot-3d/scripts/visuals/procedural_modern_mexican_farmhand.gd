@tool
extends Node3D

const ROOT_NAME := "ModernMexicanFarmhandVisual"

@export var animate_idle := true

var visual_root: Node3D
var left_arm: MeshInstance3D
var right_arm: MeshInstance3D
var left_leg: MeshInstance3D
var right_leg: MeshInstance3D
var tool: MeshInstance3D
var time := 0.0

func _ready() -> void:
	_rebuild()

func _process(delta: float) -> void:
	if not animate_idle or visual_root == null:
		return

	time += delta
	var bob := sin(time * 2.3) * 0.035
	visual_root.position.y = bob
	if left_arm != null:
		left_arm.rotation_degrees.z = 14.0 + sin(time * 2.3) * 4.0
	if right_arm != null:
		right_arm.rotation_degrees.z = -18.0 - sin(time * 2.3) * 4.0
	if left_leg != null:
		left_leg.rotation_degrees.z = -4.0 + sin(time * 2.3) * 2.0
	if right_leg != null:
		right_leg.rotation_degrees.z = 4.0 - sin(time * 2.3) * 2.0
	if tool != null:
		tool.rotation_degrees = Vector3(0.0, 0.0, -28.0 + sin(time * 2.3) * 3.0)

func _rebuild() -> void:
	var old_root := get_node_or_null(ROOT_NAME)
	if old_root != null:
		old_root.queue_free()

	visual_root = Node3D.new()
	visual_root.name = ROOT_NAME
	add_child(visual_root)
	if Engine.is_editor_hint():
		visual_root.owner = get_tree().edited_scene_root

	var skin := _mat(Color(0.70, 0.47, 0.30), 0.82)
	var shirt := _mat(Color(0.18, 0.34, 0.56), 0.88)
	var shirt_dark := _mat(Color(0.12, 0.24, 0.42), 0.88)
	var pants := _mat(Color(0.48, 0.36, 0.22), 0.86)
	var leather := _mat(Color(0.26, 0.14, 0.06), 0.74)
	var hat_mat := _mat(Color(0.72, 0.56, 0.32), 0.9)
	var hat_band := _mat(Color(0.36, 0.22, 0.10), 0.85)
	var metal := _mat(Color(0.72, 0.74, 0.72), 0.32)
	var eye_mat := _mat(Color(0.05, 0.04, 0.04), 0.4)
	var mustache_mat := _mat(Color(0.14, 0.08, 0.05), 0.95)

	_add_capsule("Torso", 0.32, 0.78, Vector3(0.0, 1.05, 0.0), shirt)
	_add_box("ShirtPlacket", Vector3(0.10, 0.42, 0.08), Vector3(0.0, 1.20, -0.30), shirt_dark)
	_add_capsule("Neck", 0.09, 0.10, Vector3(0.0, 1.46, 0.0), skin)
	_add_sphere("Head", 0.24, Vector3(0.0, 1.63, 0.0), skin)
	_add_sphere("EyeL", 0.030, Vector3(-0.090, 1.66, -0.215), eye_mat)
	_add_sphere("EyeR", 0.030, Vector3(0.090, 1.66, -0.215), eye_mat)
	_add_box("Mustache", Vector3(0.18, 0.05, 0.05), Vector3(0.0, 1.555, -0.215), mustache_mat)
	_add_cylinder("HatBrim", 0.40, 0.045, Vector3(0.0, 1.82, 0.0), hat_mat)
	_add_cylinder("HatCrownLower", 0.24, 0.05, Vector3(0.0, 1.85, 0.0), hat_mat)
	_add_cylinder("HatBand", 0.245, 0.05, Vector3(0.0, 1.88, 0.0), hat_band)
	_add_cylinder("HatCrown", 0.21, 0.18, Vector3(0.0, 1.98, 0.0), hat_mat)
	_add_box("Neckerchief", Vector3(0.42, 0.10, 0.10), Vector3(0.0, 1.40, -0.22), _mat(Color(0.70, 0.10, 0.08), 0.78))
	_add_box("NeckerchiefKnot", Vector3(0.10, 0.10, 0.06), Vector3(0.16, 1.36, -0.22), _mat(Color(0.55, 0.07, 0.05), 0.8))
	_add_box("Belt", Vector3(0.68, 0.10, 0.68), Vector3(0.0, 0.78, 0.0), leather)
	_add_box("BeltBuckle", Vector3(0.14, 0.10, 0.04), Vector3(0.0, 0.78, -0.33), _mat(Color(0.80, 0.62, 0.22), 0.4))

	left_arm = _add_limb("LeftArm", Vector3(-0.34, 1.18, 0.0), 0.08, 0.56, shirt, Vector3(0.0, 0.0, 14.0))
	right_arm = _add_limb("RightArm", Vector3(0.34, 1.18, 0.0), 0.08, 0.56, shirt, Vector3(0.0, 0.0, -18.0))
	_add_sphere("LeftHand", 0.090, Vector3(-0.42, 0.88, 0.0), skin)
	_add_sphere("RightHand", 0.090, Vector3(0.42, 0.88, 0.0), skin)
	left_leg = _add_limb("LeftLeg", Vector3(-0.15, 0.48, 0.0), 0.09, 0.62, pants, Vector3(0.0, 0.0, -4.0))
	right_leg = _add_limb("RightLeg", Vector3(0.15, 0.48, 0.0), 0.09, 0.62, pants, Vector3(0.0, 0.0, 4.0))
	_add_box("LeftBoot", Vector3(0.22, 0.12, 0.36), Vector3(-0.17, 0.10, -0.04), leather)
	_add_box("RightBoot", Vector3(0.22, 0.12, 0.36), Vector3(0.17, 0.10, -0.04), leather)
	_add_box("LeftBootHeel", Vector3(0.18, 0.08, 0.10), Vector3(-0.17, 0.05, 0.10), _mat(Color(0.14, 0.07, 0.03), 0.7))
	_add_box("RightBootHeel", Vector3(0.18, 0.08, 0.10), Vector3(0.17, 0.05, 0.10), _mat(Color(0.14, 0.07, 0.03), 0.7))

	_add_box("Satchel", Vector3(0.32, 0.28, 0.12), Vector3(-0.42, 0.93, 0.08), leather, Vector3(0.0, 0.0, -8.0))
	_add_box("SatchelFlap", Vector3(0.34, 0.16, 0.02), Vector3(-0.44, 1.04, 0.02), _mat(Color(0.32, 0.18, 0.08), 0.72), Vector3(0.0, 0.0, -8.0))
	_add_box("SatchelStrap", Vector3(0.08, 0.88, 0.05), Vector3(-0.18, 1.17, -0.22), leather, Vector3(0.0, 0.0, -28.0))

	tool = _add_box("AxeHandle", Vector3(0.07, 0.78, 0.07), Vector3(0.55, 0.82, -0.10), _mat(Color(0.45, 0.25, 0.10), 0.72), Vector3(0.0, 0.0, -28.0))
	_add_box("AxeHead", Vector3(0.28, 0.18, 0.06), Vector3(0.70, 1.16, -0.10), metal, Vector3(0.0, 0.0, -28.0))
	_add_box("AxeEdge", Vector3(0.04, 0.20, 0.07), Vector3(0.82, 1.18, -0.10), _mat(Color(0.88, 0.88, 0.86), 0.18), Vector3(0.0, 0.0, -28.0))

	var label := Label3D.new()
	label.name = "AssetLabel"
	label.text = "Mexican Farmhand"
	label.position = Vector3(0.0, 2.35, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 20
	label.modulate = Color(0.95, 0.86, 0.58)
	visual_root.add_child(label)

func _add_limb(part_name: String, position: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var limb := _add_capsule(part_name, radius, height, position, material)
	limb.rotation_degrees = rotation
	return limb

func _add_capsule(part_name: String, radius: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 6
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	visual_root.add_child(mesh_instance)
	return mesh_instance

func _add_sphere(part_name: String, radius: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 18
	mesh.rings = 9
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	visual_root.add_child(mesh_instance)
	return mesh_instance

func _add_cylinder(part_name: String, radius: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 28
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	visual_root.add_child(mesh_instance)
	return mesh_instance

func _add_box(part_name: String, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	visual_root.add_child(mesh_instance)
	return mesh_instance

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
