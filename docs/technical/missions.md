# Campaign missions

How the original runs its campaign maps, read from the unprotected expansion executable
(`original/expansion/iso/Crack/AmericaAddOn.exe`; addresses are that file's) and checked
against all 38 campaign maps (base game `Kampagne/*.alf`: four tutorials, 8 Native American,
6 Mexican, 6 outlaw and 6 American missions; expansion `Kampagne2/*.ulf`: 2 per people).
The remake's side: `MissionData` (reading), `Mission` (running), `Diplomacy`, `Campaign`
(lists and progress), `CampaignMenu`.

## Map chunks

### `SPIELER`: players
8 records of 300 bytes, one per editor slot (loader 0x442890):

| Offset | Contents |
| --- | --- |
| 0x000 | player number 1..8: the owner number of the map's objects and the scripts' player |
| 0x004 | -1 or 18 |
| 0x008 | slot 1..8 |
| 0x00C | name: a text id in `kampagnen.eng` (100+) or a literal name |
| 0x10C | people: 0 Native Americans, 1 Mexicans, 2 outlaws, 3 Americans; -1 unused slot |
| 0x110 | who plays: 1 human, 2 computer, 3 independent |
| 0x114 | side: a bit per slot (the record's place in the chunk, 0..7) for each player this one is allied with, its own included |
| 0x118 | guns, wood, gold, food (0x422a40 copies them to the stocks the conditions read) |
| 0x128 | 1: take the level's start resources (`LVL_INFO`) instead |

The player number is not the slot: the first tutorial's human is slot 3, player 4.

Starting relations (0x42be40), per ordered pair: an independent player is neutral to
everyone and everyone to it; otherwise player `a` is allied to `b` when b's side mask holds
the bit of a's slot (`mask[b] & 1 << slot[a]`, the slot from world+0xa20, which the loader
fills with each player's record index at 0x442ecf), at war when not. The masks are not
compared with each other: in base/des_05 the human's 0x21 and the computers' 0x3e share bit
5 (an unused slot), but they are at war. The test is one-sided, but every shipped map's
masks agree both ways. A player is allied to itself and shares its own sight. Relation
flags (world+0x8CC, `[from*8+to]`, read by native 206 as `[me][player]`, 0x42bdd0):
1 at war, 2 neutral, 4 allied, 0x20 shares sight. What a player neutral to
yours has joins you when one of your units comes within 96 px (0x42c580, from the unit
update; independent players' own units never take others over): the unit searches the
object grid (world+0x24206c, where every unit and building stamps its footprint) in a square
96 px each way round itself (0x45dbb0, 16 px steps, the first object whose owner has the
neutral bit towards the unit's people) and that object changes hands (0x42cd70: off the old
owner's list onto the new one's; walls 212/312/412 only take the new colour). So an
independent village's tepees join as well as its people: base/ind_06's human gets its
medicine man's tepees, researches the hail dance there (the map's `EINHEIT` allows that
upgrade but no building) and wins with the village's medicine men. Joined objects keep their
values; research and spells are the new owner's.

Each player's menus and object values come from the map's `EINHEIT` and `EIGENSCH` over
Defaults.bin ([file-formats.md](file-formats.md), "Per-player tables"); the base campaign's
maps from the base game's Defaults.bin.

### `AREA`: named rectangles
`u32 count`, then `{u32 id, left, top, right, bottom, name length; char name[length]}` in map
pixels (0x4650c0). Scripts name areas by id; an id that is not there means the whole map
(0x465ff0).

### `ABLAUF`: the script
`u32 trigger count`; per trigger `u32 item count` and items `{u32 opcode, u32 kind, ...}`:
kind 0 an action and kind 1 a condition, each `u32 count` + `count` params; kind 2 a note
(`u32 length` + text, the trigger's name in the editor; opcode -1). Up to 20 conditions and
20 actions a trigger (0x464f70).

## Running (0x464ed0)

Every 20 ms game step: the 50 timers that are above 0 count down by 20 (ms, floor 0; -1 =
stopped), then the next armed trigger after the last one checked is checked; when none is
armed the script is over. So with N triggers each is looked at every N/50 s.

Checking a trigger (0x465240): conditions in order. Normally all must hold (the first that
fails ends the check); after an OR condition (15) the first that holds is enough. A trigger
that fires disarms, then does every action; an action "stay armed" (10) re-arms it.

## Conditions (0x465330)

Players are player numbers; `type` is a GUID (`GUIDS.INI` ids: 100.. Native buildings,
150.. units, 200/250 Mexican, 300/350 outlaw, 400/450 American) or a category below 100.

| Op | Params | Holds when |
| --- | --- | --- |
| 1 | | always |
| 2 | player, amount, resource | stock >= amount |
| 3, 11 | player, n, type, area | exactly n of type in the area |
| 4 | seconds | the countdown runs and shows less than that |
| 5 | flag | flag (0..99) set |
| 6 | player, area | something of the player sees part of the area |
| 7, 9 | player, n, type | fewer than n |
| 8, 10 | player, n, type | more than n |
| 12 | player, amount, resource | stock < amount |
| 13 | player, n, type, area | more than n in the area |
| 14 | player, n, type, area | fewer than n in the area |
| 15 | | never; from here on any condition is enough |
| 16 | timer | timer (0..49) has run out (is 0) |
| 17 | variable, value | variable (0..19) equals value; unset is false, another value disarms the trigger |
| 18 | flag | flag clear |

Resources: 1 food, 2 wood, 3 horses, 4 gold, 5 guns.

Categories (0x42a0b0): 0 all units, 1..4 Native, Mexican, outlaw, American units; 5 all
buildings, 6..9 per people; 16 all soldiers (leaders, fighters, heroes), 17..20 per people.
Some GUIDs count a unit on foot and mounted together: 165 (150+151), 166, 167, 168, 267, 268,
269, 365..368, 475..478. Animals: 480 horses and 482 cows by owner, 481 buffalo whoever
owns them, 483 a horse of nobody's. Buildings under construction count.

## Actions (0x465740)

| Op | Params | Does |
| --- | --- | --- |
| 1 | player, module | starts AI module `kimodules/%08d.mod` (`kimodules2` in the expansion) for the player |
| 2 | player, area | the player's view to the area's centre |
| 3 | player, n, type, area | n new units at the area's centre (animals for nobody; 483 a horse) |
| 4 | player | the player has lost ("verloren.mp3"; the end screen 6 s later) |
| 5 | text, player, seconds | message for the player |
| 6, 34 | player, type, area | takes the player's objects of type in the area off the map |
| 7, 8 | | nothing |
| 9 | text | message with `sfx/missions/%03d.mp3` spoken, as long as the recording (bytes / 15898 + 2 s) |
| 10 | | the trigger stays armed |
| 11 | seconds | starts the countdown |
| 12 | flag | sets the flag |
| 13 | player | the player has won ("gewonnen.mp3") |
| 14 | type, x, y | a neutral object at the spot |
| 15, 16 | | shows / hides the countdown clock |
| 17 | seconds | the world stands still (no map uses it) |
| 18, 19 | | locks / unlocks the player's input (scenes) |
| 20 | player, area | uncovers the area for the player until covered |
| 21, 22 | player, amount, resource | adds / takes resources |
| 23 | flag | clears the flag |
| 24 | player, area | covers the area again |
| 25 | timer, seconds | starts a timer |
| 26 | timer | stops a timer |
| 27 | text | the mission goals ("Mission goals" in the game menu: its numbered parts are crossed out once a later goal text drops them or a trigger listed for them in game/data/campaign_goals.json has fired; tools/campaign/goal_parts.py reviews that table) |
| 28, 29 | player, player | share / stop sharing sight, both ways |
| 30 | player, player | allied, both ways |
| 31 | player, player | at war |
| 32 | player, player | neutral |
| 33 | variable, n | variable = random number below n |
| 35 | type, area, player | everything of type in the area, of any other player, goes over to the player |
| 36 | type, x, y, player | an object of type for the player at the spot (a hero, in the maps) |

Texts are `text2.eng` (`text2-Add-on.eng` for the expansion's maps, whose ids overlap the
base game's), `@` a line break. The briefing is `missionen.eng` (story) and `kampagnen.eng`
(titles 0..35 by people: 0 Native, 10 Mexican, 20 outlaw, 30 American; 40..43 people names;
100+ player names), narrated by `sfx/missions/<people><nn>.mp3` (`missions2` for the
expansion). Its picture `global/gfx/menues/kampagne/<people>0<n>.pic` (`<people>1<n>` in
the expansion) is the bottom-left corner (0, 330) of the storyteller's backdrop
`<people>.pic` with the mission's map drawn on the parchment.

## Script quirks the original has too

* base/ind_08: Capt. Weirs (291, player 8) walks `ind08_wpdef`'s waypoints with
  `ind08_wpabklappern` (224269), which, once his hit points are below 50 %, sends him
  (`move`) to the nearest of three map exits: (8010, 5235), (8010, 7867) or (5220, 12104).
  The middle one lies in area 13 and is the nearest from about waypoint 3 to waypoint 6 of
  his route. There trigger 11 (after timer 7's 30 s) takes him off the map and clears flag 1
  ("Capt. Weirs has crossed the river.", the text of the defeat trigger 4, but no defeat).
  Then neither trigger 5 (flag 1 and no Weirs: Custer's attack and the next goal) nor 4 (Weirs
  in area 1) can fire. The mission is still won through trigger 19 (every unit of player 2,
  Kearny included, dead) -> 10 (player 3's camps went for trigger 1) -> 16, only without Custer's attack or the goal telling the
  player so. The remake does the same (`--scenario=steps` with `teleport`/`hurt` on Weirs near
  waypoint 5: trigger 11 at 67 s, then 19 -> 10 -> 16 wins); the original's trigger runtime
  (0x464ed0, actions 6 and 23) and `health_unit` (306, 0x43c07f, integer percent) leave no
  room for anything else.
* base/usa_03: orange's attack waves stay at home while the human's units stand within
  about 1900 px of orange's command post (its camp watch keeps taking the wave's leader);
  see [ki-natives.md](ki-natives.md), "Claims".

## Checking the missions

`tools/campaign/check_missions.py` reads every campaign map's script and the AI modules it
starts, and checks them against the remake's data and code without running the game:

```
tools/campaign/check_missions.py -o report.md      # all 38 missions, markdown
tools/campaign/check_missions.py --json            # the same findings as JSON
tools/campaign/check_missions.py base/ind_03       # some missions ("ind_03": the base set's)
tools/campaign/check_missions.py --dump base/tut_01   # players, areas and triggers, readable
```

It reports, as ERROR (breaks the mission), WARN (probably deliberate or harmless, or the
original's own slip) or INFO: areas, texts, speech, AI modules (and what they gosub/spawn)
and players a script names that do not exist; natives the modules call that `KiNatives`
does not implement or pops/pushes differently from the original; GUIDs the remake cannot
count, spawn or create; flags, timers and variables tested but never set; triggers that
stay armed and start modules or spawn without limit; triggers that can never fire; whether
a chain of triggers can reach the human's WIN (and the chain), and how LOSE can happen. The
tables it shares with the game (`Mission.EITHER`, the category ranges, herders, thieves,
horse and cow buildings) are read from the GDScript sources, and checked against the
object data too. With the original game's files in `original/` it tells a text or module
the asset build lost from one the original lacks as well.

"Can fire" is an over-approximation, computed to a fixed point: a condition can hold when
the triggers that can fire set up what it tests, and a count condition when the player can
have enough of the type: placed on the map, spawned, created or converted by a trigger,
joined from a neutral (independent) player, driven off (cows, by herders) or stolen
(transports, by thieves), or built and trained (the human, and players a trigger starts a
module for) from its people's production buildings and prerequisites. A count only placed
or spawned is bounded by how many there are. The tool cannot tell whether an AI module will
walk a unit into an area or build something; a WIN that only an AI player's building or
training can reach is marked doubtful.
