extends Node
## Autoload "Sound": the original sound events and music.
##
## sfx/sfxguids.dat:
##   u32 version, u32 sound_count, sound_count x { u32 id; u32 volume; char path[100] }
##   u32 object_count, object_count x { u32 guid; u32 n; u32 events[20]; u32 sounds[20] }
## Each object GUID (see GUIDS.INI) maps event ids to sound ids; repeated events are variants.
## Event ids (sfx/properties.ini):

enum Event {
	SELECT = 100, ORDER = 101, DIE = 102, SHOOT = 103, MELEE = 104, CHOP = 105, SWIM = 106, BUILD = 107,
	FINISHED = 150, BURNING = 151, RUBBLE = 152, UNIT_READY = 153,
}

const SFX_TABLE := "sfx/sfxguids.dat"
const MAX_VOICES := 24
const FACTION_MUSIC := {"usa": "USA.mp3", "mex": "MEX.mp3", "ind": "IND.mp3", "des": "DES.mp3"}

var sfx_volume := 1.0
var _sounds := {}       # sound id -> {path, volume}
var _events := {}       # guid -> {event id -> PackedInt32Array of sound ids}
var _streams := {}      # path -> AudioStream
var _last_played := {}  # "guid:event" -> msec, to avoid stacking identical sounds
var _music := AudioStreamPlayer.new()


func _ready() -> void:
	add_child(_music)
	_music.bus = "Master"
	if GameData.is_ready():
		_load_table()


func _load_table() -> void:
	var d := GameData.read(SFX_TABLE)
	if d.size() < 8:
		push_warning("No sound table")
		return
	var count := d.decode_u32(4)
	var pos := 8
	for i in count:
		var path := _c_string(d, pos + 8, 100)
		_sounds[d.decode_u32(pos)] = {"path": path, "volume": d.decode_u32(pos + 4)}
		pos += 108
	var objects := d.decode_u32(pos)
	pos += 4
	for i in objects:
		var guid := d.decode_u32(pos)
		var n := mini(d.decode_u32(pos + 4), 20)
		var table := {}
		for k in n:
			var event := d.decode_u32(pos + 8 + k * 4)
			var sound := d.decode_u32(pos + 88 + k * 4)
			if not table.has(event):
				table[event] = PackedInt32Array()
			table[event].append(sound)
		_events[guid] = table
		pos += 168


## Play an object's sound for `event`. With a position the sound is placed in the world,
## otherwise it plays as interface feedback (selection and order acknowledgements).
func play_event(guid: int, event: int, at = null, cooldown_ms := 250) -> void:
	var options: PackedInt32Array = _events.get(guid, {}).get(event, PackedInt32Array())
	if options.is_empty():
		return
	var key := "%d:%d" % [guid, event]
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(key, -100000)) < cooldown_ms:
		return
	_last_played[key] = now
	play_sound(options[randi() % options.size()], at)


func play_sound(sound_id: int, at = null) -> void:
	var info: Dictionary = _sounds.get(sound_id, {})
	if info.is_empty():
		return
	var stream := _stream(info.path)
	if stream == null or get_child_count() > MAX_VOICES:
		return
	var volume: float = info.volume / 200.0 if info.volume > 0 else 1.0
	var player: Node
	if at is Vector2:
		var p2d := AudioStreamPlayer2D.new()
		p2d.position = at
		p2d.max_distance = 1400.0
		p2d.attenuation = 1.5
		p2d.volume_db = linear_to_db(volume * sfx_volume)
		p2d.stream = stream
		get_tree().current_scene.add_child(p2d)
		player = p2d
	else:
		var p := AudioStreamPlayer.new()
		p.volume_db = linear_to_db(volume * sfx_volume)
		p.stream = stream
		add_child(p)
		player = p
	player.finished.connect(player.queue_free)
	player.play()


## Decode every referenced sound; returns [ok, failed paths].
func verify_all() -> Array:
	var ok := 0
	var failed := PackedStringArray()
	for id in _sounds:
		var path: String = _sounds[id].path
		if _stream(path) != null:
			ok += 1
		else:
			failed.append(path)
	return [ok, failed]


## The original mission jingles: sfx/missions/gewonnen.mp3 / verloren.mp3.
func play_mission_result(won: bool) -> void:
	_music.stop()
	var stream := _stream("sfx/missions/gewonnen.mp3" if won else "sfx/missions/verloren.mp3")
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		add_child(player)
		player.play()


func play_music(faction: String) -> void:
	var path := GameData.install_dir.path_join("Music").path_join(FACTION_MUSIC.get(faction, "TIT.mp3"))
	if not FileAccess.file_exists(path):
		return
	var stream := AudioStreamMP3.new()
	stream.data = FileAccess.get_file_as_bytes(path)
	stream.loop = true
	_music.stream = stream
	_music.volume_db = linear_to_db(0.55)
	_music.play()


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var bytes := GameData.read(path)
	var stream: AudioStream = null
	if bytes.is_empty():
		push_warning("Missing sound %s" % path)
	elif path.ends_with(".mp3"):
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		stream = mp3
	else:
		stream = AudioStreamWAV.load_from_buffer(bytes)
	_streams[path] = stream
	return stream


static func _c_string(d: PackedByteArray, offset: int, size: int) -> String:
	var raw := d.slice(offset, offset + size)
	var end := raw.find(0)
	return raw.slice(0, end if end >= 0 else size).get_string_from_ascii()
