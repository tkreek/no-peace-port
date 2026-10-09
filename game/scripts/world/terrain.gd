class_name Terrain
extends Node2D
## Renders an AlfMap's terrain with the landscape's tile atlas and ground textures
## (assets: terrain/prairie, terrain/meadow).

const GROUND_LAYERS := 40
const GROUND_SIZE := 512
const TerrainShader := preload("res://shaders/terrain.gdshader")
const FOLDERS := {"steppe": "terrain/prairie", "wiese": "terrain/meadow"}

static var _atlases := {}

var map: AlfMap
var biome := "steppe"
var _material: ShaderMaterial
var _ground_average := PackedColorArray()  # mean colour per ground layer
var _atlas: Dictionary
var _cells: Image
var _cells_texture: ImageTexture


func setup(alf_map: AlfMap, biome_name: String) -> void:
	map = alf_map
	biome = biome_name
	var atlas := atlas_for(biome)
	_atlas = atlas
	if atlas.is_empty():
		push_error("Missing terrain atlas for biome %s" % biome)
		return
	var folder := folder_for(biome)
	_material = ShaderMaterial.new()
	_material.shader = TerrainShader
	_cells = _cell_image()
	_cells_texture = ImageTexture.create_from_image(_cells)
	_material.set_shader_parameter("cells", _cells_texture)
	_material.set_shader_parameter("atlas_index", ImageTexture.create_from_image(
			Image.create_from_data(atlas.width, atlas.height, false, Image.FORMAT_R8, atlas.pixels)))
	_material.set_shader_parameter("atlas_palette", ImageTexture.create_from_image(_palette_image(atlas.palette)))
	_material.set_shader_parameter("atlas_tiles_per_row", atlas.width / AlfMap.CELL_SIZE)
	_material.set_shader_parameter("ground", _ground_textures(folder, atlas.palette))
	var meta: Dictionary = GameData.read_json(folder.path_join("terrain.json"))
	var art := GameData.load_image(folder.path_join("terrain_atlas.png"))
	art.generate_mipmaps()
	_material.set_shader_parameter("enhanced", true)
	_material.set_shader_parameter("hd_atlas", ImageTexture.create_from_image(art))
	_material.set_shader_parameter("hd_layers", ImageTexture.create_from_image(
			GameData.load_image(folder.path_join("terrain_layers.png"))))
	_material.set_shader_parameter("hd_tile", int(meta.tile))
	_material.set_shader_parameter("hd_columns", int(meta.columns))
	_material.set_shader_parameter("ground_period", float(GROUND_SIZE))
	_material.set_shader_parameter("map_size", Vector2(map.pixel_size()))
	material = _material
	queue_redraw()


## The landscape's terrain folder in the assets.
static func folder_for(biome_name: String) -> String:
	return FOLDERS.get(biome_name, FOLDERS.steppe)


## The landscape's 32 px tile atlas as palette indices (indices 5..39 stand for the ground
## textures, the rest are colours): {width, height, pixels, palette (256 RGB)}.
static func atlas_for(biome_name: String) -> Dictionary:
	if not _atlases.has(biome_name):
		var folder := folder_for(biome_name)
		var image := GameData.load_image(folder.path_join("atlas_index.png"))
		var palette = GameData.read_json(folder.path_join("atlas_palette.json"))
		if image == null or not palette is Array:
			return {}
		image.convert(Image.FORMAT_L8)
		_atlases[biome_name] = {"width": image.get_width(), "height": image.get_height(),
				"pixels": image.get_data(), "palette": PackedByteArray(palette)}
	return _atlases[biome_name]


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


## Show changed tiles (the map editor): `rect` in cells.
func refresh_cells(rect: Rect2i) -> void:
	if _cells == null:
		return
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var tile := map.tile_ids[y * map.columns + x]
			_cells.set_pixel(x, y, Color8(tile & 0xFF, tile >> 8, 0))
	_cells_texture.update(_cells)


func _palette_image(rgb: PackedByteArray) -> Image:
	var image := Image.create_from_data(256, 1, false, Image.FORMAT_RGB8, rgb)
	image.convert(Image.FORMAT_RGBA8)
	return image


## One layer per placeholder palette index (ground_<index>.png, tiled up to twice
## GROUND_SIZE square); indices without a texture get their flat placeholder colour.
func _ground_textures(folder: String, atlas_palette: PackedByteArray) -> Texture2DArray:
	var layers: Array[Image] = []
	var size := GROUND_SIZE * 2
	for index in GROUND_LAYERS:
		var image := GameData.load_image(folder.path_join("ground_%d.png" % index))
		if image:
			image.convert(Image.FORMAT_RGB8)
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
	for i in map.tile_ids.size():
		image.set_pixel(i % map.columns, i / map.columns, tile_color(map.tile_ids[i]))
	return image


## The average colour of an atlas tile with its ground textures (a 4x4 sample).
func tile_color(tile: int) -> Color:
	var width: int = _atlas.width
	var per_row := width / AlfMap.CELL_SIZE
	var pixels: PackedByteArray = _atlas.pixels
	var palette: PackedByteArray = _atlas.palette
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
	return sum / 16.0
