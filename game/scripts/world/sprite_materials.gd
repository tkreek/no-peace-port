class_name SpriteMaterials
extends RefCounted
## Shared materials for drawing original (paletted) or enhanced (upscaled) sprite sheets.
## Team colour is a per-instance shader parameter, so one material serves every player.

const PalettedShader := preload("res://shaders/paletted_sprite.gdshader")
const EnhancedShader := preload("res://shaders/hd_sprite.gdshader")
const SHADOW_COLOR := Color(0, 0, 0, 0.45)

static var _cache := {}


## Material for a body sheet; null when the sheet needs none (true-colour classic sprites).
static func body(sheet: RdSprite, palette: Texture2D, ramps: Texture2D) -> Material:
	var key := [sheet.get_instance_id(), palette.get_instance_id() if palette else 0]
	if _cache.has(key):
		return _cache[key]
	var material: ShaderMaterial = null
	if sheet.is_enhanced:
		material = ShaderMaterial.new()
		material.shader = EnhancedShader
		material.set_shader_parameter("has_team", sheet.team_mask != null and ramps != null)
		material.set_shader_parameter("team_mask", sheet.team_mask)
		material.set_shader_parameter("ramps", ramps)
	elif not sheet.is_true_color:
		material = ShaderMaterial.new()
		material.shader = PalettedShader
		material.set_shader_parameter("palette", palette)
	_cache[key] = material
	return material


## Configure a Sprite2D for a sheet's filtering (crisp classic pixels, smooth enhanced art).
static func prepare(sprite: Sprite2D, sheet: RdSprite) -> void:
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if sheet.is_enhanced \
			else CanvasItem.TEXTURE_FILTER_NEAREST


static func make_shadow(sprite: Sprite2D) -> void:
	sprite.modulate = SHADOW_COLOR
	sprite.z_index = -1
	sprite.z_as_relative = false
