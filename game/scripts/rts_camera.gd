extends Node3D
class_name RTSCamera

@export var pan_speed := 24.0
@export var edge_pan_speed := 18.0
@export var edge_margin := 18.0
@export var zoom_speed := 4.0
@export var min_zoom := 16.0
@export var max_zoom := 54.0
@export var map_limit := 45.0

var _zoom := 32.0
var _camera: Camera3D

func _ready() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	_camera.fov = 48.0
	_update_camera_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom - zoom_speed, min_zoom, max_zoom)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom + zoom_speed, min_zoom, max_zoom)
			_update_camera_transform()

func _process(delta: float) -> void:
	var direction := Vector3.ZERO
	if Input.is_action_pressed("camera_forward"):
		direction.z -= 1.0
	if Input.is_action_pressed("camera_back"):
		direction.z += 1.0
	if Input.is_action_pressed("camera_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("camera_right"):
		direction.x += 1.0

	var mouse := get_viewport().get_mouse_position()
	var viewport_size := get_viewport().get_visible_rect().size
	if mouse.x <= edge_margin:
		direction.x -= 1.0
	elif mouse.x >= viewport_size.x - edge_margin:
		direction.x += 1.0
	if mouse.y <= edge_margin:
		direction.z -= 1.0
	elif mouse.y >= viewport_size.y - edge_margin:
		direction.z += 1.0

	if direction != Vector3.ZERO:
		direction = direction.normalized()
		var speed := pan_speed
		if mouse.x <= edge_margin or mouse.x >= viewport_size.x - edge_margin or mouse.y <= edge_margin or mouse.y >= viewport_size.y - edge_margin:
			speed = edge_pan_speed
		global_position += direction * speed * delta
		global_position.x = clampf(global_position.x, -map_limit, map_limit)
		global_position.z = clampf(global_position.z, -map_limit, map_limit)

func get_camera() -> Camera3D:
	return _camera

func _update_camera_transform() -> void:
	_camera.position = Vector3(0.0, _zoom, _zoom * 0.72)
	_camera.rotation_degrees = Vector3(-58.0, 0.0, 0.0)
