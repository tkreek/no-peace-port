# Original Game File Formats

Reverse-engineering notes for the English Windows CD release (2000). Source data lives in the
gitignored `original/` folder and is never committed.

These are the original game's formats. The game itself no longer reads them: the tools
convert them into the asset folder (`tools/assets/build_assets.py`, whose docstring lists the
asset formats). They are documented here for the tools and for mapping more of the
original later.

## Getting the data out

| Step | Tool | Notes |
| --- | --- | --- |
| CD image | `AMERICA_Win_EN.zip` → `America.iso` → `bsdtar -xf` | |
| `DATA1.CAB` (InstallShield 5) | `tools/extract_is5_cab.py` | `unshield` reads the file table but can't decompress the payload. Each file is a run of `[u16 length][raw-deflate block]` chunks (10 KiB uncompressed each). |
| `america0..4.rda` | `tools/extract_rda.js` | `RDAR` archive: name table + offsets, uncompressed. |

Archive contents:

- `america0.rda` (196 MB): all graphics: `global/gfx` (units, icons, menus, HUD, effects, fonts), `steppe/gfx` and `wiese/gfx` (per-biome buildings, terrain, trees, rocks).
- `america1.rda` (87 MB): sound: SFX, voices, mission speech (`.wav`, `.mp3`).
- `america2.rda`: `global/guids`: design tables (`DEFS.INI`, `GUIDS.INI`, `IDS.INI`, `rules.def`, `Defaults.bin`), text (`*.eng`), credits.
- `america3.rda`: `kimodules/*.mod`: AI ("KI") modules, 745 files.
- `america4.rda`: `Kampagne/*.alf`: campaign maps (tutorial plus 6–8 missions per faction). Skirmish maps are `Programm/Levels/*.alf` in the cabinet.

## Graphics

### `.ftb`: palette (`C256`)
`"C256"` + 256 × u16 RGB555. Index 0 is magenta `0x7c1f` (colour key). Each object has a base
palette plus 8 `__Farbumwandlung__N_.ftb` ("colour conversion") team palettes; the bright-green
ramp in the base palette is the team-colour slot.

### `.spx` (`RDSX`) sprites / `.shw` (`RDSW`) shadows
```
char[4] magic; u32 frame_count;
frame[frame_count]:
    u32 index; i32 hotspot_x; i32 hotspot_y; u32 width; u32 height;
    u32 row_offset[height + 1];      // relative to start of row data; last = data size
    row data: repeat { u8 skip; u8 count; u8 pixels[count] } until row width is filled
```
Shadow rows have no pixel bytes; covered pixels are darkened. A frame is drawn with
`(hotspot_x, hotspot_y)` on the object's ground anchor. Decoder: `tools/formats/rd_sprites.py`.

### `.bob`: animation descriptor (text, `[RDBOBFILE]`)
Lists the palettes (`ColTab#n`) and sub-sprite files (`SubSpriteFile#n`, `Typ=P256` sprite or
`Typ=DARK` shadow), then `AnimBlock`s:
```
SubSpriteFile=<n>  AnzDirections=8  AnzFramesProAnim=<frames per direction>
AnimList=<frame>,<ms>,<frame>,<ms>,...,<terminator>
```
Frames are stored direction-major (`dir * frames_per_anim + frame`). A negative terminator `-N`
appears to jump back N entries (loop); `-1` holds the last frame. Each sprite block is followed by
its shadow block.

Unit animation file names: `01_laufen` walk, `02_stehen` idle, `03_sterben` die,
`04_schiessen` shoot, `05_stechen` melee.

### `.pic` (`RDIC`): full images
`u32 width, height, 0`, then `COLS` + 256×RGB palette + `PRAW` + 8-bit pixels, or `P16B` (RGB555)
/ `PRGB`. Used for menus, loading screens, HUD panels, terrain atlases.

### `.spr` (`RDDX`): true-colour sprite atlas
`u32 width, height, 0`, `"P16B"`, `width*height` RGB555 pixels (0 = transparent), then an optional
`"STAB"` frame table: `u32 count` + `count × {u32 index, x, y, width, height; i32 hotspot_x, hotspot_y}`.
Used for trees, icons and menu widgets.

### Terrain (`<biome>/gfx/landschaft`)
- `steppe.pic`: 640×12000 paletted atlas of 64×64 square tiles (not isometric diamonds).
- `kleinsteppe.pic`: 80×1500, the same atlas at 1/8 scale (zoomed-out/minimap use).
- `minimap.pic`: 20×375 RGB555, one pixel per 32×32 block.
- Atlas palette indices 5–39 are placeholders: index N shows ground texture `steppeN.pic`
  (512×256 or 512×512, own palette), sampled in world space so it tiles seamlessly. Indices ≥ 40 are
  literal colours (cliffs, shores). The meadow biome (`wiese/`) uses the same file names.
  Renderer: `game/shaders/terrain.gdshader`.

## Maps (`.alf`)
RDCHUNK container: `"RDCHUNK.VERSION\0"`, u32 version, u32 0, `"RDLF"`, u32; from 0x20 chunks of
`char[8] name, u32 next_chunk_offset (absolute), u32 packed`, then (if packed) `u32 unpacked_size` +
LZW (MSB-first, 9–13-bit codes, 256 clear, 257 end, early change).

| Chunk | Contents |
| --- | --- |
| `LVL_INFO` | title (C string), map width/height in 32 px cells at 0x114/0x118, start resources |
| `LVMATRIX` | u32 per cell; low 16 bits = 32×32 tile index in the biome atlas (20 tiles per row), high 16 bits = the editor's shape code (see terrain rules) |
| `BOBLISTE` | u32 count + 24-byte placements `{u32 x, y, type_id, owner, amount, ?}` (0xCDCDCDCD = unset) |
| `BITARRAY`, `PINSMATR` | probably passability / height data (TODO) |
| `EINHEIT`, `EIGENSCH` | per-player switches and property values: see "Per-player tables" below |
| `SPIELER` | players: number, people, human/computer/independent, side, stock (see missions.md) |
| `AREA`, `ABLAUF` | mission areas and script: [missions.md](missions.md) |

Player start points are placements of type `Editor_Start` (owner = player).

### Per-player tables (`EINHEIT`, `EIGENSCH`)
Read by AmericaAddOn.exe's level loader (0x442b08..0x442e5b) into a table per player and
object (world+0x1ef3c + (player * 1000 + id) * 0xE0: +4 has a switch, +8 the switch,
+0xC/+0x70 up to 25 property ids/values, +0xD4/+0xD8 the upgrade list, +0xDC the property
count). Objects are named by `IDS.INI` id (`data/ids.json`), not GUID or BobListe type; a few
GUIDs share an id (wall pieces 412/425/426, scenery variants). Both chunks hold 9 blocks: the
neutral player's, then one per `SPIELER` record, which counts for the record's player number
(for player 1 when the record has no people or no number from 1 to 8; base/des_03 has two
records for player 7, the later one's switches win). Remake: `MapRules`.

- `EINHEIT`: `u32 count` + `{i32 id, i32 value}` (0x461830: sets the switch, a later record
  replaces it). Its one reader, 0x42c3d0 (value != 0), is asked by the menu builder 0x46a600:
  0 takes the structure's, unit's or upgrade's button out of that player's menus; horses,
  cows, guns, liquor and fields (480, 482, 710, 711, 149) ask the neutral player's table. The
  computer players are not held to it. It is not "researched": research flags are set only
  when research finishes (0x42cd00, from 0x40cfc5), and the spell buttons need them
  (0x474bd1 asks 0x42cc70). Campaign maps list each player's people (most values 1); e.g.
  base/ind_06's human (player 4) has no building but may research swimming, camouflage, the
  medicine man's dances but rain, ... at the buildings of the independent village it takes
  over; several maps switch horses (ind_01, ind_03, tut_02, tut_03, usa_01) or cows (mex_03,
  usa_01) off for everyone. Skirmish maps have one record per player slot, id 0 (the chief's
  tepee) with a stray value (0 in rio grande, beggar's canyon and around the mount, which
  hides a second chief's tepee from a Native player there).
- `EIGENSCH`: `u32 count` + `{i32 id, i32 property, i32 value, i32 use_default}`. Every map
  carries the editor's whole table in it, `use_default` 1; records with 0 (1 to 54 per
  campaign map, none in skirmish maps) set the property for that player (0x461850: the first
  one for a property counts). Examples: base/des_03's duel sheriff (player 8) 1 hit point and
  1 attack, base/ind_01's human chief 180 hit points, base/mex_03 player 4's trappers 150 hit
  points and 12 attack, research times (base/ind_06's swimming 20 s for the human), housing of
  main buildings, bank energy, wagon loads.
- Then (0x442e2b, 0x461940) every player's table is filled from Defaults.bin's: a switch the
  map did not set, the upgrade list always, and every property the map did not set. Only
  objects Defaults.bin's `EINHEIT` lists get anything.

## Terrain rules (`Steppe.gfs`, `wiese.gfs`, expansion archives)
The expansion level editor's auto-tiling rules (`"RDGS"`, atlas path, own name; u32 values from 0xA8).
Read by `game/scripts/formats/terrain_rules.gd`, used by the map editor.

| u32 index | Contents |
| --- | --- |
| 0 .. 839 | header table (unused) |
| 840 .. 30839 | 4 collision flags per atlas tile (16 px quarters), identical to a map's `BITARRAY` before objects are stamped in |
| 30840 + 623·k | 18 materials: `name#nnn\|nnnn` at +4 (steppe1/2, Ödland1/2, stein1, Weg, wüste1/2, ufer1, wasser1/2/33, höhe1, höhe_gras1/2, höhe2, Nadelwald, Laubwald) |
| 42056 .. | block records `[1, variants, A, B (-1 = plain A), w, h, shape]` + `variants` 8×8 grids of tile ids (-1 = unused); one stray 0 before the last records |

Ordinary blocks are 2×2 tiles (64 px). Materials only blend along a tree: 0-1-2-3-4, 4-5-6-7,
4-8-9-10-11, 4-16, 4-17, 4-12-13-14, 12-15 (4 = stone is the hub). Each blending pair has 24
transition shapes; 4-12 and 12-15 (plateau cliffs) use ~245 other pieces, partly 6×2.

In a map, blocks sit in 64 px columns starting at odd cell columns, every other column shifted
half a block down (column k starts on rows of parity k+1). A block therefore touches six lattice
points (top, middle, bottom of its left and right edges) and its shape code says which hold A:
patterns `TL TR ML MR BL BR` → code, e.g. `AAAABB` 28, `ABABAB` 16, `AABAAA` 26 (full table in
`TerrainRules.SHAPES`); plain blocks are code 35. A map stores the code in the high word of each
`LVMATRIX` cell. Every lattice point is the middle of exactly one block's edge; patterns with no
piece leave a lone corner to that neighbouring block. Redrawing riverside.alf from its lattice
reproduces 99.6% of the original shapes (the rest are next to cliffs).

## Object types (`BobListe.blf`, america2 root)
`"RDBF"`, u32 capacity (1000), then `capacity × {u32 ?; char bob_path[80]; i32 ?}`: the `.bob`
file list. Then one record per object type id (0–434, the ids maps and `GUIDS.INI` use):
`char name[0x50]; u32 bob_id @0x50; u32 kind @0x54 (1 unit, 2 building, 3 scenery);
i32 anim @0x6c; i32 shadow_anim @0x70` (0x104 bytes, partly uninitialised memory), followed by a
`"BARY"` footprint: `i32 anchor_x, anchor_y; u32 width, height, cols, rows, count; u32 cells[count]`
on a 16 px grid. Meadow variants end in `_Wi`. Building `.bob`s use anim 0/1 for construction
stages and 2/3 for the finished building.

## Data

- `DEFS.INI`: global tuning: start resources, sight ranges in pixels, range tiers,
  melee/ranged attack rates (1 s = 100), walk speeds.
- `GUIDS.INI` / `IDS.INI` / `Guids2.ini`: object type ID ↔ GUID ↔ graphics ID maps, grouped by
  faction (Native, Mexican, Desperado, USA buildings/units, heroes).
- `rules.def` (`TTRL`): binary, TODO (likely the tech tree).
- `Defaults.bin`: the stat table the game runs on. `"RDCHUNK\0"`, then chunks as in `.alf`
  (`char[8] name; u32 next; u32 packed` (1 LZW in the base game, 2 zlib in the expansion's
  `guids2/`); `u32 unpacked_size`). `EIGENSCH`: 5 blocks (scenery/animals, then the four
  factions) of `u32 count` + `count × {i32 type_id, prop_id, value, value}`; type ids map to
  GUIDs through `IDS.INI`, property ids are the editor's (`Einheiten.cfg`, `Gebaeude.cfg`).
  The expansion's table equals the editor's `Defaults.dat` "+" properties exactly. The base
  game's (`global/guids/`) differs for 106 GUIDs (`data/defaults_base.json`): the expansion
  doubles 54 of the 87 regular units' hit points (not the heroes'), has no minimum range
  tiers (base: 2 for most bow and gun units, 4 for the Mexican cannon), more energy for
  walls, towers and the fort, a few other carry loads and times. The remake plays the base
  campaign's missions with the base values (MapRules), everything else with the expansion's. `EINHEIT`: 5 blocks of
  `u32 count` + `{i32 id, i32 switch, u32 n, i32 upgrades[n]}`: every object the game makes,
  switched on, and per unit the ids of the upgrades that apply to it (0x461ab0, asked with
  "researched" by 0x42cc70, e.g. the medicine man: the four dances, eagle eye, magic
  energy, swimming).
- `sfx/sfxguids.dat`: sound ID table, TODO.

## Combat in the executable

Read from the unprotected `AmericaAddOn.exe` on the expansion CD (`Crack/`; the installed
one is packed and wrapped in a try-and-buy layer). Addresses are that file's.

- Load (0x442b08): a map's `EIGENSCH` (9 blocks, neutral + 8 players, records
  `{type, prop, value, use_default}`; only `use_default == 0` applies, and no skirmish map
  has any) goes into per-player tables first, then `guids2/Defaults.bin` fills the rest
  (see "Per-player tables"). The expansion reads only `guids2/`, never the base
  `Defaults.bin`; the base game's America.exe reads its own.
- Lookup (0x4298c0: player, type, property): the player's table; units read theirs when made
  and keep the values (0x419e50 copies them into the unit), so a unit that changes hands keeps
  its hit points and attack.
- Lookup (0x461900): a property that is not in the table reads as 0.
- Unit setup (0x419e50, properties 107-120): HP = max(1, 107); walk speed =
  `LaufenSpeed[110]`; sight = max(`Sichtweite[112]`, attack range); range =
  `Reichweite[115]` (tier 0 = 64 px, hand to hand); minimum range = `MindestReichweite[120]`;
  carry = max(1, 111); melee attack = 113 every `KampffrequenzNah[116]` x 10 ms. Tiers clamp
  to the table (below 0: first value, past the end: last). 108, 109, 117 and 118 are never
  read, nor DEFS.INI's `KampffrequenzFern`.
- Fighters (every unit class but the workers, wagons, boats and healers in
  `DefaultsData.WORKERS`) attack with max(1, 114) on a reload fixed by class (0x436c20):
  1500 ms for guns and bows, 1000 ms otherwise (chiefs, spearmen, lancers, the hand-to-hand
  heroes, the assassin), 2500 ms dynamite, 5000 ms cannons. Counters drop by 20 per 20 ms
  tick, so the values are ms.
- Finding a target by itself (0x436059 and on, fighters idle or attack-moving): enemy
  units first (0x45d940 / 0x45d130, class bit 2), else enemy buildings (0x45d370, class
  bit 4), spiralling out over the 16 px cells of the object map. The building scan's cell
  lookup (0x45d7c0) refuses cells whose object handle is from a list above 8 (0x45d7f6:
  trees 9, walls 10), so wall, stockade and barricade pieces are never picked: only an
  order sends a unit against them.
- Damage on firing (0x436cc0) = attack (+0x6e0) + weapon level (+0x6b4), scaled by a few
  optional percentages (morale and experience, warrior spirit; see "Morale"). The base
  `America.exe` has the same reloads and formula: the expansion doubled most units' HP (54
  of 87; heroes unchanged) but kept every attack value, so fights take about twice as many
  hits. There is no factor for the kind of attacker or target: no anti-cavalry bonus, and
  buildings take the plain damage (0x40c970: energy, fixed point x256, less damage << 8).
- Unit classes: the factory (0x425b4a) switches on GUID - 100 through a byte table at
  0x428f00 and jumps at 0x428c7c; each case allocates the object and calls its class
  constructor, with a mounted argument for classes that have a riding version. Running the
  constructors (unicorn) gives each class's flags. Fighters are the classes whose
  constructor runs the fighter setup (0x435820: reload 1000, scan timer, stance 1, thief
  flag off, experience on via 0x41be70); the others are the workers, wagons, boats and
  healers of `DefaultsData.WORKERS`. Ranged flag +0x6d0 off (reload 1000): chiefs and their
  heroes (0x433610), spearman (0x434460), Mexican lancer on foot and mounted (0x4586d0),
  coach 266 (0x459170), assassin (0x413690), American river boat 454 (0x466760), and the
  American cavalryman / Weirs on horseback only (0x438090: 0x4381ba mounted, 0x4381d1 on
  foot). On for every other fighter, the whip cracker (0x413d50) included: 1500 ms.
- Projectile flags, and what flies (else the blow lands at once, guns included):
  +0x6d3 arrow (archers 156/157, flaming archers 158/159, Gall 276/277, canoe 154;
  object 0x1a8 bytes, 0x4610d0, GUID 723), +0x6d4 knife or tomahawk (163, 172; 0x198,
  0x457780, 722), +0x6d1 cannonball (265, 465; 0x238, 0x437dc0, 720), +0x6d2 dynamite
  (359, 468; 0x238, 0x4167b0, 721). Constructor arguments (0x436d80..): a launch delay
  (+0x94, counted down by 20 a step before it flies: arrow 600 ms, knife 400, dynamite
  800, cannonball none), the start (shooter's x, y) and height (+0xb8: arrow and dynamite
  1500, knife 1100, cannonball 1; drawn 0.03 px a unit, the shadow 0.015 px sideways,
  0x461280), the target. Each class sets its flight time in ms (+0xe0, a double): arrow
  500, knife 800, cannonball 250, dynamite 500.
- Flight (0x405240, 0x405350, 0x405450): aimed at the target's position when fired
  (0x41bcf0, no leading; a building's nearest point, 0x40d690), never steered after. Over
  T = time x 0.05 steps of 20 ms it covers the distance in equal steps; the height climbs by
  0.4905 T - z0 / T, less 0.981 a step, so it comes down at the target at T: a near-flat
  path from the starting height. Speed therefore grows with distance.
- Rate (0x436abb, 0x435d04): when the counter 0x6dc is out the unit fires at once and sets
  it to the reload again; the counter runs down 20 a tick whatever the animation shows. One
  blow per reload, not per animation plus reload.
- Landing (0x405510): the target is hit if it is still within 64 px of the landing point
  (a building: 96 px), else the first object within 32 px that is an enemy or no one's
  (0x45d560, units and buildings, 0x42c040), else nothing. Cannonballs and dynamite (0x437ff0,
  0x416a40) then play the explosion, or a splash on water (0x4069b0 bit 8): no splash
  damage. There is no roll to hit anywhere.
- Experience (+0x23c, max +0x238 = 100 from the unit constructor 0x418ebb, only when +0x240
  is set: fighters): +1 for each unit killed, +5 for each building destroyed but walls,
  stockades and barricades (212, 312, 412), by blow (0x436fca, 0x437019) or shot (0x405593,
  0x4055f8). A blow deals (morale + experience / 2)% (0x436d04), so 100 points add 50
  percentage points. The status menu prints the points with a percent sign (0x475b8a).
  Mounting and dismounting carry it over with the life energy (absolute), stance, magic and
  load (0x41be90).
- Unit hit (0x418f90): `damage x (200 - morale) / 100`, a fifth of that under the
  protective shield (+0x298, set for 60000 ms by the medicine man's spell at 0x434046 ->
  0x41b530), at least 1; the unit dies at 0 (0x419120). A rider who dies (mounted classes,
  +0x464) leaves a horse of his own people where he fell (0x419363 -> 0x429900), killed at
  once if that people already has more than 5 horses, or the neutrals more than 30
  (0x4193a4). No separate horse energy turned up.
- Self-healing (0x4176f7): units with +0x174 gain 1 life energy whenever their timer
  (+0x178 from +0x17c) runs out (vtable +0x48, 0x418f60). Every Native American class
  constructor sets 2000 ms (0x41d480); Self-healing (957) sets 3000 ms in the armour
  refresh (0x41b2a9).
- Stance (+0x468, set by 0x4196b0): 0 pursues whatever comes into sight (0x43623f), 1 keeps
  to its post (+0x410/+0x414): engages within sight of it and walks back once farther than
  its sight (0x436169, 0x436205), 2 engages only within its attack range (0x4360d2), 3 not
  at all. The fighter setup starts every fighter at 1, the cannons' constructors at 2
  (0x45861a, 0x466d9a); attack orders set 0 (0x4362b9, 0x4368d6, 0x437d34). Idle fighters
  scan every 2000 ms (+0x6c8 from +0x6cc, randomly phased at 0x4358aa; 0x435fa2).
- Unit setup tables: 0x429eb0(table, tier), loaded by 0x429ad0 in this order: 0 Sichtweite,
  1 ReichweiteFernwaffe, 2 KampffrequenzNah, 3 KampffrequenzFern (unused), 4 LaufenSpeed,
  5 MindestReichweite; tiers below 0 read the first value, past the end the last. The
  fighter's own setup (0x436c20) also copies the sight into its scan radius (+0x6fc).

## Production in the executable

Same file. Costs and times are `Defaults.bin` properties; the loader (0x442db2) puts all five
of its blocks into one table by object type and copies it into every player's table, so the
neutral block's cow (482), horse (480), guns (710), liquor (711) and field (149) count for
everyone. The expansion editor's `Defaults.dat` lacks those five.

- Queueing (0x4564a0) charges 101 food, 102 wood, 103 horses, 104 gold, 105 guns, from the
  player's table, or the neutral one for horse, guns and liquor. Living space (119) is
  checked when the unit is done (0x40d103): without room the finished unit waits in the
  building, announced once (alert 805, again after the next completion). A horse waits the
  same way while the corrals are full (0x40cf78, alert 823); the build menus offer the horse
  only while the people has fewer horses than room (0x46f650 and the like), not counting
  horses queued. The queue holds
  10, trades included; liquor is queued at the distillery like a unit.
- Population limit (0x422ad0): room = min(limit, the people's living space) - its units;
  one limit (0x58fd74) for every people. Each game starts at 100 (0x422552, called from
  the map load 0x444158); outside campaigns and tutorials (flags 0x801b62 / 0x801b61, set
  by 0x4470d0 / 0x447c10) the setup's choice c replaces it with (c + 3) * 25 (0x4444df;
  Menu.eng 290..295: 75..200 in steps of 25). Campaign missions therefore cap every
  people at 100, whatever housing the map gives.
- Production timer (0x40ce30, 0x40cee0): counts to 0x7000 by
  `(0x7000 / t) * 20 / 1000` (whole numbers) every 20 ms tick, `t` = property 106 (at least
  1; 10 if the type has no entry; trades 600-619 take 20). The rounding lengthens long
  times: 20 s → 20.5, 60 → 63.7, 90 → 95.6, 120 → 143.4.
- Done (0x40cf1d): upgrades (900+) are researched; guns add 10 guns, liquor 40 food, a horse
  1 horse; buying at the trading post adds 100 food, 100 wood or 2 guns.
- Construction (0x40c4b0, called by every worker on the site each tick): every 51 of a
  worker's ticks (1.02 s) the building gains `maxHP / t` (HP is fixed point x256 from 1 HP)
  and uses `K / t` of a work pool K (2000-7000, set by building class); it is done when
  either runs out, so one worker takes `t` x 1.02 s and n workers take 1/n of that.
  `t` = property 6.

## Buildings in the executable

Same file. The building base class (constructor 0x40bdd0, vtable 0x4a1798; tick 0x40c070,
take-damage +0x44 = 0x40c970, construct/repair +0xcc = 0x40c4b0) keeps energy in 1/256ths
(+4, maximum +0x578) and its state in flags at +0x5a4 (1 site, 2 standing, 4 burning,
8 rubble, 0x10 burnt out, 0x20 producing).

- Stats (0x428b15 -> 0x40cc50): properties 1-10 of the owner's table in that order: costs 1-5
  (+0x144, food, wood, horses, gold, guns), production time 6 (at least 1), energy 7 (at
  least 10), quarters 8 (at most 10; > 0 sets class bit 0x4000), housing 9, sight tier 10
  (at least 0). A wall's straight pieces are made as their corner's type (0x428a7e: 219/220
  as 212, 316/317 as 312, 425/426 as 412) and read its values.
- A site (0x40c3f0) starts at 1 point of energy and is lost after 600000 ms if nobody has
  worked on it (+0x98, the tick's 1-point blow at 0x40c0f0; every builder's call zeroes it,
  0x40c4d8). The pitfall's own start (0x41ecd0) sets no such clock. Construction as in
  "Production": each step adds max / t energy.
- Repair (0x40c6bc, the same call on a standing building): a step every 1000 ms of builder
  ticks (50; construction's test is `> 1000`, 51) restores max / t and costs each resource's
  cost / t in whole units (0x40c300 fills +0x15c), so a full repair costs about the full
  price. Short of any, the builder stops and the local owner hears 800-804 (0x40c71a..).
- Damage (0x40c970): energy - blow x 256; at or below none, destroyed (0x40ca70). Below
  90% (+0x580, 0x40c372) flag 4: flames, in four stages of a quarter of 90% each (+0xe4),
  the burning sound 151 every 4100 ms (0x40c920); building or repairing back to 90% clears
  it. Below 40% (+0x584) flag 0x10: the burnt-out picture, anim 7 / shadow 8, until a
  repair reaches 40% (0x40c845). Nothing else: the fire does no damage and does not spread,
  and no attack starts one (every projectile hits through 0x405510: damage only).
- Fire picture (0x40d440, fire object 0x462140 on `global/gfx/feuer/fire.bob`): at stage e,
  fires at e + 1 sets of spots (marked in the building's bob, 0x40d4f0), the first at size
  min(e, 2), later ones at sizes 0, 1, 2; size s is flame anim 2 - s with its cloud 5 - s
  drawn half blended.
- Destroyed (0x40ca70): quartered units step out unhurt (0x40d7b0 -> 0x41a8a0), housing is
  taken back, upgrades in the queue are released, nothing is refunded; anim 9/10 (rubble)
  except for the pitfall and fields; sound 152; the rubble goes after 10000 ms (+0x174,
  0x40cc10), and only then does the footprint leave the map grid (0x4073a0).
- Building orders (0x4564a0, codes 0x10000001..9): produce (own table), produce (neutral
  table), let unit i out, cancel, demolish, look, trade, rally point, warrior spirit.
  Demolish (Del, 0x468f19) deals 5000 points (0x456605): no refund.
- No building fights by itself: no class overrides the tick for that (towers 0x4a6230 differ
  only in their sight refresh).
- Quarters (0x41a730, a unit within 128 px of the door, vtable +0xa8): its own building
  with room (0x40d750: count +0xd8 < +0xdc) takes it in; it stands at the middle of the
  building's ground-patch rectangle (+0x9c -> 0x40d850, anim 4), its reach +0x3ec = attack
  range + half the longer side, measured from there (0x435ce4), its sight +0x3dc = sight +
  half the shorter side when over 64 px. It fights with its own attack and reload; its
  target scan finds enemy units only, 16 px out to that reach (0x435fe8). A boat (0x41aa90)
  gives no extra reach. An enemy unit sent in (the same order) takes the building if nobody
  is inside (0x42cd70), else puts three of them out (0x41a7b8); either way it is used up
  (+0x34 = 2).
- Pitfall (class 0x41e900, vtable 0x4a34e0, tick 0x41f2f0): armed when finished; every 100 ms
  the first enemy unit within 48 px (0x45d940 with 0..0x30, class 2) takes 1000 points
  (vtable +0x44, which units scale by morale); then it springs for 2000 ms and is gone after
  the second catch (`+0x6f8 >= 2`, 0x41f3e8).
- Corrals (105, 205, 305, 405; 0x413f20..0x413f6b): +5 horse room when placed (+0xac), -5
  when the site starts (+0xb0), +5 when finished or taken over (+0xb4). Nothing takes it
  back when one is destroyed or lost.
- Banks and missions (216, 416; 0x458960): each, once finished, 1 gold every 10020 ms
  (+0x6f8 by 20 a tick, paying past 10000); no limit on how many pay.
- Magic energy (+0xa0, 1 a tick from the research of its upgrade up to +0xa4 = 0x6400, shown
  /256: 0..100, 512 s to fill; it starts empty): the tepee of the ancestors' warrior spirit
  (0x40e3c0) takes 0x4b00 (75) and adds 60000 ms to its people's timer (0x432340); levels
  968/969/970 set the people's percentage to 20/30/40 (0x4329d0). The saloon's Lift fog of
  war (965, 0x40de70) looks (0x40de90) for 0x1900 (25): object 484 (`comsat.bob`, 0x40e7b0)
  lifts the fog round the spot as sight tier 2 does, for 7000 ms (0x40e9f0, 0x40e950).
- Tower sight (0x40db80): Sight 1 (943, 962, 993) sets the tower's, lookout's or watchtower's
  sight tier (+0x18) to 3, Sight 2 (944, 963, 994) to 4. Thick boards (940, 964) are the
  wagons' (Defaults.bin's upgrade lists), not a building's.

## Upgrades in the executable

Same file. Which objects take an upgrade is data: the expansion's Defaults.bin `EINHEIT`
holds per object `{i32 id, i32 switch, i32 n, i32 upgrades[n]}` (upgrade GUIDs; the base
game's Defaults.bin has only `{id, switch}`). Remake: `GameData.UPGRADE_TARGETS`. What an
upgrade does is code, a refresh per class that asks 0x42cc70(player, object, upgrade):

- Workers (0x403240, every people's tools alike): chopping a load (+0x6b0) 4000 ms, Axe 1
  3600, Axe 2 3200; digging a load (+0x6ac) 5000 ms, Pickaxe 1 4000, Pickaxe 2 3000; the
  value a woman gives the field she works (+0x6a4, copied to the field's +0x6fc at
  0x402c3e) 150, Shovel 1 175, Shovel 2 200. Defaults set at 0x4023f0. The manual's
  "10% each" understates the pickaxes.
- Fighters (0x437400): weapon upgrades set a weapon level (+0x6b4: 1, 2, 3; 5 for the
  hardened flaming arrow); 942/992 make thieves (see stealing).
- Armour (0x41b100): Protective clothing sets the armour percentage (+0x390) to 110, 120,
  130, which scales the life energy.

## Stealing in the executable

Same file. There is no steal order, timer or range: a thief steals a wagon by fighting it.

- The thief flag (unit+0x6b1, cleared by the fighter constructor 0x4358f6, set by 0x4376d0):
  born with it are the barber 353/354 (0x4125f0) and the gunslinger 360/361 and old bandit
  282/283 (0x414320); the fighter upgrade refresh (vtable +0xc, 0x437400..0x4376c3) gives it
  for upgrade 942 (gauchos 263/264 in Defaults.bin's upgrade lists) and 992 (cowboys
  463/464), and asks for 923 too, which no IDS.INI has: the Native American arrow
  shooters the manual names can never steal. Outlaws (352) rob but do not steal.
- The check (0x437025, end of the attack 0x436cc0, after each blow or shot): attacker has
  the flag, target has class bit 0x40000 (the wagons: travois 155, transport wagon 255,
  flat-bed wagon 355, covered wagon 455, stagecoach 456; not boats, the coaches that carry
  people, or cannons) and 0x4646a0 holds: life energy (+4) below 90% of the maximum (+0x470)
  times the armour percentage (+0x390, 100 unless upgraded). The hand-to-hand / direct path
  the thieves all use deals the damage first, so the blow that takes the wagon below 90%
  steals it; a projectile path would check as it fires. Any damage counts (other units',
  earlier fights), several thieves share the work, nothing resets. A wagon at full energy
  goes in a couple of blows (base covered wagon 120: 109, then 98 = stolen).
- No relation, escort or player-kind check: computer players' thieves steal the same way,
  and only what a thief may attack (enemies) gets stolen.
- Taking it (0x42cd70): off the old owner's object list onto the new one's, set owner
  (vtable +0x20, 0x418a50: sight, sound 899's 101 for the local player, stop 0x4186a0,
  undock 0x4649e0, upgrades re-applied for the new owner). The load (+0x168) stays aboard.
- The robbing order 0x20000017 (virtual +0x94, 0x41b620; 0x41b710 within 128 px) is for
  buildings only. 0x42c580 (96 px) is the neutral-joining rule (missions.md), not stealing.

## Morale in the executable

Same file. A unit's morale is a whole percentage at +0x39c, 80..120.

- Update (0x417547, in the unit tick): only on the steps where the once-a-second flag
  0x590a20+0x7ec is up (0x429433: +20 ms a tick, raised at 1000), so every unit refreshes
  together once a second. The morale switch 0x590a20+0x7ed is set at every game start
  (0x42573c, 0x42d38e) and never cleared.
- Distance `d` (0x432560): whole pixels, `sqrt(dx² + dy²)` truncated. Morale =
  `120 - (d * 40 >> 12)`, clamped to 80..120: one point per 102.4 px, lowest from 4096 px.
- The leader (class bit 0x80000000; the four peoples' leaders, 0x80003400 in their
  constructors) measures from home (0x42c180); everyone else from the leader (0x42c1b0),
  whatever the leader's own morale. 80 when there is no leader, the leader is off the map
  (+0x3f0: in a building or boat), there is no home, or the unit has no people (player
  outside 1..8: neutrals and animals).
- Leader (0x42c1f0): the first of up to 8 slots per people (0x590a20+0x7f0, filled by
  0x42c220).
- Home (0x42c350): one slot per people (0x590a20+0x7c4). A main building fills it when
  placed (vtable +0x4c 0x40c900 -> +0xac 0x466b60 -> 0x42c2f0), so the last one placed
  wins, not the nearest; any main building leaving the map empties it (+0x38 0x40d720 ->
  +0x98 0x466b70 -> 0x42c320). It counts only once built (+0x138 == 0, the flag queueing
  also checks at 0x4564d7).
- Fights only. A blow deals `(attack + upgrade) * (morale + experience / 2) / 100`
  (0x436cfa; experience +0x23c only when +0x240 is set), and a unit takes
  `damage * (200 - morale) / 100`, at least 1 (vtable +0x44, 0x418fb6). Nothing else reads
  +0x39c but the morale bar (0x41ae70), the status menu (0x475b20) and the save: work is
  not affected.
- Warrior spirit, separately: per people a timer (+60000 ms per invocation, 0x432340, for
  0x4b00 / 256 = 75 of the tepee's energy at 0x40e3c0) and a percentage (0x432320); while
  it runs, eligible units (+0x8c) deal `x (100 + percent) / 100` more (0x436d32).

## Trading in the executable

Same file. One set of prices for every people, in the resource object 0x58fd30:
+0x2c8 wood, +0x2cc food, +0x2d0 guns, 16.16 fixed point; the whole gold part is shown and
paid (0x422c50). Trades are 600 sell wood, 601 sell food, 602 sell guns, 610-612 buy.

- Start (0x42246f, again at 0x422559): wood 25, food 33, guns 100 gold per package.
- Queueing (0x456693..0x4566c3): a purchase pays the current price in gold; a sale hands
  over 100 wood, 100 food or 2 guns.
- Done (0x40d010..0x40d0f9): a purchase adds 100 wood, 100 food or 2 guns; a sale pays the
  current price in full. Then 0x422c90 moves that good's price by half a gold, up for a
  purchase, down for a sale, kept within 1..200 gold. Nothing else moves a price: no drift
  back over time, no per-people prices.
- Cancelling (0x40d8e0): a sale gives its goods back; a purchase refunds 80% of the price
  at that moment (0x40d9e2), not what was paid.

## Economy in the executable

Same file. The worker class (vtable 0x4a138c, constructor 0x402300) runs gathering as a
chain of walk / wait states (+0x484 the state reached on arrival, dispatched at 0x402760;
+0x67c the per-tick work, 0x402810). Waits count down 20 a 20 ms tick, so values are ms.
The player's stock is the resource object 0x58fd30, per people `+0x84` food, `+0x104` wood,
`+0xa4` horses, `+0xe4` gold, `+0x144` guns, `+0x124` gold lying in gold warehouses.
Carry (`+0x16c`) is max(1, property 111): 15 for every worker and hunter, 100/120 wagons.

- Wood (0x402930, per tick 0x4030e0): at the tree the woodcutter chops for `+0x6b0` = 4000
  ms (axes 3600, 3200), a chop sound every second; then (0x402a70) the tree gives up to a
  full load at once (0x406210) and he walks it to the nearest main building or wood store
  (class mask 0x20200, 0x4297a0), hands it over (vtable +0xc4) and goes back to a tree
  within 1000 px of where he chopped (0x4028a0). One load = one 4 s chop, walking apart: a
  recording's 4 cutters 120 px out bringing 7 wood a second fits it.
- Trees (class 0x4a15ac, 0x405ed0): wood = property 302 of the tree's type (0x428822),
  1000 if missing: 250, 250, 150, 200, 200, 150 for the deciduous large 01-03 / small 01-03,
  250, 250, 250, 200, 200, 200 for the conifers, the same for the `_b` and `_c` variants
  (GUIDs 500-535, types 63-159). The first load fells it and clears its cells (0x406299:
  0x4063f0, 0x4079f0, 0x4073a0); the last leaves the stump. Property 305 (80-120) is not
  read.
- Gold (0x402420 order, 0x402500 arrival): a mine whose entrance is not framed is first
  timbered: each worker there adds 20 a tick to the mine's `+0x94` until it reaches
  `+0x90` = 11000 (0x423a39, 0x423d70), i.e. 11 worker-seconds. Then the miner takes a
  load on entering (0x423cd0), stays inside unseen `+0x6ac` = 5000 ms (pickaxes 4000,
  3000; 0x418980) and carries it to the nearest main building or gold warehouse (mask
  0x20100). The mine's gold comes from the map (0x4239fb); empty, it is boarded up.
- Gold warehouses (class 0x4a36a8, a store of kind 3): a load handed in (vtable +0xc8,
  0x423910) goes into the store (`+0x6fc`) and the people's warehoused count (+0x124),
  not the treasury; the store's loss takes the count with it (0x423940).
- Fields (class 0x4a35b8): built as a structure (Defaults.bin 149: 150 wood, property 6 =
  25, energy 200). A woman ordered to one (0x402bf0; one per field, the field's `+0x6f9`)
  brings it her `+0x6a4` (150, Shovel 1/2 175/200). An unripe field she tends
  (0x402db0 -> 0x402ed0 -> field vtable +0xcc 0x41f7a0): every 1.02 s of her work the
  field's pool of 3000 loses 3000 / 25 (0x40cc50 -> 0x40c300), so 25.5 s of one woman
  ripen it; it does not grow by itself. Ripe (0x41f849), it holds her value (150..200).
  She harvests by waiting `+0x6a8` = 30000 ms at it (0x402e40) and taking a load (15,
  0x41f9c0), which she carries to the nearest main building or food store (mask 0x120000,
  0x402fe0). Picked clean, the field is fallow again (vtable +0xd0, 0x41f740: energy set to
  0x100) and its owner hears alert 806; the next woman to tend a field at 0x100 pays the
  field's cost again (0x402e17 -> 0x403180), or stops with the shortage message.
- Weather cloud (490, 0x47c700; kind 0 rain, 1 thunder, 2 hail; one target field `+0x130`):
  after 1.2 + 5 + 1.2 s, rain sets the field's crop to 350 (0x47ca80; an unripe field's is
  overwritten when it ripens, 0x41f88e), hail destroys the field outright (0x47cac0:
  `+0x5a4` = 8, removed the next tick by 0x40c070 -> 0x40cc10).
- Hunting (fighter class, 0x437070): within 96 px of the carcass the hunter cuts up to his
  carry (0x401e10), waits 4000 ms (0x43710c), and takes it to the nearest building of class
  0x80 (0x437157): the animal-processing buildings, which also take cows (`+0x24 |= 0x80`,
  `+0xac |= 8` in the same four constructors, 0x41363f, 0x43466f, 0x457e5f, 0x4675bf), not
  the main building. Meat = max(1, property 111): horse 50, buffalo 100, cow 70 (0x401de0).
  A dead animal lies 3 s (0x419190), 30 s after each cut that leaves meat, 6 s after the
  last (0x401e1c, 0x401e3f).
- Cattle (class 0x4a3c2c): a cow starts worth 10 food, 0 gold (0x43fbd0); every 12.02 s of
  its life (0x43fb70, wild or owned, idle or not) it gains 2 food (up to 50) and 1 gold
  (up to 25). Driven to a building that takes cows (`+0xac & 8`, 0x43fbf0) and within
  80 px of it (0x43fca0), it pays both to the building's owner and is gone.
- Abandoned stores (class 0x4a94e0): the map's content 301-305 sets the kind (0x43fe50: 0
  food, 1 wood, 2 nothing, 3 gold, 4 guns) and the amount; gold counts as warehoused. A
  wagon takes (vtable +0xbc, 0x43fdb0) up to its carry, of guns carry / 50 (2 for 100 and
  120), and unloads at the main building (0x40d380).
- Hauling (wagon class, 0x464240 -> 0x464480): at an own store the wagon waits 100 ms, then
  loads each tick; it leaves when full, or 60 s after the last gold came in if it has some
  (after 60 s with none it gives up), for the main building (mask 0x20000). Abandoned
  stores (no class bit 0x100) are emptied at once.
- Robbing: a unit with `+0x388` (the outlaws, or upgrade 916, 941 or 991 via vtable +0x98)
  ordered at a building (0x20000017; 0x41b620, 0x41b710 within 128 px) takes up to its
  carry from the owner's treasury (0x58fe18, gold), waits inside 5000 ms (0x41b7d9) and
  takes it to its nearest main building or gold warehouse (0x41b7f0), again while there is
  gold. A robbing wagon at an enemy store (0x4642a4) waits 5000 ms and takes the store's
  contents (the owner hears alert 852, 0x46456d); at a bank or mission (`+0xac & 1`,
  0x464b70) it takes the treasury's gold.
- No experience for work: only hits and kills raise `+0x23c` (0x405593, 0x419b1c,
  0x436fca); no delivery touches it, and no work time reads it or morale.

## Sound in the executable

From `AmericaAddOn.exe` (addresses are that file's). It loads the expansion's
`sfx/sfxguids.dat` (0x41ffc0): sounds `{u32 id, u32 flags (low byte volume), char[100] file}`,
then per GUID `{u32 guid, u32 count, u32 event[20], u32 sound[20]}`.

- Lookup (0x420250 by object, 0x4202c0 by GUID): the first entry for the event plays;
  with none, nothing does. There are no random variants and no stand-ins.
- Select (0x46999c): event 100, or 107 (construction) for a building not yet finished.
  Order (0x41a631): 101 from the unit given the order, for the local player only.
- Blows: fighters play 103 on every attack, hand to hand too (0x436cc0); workers 104
  (0x419b85), which no entry has, so they hit silently. Projectiles play their own 103
  where they land.
- Chop 105 on each stroke; swim 106 every 1000 ms in deep water (0x417cc3); death 102.
- Buildings: 150 finished and 153 unit ready (played by the new unit) for the local player
  only; 151 every 4100 ms while burning; 152 when destroyed. Nothing plays while building.
- Medicine man (0x433c00-0x433e14), on casting: Eagle eye 122 (dance), Lightning 123,
  Hail 121, Rain 124, Protective dance 120; he heals in silence. The eagle (483) plays its
  101 as it appears; the weather cloud (490) rain 120, thunder 121, hail 122. The nurse
  and nun play 120 as they start on a patient, the priest 120 as he converts.
- Alerts (0x434cb0, 0x4353b0) play GUID 8xx's event 100, as the table has it: 806 (field
  harvested) `field_plot`, 852 (gold warehouse robbed) `attack_general`, 892 (covered wagon
  attacked) the priest's `convert`. Attack alerts by victim: chiefs/commanders 860/870/880/890,
  main buildings 861/871/881/891, wagons 862/872/882/892/893, mission 873, weapons factories
  874/895, bank 894, other buildings 851, other units 850.
- Played by id: diplomacy messages (alliance or enmity: 58, `field_harvested.wav`; "is giving
  the signal": 143; "has exposed the leaders", for 500 gold: 36).
- Something becoming the local player's (any change of owner, 0x418a50 units, 0x40bd40
  buildings): 899's 101, `message_up_map`. A new text message: 899's 100.
- Placement refused: alerts 812 (spot), 803-805 (cost, room), 809 (requirements), 808
  (building limit). Nothing else that cannot be done makes a sound (a full boat or fort,
  a trade). Unit production checks room first: 805, or 807 at the match's limit.
- Upgrades finish in silence (0x42cd00); their 153 entries go unused.
- The rest of the sound object: music streams (`Music/IND|MEX|DES|USA.MP3` in a match,
  `tit.mp3` menus, `abr.mp3` statistics, `briefing.mp3`, `credits2.mp3`), mission speech
  (`missions2/%s%02d.mp3`, `missions/%03d.mp3`, won/lost), volumes, stopping an object's
  sounds when it is removed, and two timer helpers. The menus make no sound.
- Never played: `river`, `water_splash_1-3`, `ding`, `neutral_units_recolour`,
  `burning_buildings_2`, `collapsing_buildings_large_1`; `gold_mine` only when a mine is
  clicked.

## Diplomacy in the executable

Relations as in missions.md (world+0x8CC, `T[from][to]`; 0x42c040 at war, 0x42c070 allied,
0x42c0b0 neutral, 0x42c120 sees). Besides the bit, each player has a byte mask of whose
sight lifts its fog (world+0x7B5+p, its own bit from 0x42be40, tested at 0x41397f).

- Player orders go through 0x455f20 / 0x455dd0 (at once alone, through the lockstep queue in
  a network game) and are carried out at 0x4571f0 (switch on code - 0x40000001, table
  0x457738): 1 chat, 2 send resources, 3 enemy, 4 ally, 5 defeat, 6 signal, 7 expose leaders,
  8..11 add wood/food/gold/guns, 12 gave up.
- Ally (0x4574a2): `T[p1][p2]` loses bits 7 and gains 4; 0x42d1f0 gives p1's sight to p2
  (`T[p2][p1] |= 0x20`, mask[p2] |= p1). Enemy (0x45742f): bits 7 off, 1 on; 0x42d280 takes
  the sight back. Only p1's side changes: an alliance is one-sided until answered. Text 372 or
  373 with both names, sound 58. KI natives 381/382 give the same orders; the campaign's
  trigger actions 30..32 (0x465da4) instead set both sides and leave sight alone.
- Every decision to fight reads the fighter's own entry, `T[actor][other] & 1`: the target
  scans (0x45d940 and siblings, ~20 callers) and the right click (0x46c309, 0x46c3b8: attack
  if at war, else move). Neutral is never attacked. So whoever allies first stops shooting;
  the other goes on until it answers.
- The Diplomacy dialog (0x44ff60, `ingamemulti.bob`, title 141) is offered in the Esc menu
  (text 58, 0x44b970) and on the D key (0x4448b3) only in network games, never in campaign
  missions or single-player multi-player maps. One row per player present, computers too:
  name, people, score; for the others, chat toggle, ally (0x431f30), enemy (0x431f10),
  resource recipient toggle (0x431f50); buttons 161..164 send food, wood, gold, guns. The ally
  button is lit while `T[me][p]` has no war bit (0x431ec0).
- Sending (order 0x40000002, packed at 0x432000, carried out at 0x45723e): for each marked
  recipient in turn, if the sender still has a package (100; guns 2) it moves over, else
  that recipient gets nothing. No fee, and no alliance asked for anywhere (the manual says
  allies). Only the receiver is told (texts 813..816).
- Score (stat 9, 0x422e90, shown by the dialog via 0x444f5b and on the statistics screen):
  1000 a kill + 500 a building razed + 500 a unit trained + 250 a building built + wood +
  2 gold + food + 100 a gun + 100 a horse, the resources as running totals of what came in
  (income and tributes, a tribute paid counting against). The remake counts deliveries and
  tributes.
- Computers do not answer a human's alliance (the KI reads relations only at setup). The
  expansion's KI pairs computer players up itself (addon_setstatus / addon_setfreunde): every
  pair at the difficult level, each pair by an even chance at medium, none lower; the first
  allies 30..120 s in, the second answers 3..8 s later.
- End of game (0x4320f0): first each player present may be out (0x432140; text 820 nothing
  left, 821 commander dead, 822 main building gone, by game type), then each player wins
  once no player present is at war with it either way (0x432260, 0x42c6a0). Allies win
  together; a one-sided alliance keeps both playing. Campaign missions skip both.
- The lobby has no teams: its slot records (0x80e628, copied at 0x444331) hold only the
  player's kind, number, people and name, and every shipped multiplayer map gives each slot
  only its own side bit. The remake's teams are its own setting (Match.players).

## Drawing in the executable

The visible objects are drawn in five passes over the same list (0x4625d0, through vtable
+0x6c with a flag): 2, 1, 4, 8, then 0x10. A building draws its ground patch, shadow and body
in the first three (0x40c120); a unit its shadow in pass 1 and body, selection marker and
energy bars in pass 4 (0x417f80; the body is sprite slot +0x500, its shadow +0x4b4, set
together at 0x419550 to anim N and N+1).

- Units in cover: pass 0x10 draws a unit's body again (and, if selected, its marker and bars)
  over everything with 0x4637d0, a 50/50 blend (0x409f90: `(pal[src] >> 1 & m) + (dst >> 1 &
  m)`, m the 16-bit half mask at 0x5132aa), when `[unit+0x41c]` is set. 0x417310 sets that as the
  unit moves, from bit 0x20000000 of the 16 px map grid at its feet (0x4069b0); the bit comes
  from the objects' `BARY` footprints, which mark the cells their roof or crown is drawn over
  (buildings: the cells behind the walls; trees: the whole crown). Every unit, whoever owns
  it; no option. A camouflaged unit (+0x401) skips passes 1 and 4 and is drawn in this pass
  instead, for its owner, allies and whoever's sight covers it (0x42c120, fog byte 0x4209d0).
  The remake draws it differently (`UnitSprite`, COVER_Z): over its detailed crowns and roofs
  the half blend was lost in the leaves or looked like a unit standing on the roof, and the
  cover cells miss much that hides a unit (just behind a wall, under a tower). It shows the
  unit again whenever a tree or building is drawn over its picture (`CoverGrid`), and only
  where it is hidden, as a faint team-coloured silhouette with a rim (`unit_ghost.gdshader`).
- "Shadow" in the options (texts 299-302 None / Black / Transparent) is the drop shadows, not
  this: registry `ShadowMode` (0x4471fc) at 0x4ba088, read at 0x409813 for `DARK` sub-sprites:
  0 not drawn, 1 black (0x409c20), 2 the ground halved (0x409dc0). The remake draws them
  transparent (`SpriteMaterials.SHADOW_COLOR`).

## TODO
- `.alf` `BITARRAY`/`PINSMATR`.
- Fonts, `.pk`.
- `rules.def`, `sfxguids.dat`, `kimodules/*.mod`.
- `.bik` videos (Bink 1; ffmpeg can decode).
