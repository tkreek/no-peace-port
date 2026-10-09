class_name Thumbnail
extends TextureRect
## A command-button picture made from an object's own sprite (finished building or a unit
## facing the viewer), drawn with its team colours.

static func for_type(type_id: int, team: int) -> Thumbnail:
	var type := ObjectTypes.get_type(type_id)
	if type == null:
		return null
	var bob := GameData.load_bob(type.bob_path)
	if bob == null or bob.anims.is_empty():
		return null
	var anim_index := 0
	var frame_in_anim := -1
	if type.kind == ObjectTypes.Kind.BUILDING:
		anim_index = 2 if bob.anims.size() > 3 else 0
	else:
		anim_index = maxi(0, bob.find_anim("stehen"))
		frame_in_anim = 0
	var anim := bob.anims[anim_index]
	var sheet := GameData.load_sprite(type.directory().path_join(bob.sub_sprites[anim.sub_sprite]))
	if sheet == null:
		return null
	var frame := anim.frames[frame_in_anim if frame_in_anim >= 0 else anim.frames.size() - 1]
	if type.kind != ObjectTypes.Kind.BUILDING:
		frame += 1 * anim.frames_per_direction  # direction 1 = facing south
	if frame >= sheet.frame_count():
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet.texture
	atlas.region = Rect2(sheet.rects[frame])
	var thumb := Thumbnail.new()
	thumb.texture = atlas
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.material = SpriteMaterials.body(sheet, GameData.load_palette_texture(type.directory(), bob.palettes),
			GameData.load_ramps(type.bob_path))
	thumb.set_meta("palette_row", mini(team, bob.palettes.size() - 1))
	return thumb


func _ready() -> void:
	set_instance_shader_parameter("palette_row", get_meta("palette_row", 1))
