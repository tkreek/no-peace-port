# Engine Evaluation

## Decision

Use Godot 4 for the first playable prototype.

The project is coming from an early-2000s RTS reference point, so Godot 4 should be capable of the target if the simulation, navigation, animation, and rendering are built with RTS-scale constraints in mind. The first technical milestone is to prove this with a playable map, units, camera, selection, and movement before committing to larger content.

## Evaluation Criteria

- macOS and Windows desktop support.
- RTS-scale unit counts.
- 3D animation workflow.
- Terrain and foliage tooling.
- UI tooling for command panels and minimaps.
- Pathfinding options.
- Data-driven content workflows.
- Build pipeline and patching.
- Modding potential.
- Team familiarity and long-term maintainability.

## Godot 4

### Strengths

- Open-source and lightweight.
- Pleasant scripting and clean project structure.
- Good for custom systems and tight control.
- Strong enough for a faithful/enhanced RTS prototype when units are kept lightweight.
- Simple cross-platform desktop target for macOS and Windows.

### Risks

- 3D production pipeline and high-end rendering are less mature than Unity or Unreal.
- Large group pathfinding will need careful prototyping.
- Animation and per-unit script costs must be watched early.

## Unity

### Strengths

- Strong cross-platform desktop builds.
- Good iteration speed.
- Large ecosystem for RTS-adjacent tooling.
- Mature animation import pipeline from Blender.
- Flexible UI options.
- Good fit for editor tooling and data-driven ScriptableObject workflows.

### Risks

- Large RTS pathfinding and simulation may need custom architecture.
- Render pipeline choice matters early.
- Poorly structured GameObject-heavy code can become hard to scale.

## Unreal Engine

### Strengths

- High-end rendering and cinematic tooling.
- Strong terrain, lighting, materials, and VFX.
- Good animation systems.
- C++ performance ceiling.

### Risks

- RTS UI and selection workflows may take more custom work.
- Heavier project footprint.
- Slower iteration for some gameplay systems.

## First Technical Spike

The first spike should test:

- 200 animated units moving on terrain.
- Box selection and command issuing.
- Basic pathfinding around obstacles.
- Health bars and selection indicators.
- One terrain scene with lighting, water, and foliage.
- macOS and Windows build feasibility.
