# Original Game File Formats

Reverse-engineering notes for the English Windows CD release (2000). Source data lives in the
gitignored `original/` folder and is never committed.

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

### `.spr` (`RDDX`)
RGB555 atlas. The frame rectangles are not decoded yet; earlier conversions ignored them.

### Terrain (`<biome>/gfx/landschaft`)
- `steppe.pic`: 640×12000 paletted atlas of 64×64 square tiles (not isometric diamonds).
- `kleinsteppe.pic`: 80×1500, the same atlas at 1/8 scale (zoomed-out/minimap use).
- `minimap.pic`: 20×375 RGB555, one pixel per 32×32 block.
- Many tiles are transition masks: flat red/green/orange regions are placeholder colours the
  engine fills with other terrain. Composition rules come from the map format (TODO).

## Data

- `DEFS.INI`: global tuning: start resources, sight ranges in pixels, range tiers,
  melee/ranged attack rates (1 s = 100), walk speeds.
- `GUIDS.INI` / `IDS.INI` / `Guids2.ini`: object type ID ↔ GUID ↔ graphics ID maps, grouped by
  faction (Native, Mexican, Desperado, USA buildings/units, heroes).
- `rules.def` (`TTRL`), `Defaults.bin`: binary, TODO (likely the tech tree and per-unit stats).
- `sfx/sfxguids.dat`: sound ID table, TODO.

## TODO
- `.alf` maps (terrain layers, objects, triggers, players).
- `.spr` frame tables, fonts, `.blf`, `.pk`.
- `Defaults.bin`, `rules.def`, `sfxguids.dat`, `kimodules/*.mod`.
- `.bik` videos (Bink 1; ffmpeg can decode).
