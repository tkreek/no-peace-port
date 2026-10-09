class_name Thumbnail
extends TextureRect
## A command-button picture made from an object's own sprite (finished building or a unit
## facing the viewer), drawn with its team colours.

static var _textures := {}  # portrait path -> texture


## The original portrait (expansion Potraits/*.bmp) for a GUID, or null.
static func portrait(guid: int) -> Thumbnail:
	return from_bmp(GameData.stats(guid).get("icon", ""))


## One of the original portrait BMPs (Potraits/...), or null.
static func from_bmp(path: String) -> Thumbnail:
	if path.is_empty() or not GameData.exists(path):
		return null
	if _textures.has(path):
		return _portrait_thumb(_textures[path])
	var enhanced := GameData.enhanced_image(path)
	if enhanced:
		enhanced.generate_mipmaps()  # 4x pictures shown at button size
		_textures[path] = ImageTexture.create_from_image(enhanced)
		return _portrait_thumb(_textures[path])
	var bytes := GameData.read(path)
	if bytes.size() < 54:
		return null
	# Some original BMPs carry wrong size fields in their headers; the pixel data is intact.
	var data_offset := bytes.decode_u32(10)
	bytes.encode_u32(2, bytes.size())
	bytes.encode_u32(34, bytes.size() - data_offset)
	var image := Image.new()
	if image.load_bmp_from_buffer(bytes) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r8 > 240 and c.g8 < 20 and c.b8 > 240:  # magenta colour key
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	_textures[path] = ImageTexture.create_from_image(image)
	return _portrait_thumb(_textures[path])


static func _portrait_thumb(texture: Texture2D) -> Thumbnail:
	var thumb := Thumbnail.new()
	thumb.set_meta("portrait", true)
	thumb.texture = texture
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return thumb


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
	if material:
		set_instance_shader_parameter("palette_row", get_meta("palette_row", 1))
