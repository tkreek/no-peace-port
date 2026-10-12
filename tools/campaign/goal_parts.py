#!/usr/bin/env python3
"""Review aid for game/data/campaign_goals.json, the table of which triggers mark a mission
goal's part as done (the "Mission goals" page crosses it out once one has fired).

For every goal text a mission's script gives (action 27), prints the parts MissionGoals.parse
splits it into (game/scripts/ui/hud/mission_goals.gd, replicated here: keep the two in sync)
next to the triggers the table lists for each part, with those triggers' conditions and
messages, so a human can check that each one fires exactly when the part is accomplished.

usage:
  goal_parts.py                     all missions
  goal_parts.py base/des_01 ...     only these ("des_01" means the base set's)
  goal_parts.py --check             only the table's problems (exit 1 when there are any):
                                    unknown missions or texts, part counts that differ from
                                    the parse, triggers out of range, goal texts not listed
  goal_parts.py --raw base/des_01   also each goal text as the game splits it into lines
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import check_missions as cm  # noqa: E402

TABLE = os.path.join(ROOT, "game", "data", "campaign_goals.json")
GOALS_GD = os.path.join(ROOT, "game", "scripts", "ui", "hud", "mission_goals.gd")
GOAL_ACTION, MESSAGE_ACTION = 27, 5


def gd_regex(name):
    """mission_goals.gd's regex constant `name`, as Python reads it."""
    src = open(GOALS_GD, encoding="utf-8").read()
    m = re.search(r'^const %s := "((?:[^"\\]|\\.)*)"' % name, src, re.M)
    if not m:
        raise SystemExit("mission_goals.gd: no const %s" % name)
    return m.group(1).encode().decode("unicode_escape")


HEADER = re.compile(gd_regex("HEADER"), re.I)
NUMBER = re.compile(gd_regex("NUMBER"))
SECONDARY = gd_regex("SECONDARY")


def game_text(raw):
    """Mission.text: '@' is a line break, '#' a space."""
    return raw.replace("@", "\n").replace("#", " ")


def plain(text):
    """MissionGoals._plain."""
    line = " ".join(l.strip() for l in text.split("\n") if l.strip())
    if line.count('"') % 2 == 1 and line.endswith('"'):
        line = line[:-1].strip()
    return line


def parse(text):
    """MissionGoals.parse: {"goals": [...], "tips": [...]}."""
    goals, tips = [], []
    last = ""
    for raw in text.replace(" TIP:", "\nTIP:").split("\n"):
        line = plain(HEADER.sub("", raw.strip(), count=1))
        if line == "":
            continue
        if line.upper().startswith("TIP"):
            tips.append(line)
            last = "tip"
        elif NUMBER.search(line) or line.upper().startswith(SECONDARY):
            goals.append(NUMBER.sub("", line, count=1))
            last = "goal"
        elif last == "tip":
            tips[-1] += " " + line
        elif not goals:
            goals.append(line)
            last = "goal"
        else:
            goals[-1] += " " + line
            last = "goal"
    return {"goals": goals, "tips": tips}


def goal_texts(mission):
    """The goal texts the script gives, in trigger order: {text id: [trigger, ...]}."""
    out = {}
    for t in mission.triggers:
        for a in t.actions:
            if a[0] == GOAL_ACTION:
                out.setdefault(cm.p(a, 1), []).append(t.index)
    return out


def short(text, width):
    text = " ".join(text.split())
    return text if len(text) <= width else text[:width - 3] + "..."


def trigger_lines(mission, index):
    t = mission.triggers[index]
    out = ["if %s" % mission.describe(c, False) for c in t.conditions]
    for a in t.actions:
        if a[0] in (MESSAGE_ACTION, GOAL_ACTION):
            raw = mission.data.texts(mission.set).get(str(cm.p(a, 1)), "")
            out.append("%s %d %r" % ("says" if a[0] == MESSAGE_ACTION else "goal", cm.p(a, 1), short(plain(game_text(raw)), 90)))
        elif a[0] in (12, 23, 13, 4, 25, 33):  # flags, WIN/LOSE, timers, variables
            out.append("do %s" % mission.describe(a, True))
    return out


def check(missions, table):
    problems = []
    known = {m.id for m in missions}
    for key in table:
        if key not in known:
            problems.append("%s: no such mission" % key)
    for m in missions:
        entry = table.get(m.id)
        texts = goal_texts(m)
        if entry is None:
            if texts:
                problems.append("%s: not in the table (%d goal texts)" % (m.id, len(texts)))
            continue
        for tid in texts:
            if str(tid) not in entry:
                problems.append("%s: goal text %d not listed" % (m.id, tid))
        for tid, parts in entry.items():
            if int(tid) not in texts:
                problems.append("%s: text %s is not a goal text of the script" % (m.id, tid))
                continue
            parsed = parse(game_text(m.data.texts(m.set).get(tid, "")))["goals"]
            if len(parts) != len(parsed):
                problems.append("%s: text %s has %d parts, the table %d" % (m.id, tid, len(parsed), len(parts)))
            for i, triggers in enumerate(parts):
                for t in triggers:
                    if not 0 <= t < len(m.triggers):
                        problems.append("%s: text %s part %d: no trigger %d" % (m.id, tid, i + 1, t))
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("missions", nargs="*")
    ap.add_argument("--assets", default=os.path.join(ROOT, "assets"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--raw", action="store_true")
    args = ap.parse_args()
    data = cm.Data(args.assets)
    missions = [cm.Mission(data, s, e) for s, e in cm.all_missions(data, set(args.missions))]
    table = json.load(open(TABLE, encoding="utf-8")) if os.path.exists(TABLE) else {}
    if args.check:
        problems = check(missions, table)
        for p in problems:
            print(p)
        print("%d problems" % len(problems), file=sys.stderr)
        sys.exit(1 if problems else 0)
    parts_total = mapped = 0
    for m in missions:
        texts = goal_texts(m)
        if not texts:
            continue
        entry = table.get(m.id, {})
        print("# %s %s" % (m.id, m.title))
        for tid, given_by in texts.items():
            raw = data.texts(m.set).get(str(tid), "")
            parsed = parse(game_text(raw))
            print("\n  goal text %d (given by trigger %s)" % (tid, ", ".join(map(str, given_by))))
            if args.raw:
                for line in game_text(raw).split("\n"):
                    print("    | %s" % line)
            parts = entry.get(str(tid))
            for i, goal in enumerate(parsed["goals"]):
                parts_total += 1
                triggers = parts[i] if parts is not None and i < len(parts) else None
                mapped += bool(triggers)
                print("    %d. %s" % (i + 1, short(goal, 110)))
                if triggers is None:
                    print("         (not in the table)")
                elif not triggers:
                    print("         [] no trigger")
                for t in triggers or []:
                    if 0 <= t < len(m.triggers):
                        print("         <- trigger %d" % t)
                        for line in trigger_lines(m, t):
                            print("              %s" % line)
                    else:
                        print("         <- trigger %d: NO SUCH TRIGGER" % t)
            for tip in parsed["tips"]:
                print("    tip: %s" % short(tip, 110))
        print()
    print("%d parts, %d with triggers" % (parts_total, mapped), file=sys.stderr)


if __name__ == "__main__":
    main()
