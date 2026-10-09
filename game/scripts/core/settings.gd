class_name Settings
extends RefCounted
## Player preferences (the original's settings: music and sound volume, scroll speed),
## kept in user://settings.cfg beside the install paths.

const PATH := "user://settings.cfg"
const DEFAULTS := {"music_volume": 0.55, "sound_volume": 1.0, "scroll_speed": 1.0}

static var _values := {}


static func value(key: String) -> float:
	if _values.is_empty():
		_load()
	return float(_values.get(key, DEFAULTS[key]))


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


## Push the values to the sound system (the camera reads scroll speed itself).
static func apply() -> void:
	Sound.sfx_volume = value("sound_volume")
	Sound.set_music_volume(value("music_volume"))
