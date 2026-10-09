class_name Unit
extends Node2D
## A unit drawn with its original 8-direction sprite animations, team palette and shadow.

signal died(unit: Unit)

const PalettedShader := preload("res://shaders/paletted_sprite.gdshader")
const SHADOW_COLOR := Color(0, 0, 0, 0.45)
const ARRIVE_DISTANCE := 3.0

var unit_type: UnitType
var team := 1
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var direction := 1  # sprite direction row: 0 = SE, then clockwise (1 = S ... 7 = E)
var max_health := 100.0
var health := 100.0
var path := PackedVector2Array()

var _body := Sprite2D.new()
var _shadow := Sprite2D.new()
var _action := ""
var _anim := -1
var _shadow_anim := -1
var _step := 0
var _step_time := 0.0


func setup(type: UnitType, team_index: int) -> void:
	unit_type = type
	team = team_index
	var body_material := ShaderMaterial.new()
	body_material.shader = PalettedShader
	body_material.set_shader_parameter("palette", type.palette)
	_body.material = body_material
	for sprite: Sprite2D in [_shadow, _body]:
		sprite.centered = false
		sprite.region_enabled = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow.modulate = SHADOW_COLOR
	_shadow.z_index = -1
	_shadow.z_as_relative = false
	add_child(_shadow)
	add_child(_body)
	_body.set_instance_shader_parameter("palette_row", clampi(team, 0, type.bob.palettes.size() - 1))
	play("idle")


func play(action: String) -> void:
	if action == _action:
		return
	var index := unit_type.anim_index(action)
	if index < 0:
		if _anim >= 0:
			return
		index = 0  # e.g. animals without walk/idle sheets: show their first animation
	if unit_type.bob.sub_sprite_is_shadow[unit_type.bob.anims[index].sub_sprite]:
		return
	_action = action
	_anim = index
	_shadow_anim = unit_type.bob.shadow_for(index)
	_step = 0
	_step_time = 0.0
	_apply_frame()


func move_to(target: Vector2) -> void:
	path = PackedVector2Array([target])


func stop() -> void:
	path.clear()


func face(vector: Vector2) -> void:
	if vector.length_squared() > 0.01:
		direction = posmod(roundi((rad_to_deg(vector.angle()) - 45.0) / 45.0), 8)


func _process(delta: float) -> void:
	if not path.is_empty():
		var to_target := path[0] - position
		var step := unit_type.speed * delta
		if to_target.length() <= maxf(step, ARRIVE_DISTANCE):
			position = path[0]
			path.remove_at(0)
		else:
			face(to_target)
			position += to_target.normalized() * step
	play("walk" if not path.is_empty() else "idle")
	_advance(delta)


func _advance(delta: float) -> void:
	var anim := unit_type.bob.anims[_anim]
	_step_time += delta * 1000.0
	while _step_time >= anim.durations_ms[_step]:
		_step_time -= anim.durations_ms[_step]
		if _step + 1 < anim.frames.size():
			_step += 1
		elif anim.loops():
			_step = clampi(anim.frames.size() - anim.loop_back, 0, anim.frames.size() - 1)
		else:
			_step_time = 0.0
			break
	_apply_frame()


func _apply_frame() -> void:
	_set_frame(_body, _anim)
	if _shadow_anim >= 0:
		_set_frame(_shadow, _shadow_anim)


func _set_frame(sprite: Sprite2D, anim_index: int) -> void:
	var anim := unit_type.bob.anims[anim_index]
	var sheet := unit_type.sprite_for(anim_index)
	if sheet == null:
		return
	var dir := direction % anim.directions
	var frame := dir * anim.frames_per_direction + anim.frames[mini(_step, anim.frames.size() - 1)]
	if frame >= sheet.frame_count():
		return
	sprite.texture = sheet.texture
	sprite.region_rect = Rect2(sheet.rects[frame])
	sprite.offset = -sheet.hotspots[frame]


func _draw() -> void:
	if selected:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color(1, 1, 1, 0.85), 1.5, true)
		draw_set_transform(Vector2.ZERO)
		var bar := Rect2(-12, -58, 24, 3)
		draw_rect(bar, Color(0.1, 0.1, 0.1, 0.8))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * health / max_health, bar.size.y)), Color(0.3, 0.9, 0.2))
