#!/usr/bin/env python3
"""Run every campaign mission headless with the player idle and report what does not work.

Usage: tools/campaign/runtime_report.py [options] [set/code ...]   (no codes: every mission
       but the tutorials)
  --minutes N     game minutes per mission (default 20)
  --jobs N        missions at once (default 2; each godot takes 1-2 GB)
  --out DIR       where the per-mission JSON and logs go (default /tmp/mission-stats)
  --report FILE   the markdown report (default DIR/runtime-report.md)
  --notes FILE    markdown put in the report after the summary (the analysis)
  --no-run        only build the report from the JSON already in DIR

Each run is `godot --headless --fixed-fps 30 -- --mission=<set>/<code> --time-scale=4
--report-after=<frames> --mission-stats=<json>` (game/scripts/dev/mission_stats.gd says what
the JSON holds). The report has a summary table per mission, the KI natives that came to
nothing most often across missions with the modules (and their source files) that called
them, natives the remake does not implement, modules that could not start or ended up
waiting on a semaphore forever, what every people had at the start and at the end, the
wall-clock cost of the KI and the triggers, and every trigger that never fired, decoded.
"""
import argparse
import collections
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GAME = os.path.join(ROOT, "game")
ASSETS = os.path.join(ROOT, "assets")
sys.path.insert(0, os.path.join(ROOT, "tools", "ki"))
import kimod  # noqa: E402
from kinatives import NATIVES  # noqa: E402

TIME_SCALE = 4
# Errors that are known and fixed elsewhere: counted apart so they do not hide the rest.
KNOWN_ERRORS = {"garrison freed unit": r"building_defence\.gd:9\d|BuildingDefence\._update_garrison"}
STUBS = {229, 230, 231, 232, 345, 347, 357, 399, 400, 401}
# Modules the maps start that the original does not ship either (tools/campaign/check_missions.py).
MISSING_IN_ORIGINAL = {217999, 176520, 128513, 414477, 663271}
SEARCHES = {107, 108, 109, 120, 121, 122, 139, 140, 141, 200, 201, 202, 203, 204, 205, 228, 368, 370,
            371, 372, 383, 384, 385, 386, 387, 389, 392, 393, 394, 395, 398}

CONDITIONS = {
    1: "always", 2: "P{1} has >= {2} {r3}", 3: "P{1} has exactly {2} {g3} in {a4}", 4: "countdown < {1} s",
    5: "flag {1} set", 6: "P{1} sees {a2}", 7: "P{1} has < {2} {g3}", 8: "P{1} has > {2} {g3}",
    9: "P{1} has < {2} {g3}", 10: "P{1} has > {2} {g3}", 11: "P{1} has exactly {2} {g3} in {a4}",
    12: "P{1} has < {2} {r3}", 13: "P{1} has > {2} {g3} in {a4}", 14: "P{1} has < {2} {g3} in {a4}",
    15: "OR", 16: "timer {1} ran out", 17: "variable {1} == {2}", 18: "flag {1} clear",
}
ACTIONS = {
    1: "start KI module {m2} for P{1}", 2: "P{1} view to {a2}", 3: "{2} x {g3} for P{1} at {a4}",
    4: "P{1} LOSES", 5: "message \"{t1}\" for P{2}", 6: "remove P{1}'s {g2} in {a3}", 7: "nothing", 8: "nothing",
    9: "speech \"{t1}\"", 10: "stay armed", 11: "countdown {1} s", 12: "set flag {1}", 13: "P{1} WINS",
    14: "neutral {g1} at {2},{3}", 15: "show clock", 16: "hide clock", 17: "pause {1} s", 18: "lock input",
    19: "unlock input", 20: "uncover {a2} for P{1}", 21: "give P{1} {2} {r3}", 22: "take {2} {r3} from P{1}",
    23: "clear flag {1}", 24: "cover {a2} for P{1}", 25: "timer {1} = {2} s", 26: "stop timer {1}",
    27: "goal \"{t1}\"", 28: "share sight P{1}/P{2}", 29: "unshare sight P{1}/P{2}", 30: "ally P{1}/P{2}",
    31: "war P{1}/P{2}", 32: "neutral P{1}/P{2}", 33: "variable {1} = random < {2}",
    34: "remove P{1}'s {g2} in {a3}", 35: "{g1} in {a2} goes over to P{3}", 36: "{g1} for P{4} at {2},{3}",
}
RESOURCES = {1: "food", 2: "wood", 3: "horses", 4: "gold", 5: "guns"}
CATEGORIES = {0: "units", 1: "Native units", 2: "Mexican units", 3: "outlaw units", 4: "American units",
              5: "buildings", 6: "Native buildings", 7: "Mexican buildings", 8: "outlaw buildings",
              9: "American buildings", 16: "soldiers", 17: "Native soldiers", 18: "Mexican soldiers",
              19: "outlaw soldiers", 20: "American soldiers", 480: "horses", 481: "buffalo", 482: "cows",
              483: "wild horses"}


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


CAMPAIGN = load_json(os.path.join(ASSETS, "data", "campaign.json"))
GUID_NAMES = {int(k): v.get("name_de", "") for k, v in load_json(os.path.join(ASSETS, "data", "defaults.json")).items()}
GUID_NAMES.update({int(k): v["name"] for k, v in load_json(os.path.join(GAME, "data", "stats.json")).items() if v.get("name")})


def guid_name(guid):
    return CATEGORIES.get(guid) or GUID_NAMES.get(guid) or "GUID %d" % guid


def native_name(nid):
    return NATIVES[nid][0] if nid in NATIVES else "?"


def missions(selected):
    out = []
    for set_name in ("base", "expansion"):
        for people, entries in CAMPAIGN[set_name]["missions"].items():
            for entry in entries:
                code = "%s/%s" % (set_name, entry["code"])
                if entry["code"].startswith("tut_") or (selected and code not in selected):
                    continue
                out.append(code)
    return out


# ------------------------------------------------------------------ modules

_modules = {}


def module(number):
    if number not in _modules:
        _modules[number] = None
        for set_name in ("base", "expansion"):
            path = os.path.join(ASSETS, "campaign", set_name, "ai", "%08d.mod" % number)
            if os.path.exists(path):
                try:
                    _modules[number] = kimod.load(path)
                except Exception:  # noqa: BLE001
                    pass
                break
    return _modules[number]


def module_label(number):
    m = module(int(number))
    return "%08d %s" % (int(number), m.source if m else "(no file)")


def where(number, pc):
    """`source:line` of the instruction before pc (the one that ran last) and what it is."""
    m = module(int(number))
    if m is None:
        return "?"
    at = max(0, pc - 1)
    word = m.code[at] if at < len(m.code) else -1
    op, arg = (word >> 28) & 0xF, word & 0x0FFFFFFF
    what = {4: "call %s" % native_name(arg), 5: "gosub %08d" % arg, 6: "spawn %08d" % arg}.get(op, kimod.OPNAMES.get(op, "?"))
    return "%s:%d (%s)" % (m.source, m.line_of(at) + 1, what)


# ------------------------------------------------------------------ running

def mem_available_gb():
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) / 1024 / 1024
    return 99


def run(code, minutes, out_dir):
    stem = code.replace("/", "_")
    json_path = os.path.join(out_dir, stem + ".json")
    log_path = os.path.join(out_dir, stem + ".log")
    while mem_available_gb() < 3:
        time.sleep(10)
    frames = int(minutes * 60 * 30 / TIME_SCALE)
    args = ["godot", "--headless", "--fixed-fps", "30", "--path", GAME, "--", "--mission=" + code,
            "--time-scale=%d" % TIME_SCALE, "--report-after=%d" % frames, "--seed=1", "--mission-stats=" + json_path]
    if os.path.exists(json_path):
        os.remove(json_path)
    started = time.time()
    with open(log_path, "w") as log:
        try:
            subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, timeout=minutes * 60 * 2 + 600)
            status = "ok"
        except subprocess.TimeoutExpired:
            status = "timeout"
    return code, status, time.time() - started


# ------------------------------------------------------------------ the report

def decode(item, set_name, kind):
    op, params = item[0], item[1:]
    texts = CAMPAIGN[set_name]["texts"]
    pattern = (CONDITIONS if kind == "c" else ACTIONS).get(op, "op %d %s" % (op, params))

    def value(m):
        key = m.group(1)
        prefix, index = (key[0], key[1:]) if key[0].isalpha() else ("", key)
        v = params[int(index) - 1] if int(index) - 1 < len(params) else 0
        if prefix == "a":
            return "area %d" % v
        if prefix == "g":
            return guid_name(v)
        if prefix == "r":
            return RESOURCES.get(v, "resource %d" % v)
        if prefix == "t":
            return texts.get(str(v), "text %d" % v).replace("@", " ")[:70]
        if prefix == "m":
            return module_label(v)
        return str(v)
    return re.sub(r"\{(\w+)\}", value, pattern)


def failure_rows(stats):
    """(native, reason) -> {mission: count}, and (native, reason) -> {module: count}."""
    by_mission = collections.defaultdict(collections.Counter)
    by_module = collections.defaultdict(collections.Counter)
    for code, d in stats.items():
        for nid, reasons in d["failures"].items():
            for reason, modules in reasons.items():
                key = (int(nid), reason)
                for number, n in modules.items():
                    by_mission[key][code] += n
                    by_module[key][number] += n
    return by_mission, by_module


def summarise(code, d, log_info):
    triggers = d["triggers"]
    fired = sum(1 for t in triggers if t["fired"] > 0)
    started = len(d["started_modules"])
    mods = d["modules"]
    spawned = sum(m["started"] for m in mods.values())
    start_failed = sum(m["missing"] + m["full"] for m in mods.values())
    stuck = sum(1 for r in d["running"] if _waiting(r))
    fails = sum(n for nid, reasons in d["failures"].items() if int(nid) not in STUBS
                for reason, modules in reasons.items()
                if not reason.startswith(("found nothing", "object:", "no:")) for n in modules.values())
    computers = [str(p["index"]) for p in d["players"] if p["control"] == 2]
    grown = [0, 0]
    for index in computers:
        start, end = d["start"].get(index), d["end"].get(index)
        if start and end:
            grown[0] += sum(end["buildings"].values()) - sum(start["buildings"].values())
            grown[1] += sum(end["units"].values()) - sum(start["units"].values())
    unimpl = sorted(int(n) for n in d["unimplemented"])
    cost = d["cost"]
    ki = [c[1] for c in cost]
    end = "—"
    if d["outcome"]:
        end = ("won" if d["outcome"] > 0 else "lost") + " %.0fs" % max([e["t"] for e in d["endings"]] or [0])
    elif d["endings"]:
        end = ", ".join("P%d %s %.0fs" % (e["player"], "wins" if e["op"] == 13 else "loses", e["t"]) for e in d["endings"])
    if not d["script_running"]:
        end += " (script over)" if end != "—" else "script over"
    return {"code": code, "title": d["title"], "fired": fired, "triggers": len(triggers), "end": end,
            "started": started, "spawned": spawned, "start_failed": start_failed, "running": len(d["running"]),
            "stuck": stuck, "fails": fails, "grown": grown, "unimpl": unimpl, "ki_avg": sum(ki) / max(1, len(ki)),
            "ki_max": max(ki or [0]), "trig_avg": sum(c[2] for c in cost) / max(1, len(cost)),
            "game_time": d["game_time"], **log_info}


def _waiting(r):
    while r:
        if r.get("waits", -1) >= 0:
            return r
        r = r.get("child")
    return None


def log_info(path):
    """Script and engine errors in a run's log, by kind (message and the first game frame)."""
    info = {"errors": 0, "known_errors": 0, "kinds": collections.Counter()}
    if not os.path.exists(path):
        return info
    with open(path, errors="replace") as f:
        lines = f.read().splitlines()
    for i, line in enumerate(lines):
        if not (line.startswith("SCRIPT ERROR") or line.startswith("ERROR:")) or "leaked" in line \
                or "still in use" in line or line.startswith("ERROR: Condition"):
            continue
        frame = ""
        for after in lines[i + 1:i + 8]:
            m = re.search(r"(?:at: |\] )(\w+ \(res://[^)]*\)|[\w.]+ \(res://[^)]*\))", after)
            if m:
                frame = m.group(1)
                break
        context = line + " " + frame
        if any(re.search(p, context) for p in KNOWN_ERRORS.values()):
            info["known_errors"] += 1
        else:
            info["errors"] += 1
            info["kinds"][(re.sub(r"\d+", "N", line.split(": ", 1)[-1])[:140], frame)] += 1
    return info


def peoples_table(d):
    rows = []
    control = {p["index"]: {1: "human", 2: "computer", 3: "independent"}.get(p["control"], "?") for p in d["players"]}
    for index, end in sorted(d["end"].items(), key=lambda kv: int(kv[0])):
        start = d["start"].get(index, {"units": {}, "buildings": {}, "resources": {}})
        su, eu = sum(start["units"].values()), sum(end["units"].values())
        sb, eb = sum(start["buildings"].values()), sum(end["buildings"].values())
        res = ", ".join("%s %s→%s" % (k, start["resources"].get(k, 0), v) for k, v in end["resources"].items()
                        if start["resources"].get(k, 0) != v) or "unchanged"
        new_buildings = {g: n - start["buildings"].get(g, 0) for g, n in end["buildings"].items()
                         if n > start["buildings"].get(g, 0)}
        sites = end.get("sites", {})
        made = ", ".join("%d %s" % (n, guid_name(int(g))) for g, n in new_buildings.items())
        if sites:
            made += (", " if made else "") + "sites: " + ", ".join("%d %s" % (n, guid_name(int(g))) for g, n in sites.items())
        rows.append("| %s (%s, %s) | %d→%d | %d→%d | %s | %s |" % (index, end["faction"], control.get(int(index), "-"),
                                                                 su, eu, sb, eb, made or "—", res))
    return rows


def report(stats, logs, out, notes):
    lines = []
    w = lines.append
    rows = {code: summarise(code, d, logs.get(code, {})) for code, d in stats.items()}
    w("# Campaign runtime report")
    w("")
    minutes = max([r["game_time"] for r in rows.values()] or [0]) / 60
    w("Every non-tutorial mission run headless for up to %.0f game minutes with the player idle "
      "(`tools/campaign/runtime_report.py`, `--mission-stats`). %d missions." % (minutes, len(rows)))
    w("")
    w("## Summary")
    w("")
    w("Triggers: fired at least once / total. Modules: started by the script / instances started in all "
      "(spawns included) / failed to start / still running at the end / waiting on a semaphore at the end. "
      "Failures: orders that came to nothing (see below; searches, questions and refusals left out). "
      "AI: buildings / units the computer players gained (losses included). "
      "KI ms: wall-clock ms of KI per game minute, mean and worst minute. Errors: script errors in the log "
      "(known errors fixed elsewhere apart).")
    w("")
    w("| Mission | Title | Played | Triggers | Ended | Modules | Failures | AI | Unimplemented | KI ms/min | Trigger ms/min | Errors |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for code, r in rows.items():
        w("| %s | %s | %.0f min | %d/%d | %s | %d / %d / %d / %d / %d | %d | %+d / %+d | %s | %.0f / %.0f | %.1f | %d%s |" % (
            code, r["title"], r["game_time"] / 60, r["fired"], r["triggers"], r["end"], r["started"], r["spawned"],
            r["start_failed"], r["running"], r["stuck"], r["fails"], r["grown"][0], r["grown"][1],
            ", ".join(map(str, r["unimpl"])) or "—",
            r["ki_avg"], r["ki_max"], r["trig_avg"], r.get("errors", 0),
            " (+%d known)" % r["known_errors"] if r.get("known_errors") else ""))
    w("")
    if notes:
        w(notes.rstrip())
        w("")

    # ---------------------------------------------------------- failures
    by_mission, by_module = failure_rows(stats)
    w("## Natives that came to nothing, across missions")
    w("")
    w("Per native and reason: calls that failed in all missions, in how many missions, and the modules "
      "that made most of them. `null handle`: the script passed 0 (usually an earlier search found nothing); "
      "`stale handle`: the object exists but under another owner; `dead handle`: it is gone.")
    w("")
    ranked = sorted(by_mission, key=lambda k: -sum(by_mission[k].values()))
    groups = [
        ("Orders and building", "Orders whose unit, target or building is missing, build_near without a site, "
         "production refused.", lambda nid, reason: not reason.startswith(("object:", "no:"))),
        ("Can I have it (136, 137, 290, 291 answering no)", "Prerequisites missing or not affordable, per GUID.",
         lambda nid, reason: reason.startswith("no:")),
        ("Questions about a missing object", "Mostly harmless: the VM has no short-circuit, so "
         "`exists(h) && health(h) > 0` still asks `health(0)` when an earlier search found nothing.",
         lambda nid, reason: reason.startswith("object:")),
    ]
    for title, note, accept in groups:
        w("### " + title)
        w("")
        w(note)
        w("")
        w("| Native | Reason | Calls | Missions | Top modules |")
        w("| --- | --- | --- | --- | --- |")
        shown = 0
        for key in ranked:
            nid, reason = key
            if nid in STUBS or reason == "found nothing" or not accept(nid, reason):
                continue
            shown += 1
            if shown > 40:
                break
            top = ", ".join("%s (%d)" % (module_label(n), c) for n, c in by_module[key].most_common(3))
            w("| %d %s | %s | %d | %d | %s |" % (nid, native_name(nid), reason, sum(by_mission[key].values()),
                                                len(by_mission[key]), top))
        w("")
    w("### Searches that found nothing")
    w("")
    w("| Native | Calls returning 0 | of all calls | Missions | Top modules |")
    w("| --- | --- | --- | --- | --- |")
    totals = collections.Counter()
    for d in stats.values():
        for nid, n in d["natives"].items():
            totals[int(nid)] += n
    for key in ranked:
        nid, reason = key
        if reason != "found nothing":
            continue
        n = sum(by_mission[key].values())
        top = ", ".join("%s (%d)" % (module_label(m), c) for m, c in by_module[key].most_common(3))
        w("| %d %s | %d | %.0f%% | %d | %s |" % (nid, native_name(nid), n, 100.0 * n / max(1, totals[nid]),
                                                len(by_mission[key]), top))
    w("")
    w("### Stubs called (natives the remake answers with a constant or ignores)")
    w("")
    for key in ranked:
        if key[0] in STUBS:
            w("* %d %s: %d calls in %d missions (%s)" % (key[0], native_name(key[0]), sum(by_mission[key].values()),
                                                         len(by_mission[key]), ", ".join(sorted(by_mission[key]))))
    w("")

    # ---------------------------------------------------------- unimplemented
    w("## Natives the remake does not implement")
    w("")
    unimpl = collections.defaultdict(collections.Counter)
    unimpl_missions = collections.defaultdict(set)
    for code, d in stats.items():
        for nid, modules in d["unimplemented"].items():
            for number, n in modules.items():
                unimpl[int(nid)][number] += n
                unimpl_missions[int(nid)].add(code)
    if not unimpl:
        w("None called.")
    for nid, modules in sorted(unimpl.items(), key=lambda kv: -sum(kv[1].values())):
        original = "implemented in the original: %s — %s" % (native_name(nid), NATIVES[nid][3]) if nid in NATIVES \
            else "a no-op in the original too"
        w("* **%d** (%s): %d calls in %s; modules %s" % (nid, original, sum(modules.values()),
                                                       ", ".join(sorted(unimpl_missions[nid])),
                                                       ", ".join(module_label(n) for n, _ in modules.most_common(4))))
    w("")

    # ---------------------------------------------------------- modules
    w("## Modules")
    w("")
    w("### Could not start")
    w("")
    any_failed = False
    for code, d in stats.items():
        for number, m in d["modules"].items():
            if m["missing"] or m["full"] or m["gosub_missing"] or m.get("no_player"):
                any_failed = True
                expected = " (missing in the original too)" if int(number) in MISSING_IN_ORIGINAL else ""
                w("* %s: %s%s — missing file %d, all 200 slots taken %d, for a player not in the mission %d, "
                  "gosub to a missing module %d" % (code, module_label(number), expected, m["missing"], m["full"],
                                                    m.get("no_player", 0), m["gosub_missing"]))
    if not any_failed:
        w("None.")
    w("")
    w("### Waiting on a semaphore at the end")
    w("")
    w("A module blocked on `lock(k)` whose semaphore nobody frees; the taker is the module that took it last. "
      "Semaphores merely held at the end are not listed: the scripts also use them as \"a watcher for this "
      "building type runs\" flags that stay taken for good (`lock(haus - gebäudediff)` in *_getprioritäteinheit).")
    w("")
    w("| Mission | Player | Modules | Module (where) | Semaphore | Waiting since | Taken by (since) | Taker still running |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for code, d in stats.items():
        taken = {(s["player"], s["sem"]): s for s in d["semaphores"]}
        alive = collections.Counter()
        for r in d["running"]:
            x = r
            while x:
                alive[x["module"]] += 1
                x = x.get("child")
        groups = {}
        for r in d["running"]:
            x = _waiting(r)
            if x:
                key = (r["player"], x["module"], x["pc"], x["waits"])
                first = groups.get(key, [0, 1e9])
                groups[key] = [first[0] + 1, min(first[1], x.get("waiting_since", -1))]
        for (player, number, pc, sem), (n, since) in sorted(groups.items()):
            t = taken.get((player, sem), {"module": 0, "since": -1})
            w("| %s | %d | %d | %s @ %s | %d | %.0fs | %s (%.0fs) | %s |" % (
                code, player, n, module_label(number), where(number, pc), sem, since,
                module_label(t["module"]) if t["module"] else "?", t["since"], "yes" if alive[t["module"]] else "no"))
    w("")
    w("### Busiest modules")
    w("")
    w("Instructions executed in all missions (a module that loops without `wait` costs 50 a second).")
    w("")
    w("| Module | Instructions | Ticks asleep | Ticks blocked | Started | Finished | Missions |")
    w("| --- | --- | --- | --- | --- | --- | --- |")
    agg = collections.defaultdict(lambda: collections.Counter())
    agg_missions = collections.defaultdict(set)
    for code, d in stats.items():
        for number, m in d["modules"].items():
            agg[number].update({k: v for k, v in m.items()})
            agg_missions[number].add(code)
    for number, m in sorted(agg.items(), key=lambda kv: -kv[1]["instructions"])[:20]:
        w("| %s | %d | %d | %d | %d | %d | %d |" % (module_label(number), m["instructions"], m["asleep"], m["blocked"],
                                                   m["started"], m["finished"], len(agg_missions[number])))
    w("")

    # ---------------------------------------------------------- cost
    w("## Cost")
    w("")
    w("Wall-clock ms spent per game minute (one 20-minute run, `--time-scale=4`; observation only).")
    w("")
    w("| Mission | KI mean | KI worst minute | Triggers mean | Modules running at the end |")
    w("| --- | --- | --- | --- | --- |")
    for code, r in sorted(rows.items(), key=lambda kv: -kv[1]["ki_avg"]):
        w("| %s | %.0f | %.0f | %.1f | %d |" % (code, r["ki_avg"], r["ki_max"], r["trig_avg"], r["running"]))
    w("")

    native_ms = collections.Counter()
    native_calls = collections.Counter()
    for d in stats.values():
        for nid, ms in d.get("native_ms", {}).items():
            native_ms[int(nid)] += ms
            native_calls[int(nid)] += d["natives"].get(nid, 0)
    if native_ms:
        total_ki = sum(c[1] for d in stats.values() for c in d["cost"])
        w("### Natives by wall-clock time")
        w("")
        w("All missions together: %.0f s of KI, %.0f s of it inside natives." % (total_ki / 1000, sum(native_ms.values()) / 1000))
        w("")
        w("| Native | ms | Calls | µs per call |")
        w("| --- | --- | --- | --- |")
        for nid, ms in native_ms.most_common(15):
            w("| %d %s | %.0f | %d | %.1f |" % (nid, native_name(nid), ms, native_calls[nid], 1000.0 * ms / max(1, native_calls[nid])))
        w("")

    # ---------------------------------------------------------- errors
    w("## Errors in the logs")
    w("")
    known = sum(r.get("known_errors", 0) for r in rows.values())
    w("Known and fixed elsewhere (the garrison keeping freed units, commit 49c55e9 on `campaign`): %d lines. "
      "Others, by kind:" % known)
    w("")
    kinds = collections.Counter()
    where_seen = collections.defaultdict(set)
    for code in stats:
        for key, n in logs.get(code, {}).get("kinds", {}).items():
            kinds[key] += n
            where_seen[key].add(code)
    if not kinds:
        w("None.")
    for (message, frame), n in kinds.most_common(15):
        w("* %d x `%s` at `%s` (%s)" % (n, message, frame or "?", ", ".join(sorted(where_seen[(message, frame)]))))
    w("")

    # ---------------------------------------------------------- peoples
    w("## The peoples at the start and the end")
    w("")
    for code, d in stats.items():
        w("### %s %s" % (code, d["title"]))
        w("")
        w("| Player | Units | Buildings | New buildings / sites | Stock |")
        w("| --- | --- | --- | --- | --- |")
        lines.extend(peoples_table(d))
        w("")

    # ---------------------------------------------------------- triggers
    w("## Triggers that never fired")
    w("")
    w("Conditions `;`-separated (all must hold, after an OR any), then `=>` the actions. Triggers whose "
      "actions end the mission are expected not to fire in an idle run.")
    w("")
    for code, d in stats.items():
        set_name = code.split("/")[0]
        never = [(i, t) for i, t in enumerate(d["triggers"]) if t["fired"] == 0]
        w("### %s: %d of %d never fired" % (code, len(never), len(d["triggers"])))
        w("")
        for i, t in never:
            cond = "; ".join(decode(c, set_name, "c") for c in t["conditions"]) or "(none)"
            acts = "; ".join(decode(a, set_name, "a") for a in t["actions"])
            name = (" \"%s\"" % t["name"]) if t["name"] else ""
            w("* %d%s (checked %d): %s => %s" % (i, name, t["checked"], cond, acts))
        w("")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("codes", nargs="*")
    parser.add_argument("--minutes", type=float, default=20)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--out", default="/tmp/mission-stats")
    parser.add_argument("--report")
    parser.add_argument("--notes")
    parser.add_argument("--no-run", action="store_true")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    codes = missions(set(args.codes))
    if not args.no_run:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            for code, status, seconds in pool.map(lambda c: run(c, args.minutes, args.out), codes):
                print("%-16s %s in %.0f s" % (code, status, seconds), flush=True)
    stats, logs = {}, {}
    for code in codes:
        stem = code.replace("/", "_")
        path = os.path.join(args.out, stem + ".json")
        logs[code] = log_info(os.path.join(args.out, stem + ".log"))
        if os.path.exists(path):
            stats[code] = load_json(path)
        else:
            print("no stats for %s (crashed or timed out?)" % code, file=sys.stderr)
    notes = open(args.notes, encoding="utf-8").read() if args.notes else ""
    out = args.report or os.path.join(args.out, "runtime-report.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write(report(stats, logs, out, notes))
    print("report: %s" % out)


if __name__ == "__main__":
    main()
