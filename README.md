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

