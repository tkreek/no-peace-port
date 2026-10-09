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
3. Run:
   ```bash
   godot --path game -- --install-dir=/path/to/Programm
   ```
   Without `--install-dir` the game looks in `../original/install/Programm` (the dev checkout layout)
   or `user://settings.cfg` `[paths] install_dir`.

## Options (after `--`)

- `--map=<file in Levels/ or absolute path>`: default `[2 Players] - close combat.alf`.
- `--biome=steppe|wiese`: override the biome detected from the map's objects.
- `--camera=x,y`, `--zoom=z`.
- `--screenshot=<png> --frames=<n>`: render, save a frame and quit (used for automated checks).

## Controls

- WASD / arrows / screen edge / middle-drag: pan. Mouse wheel: zoom.
- Left click / drag: select. Shift adds. Right click: move in formation.
- Ctrl+0–9: assign control group, 0–9: recall. H: halt.

## Layout

- `scripts/formats/`: readers for the original formats (RDA archives, LZW, `.alf` maps, sprites,
  palettes, `.bob` animations, the `BobListe.blf` object table). See `docs/technical/file-formats.md`.
- `scripts/core/game_data.gd`: autoload that finds the installation and serves archive files.
- `scripts/world/`: terrain renderer, units, map objects, camera, selection.
- `shaders/`: GPU terrain compositing and team-colour palette lookup.
