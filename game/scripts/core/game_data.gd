extends Node
## Autoload "GameData": locates the original installation and serves files from its
## .rda archives. Nothing from the original game is shipped with this project; the
## player points the game at their own copy.
##
## Install dir resolution: --install-dir=<path> on the command line, then
## user://settings.cfg [paths] install_dir, then ../original/install/Programm (dev checkout).

const ARCHIVES := ["america0.rda", "america1.rda", "america2.rda", "america3.rda", "america4.rda"]
const SETTINGS_PATH := "user://settings.cfg"

var install_dir := ""
var archives: Array[RdaArchive] = []
var _bob_cache := {}
var _sprite_cache := {}
var _palette_cache := {}


func _ready() -> void:
	install_dir = _resolve_install_dir()
	for name in ARCHIVES:
		var archive := RdaArchive.new()
		if archive.open(install_dir.path_join(name)) == OK:
			archives.append(archive)
	if archives.is_empty():
		push_error("No original game archives found in '%s'. Pass --install-dir=<folder with america0.rda>." % install_dir)


func is_ready() -> bool:
	return not archives.is_empty()


func cmdline_option(name: String, default: String = "") -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return default


func _resolve_install_dir() -> String:
	var from_args := cmdline_option("install-dir")
	if not from_args.is_empty():
		return from_args
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK and config.has_section_key("paths", "install_dir"):
		return config.get_value("paths", "install_dir")
	return ProjectSettings.globalize_path("res://").path_join("../original/install/Programm").simplify_path()


func read(path: String) -> PackedByteArray:
	for archive in archives:
		if archive.has(path):
			return archive.read(path)
	return PackedByteArray()


func exists(path: String) -> bool:
	for archive in archives:
		if archive.has(path):
			return true
	return false


func read_text(path: String) -> String:
	return read(path).get_string_from_ascii()


func load_image(path: String) -> Image:
	var bytes := read(path)
	return RdImage.pic_to_image(bytes) if not bytes.is_empty() else null


func load_bob(path: String) -> BobFile:
	var key := RdaArchive.normalize(path)
	if not _bob_cache.has(key):
		var text := read_text(path)
		_bob_cache[key] = BobFile.parse(text) if not text.is_empty() else null
	return _bob_cache[key]


func load_sprite(path: String) -> RdSprite:
	var key := RdaArchive.normalize(path)
	if not _sprite_cache.has(key):
		var bytes := read(path)
		_sprite_cache[key] = RdSprite.load_bytes(bytes) if not bytes.is_empty() else null
	return _sprite_cache[key]


## A 256 x N RGBA texture with one row per palette file (row 0 = base, 1..8 = teams).
func load_palette_texture(directory: String, files: PackedStringArray) -> ImageTexture:
	var key := RdaArchive.normalize(directory.path_join(",".join(files)))
	if _palette_cache.has(key):
		return _palette_cache[key]
	var image := Image.create_empty(256, maxi(1, files.size()), false, Image.FORMAT_RGBA8)
	for row in files.size():
		var colors := RdImage.read_palette(read(directory.path_join(files[row])))
		for i in colors.size():
			image.set_pixel(i, row, colors[i])
	var texture := ImageTexture.create_from_image(image)
	_palette_cache[key] = texture
	return texture


func maps_dir() -> String:
	return install_dir.path_join("Levels")
