# America Remastered (Godot 4)

A 2D engine that plays *America: No Peace Beyond the Line* (Related Designs, 2000) with the
original art and sound, read from your own copy of the game at runtime. No original assets are
included in this repository.

## Setup

1. Install Godot 4.7+.
2. Get the original game files. From the CD image:
   ```bash
   bsdtar -xf America.iso -C original/iso
   python3 tools/extract_is5_cab.py original/iso/DATA1.CAB original/install
   ```
   This yields `original/install/Programm/` with `america0.rda` … `america4.rda` and `Levels/`.
   An existing installation folder works too.
3. Optional: the expansion pack. Extract its `Setup/data1.cab` the same way into
   `original/expansion/install` (or install it into the same folder as the base game). It adds
   51 maps, new units and buildings, the original portrait icons and the editor's real
   default stats (`Defaults.dat`).
4. Run:
   ```bash
   godot --path game -- --install-dir=/path/to/Programm
   ```
   Without `--install-dir` the game looks in `../original/install/Programm` (the dev checkout layout)
   or `user://settings.cfg` `[paths] install_dir` (and `addon_dir` for the expansion).

The game opens on the main menu; "Skirmish" picks a map (all 71), your people and up to four
computer opponents. Esc in a game opens the in-game menu.

## Enhanced graphics (optional)

The upscaled sprite set is built once from your install with Real-ESRGAN (about 2 hours on an
RTX 4060 Ti, ~900 MB):

```bash
python3 -m venv tools/.venv && tools/.venv/bin/pip install numpy pillow
# put the realesrgan-ncnn-vulkan release in tools/bin/realesrgan/
tools/.venv/bin/python tools/upscale/hd_sprites.py original/install/Programm original/hd
```

The game uses `original/hd` automatically (or `--hd-dir=`, or `[paths] hd_dir` in
`user://settings.cfg`); `--graphics=classic` forces the original pixels.

## Options (after `--`)

Any of `--map`, `--scenario`, `--screenshot`, `--report-after` skips the menu and starts a game.

- `--map=<file in either Levels/ folder or absolute path>`: default `[2 Players] - close combat.alf`.
- `--faction=ind|mex|des|usa`, `--enemy=...`: the peoples (default Mexicans vs. Americans).
- `--fog=off`, `--ai=off`, `--expansion=off`.
- `--biome=steppe|wiese`: override the biome detected from the map's objects.
- `--camera=x,y`, `--zoom=z`.
- `--screenshot=<png> --frames=<n>`: render, save a frame and quit (used for automated checks).
- `--scenario=battle|economy|build`, `--ai-vs-ai=1`, `--report-after=<frames>` (with `--fixed-fps 30`):
  scripted test setups and headless stockpile reports (every 1800 frames also each side's
  units and buildings). `--trace-ai=1` logs the AI's building and attacks; `--ai-ferry=1`
  makes it ferry its waves by boat as if the enemy were across the water.
- `--selftest=1`: decode every sound and map and report.

## Controls

- WASD / arrows / screen edge / middle-drag: pan. Mouse wheel: zoom.
- Left click / drag: select units; click a building to select it. Shift adds.
- Right click: move in formation, attack a unit or building, gather from a tree or gold mine.
  Ctrl+right click on a rider: shoot the horse instead of the rider.
- Workers: build menu in the bottom bar; left click places, right click / Esc cancels, Shift keeps placing
  (the workers then build the sites in turn).
  Repair (R), then click a damaged building.
- Buildings: train units from the bottom bar (needs housing; houses and HQs provide it).
- Mixed groups show only the commands every member can carry out.
- Boats: right-click your boat with land units selected to board it; right-click land with a
  loaded boat selected to put the passengers ashore there (U: at the nearest bank).
- Travois: G packs a tepee (click it), L sets it up again where you click.
- Ctrl+0–9: assign control group, 0–9: recall. X: stop. Q/E/H/Y: aggressive, defensive, hold
  ground, passive. Z: patrol, C: follow, G/L: into / out of quarters, I: assembly location.
- Esc: in-game menu (save, load, options). Settings are also on the main menu.

## Layout

- `scripts/formats/`: readers for the original formats (RDA archives, LZW, `.alf` maps, sprites,
  palettes, `.bob` animations, the `BobListe.blf` object table). See `docs/technical/file-formats.md`.
- `scripts/core/`: autoloads that find the installation and serve its files (`GameData`), play
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
