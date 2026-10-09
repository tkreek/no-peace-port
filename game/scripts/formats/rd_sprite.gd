class_name RdSprite
extends RefCounted
## Decoder for .spx ("RDSX", paletted) and .shw ("RDSW", shadow) sprite lists.
##
## "RDSX"/"RDSW", u32 frame_count, then frames back to back:
##   u32 index, i32 hotspot_x, i32 hotspot_y, u32 width, u32 height,
##   u32 row_offsets[height + 1] (relative to row data; last = row data size),
##   rows of { u8 skip, u8 count, u8 pixels[count] } runs (shadows have no pixel bytes).
##
## Frames are packed into one LA8 atlas: L = palette index (0 for shadows), A = coverage.
## A frame is drawn with its hotspot on the object's ground anchor.
##
## .spr ("RDDX") is a true-colour atlas: u32 width, height, 0, "P16B", RGB555 pixels
## (0 = transparent), then optionally "STAB", u32 count,
## count x { u32 index, x, y, width, height, hotspot_x, hotspot_y }.

const ATLAS_WIDTH := 2048
const PADDING := 1

var is_shadow := false
var is_true_color := false
var is_enhanced := false  ## upscaled set: RGBA atlas at `scale`, optional team mask
var scale := 1.0
var team_mask: Texture2D
var texture: Texture2D
var rects: Array[Rect2i] = []
var hotspots := PackedVector2Array()


static func load_bytes(bytes: PackedByteArray) -> RdSprite:
	var magic := bytes.slice(0, 4).get_string_from_ascii()
	if magic == "RDDX":
		return _load_rddx(bytes)
	if magic != "RDSX" and magic != "RDSW":
		push_error("Unknown sprite magic %s" % magic)
		return null
	var sprite := RdSprite.new()
	sprite.is_shadow = magic == "RDSW"
	var count := bytes.decode_u32(4)

	# First pass: frame headers and shelf layout.
	var headers: Array[PackedInt32Array] = []
	var pos := 8
	var shelf_x := 0
	var shelf_y := 0
	var shelf_h := 0
	for i in count:
		var hotspot_x := bytes.decode_s32(pos + 4)
		var hotspot_y := bytes.decode_s32(pos + 8)
		var width := bytes.decode_u32(pos + 12)
		var height := bytes.decode_u32(pos + 16)
		var table := pos + 20
		var data := table + 4 * (height + 1)
		if shelf_x + width > ATLAS_WIDTH:
			shelf_x = 0
			shelf_y += shelf_h + PADDING
			shelf_h = 0
		sprite.rects.append(Rect2i(shelf_x, shelf_y, width, height))
		sprite.hotspots.append(Vector2(hotspot_x, hotspot_y))
		headers.append(PackedInt32Array([table, data, width, height]))
		shelf_x += width + PADDING
		shelf_h = maxi(shelf_h, height)
		pos = data + bytes.decode_u32(table + 4 * height)

	var atlas_height := maxi(1, shelf_y + shelf_h)
	var pixels := PackedByteArray()
	pixels.resize(ATLAS_WIDTH * atlas_height * 2)

	# Second pass: decode run-length rows into the atlas.
	for i in count:
		var h := headers[i]
		var rect := sprite.rects[i]
		for row in h[3]:
			var p := h[1] + bytes.decode_u32(h[0] + row * 4)
			var end := h[1] + bytes.decode_u32(h[0] + row * 4 + 4)
			var col := 0
			var out_row := ((rect.position.y + row) * ATLAS_WIDTH + rect.position.x) * 2
			while p < end:
				col += bytes[p]
				var n := bytes[p + 1]
				p += 2
				for k in n:
					var o := out_row + (col + k) * 2
					if sprite.is_shadow:
						pixels[o + 1] = 255
					else:
						pixels[o] = bytes[p + k]
						pixels[o + 1] = 255
				if not sprite.is_shadow:
					p += n
				col += n
	var image := Image.create_from_data(ATLAS_WIDTH, atlas_height, false, Image.FORMAT_LA8, pixels)
	sprite.texture = ImageTexture.create_from_image(image)
	return sprite


func frame_count() -> int:
	return rects.size()


## Show `frame` on `sprite` (texture region, hotspot offset, display scale).
func apply(sprite: Sprite2D, frame: int) -> void:
	sprite.texture = texture
	sprite.region_rect = Rect2(rects[frame])
	sprite.offset = -hotspots[frame]
	sprite.scale = Vector2.ONE / scale


## Load an upscaled sprite written by tools/upscale/hd_sprites.py (<base>.png/.json[/.team.png]).
static func load_enhanced(base_path: String) -> RdSprite:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base_path + ".json"))
	var image := Image.load_from_file(base_path + ".png")
	if meta == null or image == null:
		return null
	var sprite := RdSprite.new()
	sprite.is_enhanced = true
	sprite.is_shadow = meta.get("kind") == "shadow"
	sprite.scale = meta.get("scale", 2)
	image.generate_mipmaps()
	sprite.texture = ImageTexture.create_from_image(image)
	for f: Array in meta.frames:
		sprite.rects.append(Rect2i(f[0], f[1], f[2], f[3]))
		sprite.hotspots.append(Vector2(f[4], f[5]))
	if meta.get("team", false):
		var mask := Image.load_from_file(base_path + ".team.png")
		if mask:
			mask.generate_mipmaps()
			sprite.team_mask = ImageTexture.create_from_image(mask)
	return sprite


static func _load_rddx(bytes: PackedByteArray) -> RdSprite:
	var sprite := RdSprite.new()
	sprite.is_true_color = true
	var width := bytes.decode_u32(4)
	var height := bytes.decode_u32(8)
	var rgba := PackedByteArray()
	rgba.resize(width * height * 4)
	for i in width * height:
		var value := bytes.decode_u16(20 + i * 2)
		if value == 0:
			continue
		var r := (value >> 10) & 31
		var g := (value >> 5) & 31
		var b := value & 31
		rgba[i * 4] = (r << 3) | (r >> 2)
		rgba[i * 4 + 1] = (g << 3) | (g >> 2)
		rgba[i * 4 + 2] = (b << 3) | (b >> 2)
		rgba[i * 4 + 3] = 255
	var table := 20 + width * height * 2
	if table + 8 <= bytes.size() and bytes.slice(table, table + 4).get_string_from_ascii() == "STAB":
		for i in bytes.decode_u32(table + 4):
			var o := table + 8 + i * 28
			sprite.rects.append(Rect2i(bytes.decode_u32(o + 4), bytes.decode_u32(o + 8),
					bytes.decode_u32(o + 12), bytes.decode_u32(o + 16)))
			sprite.hotspots.append(Vector2(bytes.decode_s32(o + 20), bytes.decode_s32(o + 24)))
	else:
		sprite.rects.append(Rect2i(0, 0, width, height))
		sprite.hotspots.append(Vector2.ZERO)
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
	sprite.texture = ImageTexture.create_from_image(image)
	return sprite
