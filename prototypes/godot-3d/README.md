# Frontier RTS Prototype

This is the first Godot 4 gameplay prototype for the RTS remake/spiritual successor.

## Current Features

- Procedural 3D test map with ground, river, trees, rocks, and a placeholder building.
- Command Post building with an in-world label.
- Wood stand, gold mine, and garden resource assets.
- Mexican Weapons Factory with cannon training cost.
- Worker construction flow with build command buttons, placement outline, construction sites, progress labels, and faster build speed with multiple workers.
- Five controllable placeholder units.
- Trainable Mexican cannon unit.
- Enemy warrior targets for cannon combat testing.
- RTS camera with WASD movement, edge scrolling, and mouse-wheel zoom.
- Drag-select units.
- Left-click or right-click movement for selected units.
- Worker resource loop: assign a worker to wood, gold, or food and it gathers, returns to the Command Post, deposits +10, then repeats.
- Cannon combat loop: train a cannon, select it, then click enemy warriors to fire.
- Simple formation offsets, gather slots, deposit slots, and local unit separation to reduce crowding.
- Classic RTS HUD shell with resources at the top, unit details along the bottom, and a minimap in the bottom right.
- Selection details for units and buildings, including name and health.
- Looping Mexican faction music theme during gameplay.

## How To Run

1. Open Godot 4.x.
2. Import/open the `game/project.godot` project.
3. Run the main scene.

## Controls

- `WASD`: pan camera.
- Mouse at screen edge: pan camera.
- Mouse wheel: zoom.
- Left mouse click: select a unit or move selected units.
- Left mouse click a building: select it and view name/health details.
- Left mouse drag: box-select units.
- Right mouse click: move selected units.
- Left-click or right-click a resource with workers selected: gather that resource.
- Select a worker: building buttons appear in the bottom command panel.
- Click a building button: a placement outline follows the cursor.
- Left-click the map while placing: spend resources and assign selected workers to build.
- Right-click while placing: cancel placement.
- Click `Train Cannon` in the bottom command panel: spends `20 food`, `80 wood`, and `40 gold`.
- Left-click or right-click an enemy with a cannon selected: attack.

## Next Prototype Targets

- Add terrain-aware navigation around obstacles.
- Add building placement.
- Add enemy movement and counterattacks.
