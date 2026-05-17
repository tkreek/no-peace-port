# Technical Architecture Notes

## Core Principle

Keep game rules data-driven and simulation-oriented. Rendering, UI, audio, and animation should observe or represent game state rather than becoming the source of truth.

## Major Runtime Domains

### Simulation

- Units.
- Buildings.
- Resources.
- Ownership and teams.
- Health and damage.
- Weapons and cooldowns.
- Production queues.
- Construction.
- Gathering.
- Objectives and win/loss conditions.

### Commands

Player and AI actions should flow through explicit commands:

- Move.
- Attack.
- Gather.
- Build.
- Repair.
- Train.
- Stop.
- Hold position.
- Patrol.

### Navigation

Navigation needs to support:

- Terrain costs.
- Dynamic obstacles.
- Group movement.
- Local avoidance.
- Formation spacing.
- Building placement blockers.

### Presentation

Presentation systems include:

- Meshes and materials.
- Animation state.
- VFX.
- Sound.
- UI widgets.
- Minimap representation.

### Data

Prefer structured data for:

- Unit definitions.
- Building definitions.
- Weapon definitions.
- Resource definitions.
- Faction rosters.
- Upgrades.
- Mission triggers.

## Early Data Schema Candidates

- JSON for external human-editable data.
- Engine-native assets for editor tooling.
- Hybrid approach: author in editor-native assets, export to runtime data.

## Save/Load Direction

Save/load should serialize authoritative simulation state, not presentation-only state. The first version can be simple snapshot serialization; deterministic replay can be considered later if multiplayer becomes a goal.

## Multiplayer Note

Do not design the first prototype around multiplayer unless it becomes a core requirement. RTS multiplayer changes architecture, determinism, testing, and content balance significantly.

