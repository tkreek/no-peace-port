#!/usr/bin/env python3
"""Static checker for the campaign missions: reads every campaign map's script (SPIELER,
AREA, ABLAUF), the AI modules it starts and the remake's data and code, and reports what
would break or look wrong in the remake, without running the game.

usage:
  check_missions.py                     markdown report of all 38 missions on stdout
  check_missions.py -o REPORT.md        ... into a file
  check_missions.py --json              the findings as JSON
  check_missions.py base/ind_03 ...     only these missions ("ind_03" means the base set's)
  check_missions.py --dump base/tut_01  the mission's players, areas and triggers, readable

What it checks (docs/technical/missions.md has the opcodes, docs/technical/ki.md the
modules):
  * references: areas missing from AREA (the whole map then), message texts missing from
    the set's text table, speech for action 9, AI modules (action 1, and every module those
    reach through gosub/spawn), player numbers that are not in SPIELER, out-of-range flags,
    timers and variables, unknown resources and object categories;
  * the natives the mission's modules call that game/scripts/game/ki/ki_natives.gd does not
    implement, or implements with another argument/result count than the original's
    (tools/ki/kinatives.py);
  * GUIDs the remake cannot count, spawn or create (no object type, not a unit, ...), and
    GUIDs a condition waits for that the player can never have;
  * the script's logic: flags, timers and variables tested but never set, triggers that can
    never fire, and whether a chain of triggers can reach the human player's WIN (and how
    LOSE can happen).

Reachability is an over-approximation: a trigger "may fire" when each of its conditions
can hold given what the triggers that may fire before it set up (flags, timers, variables,
the countdown, units they spawn) and what the players can have. A player can have a GUID
when the map places one for it, a trigger spawns/creates/converts one for it, or it can
train or build it: structures of its people whose prerequisites it can have, when it can
have a builder (BUILDERS); units of its people whose production building and
prerequisites it can have; mounted units when it can have the unit on foot. Only the
human and players a trigger starts an AI module for train or build. Counts are bounded by
placements and spawns when nothing else can make more.
"""
import argparse
import collections
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "formats"))
sys.path.insert(0, os.path.join(ROOT, "tools", "ki"))

from rd_chunks import read_chunks  # noqa: E402
import kimod  # noqa: E402
from kinatives import NATIVES  # noqa: E402

SETS = ["base", "expansion"]
PEOPLES = ["ind", "mex", "des", "usa"]
SEATS = {0: "none", 1: "human", 2: "computer", 3: "independent"}
ERROR, WARN, INFO = "ERROR", "WARN", "INFO"
SEVERITIES = [ERROR, WARN, INFO]


def gd_constants(rel, names):
    """Constants of the remake's GDScript file `rel` (literal ints, strings, lists and
    dictionaries, which read as Python), so the checker follows the game's own tables."""
    import ast
    src = open(os.path.join(ROOT, "game", "scripts", rel), encoding="utf-8").read()
    out = {}
    for name in names:
        m = re.search(r"^const %s := " % name, src, re.M)
        if not m:
            raise SystemExit("%s: no const %s" % (rel, name))
        at, depth, end = m.end(), 0, m.end()
        while True:  # the expression: up to the end of the line, brackets balanced
            c = src[end]
            depth += c in "[{(" and 1 or (c in "]})" and -1 or 0)
            if c == "\n" and depth == 0:
                break
            end += 1
        expr = re.sub(r"#[^\n]*", "", src[at:end])
        for k, v in sorted(out.items(), key=lambda kv: -len(kv[0])):
            expr = re.sub(r"\b%s\b" % k, repr(v), expr)
        out[name] = ast.literal_eval(expr.strip())
    return out


# The remake's limits and tables, read from its code.
_M = gd_constants("game/mission.gd", ["TIMERS", "FLAGS", "VARIABLES", "RESOURCES", "UNIT_RANGES", "BUILDING_RANGES",
                                      "SOLDIERS", "EITHER", "HORSE", "BUFFALO", "COW", "WILD_HORSE", "ANIMALS"])
FLAGS, TIMERS, VARIABLES, RESOURCES = _M["FLAGS"], _M["TIMERS"], _M["VARIABLES"], _M["RESOURCES"]
UNIT_RANGES, BUILDING_RANGES, SOLDIERS, EITHER = _M["UNIT_RANGES"], _M["BUILDING_RANGES"], _M["SOLDIERS"], _M["EITHER"]
HORSE, BUFFALO, COW, WILD_HORSE, ANIMALS = _M["HORSE"], _M["BUFFALO"], _M["COW"], _M["WILD_HORSE"], _M["ANIMALS"]
_P = gd_constants("world/objects/building_production.gd", ["HORSE_BUILDINGS", "COW_BUILDINGS"])
HORSE_BUILDINGS, COW_BUILDINGS = _P["HORSE_BUILDINGS"], _P["COW_BUILDINGS"]
EXPANSION_PRODUCTION = gd_constants("core/game_data.gd", ["EXPANSION_PRODUCTION"])["EXPANSION_PRODUCTION"]
# Who takes others' cows by coming close, and who steals transports (some need an upgrade
# first); transports are what UnitType.is_transport says: wagons, travois, stagecoaches.
HERDERS = gd_constants("world/units/unit_animal.gd", ["HERDERS"])["HERDERS"]
THIEVES = list(gd_constants("world/units/unit_work.gd", ["THIEVES"])["THIEVES"])
TRANSPORTS = [155, 255, 355, 455, 456]
FIELD = 149
FIELD_BUILDINGS = [108, 208, 408]  # granary, finca, farm
# Who puts up structures: the units with a building animation (UnitType.can_build).
BUILDERS = {"ind": [152, 153], "mex": [252], "des": [352], "usa": [452]}
CATEGORIES = {0: "all units", 1: "Native units", 2: "Mexican units", 3: "outlaw units",
              4: "American units", 5: "all buildings", 6: "Native buildings",
              7: "Mexican buildings", 8: "outlaw buildings", 9: "American buildings",
              16: "all soldiers", 17: "Native soldiers", 18: "Mexican soldiers",
              19: "outlaw soldiers", 20: "American soldiers"}

COND = {  # opcode: (name, parameter names)
    1: ("always", []),
    2: ("stock >=", ["player", "amount", "resource"]),
    3: ("exactly n in area", ["player", "n", "type", "area"]),
    4: ("countdown below", ["seconds"]),
    5: ("flag set", ["flag"]),
    6: ("sees area", ["player", "area"]),
    7: ("fewer than", ["player", "n", "type"]),
    8: ("more than", ["player", "n", "type"]),
    9: ("fewer than", ["player", "n", "type"]),
    10: ("more than", ["player", "n", "type"]),
    11: ("exactly n in area", ["player", "n", "type", "area"]),
    12: ("stock <", ["player", "amount", "resource"]),
    13: ("more than n in area", ["player", "n", "type", "area"]),
    14: ("fewer than n in area", ["player", "n", "type", "area"]),
    15: ("OR (any from here)", []),
    16: ("timer ran out", ["timer"]),
    17: ("variable ==", ["variable", "value"]),
    18: ("flag clear", ["flag"]),
}
ACT = {
    1: ("start AI module", ["player", "module"]),
    2: ("camera to area", ["player", "area"]),
    3: ("spawn", ["player", "n", "type", "area"]),
    4: ("LOSE", ["player"]),
    5: ("message", ["text", "player", "seconds"]),
    6: ("remove", ["player", "type", "area"]),
    7: ("nothing", []),
    8: ("nothing", []),
    9: ("spoken message", ["text"]),
    10: ("stay armed", []),
    11: ("start countdown", ["seconds"]),
    12: ("set flag", ["flag"]),
    13: ("WIN", ["player"]),
    14: ("neutral object", ["type", "x", "y"]),
    15: ("show clock", []),
    16: ("hide clock", []),
    17: ("pause world", ["seconds"]),
    18: ("lock input", []),
    19: ("unlock input", []),
    20: ("uncover area", ["player", "area"]),
    21: ("add resources", ["player", "amount", "resource"]),
    22: ("take resources", ["player", "amount", "resource"]),
    23: ("clear flag", ["flag"]),
    24: ("cover area", ["player", "area"]),
    25: ("start timer", ["timer", "seconds"]),
    26: ("stop timer", ["timer"]),
    27: ("mission goals", ["text"]),
    28: ("share sight", ["player", "player"]),
    29: ("stop sharing sight", ["player", "player"]),
    30: ("ally", ["player", "player"]),
    31: ("war", ["player", "player"]),
    32: ("neutral", ["player", "player"]),
    33: ("random variable", ["variable", "below"]),
    34: ("remove", ["player", "type", "area"]),
    35: ("convert", ["type", "area", "player"]),
    36: ("create", ["type", "x", "y", "player"]),
}
COUNT_CONDS = {3, 7, 8, 9, 10, 11, 13, 14}


def p(item, i):
    """Parameter i (1-based) of a condition/action, 0 when missing (as mission.gd's _param)."""
    return item[i] if i < len(item) else 0


# ------------------------------------------------------------------------------- data

class Data:
    """The remake's tables: texts, object types, GUIDs, stats, the native implementation."""

    def __init__(self, assets):
        self.assets = assets
        load = lambda rel: json.load(open(os.path.join(assets, rel), encoding="utf-8"))
        self.campaign = load("data/campaign.json")
        self.names = {int(k): v for k, v in load("data/texts.json").items() if k.isdigit()}
        self.type_guid = {int(k): int(v) for k, v in load("data/guids.json").items()}
        self.types = {t["id"]: t for t in load("data/object_types.json")}
        self.guid_types = collections.defaultdict(list)  # GUID -> object types with art
        for tid, guid in self.type_guid.items():
            t = self.types.get(tid)
            if t and t.get("anims"):
                self.guid_types[guid].append(t)
        self.stats = self._stats(load("data/defaults.json"))
        self.natives = NativeImpl(os.path.join(ROOT, "game", "scripts", "game", "ki", "ki_natives.gd"))

    def _stats(self, defaults):
        """GameData._load_tables in short: the manual's stats, the editor's kinds and factions,
        the expansion manual, production places for mounted units and expansion units."""
        stats = {int(k): dict(v) for k, v in json.load(open(os.path.join(ROOT, "game", "data", "stats.json"))).items()}
        for k, v in defaults.items():
            g = int(k)
            if v.get("kind") in ("unit", "hero", "structure"):
                st = stats.setdefault(g, {})
                st["kind"] = v["kind"]
                st["faction"] = v.get("faction", "")
                st["name"] = self.names.get(g, st.get("name", v.get("name_de", "")))
        manual = json.load(open(os.path.join(ROOT, "game", "data", "expansion_manual.json")))
        for k, v in manual.items():
            if k.isdigit():
                stats.setdefault(int(k), {}).update(v)
        for g, at in EXPANSION_PRODUCTION.items():
            if g in stats:
                stats[g]["produced_at"] = at
        by_name = {(s.get("faction"), s.get("name", "").lower()): g for g, s in stats.items() if s.get("kind") == "unit"}
        self.foot_of = {}
        for g, s in stats.items():
            name = s.get("name", "")
            if s.get("kind") == "unit" and name.startswith("Mounted "):
                foot = by_name.get((s.get("faction"), name[8:].lower()))
                if foot is not None:
                    self.foot_of[g] = foot
                    if "produced_at" not in s and "produced_at" in stats[foot]:
                        s["produced_at"] = stats[foot]["produced_at"]
        # prerequisites by name, as GameData.prerequisites does
        key = lambda n: re.sub("[^a-z]", "", n.lower())
        for g, s in stats.items():
            wanted = [key(r) for r in s.get("prerequisites", "").split(",") if r.strip()]
            pre = []
            for w in wanted:
                for o, c in stats.items():
                    if c.get("faction") == s.get("faction") and c.get("kind") == "structure" and key(c.get("name", "")) == w:
                        pre.append(o)
                        break
                else:
                    pre.append(None)  # a name nothing matches: the remake skips it
            s["prereq_guids"] = [x for x in pre if x is not None]
        return stats

    def name(self, guid):
        if guid < 100:
            return CATEGORIES.get(guid, "category %d?" % guid)
        if guid in EITHER:
            return "%s (foot or mounted)" % self.name(EITHER[guid][0])
        if guid == WILD_HORSE:
            return "wild horse"
        n = self.stats.get(guid, {}).get("name")
        if not n and self.guid_types.get(guid):
            n = self.guid_types[guid][0]["name"]
        return n or "GUID %d (unknown)" % guid

    def is_unit_type(self, guid):
        return any(t["kind"] == 1 for t in self.guid_types.get(guid, []))

    def texts(self, set_name):
        return self.campaign[set_name]["texts"]


class NativeImpl:
    """What KiNatives.call_native does with each id, parsed from ki_natives.gd: ARGS (how
    many it pops), CONSTANTS (pushes a number), and the match arms (with or without a push,
    or a stub that does nothing / pushes 0)."""

    def __init__(self, path):
        src = open(path, encoding="utf-8").read()
        self.args = {int(a): int(b) for a, b in re.findall(r"(\d+): (\d+)", self._block(src, "const ARGS := {"))}
        self.constants = {int(a) for a, _ in re.findall(r"(\d+): (0x[0-9a-f]+|\d+)", self._block(src, "const CONSTANTS := {"))}
        self.arms = {}  # id -> body text
        body = src[src.index("\tmatch id:"):]
        body = body[:body.index("\n\n\n")]
        current = None
        for line in body.splitlines()[1:]:
            m = re.match(r"^\t\t(\d+(?:, \d+)*):(.*)$", line)
            if m:
                current = [int(x) for x in m.group(1).split(", ")]
                for i in current:
                    self.arms[i] = m.group(2)
            elif line.startswith("\t\t\t") and current:
                for i in current:
                    self.arms[i] += "\n" + line
            elif line.startswith("\t\t#"):
                current = None

    @staticmethod
    def _block(src, start):
        at = src.index(start)
        return src[at + len(start):src.index("}", at)]

    def classify(self, nid):
        """(severity or None, what): how the remake runs native `nid` against the original."""
        orig = NATIVES.get(nid)
        pops = self.args.get(nid, 0)
        if nid in self.constants:
            if orig and (orig[1] != 0 or orig[2] != 1):
                return ERROR, "a constant in the remake, but the original pops %d and pushes %d" % (orig[1], orig[2])
            return None, "constant"
        if orig is None:
            return INFO, "not a native of the original (does nothing there either)"
        name, na, nr = orig[0], orig[1], orig[2]
        if nid not in self.arms:
            if pops != na or nr:
                return ERROR, "not implemented: pops %d and pushes nothing, the original pops %d and pushes %d (stack out of step)" % (pops, na, nr)
            return WARN, "not implemented (pops its %d argument(s), does nothing)" % na
        arm = self.arms[nid]
        pushes = "task.push(" in arm
        if pops != na:
            return ERROR, "pops %d, the original %d (stack out of step)" % (pops, na)
        if nr and not pushes:
            return ERROR, "pushes nothing, the original pushes %d (stack out of step)" % nr
        if not nr and pushes:
            return ERROR, "pushes a result the original does not"
        stripped = re.sub(r"\s+", " ", arm).strip()
        if stripped.startswith("pass") or stripped == "task.push(0)":
            return INFO, "a stub (%s)" % stripped.split("#")[0].strip()
        return None, "implemented"


class Original:
    """The original game's files (original/, gitignored), when present: only to tell a
    problem the remake's asset build made from one the original game has as well."""
    TEXTS = {"base": "extracted/america2/global/guids/text2.eng",
             "expansion": "expansion/extracted/america7/global/guids2/text2-Add-on.eng"}
    MODULES = {"base": "extracted/america3/kimodules", "expansion": "expansion/extracted/america8/kimodules2"}

    def __init__(self, folder):
        self.folder = folder
        self.texts = {}  # set -> {id: [line numbers]}
        for set_name, rel in self.TEXTS.items():
            path = os.path.join(folder, rel)
            if not os.path.exists(path):
                continue
            ids = collections.defaultdict(list)
            for n, line in enumerate(open(path, encoding="latin1"), 1):
                k = line.split("=", 1)[0].strip()
                if "=" in line and k.isdigit():
                    ids[int(k)].append(n)
            self.texts[set_name] = ids

    def has_module(self, number):
        """True/False, or None when the original's modules are not there."""
        found = None
        for rel in self.MODULES.values():
            d = os.path.join(self.folder, rel)
            if os.path.isdir(d):
                found = found or os.path.exists(os.path.join(d, "%08d.mod" % number))
        return found

    def text_note(self, set_name, tid):
        """Where the original stands on a text id the remake's table lacks."""
        ids = self.texts.get(set_name)
        if ids is None:
            return ERROR, ""
        if tid in ids:
            return ERROR, " (the original's %s has it: the asset build lost it)" % os.path.basename(self.TEXTS[set_name])
        hint = ""
        for other, lines in ids.items():
            if len(lines) > 1 and abs(other - tid) <= 2:
                hint = "; it lists id %d twice (lines %s), probably one of them was meant to be %d" % (
                    other, ", ".join(map(str, lines)), tid)
        return WARN, " (missing from the original's %s too: the original shows an empty message%s)" % (
            os.path.basename(self.TEXTS[set_name]), hint)


# ------------------------------------------------------------------------------- maps

class Trigger:
    def __init__(self, index):
        self.index = index
        self.name = ""
        self.conditions = []  # [opcode, params...]
        self.actions = []


class Mission:
    def __init__(self, data, set_name, entry):
        self.data = data
        self.set = set_name
        self.code = entry["code"]
        self.id = "%s/%s" % (set_name, self.code)
        self.title = entry.get("title", "")
        self.path = os.path.join(data.assets, entry["map"])
        self.chunks = {}
        for name, body in read_chunks(self.path):
            self.chunks.setdefault(name.split("\0")[0], body)
        self.players = self._players(self.chunks.get("SPIELER", b""))
        self.areas = self._areas(self.chunks.get("AREA", b""))
        self.triggers = self._script(self.chunks.get("ABLAUF", b""))
        self.placements = self._placements(self.chunks.get("BOBLISTE", b""))
        info = self.chunks.get("LVL_INFO", b"")
        self.size = (struct.unpack_from("<I", info, 0x114)[0] * 32, struct.unpack_from("<I", info, 0x118)[0] * 32) if len(info) >= 0x11C else (0, 0)
        self.biome = "wiese" if any(data.types.get(t, {}).get("name", "").endswith("_meadow") for _, _, t, _ in self.placements) else "steppe"
        humans = [q for q in self.players.values() if q["control"] == 1]
        self.human = humans[0]["index"] if humans else None
        self.humans = humans

    @staticmethod
    def _players(b):
        out = {}
        for slot in range(len(b) // 300):
            at = slot * 300
            index, people = struct.unpack_from("<i", b, at)[0], struct.unpack_from("<i", b, at + 0x10C)[0]
            if people < 0 or not 1 <= index <= 8:
                continue
            name = b[at + 12:at + 0x10C].split(b"\0")[0].decode("latin1")
            control, allies = struct.unpack_from("<ii", b, at + 0x110)
            out[index] = {"index": index, "slot": slot, "name": name, "people": PEOPLES[people] if people < 4 else "usa",
                          "control": control, "allies": allies}
        return out

    @staticmethod
    def _areas(b):
        out = {}
        if len(b) < 4:
            return out
        at = 4
        for _ in range(struct.unpack_from("<I", b)[0]):
            if at + 24 > len(b):
                break
            aid, left, top, right, bottom, length = struct.unpack_from("<6i", b, at)
            out[aid] = {"rect": (left, top, right, bottom), "name": b[at + 24:at + 24 + length].split(b"\0")[0].decode("latin1")}
            at += 24 + length
        return out

    @staticmethod
    def _script(b):
        triggers = []
        if len(b) < 4:
            return triggers
        at = 4
        for t in range(struct.unpack_from("<I", b)[0]):
            trig = Trigger(t)
            items = struct.unpack_from("<i", b, at)[0]
            at += 4
            for _ in range(items):
                op, kind = struct.unpack_from("<ii", b, at)
                at += 8
                if kind == 2:
                    length = struct.unpack_from("<i", b, at)[0]
                    trig.name = " ".join(b[at + 4:at + 4 + length].split(b"\0")[0].decode("latin1").split())
                    at += 4 + length
                    continue
                count = struct.unpack_from("<i", b, at)[0]
                item = [op] + list(struct.unpack_from("<%di" % count, b, at + 4))
                at += 4 + 4 * count
                (trig.conditions if kind == 1 else trig.actions).append(item)
            triggers.append(trig)
        return triggers

    def _placements(self, b):
        """BOBLISTE: (x, y, type id, owner) of every object with a GUID."""
        out = []
        if len(b) < 4:
            return out
        for i in range(struct.unpack_from("<I", b)[0]):
            o = 4 + i * 24
            if o + 24 > len(b):
                break
            x, y, tid, owner = struct.unpack_from("<4I", b, o)
            out.append((x, y, tid, owner))
        return out

    def area_text(self, aid):
        a = self.areas.get(aid)
        return "area %d %r" % (aid, a["name"]) if a else "area %d (MISSING: whole map)" % aid

    def text(self, tid, width=70):
        t = self.data.texts(self.set).get(str(tid))
        if t is None:
            return "text %d MISSING" % tid
        t = t.replace("@", " / ").replace("#", " ").strip()
        return "text %d %r" % (tid, t if len(t) <= width else t[:width - 3] + "...")

    def player_text(self, n):
        q = self.players.get(n)
        if not q:
            return "player %d (not in SPIELER)" % n
        return "player %d (%s %s)" % (n, q["people"], SEATS.get(q["control"], "?"))

    def describe(self, item, is_action):
        op = item[0]
        table = ACT if is_action else COND
        name, params = table.get(op, ("UNKNOWN %d" % op, []))
        parts = []
        for i, pname in enumerate(params, 1):
            v = p(item, i)
            if pname == "player":
                parts.append(self.player_text(v))
            elif pname == "type":
                parts.append("%d %s" % (v, self.data.name(v)))
            elif pname == "area":
                parts.append(self.area_text(v))
            elif pname == "text":
                parts.append(self.text(v))
            elif pname == "resource":
                parts.append(RESOURCES.get(v, "resource %d?" % v))
            elif pname == "module":
                parts.append("%08d.mod" % v)
            else:
                parts.append("%s %d" % (pname, v))
        extra = item[1 + len(params):]
        if extra:
            parts.append("extra %s" % extra)
        return "%s(%s)" % (name, ", ".join(parts))


# ------------------------------------------------------------------------------- modules

class Modules:
    """The AI modules as the remake finds them (KiModule.load: the base set's folder first,
    then the expansion's)."""

    def __init__(self, assets):
        self.folders = {s: os.path.join(assets, "campaign", s, "ai") for s in SETS}
        self.cache = {}

    def path(self, number, set_name=None):
        for s in ([set_name] if set_name else SETS):
            f = os.path.join(self.folders[s], "%08d.mod" % number)
            if os.path.exists(f):
                return f
        return None

    def load(self, number):
        """(module or None, error text or None) for the module the remake would load."""
        if number not in self.cache:
            f = self.path(number)
            if f is None:
                self.cache[number] = (None, "missing")
            else:
                try:
                    self.cache[number] = (kimod.load(f), None)
                except Exception as e:  # noqa: BLE001
                    self.cache[number] = (None, "does not parse: %s" % e)
        return self.cache[number]

    def closure(self, roots):
        """Every module reachable from `roots` through gosub (5) and spawn (6):
        {number: (module or None, error, set of modules that call it)}."""
        seen = {}
        todo = [(r, None) for r in roots]
        while todo:
            n, parent = todo.pop()
            if n in seen:
                if parent is not None:
                    seen[n][2].add(parent)
                continue
            mod, err = self.load(n)
            seen[n] = (mod, err, set() if parent is None else {parent})
            if mod:
                for w in mod.code:
                    if w >> 28 in (5, 6):
                        todo.append((w & 0x0FFFFFFF, n))
        return seen


# ------------------------------------------------------------------------------- checks

class Report:
    def __init__(self, mission):
        self.mission = mission
        self.findings = []
        self.sections = collections.OrderedDict()  # extra readable blocks for the report

    def add(self, severity, code, message, trigger=None):
        self.findings.append({"severity": severity, "code": code, "message": message, "trigger": trigger})

    def count(self, severity):
        return sum(1 for f in self.findings if f["severity"] == severity)


def matches(guid, what):
    """mission.gd matches(): whether an object of `guid` counts as `what`."""
    if what >= 100:
        return guid == what or guid in EITHER.get(what, [])
    if what == 0:
        return any(a <= guid < b for a, b in UNIT_RANGES)
    if 1 <= what <= 4:
        a, b = UNIT_RANGES[what - 1]
        return a <= guid < b
    if what == 5:
        return any(a <= guid < b for a, b in BUILDING_RANGES)
    if 6 <= what <= 9:
        a, b = BUILDING_RANGES[what - 6]
        return a <= guid < b
    if what == 16:
        return any(guid in s for s in SOLDIERS)
    if 17 <= what <= 20:
        return guid in SOLDIERS[what - 17]
    return False


def counts_as(guid, what):
    """matches(), with the animals counted by kind (unit_matches)."""
    if what in (HORSE, WILD_HORSE):
        return guid in (HORSE, WILD_HORSE)
    if what in (COW, BUFFALO):
        return guid == what
    return matches(guid, what)


class Checker:
    def __init__(self, data, modules, mission, original):
        self.original = original
        self.d = data
        self.mods = modules
        self.m = mission
        self.r = Report(mission)

    # -------------------------------------------------------------- references

    def check(self):
        m = self.m
        if not m.triggers:
            self.r.add(ERROR, "no-script", "the map has no ABLAUF triggers")
            return self.r
        if len(m.humans) != 1:
            self.r.add(ERROR, "human", "%d human players in SPIELER (expected 1)" % len(m.humans))
        self.check_references()
        self.check_modules()
        self.check_guids()
        self.check_repeats()
        self.check_logic()
        return self.r

    def check_references(self):
        m, d, r = self.m, self.d, self.r
        texts = d.texts(m.set)
        for tid in (1, 2):
            if str(tid) not in texts:
                r.add(WARN, "text", "text %d (the won/lost banner) missing from the %s texts" % (tid, m.set))
        missing_areas = collections.defaultdict(list)
        missing_texts = collections.defaultdict(list)
        missing_speech = collections.defaultdict(list)
        bad_players = collections.defaultdict(lambda: ([], set()))
        silent = []
        speech_dir = os.path.join(d.assets, "campaign", "base", "speech")
        for t in m.triggers:
            items = [(c, False) for c in t.conditions] + [(a, True) for a in t.actions]
            for item, is_action in items:
                op = item[0]
                table = ACT if is_action else COND
                if op not in table:
                    r.add(ERROR, "opcode", "unknown %s %d: %s" % ("action" if is_action else "condition", op, item), t.index)
                    continue
                params = table[op][1]
                if len(item) - 1 < len(params):
                    r.add(WARN, "params", "%s has %d parameters, %d expected (missing ones read as 0)"
                          % (m.describe(item, is_action), len(item) - 1, len(params)), t.index)
                for i, pname in enumerate(params, 1):
                    v = p(item, i)
                    if pname == "area" and v not in m.areas:
                        missing_areas[v].append(t.index)
                    elif pname == "text" and str(v) not in texts:
                        missing_texts[v].append(t.index)
                    elif pname == "player" and v not in m.players:
                        bad_players[v][0].append(t.index)
                        bad_players[v][1].add(self.unknown_player_use(item, is_action))
                    elif pname == "resource" and v not in RESOURCES:
                        r.add(ERROR, "resource", "%s: resource %d is not one the remake knows (reads/changes nothing)"
                              % (m.describe(item, is_action), v), t.index)
                    elif pname == "flag" and not 0 <= v < FLAGS:
                        r.add(ERROR, "range", "flag %d out of range 0..%d (ignored)" % (v, FLAGS - 1), t.index)
                    elif pname == "timer" and not 0 <= v < TIMERS:
                        r.add(ERROR, "range", "timer %d out of range 0..%d (ignored)" % (v, TIMERS - 1), t.index)
                    elif pname == "variable" and not 0 <= v < VARIABLES:
                        r.add(ERROR, "range", "variable %d out of range 0..%d (ignored)" % (v, VARIABLES - 1), t.index)
                if is_action and op == 9:
                    if m.set == "base":
                        if not os.path.exists(os.path.join(speech_dir, "%03d.mp3" % p(item, 1))):
                            missing_speech[p(item, 1)].append(t.index)
                    else:
                        silent.append(p(item, 1))
                if is_action and op == 5 and m.human is not None and p(item, 2) != m.human:
                    r.add(INFO, "message-other", "%s is for another player: the human never sees it"
                          % m.describe(item, True), t.index)
                if is_action and op == 14 and not (0 <= p(item, 2) < m.size[0] and 0 <= p(item, 3) < m.size[1]):
                    r.add(WARN, "spot", "%s: the spot is off the %dx%d map" % (m.describe(item, True), *m.size), t.index)
                if is_action and op == 36 and not (0 <= p(item, 2) < m.size[0] and 0 <= p(item, 3) < m.size[1]):
                    r.add(WARN, "spot", "%s: the spot is off the %dx%d map" % (m.describe(item, True), *m.size), t.index)
        for aid, a in sorted(m.areas.items()):
            left, top, right, bottom = a["rect"]
            if right <= left or bottom <= top:
                r.add(WARN, "area", "area %d %r is empty (%s): Mission.count and remove treat it as the whole map" % (aid, a["name"], a["rect"]))
        for aid, ts in sorted(missing_areas.items()):
            r.add(WARN, "area", "area %d is not in AREA (%d areas defined): the whole map is used (triggers %s)"
                  % (aid, len(m.areas), _list(ts)))
        for tid, ts in sorted(missing_texts.items()):
            sev, note = self.original.text_note(m.set, tid)
            r.add(sev, "text", "text %d is missing from the %s texts: an empty message (triggers %s)%s" % (tid, m.set, _list(ts), note))
        for tid, ts in sorted(missing_speech.items()):
            orig = os.path.exists(os.path.join(ROOT, "original", "extracted", "america1", "SFX", "Missions", "%03d.mp3" % tid))
            r.add(WARN if orig else INFO, "speech",
                  "speech %03d.mp3 for action 9 is not in campaign/base/speech%s: the message shows silently for the default time (triggers %s)"
                  % (tid, " (the original has it: the asset build missed it)" if orig else " (nor in the original)", _list(ts)))
        if silent:
            r.add(INFO, "speech", "%d spoken messages (action 9) have no recording in the expansion set: shown silently" % len(silent))
        for n, (ts, uses) in sorted(bad_players.items()):
            harmless = uses <= {"spawn an animal (nobody's anyway)"}
            r.add(INFO if harmless or n == 0 else WARN, "player", "player %d is not in SPIELER: %s (triggers %s)"
                  % (n, "; ".join(sorted(uses)), _list(ts)))

    @staticmethod
    def unknown_player_use(item, is_action):
        """What an action or condition does with a player that is not in SPIELER."""
        op = item[0]
        if not is_action:
            return "a condition about it (it never has anything)"
        if op == 3 and p(item, 3) in (BUFFALO, COW, WILD_HORSE):
            return "spawn an animal (nobody's anyway)"
        if op == 1:
            return "an AI module for it, which the remake does not start (KiManager has no such player)"
        return "%s for it" % ACT.get(op, ("action %d" % op,))[0]

    # -------------------------------------------------------------- modules

    def check_modules(self):
        m, r = self.m, self.r
        starts = [(t.index, p(a, 1), p(a, 2)) for t in m.triggers for a in t.actions if a[0] == 1]
        self.module_players = collections.defaultdict(set)
        for ti, player, num in starts:
            self.module_players[player].add(num)
            q = m.players.get(player)
            if q and q["control"] == 3:
                r.add(INFO, "module-independent", "module %08d runs for independent player %d" % (num, player), ti)
        closure = self.mods.closure(sorted({n for _, _, n in starts}))
        self.closure = closure
        root_of = {}
        for ti, player, num in starts:
            root_of.setdefault(num, []).append(ti)
        calls = collections.Counter()
        for num, (mod, err, parents) in sorted(closure.items()):
            where = ("started by triggers %s" % _list(root_of[num])) if num in root_of else ("called from %s" % ", ".join("%08d" % x for x in sorted(parents)))
            if err:
                there = self.original.has_module(num) if err == "missing" else True
                if there is False:
                    r.add(WARN, "module", "AI module %08d missing (%s); the original game does not have it either, so that player runs nothing there too" % (num, where))
                else:
                    r.add(ERROR, "module", "AI module %08d %s (%s)%s" % (num, err, where, " (the original has it)" if there else ""))
                continue
            own = self.mods.path(num, m.set)
            used = self.mods.path(num)
            if own is None:
                r.add(WARN, "module-set", "AI module %08d is not in the %s set's folder; the remake takes %s (%s)"
                      % (num, m.set, os.path.relpath(used, self.d.assets), where))
            elif own != used and open(own, "rb").read() != open(used, "rb").read():
                r.add(ERROR, "module-set", "AI module %08d exists in both sets and differs: the remake loads the %s one for this %s mission (%s)"
                      % (num, "base" if "base" in used else "expansion", m.set, where))
            for w in mod.code:
                if w >> 28 == 4:
                    calls[w & 0x0FFFFFFF] += 1
        self.native_calls = calls
        bad = collections.defaultdict(list)
        for nid, n in sorted(calls.items()):
            sev, what = self.d.natives.classify(nid)
            if sev:
                bad[sev].append((nid, n, what))
        self.stubs = {}
        for sev, items in bad.items():
            for nid, n, what in items:
                name = NATIVES.get(nid, ("native_%d" % nid,))[0]
                if sev == INFO:  # stubs: listed once for all missions (check_tables)
                    self.stubs[nid] = n
                    continue
                r.add(sev, "native", "native %d %s (%d calls in %d modules): %s" % (nid, name, n, self._modules_calling(nid), what))
        human = [(ti, num) for ti, player, num in starts if m.players.get(player, {}).get("control") == 1]
        if human:
            r.add(INFO, "module-human", "AI modules run for the human player (scripted scenes): %s"
                  % ", ".join("%08d (t%d)" % (num, ti) for ti, num in human))
        r.sections["modules"] = "%d modules started (%s), %d reachable, %d native calls" % (
            len(root_of), ", ".join("%08d for player %s" % (n, ",".join(str(pp) for _, pp, nn in starts if nn == n)) for n in sorted(root_of)),
            len(closure), sum(calls.values()))

    def _modules_calling(self, nid):
        return sum(1 for mod, err, _ in self.closure.values() if mod and any(w == (4 << 28 | nid) for w in mod.code))

    # -------------------------------------------------------------- GUIDs

    def guid_problem(self, guid, use):
        """Why the remake cannot do `use` ('count', 'spawn', 'remove', 'convert', 'create')
        with `guid`, or None."""
        d = self.d
        if guid < 100:
            if guid not in CATEGORIES:
                return "category %d is not one the remake knows: matches nothing" % guid
            if use in ("spawn", "create"):
                return "a category, not an object type: nothing is made"
            return None
        if guid in EITHER:
            if use in ("spawn", "create"):
                return "a foot-or-mounted GUID: no object type, nothing is made"
            return None
        if guid in ANIMALS:
            return None
        if guid not in d.guid_types:
            return "no object type with art has this GUID (guids.json/object_types.json): %s" % (
                "matches nothing" if use in ("count", "remove", "convert") else "nothing is made")
        if use == "spawn" and not d.is_unit_type(guid):
            return "not a unit: the spawn action builds a unit from a building's art"
        if use == "create":
            kinds = {t["kind"] for t in d.guid_types[guid]}
            if not kinds & {1, 2}:
                return "neither a unit nor a building (object kind %s)" % sorted(kinds)
        return None

    def check_guids(self):
        m, r = self.m, self.r
        uses = {3: "spawn", 6: "remove", 34: "remove", 14: "create", 35: "convert", 36: "create"}
        guid_param = {3: 3, 6: 2, 34: 2, 14: 1, 35: 1, 36: 1}
        for t in m.triggers:
            for c in t.conditions:
                if c[0] in COUNT_CONDS:
                    why = self.guid_problem(p(c, 3), "count")
                    if why:
                        r.add(ERROR, "guid", "%s: %s" % (m.describe(c, False), why), t.index)
            for a in t.actions:
                if a[0] in uses:
                    g = p(a, guid_param[a[0]])
                    why = self.guid_problem(g, uses[a[0]])
                    if why:
                        r.add(ERROR, "guid", "%s: %s" % (m.describe(a, True), why), t.index)
                    elif a[0] in (14, 36) and g >= 100 and g not in ANIMALS and not self.d.is_unit_type(g):
                        meadow = [x["name"].endswith("_meadow") for x in self.d.guid_types.get(g, [])]
                        if meadow and (m.biome == "wiese") not in meadow:
                            r.add(INFO, "biome", "%s: no %s variant, the remake uses another biome's art"
                                  % (m.describe(a, True), "meadow" if m.biome == "wiese" else "prairie"), t.index)
        unknown = collections.Counter()
        for _, _, tid, owner in m.placements:
            if tid not in self.d.type_guid and owner:
                unknown[tid] += 1
        for tid, n in unknown.items():
            r.add(INFO, "placement", "%d placed objects of type %d owned by a player have no GUID (not counted by the script)" % (n, tid))

    # -------------------------------------------------------------- triggers that stay armed

    def check_repeats(self):
        """Triggers that stay armed (action 10) fire at every check while their conditions
        hold, that is every (number of armed triggers) x 20 ms."""
        m, r = self.m, self.r
        every = len(m.triggers) * 0.02
        for t in m.triggers:
            if not any(a[0] == 10 for a in t.actions):
                continue
            timed = any(c[0] in (16, 4) for c in t.conditions) or any(a[0] in (23, 26) for a in t.actions)
            for a in t.actions:
                if a[0] == 1 and not timed:
                    r.add(WARN, "repeat-module", "stays armed and starts AI module %08d for player %d again at every check while "
                          "its conditions hold (up to every %.2f s): copies pile up in the player's 200 module slots, and the "
                          "remake's Mission.started_modules (saved with the game) grows by one each time" % (p(a, 2), p(a, 1), every), t.index)
                if a[0] == 3 and not timed:
                    pl, g = p(a, 1), p(a, 3)
                    limited = any(c[0] in (7, 9, 14) and p(c, 1) == pl and (counts_as(g, p(c, 3)) or p(c, 3) == g)
                                  for c in t.conditions)
                    if not limited:
                        r.add(WARN, "repeat-spawn", "stays armed and %s at every check while its conditions hold (up to every %.2f s), "
                              "and no condition counts what it spawns" % (m.describe(a, True), every), t.index)

    # -------------------------------------------------------------- logic

    def initial_have(self):
        """player -> {guid: count} from the map's placements (0: nobody's)."""
        have = collections.defaultdict(collections.Counter)
        for x, y, tid, owner in self.m.placements:
            g = self.d.type_guid.get(tid)
            if g is not None:
                have[owner][g] += 1
        return have

    def production(self, player, have):
        """GUIDs `player` can train or build given the GUIDs in `have` (fixed point)."""
        q = self.m.players.get(player)
        if not q:
            return set()
        people = q["people"]
        st = self.d.stats
        got = set(have)
        made = set()
        changed = True
        while changed:
            changed = False
            builder = any(b in got for b in BUILDERS.get(people, []))
            for g, s in st.items():
                if g in made:
                    continue
                ok = False
                if g == FIELD:  # every people's farm building allows fields
                    ok = builder and any(b in got for b in FIELD_BUILDINGS)
                elif s.get("faction") != people:
                    continue
                elif s.get("kind") == "structure":
                    ok = builder and all(x in got for x in s["prereq_guids"])
                elif s.get("kind") == "unit":
                    if g in self.d.foot_of:
                        ok = self.d.foot_of[g] in got
                    else:
                        ok = s.get("produced_at") in got and all(x in got for x in s["prereq_guids"])
                if ok:
                    made.add(g)
                    got.add(g)
                    changed = True
            for animal, places in ((HORSE, HORSE_BUILDINGS), (COW, COW_BUILDINGS)):
                if animal not in made and any(b in got for b in places):
                    made.add(animal)
                    got.add(animal)
                    changed = True
        return made

    def check_logic(self):
        m, d, r = self.m, self.d, self.r
        trig = m.triggers
        placed = self.initial_have()
        producers = {pl for pl, q in m.players.items() if q["control"] == 1} | set(self.module_players)

        # what each trigger needs and does
        sets_flag, clears_flag, starts_timer, assigns_var = (collections.defaultdict(list) for _ in range(4))
        tests_flag, tests_clear, tests_timer, tests_var = (collections.defaultdict(list) for _ in range(4))
        countdown_starts, countdown_tests = [], []
        for t in trig:
            for a in t.actions:
                op = a[0]
                if op == 12:
                    sets_flag[p(a, 1)].append(t.index)
                elif op == 23:
                    clears_flag[p(a, 1)].append(t.index)
                elif op == 25:
                    starts_timer[p(a, 1)].append(t.index)
                elif op == 33:
                    assigns_var[p(a, 1)].append((t.index, p(a, 2)))
                elif op == 11:
                    countdown_starts.append(t.index)
            for c in t.conditions:
                op = c[0]
                if op == 5:
                    tests_flag[p(c, 1)].append(t.index)
                elif op == 18:
                    tests_clear[p(c, 1)].append(t.index)
                elif op == 16:
                    tests_timer[p(c, 1)].append(t.index)
                elif op == 17:
                    tests_var[p(c, 1)].append((t.index, p(c, 2)))
                elif op == 4:
                    countdown_tests.append(t.index)
        for f, ts in sorted(tests_flag.items()):
            if f not in sets_flag:
                r.add(WARN, "flag", "flag %d is tested (set) but no trigger sets it (triggers %s never fire)" % (f, _list(ts)))
        for f, ts in sorted(sets_flag.items()):
            if f not in tests_flag and f not in tests_clear:
                r.add(INFO, "flag-unused", "flag %d is set (triggers %s) but never tested" % (f, _list(ts)))
        for f, ts in sorted(tests_clear.items()):
            if f not in sets_flag:
                r.add(INFO, "flag", "flag %d is tested clear (triggers %s) but nothing sets it: always clear" % (f, _list(ts)))
        for f, ts in sorted(clears_flag.items()):
            if f not in sets_flag:
                r.add(INFO, "flag", "flag %d is cleared (triggers %s) but nothing sets it" % (f, _list(ts)))
        for k, ts in sorted(tests_timer.items()):
            if k not in starts_timer:
                r.add(WARN, "timer", "timer %d is tested but never started (triggers %s never fire)" % (k, _list(ts)))
        for k, ts in sorted(starts_timer.items()):
            if k not in tests_timer:
                r.add(INFO, "timer-unused", "timer %d is started (triggers %s) but never tested" % (k, _list(ts)))
        for v, uses in sorted(tests_var.items()):
            if v not in assigns_var:
                r.add(WARN, "variable", "variable %d is tested but never assigned (triggers %s never fire)" % (v, _list([u[0] for u in uses])))
                continue
            for ti, value in uses:
                if not any(value < n for _, n in assigns_var[v]):
                    r.add(WARN, "variable", "variable %d == %d can never hold: it is assigned a random number below %s"
                          % (v, value, "/".join(str(n) for _, n in assigns_var[v])), ti)
        if countdown_tests and not countdown_starts:
            r.add(WARN, "countdown", "the countdown is tested (triggers %s) but never started" % _list(countdown_tests))
        for t in trig:
            if not t.conditions and t.index % 256 == 0:
                r.add(WARN, "no-conditions", "trigger %d has no conditions and is number %d: the remake (like the original's register) never fires it"
                      % (t.index, t.index), t.index)
            if t.conditions and t.conditions[-1][0] == 15:
                r.add(WARN, "or-last", "the OR condition is the last one: nothing can hold after it, the trigger never fires", t.index)

        # ------------------------------------------------------- may-fire fixed point
        fired = {}  # trigger -> round
        facts = {}  # fact -> providing trigger
        own = {pl: collections.Counter(c) for pl, c in placed.items()}  # placed, spawned, converted
        made = collections.defaultdict(set)  # player -> GUIDs it can make without limit
        sources = collections.defaultdict(lambda: collections.defaultdict(list))  # player -> guid -> where from

        def source(pl, g, text):
            if text not in sources[pl][g]:
                sources[pl][g].append(text)

        for pl, c in placed.items():
            for g in c:
                source(pl, g, "placed on the map (%d)" % c[g])
        neutral_pairs = set()  # players set neutral by a trigger (action 32)
        independent = {pl for pl, q in m.players.items() if q["control"] == 3}

        def neutral(a, b):
            return a != b and a != 0 and b != 0 and (a in independent or b in independent or (a, b) in neutral_pairs)

        def joiners(pl):
            """Players whose units join `pl`'s when they meet (mission.gd _join_neutrals):
            those neutral to it, when `pl` is not independent itself."""
            if pl in independent or pl not in m.players:
                return []
            return [q for q in own if neutral(pl, q)]

        def holdings(pl):
            """(counts, limitless GUIDs) of what `pl` can have: its own, units of neutral
            players that join it, cows its herders drive off, transports its thieves steal."""
            counts = collections.Counter(own.get(pl, {}))
            limitless = set(made[pl])
            for q in joiners(pl):
                for g, n in own[q].items():
                    if d.is_unit_type(g):
                        counts[g] += n
                        source(pl, g, "joins from player %d (neutral, %d)" % (q, n))
            mine = {g for g, n in counts.items() if n > 0} | limitless
            for takers, goods, how in ((HERDERS, [COW], "driven off by its herders"), (THIEVES, TRANSPORTS, "stolen by its thieves")):
                if pl == 0 or not mine & set(takers):
                    continue
                for q in own:
                    if q == pl:
                        continue
                    for g in goods:
                        if own[q].get(g, 0) > 0 or g in made[q]:
                            counts[g] += own[q].get(g, 0)
                            if g in made[q]:
                                limitless.add(g)
                            source(pl, g, "%s (player %d's)" % (how, q))
            return counts, limitless

        def refresh_production():
            for pl in m.players:
                if pl not in producers:
                    continue
                counts, limitless = holdings(pl)
                for g in self.production(pl, set(g for g, n in counts.items() if n > 0) | limitless):
                    if g not in made[pl]:
                        made[pl].add(g)
                        source(pl, g, "%s by the %s" % (
                            "built" if d.stats.get(g, {}).get("kind") == "structure" else "trained",
                            "human" if m.players[pl]["control"] == 1 else "AI (if its modules do)"))

        def amount(pl, what):
            """(how many of `what` player `pl` can have at most, None: no limit; sources)."""
            if what == BUFFALO:  # counted whoever owns them
                n = sum(c[BUFFALO] for c in own.values())
                limitless = any(BUFFALO in s for s in made.values())
                return (None if limitless else n), ["%d buffalo placed or spawned" % n], False
            counts, limitless = holdings(pl)
            total, src, unlimited, ai_only = 0, [], False, True
            for g in sorted(set(counts) | limitless):
                if not counts_as(g, what):
                    continue
                if g in limitless:
                    unlimited = True
                elif counts[g] <= 0:
                    continue
                else:
                    total += counts[g]
                src.append("%s: %s" % (d.name(g), ", ".join(sources[pl].get(g, ["?"]))))
                ai_only = ai_only and all("AI (if" in x for x in sources[pl].get(g, ["?"]))
            if what in (HORSE, WILD_HORSE) and pl in m.players and own.get(0, {}).get(HORSE):
                total += own[0][HORSE]
                src.append("%d horses of nobody's (can be caught)" % own[0][HORSE])
                ai_only = False
            return (None if unlimited else total), src, ai_only and bool(src)

        def cond_ok(c):
            """(can hold, doubts, facts it needs)"""
            op = c[0]
            weak, needs = [], []
            if op in COUNT_CONDS:
                pl, n, what = p(c, 1), p(c, 2), p(c, 3)
                if op in (3, 11, 13, 14) and p(c, 4) not in m.areas:
                    weak.append("area %d is missing: the whole map" % p(c, 4))
                if pl not in m.players:
                    weak.append("player %d is not in SPIELER" % pl)
                if op in (7, 9, 14):  # fewer than n: none at all will do
                    return n > 0, weak, needs
                need = n if op in (3, 11) else n + 1
                if need <= 0:
                    return True, weak, needs
                if self.guid_problem(what, "count"):
                    return False, weak + ["the remake cannot count %s" % d.name(what)], needs
                most, src, ai_only = amount(pl, what)
                needs.append(("have", pl, what))
                if most is not None and most < need:
                    return False, weak + ["player %d can have at most %d %s (%s)" % (pl, most, d.name(what), "; ".join(src) or "nothing")], needs
                if ai_only:
                    weak.append("only if the AI player %d builds/trains %s" % (pl, d.name(what)))
                return True, weak, needs
            if op in (1, 2, 18):
                return True, weak, needs
            if op == 12:
                return p(c, 2) > 0, weak, needs
            if op == 4:
                needs.append(("countdown",))
            elif op == 5:
                needs.append(("flag", p(c, 1)))
            elif op == 16:
                needs.append(("timer", p(c, 1)))
            elif op == 17:
                needs.append(("var", p(c, 1), p(c, 2)))
            elif op == 6:
                pl = p(c, 2)
                if p(c, 2) not in m.areas:
                    weak.append("area %d is missing: the whole map" % p(c, 2))
                counts, limitless = holdings(p(c, 1))
                anything = any(n > 0 for n in counts.values()) or bool(limitless)
                return anything, weak + ([] if anything else ["player %d never has anything" % p(c, 1)]), needs
            elif op == 15:
                return False, weak, needs
            else:
                return False, weak + ["unknown condition"], needs
            return needs[0] in facts, weak, needs

        def may_fire(t):
            """(may fire, doubts, facts needed) by mission.gd _check's rules: all
            conditions before an OR (15), then any one after it."""
            if not t.conditions:
                return t.index % 256 != 0, [], []
            results = [cond_ok(c) for c in t.conditions]
            ops = [c[0] for c in t.conditions]
            if 15 in ops:
                k = ops.index(15)
                before = results[:k]
                after = [x for x, o in zip(results[k + 1:], ops[k + 1:]) if o != 15 and x[0]]
                ok = all(x[0] for x in before) and bool(after)
                used = before + after[:1]
            else:
                ok = all(x[0] for x in results)
                used = results
            return ok, [w for x in used for w in x[1]], [n for x in used for n in x[2]]

        def apply(t):
            again = any(a[0] == 10 for a in t.actions)
            for a in t.actions:
                op = a[0]
                if op == 12:
                    facts.setdefault(("flag", p(a, 1)), t.index)
                elif op == 25:
                    facts.setdefault(("timer", p(a, 1)), t.index)
                elif op == 11:
                    facts.setdefault(("countdown",), t.index)
                elif op == 33:
                    for v in range(max(0, p(a, 2))):
                        facts.setdefault(("var", p(a, 1), v), t.index)
                elif op == 1:
                    producers.add(p(a, 1))
                elif op == 32:
                    neutral_pairs.update({(p(a, 1), p(a, 2)), (p(a, 2), p(a, 1))})
                elif op in (3, 14, 36):
                    pl, g, n = {3: (p(a, 1), p(a, 3), p(a, 2)), 14: (0, p(a, 1), 1), 36: (p(a, 4), p(a, 1), 1)}[op]
                    if g in (BUFFALO, COW, WILD_HORSE) and op == 3:
                        pl = 0  # nobody's (a horse keeps its owner)
                    g = HORSE if g == WILD_HORSE else g
                    if self.guid_problem(g, "spawn" if op == 3 else "create"):
                        continue
                    own.setdefault(pl, collections.Counter())[g] += n
                    if again:  # fires again and again: no limit
                        made[pl].add(g)
                    source(pl, g, "%s by trigger %d" % ("spawned" if op == 3 else "created", t.index))
                    facts.setdefault(("spawn", pl, g), t.index)
                elif op == 35:
                    what, pl = p(a, 1), p(a, 3)
                    for q in list(own):
                        if q in (0, pl):
                            continue
                        counts, limitless = holdings(q)
                        for g in set(counts) | limitless:
                            if counts_as(g, what) and (counts[g] > 0 or g in limitless):
                                own.setdefault(pl, collections.Counter())[g] += counts[g]
                                if g in limitless:
                                    made[pl].add(g)
                                source(pl, g, "converted from player %d by trigger %d" % (q, t.index))
                                facts.setdefault(("spawn", pl, g), t.index)

        rounds = 0
        refresh_production()
        changed = True
        while changed and rounds < 200:
            changed = False
            rounds += 1
            for t in trig:
                if t.index not in fired and may_fire(t)[0]:
                    fired[t.index] = rounds
                    apply(t)
                    changed = True
            refresh_production()
        self.fired = fired
        self.facts = facts
        self.sources = sources

        dead = [t for t in trig if t.index not in fired]
        for t in dead:
            reasons = []
            for c in t.conditions:
                ok, weak, _ = cond_ok(c)
                if not ok and c[0] != 15:
                    reasons.append(m.describe(c, False) + (" [%s]" % "; ".join(weak) if weak else ""))
            does = ", ".join(sorted({ACT.get(a[0], ("?",))[0] for a in t.actions}))
            important = any(a[0] in (13, 4) and p(a, 1) == m.human for a in t.actions)
            r.add(WARN if important else INFO, "dead", "trigger %d%s can never fire (%s) [does: %s]"
                  % (t.index, " %r" % t.name if t.name else "", "; ".join(reasons) or "no condition can hold", does), t.index)

        # ------------------------------------------------------- WIN and LOSE
        human = m.human
        wins = [t for t in trig if any(a[0] == 13 and p(a, 1) == human for a in t.actions)]
        loses = [t for t in trig if any(a[0] == 4 and p(a, 1) == human for a in t.actions)]
        others = [(t.index, p(a, 1), a[0]) for t in trig for a in t.actions if a[0] in (4, 13) and p(a, 1) != human]
        if others:
            r.add(INFO, "end-other", "WIN/LOSE for other players (the remake ignores them): %s"
                  % ", ".join("trigger %d %s player %d" % (ti, "WIN" if op == 13 else "LOSE", pl) for ti, pl, op in others))
        reachable_wins = [t for t in wins if t.index in fired]
        if not wins:
            r.add(ERROR, "win", "no trigger makes the human player %s win" % human)
        elif not reachable_wins:
            r.add(ERROR, "win", "the human's WIN (triggers %s) can never be reached" % _list([t.index for t in wins]))
        chains = []
        for t in reachable_wins:
            chain = self.chain(t.index, may_fire)
            weak = []
            for ti in chain:
                _, w, _ = may_fire(trig[ti])
                weak += ["trigger %d: %s" % (ti, x) for x in w]
            chains.append((t.index, chain, weak))
        if reachable_wins and all(c[2] for c in chains):
            r.add(WARN, "win-weak", "every chain to the human's WIN rests on a doubtful condition: %s"
                  % " | ".join("; ".join(c[2]) for c in chains))
        r.sections["win"] = self.describe_chains(chains, wins)
        lose_lines = []
        for t in loses:
            ok = t.index in fired
            conds = " AND ".join(m.describe(c, False) for c in t.conditions) or "(none)"
            lose_lines.append("trigger %d%s: %s%s" % (t.index, " %r" % t.name if t.name else "", conds, "" if ok else " [can never fire]"))
        if not loses:
            r.add(INFO, "lose", "no trigger makes the human lose: when it has lost everything nothing ends the mission "
                  "(main.gd's _check_victory leaves missions to their script)")
        r.sections["lose"] = lose_lines or ["no trigger makes the human lose"]

        # ------------------------------------------------------- players
        referenced = collections.defaultdict(list)
        for t in trig:
            for c in t.conditions:
                if c[0] in COUNT_CONDS | {2, 6, 12}:
                    referenced[p(c, 1)].append(t.index)
        for pl, ts in sorted(referenced.items()):
            counts, limitless = holdings(pl)
            if pl in m.players and not any(n > 0 for n in counts.values()) and not limitless:
                r.add(WARN, "player-empty", "player %d is tested (triggers %s) but never has anything" % (pl, _list(ts)))
        return r

    def chain(self, start, may_fire):
        """The triggers that set up what `start` needs, back to the start (earliest
        providers in the fixed point), in firing order."""
        out = []
        todo = [start]
        seen = set()
        while todo:
            ti = todo.pop()
            if ti in seen:
                continue
            seen.add(ti)
            out.append(ti)
            _, _, needs = may_fire(self.m.triggers[ti])
            for n in needs:
                if n[0] == "have":  # spawned by triggers, unless the map or production gives it
                    src = {g: v for g, v in self.sources[n[1]].items() if counts_as(g, n[2]) and v}
                    if any(" by trigger " in x for v in src.values() for x in v) \
                            and not any("placed" in x or "joins" in x for v in src.values() for x in v):
                        todo += [self.facts[("spawn", n[1], g)] for g in src if ("spawn", n[1], g) in self.facts]
                elif n in self.facts:
                    todo.append(self.facts[n])
        return sorted(out, key=lambda i: (self.fired.get(i, 0), i))

    def describe_chains(self, chains, wins):
        m = self.m
        lines = []
        if not wins:
            return ["no WIN action for the human"]
        for win, chain, weak in chains:
            lines.append("WIN by trigger %d through %d trigger(s):" % (win, len(chain)))
            for ti in chain:
                t = m.triggers[ti]
                conds = " AND ".join(m.describe(c, False) for c in t.conditions) or "(no conditions)"
                acts = ", ".join(m.describe(a, True) for a in t.actions if a[0] in (12, 25, 33, 11, 13, 3, 35, 36, 1))
                lines.append("  - trigger %d%s: if %s -> %s" % (ti, " %r" % t.name if t.name else "", conds, acts))
            for w in weak:
                lines.append("  ! %s" % w)
        unreachable = [t.index for t in wins if t.index not in self.fired]
        if unreachable:
            lines.append("WIN triggers that can never fire: %s" % _list(unreachable))
        return lines


def _list(xs):
    xs = sorted(set(xs))
    return ", ".join(str(x) for x in xs[:12]) + (" ..." if len(xs) > 12 else "")


# ------------------------------------------------------------------------------- the remake's tables

def check_tables(data, missions, checkers=()):
    """The remake's own mission tables (mission.gd) against the object data: the
    foot-or-mounted GUIDs and the people's unit and building ranges of the categories;
    and the natives the missions' modules use, all together."""
    out = []
    calls = collections.Counter()
    stubs = collections.defaultdict(list)
    modules = {}
    for c in checkers:
        modules.update({n: mod for n, (mod, _, _) in getattr(c, "closure", {}).items() if mod})
        for nid in getattr(c, "stubs", {}):
            stubs[nid].append(c.m.id)
    for mod in modules.values():
        calls.update(w & 0x0FFFFFFF for w in mod.code if w >> 28 == 4)
    if calls:
        bad = [nid for nid in calls if data.natives.classify(nid)[0] in (ERROR, WARN)]
        out.append({"severity": INFO, "code": "natives", "message": "the missions' %d modules call %d natives (%d calls); %s" % (
            len(modules), len(calls), sum(calls.values()), "%d of them are missing or out of step (see the missions)" % len(bad) if bad else
            "ki_natives.gd implements every one with the original's argument and result counts")})
    for nid, where in sorted(stubs.items()):
        out.append({"severity": INFO, "code": "native-stub", "message": "native %d %s is %s in ki_natives.gd; called in %d missions (%s)" % (
            nid, NATIVES[nid][0], data.natives.classify(nid)[1], len(where), _list(where))})
    used = collections.defaultdict(list)
    for m in missions:
        for t in m.triggers:
            for item in t.conditions + t.actions:
                for v in item[1:]:
                    if v in EITHER:
                        used[v].append(m.id)
    mounted_of = {foot: mnt for mnt, foot in data.foot_of.items()}
    for key, pair in sorted(EITHER.items()):
        foot, mnt = pair
        names = [data.stats.get(g, {}).get("name") for g in pair]
        heroes = all(data.stats.get(g, {}).get("kind") == "hero" for g in pair) and names[0] == names[1]
        if data.foot_of.get(mnt) == foot or heroes:
            continue
        guess = ""
        for g in pair:
            if g in data.foot_of:
                guess = "; probably [%d, %d] (%s, %s)" % (data.foot_of[g], g, data.name(data.foot_of[g]), data.name(g))
                break
            if g in mounted_of:
                guess = "; probably [%d, %d] (%s, %s)" % (g, mounted_of[g], data.name(g), data.name(mounted_of[g]))
                break
        where = sorted(set(used.get(key, [])))
        out.append({"severity": ERROR if where else INFO, "code": "either",
                    "message": "mission.gd EITHER[%d] = %s counts %s, not a unit on foot and the same unit mounted%s; %s"
                    % (key, pair, " and ".join(data.name(g) if data.stats.get(g) else "%d (no such GUID)" % g for g in pair),
                       guess, ("used by " + ", ".join(where)) if where else "no mission uses it")})
    hero_gaps = []
    for i, people in enumerate(PEOPLES):
        for ranges, kinds, what in ((UNIT_RANGES, ("unit", "hero"), "units"), (BUILDING_RANGES, ("structure",), "buildings")):
            lo, hi = ranges[i]
            outside = sorted(g for g, st in data.stats.items() if st.get("faction") == people and st.get("kind") in kinds
                             and not lo <= g < hi and g != FIELD and g < 1000)
            heroes = [g for g in outside if data.stats[g].get("kind") == "hero"]
            others = [g for g in outside if g not in heroes]
            if others:
                out.append({"severity": INFO, "code": "category", "message": "the %s %s category (%d..%d) leaves out %s" % (
                    people, what, lo, hi - 1, ", ".join("%d %s" % (g, data.name(g)) for g in others))})
            if heroes:
                hero_gaps.append("%s %d..%d" % (people, heroes[0], heroes[-1]))
    if hero_gaps:
        out.append({"severity": INFO, "code": "category", "message": "the unit categories (0..4, 16..20) leave out the heroes (%s): "
                    "\"fewer than 1 unit\" holds while a hero lives; the scripts test heroes separately (e.g. base/ind_04 t3), "
                    "so the original's categories probably do the same" % ", ".join(hero_gaps)})
    return out


# ------------------------------------------------------------------------------- output

def all_missions(data, wanted):
    out = []
    for s in SETS:
        for people in ["tut"] + PEOPLES:
            for e in data.campaign[s]["missions"].get(people, []):
                mid = "%s/%s" % (s, e["code"])
                if not wanted or mid in wanted or (s == "base" and e["code"] in wanted):
                    out.append((s, e))
    return out


def dump(data, modules, mission):
    m = mission
    print("# %s %s  (%s, %dx%d px, %s)" % (m.id, m.title, os.path.relpath(m.path, data.assets), m.size[0], m.size[1], m.biome))
    print("\nplayers:")
    for q in sorted(m.players.values(), key=lambda q: q["slot"]):
        owned = collections.Counter(data.type_guid.get(t) for _, _, t, o in m.placements if o == q["index"])
        owned.pop(None, None)
        print("  player %d slot %d %-4s %-11s name %-12r allies %#04x  has %s" % (
            q["index"], q["slot"], q["people"], SEATS.get(q["control"], "?"), q["name"], q["allies"],
            ", ".join("%d %s" % (n, data.name(g)) for g, n in sorted(owned.items())) or "nothing"))
    print("\nareas:")
    for aid, a in sorted(m.areas.items()):
        print("  %3d %-24r %s" % (aid, a["name"], a["rect"]))
    print("\ntriggers:")
    for t in m.triggers:
        print("  [%d]%s" % (t.index, " %r" % t.name if t.name else ""))
        for c in t.conditions:
            print("      if   %s" % m.describe(c, False))
        for a in t.actions:
            print("      do   %s" % m.describe(a, True))


def markdown(reports, tables, out):
    w = lambda s="": print(s, file=out)
    w("# Campaign mission check")
    w()
    w("`tools/campaign/check_missions.py`: a static check of the campaign maps' scripts against the remake's")
    w("data and code (see the tool's docstring for what \"may fire\" and \"can have\" mean).")
    w()
    w("| Mission | Title | Triggers | ERROR | WARN | INFO | WIN |")
    w("| --- | --- | --- | --- | --- | --- | --- |")
    for r in reports:
        m = r.mission
        win = "no WIN" if any(f["code"] == "win" for f in r.findings) else ("doubtful" if any(f["code"] == "win-weak" for f in r.findings) else "reachable")
        w("| %s | %s | %d | %d | %d | %d | %s |" % (m.id, m.title, len(m.triggers), r.count(ERROR), r.count(WARN), r.count(INFO), win))
    w()
    if tables:
        w("## The remake's tables")
        w()
        for f in tables:
            w("- %s: %s" % (f["severity"], f["message"]))
        w()
    for r in reports:
        m = r.mission
        w("## %s %s" % (m.id, m.title))
        w()
        w("Players: %s. Human: player %s. %s." % (
            ", ".join("%d %s %s" % (q["index"], q["people"], SEATS.get(q["control"], "?")) for q in sorted(m.players.values(), key=lambda q: q["index"])),
            m.human, r.sections.get("modules", "")))
        w()
        for sev in SEVERITIES:
            items = [f for f in r.findings if f["severity"] == sev]
            if not items:
                continue
            w("**%s**" % sev)
            w()
            for f in items:
                w("- %s%s" % ("[t%d] " % f["trigger"] if f["trigger"] is not None else "", f["message"]))
            w()
        w("**How to win**")
        w()
        w("```")
        for line in r.sections.get("win", []):
            w(line)
        w("```")
        w()
        w("**How to lose**")
        w()
        for line in r.sections.get("lose", []):
            w("- %s" % line)
        w()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("missions", nargs="*", help="set/code (e.g. base/ind_03, expansion/usa_01); a bare code is the base set's")
    ap.add_argument("--assets", default=os.path.join(ROOT, "assets"), help="the built asset folder")
    ap.add_argument("--original", default=os.path.join(ROOT, "original"),
                    help="the original game's extracted files (optional: tells the asset build's gaps from the original's)")
    ap.add_argument("--json", action="store_true", help="print the findings as JSON")
    ap.add_argument("--dump", metavar="MISSION", help="print a mission's players, areas and triggers")
    ap.add_argument("-o", "--output", help="write the report here instead of stdout")
    args = ap.parse_args()
    data = Data(args.assets)
    modules = Modules(args.assets)
    if args.dump:
        found = all_missions(data, {args.dump})
        if not found:
            sys.exit("no mission %s" % args.dump)
        dump(data, modules, Mission(data, *found[0]))
        return
    original = Original(args.original)
    missions = [Mission(data, s, e) for s, e in all_missions(data, set(args.missions))]
    checkers = [Checker(data, modules, m, original) for m in missions]
    reports = [c.check() for c in checkers]
    tables = check_tables(data, missions, checkers)
    out = open(args.output, "w", encoding="utf-8") if args.output else sys.stdout
    if args.json:
        json.dump({"tables": tables, "missions": [{"mission": r.mission.id, "title": r.mission.title, "human": r.mission.human,
                    "counts": {s: r.count(s) for s in SEVERITIES}, "findings": r.findings,
                    "win": r.sections.get("win", []), "lose": r.sections.get("lose", [])} for r in reports]}, out, indent=1)
        print(file=out)
    else:
        markdown(reports, tables, out)
    errors = sum(r.count(ERROR) for r in reports)
    print("%d missions: %d errors, %d warnings" % (len(reports), errors, sum(r.count(WARN) for r in reports)), file=sys.stderr)


if __name__ == "__main__":
    main()
