class_name Terrain
extends Node2D
## Renders an AlfMap's terrain with the original biome atlas and ground textures.

const GROUND_LAYERS := 40
const GROUND_SIZE := 512
const TerrainShader := preload("res://shaders/terrain.gdshader")

var map: AlfMap
var biome := "steppe"
var _material: ShaderMaterial
var _ground_average := PackedColorArray()  # mean colour per ground layer
var _atlas: Dictionary


func setup(alf_map: AlfMap, biome_name: String) -> void:
	map = alf_map
	biome = biome_name
	var directory := "%s/gfx/landschaft" % biome
	var atlas := RdImage.read_indexed_pic(GameData.read(directory.path_join("steppe.pic")))
	_atlas = atlas
	if atlas.is_empty():
		push_error("Missing terrain atlas for biome %s" % biome)
		return

	_material = ShaderMaterial.new()
	_material.shader = TerrainShader
	_material.set_shader_parameter("cells", ImageTexture.create_from_image(_cell_image()))
	_material.set_shader_parameter("atlas_index", ImageTexture.create_from_image(
			Image.create_from_data(atlas.width, atlas.height, false, Image.FORMAT_R8, atlas.pixels)))
	_material.set_shader_parameter("atlas_palette", ImageTexture.create_from_image(_palette_image(atlas.palette)))
	_material.set_shader_parameter("atlas_tiles_per_row", atlas.width / AlfMap.CELL_SIZE)
	var enhanced := _enhanced_dir()
	_material.set_shader_parameter("ground", _ground_textures(directory, atlas.palette, enhanced))
	if not enhanced.is_empty():
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(enhanced.path_join("terrain.json")))
		var art := Image.load_from_file(enhanced.path_join("terrain_atlas.png"))
		art.generate_mipmaps()
		_material.set_shader_parameter("enhanced", true)
		_material.set_shader_parameter("hd_atlas", ImageTexture.create_from_image(art))
		_material.set_shader_parameter("hd_layers", ImageTexture.create_from_image(
				Image.load_from_file(enhanced.path_join("terrain_layers.png"))))
		_material.set_shader_parameter("hd_tile", int(meta.tile))
		_material.set_shader_parameter("hd_columns", int(meta.columns))
	_material.set_shader_parameter("ground_period", float(GROUND_SIZE))
	_material.set_shader_parameter("map_size", Vector2(map.pixel_size()))
	material = _material
	queue_redraw()


func _draw() -> void:
	if map:
		draw_rect(Rect2(Vector2.ZERO, map.pixel_size()), Color.WHITE)


func _cell_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(map.columns * map.rows * 2)
	for i in map.tile_ids.size():
		bytes[i * 2] = map.tile_ids[i] & 0xFF
		bytes[i * 2 + 1] = map.tile_ids[i] >> 8
	return Image.create_from_data(map.columns, map.rows, false, Image.FORMAT_RG8, bytes)


func _palette_image(rgb: PackedByteArray) -> Image:
	var image := Image.create_from_data(256, 1, false, Image.FORMAT_RGB8, rgb)
	image.convert(Image.FORMAT_RGBA8)
	return image


## One layer per placeholder palette index; textures are tiled up to GROUND_SIZE square.
## Indices without a texture file fall back to their flat placeholder colour.
## Folder of the upscaled terrain for this biome, or "" to use the original pixels.
func _enhanced_dir() -> String:
	if GameData.enhanced_dir.is_empty():
		return ""
	var dir := GameData.enhanced_dir.path_join("terrain").path_join(biome)
	return dir if FileAccess.file_exists(dir.path_join("terrain.json")) else ""


func _ground_textures(directory: String, atlas_palette: PackedByteArray, enhanced: String) -> Texture2DArray:
	var layers: Array[Image] = []
	var size := GROUND_SIZE * (2 if not enhanced.is_empty() else 1)
	for index in GROUND_LAYERS:
		var image: Image
		if not enhanced.is_empty() and FileAccess.file_exists(enhanced.path_join("ground_%d.png" % index)):
			image = Image.load_from_file(enhanced.path_join("ground_%d.png" % index))
			image.convert(Image.FORMAT_RGB8)
		else:
			image = GameData.load_image(directory.path_join("steppe%d.pic" % index))
			if image and not enhanced.is_empty():
				image.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_LANCZOS)
		var layer := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
		if image:
			for y in range(0, size, image.get_height()):
				for x in range(0, size, image.get_width()):
					layer.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, y))
		else:
			layer.fill(Color8(atlas_palette[index * 3], atlas_palette[index * 3 + 1], atlas_palette[index * 3 + 2]))
		layer.generate_mipmaps()
		layers.append(layer)
		# The smallest mip level is the layer's average colour.
		var tiny := layer.duplicate()
		tiny.resize(1, 1, Image.INTERPOLATE_TRILINEAR)
		_ground_average.append(tiny.get_pixel(0, 0))
	var array := Texture2DArray.new()
	array.create_from_images(layers)
	return array


## One pixel per 32 px cell, averaging a 4x4 sample of each cell's composited colour.
func overview_image() -> Image:
	var image := Image.create_empty(map.columns, map.rows, false, Image.FORMAT_RGB8)
	var width: int = _atlas.width
	var per_row := width / AlfMap.CELL_SIZE
	var pixels: PackedByteArray = _atlas.pixels
	var palette: PackedByteArray = _atlas.palette
	for i in map.tile_ids.size():
		var tile := map.tile_ids[i]
		var origin := Vector2i(tile % per_row, tile / per_row) * AlfMap.CELL_SIZE
		var sum := Color(0, 0, 0)
		for sy in 4:
			for sx in 4:
				var p := origin + Vector2i(4 + sx * 8, 4 + sy * 8)
				var index := pixels[p.y * width + p.x]
				if index < GROUND_LAYERS:
					sum += _ground_average[index]
				else:
					sum += Color8(palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2])
		image.set_pixel(i % map.columns, i / map.columns, sum / 16.0)
	return image
