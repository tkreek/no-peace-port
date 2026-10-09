# Unmapped assets

`tools/assets/build_assets.py` builds `assets/` from the original game and the upscaled
set. This note lists what it leaves out, and what it brings in that the game does not use
yet, so you can decide what to map later. The full per-file list is in `assets/REPORT.md`
after a build; `assets/manifest.json` maps every included original file to its new name.

Of 6,546 original files, 2,706 are in the asset folder (1.2 GB), and 4,082 are left out.

## Left out

| What | Files | Original folders | Note |
| --- | ---: | --- | --- |
| Palettes (`.ftb`) | 2,109 | everywhere | Not needed: the upscaled graphics carry their own colours and team-colour masks. |
| Campaign AI modules (`.mod`) | 1,311 | `kimodules/`, `kimodules2/` | The scripted computer players of the campaign missions. Needed only for a campaign. |
| Original pictures (`.spx`, `.shw`, `.spr`, `.pic`, `.bmp`) | 367 | units, effects, menus | Two kinds. Most are sheets in unit folders that no animation set names (older or alternative versions, e.g. the Mexican woman's `01_laufe.spx`). The rest are pictures replaced by their upscaled versions. Also `startbild.bmp`/`about.bmp` (start and about screens) and `ladebalken.pic` (a loading bar). |
| Campaign and missions | 186 | `kampagne/` (30 base campaign maps), `kampagne2/` (8 expansion maps), `sfx/missions*/` (92 spoken briefings), `global/gfx/menues/kampagne` (40 campaign map pictures), the campaign and mission texts | Map these when the campaign is built. |
| Other original menu screens | 38 | `global/gfx/menues/` (statistics, credits, settings, load/save, single player) | The game draws its own menus over the main menu and level select art. The statistics screen art (`abrechnung`) could dress up the end-of-game screen. |
| Multiplayer menus | 30 | `global/gfx/menues/` (lobby, chat, network, connection) | Only for multiplayer. |
| Other data | 27 | `global/guids*/`, `sfx/`, root | Superseded base-game tables (the expansion's are used), `ids.ini`, the level editor's `.cfg` files, `sfx/properties.ini` (sound event names) and `rules.def` (the tech tree, binary, not decoded). **`rules.def` is worth decoding** if prerequisites ever need to come from the game rather than the manual. |
| Medicine man song leftovers | 6 | `sfx/voices/medizinmann tanzen/` | Stray `.pk` files and a duplicate `.wav (2)`. |
| Credits and logos | 4 | `global/guids*/` | Credits text and the publisher logo animation. |
| Level editor data | 3 | `editor_daten/`, root | The original editor's start flag and texts; the map editor draws its own. |
| Status icon set | 1 | `global/gfx/usa/sonstigeicons/sonstigeicons.bob` | Its sheets aren't upscaled. The game uses the `.spr` icon sheets in that folder directly. |

Missing: the sound table names `sound alarm.wav` and `sound alarmglocke.wav` (alarm, alarm
bell), but neither is in the archives. They were never in the game.

## Included but not used yet

These have English names in the asset folder and are ready to use:

- **Ambient effects** (`effects/`): water ripples, bubbles, fog, an aura, and the original's
  "sensor" and "comsat" markers. (Since wired in: the corpses rotting, through
  `UnitRemains`; smoke over ruins, through `BuildingCondition`; gulls and the eagle, through
  `Ambience`.)
- **Weapons factory** (`buildings/mexicans/weapons_factory/weapons.anims.json`): an older
  copy of the factory's animation set, with a 5-frame furnace loop instead of 7. The game
  uses the current set.
- **Native storage camp** (`buildings/natives/camp/store.anims.json`).
- **Second animation sets** for the American cavalryman, the native archer and the outlaw
  hunter (`*_2.anims.json`). The object types use the first ones.
- **Interface icon sets** (`interface/icons/...anims.json`): per-people icon animations. The
  game uses the `.spr` sheets beside them.
- **Status bar animation set** (`interface/hud/bar/status.anims.json`) and a tree overview set
  (`nature/prairie/trees/trees.anims.json`).
- **Sounds** the sound table doesn't name (35): long and short dying cries for men and women
  (`sounds/voices/dying_man`, `dying_woman`), a cannon shot, "message" and "notify" chimes, a
  short Mexican voice line and the medicine man's silence.
