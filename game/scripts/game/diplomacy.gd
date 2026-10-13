class_name Diplomacy
extends RefCounted
## How the peoples stand to each other. A skirmish has everyone against everyone (but the
## teams set up for it); a campaign map sets sides in the level editor and its script can
## change them; in a skirmish or network game the players take sides on the Diplomacy page.
## Flags as the original keeps them per ordered pair (AmericaAddOn.exe world+0x8CC, a dword
## per [from][to]): `from` at war with, neutral to or allied to `to`, and `from` seeing what
## `to` sees (0x42c120). Each side's stance is its own: everything that decides whether to
## fight reads the fighter's (the target scans at 0x45d940.., the right click at 0x46c309).
## Units of a people neutral to yours join you when one of yours comes close (the
## "independent" Native Americans of the first tutorial).

const ENEMY := 1
const NEUTRAL := 2
const ALLY := 4
const VISION := 0x20

## What the Diplomacy page sends in one package (order 0x40000002, 0x45723e), and its status
## bar icon.
const PACKAGES := {"food": 100, "wood": 100, "gold": 100, "guns": 2}
const ICONS := {"food": 4, "wood": 2, "gold": 1, "guns": 0}

static var _relations := {}  # from * 16 + to -> flags (absent: at war)
## Whether the players may change sides in this match (the Diplomacy page; not in campaign
## missions, whose scripts keep the sides).
static var negotiable := false
## Told of every side a player takes in the game, to announce it: (from, to, allied).
static var declared := Callable()
## Told of every package handed over, for its receiver's message: (from, to, good, amount).
static var sent := Callable()


static func reset() -> void:
	_relations.clear()
	negotiable = false


static func relation(from: int, to: int) -> int:
	if from == to:
		return ALLY | VISION
	return _relations.get(from * 16 + to, ENEMY)


static func set_relation(from: int, to: int, flags: int) -> void:
	_relations[from * 16 + to] = flags


## The stance part (war, neutral, alliance) both ways; shared sight stays as it was (the
## campaign's trigger actions 30..32, 0x465da4; and the teams a skirmish starts with).
static func set_stance(a: int, b: int, stance: int) -> void:
	for pair in [[a, b], [b, a]]:
		set_relation(pair[0], pair[1], (relation(pair[0], pair[1]) & ~(ENEMY | NEUTRAL | ALLY)) | stance)


static func share_vision(a: int, b: int, on: bool) -> void:
	for pair in [[a, b], [b, a]]:
		var flags := relation(pair[0], pair[1])
		set_relation(pair[0], pair[1], flags | VISION if on else flags & ~VISION)


## People `from` makes people `to` an ally or an enemy (the Diplomacy page, Orders "declare";
## the page's buttons give orders 0x40000004 / 0x40000003 at 0x431f30 / 0x431f10). Taking
## the side it already has changes nothing.
static func declare(from: int, to: int, ally: bool) -> void:
	if not negotiable or from == to or not Player.by_index.has(from) or not Player.by_index.has(to):
		return
	if relation(from, to) & (ALLY if ally else ENEMY) == 0:
		take_side(from, to, ally)


## People `from` takes a side toward people `to` (the player orders carried out at 0x4574a2,
## ally, and 0x45742f, enemy; KI natives 381, 382 give them too). Only from's stance changes:
## `to` stays at war with `from` until it declares otherwise, and fights on meanwhile. Allying
## lets `to` see what `from` sees (0x42d1f0); enmity takes that back (0x42d280). Everyone hears
## of it (texts 372, 373).
static func take_side(from: int, to: int, ally: bool) -> void:
	set_relation(from, to, (relation(from, to) & ~(ENEMY | NEUTRAL | ALLY)) | (ALLY if ally else ENEMY))
	var sight := relation(to, from)
	set_relation(to, from, sight | VISION if ally else sight & ~VISION)
	if declared.is_valid():
		declared.call(from, to, ally)


## People `from` sends a package of `good` to each of `recipients` (the Diplomacy page,
## Orders "send"; carried out at 0x45723e): one package per recipient, each while `from`
## still has a whole package, else that one gets nothing. The original asks for no alliance
## (the manual says allies; 0x431f50, 0x432000 and the executor never look) and takes no fee.
static func send(from: int, good: String, recipients: Array) -> void:
	var giver: Player = Player.by_index.get(from)
	if not negotiable or giver == null or not PACKAGES.has(good):
		return
	var amount: int = PACKAGES[good]
	for to in recipients:
		var taker: Player = Player.by_index.get(int(to))
		if taker == null or int(to) == from or int(giver.resources.get(good, 0)) < amount:
			continue
		giver.add(good, -amount)
		taker.add(good, amount)
		giver.stats[good] -= amount  # the score goes with it
		taker.stats[good] += amount
		if sent.is_valid():
			sent.call(from, int(to), good, amount)


## Whether people `a` fights people `b` (people 0, the wild animals and loose objects, never).
static func hostile(a: int, b: int) -> bool:
	return a > 0 and b > 0 and a != b and relation(a, b) & ENEMY != 0


static func neutral(a: int, b: int) -> bool:
	return a > 0 and b > 0 and a != b and relation(a, b) & NEUTRAL != 0


static func allied(a: int, b: int) -> bool:
	return a == b or (a > 0 and b > 0 and relation(a, b) & ALLY != 0)


## Whether `viewer` sees what people `other` sees ([viewer][other] & 0x20, 0x41395e).
static func sees_for(viewer: int, other: int) -> bool:
	return viewer == other or relation(viewer, other) & VISION != 0


## The relations as numbers, in a fixed order (Sim.checksum).
static func fingerprint() -> PackedFloat64Array:
	var keys := _relations.keys()
	keys.sort()
	var out := PackedFloat64Array()
	for key in keys:
		out.append_array([key, _relations[key]])
	return out


static func save_state() -> Dictionary:
	var out := {}
	for key in _relations:
		out[str(key)] = _relations[key]
	return out


static func restore_state(data: Dictionary) -> void:
	_relations.clear()
	for key in data:
		_relations[int(key)] = int(data[key])
