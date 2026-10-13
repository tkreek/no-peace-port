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
- Damage on firing (0x436cc0) = attack + upgrade bonus, scaled by a few optional
  percentages. The base `America.exe` has the same reloads and formula: the expansion
  doubled most units' HP (54 of 87; heroes unchanged) but kept every attack value, so
  fights take about twice as many hits.

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

## TODO
- `.alf` `BITARRAY`/`PINSMATR`.
- Fonts, `.pk`.
- `rules.def`, `sfxguids.dat`, `kimodules/*.mod`.
- `.bik` videos (Bink 1; ffmpeg can decode).
