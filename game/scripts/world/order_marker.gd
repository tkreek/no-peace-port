class_name OrderMarker
extends Node2D
## Order feedback drawn from the original graphics:
## - move orders: the pointer set's target animation (global/gfx/usa/zeiger, animation 10),
##   four arrows that close in on the destination and shrink away; it plays once;
## - a building's assembly location: the waving position flag (global/gfx/positionsfahne)
##   in the player's colour, shown while the building is selected.

const TARGET_BOB := "global/gfx/usa/zeiger/Zeiger.bob"
const TARGET_ANIM := 10
const FLAG_BOB := "global/gfx/positionsfahne/positionsfahne.bob"

var looping := false
var _bob_path := ""
var _anim := 0
var _bob: BobFile
var _body := Sprite2D.new()
var _shadow: Sprite2D
var _step := 0
var _time := 0.0


static func spawn(parent: Node, at: Vector2, team: int) -> void:
	var marker := OrderMarker.new()
	marker.position = at
	parent.add_child(marker)
	marker._setup(TARGET_BOB, TARGET_ANIM, team, false)


## A waving flag that stays until freed (assembly location).
static func flag(parent: Node, at: Vector2, team: int) -> OrderMarker:
	var marker := OrderMarker.new()
	marker.position = at
	parent.add_child(marker)
	marker._setup(FLAG_BOB, 0, team, true)
	return marker


func _setup(bob_path: String, anim: int, team: int, loop: bool) -> void:
	_bob_path = bob_path
	_anim = anim
	looping = loop
	_bob = GameData.load_bob(bob_path)
	if _bob == null or _bob.anims.size() <= anim:
		queue_free()
		return
	z_index = 5  # over units and scenery
	var palette := GameData.load_palette_texture(bob_path.get_base_dir(), _bob.palettes)
	if looping and _bob.anims.size() > anim + 1:
		_shadow = Sprite2D.new()
		_shadow.centered = false
		_shadow.region_enabled = true
		SpriteMaterials.make_shadow(_shadow)
		add_child(_shadow)
	_body.centered = false
	_body.region_enabled = true
	add_child(_body)
	var sheet := _sheet(_anim)
	if sheet == null:
		queue_free()
		return
	SpriteMaterials.prepare(_body, sheet)
	_body.material = SpriteMaterials.body(sheet, palette, GameData.load_ramps(bob_path))
	_body.set_instance_shader_parameter("palette_row", clampi(team, 0, _bob.palettes.size() - 1))
	_apply()


func _sheet(anim: int) -> RdSprite:
	return GameData.load_sprite(_bob_path.get_base_dir().path_join(_bob.sub_sprites[_bob.anims[anim].sub_sprite]))


func _process(delta: float) -> void:
	if _bob == null:
		return
	var anim := _bob.anims[_anim]
	_time += delta * 1000.0
	while _time >= anim.durations_ms[_step]:
		_time -= anim.durations_ms[_step]
		_step += 1
		if _step >= anim.frames.size():
			if not looping:
				queue_free()
				return
			_step = 0
	_apply()


func _apply() -> void:
	_show(_body, _anim)
	if _shadow:
		_show(_shadow, _anim + 1)


func _show(sprite: Sprite2D, anim: int) -> void:
	var sheet := _sheet(anim)
	var frames := _bob.anims[anim].frames
	var frame: int = frames[mini(_step, frames.size() - 1)]
	if sheet and frame < sheet.frame_count():
		if sprite == _shadow:
			SpriteMaterials.prepare(_shadow, sheet)
		sheet.apply(sprite, frame)
