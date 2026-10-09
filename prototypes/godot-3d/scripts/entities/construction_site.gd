@tool
extends Node3D
class_name RTSConstructionSite

signal completed(site: Node3D, building_type: String, build_position: Vector3)

var building_type := ""
var display_name := "Construction Site"
var build_time := 1.0
var build_progress := 0.0
var max_health := 100
var health := 1
var size := Vector3(3.0, 1.0, 3.0)

func configure(type_id: String, definition: Dictionary) -> void:
	building_type = type_id
	display_name = "%s Construction Site" % str(definition["name"])
	build_time = float(definition["time"])
	size = definition["size"]
	max_health = int(build_time * 100.0)
	health = 1
	name = display_name
	_sync_metadata()
	_create_collision()
	_create_visuals(str(definition["name"]))
	_create_selection_indicator()

func add_progress(amount: float) -> void:
	if build_progress >= build_time:
		return

	build_progress += amount
	var ratio := clampf(build_progress / build_time, 0.0, 1.0)
	health = int(ratio * float(max_health))
	_sync_metadata()

	var scaffold := get_node_or_null("Scaffold") as MeshInstance3D
	if scaffold != null:
		scaffold.scale.y = clampf(ratio, 0.15, 1.0)

	var label := get_node_or_null("ProgressLabel") as Label3D
	if label != null:
		label.text = "%s %d%%" % [display_name.replace(" Construction Site", ""), int(ratio * 100.0)]

	if build_progress >= build_time:
		emit_signal("completed", self, building_type, global_position)

func _sync_metadata() -> void:
	add_to_group("buildings")
	add_to_group("construction_sites")
	set_meta("building_type", building_type)
	set_meta("display_name", display_name)
	set_meta("build_progress", build_progress)
	set_meta("build_time", build_time)
	set_meta("health", health)
	set_meta("max_health", max_health)

func _create_collision() -> void:
	var collision_body := StaticBody3D.new()
	collision_body.name = "ConstructionCollision"
	collision_body.add_to_group("buildings")
	collision_body.set_meta("selection_owner", self)
	add_child(collision_body)

	var collision := CollisionShape3D.new()
	var collision_shape := BoxShape3D.new()
	collision_shape.size = Vector3(size.x, maxf(size.y, 0.6), size.z)
	collision.shape = collision_shape
	collision.position.y = maxf(size.y, 0.6) * 0.5
	collision_body.add_child(collision)

func _create_visuals(building_name: String) -> void:
	var foundation := MeshInstance3D.new()
	foundation.name = "Foundation"
	var foundation_mesh := BoxMesh.new()
	foundation_mesh.size = Vector3(size.x, 0.18, size.z)
	foundation.mesh = foundation_mesh
	foundation.position.y = 0.09
	foundation.material_override = _make_material(Color(0.22, 0.15, 0.08, 0.85))
	add_child(foundation)

	var scaffold := MeshInstance3D.new()
	scaffold.name = "Scaffold"
	var scaffold_mesh := BoxMesh.new()
	scaffold_mesh.size = Vector3(size.x, size.y * 0.35, size.z)
	scaffold.mesh = scaffold_mesh
	scaffold.position.y = maxf(0.25, size.y * 0.18)
	scaffold.scale.y = 0.15
	scaffold.material_override = _make_transparent_material(Color(0.66, 0.44, 0.22, 0.55))
	add_child(scaffold)

	var label := Label3D.new()
	label.name = "ProgressLabel"
	label.text = "%s 0%%" % building_name
	label.position = Vector3(0.0, size.y + 0.85, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 24
	label.modulate = Color(0.95, 0.86, 0.58)
	add_child(label)

func _create_selection_indicator() -> void:
	var indicator := MeshInstance3D.new()
	indicator.name = "SelectionIndicator"
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(size.x, size.z) * 0.52
	mesh.outer_radius = maxf(size.x, size.z) * 0.58
	indicator.mesh = mesh
	indicator.position.y = 0.07
	indicator.material_override = _make_material(Color(0.96, 0.85, 0.30))
	indicator.visible = false
	add_child(indicator)

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
