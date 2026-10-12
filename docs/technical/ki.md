# The KI virtual machine (the original's AI scripts)

Everything here was read from the unprotected expansion executable
`original/expansion/iso/Crack/AmericaAddOn.exe` (image base 0x400000; all addresses are that
file's virtual addresses) and checked against the 1311 module files of both games
(`original/extracted/america3/kimodules/*.mod`, 745 files, and
`original/expansion/extracted/america8/kimodules2/*.mod`, 566 files). The base game's
`america.exe` is packed and was not disassembled. Its modules use the same file format and
only native ids the expansion implements (see "Base game" at the end).

Tools (`tools/ki/`, reading `original/` or the built `assets/campaign/*/ai/`):

* `kimod.py`: parser and disassembler (`kimod.py FILE.mod`, `kimod.py --stats DIR...`).
* `kidec.py`: decompiler to pseudo-code (statements, if/else, while; gotos otherwise).
* `kinatives.py` (+ `native_sig.json`, the argument and result counts found by running every
  native's handler in an emulator): the native table.

The natives in detail: [ki-natives.md](ki-natives.md). The remake's machine:
`game/scripts/game/ki/` (KiModule, KiStore, KiTask, KiPlayer, KiNatives, KiWorld, KiManager).

"KI" is German for AI (*Künstliche Intelligenz*). The scripts were written in a C-like language
(`*.aml`, kept in `kimodules2/sources/`, not shipped) and compiled to this stack bytecode.
The DEBUGGER section still names the source file, and VARMAP still holds the variable names.

---------------------------------------------------------------------------------------------

## 1. File format

All integers are little-endian u32 unless noted.

```
char[8]  "KIMODULE"
u32      size                       file length - 12
then sections until the end of the file:
char[8]  name                       space-padded: "HEADER  ", "VARIABLE", "CONSTDAT",
                                    "CODEDATA", "VARMAP  ", "DEBUGGER"
u32      length                     bytes of section data that follow
```

The loader (`CKIModuleObject::LoadKIModule`, 0x43e230) reads the magic and size, then
loops over sections by name with `strncmp`; unknown names are skipped. Every shipped file
has all six sections in the order above.

| Section | Layout | Loader |
| --- | --- | --- |
| `HEADER` | `u32` = 1 in every file. | stored in module+0x130; never read again. |
| `VARIABLE` | `u32 n`, then `n` x `{u32 descriptor, u32 count}`. The descriptor is `class<<24 \| type<<16` (see 3). Declares `count` slots of that class/type. | 0x40f000: allocates `count` dwords (zeroed); for class 2 (arrays) also `count` array objects. |
| `CONSTDAT` | `u32 n`, then `n` x `{u32 variable id, i32 value}`. Initial values. | 0x40f160: plain stores (0x40f1d0) into the slots. |
| `CODEDATA` | `length/4` instruction words. | 0x40e6a0: code object at module+0x648 = `{vtbl, pc, count, words*}`. |
| `VARMAP` | `u32 n`, then `n` x `{char name[32], u32 variable id}`. Debug names; compiler temporaries and literal constants are called `#INTERNAL#`. | read only when the player's KI is in debug mode (KI+0x82c). |
| `DEBUGGER` | `char source[256]` (e.g. `ind01_einleitung.aml`), `u32 n`, `u32 first_pc[n]`: `first_pc[i]` = index of the first instruction of source line `i` (0-based; lines without code repeat the previous value). | debug mode only: also loads `kimodules2/sources/<source>` for the in-game debugger (0x43eb00). Line lookup: 0x43ed80 = last `i` with `first_pc[i] <= pc`. |

Example `00159232.mod` (`ind01_einleitung.aml`): VARIABLE declares 13 ints, 1 building and
1 unit array; CONSTDAT gives ten literals (ids 2, 3, 5..12) their values; VARMAP names
`i`, `j`, `feind`, `einheit`; CODEDATA is 29 words.

## 2. Instruction encoding

One instruction per 32-bit word: `opcode = word >> 28`, `operand = word & 0x0FFFFFFF`.
Interpreter: `CKIModuleObject::Step` at 0x43e860; it fetches with 0x40e6f0 (returns
`words[pc++]`, or -1 when `pc >= count`) and jumps through the 10-entry table at 0x43eacc.
Opcodes 10-15 (including the -1 returned at the end of the code) do nothing.

| Op | Word | Mnemonic | Semantics | Handler |
| --- | --- | --- | --- | --- |
| 0 | `0x0vvvvvvv` | `push v` | push the value of variable `v` (references resolved, see 3) | 0x43e8a8 (0x40f270) |
| 1 | `0x1vvvvvvv` | `pop v` | pop into variable `v` (references resolved); `v = 0x0FFFFFFF` just discards the top (`drop`) | 0x43e8d4 (0x40f220) |
| 2 | `0x2vvvvvvv` | `pushi n` | push the 28-bit operand itself. The compiler uses it only to pass a variable id by reference (an array, or a variable a native or a subroutine writes): all 4934 uses push the id of a declared variable, e.g. `0x22030000` = `&einheit` (array of units, index 0). | 0x43e90c |
| 3 | `0x3vvvvvvv` | `popraw v` | pop and store into slot `v` of the module's own store without following references (0x40f1d0). The compiler uses it to receive a by-reference parameter (a `ref array` slot, class 3) at the start of a subroutine: `pushi &e` in the caller, `popraw g` in the callee (3 uses, all in `a_umschiffen*`). | 0x43e92c |
| 4 | `0x4nnnnnnn` | `call n` | call native `n` (1..401) through the dispatcher 0x43a250(n, stack, varstore, module); the native pops its arguments and pushes 0 or 1 results. | 0x43e964 |
| 5 | `0x5mmmmmmm` | `gosub m` | call module `kimodules2/%08d.mod` (`m` decimal, 8 digits) as a subroutine (see 5). | 0x43e9c0 |
| 6 | `0x6mmmmmmm` | `spawn m` | start module `m` as a new, independent script of the same player (see 5). | 0x43ea51 |
| 7 | `0x7aaaaaaa` | `jmp a` | `pc = a` (word index). | 0x43eab0 |
| 8 | `0x8aaaaaaa` | `jz a` | pop; if the value is 0, `pc = a`. | 0x43ea90 |
| 9 | `0x9aaaaaaa` | `jnz a` | pop; if the value is not 0, `pc = a`. (53 uses in all files.) | 0x43eaa1 |

So there are **10 opcodes**. Everything else (arithmetic, comparisons, logic, arrays, waits,
semaphores, engine access) is a native call. A jump to `count` (one past the last word) ends
the module; the compiler emits `return x` as `push x; jmp <end>`.

Usage over all 1311 modules: push 185513, pop 49144 (of which drop is part), pushi 4934,
popraw 3, call 114776, gosub 3970, spawn 5305, jmp 43354, jz 30617, jnz 53.

### Evaluation stack

Each module has an operand stack object (0x198 bytes, vtable 0x4a9860): `int v[100]` at +4
and the depth at +0x194. `push` (0x463d40) on a full stack sets the global error flag and
copies an error string (0x4b182c "error", 0x4b31c0) instead of pushing; `pop` (0x463dc0) on an
empty stack returns 0. Values are plain signed 32-bit integers; there are no floats or
strings. Object handles (units, buildings, neutral objects) are 32-bit ids (see 7).

Operand order: arguments are pushed left to right, so a native's *last* argument is on top.
Example: `native 2` (subtract) pops `a` (top) then `b` and pushes `b - a`; the source
expression `x - 1` compiles to `push x; pushc 1; call 2`.

## 3. Variables, constants and references

Every module has a variable store (module+0x140, 0x508 bytes; class `0x4a18f4`):
16 classes x 10 types of `{int count, int *slots}` (0x40ef40). A variable id is

```
bits 24..27  class   0 scalar, 1 reference to a scalar, 2 array, 3 reference to an array
bits 16..23  type    0 int, 1 bool, 2 building, 3 unit, 4 neutral object (tree, mine, cow...)
bits  0..15  index   slot number within (class, type)
```

The type is only a compile-time tag (the VM treats every slot as a 32-bit int) but the
compiler keeps separate slot ranges per type, and VARMAP names make the meaning clear:
type 2 holds `gebäude`, `palisade`, `haus`; type 3 `e`, `einheit`, `feind`; type 4 `pferd`,
`Baum`, `OGold`, `Kuh`.

* **Constants** are not a separate pool: every literal used by the code gets its own
  `#INTERNAL#` scalar slot whose initial value is set by CONSTDAT and that is read with
  ordinary `push`. (CONSTDAT also initialises named variables, e.g. `int s = 0`; typed
  "null object" constants such as a neutral 0 get a slot of that type.)
  The disassembler shows such pushes as `pushc <value>`.
* **Scalars** (class 0): `push`/`pop` read and write the slot (0x40f2b0 / 0x40f1d0). Bad
  indices read 0 and ignore writes.
* **Arrays** (class 2): each slot holds a pointer to a growable int array
  (12 bytes, vtable 0x4a97e4: `{vtbl, int *data, int size}`, created with size 1 at load,
  0x459db0). They are only accessed through natives that receive the array's id by
  `pushi`: `get(arr, i)` (0x459e50), `set(arr, i, v)` (0x459e20), `copy(dst, src)` (0x459f00).
  An index from 0 to 1000 grows the array to `index + 10` elements (0x459e80);
  outside that range get returns 0 and set is ignored. `popraw`/`pop` on an array slot is
  refused by 0x40f1d0 (class 2 without bit 0 is write-protected).
* **References** (class bit 0 = 1): the slot holds the id of a variable of the *calling*
  module. Reads (0x40f270) and writes (0x40f220) look the id up in the module's store, then
  continue in the parent store (store+4) as long as the found id still has bit 24 set.
  A module's parent store is the caller's store for `gosub` and none for `spawn` or for a
  module started by the engine (a reference then reads 0 / ignores the write). Only
  class 3 (`ref array unit`, e.g. a parameter `geleit`) occurs in the shipped files.

Stack discipline: with the argument and result counts of `kinatives.py` (and a subroutine's
parameters = its leading `pop`/`popraw`s), every one of the 1311 modules has the same stack
depth on all paths into each instruction and never pops below its parameters
(`checkstack.py`); 224 modules end with one value on the stack (their return value), the
others with none.

Initial values: every slot not named in CONSTDAT is 0 at load. Variables are per module
instance; nothing is shared between modules except through the player's KI globals (see 6).

## 4. Execution and scheduling

### Per-player KI objects

`CKIManager` (singleton at 0x7d2c98) holds one `CKIPlayer` per player at
`0x7d2c98 + 0xfa0 + player*4` (players 0..8; the scheduler visits 1..8).
`0x438300(player, debug)` creates it (0x19d38 bytes, ctor 0x439e70) with **200 module slots**
(`0x43a210(200)`: `CKIModuleObject *slots[200]` at +0x19930, count at +0x19934).
It is created at match start for every slot whose player type is 2 (computer;
0x444596..0x4445bc, which also starts module **40397**, `addon_main.aml`, the skirmish AI),
and by the cheat-console parser at 0x431860 (strings `startmodule`, `endallmodules`, `cpuon`, `cpuoff`; which command takes which path was not traced).
`0x4396f0(player)` deletes it.

CKIPlayer layout (offsets):

| Offset | Contents |
| --- | --- |
| +0x4 | round-robin cursor of the scheduler |
| +0x8 | `int q1[256]` ring buffer of unit handles (head +0x808, tail +0x80c): "unit attacked" events (see natives 330/331) |
| +0x408 | `int q2[256]` ring buffer (head +0x810, tail +0x814): "building attacked" events (natives 329/332) |
| +0x818 | byte: an atomic section is active (native 304) |
| +0x81c | slot index that owns the atomic section |
| +0x820 | slot index currently being stepped |
| +0x824 | debugger: selected slot |
| +0x828 | player number (the scripts' `ME`, native 308) |
| +0x82c | byte: debug mode (load VARMAP/DEBUGGER and sources) |
| +0x82d | `byte sem[256]`: semaphores, 0 free / 1 taken (natives 221-223) |
| +0x930 | `int table[100][256]`: shared tables (natives 233-248, 354, 390/391) |
| +0x19930 / +0x19934 | module slots / slot count (200) |
| +0x19938 | `int global[256]`: shared globals (natives 219/220) |

### Starting modules

* Trigger action "run AI module" (ABLAUF action 1, 0x465764) and the console call
  `CKIManager::StartModule(player, id)` = 0x438450: formats `kimodules2/%08d.mod` and calls
  0x43d900 on that player's CKIPlayer (fails if it does not exist).
* 0x43d900(path, parent=0): finds the first free slot (0x43a110; **fails silently when all 200
  slots are used**), allocates a CKIModuleObject (0x684 bytes, ctor 0x43e050), loads the file
  with its own new stack and no parent store, and puts it in the slot.
* `spawn m` (opcode 6, 0x43ea51 -> 0x43d9d0): same, but the new module's stack starts with a
  copy of the **top 10 values** (fewer if the stack is shallower) of the spawning module's
  stack (0x463de0). Those are its arguments: the callee begins with one `pop` per
  parameter (last parameter first), and the caller drops the values itself afterwards:

  ```
  push Player; push s; pushc 152; push mainx; push mainy; spawn 106992; drop; drop; drop; drop; drop
  ; 00106992.mod starts: pop vMainY; pop vMainX; pop guid; pop s; pop Player
  ```
  The spawned module is independent: it does not end with its creator.
* `gosub m` (opcode 5, 0x43e9c0): loads `m` as a child (module+0x12c) that **shares the
  caller's stack** and has the caller's store as parent store (so reference parameters
  work), and sets bit 0x10 in the caller's state. While the bit is set, every step of the
  caller steps the child instead; when the child reaches its end it is deleted and the
  caller continues after the `gosub`. Arguments are popped by the callee from the shared
  stack; whatever the callee leaves on the stack is its return value
  (`push 0; jmp end` = `return 0`), typically popped by the caller right away
  (`gosub 224192; pop guid`). Subroutines nest without limit. The module file is
  re-read from disk at every gosub/spawn.

### Module state

CKIModuleObject (0x684 bytes):

| Offset | Contents |
| --- | --- |
| +0x8 | parent module (only set while loading; cleared for spawned modules) |
| +0xc | file path (256 bytes; source name in debug mode) |
| +0x10c, +0x110 | x, y of the last successful build placement (natives 135/292 -> 293/294) |
| +0x114, +0x118 | x, y found by native 228 (read by 226/227) |
| +0x11c, +0x120 | x, y found by natives 394/395 (read by 396/397) |
| +0x124, +0x128 | list of `{int a, int b}` pairs and its count from native 229 (read by 230-232) |
| +0x12c | child module of a running `gosub` |
| +0x130 | HEADER value |
| +0x134 | state: 1 runnable, 4 finished, 0x10 added while a gosub child runs |
| +0x138 | owning CKIPlayer |
| +0x13c | evaluation stack (owned unless this is a gosub child, +0x668) |
| +0x140 | variable store (+0x144 = parent store) |
| +0x648 | code `{vtbl, pc, count, words}` |
| +0x658 | semaphore the module is waiting for, or -1 |
| +0x4 | handle written by natives 329/330 (read by 331/332) |
| +0x664 | sleep timer in ms (native 40/41) |
| +0x680 | current source line (debugger) |

### The scheduler: one instruction per module per tick

The match loop advances game time by 20 ms per simulation tick (0x444a74: `[0x4b9888] += 20`)
and, when AI is enabled, calls `CKIManager::Run` (0x4383c0) once per tick, which calls
`CKIPlayer::Run` (0x439f80) for players 1..8:

```
n = 200 / KISpeed                      // KISpeed = world+0xec = [0x590b0c], set to 1 at 0x42d529
repeat n times:
    slot = (cursor + i) mod 200        // cursor at KI+0x4, advanced by n afterwards
    m = slots[slot]
    if m and (m.state & 1):
        paused = atomic_active and slot != atomic_owner
        if Step(m, paused) & 4: delete m (0x43a140); slots[slot] = 0
```

`CKIModuleObject::Tick` (0x43e650, `paused` argument):

1. If waiting for semaphore `k` (+0x658 >= 0): if `sem[k]` is still taken, return (blocked);
   otherwise take it (`sem[k] = 1`), clear the wait, and go on.
2. If a gosub child is running (state & 0x10): `Tick(child, paused)`; if the child has
   finished, delete it and clear the bit. Return.
3. If the sleep timer is > 0: subtract `KISpeed * 20` and return.
4. If `paused`, return.
5. If `pc >= count`, state = 4 (finished). Execute **exactly one instruction** (0x43e860).

So with the default KISpeed 1 every live module executes one VM instruction every 20 ms
tick (50 instructions per second per module); `wait(ms)` costs one instruction plus
`ceil(ms/20)` ticks. Modules run in slot order within a tick, and a module started during a
tick gets its first step in that tick if its slot comes later. There is no other time
slicing, priority, or instruction budget. A module ends only by running past its last
instruction (there is no "end" opcode and no native to kill another module; the console
command `endallmodules` and `CKIPlayer` deletion remove all).

The debugger variant `0x43a040`/`0x43e740` (used when the game runs the KI single-stepped,
0x444bc3) runs each module until its source line changes.

### Waiting, semaphores, atomic sections

* `wait(ms)` (natives 40, 41): module+0x664 = ms; the module sleeps for that many ms of game
  time (counted down by 20*KISpeed per tick).
* `lock(k)` (221): if `sem[k]` is free it is taken at once; otherwise the module records `k`
  and blocks before its next instruction until the semaphore is free, then takes it.
  `unlock(k)` (222) frees it; `locked(k)` (223) tests it. 256 semaphores per player, shared by
  all that player's modules; they are plain flags (no owner, no count, not released when a
  module ends). The scripts use them as mutexes around shared tables
  (`lock(einheitarray) ... unlock(einheitarray)`).
* `atomic_begin()` (304) sets KI+0x818 and records the current slot; until `atomic_end()`
  (305) every other module of the player is ticked with `paused = 1`: timers and semaphore
  waits still progress, but no instruction executes. 200 uses, always in pairs around a few
  statements.

### Saving

The whole KI state is saved and loaded with the game (CKIPlayer 0x43ddc0: queues, flags,
semaphores, tables, globals, then every slot's module 0x43efd0: code position, store,
stack, timers, gosub child). A remake needs to serialise the same.

## 5. Calling convention of natives

Dispatcher: `CKIPlayer::CallNative(id, stack, store, module)` at 0x43a250, `ecx` = the
CKIPlayer. `switch (id - 1)` over a 401-entry jump table at 0x43d2b8; 105 ids lead to the
default (do nothing), so **296 ids are implemented by 240 handlers** (several ids share a
handler, e.g. the four typed variants of the array natives).

* A handler pops its arguments with 0x463dc0 (first pop = last argument), calls a thin
  wrapper method of CKIManager (0x438xxx-0x439xxx, `ecx = 0x7d2c98`) or reads KI/module
  fields itself, and pushes at most one result with 0x463d40. Booleans are 0/1.
* The caller's player number (KI+0x828) is passed implicitly where a native acts "for
  me" (orders are issued in the KI player's name, searches are relative to it).
* Natives never block: orders are queued (see below) and the script polls or `wait`s.
  The only natives that affect scheduling are 40/41 (sleep), 221 (lock) and 304/305.
* Natives with "out" results (positions) store them in fields of the calling module that
  other natives read back (e.g. 135 then 293/294).
* Errors (unknown handle, bad index, array that cannot be resolved) make most getters
  push 0 or -1 (as listed per native); a few handlers (array natives with an unresolvable
  array, table natives with a bad index) return **without pushing**, which unbalances the
  stack - harmless in practice because the compiler pops results immediately.
* After every native the interpreter calls a debug hook (0x41ecc0, empty) if the KI's
  player is 7.

Unit and building orders go through the engine's order queue `0x80b278` (the same queue the
user interface and the network lockstep use: 0x455ea0/0x455ee0/0x455f20/0x455f60 build a
message `{u32 code, u32 size, u32 flags, u32 time, u32 args...}`, executed by 0x456450 after
the network latency of `[0x80e2bc]` ticks, 0x455cb0). So AI orders take effect with the same
delay and checks as a human player's and are deterministic in multiplayer. The executor checks
the object's kind but **not its owner**, and deducts costs without an affordability check.
See NATIVES.md for each order code.

## 6. Shared state between modules

All modules of one player share, through their CKIPlayer:

* 256 globals (219 `getglobal(i)`, 220 `setglobal(i, v)`). The scripts use fixed indices as
  named settings, e.g. 242/243 = home position x/y, 253 = skill level, 254 = nation-specific
  data, 150 = "running" flags; 100-ish are counters.
* 100 tables of 256 ints (233-236 set, 237-240 get, 241-244 remove-at, 245-248 insert-at; the
  four ids of each group are identical, typed per element type). Typical use: lists of x/y
  coordinates (`xvaluearray`, `yvaluearray` are table numbers) and unit lists
  (`einheitarray`) handed from one module to another.
* 256 semaphores (221-223) and the atomic flag (304/305).
* Two event queues filled by the engine: a unit of this player was damaged (0x418f90 ->
  0x42d0b0 -> 0x43dca0) and a building of this player was damaged (0x40c970 -> 0x42d070 ->
  0x43dcf0). Each holds up to 256 distinct handles (a handle already queued is not added
  again). 330/329 pop one into the module (true if there was one), 331/332 read it.

There is no messaging between modules beyond these, and no way to stop another module.

## 7. Object handles

Script values for units, buildings and neutral objects are 32-bit handles built by
0x4325f0: `list<<28 | (guid & 0xfff)<<16 | slot` from obj+0x10 (list), obj+0xc (type) and
obj+0x8 (slot). Lists: 0 neutral objects (animals, mines, ...), 1-8 the players' objects,
9 trees and other map objects, 10 wall segments (every wall, barricade and stockade piece,
whoever owns it: 0x427925 ... -> 0x42698e; so no search or count over a player's list sees
walls, only `nearest_wall`). 0x42b820(world, handle) maps a handle back to
the object: 0 if the slot is empty, holds another type, or the object is dying and no longer
shown. Natives then return their error value (0 or -1), and orders to such a handle do nothing;
0 is "no object". Natives 110-112 test whether a handle still resolves. Slots are reused only
after the list's next-fit cursor wraps, so handles are unique in practice. **When an object
changes owner (conversion, capture) it moves to the new owner's list and gets a new handle.**

Objects also carry a per-player "claimed by this AI" bitmask (obj+0x1c) that most searches use
to hand out each object to only one module at a time; see NATIVES.md, "Claims".

## 8. Reimplementation notes

* Keep 1 instruction per module per 20 ms of game time: the scripts' timing (polling loops
  without `wait`, the spacing between orders) depends on it. With the remake's 30 Hz `Sim`
  tick, accumulate simulated milliseconds and run one VM step per module for every 20 ms
  (1 or 2 steps per tick), and count sleep timers in ms.
* All arithmetic is 32-bit signed with C semantics: `/` truncates toward zero and divides by 1
  when the divisor is 0; `%` by 0 would crash the original (never happens in the files);
  comparisons and `&&`/`||`/`!` push 0/1 (no short-circuit: both operands are always
  evaluated).
* Random numbers (335) come from a 1000-entry table of CRT `rand()` values cycled by one
  counter shared by all players; `random(lo, hi)` gives lo..hi-1 and `random(a, a)` gives a-1
  (`multi_situation_analyser_*` does call `random(x, x)`). For determinism use the game's seeded RNG.
* Scripts poll a lot and clean up little (modules that wait forever for a dead unit's position,
  semaphores never released if a module dies in between); the 200-slot limit per player and
  "start fails silently when full" are part of the behaviour.
* Module ids live in two directories: base campaign modules in `kimodules/`, expansion ones
  in `kimodules2/`; the id sets do not overlap, so a loader can look in both.
* Unknown native ids must be no-ops that push nothing (as the default case does).

## Base game

The base game's `america.exe` is packed (one compressed `.code` section), so its VM was not
read. Its strings show the same loader (`kimodules/%08d.mod`, `KIMODULE`,
`kimodules/sources/`). Its 745 modules parse with the same format, use only the ten opcodes,
and every native id they call is implemented by the expansion's dispatcher with argument
counts that keep the stack balanced (`checkstack.py`: consistent depths in all 1311 files). The expansion VM can therefore run them, modulo the directory name.

## In the remake

* `KiManager` (one per campaign match) steps every people's `KiPlayer` once per 20 ms of
  game time (1 or 2 times per 30 Hz `Sim` step), like the original's 50 Hz loop.
* Handles are `owner << 24 | sim id`, so a unit that changes hands gets a new handle, as in
  the original. Claims are kept per sim id (`KiWorld.claims`).
* Orders are carried out at once through the units' and buildings' own methods (the original
  queues them with the network latency); they are game state like the rest of the step.
* The class and state bits are worked out from the remake's objects (`KiWorld.class_bits`,
  `state_bits`); some (wagon bits, special states, building abilities) are approximations.
* `random` draws from `Sim.rng` instead of the original's table of CRT values.
* A saved mission keeps the KI's modules, but units get new sim ids when a game is loaded,
  so handles held across a load stop working (open work).
