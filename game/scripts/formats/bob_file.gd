class_name BobFile
extends RefCounted
## Text animation descriptor ([RDBOBFILE]).
##
##   ColTab#n      Typ=C256, Filename=<palette.ftb>          (0 = base, 1..8 = team colours)
##   SubSpriteFile#n Typ=P256|DARK, Filename=<sprite.spx|.shw>
##   AnimBlock#n   SubSpriteFile, AnzDirections, AnzFramesProAnim,
##                 AnimList=frame,ms,frame,ms,...,-N   (-N jumps back N entries; -1 holds)
## Frame index in the sprite file = direction * frames_per_direction + frame.


class Anim:
	var sub_sprite := 0
	var directions := 1
	var frames_per_direction := 1
	var frames := PackedInt32Array()
	var durations_ms := PackedInt32Array()
	var loop_back := 1  # entries to jump back after the last one; 1 = hold last frame

	func loops() -> bool:
		return loop_back > 1


var palettes := PackedStringArray()
var sub_sprites := PackedStringArray()
var sub_sprite_is_shadow: Array[bool] = []
var anims: Array[Anim] = []


static func parse(text: String) -> BobFile:
	var bob := BobFile.new()
	var section := ""
	var current: Anim = null
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("ColTab#"):
			section = "palette"
		elif line.begins_with("SubSpriteFile#"):
			section = "sprite"
			bob.sub_sprites.append("")
			bob.sub_sprite_is_shadow.append(false)
		elif line.begins_with("AnimBlock#"):
			section = "anim"
			current = Anim.new()
			bob.anims.append(current)
		elif "=" in line:
			var key := line.get_slice("=", 0)
			var value := line.get_slice("=", 1).strip_edges()
			match [section, key]:
				["palette", "Filename"]:
					bob.palettes.append(value)
				["sprite", "Filename"]:
					bob.sub_sprites[-1] = value
				["sprite", "Typ"]:
					bob.sub_sprite_is_shadow[-1] = value == "DARK"
				["anim", "SubSpriteFile"]:
					current.sub_sprite = value.to_int()
				["anim", "AnzDirections"]:
					current.directions = value.to_int()
				["anim", "AnzFramesProAnim"]:
					current.frames_per_direction = value.to_int()
				["anim", "AnimList"]:
					var numbers := value.split(",")
					var i := 0
					while i < numbers.size():
						var n := numbers[i].to_int()
						if n < 0:
							current.loop_back = -n
							break
						current.frames.append(n)
						current.durations_ms.append(numbers[i + 1].to_int() if i + 1 < numbers.size() else 100)
						i += 2
	return bob


## Index of the first animation whose sprite file name contains `stem` (body, not shadow).
func find_anim(stem: String) -> int:
	for i in anims.size():
		var sub := anims[i].sub_sprite
		if sub < sub_sprites.size() and not sub_sprite_is_shadow[sub] \
				and sub_sprites[sub].to_lower().contains(stem):
			return i
	return -1


## Index of the shadow animation paired with body animation `index`, or -1.
func shadow_for(index: int) -> int:
	var next := index + 1
	if next < anims.size() and sub_sprite_is_shadow[anims[next].sub_sprite]:
		return next
	return -1
