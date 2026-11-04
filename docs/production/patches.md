# Remake patches

The game plays by the original's rules: the values in the code come from AmericaAddOn.exe
and its data, each cited by address (docs/technical/file-formats.md). Where the remake
deliberately plays differently, the change is a **patch**: listed in
`game/data/patches.json`, switched on or off by the player, and read through `Patches`
(`game/scripts/core/patches.gd`). With every patch off the game is the original.

## What is and is not a patch

- A patch changes a rule or value the original has, on purpose: balance, help for new
  players, a fix for something the original does badly.
- Not patches: values the original surely has but that have not been found yet (the
  "Values chosen without a source" table in open-work.md; replace them with the exe's as
  they turn up), and interface conveniences that change no rule (control groups, the
  upgrades line in the unit panel, wide screens). Those stay in the code as they are.

## The current patches

| id | Default | What it changes |
|---|---|---|
| `campaign_expansion_stats` | on | The base game's campaign missions use the expansion's stat table (most units' hit points doubled, no minimum ranges) instead of the base game's. |
| `very_easy_help` | on | On Very easy in campaign missions, the computer's units and towers deal 60% damage to the player's (the original's scripts read Very easy as Easy). |
| `faster_self_healing` | off | Units with the Self-healing upgrade heal 1 life every second instead of every 3 s. |

## How a match uses them

`Patches.begin` fixes the set when a match starts, and game logic reads only that set:

- a new game: the player's choices (Settings, the `[patches]` section of settings.cfg);
- a loaded game: the set saved with it (saves from before a patch existed get its default);
- a replay: the set recorded with it;
- a network game: the host's choices, sent with the match settings (Net protocol 4).

The settings screen lists every patch with its reason as the tooltip; in the in-game menu
they are shown greyed out, since they cannot change mid-match. On the command line,
`--patches=none` plays the original's rules, `--patches=default` each patch's default, and
`--patches=a,b` only the patches named.

## Adding one

1. Keep the original's value in the code, with its address, as the default.
2. Add an entry to `patches.json`: `title`, `why` (shown to players), `default`, and the
   `values` the code reads instead of the original's.
3. Read it in game logic with `Patches.on(id)` or `Patches.value(id, key, original)`.
   Never from the interface alone: every machine must play by the same set.
4. Add a row to the table above.
