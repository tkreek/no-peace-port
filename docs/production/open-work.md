# Open work

What the remake does not do yet, measured against the original manual (`original/manual.txt`),
plus the values that had to be chosen because neither the manual nor the game data gives them.
Last reviewed 2026-10-09 (branch `rebuild-2d`).

## Not implemented

- Mission goals screen, diplomacy (alliances, sending resources, chat), the signal button.
  These are multiplayer only.
- Campaign and tutorials. Left out on purpose for now.
- Walls, stockades and barricades are not built by the AI (they are placed in segments).

## Balance

AI-against-AI games are the only balance test so far: one 16-minute game per pairing on
"close combat", medium difficulty, run with
`--ai-vs-ai=1 --faction=X --enemy=Y --fog=off --time-scale=4 --fixed-fps 30 --report-after=7200 --trace-ai=1`.
Units alive at the end (2026-10-09):

| Player 1 | Player 2 | Units at 16 min |
|---|---|---|
| Americans | Outlaws | 89 : 14 |
| Mexicans | Americans | 23 : 80 |
| Americans | Native Americans | 35 : 64 |
| Mexicans | Native Americans | 32 : 77 |
| Outlaws | Native Americans | 17 : 80 |
| Mexicans | Outlaws | 62 : 46 |

Roughly: Americans and Native Americans strongest, then Mexicans, then Outlaws. With one
game per pairing the order is noisy (Americans against Native Americans went the other way
in an earlier run). The outlaws field few soldiers: most of their units are workers and
hunters, and their soldiers cost gold that runs short. Fixes so far were in the AI (what it
builds and trains) and in two rules that were wrong: the canoe fought on land, and guns
could not be made. The peoples' own numbers have not been touched.

## Values chosen without a source

These live in code as named constants and should be tuned through play.

| What | Value | Where |
|---|---|---|
| Trade packages and prices | 100 food/wood or 2 guns; base 60/60/100 gold; ±10% per deal; selling pays 70% | `Player.TRADE_*` |
| Bank and mission income | 15 gold every 12 s each, at most 5 buildings of each | `MapObject.INCOME_*` |
| Horse raising | 50 food, 20 s; 5 horses per corral, hacienda or ranch | `GameData` horse stats, `MapObject.HORSES_PER_BUILDING` |
| Gun making | 40 wood and 40 gold for one rifle, 12 s, at the weapons factory | `GameData` gun stats (`MapObject.GUN_GUID`) |
| Cow raising and value | 40 food, 15 s; worth up to 25 gold after 200 s grazing | `GameData`, `Unit.COW_*` |
| Morale | 80–120%; leader helps within 1200 px; his own falls to 80% at 2400 px from home | `Unit.MORALE_*`, `LEADER_REACH`, `HOME_REACH` |
| Experience | +10% per kill, +1% per load delivered, up to +20% effectiveness | `Unit.EXPERIENCE_*` |
| Magic | pool 100 (150 with upgrade), refills 1.5/s; spell costs 30–60 | `Unit.SPELLS`, `MAGIC_*` |
| Damage matchups | anti-cavalry ×2; fire, dynamite and cannons ×3 against buildings; other weapons ×0.5 | `Unit.damage_factor` |
| Horses under fire | a mount takes 80 damage before it falls (when told to shoot it) | `Unit.HORSE_HEALTH` |
| Fire from flaming arrows | burns 20 s at 3 energy/s; 6% a second to leap to a building within 48 px | `MapObject.BURN_*`, `SPREAD_*` |
| Self-healing | 0.6 energy per second | `Unit.SELF_HEAL_PER_SECOND` |
| Repair | half the building cost for the energy restored | `MapObject.add_repair_work` |
| Robbing / stealing | 4 s inside a building; 4 s beside a vehicle; robbers carry 3× their normal load | `Unit.ROB_SECONDS`, `STEAL_SECONDS` |
| Garrison range bonus | a quarter more range when shooting from a fort or tower, counted from its walls | `BuildingDefence.GARRISON_RANGE_FACTOR` |
| Hunting | 5 s to cut a load (a harvest's time), the hunter's own load (15) per trip; DEFS.INI has no gathering rates | `UnitWork.BUTCHER_SECONDS` |
| Tepee packing | 6 s to take a tepee down or set it up | `Unit.PACK_SECONDS` |
| Riverboat capacity | 10 units (the raft's 8 is from the manual) | `Unit.BOAT_CAPACITY` |
| Boarding and landing | board within 72 px of the boat; land within 7 cells of dry ground | `Unit.BOARD_REACH`, `LANDING_REACH` |
| Shipyards | must have deep water within 3 cells of the footprint | `MapObject.SHORE_REACH` |
| AI difficulty | workers, buildings, first attack time, wave size per level | `AiPlayer.DIFFICULTY` |
| AI later game | "rich" at 1200 wood and 1500 gold+food; towers/pitfalls 0–3 by level; a fifth of the army guards home; the wounded turn back below 30% | `AiPlayer` constants |
| Building fire stages | burning below 2/3 energy, burnt-out below 1/3 | `MapObject.FIRE_BELOW`, `BURNT_BELOW` |
| Surrender | the AI gives up 20 s after losing its main building if it cannot rebuild | `AiPlayer.SURRENDER_GRACE` |

## Notes on the original data

- The game's own building icon sheet swaps the outlaws' drugstore (310) and lookout (313).
  The build buttons use the editor portraits from `Defaults.dat`, which are right.
- The manual's explosives hut entry has "Cost 400 wood units" without a colon; the stats
  extractor accepts it.
- Every skirmish map, base game and expansion, joins all start positions by land (often
  through fords), so the AI ferries troops only when the land route is blocked.
  `--ai-ferry=1` forces ferrying for tests.
