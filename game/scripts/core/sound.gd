extends Node
## Autoload "Sound": the original sound events and music.
##
## Each object GUID maps event ids to sound ids (data/sounds.json); repeated events are
## variants. Event ids (from the original sfx/properties.ini):

enum Event {
	SELECT = 100, ORDER = 101, DIE = 102, SHOOT = 103, MELEE = 104, CHOP = 105, SWIM = 106, BUILD = 107,
	FINISHED = 150, BURNING = 151, RUBBLE = 152, UNIT_READY = 153,
}

const SOUND_TABLE := "data/sounds.json"
const MAX_VOICES := 24
## How far (px) world sounds carry by default, and work going on (axes, mines, building)
## that you hear beyond the screen edge and through the fog of war, fading with distance.
const HEARING_RANGE := 1800.0
const WORK_RANGE := 3200.0
const FACTION_MUSIC := {"usa": "americans", "mex": "mexicans", "ind": "natives", "des": "outlaws"}

var sfx_volume := 1.0
var music_volume := 0.55
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
	Settings.apply.call_deferred()


## The sound table (assets: data/sounds.json, from the original sfxguids.dat): sound id ->
## {file, volume}, and per GUID the sounds of each event.
func _load_table() -> void:
	var data = GameData.read_json(SOUND_TABLE)
	if not data is Dictionary:
		push_warning("No sound table")
		return
	for id in data.sounds:
		var entry: Dictionary = data.sounds[id]
		_sounds[id.to_int()] = {"path": entry.file, "volume": int(entry.volume)}
	for guid in data.events:
		var table := {}
		for event in data.events[guid]:
			table[event.to_int()] = PackedInt32Array(data.events[guid][event])
		_events[guid.to_int()] = table


## Play an object's sound for `event`. With a position the sound is placed in the world,
## otherwise it plays as interface feedback (selection and order acknowledgements).
## `source` keeps the cooldown per emitter (e.g. each woodcutter) instead of per kind, so
## a nearby axe doesn't silence one further off; `reach` is how far away it can be heard.
func play_event(guid: int, event: int, at = null, cooldown_ms := 250, source := 0, reach := HEARING_RANGE) -> void:
	var options := PackedInt32Array()
	for id in _events.get(guid, {}).get(event, PackedInt32Array()):
		if _sounds.has(id):
			options.append(id)
	# The original table points the Mexican woman's axe at a sound that does not exist;
	# every people's woodcutters use the same "chop_wood".
	if options.is_empty() and event == Event.CHOP:
		var axe := _sound_id("chop_wood")
		if axe >= 0:
			options.append(axe)
	if options.is_empty():
		return
	var key := "%d:%d:%d" % [guid, event, source]
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(key, -100000)) < cooldown_ms:
		return
	_last_played[key] = now
	play_sound(options[randi() % options.size()], at, reach)


## A positional player for a looping work sound (e.g. a worked gold mine), not yet started.
func work_emitter(fragment: String) -> AudioStreamPlayer2D:
	for id in _sounds:
		if String(_sounds[id].path).to_lower().contains(fragment):
			var stream := _stream(_sounds[id].path)
			if stream == null:
				return null
			var p2d := AudioStreamPlayer2D.new()
			p2d.stream = stream
			p2d.max_distance = WORK_RANGE
			p2d.attenuation = 1.0
			var volume: float = _sounds[id].volume / 200.0 if _sounds[id].volume > 0 else 1.0
			p2d.volume_db = linear_to_db(volume * sfx_volume * 0.8)
			return p2d
	return null


func _sound_id(fragment: String) -> int:
	for id in _sounds:
		if String(_sounds[id].path).to_lower().contains(fragment):
			return id
	return -1


## Play the first sound whose file name contains `fragment` (e.g. "chop_wood").
func play_named(fragment: String, at = null) -> void:
	for id in _sounds:
		if String(_sounds[id].path).to_lower().contains(fragment):
			play_sound(id, at)
			return


func play_sound(sound_id: int, at = null, reach := HEARING_RANGE) -> void:
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
		p2d.max_distance = reach
		p2d.attenuation = 1.0
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


## The original mission jingles (sounds/missions/won.mp3, lost.mp3).
func play_mission_result(won: bool) -> void:
	_music.stop()
	var stream := _stream("sounds/missions/won.mp3" if won else "sounds/missions/lost.mp3")
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		add_child(player)
		player.play()


func play_music(faction: String) -> void:
	var path := "music/%s.mp3" % FACTION_MUSIC.get(faction, "title")
	if not GameData.exists(path):
		return
	var stream := AudioStreamMP3.new()
	stream.data = GameData.read(path)
	stream.loop = true
	_music.stream = stream
	_music.volume_db = linear_to_db(maxf(0.001, music_volume))
	_music.play()


func set_music_volume(volume: float) -> void:
	music_volume = volume
	_music.volume_db = linear_to_db(maxf(0.001, volume))


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

