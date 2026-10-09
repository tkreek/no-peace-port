@tool
extends Node3D

const ModernChurchScript := preload("res://scripts/visuals/procedural_modern_church.gd")
const ModernMexicanFarmhandScript := preload("res://scripts/visuals/procedural_modern_mexican_farmhand.gd")

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.68, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.56, 0.50)
	env.ambient_light_energy = 0.95
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.name = "LateAfternoonSun"
	sun.rotation_degrees = Vector3(-48.0, -34.0, 0.0)
	sun.light_energy = 2.8
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "WarmFill"
	fill.position = Vector3(-3.0, 4.0, 4.0)
	fill.light_color = Color(1.0, 0.78, 0.48)
	fill.light_energy = 0.7
	fill.omni_range = 8.0
	add_child(fill)

	var ground := MeshInstance3D.new()
	ground.name = "PreviewGround"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(10.0, 7.0)
	ground.mesh = ground_mesh
	ground.material_override = _mat(Color(0.45, 0.35, 0.23), 0.95)
	add_child(ground)

	var church := ModernChurchScript.new()
	church.name = "MexicanChurchModern"
	church.position = Vector3(-1.2, 0.0, 0.0)
	add_child(church)

	var farmhand := ModernMexicanFarmhandScript.new()
	farmhand.name = "MexicanFarmhandModern"
	farmhand.position = Vector3(2.4, 0.0, -0.8)
	farmhand.rotation_degrees.y = -22.0
	add_child(farmhand)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(4.8, 4.0, 6.0)
	camera.rotation_degrees = Vector3(-34.0, 38.0, 0.0)
	camera.fov = 38.0
	camera.current = true
	add_child(camera)

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
