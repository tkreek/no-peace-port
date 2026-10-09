class_name RtsCamera
extends Camera2D
## Keyboard / edge / middle-drag panning and smooth wheel zoom, clamped to the map.

@export var pan_speed := 900.0
@export var edge_margin := 6
## Zoom levels are relative to a 1080-line screen, so a bigger monitor shows the same
## stretch of map at the same level rather than more of it.
@export var min_zoom := 0.85  # wide enough to see a base and its approaches
@export var max_zoom := 1.6  # close enough for detail without blowing the art up
@export var zoom_step := 1.15

var bounds := Rect2()
var input_enabled := true
var _target_zoom := 1.0
var _dragging := false


func _ready() -> void:
	_target_zoom = zoom.x


func set_zoom_level(value: float) -> void:
	_target_zoom = clampf(value, min_zoom, max_zoom)
	zoom = Vector2(_target_zoom, _target_zoom) * screen_scale()


func screen_scale() -> float:
	return maxf(1.0, get_viewport_rect().size.y / 1080.0)


func _process(delta: float) -> void:
	var input := Vector2(
		Input.get_axis("camera_left", "camera_right"),
		Input.get_axis("camera_up", "camera_down"))
	var viewport := get_viewport()
	if not input_enabled:
		input = Vector2.ZERO
	elif DisplayServer.window_is_focused() and viewport.get_visible_rect().has_point(viewport.get_mouse_position()):
		var mouse := viewport.get_mouse_position()
		var size := viewport.get_visible_rect().size
		if mouse.x < edge_margin: input.x = -1
		elif mouse.x > size.x - edge_margin: input.x = 1
		if mouse.y < edge_margin: input.y = -1
		elif mouse.y > size.y - edge_margin: input.y = 1
	position += input.limit_length(1.0) * pan_speed * Settings.value("scroll_speed") * delta / zoom.x
	var z := lerpf(zoom.x, _target_zoom * screen_scale(), minf(1.0, delta * 12.0))
	zoom = Vector2(z, z)
	_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clampf(_target_zoom * zoom_step, min_zoom, max_zoom)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clampf(_target_zoom / zoom_step, min_zoom, max_zoom)
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom.x


func _clamp() -> void:
	if bounds.size == Vector2.ZERO:
		return
	var half := get_viewport_rect().size / zoom / 2.0
	position.x = clampf(position.x, bounds.position.x + half.x, maxf(bounds.position.x + half.x, bounds.end.x - half.x))
	position.y = clampf(position.y, bounds.position.y + half.y, maxf(bounds.position.y + half.y, bounds.end.y - half.y))
