class_name OrderMarker
extends Node2D
## Feedback for orders: the original waving position flag (global/gfx/positionsfahne) at a
## move destination, in the player's colour, shown briefly and then faded out.

const BOB := "global/gfx/positionsfahne/positionsfahne.bob"
const LIFETIME := 1.6

var _bob: BobFile
var _body := Sprite2D.new()
var _shadow := Sprite2D.new()
var _step := 0
var _time := 0.0
var _age := 0.0


static func spawn(parent: Node, at: Vector2, team: int) -> void:
	var marker := OrderMarker.new()
	marker.position = at
	parent.add_child(marker)
	marker._setup(team)


func _setup(team: int) -> void:
	_bob = GameData.load_bob(BOB)
	if _bob == null or _bob.anims.is_empty():
		queue_free()
		return
	var palette := GameData.load_palette_texture(BOB.get_base_dir(), _bob.palettes)
	for sprite: Sprite2D in [_shadow, _body]:
		sprite.centered = false
		sprite.region_enabled = true
		add_child(sprite)
	SpriteMaterials.make_shadow(_shadow)
	var sheet := _sheet(0)
	if sheet:
		SpriteMaterials.prepare(_body, sheet)
		_body.material = SpriteMaterials.body(sheet, palette, GameData.load_ramps(BOB))
		_body.set_instance_shader_parameter("palette_row", clampi(team, 0, _bob.palettes.size() - 1))
	_apply()


func _sheet(anim: int) -> RdSprite:
	if anim >= _bob.anims.size():
		return null
	return GameData.load_sprite(BOB.get_base_dir().path_join(_bob.sub_sprites[_bob.anims[anim].sub_sprite]))


func _process(delta: float) -> void:
	if _bob == null:
		return
	_age += delta
	modulate.a = clampf((LIFETIME - _age) / 0.4, 0.0, 1.0)
	if _age >= LIFETIME:
		queue_free()
		return
	var anim := _bob.anims[0]
	_time += delta * 1000.0
	if _time >= anim.durations_ms[_step]:
		_time = 0.0
		_step = (_step + 1) % anim.frames.size()
		_apply()


func _apply() -> void:
	for pair in [[_body, 0], [_shadow, 1]]:
		var sheet := _sheet(pair[1])
		if sheet == null:
			continue
		var frame: int = _bob.anims[pair[1]].frames[mini(_step, _bob.anims[pair[1]].frames.size() - 1)]
		if frame < sheet.frame_count():
			if pair[0] == _shadow:
				SpriteMaterials.prepare(_shadow, sheet)
			sheet.apply(pair[0], frame)
