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
| `EINHEIT`, `EIGENSCH` | per-object property overrides `{u32 object, property, value, ?}` (TODO) |
| `SPIELER` | player slots and names |
| `AREA*`, `ABLAUF*` | mission trigger areas and scripts (TODO) |

Player start points are placements of type `Editor_Start` (owner = player).

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
- `Defaults.bin`: RDCHUNK file with `EINHEIT`/`EIGENSCH` chunks: default per-type properties (stats), TODO.
- `sfx/sfxguids.dat`: sound ID table, TODO.

## TODO
- `.alf` `BITARRAY`/`PINSMATR`, `EIGENSCH` property ids, triggers and scripts.
- Fonts, `.pk`.
- `Defaults.bin`, `rules.def`, `sfxguids.dat`, `kimodules/*.mod`.
- `.bik` videos (Bink 1; ffmpeg can decode).
