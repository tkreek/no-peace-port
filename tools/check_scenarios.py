#!/usr/bin/env python3
"""Run the game's developer scenarios headless and check what they print.

Usage: tools/check_scenarios.py [name ...]   (no names: all of them)

Each check starts `godot --headless` with a scenario (see game/scripts/dev/scenarios.gd),
waits for it to finish, and requires every expected pattern in the output and no script
error. Scenarios that never quit on their own are bounded with --report-after frames.
Runs several at once; exits non-zero if any check fails.
"""
import concurrent.futures
import os
import re
import subprocess
import sys
import time

GAME = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game")
BASE = ["--ai=off", "--fog=off"]
ISLANDS = "--map=[2 Players] - 2 islands.alf"

# name -> (extra arguments, frames to stop after or 0 if it quits itself, expected patterns)
CHECKS = {
    "parse": ([], 0, [r"parsed \d+ scripts"]),
    "abandoned": (["--map=[4 Players] - forts.alf"], 0, [r"store left 0; guns \d+ -> \d+"]),
    "rob": (["--faction=des"], 1200, [r"robber can rob true, barber can steal true", r"our gold \+[1-9]"]),
    "horses": ([], 0, [r"mounted: true \(horse gone true\)", r"horses 1 / 5, cowboy on foot again true"]),
    "cattle": (["--faction=usa"], 0, [r"cow team 1", r"sold: cow gone true"]),
    "camouflage": (["--faction=ind"], 0, [r"after the trapper: energy"]),
    "pitfall": (["--faction=ind"], 0, [r"pit spent"]),
    "quarters": ([], 0, [r"capacity \d, quartered \d", r"after release: quartered 0"]),
    "research": ([], 2100, [r"researched: \[925\] rifle 2 now:true"]),
    "trade": ([], 0, [r"queued: truetruetrue", r"\"guns\": 24"]),
    "orders": ([], 0, [r"queued Field worker: true", r"rally flag: true"]),
    "magic": ([], 0, [r"conversion: target now team 1"]),
    "magic_ind": (["--faction=ind"], 0, [r"lightning: enemy energy", r"warrior shielded [1-9]"]),
    "hunt": ([], 2700, [r"food \+[1-9]"]),
    "gold": ([], 2700, [r"gold \+[1-9]\d*"]),
    "woodcut": ([], 1900, [r"wood\+[1-9]"]),
    "unhorse": (["--faction=usa", "--enemy=mex"], 0, [r"gauchos on foot alive \d+ dead [1-9]", r"horses alive [1-9]"]),
    "fire": (["--faction=ind", "--enemy=usa"], 0, [r"\"\d+% burning\", \"\d+% burning\""]),
    "tepee": (["--faction=ind"], 0, [r"tepee gone true", r"\"up 70%\""]),
    "boats": (["--faction=usa", "--time-scale=4", ISLANDS], 0, [r"aboard 4 / 4", r"passengers 0, soldiers ashore"]),
    "swim": (["--faction=ind", ISLANDS], 0, [r"swam: true", r"canoe on water plays paddle"]),
    # The command panel for builders, farmers and every building that trains something.
    "menus": ([], 300, [r"builders  \(\d+ units\): Build structure \(B\), Build expanded structure \(V\)",
                        r"farmers  \(\d+ units\): Build structure \(B\), Field"]),
    "saveload": ([], 0, [r"before: units (\d+)", r"after: +units \d+"]),
    # Six computer players for ten game minutes: no script errors, and the waves go out.
    "aigame": (["--ai-vs-ai=1", "--players=mex,usa,ind,des,mex,usa", "--time-scale=4", "--trace-ai=1",
                "--map=[6 Players] - oasis.alf"], 4500, [r"attacks with \d+ units"]),
}


def run(name):
    args, frames, expected = CHECKS[name]
    scenario = name.split("_")[0]
    command = ["godot", "--headless", "--path", GAME]
    if frames:
        command += ["--fixed-fps", "30"]
    if name == "parse":
        command += ["--", "--selftest=parse"]
    elif name == "aigame":
        command += ["--", "--fog=off"] + args
    else:
        command += ["--", "--scenario=" + scenario] + BASE + args
    if frames:
        command.append("--report-after=%d" % frames)
    started = time.time()
    try:
        out = subprocess.run(command, capture_output=True, text=True, timeout=400).stdout
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        out += "\nTIMEOUT"
    problems = [p for p in expected if not re.search(p, out)]
    if "SCRIPT ERROR" in out:
        problems.append("script error: " + out[out.index("SCRIPT ERROR"):].split("\n", 3)[0:3].__str__())
    if "TIMEOUT" in out:
        problems.append("timed out")
    return name, problems, time.time() - started


def main():
    names = sys.argv[1:] or list(CHECKS)
    failed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() // 2 or 2) as pool:
        for name, problems, seconds in pool.map(run, names):
            if problems:
                failed += 1
                print("FAIL %-12s %4.0fs  %s" % (name, seconds, "; ".join(problems)))
            else:
                print("ok   %-12s %4.0fs" % (name, seconds))
    print("%d of %d checks failed" % (failed, len(names)) if failed else "all %d checks passed" % len(names))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
