class_name SpriteMaterials
extends RefCounted
## Shared materials for drawing sprite sheets. Team colour is a per-instance shader
## parameter (palette_row), so one material serves every player.

const SheetShader := preload("res://shaders/hd_sprite.gdshader")
const SHADOW_COLOR := Color(0, 0, 0, 0.45)

static var _cache := {}


## Material for a body sheet: team-coloured pixels are tinted through the set's ramps.
static func body(sheet: RdSprite, ramps: Texture2D) -> Material:
	var key := [sheet.get_instance_id(), ramps.get_instance_id() if ramps else 0]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = SheetShader
	material.set_shader_parameter("has_team", sheet.team_mask != null and ramps != null)
	material.set_shader_parameter("team_mask", sheet.team_mask)
	material.set_shader_parameter("ramps", ramps)
	_cache[key] = material
	return material


## Configure a Sprite2D for a sheet (smooth filtering of the upscaled art).
static func prepare(sprite: Sprite2D, _sheet: RdSprite = null) -> void:
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func make_shadow(sprite: Sprite2D) -> void:
	sprite.modulate = SHADOW_COLOR
	sprite.z_index = -1
	sprite.z_as_relative = false
