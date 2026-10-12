#!/usr/bin/env python3
"""Drive every campaign mission to its win with the mission driver and write a summary.

Usage: tools/campaign/drive_all.py [--report=path] [--logs=dir] [--jobs=2] [--mode=win|story] [mission ...]
       (missions as <set>/<code>, e.g. base/ind_01; none: every mission but the tutorials;
       --mode=story fires every other trigger it can on the way before going for the win)

Runs `--scenario=drive` (game/scripts/dev/mission_driver.gd) headless per mission, keeps
each run's output in the log folder, and writes a markdown report: per mission the result
(WON / STUCK / LOST), the triggers that fired on the way, and for the stuck ones the
driver's diagnosis.
"""
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
GAME = os.path.join(ROOT, "game")
TIMEOUT = 1500  # seconds of real time per mission
MAX_LOG = 64 << 20


def missions():
    with open(os.path.join(ROOT, "assets", "data", "campaign.json")) as f:
        data = json.load(f)
    found = []
    for set_name in ("base", "expansion"):
        for people, entries in data[set_name]["missions"].items():
            if people == "tut":
                continue
            found += ["%s/%s" % (set_name, m["code"]) for m in entries]
    return sorted(found)


def drive(mission, logs, mode):
    command = ["godot", "--headless", "--fixed-fps", "30", "--path", GAME, "--",
               "--mission=" + mission, "--scenario=drive", "--time-scale=8", "--drive=" + mode]
    started = time.time()
    log = os.path.join(logs, mission.replace("/", "_") + ".log")
    with open(log, "w") as f:  # written as it runs, to follow a long one
        game = subprocess.Popen(command, stdout=f, stderr=subprocess.STDOUT)
        stop = ""
        while game.poll() is None:
            time.sleep(2)
            if time.time() - started > TIMEOUT:
                stop = "TIMEOUT after %d s real time" % TIMEOUT
            elif os.path.getsize(log) > MAX_LOG:
                stop = "TIMEOUT: the log passed %d MB (an error repeating every step)" % (MAX_LOG >> 20)
            elif "Compile Error" in tail(log):
                stop = "TIMEOUT: a script does not compile"
            if stop:
                game.kill()
                game.wait()
                f.write("\nDRIVE %s %s\n" % (mission, stop))
    out = read_log(log)
    return mission, out, time.time() - started


def tail(path, size=200000):
    with open(path, "rb") as f:
        f.seek(max(0, os.path.getsize(path) - size))
        return f.read().decode(errors="replace")


def read_log(path):
    """The log, with an error that repeats thousands of times cut down to a count."""
    with open(path, errors="replace") as f:
        lines = f.read().split("\n")
    seen = {}
    kept = []
    for line in lines:
        if line.startswith(("ERROR", "SCRIPT ERROR", "WARNING", " ")):
            seen[line] = seen.get(line, 0) + 1
            if seen[line] > 3:
                continue
        kept.append(line)
    repeated = ["(%d times) %s" % (n, line) for line, n in seen.items() if n > 3 and line.strip()]
    out = "\n".join(kept + repeated) + "\n"
    if os.path.getsize(path) > MAX_LOG // 4:
        with open(path, "w") as f:
            f.write(out)
    return out


def summarise(mission, out):
    final = re.findall(r"^DRIVE \S+ (WON|STUCK|LOST|TIMEOUT)(.*)$", out, re.M)
    result, detail = final[-1] if final else ("CRASHED", "")
    fired = re.findall(r"^DRIVE t=(\d+) fired (\d+) ('[^']*')?", out, re.M)
    path = ", ".join("%s@%s" % (index, t) for t, index, _ in fired)
    diagnosis = ""
    if "DRIVE diagnosis" in out:
        diagnosis = out[out.index("DRIVE diagnosis"):].split("\nDRIVE ", 1)[0]
    errors = sorted(set(re.findall(r"SCRIPT ERROR: (.*)", out)))
    cheats = len(re.findall(r"^DRIVE t=\d+ cheat", out, re.M))
    return result, detail.strip(), path, diagnosis, errors, cheats


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    options = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    scratch = "/tmp/claude-1000/-home-tkreek-Work-no-peace-port/31e5b2da-fed2-4f3a-b481-391dcc75230f/scratchpad/agents"
    report = options.get("report", os.path.join(scratch, "driver-report.md"))
    logs = options.get("logs", os.path.join(os.path.dirname(report), "driver-logs"))
    os.makedirs(logs, exist_ok=True)
    todo = args or missions()
    rows = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=int(options.get("jobs", "2"))) as pool:
        for mission, out, seconds in pool.map(lambda m: drive(m, logs, options.get("mode", "win")), todo):
            rows[mission] = summarise(mission, out) + (seconds,)
            print("%-16s %-7s %4.0fs  %s" % (mission, rows[mission][0], seconds, rows[mission][1][:120]), flush=True)
    lines = ["# Campaign driver report", "",
             "Each mission run with `--scenario=drive --time-scale=8 --drive=%s` (game/scripts/dev/mission_driver.gd)."
             % options.get("mode", "win"), "",
             "| Mission | Result | Detail | Cheats | Script errors |", "| --- | --- | --- | --- | --- |"]
    for mission in todo:
        result, detail, path, diagnosis, errors, cheats, seconds = rows[mission]
        lines.append("| %s | %s | %s | %d | %d |" % (mission, result, detail.replace("|", "/"), cheats, len(errors)))
    for mission in todo:
        result, detail, path, diagnosis, errors, cheats, seconds = rows[mission]
        lines += ["", "## %s: %s" % (mission, result), "", detail, "", "Triggers fired (index@game second): " + (path or "none")]
        if diagnosis:
            lines += ["", "```", diagnosis.strip(), "```"]
        if errors:
            lines += ["", "Script errors:"] + ["- `%s`" % e for e in errors[:10]]
    with open(report, "w") as f:
        f.write("\n".join(lines) + "\n")
    won = sum(1 for r in rows.values() if r[0] == "WON")
    print("%d of %d won; report: %s" % (won, len(todo), report))


if __name__ == "__main__":
    main()
