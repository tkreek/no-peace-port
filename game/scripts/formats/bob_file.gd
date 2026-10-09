class_name BobFile
extends RefCounted
## An animation set (assets: <name>.anims.json, made from the original .bob files by
## tools/assets/build_assets.py):
##
##   sheets  [{file, shadow}]  sprite sheets, by path relative to the set (see RdSprite)
##   anims   [{sheet, directions, frames_per_direction, frames, durations, loop_back}]
##           frames index the sheet: direction * frames_per_direction + frame; loop_back
##           is how many entries to jump back after the last one (1 = hold the last frame)
##   ramps   whether <name>.ramps.png holds the team colour ramps
##   teams   colour rows: 9 for team-coloured sets (neutral + 8 players), else 1


class Anim:
	var sub_sprite := 0
	var directions := 1
	var frames_per_direction := 1
	var frames := PackedInt32Array()
	var durations_ms := PackedInt32Array()
	var loop_back := 1  # entries to jump back after the last one; 1 = hold last frame

	func loops() -> bool:
		return loop_back > 1


var sub_sprites := PackedStringArray()  ## sheet paths relative to the set
var sub_sprite_is_shadow: Array[bool] = []
var anims: Array[Anim] = []
var has_ramps := false
var teams := 1


static func from_json(text: String) -> BobFile:
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		return null
	var bob := BobFile.new()
	for sheet: Dictionary in data.get("sheets", []):
		bob.sub_sprites.append(sheet.get("file", ""))
		bob.sub_sprite_is_shadow.append(sheet.get("shadow", false))
	for entry: Dictionary in data.get("anims", []):
		var anim := Anim.new()
		anim.sub_sprite = int(entry.sheet)
		anim.directions = int(entry.directions)
		anim.frames_per_direction = int(entry.frames_per_direction)
		anim.frames = PackedInt32Array(entry.frames)
		anim.durations_ms = PackedInt32Array(entry.durations)
		anim.loop_back = int(entry.loop_back)
		bob.anims.append(anim)
	bob.has_ramps = data.get("ramps", false)
	bob.teams = int(data.get("teams", 1))
	return bob


## Index of the first animation whose sheet name contains `stem` (body, not shadow).
func find_anim(stem: String) -> int:
	for i in anims.size():
		var sub := anims[i].sub_sprite
		if sub < sub_sprites.size() and not sub_sprite_is_shadow[sub] \
				and sub_sprites[sub].get_file().contains(stem):
			return i
	return -1


## Index of the shadow animation paired with body animation `index`, or -1.
func shadow_for(index: int) -> int:
	var next := index + 1
	if next < anims.size() and sub_sprite_is_shadow[anims[next].sub_sprite]:
		return next
	return -1
