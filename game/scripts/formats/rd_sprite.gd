class_name RdSprite
extends RefCounted
## A sprite sheet from the asset folder (upscaled from the original by tools/upscale/
## hd_sprites.py and copied by tools/assets/build_assets.py):
##
##   <base>.png        RGBA atlas at `scale` x the original size (LA for shadows)
##   <base>.json       {"scale": 2, "kind": "shadow"?, "team": bool,
##                      "frames": [[x, y, w, h, hotspot_x, hotspot_y], ...]}
##   <base>.team.png   L mask of the team-coloured pixels (tinted through the set's ramps)
##
## A frame is drawn with its hotspot on the object's ground anchor.

var is_shadow := false
var scale := 1.0
var team_mask: Texture2D
var texture: Texture2D
var rects: Array[Rect2i] = []
var hotspots := PackedVector2Array()


static func load_sheet(base_path: String) -> RdSprite:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(base_path + ".json"))
	var image := Image.load_from_file(GameData.picture_file(base_path + ".png"))
	if not meta is Dictionary or image == null:
		return null
	var sprite := RdSprite.new()
	sprite.is_shadow = meta.get("kind") == "shadow"
	sprite.scale = meta.get("scale", 2)
	image.generate_mipmaps()
	sprite.texture = ImageTexture.create_from_image(image)
	for f: Array in meta.frames:
		sprite.rects.append(Rect2i(f[0], f[1], f[2], f[3]))
		sprite.hotspots.append(Vector2(f[4], f[5]))
	if meta.get("team", false):
		var mask := Image.load_from_file(GameData.picture_file(base_path + ".team.png"))
		if mask:
			mask.generate_mipmaps()
			sprite.team_mask = ImageTexture.create_from_image(mask)
	return sprite


func frame_count() -> int:
	return rects.size()


## Show `frame` on `sprite` (texture region, hotspot offset, display scale).
func apply(sprite: Sprite2D, frame: int) -> void:
	sprite.texture = texture
	sprite.region_rect = Rect2(rects[frame])
	sprite.offset = -hotspots[frame]
	sprite.scale = Vector2.ONE / scale
