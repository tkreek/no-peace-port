extends Node
## Autoload "Sound": the original sound events and music.
##
## Each object GUID maps event ids to sound ids (data/sounds.json); repeated events are
## variants. Event ids (from the original sfx/properties.ini):

enum Event {
	SELECT = 100, ORDER = 101, DIE = 102, SHOOT = 103, MELEE = 104, CHOP = 105, SWIM = 106, BUILD = 107,
	SPECIAL_1 = 120, SPECIAL_2 = 121, SPECIAL_3 = 122, SPECIAL_4 = 123, SPECIAL_5 = 124,
	FINISHED = 150, BURNING = 151, RUBBLE = 152, UNIT_READY = 153,
}

## How AmericaAddOn.exe uses the table (its lookup, 0x420250): an object plays the sound of
## the first entry for the event and nothing when it has none: no variants picked at random,
## no stand-ins. Who plays what, and when, is in docs/technical/file-formats.md ("Sound in
## the executable").

const SOUND_TABLE := "data/sounds.json"
const MAX_VOICES := 24
## Copies of one recording heard at once in the world (more rifles or axes only make a
## din). A new one nearer the view than the farthest playing takes its place.
const SAME_SOUND_LIMIT := 4
## Interface sounds play on a channel, each cutting off the one before: clicks (selection
## and order replies, "not possible") and alerts (warnings, fanfares, messages) apart, so
## clicking about doesn't silence a warning.
enum Channel { CLICK, ALERT }
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
var _channels := {}     # Channel -> AudioStreamPlayer
var _in_world := {}     # sound id -> AudioStreamPlayer2D playing it in the world
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
## Returns how long the sound lasts (s), 0 when none played.
func play_event(guid: int, event: int, at = null, cooldown_ms := 250, source := 0, reach := HEARING_RANGE) -> float:
	var key := "%d:%d:%d" % [guid, event, source]
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(key, -100000)) < cooldown_ms:
		return 0.0
	var options := event_sounds(guid, event)
	if options.is_empty():
		return 0.0
	_last_played[key] = now
	return play_sound(options[randi() % options.size()], at, reach)


## An alert's sound (its event "select" unless told otherwise), on the alert channel.
func play_alert(guid: int, event := Event.SELECT) -> float:
	var options := event_sounds(guid, event)
	if options.is_empty():
		return 0.0
	return play_sound(options[randi() % options.size()], null, HEARING_RANGE, Channel.ALERT)


## The sound an object makes for `event` (its table's first entry for it), or none.
func event_sounds(guid: int, event: int) -> PackedInt32Array:
	var table: Dictionary = _events.get(guid, {})
	for id in table.get(event, PackedInt32Array()):
		return PackedInt32Array([id]) if _sounds.has(id) else PackedInt32Array()
	return PackedInt32Array()


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


## Play the first sound whose file name contains `fragment` (e.g. "chop_wood"), or with
## `any` one picked at random from all that do (e.g. "water_splash" for _1 to _3).
func play_named(fragment: String, at = null, any := false) -> void:
	var matches := PackedInt32Array()
	for id in _sounds:
		if String(_sounds[id].path).to_lower().contains(fragment):
			matches.append(id)
			if not any:
				break
	if not matches.is_empty():
		play_sound(matches[randi() % matches.size()], at)


## Returns how long the sound lasts (s), 0 when none played. Without a position it
## plays on `channel`, cutting off what played there before.
func play_sound(sound_id: int, at = null, reach := HEARING_RANGE, channel := Channel.CLICK) -> float:
	var info: Dictionary = _sounds.get(sound_id, {})
	if info.is_empty():
		return 0.0
	var stream := _stream(info.path)
	if stream == null:
		return 0.0
	var volume: float = info.volume / 200.0 if info.volume > 0 else 1.0
	if not at is Vector2:
		var p: AudioStreamPlayer = _channels.get(channel)
		if p == null:
			p = AudioStreamPlayer.new()
			add_child(p)
			_channels[channel] = p
		p.stop()
		p.volume_db = linear_to_db(volume * sfx_volume)
		p.stream = stream
		p.play()
		return stream.get_length()
	if not _make_room(sound_id, at, SAME_SOUND_LIMIT):
		return 0.0
	var p2d := AudioStreamPlayer2D.new()
	p2d.position = at
	p2d.max_distance = reach
	p2d.attenuation = 1.0
	p2d.volume_db = linear_to_db(volume * sfx_volume)
	p2d.stream = stream
	get_tree().current_scene.add_child(p2d)
	p2d.finished.connect(p2d.queue_free)
	p2d.play()
	_in_world.get_or_add(sound_id, []).append(p2d)
	return stream.get_length()


## Whether one more copy of `sound_id` may play at `at`: under `limit` copies, or by
## stopping the copy farthest from the view when that is farther than `at`; and under
## MAX_VOICES in all.
func _make_room(sound_id: int, at: Vector2, limit: int) -> bool:
	var total := 0
	for id in _in_world:
		_in_world[id] = _in_world[id].filter(func(p) -> bool: return is_instance_valid(p) and p.playing)  # untyped: freed players are passed too
		total += _in_world[id].size()
	var same: Array = _in_world.get(sound_id, [])
	if same.size() < limit:
		return total < MAX_VOICES
	var camera := get_viewport().get_camera_2d()
	var view := camera.get_screen_center_position() if camera else at
	var farthest: AudioStreamPlayer2D = null
	for p: AudioStreamPlayer2D in same:
		if farthest == null or p.position.distance_squared_to(view) > farthest.position.distance_squared_to(view):
			farthest = p
	if farthest.position.distance_squared_to(view) <= at.distance_squared_to(view):
		return false
	farthest.stop()
	farthest.queue_free()
	same.erase(farthest)
	return true


## Something neutral (a stray cow or horse, an empty building) takes a people's colours
## ("Neutrale Einheiten umfärben"); a herd joining at once is heard once.
func play_neutral_taken(at: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get("neutral", -100000)) >= 2500:
		_last_played["neutral"] = now
		play_named("neutral_units_recolour", at)


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

