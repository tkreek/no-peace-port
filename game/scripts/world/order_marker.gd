class_name OrderMarker
extends Node2D
## Feedback for move orders: the original pointer set's target animation (global/gfx/usa/zeiger,
## animation 10): four arrows that close in on the destination and shrink away. It plays once.
## (The waving flag in global/gfx/positionsfahne is the rally point of a building.)

const BOB := "global/gfx/usa/zeiger/Zeiger.bob"
const TARGET_ANIM := 10

var _bob: BobFile
var _body := Sprite2D.new()
var _step := 0
var _time := 0.0


static func spawn(parent: Node, at: Vector2, team: int) -> void:
	var marker := OrderMarker.new()
	marker.position = at
	parent.add_child(marker)
	marker._setup(team)


func _setup(team: int) -> void:
	_bob = GameData.load_bob(BOB)
	if _bob == null or _bob.anims.size() <= TARGET_ANIM:
		queue_free()
		return
	z_index = 5  # over units and scenery
	var palette := GameData.load_palette_texture(BOB.get_base_dir(), _bob.palettes)
	_body.centered = false
	_body.region_enabled = true
	add_child(_body)
	var sheet := _sheet()
	if sheet == null:
		queue_free()
		return
	SpriteMaterials.prepare(_body, sheet)
	_body.material = SpriteMaterials.body(sheet, palette, GameData.load_ramps(BOB))
	_body.set_instance_shader_parameter("palette_row", clampi(team, 0, _bob.palettes.size() - 1))
	_apply()


func _sheet() -> RdSprite:
	return GameData.load_sprite(BOB.get_base_dir().path_join(_bob.sub_sprites[_bob.anims[TARGET_ANIM].sub_sprite]))


func _process(delta: float) -> void:
	if _bob == null:
		return
	var anim := _bob.anims[TARGET_ANIM]
	_time += delta * 1000.0
	while _time >= anim.durations_ms[_step]:
		_time -= anim.durations_ms[_step]
		_step += 1
		if _step >= anim.frames.size():
			queue_free()
			return
	_apply()


func _apply() -> void:
	var sheet := _sheet()
	var frame: int = _bob.anims[TARGET_ANIM].frames[_step]
	if sheet and frame < sheet.frame_count():
		sheet.apply(_body, frame)
