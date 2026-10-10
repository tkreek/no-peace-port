class_name UnitSprite
extends Node2D
## How a unit looks: its original 8-direction sprite animations with team palette and
## shadow, the facing, the selection ring and a brief tint when picked as a target.
## Unit builds the rules on top of this.

var unit_type: UnitType
var direction := 1  # sprite direction row: 0 = SE, then clockwise (1 = S ... 7 = E)
var selected := false:
	set(value):
		selected = value
		queue_redraw()
		if is_instance_valid(_overlay):
			_overlay.queue_redraw()

## Draw the selection ring over the picture (boats: their hulls would hide one underneath).
var ring_on_top := false
var _overlay := DrawOverlay.new()
var _body := Sprite2D.new()
var _shadow := Sprite2D.new()
var _action := ""
var _anim := -1
var _shadow_anim := -1
var _step := 0
var _step_time := 0.0
var _anim_finished := false
var _flash_time := 0.0


func _setup_sprites(type: UnitType, palette_row: int) -> void:
	unit_type = type
	for sprite: Sprite2D in [_shadow, _body]:
		sprite.centered = false
		sprite.region_enabled = true
	SpriteMaterials.make_shadow(_shadow)
	add_child(_shadow)
	add_child(_body)
	add_child(_overlay)
	set_palette_row(palette_row)


## Health bars and the like above every sprite (Unit draws them; a bare sprite, such as the
## map editor's preview, has none).
func _draw_overlay(_canvas: Node2D) -> void:
	pass


## Take the unit's own picture away (its remains are shown instead).
func hide_body() -> void:
	_body.visible = false
	_shadow.visible = false


func set_palette_row(row: int) -> void:
	_body.set_instance_shader_parameter("palette_row", clampi(row, 0, unit_type.bob.teams - 1))


## Whether the unit is standing (dead ones lose their selection ring). Unit overrides it.
func is_alive() -> bool:
	return true


## Briefly tint the unit to confirm it was picked as an attack target.
func flash(color := Color(1.0, 0.35, 0.3)) -> void:
	_flash_time = 0.8
	_body.self_modulate = color


func _fade_flash(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_body.self_modulate = Color.WHITE


func face(vector: Vector2) -> void:
	if vector.length_squared() > 0.01:
		direction = posmod(roundi((rad_to_deg(vector.angle()) - 45.0) / 45.0), 8)


## The animation to show for `action` here (Unit swaps in swimming and paddling sheets).
func _variant(action: String) -> String:
	return action


func play(action: String) -> void:
	action = _variant(action)
	if action == _action:
		return
	var index := unit_type.anim_index(action)
	if index < 0:
		if _anim >= 0:
			return
		index = 0  # e.g. animals without walk/idle sheets: show their first animation
	_action = action
	_start_anim(index)


## Work animations (chopping, building, sowing...) are single swings in the .bob files;
## the original repeats them for as long as the work goes on. True when a swing starts.
func play_repeating(action: String) -> bool:
	if action != _action:
		play(action)
		return _action == action
	if _anim_finished:
		_start_anim(_anim)
		return true
	return false


func _play_index(index: int) -> void:
	_action = "#%d" % index
	_start_anim(index)


func _start_anim(index: int) -> void:
	if unit_type.bob.sub_sprite_is_shadow[unit_type.bob.anims[index].sub_sprite]:
		return
	_anim = index
	_shadow_anim = unit_type.bob.shadow_for(index)
	_step = 0
	_step_time = 0.0
	_anim_finished = false
	_apply_frame()


func _advance(delta: float) -> void:
	var anim := unit_type.bob.anims[_anim]
	_step_time += delta * 1000.0
	while _step_time >= anim.durations_ms[_step]:
		_step_time -= anim.durations_ms[_step]
		if _step + 1 < anim.frames.size():
			_step += 1
		elif anim.loops():
			_step = clampi(anim.frames.size() - anim.loop_back, 0, anim.frames.size() - 1)
			_anim_finished = true  # one full cycle played (attack sequences wait for this)
		else:
			_step_time = 0.0
			_anim_finished = true
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
	if sprite.texture != sheet.texture:
		SpriteMaterials.prepare(sprite, sheet)
		if sprite == _body:
			sprite.material = SpriteMaterials.body(sheet, unit_type.ramps)
	sheet.apply(sprite, frame)


## Whether `point` (world) is on a solid pixel of the unit's current picture.
func hit(point: Vector2) -> bool:
	if _body.texture == null:
		return false
	var local := _body.to_local(point)
	return _body.get_rect().has_point(local) and _body.is_pixel_opaque(local)


func _draw() -> void:
	# The selection ring belongs on the ground, under the unit's own sprite.
	if selected and is_alive() and not ring_on_top:
		_draw_ring(self, 16.0)


func _draw_ring(canvas: CanvasItem, radius: float) -> void:
	StatusBar.ring(canvas, Vector2.ZERO, radius, StatusBar.team_colour(get("team")))
