class_name UnitSprite
extends Node2D
## How a unit looks: its original 8-direction sprite animations with team palette and
## shadow, the facing, the selection ring and a brief tint when picked as a target, and
## its picture showing through a roof or a canopy drawn over it.
## Unit builds the rules on top of this.

## In cover, the original draws a unit's picture once more after everything else, blended
## half and half with what is there (draw passes 0x4625d0: the last one, 0x10; unit draw
## 0x417f80 does it when [unit+0x41c], which 0x417310 sets from bit 29 of the grid at its
## feet as it moves; blit 0x409f90 adds src >> 1 and dst >> 1). Over the remake's detailed
## crowns and roofs that half-blend was lost in the leaves, or on a bright roof looked like
## a unit standing on it; and the grid's cover cells miss much of what hides a unit (the
## ground just behind a wall, under a tall tower, a crown whose tree was felled beside it).
## So the remake draws it again over everything whenever a tree or building is drawn over
## its picture (CoverGrid), and only where it is hidden: a faint silhouette in its team
## colour with a brighter rim (unit_ghost.gdshader). Where it is in plain view nothing
## changes. All units, whoever's; a selected one's marker too, faintly.
const COVER_Z := 5  ## over every sprite, under the weather (6) and the fog of war (90)
const COVER_RING_ALPHA := 0.5

var unit_type: UnitType
var direction := 1  # sprite direction row: 0 = SE, then clockwise (1 = S ... 7 = E)
var selected := false:
	set(value):
		selected = value
		queue_redraw()
		_cover.queue_redraw()
		if is_instance_valid(_overlay):
			_overlay.queue_redraw()

## Draw the selection ring over the picture (boats: their hulls would hide one underneath).
var ring_on_top := false
var _overlay := DrawOverlay.new()
var _body := Sprite2D.new()
var _shadow := Sprite2D.new()
## The picture again over everything while in cover (with the selection ring under it).
var _cover := Node2D.new()
var _cover_body := Sprite2D.new()
var _cover_cell := Vector2i(-1, -1)  # the 16 px cell where the cover was last looked up
var _cover_roster := -1  # and MapObject.roster_version then
var _body_sheet: RdSprite  # the sheet the body shows
var _action := ""
var _anim := -1
var _shadow_anim := -1
var _step := 0
var _step_time := 0.0
var _anim_finished := false
var _flash_time := 0.0
var _flash_ring := false
## The picture on each sprite now (anim << 32 | frame): a step that changes neither leaves it be.
var _body_shown := -1
var _shadow_shown := -1
var _shown_direction := -1


func _setup_sprites(type: UnitType, palette_row: int) -> void:
	unit_type = type
	_body_shown = -1
	_shadow_shown = -1
	for sprite: Sprite2D in [_shadow, _body]:
		sprite.centered = false
		sprite.region_enabled = true
	SpriteMaterials.make_shadow(_shadow)
	add_child(_shadow)
	add_child(_body)
	_cover_body.centered = false
	_cover_body.region_enabled = true
	_cover.z_index = COVER_Z
	_cover.z_as_relative = false
	_cover.self_modulate.a = COVER_RING_ALPHA
	_cover.visible = false
	_cover.draw.connect(_draw_cover_ring)
	_cover.add_child(_cover_body)
	add_child(_cover)
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
	_cover_body.visible = false


func set_palette_row(row: int) -> void:
	_body.set_instance_shader_parameter("palette_row", clampi(row, 0, unit_type.bob.teams - 1))
	_cover_body.set_instance_shader_parameter("palette_row", clampi(row, 0, unit_type.bob.teams - 1))
	_cover_body.set_instance_shader_parameter("ghost_colour", StatusBar.team_colour(row))


## Whether the unit is standing (dead ones lose their selection ring). Unit overrides it.
func is_alive() -> bool:
	return true


## Briefly tint the unit to confirm it was picked as an attack target; `ring` also circles
## it, blinking (a horse to be mounted).
func flash(color := Color(1.0, 0.35, 0.3), ring := false) -> void:
	_flash_time = 1.2 if ring else 0.8
	_flash_ring = ring
	_body.self_modulate = color
	_cover_body.self_modulate = color


func _fade_flash(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_ring:
			queue_redraw()
		if _flash_time <= 0.0:
			_body.self_modulate = Color.WHITE
			_cover_body.self_modulate = Color.WHITE
			_flash_ring = false


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


## Play animation `index` of the set (one no action name reaches), unless it is playing.
func play_index(index: int) -> void:
	if index >= 0 and _action != "#%d" % index:
		_play_index(index)


## Whether the current animation has played through once (a looping one: a full cycle).
func anim_done() -> bool:
	return _anim_finished


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
	_update_cover()
	var anim := unit_type.bob.anims[_anim]
	var shown_step := _step
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
	if _step != shown_step or direction != _shown_direction:
		_apply_frame()


func _apply_frame() -> void:
	_shown_direction = direction
	_set_frame(_body, _anim)
	if _shadow_anim >= 0:
		_set_frame(_shadow, _shadow_anim)


func _set_frame(sprite: Sprite2D, anim_index: int) -> void:
	var anim := unit_type.bob.anims[anim_index]
	var dir := direction % anim.directions
	var frame := dir * anim.frames_per_direction + anim.frames[mini(_step, anim.frames.size() - 1)]
	var shown := anim_index << 32 | frame
	if sprite == _body:
		if shown == _body_shown:
			return
		_body_shown = shown
	else:
		if shown == _shadow_shown:
			return
		_shadow_shown = shown
	var sheet := unit_type.sprite_for(anim_index)
	if sheet == null:
		return
	if frame >= sheet.frame_count():
		return
	if sprite.texture != sheet.texture:
		SpriteMaterials.prepare(sprite, sheet)
		if sprite == _body:
			sprite.material = SpriteMaterials.body(sheet, unit_type.ramps)
	if sprite == _body:
		_body_sheet = sheet
	sheet.apply(sprite, frame)
	if sprite == _body and _cover.visible:
		_show_cover_frame()


## Whether the unit is shown through what is drawn over it (see COVER_Z).
func shows_through() -> bool:
	return _cover.visible


## Look up whether a tree or building is drawn over the unit, when it has moved to another
## cell or objects came or went (and once it has died, take the picture away). Only the
## drawing reads it.
func _update_cover() -> void:
	if not is_alive():
		_cover.visible = false
		return
	var cell := Vector2i((position / NavGrid.CELL).floor())
	if NavGrid.current == null or _body.texture == null \
			or (cell == _cover_cell and MapObject.roster_version == _cover_roster):
		return
	_cover_cell = cell
	_cover_roster = MapObject.roster_version
	var picture := _body.get_rect()
	var covered := CoverGrid.covered(position, Rect2(position + picture.position * _body.scale, picture.size * _body.scale))
	if covered != _cover.visible:
		_cover.visible = covered
		if covered:
			_show_cover_frame()


func _show_cover_frame() -> void:
	_cover_body.texture = _body.texture
	_cover_body.texture_filter = _body.texture_filter
	_cover_body.material = SpriteMaterials.ghost(_body_sheet, unit_type.ramps) if _body_sheet else null
	_cover_body.region_rect = _body.region_rect
	_cover_body.offset = _body.offset
	_cover_body.scale = _body.scale


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
	elif _flash_ring and int(_flash_time * 5.0) % 2 == 0:
		StatusBar.ring(self, Vector2.ZERO, 22.0, _body.self_modulate)


func _draw_cover_ring() -> void:
	if selected and is_alive() and not ring_on_top:
		_draw_ring(_cover, 16.0)


func _draw_ring(canvas: CanvasItem, radius: float) -> void:
	StatusBar.ring(canvas, Vector2.ZERO, radius, StatusBar.team_colour(get("team")))
