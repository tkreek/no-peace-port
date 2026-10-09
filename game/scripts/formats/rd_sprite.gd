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

const ATLAS_WIDTH := 2048
const PADDING := 1

var is_shadow := false
var texture: ImageTexture
var rects: Array[Rect2i] = []
var hotspots := PackedVector2Array()


static func load_bytes(bytes: PackedByteArray) -> RdSprite:
	var magic := bytes.slice(0, 4).get_string_from_ascii()
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
