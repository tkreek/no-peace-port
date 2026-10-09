# America Remastered (Godot 4)

A 2D engine that plays *America: No Peace Beyond the Line* (Related Designs, 2000) with its
art and sound, upscaled. The game reads everything from an asset folder (`assets/`, beside
`game/`) that is built from your own copy of the original game; no original assets are in
this repository.

## Setup

1. Install Godot 4.7+.
2. Get the asset folder, either:
   - from someone who has built it: put the `assets/` folder beside `game/` (or anywhere,
     and start with `--assets-dir=<folder>` or set `[paths] assets_dir` in
     `user://settings.cfg`), or
   - by building it (below).
3. Run `godot --path game`. The game opens on the main menu: "Skirmish" picks a map (all
   71), your people and up to seven computer opponents; "Map editor" builds maps. Esc in a
   game opens the in-game menu.

## Building the assets

From the original CD and the expansion pack:

1. Extract the game into `original/install` (and the expansion's `Setup/data1.cab` into
   `original/expansion/install`):
   ```bash
   bsdtar -xf America.iso -C original/iso
   python3 tools/extract_is5_cab.py original/iso/DATA1.CAB original/install
   ```
   This yields `original/install/Programm/` with `america0.rda` … `america4.rda`, `Levels/`
   and `Music/`. The expansion adds 51 maps, units and buildings, the portraits, the
   editor's real default stats and the terrain painting rules.
2. Upscale the graphics with Real-ESRGAN into `original/hd` (about 2 hours on an RTX 4060 Ti):
   ```bash
   python3 -m venv tools/.venv && tools/.venv/bin/pip install numpy pillow
   # put the realesrgan-ncnn-vulkan release in tools/bin/realesrgan/
   tools/.venv/bin/python tools/upscale/hd_sprites.py original/install/Programm original/hd --addon original/expansion/install/Programm
   tools/.venv/bin/python tools/upscale/hd_images.py original/install/Programm original/hd --addon original/expansion/install/Programm
   tools/.venv/bin/python tools/upscale/hd_terrain.py original/install/Programm original/hd
   ```
3. Build the asset folder (a few seconds):
   ```bash
   python3 tools/assets/build_assets.py
   ```
   It writes `assets/` with English names: `units/`, `buildings/`, `animals/`, `nature/`,
   `effects/`, `interface/`, `portraits/`, `terrain/`, `sounds/`, `music/`, `maps/` and the
   JSON tables in `data/`, plus `manifest.json` (original path → asset path) and
   `REPORT.md` (what was left out and why; see `docs/production/unmapped-assets.md`).

The game never reads `original/`; it is only the source for the tools.

## Options (after `--`)

Any of `--map`, `--scenario`, `--screenshot`, `--report-after` skips the menu and starts a game.

- `--map=<file in assets/maps or maps/, or an absolute path>`: default `[2 Players] - close combat.ulf`.
- `--faction=ind|mex|des|usa`, `--enemy=...`: the peoples (default Mexicans vs. Americans).
- `--fog=off`, `--ai=off`.
- `--biome=steppe|wiese`: override the biome detected from the map's objects.
- `--camera=x,y`, `--zoom=z`.
- `--screenshot=<png> --frames=<n>`: render, save a frame and quit (used for automated checks).
- `--scenario=battle|economy|build`, `--ai-vs-ai=1`, `--report-after=<frames>` (with `--fixed-fps 30`):
  scripted test setups and headless stockpile reports (every 1800 frames also each side's
  units and buildings). `--trace-ai=1` logs the AI's building and attacks; `--ai-ferry=1`
  makes it ferry its waves by boat as if the enemy were across the water.
- `--selftest=1`: decode every sound and map and report.
- `--assets-dir=<folder>`: the asset folder (default `assets/` beside `game/`).

## Controls

- WASD / arrows / screen edge / middle-drag: pan. Mouse wheel: zoom.
- Left click / drag: select units; click a building to select it. Shift adds.
- Right click: move in formation, attack a unit or building, gather from a tree or gold mine.
  Ctrl+right click on a rider: shoot the horse instead of the rider.
- Workers: build menu in the bottom bar; left click places, right click / Esc cancels, Shift keeps placing.
- Buildings: train units from the bottom bar (needs housing; houses and HQs provide it).
- Mixed groups show only the commands every member can carry out.
- Boats: right-click your boat with land units selected to board it; right-click land with a
  loaded boat selected to put the passengers ashore there (U: at the nearest bank).
- Travois: G packs a tepee (click it), L sets it up again where you click.
- Ctrl+0–9: assign control group, 0–9: recall. X: stop. Q/E/H/Y: aggressive, defensive, hold
  ground, passive. Z: patrol, C: follow, G/L: into / out of quarters, I: assembly location.
- Esc: in-game menu (save, load, options). Settings are also on the main menu.

## Map editor

Main menu → Map editor (or `-- --editor[=<map file>]`).

- Top bar: New, Open, Save (to `maps/` beside `game/`, as `[N Players] - title.ulf`), Test (saves
  and plays the map at once; Esc → "Back to the map editor"), Undo, Erase, the map's title.
- Terrain: pick a material and paint (left drag). Materials only blend into their neighbours,
  so painting water into steppe grows shore and shallow-water rings by itself. `[` `]` set the
  brush size. Painting needs the expansion's `Steppe.gfs` / `wiese.gfs`.
- Nature, Buildings, Units: pick an object (buildings and units for the chosen player), click
  to place. Right click removes the object under the cursor with any tool.
- Players: put each player's start point; choose their people and whether the computer plays
  them in test games; start resources.
- A player who owns placed units or buildings starts a game with exactly those, without the
  usual main building and workers: a few units on an empty map make a quick test bench.

## Layout

- `scripts/formats/`: readers for the asset formats: maps (`.ulf`), sprite sheets, animation
  sets, the object types, the editor defaults and the terrain painting rules.
- `scripts/core/`: autoloads that serve the asset folder and its tables (`GameData`), play
  sounds and music (`Sound`), hold the match settings (`Match`); player settings.
- `scripts/main.gd`: the match: map, peoples, interface, computer players, victory.
- `scripts/world/`: terrain, navigation (ground, water, both), fog of war, camera, selection
  and orders, building placement, projectiles and effects.
  - `units/`: `Unit` (state machine, orders, combat, movement) on `UnitSprite`, with parts for
    work, riding, animals, magic, stealth, water and tepees.
  - `objects/`: `MapObject` (buildings and scenery) with its stock, and for buildings their
    condition, production and defence.
- `scripts/game/`: players (stockpiles, housing, research, trading), saved games, and the
  computer player in `ai/` (economy, building, army).
- `scripts/editor/`: the map editor (`MapEditor`, its interface, and `TerrainPainter`, which
  lays terrain out with the expansion editor's rules read by `formats/terrain_rules.gd`).
- `scripts/ui/`: main menu, settings, minimap, thumbnails; the in-game interface in `hud/`
  (selection panel, command panel, game menu).
- `scripts/dev/`: test scenarios (`--scenario=`), self-tests, headless reports and the profiler.
- `data/stats.json`: unit and structure stats extracted from the manual
  (`tools/data/extract_manual_stats.py`).
- `shaders/`: GPU terrain compositing, team-colour palette lookup and the fog of war.

## Checks

```bash
python3 tools/check_scenarios.py
```

runs every test scenario headless (about seven minutes, several at once) and checks what
each prints: the scripts parse, the rules work (gathering, combat, magic, boats...), the
command panel builds, saving and loading keeps the match, and a six-player AI game runs.
Pass names to run only some (`tools/check_scenarios.py boats swim`).
