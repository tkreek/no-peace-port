class_name Thumbnail
extends TextureRect
## A command-button picture made from an object's own sprite (finished building or a unit
## facing the viewer), drawn with its team colours.

static var _textures := {}  # portrait path -> texture


## The portrait for a GUID (assets: portraits/...), or null.
static func portrait(guid: int) -> Thumbnail:
	return from_image(GameData.stats(guid).get("icon", ""))


## A portrait picture (portraits/....png), or null.
static func from_image(path: String) -> Thumbnail:
	if path.is_empty() or not GameData.exists(path):
		return null
	if not _textures.has(path):
		var image := GameData.load_image(path)
		image.generate_mipmaps()  # large pictures shown at button size
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
	var bob := GameData.load_bob(type.anims)
	if bob == null or bob.anims.is_empty():
		return null
	var anim_index := 0
	var frame_in_anim := -1
	if type.kind == ObjectTypes.Kind.BUILDING:
		anim_index = 2 if bob.anims.size() > 3 else 0
	elif type.kind == ObjectTypes.Kind.UNIT:
		anim_index = maxi(0, bob.find_anim("idle"))
		frame_in_anim = 0
	else:  # trees, rocks, mines: the type's own animation, first frame
		anim_index = clampi(type.anim, 0, bob.anims.size() - 1)
		frame_in_anim = 0
	var anim := bob.anims[anim_index]
	var sheet := GameData.load_set_sheet(type.anims, bob, anim.sub_sprite)
	if sheet == null:
		return null
	var frame := anim.frames[frame_in_anim if frame_in_anim >= 0 else anim.frames.size() - 1]
	if type.kind == ObjectTypes.Kind.UNIT:
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
	thumb.material = SpriteMaterials.body(sheet, GameData.load_ramps(type.anims))
	thumb.set_meta("palette_row", mini(team, bob.teams - 1))
	return thumb


func _ready() -> void:
	if material:
		set_instance_shader_parameter("palette_row", get_meta("palette_row", 1))
