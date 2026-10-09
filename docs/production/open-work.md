# Open work

What the remake does not do yet, measured against the original manual (`original/manual.txt`),
plus the values that had to be chosen because neither the manual nor the game data gives them.
Last reviewed 2026-10-09 (branch `rebuild-2d`).

## Not implemented

### Water
- Boats: the Native canoe, the Mexican and American riverboats, the outlaw raft. They need a
  water navigation grid, loading and unloading of passengers, and passengers shooting from a
  riverboat or raft.
- Native swimming. The Swim upgrade (914 Native, 995 expansion) is researchable but has no
  effect, and units cannot enter water.
- Shipyards (wharf, boathouse) can be built, but the boats they train cannot move on water.

### Native Americans
- Packing tepees onto a travois, moving them, and setting them up again (hotkeys G/L in the
  manual).
- Women building pitfalls from their own menu. The pitfall is currently in the expanded
  structures menu.

### Smaller rules from the manual
- Mounted targets: units should shoot the rider rather than the horse unless told otherwise,
  and a rider shot off leaves a capturable horse. Today a mounted unit dies as one unit.
- Hunters shooting horses for food (not Native hunters).
- Fire spreading from flaming arrows. These do extra damage to buildings, but nothing
  actually burns.
- Mixed groups getting only the commands all members share. The command panel shows the
  union of commands instead.
- A main-menu settings screen. Options exist only in the in-game Esc menu, and there is no
  resolution, mouse speed or UI scale setting yet.
- Mission goals screen, diplomacy (alliances, sending resources, chat), the signal button.
  These are multiplayer only.
- Campaign and tutorials. Left out on purpose for now.

### AI
- It piles up resources late in the game instead of expanding: no second base, no towers or
  walls, no trading.
- It does not use robbing, stealing, camouflage, magic, cattle, wild horses or abandoned
  warehouses.
- It does not retreat or regroup, and it does not use stances or formations.
- Balance between the peoples is untested. In one 12-minute AI game the Outlaws lost
  heavily to the Native Americans.

## Values chosen without a source

These live in code as named constants and should be tuned through play.

| What | Value | Where |
|---|---|---|
| Trade packages and prices | 100 food/wood or 2 guns; base 60/60/100 gold; ±10% per deal; selling pays 70% | `Player.TRADE_*` |
| Bank and mission income | 15 gold every 12 s each, at most 5 buildings of each | `MapObject.INCOME_*` |
| Horse raising | 50 food, 20 s; 5 horses per corral, hacienda or ranch | `GameData` horse stats, `MapObject.HORSES_PER_BUILDING` |
| Cow raising and value | 40 food, 15 s; worth up to 25 gold after 200 s grazing | `GameData`, `Unit.COW_*` |
| Morale | 80–120%; leader helps within 1200 px; his own falls to 80% at 2400 px from home | `Unit.MORALE_*`, `LEADER_REACH`, `HOME_REACH` |
| Experience | +10% per kill, +1% per load delivered, up to +20% effectiveness | `Unit.EXPERIENCE_*` |
| Magic | pool 100 (150 with upgrade), refills 1.5/s; spell costs 30–60 | `Unit.SPELLS`, `MAGIC_*` |
| Damage matchups | anti-cavalry ×2; fire, dynamite and cannons ×3 against buildings; other weapons ×0.5 | `Unit.damage_factor` |
| Self-healing | 0.6 energy per second | `Unit.SELF_HEAL_PER_SECOND` |
| Repair | half the building cost for the energy restored | `MapObject.add_repair_work` |
| Robbing / stealing | 4 s inside a building; 4 s beside a vehicle; robbers carry 3× their normal load | `Unit.ROB_SECONDS`, `STEAL_SECONDS` |
| Garrison range bonus | +60 px when shooting from a fort or tower | `MapObject.GARRISON_RANGE_BONUS` |
| AI difficulty | workers, buildings, first attack time, wave size per level | `AiPlayer.DIFFICULTY` |
| Building fire stages | burning below 2/3 energy, burnt-out below 1/3 | `MapObject.FIRE_BELOW`, `BURNT_BELOW` |
| Surrender | the AI gives up 20 s after losing its main building if it cannot rebuild | `AiPlayer.SURRENDER_GRACE` |

## Known rough edges
- Spell clouds (lightning, hail, rain) are drawn at ground level and can hide the units
  beneath them.
- On the setup screen, matches with many opponents may crowd the option rows near the
  buttons.
- Outlaw building GUIDs 310 and 313 swap in the game's own icon sheet, so building buttons
  keep the editor portraits.
