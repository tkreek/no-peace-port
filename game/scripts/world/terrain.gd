class_name Terrain
extends Node2D
## Renders an AlfMap's terrain with the original biome atlas and ground textures.

const GROUND_LAYERS := 40
const GROUND_SIZE := 512
const TerrainShader := preload("res://shaders/terrain.gdshader")

var map: AlfMap
var biome := "steppe"
var _material: ShaderMaterial


func setup(alf_map: AlfMap, biome_name: String) -> void:
	map = alf_map
	biome = biome_name
	var directory := "%s/gfx/landschaft" % biome
	var atlas := RdImage.read_indexed_pic(GameData.read(directory.path_join("steppe.pic")))
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
	_material.set_shader_parameter("ground", _ground_textures(directory, atlas.palette))
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
func _ground_textures(directory: String, atlas_palette: PackedByteArray) -> Texture2DArray:
	var layers: Array[Image] = []
	for index in GROUND_LAYERS:
		var image := GameData.load_image(directory.path_join("steppe%d.pic" % index))
		var layer := Image.create_empty(GROUND_SIZE, GROUND_SIZE, false, Image.FORMAT_RGB8)
		if image:
			for y in range(0, GROUND_SIZE, image.get_height()):
				for x in range(0, GROUND_SIZE, image.get_width()):
					layer.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, y))
		else:
			layer.fill(Color8(atlas_palette[index * 3], atlas_palette[index * 3 + 1], atlas_palette[index * 3 + 2]))
		layer.generate_mipmaps()
		layers.append(layer)
	var array := Texture2DArray.new()
	array.create_from_images(layers)
	return array
