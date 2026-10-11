class_name WallLine
extends RefCounted
## Walls (the Mexican wall, the outlaws' barricade, the American stockade) are built from
## pieces: corners and two straight pieces, one for each of the isometric diagonals. As on
## the original maps, a "left" piece follows the one before it 32 px right and 16 px down,
## a "right" piece 32 px left and 16 px down, and corners close the ends and the turns.
## Each piece stands on two cells (32 x 16 px); along a diagonal they meet corner to
## corner, which the pathfinder doesn't cut, so a finished line is closed.

## Wall GUIDs by people: [corner, left, right].
const PIECES := {
	"mex": [212, 219, 220],
	"des": [312, 316, 317],
	"usa": [412, 425, 426],
}
const STEP_LEFT := Vector2(32, 16)
const STEP_RIGHT := Vector2(-32, 16)
## The object type names of the pieces that can be built (not the plateau versions).
const TYPE_NAME := "^(mexicans_wall|outlaws_barricade|americans_palisade)_(corner|left|right)_(prairie|meadow)$"


static func is_wall(guid: int) -> bool:
	for pieces: Array in PIECES.values():
		if guid in pieces:
			return true
	return false


## The pieces of a wall from `from` to `to` for the people who build `corner_guid`: the
## longer diagonal first, then (if `to` is off it) a turn onto the other. Each entry is
## {type_id, position}, in building order. A single corner when the two are close.
static func plan(corner_guid: int, from: Vector2, to: Vector2, biome: String) -> Array[Dictionary]:
	var pieces: Array = []
	for people: Array in PIECES.values():
		if people[0] == corner_guid:
			pieces = people
	var out: Array[Dictionary] = []
	if pieces.is_empty():
		return out
	var d := to - from
	var along_left := roundi((d.x / STEP_LEFT.x + d.y / STEP_LEFT.y) / 2.0)
	var along_right := roundi((d.y / STEP_RIGHT.y - d.x / -STEP_RIGHT.x) / 2.0)
	var legs := [[along_left, STEP_LEFT, pieces[1]], [along_right, STEP_RIGHT, pieces[2]]]
	if absi(along_right) > absi(along_left):
		legs.reverse()
	var at := from
	_add(out, pieces[0], at, biome)
	for leg: Array in legs:
		var count: int = absi(leg[0])
		var step: Vector2 = leg[1] * signf(leg[0])
		for i in count:
			at += step
			_add(out, pieces[0] if i == count - 1 else leg[2], at, biome)
	return out


static func _add(out: Array[Dictionary], guid: int, at: Vector2, biome: String) -> void:
	var type_id := GameData.type_for_guid(guid, biome)
	if type_id >= 0:
		out.append({"type_id": type_id, "position": at})
