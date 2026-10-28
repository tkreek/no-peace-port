# America Remastered

A 2D engine, built in Godot 4, that plays *America: No Peace Beyond the Line* (Related
Designs, 2000) and its expansion with the original art and sound, upscaled. The game's assets
are not in this repository: you get them as a separate asset pack (below).

## Status

- **Skirmish**: all 71 maps, the four peoples (Americans, Mexicans, Native Americans,
  Outlaws), up to seven computer opponents, teams and diplomacy, fog of war, saving and
  loading.
- **Multiplayer**: lockstep over the network; a player hosts from the menu, or everyone
  joins a dedicated server (`server/`).
- **Map editor**: terrain painting, objects, start points; saves to `maps/`.
- **Campaign**: the menus, briefings and mission scripts run, but the missions' own computer
  players don't move yet.

What is still missing, and the values that had to be guessed, are in
[`docs/production/open-work.md`](docs/production/open-work.md).

## Quick Start

1. Install Godot 4.7 or newer.
2. Get the asset pack and apply the project's edits (see "Getting the Assets").
3. Run `godot --path game`.

Controls, command-line options, the map editor and the code layout are in
[`game/README.md`](game/README.md).

## Getting the Assets

The game reads its art, sound, maps and data tables from an `assets/` folder that is not in
this repository. Ask the project owner for the asset pack's Google Drive link, then unzip
`no-peace-port-assets.zip` in the root of your checkout and apply the project's edits:

```sh
cd no-peace-port
unzip ~/Downloads/no-peace-port-assets.zip   # makes assets/ next to game/ and tools/
tools/assets/patch_assets.py apply
```

To keep the folder somewhere else, run the game with `--assets-dir=<folder>` (or set
`assets_dir` under `[paths]` in `user://settings.cfg`) and pass the same folder to
`patch_assets.py --assets <folder>`.

## Editing Assets

The asset pack is a fixed base that nobody commits. Every change to it lives in
`asset_patches/`, which is version controlled, laid out like `assets/`:

- `data/<table>.patch.json` changes a table: only the values that differ from the pack.
  `data/object_types.json` is patched per object id, so two people changing different units
  don't conflict.
- Any other file (a new map, a new picture or sound) is copied in, adding it or replacing
  the pack's file.

`tools/assets/patch_assets.py apply` puts the patches on top of the pack. It keeps the pack's
originals in `assets/.pristine/`, so applying again after a patch changes or disappears gives
the same result as a fresh unzip.

Workflow:

1. `git pull`, then `tools/assets/patch_assets.py apply`, after every pull and before you edit.
2. Edit tables in `assets/` (or make maps in the map editor, which saves to `maps/`).
3. `tools/assets/patch_assets.py capture assets/data/defs.json "maps/[2 Players] - my map.ulf"`
   turns the edits into files in `asset_patches/`. `patch_assets.py status` lists anything
   edited but not captured.
4. Commit `asset_patches/` on a branch and open a pull request. The diff shows exactly what
   changed.

Best practice:

- **Capture before you apply.** `apply` refuses to overwrite a hand edit it hasn't
  captured, and `--force` throws the edit away.
- **Put new or replacement pictures and sounds straight into `asset_patches/`** and run
  `apply`, rather than overwriting the file in `assets/`. A file overwritten in place loses
  its original, and only a fresh unzip brings it back.
- **Small patches, one topic per pull request.** Never commit whole tables or anything from
  the pack. Only commit your own work.
- **Pictures don't merge.** Before reworking a picture someone else is working on, agree
  who has it. If binaries get large, move `asset_patches/` to Git LFS.
- **Never commit or share `assets/` or the zip publicly.** Share the Drive link only with
  named people.

### Making the asset pack (project owner)

The pack is built from the original game with `tools/assets/build_assets.py`, which also
applies `asset_patches/`. Make the zip without the patches, so everyone shares the same base,
and upload it again whenever the base changes:

```sh
tools/assets/patch_assets.py zip build/no-peace-port-assets.zip
```

## Project Layout

- `game/`: the Godot project (the engine, interface, AI, map editor).
- `asset_patches/`: the project's edits to the asset pack (see "Editing Assets").
- `tools/`: the asset pipeline (`tools/assets/`), test runner (`check_scenarios.py`), and
  game and server build scripts (`build_game.sh`, `build_server.sh`).
- `server/`: the dedicated multiplayer server's systemd unit and setup guide.
- `docs/`: file formats, mission scripting and AI notes (`technical/`), open work and
  playtesting (`production/`), design notes (`design/`).
- `prototypes/godot-3d/`: the earlier 3D prototype, archived.
- Not in the repository: `assets/` (the asset pack), `maps/` (the map editor's saves),
  `build/` (build output).

## Checks

```sh
python3 tools/check_scenarios.py
```

This runs every test scenario headless (about seven minutes) and checks the rules, the
interface, saving and loading, and a six-player AI game. Run it before opening a pull
request that changes game code.

## Legal Note

No files from the original game (executables, archives, art, sound, maps, text) go in this
repository. The asset pack is made from the project owner's copy and shared privately, only
with named collaborators.
