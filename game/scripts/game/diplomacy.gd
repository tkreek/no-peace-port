class_name Diplomacy
extends RefCounted
## How the peoples stand to each other. A skirmish has everyone against everyone; a
## campaign map sets sides in the level editor and its script can change them. Flags as the
## original keeps them per pair (AmericaAddOn.exe world+0x8CC): at war, neutral, allied,
## sharing what they see. Units of a people neutral to yours join you when one of yours comes
## close (the "independent" Native Americans of the first tutorial).

const ENEMY := 1
const NEUTRAL := 2
const ALLY := 4
const VISION := 0x20

static var _relations := {}  # from * 16 + to -> flags (absent: at war)


static func reset() -> void:
	_relations.clear()


static func relation(from: int, to: int) -> int:
	if from == to:
		return ALLY | VISION
	return _relations.get(from * 16 + to, ENEMY)


static func set_relation(from: int, to: int, flags: int) -> void:
	_relations[from * 16 + to] = flags


## The stance part (war, neutral, alliance) both ways; shared sight stays as it was.
static func set_stance(a: int, b: int, stance: int) -> void:
	for pair in [[a, b], [b, a]]:
		set_relation(pair[0], pair[1], (relation(pair[0], pair[1]) & ~(ENEMY | NEUTRAL | ALLY)) | stance)


static func share_vision(a: int, b: int, on: bool) -> void:
	for pair in [[a, b], [b, a]]:
		var flags := relation(pair[0], pair[1])
		set_relation(pair[0], pair[1], flags | VISION if on else flags & ~VISION)


## Whether people `a` fights people `b` (people 0, the wild animals and loose objects, never).
static func hostile(a: int, b: int) -> bool:
	return a > 0 and b > 0 and a != b and relation(a, b) & ENEMY != 0


static func neutral(a: int, b: int) -> bool:
	return a > 0 and b > 0 and a != b and relation(a, b) & NEUTRAL != 0


static func allied(a: int, b: int) -> bool:
	return a == b or (a > 0 and b > 0 and relation(a, b) & ALLY != 0)


## Whether `viewer` sees what people `other` sees.
static func sees_for(viewer: int, other: int) -> bool:
	return viewer == other or relation(other, viewer) & VISION != 0


static func save_state() -> Dictionary:
	var out := {}
	for key in _relations:
		out[str(key)] = _relations[key]
	return out


static func restore_state(data: Dictionary) -> void:
	_relations.clear()
	for key in data:
		_relations[int(key)] = int(data[key])
