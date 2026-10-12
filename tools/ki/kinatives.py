# KI native function table (AmericaAddOn.exe dispatcher 0x43a250).
# NATIVES[id] = (name, number of arguments popped, number of results pushed, description)
# SIGS[id]    = argument list in push order and result
# DETAILS[id] = engine detail (wrapper / order code / fields)
# Argument and result counts were recovered by emulating every handler (emu.py) and verified
# by stack-balance analysis of all 1311 modules (checkstack.py).

NATIVES = {}
SIGS = {}
DETAILS = {}


def N(i, name, na, nr, sig, desc, det=''):
    NATIVES[i] = (name, na, nr, desc)
    SIGS[i] = sig
    if det:
        DETAILS[i] = det


# ---- operators --------------------------------------------------------------------------
N(1, 'add', 2, 1, '(a, b) -> a+b', 'Integer addition (32-bit wrap).')
N(2, 'sub', 2, 1, '(a, b) -> a-b', 'Subtraction.')
N(3, 'mul', 2, 1, '(a, b) -> a*b', 'Multiplication (low 32 bits).')
N(4, 'div', 2, 1, '(a, b) -> a/b', 'Signed division truncating toward 0; b == 0 is treated as 1.')
N(5, 'band', 2, 1, '(a, b) -> a&b', 'Bitwise and (used to test object flag masks).')
N(6, 'bor', 2, 1, '(a, b) -> a|b', 'Bitwise or (used to combine flag constants).')
N(7, 'bxor', 2, 1, '(a, b) -> a^b', 'Bitwise xor.')
N(8, 'mod', 2, 1, '(a, b) -> a%b', 'Signed remainder (C `%`); b == 0 would fault in the original (idiv).')
N(10, 'gt', 2, 1, '(a, b) -> a>b', 'Signed comparison, pushes 0/1.')
N(11, 'lt', 2, 1, '(a, b) -> a<b', 'Signed comparison.')
N(12, 'eq', 2, 1, '(a, b) -> a==b', 'Equality.')
N(13, 'ne', 2, 1, '(a, b) -> a!=b', 'Inequality.')
N(14, 'ge', 2, 1, '(a, b) -> a>=b', 'Signed comparison.')
N(15, 'le', 2, 1, '(a, b) -> a<=b', 'Signed comparison.')
N(20, 'land', 2, 1, '(a, b) -> a&&b', 'Logical and (both operands already evaluated; no short circuit).')
N(21, 'lor', 2, 1, '(a, b) -> a||b', 'Logical or (no short circuit).')
N(22, 'lnot', 1, 1, '(a) -> !a', 'Logical not.')

# ---- arrays (module-local growable arrays, VM.md 3) ---------------------------------------
for base, ty in ((31, 'int'), (42, 'unit'), (45, 'building'), (48, 'neutral')):
    N(base, 'aget_' + ty, 2, 1, '(&arr, i) -> value',
      'Element i of %s array `arr` (passed with pushi). 0 <= i <= 1000 grows the array to i+10 '
      'elements (new ones 0); other i give 0. If `arr` does not resolve the handler returns '
      'without pushing.' % ty, 'store 0x40f270 then 0x459e50')
    N(base + 1, 'aset_' + ty, 3, 0, '(&arr, i, value)',
      'arr[i] = value (same growth rule; i outside 0..1000 is ignored).',
      'store 0x40f270 then 0x459e20')
    N(base + 2, 'acopy_' + ty, 2, 0, '(&dst, &src)',
      'dst = copy of src (resized to src\'s size).', '0x459f00')
N(40, 'sleep', 1, 0, '(ms)', 'Sleep: module+0x664 = ms; the module executes nothing until that many '
  'ms of game time have passed (decremented by 20*KISpeed per tick). Identical to 41.', '0x43ec10')
N(41, 'wait', 1, 0, '(ms)', 'Same handler as 40; the id the compiler emits for `wait` (40 is never used).',
  '0x43ec10')

# ---- object properties --------------------------------------------------------------------
for i, ty in ((101, 'building'), (103, 'unit'), (105, 'neutral')):
    N(i, 'getx_' + ty, 1, 1, '(h) -> x', 'X position in map pixels of the %s (obj+0x2c); -1 if the handle does not resolve.' % ty, '0x4384a0')
    N(i + 1, 'gety_' + ty, 1, 1, '(h) -> y', 'Y position in map pixels (obj+0x30); -1 if gone.', '0x4384c0')
for i, ty in ((110, 'building'), (111, 'unit'), (112, 'neutral')):
    N(i, 'exists_' + ty, 1, 1, '(h) -> bool', 'True if h != 0 and the object still exists (0x42b820 finds it). The scripts\' "is alive" test.', '0x438d90')
for i, ty in ((113, 'building'), (114, 'unit'), (115, 'neutral')):
    N(i, 'hasflags_' + ty, 2, 1, '(h, mask) -> bool', '(state(obj) & mask) == mask, state = the dynamic flags returned by virtual +0x2c (see "Flags"); false if gone. E.g. hasflags_unit(e, 4) = idle, hasflags_building(b, 0x10) = producing.', '0x438500')
for i, ty in ((116, 'building'), (117, 'unit'), (118, 'neutral')):
    N(i, 'hasanyflag_' + ty, 2, 1, '(h, mask) -> bool', '(state(obj) & mask) != 0.', '0x438530')
N(365, 'hasflags', 2, 1, '(h, mask) -> bool', '(class(obj) & mask) == mask with the static class flags obj+0x24 (0x4324a0), e.g. hasflags(e, 0x2000) = can ride, 0x80000000 = leader.', '0x439850')
N(366, 'hasanyflag', 2, 1, '(h, mask) -> bool', '(class(obj) & mask) != 0 (class flags obj+0x24).', '0x439880')
for i in (295, 296, 297):
    N(i, ('guid_neutral', 'guid_unit', 'guid_building')[i - 295], 1, 1, '(h) -> guid', 'Object type GUID (obj+0xc, e.g. 104, 458); -1 if gone.', '0x438d70')
for i in (312, 367, 379):
    N(i, {312: 'owner_building', 367: 'owner_neutral', 379: 'owner_unit'}[i], 1, 1, '(h) -> player', 'Owner player number (obj+0x14); 0 if gone. (Ids 312/367/379 share one handler; the scripts use 379 for units and 367 for cattle.)', '0x4398b0')
N(306, 'health_unit', 1, 1, '(h) -> percent', 'Hit points in percent: obj+0x4 * 100 / obj+0x470 (units); -1 if gone.', '0x438e60')
N(307, 'health_building', 1, 1, '(h) -> percent', 'Hit points in percent: obj+0x4 * 100 / obj+0x578 (buildings); -1 if gone.', '0x438e20')
N(132, 'resource_left', 1, 1, '(h) -> amount', 'obj+0x9c (0x423c70): what is left in a gold mine (class 0x8, types 700-703); the scripts test `> 0` before sending miners. 0 if gone.', '0x4385f0')
N(217, 'free_garrison', 1, 1, '(building) -> n', 'Garrison capacity obj+0xdc (building property 8, max 10) minus units inside obj+0xd8.', '0x438f80')
N(218, 'free_seats', 1, 1, '(transport) -> n', 'Passenger capacity obj+0x3d4 (raft 8, riverboats 8/10, stagecoach 2, default 4) minus passengers obj+0x3d0.', '0x438fb0')
N(300, 'stored_gold', 1, 1, '(building) -> n', 'obj+0x6fc of a storage building: amount stored (gold in a gold warehouse); -1 if gone. (Other classes use +0x6fc differently: a gatherer\'s resource object, a fighter\'s leash radius.)', '0x438db0')
N(359, 'stored_gold_', 1, 1, '(building) -> n', 'Same field as 300, 0 if gone.', '0x439800')
N(303, 'cargo', 1, 1, '(wagon) -> n', 'obj+0x6b0: cargo loaded on a wagon (travois, covered wagon, stagecoach); kind at +0x6b4. 0 if gone.', '0x438df0')
N(337, 'producing', 1, 1, '(building) -> guid', 'Type id currently in production (queue +0x108[0]) if the queue (+0x104) is not empty, else 0.', '0x4392f0')
N(353, 'energy_percent', 1, 1, '(unit) -> percent', 'Magic/healing energy: obj+0x394 * 100 / obj+0x380 if the unit has an energy pool (byte +0x398: medicine man, nurse, nun, priest...), else 0. Energy refills 1 per tick up to 10000 (15000 with upgrade 917).', '0x439530')
N(356, 'walk_speed', 1, 1, '(unit) -> speed', 'obj+0x47c: LaufenSpeed table value (50..160) from property 110; 0 if gone.', '0x439760')
N(357, 'special_state', 1, 1, '(h) -> n', 'obj+0x700: assassin 0 normal / 1 dug in / 2 stalking / 4 struck; field bit 1 growing, bit 2 ripe; trap 1 armed. 0 if gone.', '0x439780')
N(373, 'attack_range', 1, 1, '(unit) -> px', 'obj+0x3e4: ranged attack range in px (64, 100, 200, 350, 500 by property 115); used as search radius. 0 if gone.', '0x439ab0')
N(400, 'ability_charge', 1, 1, '(building) -> 0..100', 'obj+0xa0 >> 8: the building ability meter (grows 1 per 5.12 s after upgrade 965 or 968-970; 401 costs 25, 399 costs 75). 0 if gone.', '0x439e10')
N(134, 'distance', 4, 1, '(x1, y1, x2, y2) -> d', 'Euclidean distance, `(int)sqrt(dx*dx + dy*dy)` (x87 fsqrt, truncated by 0x49bb26 = _ftol).')

# ---- player state ------------------------------------------------------------------------
N(308, 'me', 0, 1, '() -> player', 'The KI\'s own player number (KI+0x828).')
N(188, 'my_nation', 0, 1, '() -> nation', 'Own nation: dword at 0x5aefdc + player*300 (+0x10c of the SPIELER record copy at 0x5aeed0) : 0 Natives, 1 Mexicans, 2 Outlaws, 3 USA, -1 none (checked against the campaign maps\' SPIELER records and the per-nation modules).', '0x438d50')
N(189, 'nation', 1, 1, '(player) -> nation', 'Nation of any player.', '0x438d50')
for i, nm, arr in ((271, 'wood', '0x58fe34'), (272, 'gold', '0x58fe14'), (273, 'horses', '0x58fdd4'),
                   (274, 'food', '0x58fdb4'), (278, 'guns', '0x58fe74')):
    N(i, 'my_' + nm, 0, 1, '() -> n', 'Own stock of %s (%s[player]).' % (nm, arr))
    N(i + 10, nm, 1, 1, '(player) -> n', 'Stock of %s of any player (%s[p]; no range check).' % (nm, arr))
N(301, 'my_warehouse_gold', 0, 1, '() -> n', 'Gold lying in my gold warehouses (0x58fe54[p] = player manager +0x124, the sum of their +0x6fc). Spendable gold is 272.', '0x438de0')
N(302, 'warehouse_gold', 1, 1, '(player) -> n', 'Same for any player.', '0x438de0')
N(275, 'my_free_living_space', 0, 1, '() -> n', 'min(unit limit 0x58fd74[0], housing 0x58fd94[p]) - population 0x58fd74[p] (0x422ad0): how many more units fit.', '0x438cb0')
N(285, 'free_living_space', 1, 1, '(player) -> n', 'Same for any player.', '0x438cb0')
N(279, 'my_population', 0, 1, '() -> n', 'Own population (living space used, 0x58fd74[p]); 0 if p not 1..8.', '0x439720')
N(289, 'unit_limit', 0, 1, '() -> n', 'The match unit limit 0x58fd74[0] = (menu choice + 3) * 25, 75..200.', '0x439740')
N(270, 'my_count', 1, 1, '(guid) -> n', 'Number of own objects of type guid (world 0x42a0b0(player, guid)): the tally of the player\'s object list, which has no wall pieces (walls, barricades, stockades are in list 10, created at 0x42698e), so this is 0 for them.', '0x438c50')
N(280, 'count', 2, 1, '(player, guid) -> n', 'Number of objects of type guid owned by player.', '0x438c50')
N(340, 'count_checked', 2, 1, '(player, guid) -> n', 'Same as 280 but 0 unless 0 <= player <= 10 (player 0 = neutral: `native_340(0, 482)` counts free cows).', '0x4393a0')
N(276, 'my_farms', 0, 1, '() -> n', 'Own count of GUIDs 408 + 208 + 108 (USA farm, Mexican finca, Native field).', '0x438cd0')
N(286, 'farms', 1, 1, '(player) -> n', 'Same for any player.', '0x438cd0')
N(277, 'my_fields', 0, 1, '() -> n', 'Own count of GUID 149 (field).', '0x438d10')
N(287, 'fields', 1, 1, '(player) -> n', 'Same for any player.', '0x438d10')
N(199, 'my_corrals', 0, 1, '() -> n', 'Own count of GUIDs 405 + 305 + 205 + 105 (ranch, corral, hacienda, corral: horse breeding).', '0x4390c0')
N(334, 'upgrade_known', 1, 1, '(id) -> bool', 'Own upgrade id (900-999) researched or in research: byte 0x590e38[p*100 + id-900] or 0x590b18[...] set; false outside 900..999.', '0x439920')
N(369, 'upgrade_done', 1, 1, '(id) -> bool', 'Own upgrade id (900-999): byte 0x590b18[p*100 + id-900] set.', '0x439980')
N(352, 'difficulty', 0, 1, '() -> s', 'From the difficulty option v = [0x803a0c] (0 very easy, 1 easy, 2 medium, 3 difficult): returns 0 for v = 0, else 4 - v (easy 3, medium 2, difficult 1). Scripts subtract it from unit counts and treat 0 specially (`if (s == 0) s = 3`).')
N(363, 'victory_condition', 0, 1, '() -> n', '[0x802b0c]: 0 everybody for themselves, 1 kill the leader, 2 destroy the main buildings.')
N(364, 'map_players', 0, 1, '() -> n', 'Number of players / start positions of the current map (map list 0x7d3c60, entry +0x2d8; 0x442210). Scripts: `maxspieler`, `< 5`.', '0x439840')
N(224, 'map_width', 0, 1, '() -> px', 'Map size x ([0x7d2a68]); scripts clamp coordinates to 1..map_width.', '0x439010')
N(225, 'map_height', 0, 1, '() -> px', 'Map size y ([0x7d2a6c]).', '0x439020')
N(206, 'my_relation', 1, 1, '(player) -> bits', 'Relation of me to player (0x42bdd0(me-1, p-1)): bit 0x1 hostile, 0x4 allied, 0x20 set by a declaration, | 0x40 if the other player is a computer, | 0x80 if human; 0x10 if either player is absent; 8 if p == me.', '0x438fe0')
N(207, 'relation', 2, 1, '(p1, p2) -> bits', 'Same for two players; 8 if equal.', '0x438fe0')
N(362, 'zero', 0, 1, '() -> 0', 'Calls 0x41d4a0, which returns 0. Unused.', '0x41d4a0')

# ---- shared KI state ---------------------------------------------------------------------
N(219, 'getglobal', 1, 1, '(i) -> v', 'KI-wide global i (KI+0x19938, 256 ints shared by all modules of the player); 0 if i outside 0..255.')
N(220, 'setglobal', 2, 0, '(i, v)', 'global[i] = v (ignored outside 0..255).')
N(221, 'lock', 1, 0, '(k)', 'Take semaphore k (KI+0x82d+k). If it is taken the module blocks until it is free (module+0x658 = k; 0x43efa0). k outside 0..255: no effect.', '0x43efa0')
N(222, 'unlock', 1, 0, '(k)', 'sem[k] = 0.')
N(223, 'is_locked', 1, 1, '(k) -> bool', 'sem[k] == 1; 0 outside range.')
N(304, 'atomic_begin', 0, 0, '()', 'KI+0x818 = 1, KI+0x81c = current slot: all other modules of this player stop executing (timers still run) until atomic_end.')
N(305, 'atomic_end', 0, 0, '()', 'KI+0x818 = 0.')
for b, nm, sig, d in ((233, 'tset', '(t, i, v)', 'table[t][i] = v (KI+0x930 + (t*256+i)*4); t 0..99, i 0..255, else ignored.'),
                      (237, 'tget', '(t, i) -> v', 'table[t][i]; 0 if out of range.'),
                      (241, 'tremove', '(t, i)', 'Remove element i: table[t][i..254] = table[t][i+1..255], table[t][255] = 0.'),
                      (245, 'tinsert', '(t, i, v)', 'Insert at i: elements i..254 move up one (255 is lost), table[t][i] = v.')):
    for k, ty in enumerate(('int', 'unit', 'neutral', 'building')):  # +2 never used: 'neutral' is a guess
        na = 3 if nm in ('tset', 'tinsert') else 2
        N(b + k, nm + '_' + ty, na, 1 if nm == 'tget' else 0, sig, d + ' (The four ids of the group share one handler; the compiler picks one by element type.)')
N(335, 'random', 2, 1, '(lo, hi) -> n', 'Pseudo-random number in lo..hi-1: idx = ([0x7d3c5c] + 1) mod 1000 (one counter for all players); r = table[idx] (1000 CRT rand() values 0..32767 at 0x7d2c9c, filled by 0x4382c0 when the KI is reset); n = lo + (hi-lo)*r/32767, then n = max(n, lo), then n = min(n, hi-1). So hi itself only comes out as hi-1, and random(a, a) returns a-1.', '0x439270')
N(329, 'next_attacked_building', 0, 1, '() -> bool', 'Pop the oldest handle from the player\'s "building damaged" queue (filled by the building damage routine 0x40c970 via 0x42d070) into module+0x4; false if empty. Read it with 332.', '0x43dd40')
N(330, 'next_attacked_unit', 0, 1, '() -> bool', 'Same for the "unit damaged" queue (unit damage routine 0x418f90 via 0x42d0b0). Read with 331.', '0x43dd80')
N(331, 'last_event_unit', 0, 1, '() -> h', 'module+0x4 (handle taken by 329/330).')
N(332, 'last_event_building', 0, 1, '() -> h', 'module+0x4 (same field as 331).')

# ---- constants ---------------------------------------------------------------------------
_consts = {150: 0x20000, 151: 8, 152: 4, 153: 2, 154: 0x40, 155: 0x10, 156: 1, 157: 0x800,
           158: 0x1000000, 159: 4, 160: 0x8000, 161: 419, 162: 409, 163: 455, 164: 8, 165: 0x10,
           166: 0x40000, 167: 2, 168: 0x80, 169: 0x20, 170: 0x400, 171: 0x1000, 172: 0x2000,
           173: 0x4000, 174: 0x10000, 175: 0x80000, 176: 0x100000, 177: 0x200000, 178: 0x400000,
           179: 0x800000, 180: 0x2000000, 181: 0x4000000, 182: 0, 183: 1, 184: 2, 185: 3,
           186: 401, 187: 0x40, 190: 0x100, 191: 0x200, 192: 1, 193: 2, 194: 4, 195: 8,
           196: 0x400, 197: 0x800, 198: 0x10, 310: 0x20, 350: 0x1000}
CLASS_BITS = {0x1: 'static scenery', 0x2: 'unit', 0x4: 'building', 0x8: 'gold mine (types 700-703)',
              0x10: 'tree (types 500-535, map grid list 9)', 0x20: 'livestock (buffalo, cow)', 0x40: 'tent / packable tepee',
              0x80: 'food drop-off', 0x100: 'gold warehouse', 0x200: 'wood drop-off',
              0x400: 'armed unit (also the trap building)', 0x800: 'gatherer (receives gold-mining orders)', 0x1000: 'military',
              0x2000: 'can ride', 0x4000: 'can garrison / building that takes a garrison', 0x8000: 'builder',
              0x10000: 'gatherer', 0x20000: 'main building (HQ)', 0x40000: 'wagon', 0x80000: 'storage building (set at run time)',
              0x100000: 'farm / granary', 0x200000: 'exhausted field', 0x400000: 'field',
              0x800000: 'women', 0x1000000: 'civilian worker (receives wood-cutting orders)', 0x2000000: 'horse',
              0x4000000: 'animal', 0x8000000: 'unit transport (boat, raft, stagecoach)',
              0x10000000: 'can camouflage (run time)', 0x20000000: 'detects hidden units (archers, trappers, hunters)', 0x40000000: 'horse corral',
              0x80000000: 'leader / hero'}
STATE_BITS_UNIT = {0x1: 'worker task bit', 0x2: 'worker task bit', 0x4: 'idle', 0x8: 'working / building', 0x20: 'wagon bit',
                   0x80: 'worker task bit', 0x100: 'moving', 0x400: 'inside a building', 0x800: 'inside a transport',
                   0x2000: 'fighter in combat', 0x4000: 'task 0x40000/0x80000', 0x8000: 'medicine man casting',
                   0x10000: 'camouflaged', 0x20000: 'damaged', 0x100000: 'task 0x400', 0x800000: '+0x418 bit 2',
                   0x1000000: 'following', 0x2000000: 'carrying wood', 0x4000000: 'carrying gold',
                   0x8000000: 'carrying food', 0x10000000: 'mounted', 0x20000000: 'dug in', 0x40000000: 'animal',
                   0x80000000: 'hero'}
STATE_BITS_BUILDING = {0x4: 'finished', 0x10: 'producing', 0x200: 'under construction', 0x1000: 'below 40% HP',
                       0x20000: 'damaged', 0x40: 'field lying fallow (+0x6f9 == 0)'}
_cnote = {161: 'GUID 419 (USA gold store)', 162: 'GUID 409 (USA saw mill)', 163: 'GUID 455 (covered wagon)',
          186: 'GUID 401 (USA house)', 182: 'stance 0', 183: 'stance 1', 184: 'stance 2', 185: 'stance 3',
          156: 'state 0x1 (worker task) / relation bit hostile', 159: 'class building / state idle (units) or finished (buildings)',
          152: 'class building / state idle', 165: 'state producing (buildings) / class 0x10 tree', 191: 'state under construction',
          196: 'state inside a building', 197: 'state inside a transport', 190: 'state moving',
          168: 'state worker task bit / relation: human', 187: 'relation: computer / class tent',
          192: 'relation bit: hostile', 193: 'relation bit 0x2', 194: 'relation bit: allied', 195: 'relation: same player (8)',
          198: 'relation: player absent (0x10)', 154: 'class bit 0x40 = tent; with find_neutral any mask containing 0x10 or 0x40 switches to the tree grid search, which is how the scripts find trees',
          171: 'class military / state below 40% HP'}
for i, v in _consts.items():
    note = _cnote.get(i) or ('class bit: ' + CLASS_BITS[v] if v in CLASS_BITS else '')
    N(i, 'const_%d' % i, 0, 1, '() -> %s' % (hex(v) if v > 9 else v),
      'Pushes %s%s.' % (hex(v) if v > 9 else v, (' (' + note + ')') if note else ''))

# ---- searches (nearest object queries over the per-player object lists 0x7d2778 + p*0x3c) ---
# Common terms: "class" = obj+0x24 flags (0x4324a0), "state" = virtual method +0x2c flags;
# "claimed" = bit (1<<player) in obj+0x1c, set by the claiming searches and by 380, cleared by
# 123-125. Claiming searches skip objects this player already claimed, so a loop of searches
# returns distinct objects; the scripts release (123-125) objects they only wanted to look at.
_find = 'Nearest (squared distance to x,y) object in player %s\'s list whose class flags contain all bits of `mask`%s and whose state has any bit of `state` (or state == 0), not yet claimed by me; the result is claimed for me (vtable +0x28). Handle or 0. If mask has bit 0x10 or 0x40 the search goes instead through the map grid (world+0x241f74, 0x405bf0, radius 10000) and nothing is claimed.'
N(107, 'find_my_building', 4, 1, '(mask, x, y, state) -> h', _find % ('ME', ' | 4 (building)'), '0x438560 -> 0x42bce0 -> 0x424ad0')
N(108, 'find_neutral', 4, 1, '(mask, x, y, state) -> h', _find % ('0 (neutral objects: trees 0x40, mines 0x8, stores...)', ''), '0x438560 -> 0x42bce0')
N(109, 'find_my_unit', 4, 1, '(mask, x, y, state) -> h', _find % ('ME', ' | 2 (unit)'), '0x438560 -> 0x42bce0')
N(200, 'find_building_of', 5, 1, '(player, mask, x, y, state) -> h', _find % ('`player`', ' | 4'), '0x438560')
N(201, 'find_object_of', 5, 1, '(player, mask, x, y, state) -> h', _find % ('`player`', ''), '0x438560')
N(202, 'find_unit_of', 5, 1, '(player, mask, x, y, state) -> h', _find % ('`player`', ' | 2'), '0x438560')
_findg = 'Nearest object of type `guid` (obj+0xc) in player %s\'s list, state any-of `state` (or 0), not claimed by me; claims it. Handle or 0.'
N(139, 'find_my_building_type', 4, 1, '(guid, x, y, state) -> h', _findg % 'ME', '0x438a60 -> 0x42bd70 -> 0x424e10')
N(140, 'find_my_unit_type', 4, 1, '(guid, x, y, state) -> h', _findg % 'ME' + ' (same handler as 139)', '0x438a60')
N(141, 'find_neutral_type', 4, 1, '(guid, x, y, state) -> h', _findg % '0' + ' Horses 480, buffalo 481, cows 482.', '0x438a60')
N(203, 'find_building_type_of', 5, 1, '(player, guid, x, y, state) -> h', _findg % '`player`', '0x438a60')
N(204, 'find_unit_type_of', 5, 1, '(player, guid, x, y, state) -> h', _findg % '`player`' + ' (same handler as 203)', '0x438a60')
N(205, 'find_neutral_type_owned', 5, 1, '(player, guid, x, y, state) -> h', 'Nearest object of type guid in the neutral list (player 0) whose owner (obj+0x14) is `player` (cattle and horses in a player\'s corral), state any-of, unclaimed; claims it.', '0x438a90 -> 0x424ec0')
_near = 'Nearest object in player `player`\'s list with %s; no claim test, nothing claimed. Handle or 0 (0 also if player is not 0..8).'
N(368, 'nearest_unit', 5, 1, '(player, x, y, mask, state) -> h', _near % 'class flags containing mask|2 and state any-of `state` (or 0)', '0x4398d0 -> 0x424c40')
N(389, 'nearest_object', 5, 1, '(player, x, y, mask, state) -> h', _near % 'class flags containing mask and state any-of `state` (or 0)', '0x4398d0 -> 0x424c40')
N(392, 'nearest_building', 5, 1, '(player, x, y, mask, state) -> h', _near % 'class flags containing mask|4 and state any-of `state` (or 0)', '0x4398d0 -> 0x424c40')
N(370, 'nearest_excluding', 5, 1, '(player, x, y, mask, notstate) -> h', _near % 'class flags containing mask and (state & notstate) == 0', '0x4399c0 -> 0x424ce0')
N(371, 'nearest_type', 5, 1, '(player, x, y, guid, notstate) -> h', _near % 'type guid and (state & notstate) == 0', '0x439a10 -> 0x424d80')
N(393, 'nearest_type_', 5, 1, '(player, x, y, guid, notstate) -> h', 'Same handler as 371.', '0x439a10')
N(383, 'claim_nearest', 5, 1, '(player, x, y, mask, notstate) -> h', 'Nearest in player\'s list with class containing mask|2, (state & notstate) == 0, not claimed by me; claims it (sets obj+0x1c bit).', '0x439b40 -> 0x4252e0')
N(384, 'claim_nearest_type', 5, 1, '(player, x, y, guid, notstate) -> h', 'Nearest of type guid with (state & notstate) == 0, not claimed by me; claims it. The standard way to pick an idle own unit: `e = claim_nearest_type(me(), mainx, mainy, 459, 0xc00)`.', '0x439b90 -> 0x4253b0')
N(385, 'claim_first', 3, 1, '(player, ignored, notstate) -> h', 'First object (list order) in player\'s list with (state & notstate) == 0 not claimed by me (class mask 0 = any; the second argument is replaced by 0); claims it. Unused.', '0x439be0 -> 0x425470')
N(386, 'claim_first_type', 3, 1, '(player, guid, notstate) -> h', 'First object of type guid, (state & notstate) == 0, not claimed by me; claims it.', '0x439c30 -> 0x4254e0')
N(380, 'claim', 1, 0, '(h)', 'Claim the object for me (virtual +0x28(me): obj+0x1c |= 1<<me) so my claiming searches skip it.', '0x439ad0')
for _i, _t in ((123, 'building'), (124, 'neutral'), (125, 'unit')):
    N(_i, 'release_' + _t, 1, 0, '(h)', 'Release my claim (virtual +0x24(me)): the object can be found again by my claiming searches. (123-125 share one handler.)', '0x438620')
N(120, 'first_my_building', 1, 1, '(mask) -> h', 'world 0x42bca0(me, mask|4, 0) -> 0x424a70: first (list order) own object whose class contains mask|4 and that is active (virtual +0x54); scripts: mask 0x20000 = main building.', '0x4384e0')
N(121, 'first_my_unit', 1, 1, '(mask) -> h', '0x42bca0(me, mask|2, 0): first own unit with those class bits (0x40000 = covered wagon / settler wagon, 0x80000000).', '0x4384e0')
N(122, 'first_object', 1, 1, '(mask) -> h', '0x42bca0(0, mask, 0) over player 0.', '0x4384e0')

# ---- orders (engine order queue 0x80b278, executed by 0x456450; see VM.md 5) --------------
# Unit orders are ignored unless the object is a unit/horse/animal/transport that is not dying;
# building orders unless it is a building/field. There is no ownership check.
_O = lambda code: 'order %s' % code
N(143, 'move', 3, 0, '(unit, x, y)', 'Move to (x, y) (order 0x20000001 -> 0x41bb20, the normal right-click move; ignored while the unit is inside a building or transport). Not sent unless x > 0 and y > 0.', '0x438b00')
N(311, 'move_', 3, 0, '(unit, x, y)', 'Same handler as 143.', '0x438b00')
N(328, 'attack_move', 3, 0, '(unit, x, y)', 'Move to (x, y) attacking enemies met on the way and stay there (order 0x2000001a -> 0x41bb50, a one-way patrol leg; only the AI sends it). Not sent unless x > 0 and y > 0. The most used order.', '0x439240')
N(327, 'patrol', 3, 0, '(unit, x, y)', 'Patrol between the current position and (x, y) (order 0x20000019 -> 0x41b9b0).', '0x439210')
N(145, 'attack', 2, 0, '(unit, target)', 'Attack (or hunt) an object (order 0x20000007 -> virtual +0xc8; fighters 0x436290, no effect for workers and wagons).', '0x438b50')
N(251, 'hunt', 2, 0, '(unit, animal)', 'Same handler as 145; the scripts use it on buffalo and cows.', '0x438b50')
N(250, 'attack_building', 2, 0, '(unit, building)', 'Attack a building (order 0x2000000b -> virtual +0xc4, fighters 0x4368c0); the scripts use it on palisades blocking the way.', '0x438bf0')
N(149, 'worker_attack', 2, 0, '(unit, target)', 'Melee attack by a non-fighter with a melee value (order 0x2000000a -> 0x419910).', '0x438bd0')
N(146, 'set_stance', 2, 0, '(unit, stance)', 'Set the behaviour/stance (order 0x20000008 -> 0x4196b0, unit+0x468; for 2 and 3 the current position becomes the guard point). Values 0..3 (constants 182-185); the UI sends 0/1/2. Order of meanings probably aggressive, defensive, hold ground, passive (texts 60-63) - unverified.', '0x438b70')
N(336, 'stop', 1, 0, '(unit)', 'Stop (order 0x20000026 -> 0x4186a0: task = idle, also stops passengers).', '0x4392d0')
N(326, 'follow', 2, 0, '(unit, target)', 'Follow an object (order 0x20000018 -> 0x41b980; used for escorts).', '0x4391f0')
N(374, 'follow_', 2, 0, '(unit, target)', 'Same handler as 326.', '0x4391f0')
N(211, 'enter', 2, 0, '(unit, building)', 'Enter / garrison a building (order 0x20000012 -> 0x41a640; unit and building need class 0x4000: towers, forts, quarters).', '0x438ec0')
N(212, 'into_corral', 2, 0, '(horse, corral)', 'Put a horse into a corral (order 0x20000011 -> 0x461540; target class 0x40000000).', '0x438ee0')
N(213, 'board', 2, 0, '(unit, transport)', 'Board a boat / raft / coach (order 0x20000013 -> 0x41a900; transport class 0x8000000).', '0x438f00')
N(214, 'unload', 2, 0, '(transport, index)', 'Unload passenger number `index` (order 0x20000014 -> 0x41ac30; needs a free landing cell within 128 px).', '0x438f20')
N(358, 'unload_all', 1, 0, '(transport)', 'If the object has class 0x8000000: send order 0x20000014(t, 0) once per passenger (count obj+0x3d0).', '0x4397a0')
N(130, 'chop_wood', 2, 0, '(worker, tree)', 'Order 0x20000005(worker, tree.x, tree.y) -> 0x402860: cut wood at the tree nearest to the given tree\'s position (nearest class-0x10 object within 1000 px).', '0x4385b0')
N(131, 'mine_gold', 2, 0, '(worker, mine)', 'Dig gold at a mine (order 0x20000004 -> 0x402420; refused when the mine is empty, 0x423c70 == 0).', '0x438590')
N(133, 'transport_to', 2, 0, '(wagon, building)', 'Wagon transport (order 0x2000000c -> virtual +0xb8, 0x464180): to the main building = deliver, to a gold warehouse etc. = load there.', '0x438650')
N(360, 'transport_to_', 2, 0, '(wagon, building)', 'Same handler as 133.', '0x438650')
N(252, 'work_field', 2, 0, '(worker, field)', 'Work a field (order 0x2000000d -> 0x402bf0; women, class 0x800000).', '0x438c10')
N(253, 'mount', 2, 0, '(unit, horse)', 'Mount a horse (order 0x20000010 -> 0x419fc0; unit class 0x2000, not mounted).', '0x438c30')
N(361, 'animal_into', 2, 0, '(animal, building)', 'Lead an animal into a building, e.g. a cow to the slaughterhouse/corral (order 0x20000024 -> 0x43fbf0).', '0x439820')
N(144, 'build_repair', 2, 0, '(worker, building)', 'Help construct or repair a building (order 0x20000003 -> 0x41b420).', '0x438b30')
N(135, 'build_near', 4, 1, '(worker, guid, x, y) -> bool', 'Place a building: spiral search from (x, y) outward in 16 px steps up to +-500 px for a spot on the worker\'s terrain level (0x407cf0) where the footprint fits (placement helper 0x429a20/0x45c900, terrain mask 0x100, 0x1000 for shipyards 218/315/418), then order 0x20000002(worker, x, y, guid) (place site, deduct cost, build) or 0x2000000f for a field (149). Returns 1 if a spot was found; the spot is kept in module+0x10c/0x110 (read with 293/294). No affordability check (use 137).', '0x438670')
N(292, 'build_near_at', 4, 1, '(worker, x, y, guid) -> bool', 'Same as 135 with the arguments in this order.', '0x438d30 -> 0x438670')
N(293, 'last_build_x', 0, 1, '() -> x', 'module+0x110 (x of the last 135/292 placement).')
N(294, 'last_build_y', 0, 1, '() -> y', 'module+0x10c.')
N(147, 'self_destruct', 1, 0, '(unit)', 'Order 0x20000009 sub-code 6 -> 0x419120(0): the unit dies.', '0x438b90')
N(148, 'unsaddle', 1, 0, '(unit)', 'Order 0x20000009 sub-code 2 -> 0x41a080: dismount; a horse (480) and the foot type (guid-1) appear.', '0x438bb0')
N(215, 'camouflage', 1, 0, '(unit)', 'Order 0x20000009 sub-code 3 -> 0x41a550 (unit+0x401 = 1).', '0x438f40')
N(216, 'uncamouflage', 1, 0, '(unit)', 'Order 0x20000009 sub-code 4 -> 0x41a5b0.', '0x438f60')
N(345, 'unpack_tepee', 1, 0, '(travois)', 'Order 0x20000009 sub-code 5 -> 0x4647f0.', '0x439450')
N(344, 'pack_tepee', 2, 0, '(travois, tepee)', 'Pack an own tepee (class 0x40) onto a travois (order 0x2000001d -> 0x4646d0).', '0x439430')
N(320, 'spell_eagle_eye', 3, 0, '(medicine_man, x, y)', 'Order 0x20000016 spell 0 at (x, y) (0x433c00). Spells need energy obj+0x394 >= the spell\'s cost.', '0x439110')
N(321, 'spell_lightning', 3, 0, '(medicine_man, x, y)', 'Order 0x20000016 spell 1 at (x, y).', '0x439140')
N(322, 'spell_hail', 2, 0, '(medicine_man, target)', 'Order 0x20000016 spell 2 on an object.', '0x439170')
N(323, 'spell_protect', 2, 0, '(medicine_man, target)', 'Order 0x20000016 spell 4 (protective dance) on an object.', '0x439190')
N(324, 'spell_rain', 2, 0, '(medicine_man, target)', 'Order 0x20000016 spell 3 (rain) on an object.', '0x4391b0')
N(325, 'rob', 2, 0, '(unit, building)', 'Rob / steal from a building (order 0x20000017 -> virtual +0x94, 0x41b620).', '0x4391d0')
N(341, 'dig_in', 1, 0, '(unit)', 'Bury / dig in (order 0x2000001f -> 0x4377c0; the assassin).', '0x4393d0')
N(342, 'dig_out', 1, 0, '(unit)', 'Come out (order 0x20000020 -> 0x4377f0).', '0x4393f0')
N(343, 'disarm_trap', 2, 0, '(unit, trap)', 'Disarm an enemy trap (order 0x20000021 -> 0x41bd10).', '0x439410')
N(346, 'convert', 2, 0, '(priest, unit)', 'Convert (order 0x2000001c -> 0x4593b0; needs energy and range 500).', '0x439470')
N(347, 'heal', 2, 0, '(healer, unit)', 'Heal (order 0x2000001b -> 0x43f3f0; only if the target is hurt).', '0x439490')
N(354, 'group_attack_move', 5, 0, '(table, n, formation, x, y)', 'Formation attack-move of the first n (max 20) handles in KI table `table` (0..99): order 0x20000028 {leader = table[t][0], x, y, formation, n-1, the others}. The scripts use formation 6.', '0x439570')
N(390, 'group_attack', 4, 0, '(table, n, formation, target)', 'Formation attack on an object by the first n (max 20) units of table t: order 0x20000027 {leader, target.x, target.y, formation, target, n-1, others}. Nothing is sent if the target is gone.', '0x439cf0')
N(391, 'group_attack_', 4, 0, '(table, n, formation, target)', 'Same handler as 390.', '0x439cf0')
N(138, 'produce', 2, 0, '(building, guid)', 'Queue a unit/upgrade (order 0x10000001 -> 0x40cd10), the order the build menu sends too, without the menu\'s limits. Refused only for a full queue (10), a second leader (in production 0x590a63, or alive 0x42c1f0) and an upgrade researched (0x590b18) or in research at any building (0x590e38, set here; cleared when done 0x42cd00 or cancelled 0x40d8e0). Nothing about the level before (the menu 0x4750a0 offers the next level only when no level is in research) or prerequisites, so Sight 2 waits behind Sight 1. Costs (props 101-105) from the owner\'s table are then deducted unconditionally (0x422580, may go below 0) - test 136 first. Horses need no room: a finished one waits while the corrals are full (0x40cf78, alert 823).', '0x438a40')
N(142, 'produce_neutral', 2, 0, '(building, guid)', 'Same with costs from the neutral table (order 0x10000002): horses 480, cows 482, guns 710, liquor 711.', '0x438ae0')
N(210, 'release_unit', 2, 0, '(building, index)', 'Let garrisoned unit `index` out (order 0x10000003 -> 0x40d7b0).', '0x438ea0')
N(351, 'release_all', 1, 0, '(building)', 'If class 0x4000: order 0x10000003(b, 0) once per occupant (obj+0xd8).', '0x4394d0')
N(338, 'cancel_production', 1, 0, '(building)', 'Cancel the first queue entry with refund (order 0x10000004 index 0).', '0x439320')
N(348, 'demolish', 1, 0, '(building)', 'Order 0x10000005: the building takes 5000 damage (virtual +0x44 = 0x40c970; HP are x256, so 19.5 HP per order).', '0x4394b0')
N(355, 'set_rally_point', 3, 0, '(building, x, y)', 'Order 0x10000008: rally point (building+0xf8 = x, +0xf4 = y; both must be > 0).', '0x4395f0')
N(399, 'player_bonus', 1, 0, '(building)', 'Order 0x10000009 -> 0x40e3c0: uses 0x4b00 of the building\'s charge (+0xa0) for a 60 s player-wide effect (world+4+4*(p-1); probably a combat bonus).', '0x439df0')
N(401, 'building_ability', 3, 0, '(building, x, y)', 'Order 0x10000006 -> 0x40de90: uses 0x1900 charge, creates a 7 s effect object at (x, y) (probably reveals the area).', '0x439e40')
N(376, 'add_food', 1, 0, '(amount)', 'Player order 0x40000009(me, amount): adds food (0x422990). The AI\'s resource cheat (multi_situation_analyser tops itself up when low).', '0x455ea0')
N(377, 'add_wood', 1, 0, '(amount)', 'Player order 0x40000008: adds wood (0x422650).', '0x455ea0')
N(378, 'add_gold', 1, 0, '(amount)', 'Player order 0x4000000a: adds gold (0x422600).', '0x455ea0')
N(381, 'make_allies', 2, 0, '(p1, p2)', 'Player order 0x40000004: p1 allies with p2 (relation bit 4, shared vision, message 372).', '0x439b00')
N(382, 'make_enemies', 2, 0, '(p1, p2)', 'Player order 0x40000003: p1 declares p2 enemy (bit 1, message 373).', '0x439b20')
N(388, 'resign', 0, 0, '()', 'Player order 0x4000000c(me): "player left" message and removal of this player.', '0x439c80')

# ---- remaining queries --------------------------------------------------------------------
N(136, 'can_train', 1, 1, '(guid) -> bool', 'Prerequisite buildings exist for guid (0x42a020: every type in its requirement list is owned) and I can afford its unit costs (props 101-105 food, wood, horses, gold, guns and 119 living space, from my table; 0x422680).', '0x438900')
N(291, 'can_train_default', 1, 1, '(guid) -> bool', 'Same, costs from the neutral/default table (player 0).', '0x438900')
N(137, 'can_build', 1, 1, '(guid) -> bool', 'Prerequisites met and I can afford its building costs (props 1-5, no living space). Types without props 1-5 (units) only test the prerequisites, which is how the scripts use it for units too.', '0x4389a0')
N(290, 'can_build_default', 1, 1, '(guid) -> bool', 'Same with the default table.', '0x4389a0')
N(339, 'count_in_area', 5, 1, '(player, guid, x, y, r) -> n', 'Objects of player (0..10) of type guid (or category: 0 all units, 1-4 units per nation, 5 all buildings, 6-9 buildings per nation, 16 all military, 17-20 military per nation) inside the square x-r..x+r, y-r..y+r (0x42ad00, PtInRect). Animals 480-483 count for any owner. Sets world+0x4c = 0 first (count units inside buildings too).', '0x439340')
N(375, 'count_in_area_outside', 5, 1, '(player, guid, x, y, r) -> n', 'Same with world+0x4c = 1: units inside buildings or transports are not counted.', '0x439340')
N(387, 'nearest_enemy', 4, 1, '(x, y, classany, notstate) -> h', 'First object found ring by ring within 500 px of (x, y) in the object grid (0x7d2a8c, 0x45df50) that is hostile to me, has any of the class bits and none of the state bits. 0 if none.', '0x439ca0')
N(398, 'nearest_enemy_', 4, 1, '(x, y, classany, notstate) -> h', 'Same handler as 387.', '0x439ca0')
N(372, 'nearest_wall', 4, 1, '(player, x, y, radius) -> h', 'Nearest wall/palisade cell of `player` within radius (wall list 0x7d29f4, 0x448790; the wall grid byte holds the owner); handle of that wall segment or 0.', '0x439a60')
N(228, 'find_water', 2, 1, '(x, y) -> bool', 'Ring search in 16 px steps from (x, y) over the map cell flags (0x7d2a54, 0x407d80) for a cell with flag 8 (water); on success stores it in module+0x114/+0x118 (read by 226/227) and returns 1.', '0x439030')
N(226, 'found_x', 0, 1, '() -> x', 'module+0x114 from 228.')
N(227, 'found_y', 0, 1, '() -> y', 'module+0x118 from 228.')
N(229, 'would_move', 3, 1, '(unit, x, y) -> bool', 'Snaps (x, y) to the centre of the nearest cell passable for the unit\'s movement class (0x419ba0, up to 32 rings); true if that differs from the unit\'s position. On true the handler also stores two values in module+0x124/+0x128 (freeing the old +0x124 block), which 230-232 read as a pair list - apparently left over from an earlier design. Unused by the shipped modules.', '0x439050')
N(230, 'list_count', 0, 1, '() -> n', 'module+0x128 (229\'s list size).')
N(231, 'list_a', 1, 1, '(i) -> a', 'First dword of pair i of the module list (0 if out of range).')
N(232, 'list_b', 1, 1, '(i) -> b', 'Second dword of pair i.')
N(394, 'reachable_point', 3, 1, '(unit, x, y) -> bool', 'Pathfinder 0x45f6a0(unit movement class +0x4ac, unit x, y, &x, &y): moves (x, y) to the nearest cell reachable from the unit; result in module+0x11c/+0x120 (read by 396/397) whether or not it succeeded; returns true if found.', '0x439d80')
N(395, 'reachable_point_from', 5, 1, '(moveclass, fromx, fromy, x, y) -> bool', 'Same with an explicit movement class and start point.', '0x439dc0')
N(396, 'reachable_x', 0, 1, '() -> x', 'module+0x11c.')
N(397, 'reachable_y', 0, 1, '() -> y', 'module+0x120.')

# ---- fallback for ids not described above (arity from emu.py) ---------------------------
import json as _json, os as _os
_sig = _json.load(open(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), 'native_sig.json')))
for _k, _v in _sig.items():
    if int(_k) not in NATIVES:
        N(int(_k), 'native_%s' % _k, _v['pops'], _v['pushes'], '?', 'not yet described')

# ---- grouping for NATIVES.md --------------------------------------------------------------
_R = lambda a, b: list(range(a, b + 1))
GROUPS = [
    ('Operators', [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 20, 21, 22], None),
    ('Module arrays and waiting', [31, 32, 33, 42, 43, 44, 45, 46, 47, 48, 49, 50, 40, 41], None),
    ('Shared KI state: globals, tables, semaphores, atomic sections, events',
     [219, 220] + _R(233, 248) + [221, 222, 223, 304, 305, 329, 330, 331, 332], None),
    ('Constants', [150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165,
                   166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181,
                   182, 183, 184, 185, 186, 187, 190, 191, 192, 193, 194, 195, 196, 197, 198, 310,
                   350], 'Pushed constants: class/state flag masks, stance values, diplomacy values and GUIDs (see "Flags").'),
    ('Object queries', [101, 102, 103, 104, 105, 106, 110, 111, 112, 113, 114, 115, 116, 117, 118,
                        365, 366, 295, 296, 297, 312, 367, 379, 306, 307, 132, 217, 218, 300, 359,
                        303, 337, 353, 356, 357, 373, 400, 134], None),
    ('Searches and claims', [107, 108, 109, 200, 201, 202, 139, 140, 141, 203, 204, 205, 368, 389,
                             392, 370, 371, 393, 383, 384, 385, 386, 387, 398, 372, 380, 123, 124,
                             125, 120, 121, 122, 339, 375, 228, 226, 227, 229, 230, 231, 232, 394,
                             395, 396, 397], None),
    ('Player, economy and match state', [308, 188, 189, 271, 272, 273, 274, 278, 281, 282, 283,
                                         284, 288, 301, 302, 275, 285, 279, 289, 270, 280, 340,
                                         276, 286, 277, 287, 199, 334, 369, 352, 363, 364, 224,
                                         225, 206, 207, 335, 362, 136, 137, 290, 291], None),
    ('Orders to units', [143, 311, 328, 327, 145, 251, 250, 149, 146, 336, 326, 374, 211, 212, 213,
                         214, 358, 130, 131, 133, 360, 252, 253, 361, 144, 135, 292, 293, 294, 147,
                         148, 215, 216, 345, 320, 321, 322, 323, 324, 325, 341, 342, 343, 344, 346,
                         347, 354, 390, 391], None),
    ('Orders to buildings', [138, 142, 210, 338, 348, 351, 355, 399, 401], None),
    ('Player-level orders', [376, 377, 378, 381, 382, 388], None),
]
