# Playtesting campaign missions

How to get into a mission quickly, see what its script is waiting for, skip past what works,
and report where it stalls. The pieces: `MissionDebug` (the overlay and keys), `Cheats`
(what the cheats do), `Mission` (the script, docs/technical/missions.md).

## Starting a mission directly

From `game/`:

```
godot --path . -- --mission=base/ind_01
```

`--mission=<set>/<code>`: the set is `base` or `expansion`; the codes are `tut_01`..`tut_04`
(tutorials), `ind_01`..`ind_08`, `mex_01`..`mex_06`, `des_01`..`des_06` and
`usa_01`..`usa_06` in the base game, and `<people>_01`, `<people>_02` in the expansion.
Useful additions:

| Option | Does |
| --- | --- |
| `--debug-overlay=1` | opens the overlay at the start (`--debug-trigger=<n>` selects trigger n) |
| `--time-scale=4` | the whole game 4 times as fast (up to 8) |
| `--fog=off` | no fog of war |
| `--trace-mission=1` | prints every trigger that fires, with its actions |
| `--trace-ki=1` | prints every AI module started (2: also what the AI tries to build) |
| `--seed=<n>` | the same randomness every run |
| `--record=<file>` | keeps the run's orders (cheats included) to replay with `--replay=<file>` |

A mission won (also by the win cheat) counts as won in the campaign screen, which opens the
next one.

## The overlay (F9)

F9 opens a panel on the right, in campaign missions only. Top to bottom:

- **The mission**: its title and code, game time, whether the script still runs (it ends
  when no trigger is armed), the speed, the fog, whether a scene locks the player's input,
  the countdown when one runs, and the current goal text.
- **Triggers**: the armed ones in script order, each with its editor name (or, when it has
  none, what it does first, after an arrow) and its conditions in words, each with its value
  now and `yes` or `NO`. A `NO` line in red is what that trigger waits for. A trigger shown
  in green has all it needs and fires the next time the script checks it. After an `OR`
  line any one of the conditions below is enough. The first twelve show; "show all" lists
  the rest. Click a trigger to select it: its actions are listed under it (`→`), its areas
  light up on the map, and Ctrl+Shift+F fires it.
- **Fired**: the triggers that fired lately, newest first, with the game time; those fired
  by the cheat are marked "(cheat)".
- **Timers, flags, variables**: the script's running timers (seconds left, or "run out"),
  the flags that are set, and the variables that have a value.
- **Peoples and AI**: every player of the map with its number (the `P4` in conditions),
  name, people and who plays it; its stockpile, units and buildings; and the AI modules
  running for it, by the name of their source script (`ind02_angriff`, `a_produce ×6`).
  A computer player with no modules does nothing.

Conditions read like `count(P4, Little Crow in "Lager") < 1: 1`: player 4 has 1 Little Crow
in the area named "Lager", and the trigger needs fewer than 1. Areas are the level editor's
named rectangles; an area the map does not have means the whole map. F10 shows or hides the
areas on the map while the overlay is open (the selected trigger's brighter).

The panel scrolls with the mouse wheel. It only reads the game.

## Cheats

In campaign missions (and in any single-player match started with `--cheats=1`; never in a
network game):

| Keys | Cheat |
| --- | --- |
| Ctrl+Shift+R | fog of war off (again: on) |
| Ctrl+Shift+G | +1000 food, wood, gold and guns |
| Ctrl+Shift+K | kill the selected units or building (anyone's) |
| Ctrl+Shift+W | win the mission now |
| Ctrl+Shift+F | fire the trigger selected in the overlay, whatever its conditions say |
| Ctrl+Shift+T | game speed 1x, 4x, 8x |
| Ctrl+Shift+C | copy the overlay's text to the clipboard (and print it to the log) |

The cheats are orders like any other (`Orders.cheat`, carried out at the start of a game
step), so a recorded run replays the same and the game stays deterministic. They also work
while a scene locks the player's orders. Firing a trigger does its actions as the script
would, so it can start AI modules, spawn units or end the mission; it does not set the
conditions true, so later triggers that test the same things may still wait.

## What to report when a mission stalls

1. Open the overlay (F9), find the trigger the mission should fire next (usually the one
   whose actions bring the next goal or message) and click it so its actions show.
2. Press Ctrl+Shift+C and paste the text into the report; add a screenshot with the
   overlay open and, if areas matter, F10 on.
3. Say what you did before it stalled, the mission code, the game time, and what you
   expected: which `NO` condition should have become `yes`, and why you think it did not
   (e.g. "the 4 towers are destroyed, but count(P5, Watchtower in "Sieg") is still 2").
4. If an AI player does nothing, say which `P` and whether its modules line is empty.
5. Whether Ctrl+Shift+F on that trigger lets the mission go on.
