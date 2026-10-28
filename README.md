# Frontier RTS Remake

Working title for a modern cross-platform RTS inspired by early-2000s frontier strategy games.

This repository is being scaffolded as a clean-room, modern remake/spiritual successor project. The goal is to build a real-time strategy game that runs on macOS and Windows, supports modern displays and hardware, and improves animation, rendering, UI, AI, and tooling.

## Current Phase

Phase 0: planning and prototype setup.

The current focus is to define the product shape, legal boundaries, technical direction, and first vertical slice before committing to a full content build.

## Guiding Goals

- Cross-platform desktop support for macOS and Windows.
- Modern RTS controls: selection, control groups, camera, minimap, command queues, and contextual commands.
- Higher-quality 3D animation and effects than the historical reference point.
- Scalable visuals for higher-end GPUs while keeping broad hardware support in mind.
- Data-driven units, buildings, resources, upgrades, and mission scripting.
- A playable vertical slice before large-scale content production.

## Project Layout

- `docs/design/` - gameplay, factions, economy, units, campaigns, and UX direction.
- `docs/technical/` - engine evaluation, architecture, performance, platform, and build notes.
- `docs/production/` - roadmap, milestones, backlog, asset pipeline, and team workflows.
- `docs/legal/` - IP, licensing, clean-room, and naming guidance.
- `docs/research/` - notes from studying historical RTS patterns and reference material.
- `game/` - future engine project source.
- `assets/` - source art, audio, animation, and reference assets.
- `prototypes/` - throwaway experiments and technical spikes.
- `tools/` - custom scripts, importers, exporters, and project utilities.
- `server/` - the dedicated multiplayer server's systemd unit and setup guide (`tools/build_server.sh` packs it).

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

## First Target

Build a vertical slice with:

- One small skirmish map.
- One playable faction.
- Three units: worker, ranged fighter, mounted or melee fighter.
- Three buildings: command center, barracks, resource drop-off.
- Two resources.
- Core RTS camera, selection, movement, gathering, building placement, unit training, and combat.
- One basic enemy AI.

## Legal Note

This repository should not contain ripped assets, original game data, proprietary art, proprietary audio, copied maps, copied scripts, or trademarked branding unless explicit rights are obtained.

