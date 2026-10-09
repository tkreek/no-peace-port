class_name Settings
extends RefCounted
## Player preferences, kept in user://settings.cfg beside the asset folder path: the original's
## settings (music and sound volume, scroll speed) and the modern ones it lacked (window
## mode and size, vsync, interface scale, edge scrolling).

const PATH := "user://settings.cfg"
const DEFAULTS := {"music_volume": 0.55, "sound_volume": 1.0, "scroll_speed": 1.0, "ui_scale": 1.0,
		"edge_scroll": 1.0, "fullscreen": 0.0, "window_size": 0.0, "vsync": 1.0}
## Window sizes offered in windowed mode (index 0 keeps whatever size the window has).
const WINDOW_SIZES := [Vector2i.ZERO, Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
		Vector2i(2560, 1440), Vector2i(3840, 2160)]

static var _values := {}


static func value(key: String) -> float:
	if _values.is_empty():
		_load()
	return float(_values.get(key, DEFAULTS[key]))


static func enabled(key: String) -> bool:
	return value(key) > 0.5


static func set_value(key: String, v: float) -> void:
	if _values.is_empty():
		_load()
	_values[key] = v
	var config := ConfigFile.new()
	config.load(PATH)  # keep the [paths] section
	for k in _values:
		config.set_value("options", k, _values[k])
	config.save(PATH)
	apply()


static func _load() -> void:
	_values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		for k in DEFAULTS:
			_values[k] = float(config.get_value("options", k, DEFAULTS[k]))


## Push the values to the sound system and the window (the camera and the interface read
## theirs as they go).
static func apply() -> void:
	Sound.sfx_volume = value("sound_volume")
	Sound.set_music_volume(value("music_volume"))
	if DisplayServer.get_name() == "headless":
		return
	var fullscreen := enabled("fullscreen")
	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not fullscreen:
		var size: Vector2i = WINDOW_SIZES[clampi(int(value("window_size")), 0, WINDOW_SIZES.size() - 1)]
		if size != Vector2i.ZERO and DisplayServer.window_get_size() != size:
			var screen := DisplayServer.screen_get_usable_rect()
			size = size.min(screen.size)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled("vsync") else DisplayServer.VSYNC_DISABLED)
