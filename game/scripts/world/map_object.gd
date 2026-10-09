class_name MapObject
extends Node2D
## A static placed object (building or scenery) drawn from its original sprite and shadow.

const PalettedShader := preload("res://shaders/paletted_sprite.gdshader")
const SHADOW_COLOR := Color(0, 0, 0, 0.45)

var object_type: ObjectTypes.ObjectType
var owner_index := 0
var amount := 0


func setup(type: ObjectTypes.ObjectType, owner: int) -> bool:
	object_type = type
	owner_index = owner
	var bob := GameData.load_bob(type.bob_path)
	if bob == null or bob.anims.is_empty():
		return false
	var body_anim := type.anim
	var shadow_anim := type.shadow_anim
	if type.kind == ObjectTypes.Kind.BUILDING:
		# Buildings: anim 0/1 are construction stages; 2/3 hold the finished frame.
		body_anim = 2 if bob.anims.size() > 3 else 0
		shadow_anim = bob.shadow_for(body_anim)
	elif shadow_anim == body_anim:
		shadow_anim = bob.shadow_for(body_anim)
	var palette := GameData.load_palette_texture(type.directory(), bob.palettes)
	var team_row := owner if type.kind == ObjectTypes.Kind.BUILDING and owner > 0 else 0
	if shadow_anim >= 0 and shadow_anim < bob.anims.size():
		var shadow := _sprite(bob, shadow_anim)
		if shadow:
			shadow.modulate = SHADOW_COLOR
			shadow.z_index = -1
			shadow.z_as_relative = false
			add_child(shadow)
	var body := _sprite(bob, body_anim)
	if body == null:
		return false
	if body.has_meta("true_color"):
		add_child(body)
		return true
	var mat := ShaderMaterial.new()
	mat.shader = PalettedShader
	mat.set_shader_parameter("palette", palette)
	body.material = mat
	add_child(body)
	body.set_instance_shader_parameter("palette_row", mini(team_row, bob.palettes.size() - 1))
	return true


func _sprite(bob: BobFile, anim_index: int) -> Sprite2D:
	var anim := bob.anims[anim_index]
	var sheet := GameData.load_sprite(object_type.directory().path_join(bob.sub_sprites[anim.sub_sprite]))
	if sheet == null or anim.frames.is_empty():
		return null
	var frame := anim.frames[anim.frames.size() - 1]
	if frame >= sheet.frame_count():
		return null
	var sprite := Sprite2D.new()
	sprite.texture = sheet.texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(sheet.rects[frame])
	sprite.offset = -sheet.hotspots[frame]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sheet.is_true_color:
		sprite.set_meta("true_color", true)
	return sprite
