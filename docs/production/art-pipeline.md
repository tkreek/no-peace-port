# Art And Animation Pipeline

## Goals

- Support high-quality 3D units, buildings, terrain, VFX, and UI.
- Keep assets readable from RTS camera distances.
- Allow iteration without expensive manual import steps.

## Proposed Tools

- Blender for modeling, rigging, and animation.
- Krita, Photoshop, or Substance tools for texture authoring.
- Engine-native materials and VFX tooling.
- Git LFS or external asset storage once binary asset volume grows.

## Unit Asset Requirements

Each unit should define:

- Mesh.
- Rig.
- Materials.
- Team color mask or material slot.
- LODs.
- Selection radius.
- Footprint size.
- Animation clips.
- Audio hooks.
- VFX hooks.

## Starter Animation List

### Worker

- Idle.
- Walk.
- Gather.
- Carry.
- Build.
- Repair.
- Death.

### Ranged Fighter

- Idle.
- Walk.
- Aim.
- Fire.
- Reload.
- Hit reaction.
- Death.

### Mounted Or Melee Fighter

- Idle.
- Walk.
- Run.
- Attack.
- Hit reaction.
- Death.

## Visual Readability Rules

- Strong silhouettes matter more than tiny detail.
- Team color should be visible from normal play zoom.
- Weapons and role-defining props should be exaggerated enough to read.
- VFX should communicate combat without covering units.
- Terrain decoration should not hide important units or buildings.

