# Technical Architecture Notes

## How the code is organised (rebuild-2d, 2026-10)

The game is a Godot 4 project in `game/`, written in GDScript. `game/README.md` lists the
folders; these are the conventions that hold them together.

**Assets.** The game reads only the asset folder (`assets/`, built by
`tools/assets/build_assets.py` from the original game and the upscaled set; see
`docs/production/unmapped-assets.md`). Everything in it has an English name and an
engine-friendly format:
- sprite sheets are a PNG atlas plus a JSON frame list;
- animation sets are `.anims.json`;
- pictures are PNG;
- tables are JSON in `assets/data/`;
- maps are zlib-packed `.ulf`.

Code names assets by their path in the folder (`GameData.load_sprite("interface/hud/bar/sheet_1")`).
Object types carry English names (`tree_conifer_large_01_prairie`,
`americans_cavalryman_mounted`), and unit actions are found by English words in the sheet
names (`walk`, `idle`, `die`...). The original formats are read only by the Python tools in
`tools/formats/` and `tools/assets/`. New mappings, such as a word or a folder name, go into
`tools/assets/glossary.py`.

**Units and map objects are a core plus parts.** `Unit` (`scripts/world/units/unit.gd`)
holds what every unit has: its state machine, orders, combat, movement, health, morale and
experience. Everything particular to some kinds of unit lives in a part: `UnitWork`
(gathering, hauling, building, hunting, robbing), `UnitRiding`, `UnitAnimal`, `UnitMagic`,
`UnitStealth`, `UnitWater`, `UnitTepees`. Each part extends `UnitPart`. While it is `busy`
it gets the frame before the state machine, and every new order calls its `clear_orders`.
The interface and the AI give orders through methods on `Unit` (`gather`, `board`,
`cast`...). They read a part's state through the part (`unit.work.carrying`,
`unit.water.passengers`).

`MapObject` (`scripts/world/objects/`) works the same way. Every object has an
`ObjectStock` (wood, gold, crops, warehoused gold, abandoned goods). Buildings also have
`BuildingCondition` (construction, damage, fire, repair, destruction), `BuildingProduction`
(queue, research, trades, income) and `BuildingDefence` (garrison, pitfall). These three are
null for trees, mines and fields, so code that may see any object checks `is_building()`
first.

A new rule goes into the part it belongs to. A new kind of behaviour gets its own part.

**Finding things.** Don't loop over `MapObject.all_objects` (thousands of trees and rocks)
or `units_root` children in anything that runs often:
- `MapObject.structures` holds only buildings and fields; `MapObject.abandoned_stores`
  the abandoned warehouses.
- `UnitGrid.near(point, radius)` gives the units in the cells round a point (rebuilt once
  a frame); check the exact distance after.
- The AI gathers its own units and buildings once per think (`AiPlayer.my_units()`,
  `my_buildings()`).

**The interface** (`scripts/ui/hud/`) is `Hud` with `SelectionPanel`, `CommandPanel` and
`GameMenu`. The command panel rebuilds its buttons only when its signature string changes.
Anything a button depends on belongs in that signature.

**The AI** (`scripts/game/ai/`) is `AiPlayer` with `AiEconomy`, `AiBuilder` and `AiArmy`.
Each think runs economy, then building, then the army.

**Saved games.** Objects save and restore their own state (`MapObject.save_state` /
`restore_state`, `AiPlayer.save_state`); `SaveGame` puts the match together.

**Checks.** `tools/check_scenarios.py` runs the scenarios in `scripts/dev/scenarios/`
headless and matches what they print. A new rule should come with a scenario
(`_scenario_<name>` in the fitting group) and an entry in the runner's `CHECKS`.
Scenarios seed the random numbers, so runs repeat. For performance,
`--players=a,b,... --ai-vs-ai=1 --report-after=N` prints frame times, and `--profile=1`
adds the sections timed with `Prof`.

## Original plan (2025, phase 0)

The notes below predate the 2D rebuild and describe intentions, not the current code.

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

