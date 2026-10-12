class_name MissionData
extends RefCounted
## What a campaign map says beyond its landscape and objects: the players (SPIELER), the
## named areas (AREA) and the mission script (ABLAUF). Read from the original executable's
## loaders (AmericaAddOn.exe 0x442890, 0x4650c0, 0x464f70); docs/technical/missions.md has
## the layouts and what every condition and action does.

## SPIELER: 8 records of 300 bytes, one per editor slot.
const PLAYER_RECORD := 300
## People as the editor numbers them (record +0x10C).
const PEOPLES := ["ind", "mex", "des", "usa"]

enum Seat { NONE = 0, HUMAN = 1, COMPUTER = 2, INDEPENDENT = 3 }


## One player as the level editor set it up.
class PlayerSlot:
	var slot := 0  ## 0..7, the record's place (the allies mask counts in slots)
	var index := 0  ## the player number units, scripts and colours use (1..8)
	var name := ""  ## a text id in kampagnen.eng, or the name itself
	var faction := ""
	var control := Seat.NONE
	var allies := 0  ## bit per slot of the players on the same side
	var resources := {}
	var level_resources := false  ## takes the level's start resources instead of its own


## A trigger: when every condition holds (or any, once an OR condition came first) its
## actions run, once, unless one of them asks to stay armed.
class Trigger:
	var name := ""
	var conditions: Array[PackedInt32Array] = []  ## [opcode, params...]
	var actions: Array[PackedInt32Array] = []


var players: Array[PlayerSlot] = []
var areas := {}  ## area id -> Rect2 (map pixels)
var area_names := {}  ## area id -> the editor's name for it
var triggers: Array[Trigger] = []


static func from_map(map: AlfMap) -> MissionData:
	var data := MissionData.new()
	data._read_players(map.chunks.get("SPIELER", PackedByteArray()))
	data._read_areas(map.chunks.get("AREA", PackedByteArray()))
	data._read_script(map.chunks.get("ABLAUF", PackedByteArray()))
	return data


func has_script() -> bool:
	return not triggers.is_empty()


func player(index: int) -> PlayerSlot:
	for p in players:
		if p.index == index:
			return p
	return null


func human() -> PlayerSlot:
	for p in players:
		if p.control == Seat.HUMAN:
			return p
	return null


## An area by id; the whole map when the script names one that does not exist (as the
## original does).
func area(id: int, map_size: Vector2) -> Rect2:
	return areas.get(id, Rect2(Vector2.ZERO, map_size))


func _read_players(bytes: PackedByteArray) -> void:
	for slot in bytes.size() / PLAYER_RECORD:
		var at := slot * PLAYER_RECORD
		var people := bytes.decode_s32(at + 0x10C)
		var index := bytes.decode_s32(at)
		if people < 0 or index < 1 or index > 8 or bytes.decode_s32(at + 0x110) == Seat.NONE:
			continue
		var p := PlayerSlot.new()
		p.slot = slot
		p.index = index
		var end := bytes.find(0, at + 12)
		p.name = bytes.slice(at + 12, mini(end if end >= 0 else at + 0x10C, at + 0x10C)).get_string_from_ascii()
		p.faction = PEOPLES[people] if people < PEOPLES.size() else "usa"
		p.control = bytes.decode_s32(at + 0x110) as Seat
		p.allies = bytes.decode_s32(at + 0x114)
		# guns, wood, gold, food: the order 0x422a40 hands them to the stocks the scripts' resource
		# conditions read (5 guns, 2 wood, 4 gold, 1 food)
		p.resources = {"guns": bytes.decode_s32(at + 0x118), "wood": bytes.decode_s32(at + 0x11C),
				"gold": bytes.decode_s32(at + 0x120), "food": bytes.decode_s32(at + 0x124)}
		p.level_resources = bytes.decode_s32(at + 0x128) != 0
		# The loader (0x442890) copies each record in use to its player number's place, so
		# when two records name the same player the later one counts (base/des_03: slot 0,
		# an American with nothing, and slot 7, the outlaws with 2000 wood).
		players = players.filter(func(q: PlayerSlot) -> bool: return q.index != index)
		players.append(p)


## u32 count, then {u32 id, left, top, right, bottom, name length; name}.
func _read_areas(bytes: PackedByteArray) -> void:
	if bytes.size() < 4:
		return
	var at := 4
	for i in bytes.decode_u32(0):
		if at + 24 > bytes.size():
			break
		var id := bytes.decode_s32(at)
		var left := bytes.decode_s32(at + 4)
		var top := bytes.decode_s32(at + 8)
		var right := bytes.decode_s32(at + 12)
		var bottom := bytes.decode_s32(at + 16)
		var length := bytes.decode_s32(at + 20)
		areas[id] = Rect2(left, top, right - left, bottom - top)
		area_names[id] = bytes.slice(at + 24, at + 24 + length).get_string_from_ascii()
		at += 24 + length


## u32 trigger count; per trigger u32 item count and items {u32 opcode, u32 kind, ...}:
## kind 0 an action and 1 a condition (u32 count + params), 2 a note (u32 length + text;
## the editor's name for the trigger).
func _read_script(bytes: PackedByteArray) -> void:
	if bytes.size() < 4:
		return
	var at := 4
	for t in bytes.decode_u32(0):
		var trigger := Trigger.new()
		var items := bytes.decode_s32(at)
		at += 4
		for i in items:
			var opcode := bytes.decode_s32(at)
			var kind := bytes.decode_s32(at + 4)
			at += 8
			if kind == 2:
				var length := bytes.decode_s32(at)
				var text := bytes.slice(at + 4, at + 4 + length)
				var end := text.find(0)
				trigger.name = text.slice(0, end if end >= 0 else text.size()).get_string_from_ascii()
				at += 4 + length
				continue
			var count := bytes.decode_s32(at)
			var item := PackedInt32Array([opcode])
			for k in count:
				item.append(bytes.decode_s32(at + 4 + k * 4))
			at += 4 + count * 4
			if kind == 1:
				trigger.conditions.append(item)
			else:
				trigger.actions.append(item)
		triggers.append(trigger)
