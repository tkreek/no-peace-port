class_name RdImage
extends RefCounted
## Decoders for the original image formats.
##   .pic "RDIC": u32 width, height, 0, then "COLS" + 256 RGB + "PRAW" + 8-bit pixels,
##                or "P16B" RGB555 / "PRGB" RGB24 pixels.
##   .ftb "C256": 256 x RGB555 palette; index 0 is the magenta colour key.


static func rgb555(value: int) -> Color:
	var r := (value >> 10) & 31
	var g := (value >> 5) & 31
	var b := value & 31
	return Color8((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2))


## Returns 256 Colors (index 0 transparent).
static func read_palette(bytes: PackedByteArray) -> PackedColorArray:
	var colors := PackedColorArray()
	if bytes.slice(0, 4).get_string_from_ascii() != "C256":
		push_error("Not a C256 palette")
		return colors
	colors.resize(256)
	for i in 256:
		colors[i] = rgb555(bytes.decode_u16(4 + i * 2))
	colors[0] = Color(0, 0, 0, 0)
	return colors


## Indexed .pic: returns {width, height, palette: PackedByteArray(768 RGB), pixels}.
static func read_indexed_pic(bytes: PackedByteArray) -> Dictionary:
	if bytes.slice(0, 4).get_string_from_ascii() != "RDIC" \
			or bytes.slice(16, 20).get_string_from_ascii() != "COLS":
		return {}
	var width := bytes.decode_u32(4)
	var height := bytes.decode_u32(8)
	return {
		"width": width,
		"height": height,
		"palette": bytes.slice(20, 20 + 768),
		"pixels": bytes.slice(24 + 768, 24 + 768 + width * height),
	}


## Any .pic to an RGB8 Image.
static func pic_to_image(bytes: PackedByteArray) -> Image:
	var width := bytes.decode_u32(4)
	var height := bytes.decode_u32(8)
	var format := bytes.slice(16, 20).get_string_from_ascii()
	var rgb := PackedByteArray()
	rgb.resize(width * height * 3)
	match format:
		"COLS":
			var pic := read_indexed_pic(bytes)
			var palette: PackedByteArray = pic.palette
			var pixels: PackedByteArray = pic.pixels
			for i in width * height:
				var p := pixels[i] * 3
				rgb[i * 3] = palette[p]
				rgb[i * 3 + 1] = palette[p + 1]
				rgb[i * 3 + 2] = palette[p + 2]
		"P16B":
			for i in width * height:
				var c := rgb555(bytes.decode_u16(20 + i * 2))
				rgb[i * 3] = c.r8
				rgb[i * 3 + 1] = c.g8
				rgb[i * 3 + 2] = c.b8
		"PRGB":
			rgb = bytes.slice(20, 20 + width * height * 3)
		_:
			push_error("Unsupported pic format %s" % format)
			return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, rgb)
