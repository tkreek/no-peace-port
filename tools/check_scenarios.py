#!/usr/bin/env python3
"""Run the game's developer scenarios headless and check what they print.

Usage: tools/check_scenarios.py [name ...]   (no names: all of them)
       CHECK_ARGS="--opt=value ..." passes extra options to every run.

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
import tempfile
import time

GAME = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game")
BASE = ["--ai=off", "--fog=off"]
ISLANDS = "--map=[2 Players] - 2 islands.ulf"

# name -> (extra arguments, frames to stop after or 0 if it quits itself, expected patterns)
CHECKS = {
    "parse": ([], 0, [r"parsed \d+ scripts"]),
    "abandoned": (["--map=[4 Players] - forts.ulf"], 0, [r"store left \d+; guns (\d+) -> (?!\1;)\d+; loads of at most 2"]),
    "rob": (["--faction=des"], 1200, [r"robber can rob true, barber can steal true", r"our gold \+[1-9]"]),
    "horses": ([], 0, [r"mounted: true \(horse gone true\)", r"horses 1 / 5, cowboy on foot again true"]),
    "cattle": (["--faction=usa"], 0, [r"cow team 1", r"sold: cow gone true"]),
    "camouflage": (["--faction=ind"], 0, [r"after the trapper: energy"]),
    "pitfall": (["--faction=ind"], 0, [r"pit spent"]),
    "quarters": ([], 0, [r"capacity \d, quartered \d", r"hit beyond the open range: true", r"after release: quartered 0, outside (\d+) on \1 cells"]),
    "research": ([], 2100, [r"researched: \[925\] rifle 2 now:true"]),
    "trade": ([], 0, [r"queued: truetruetrue", r"\"guns\": 24"]),
    "orders": ([], 0, [r"queued Field worker: true", r"rally flag: true"]),
    "food": ([], 300, [r"workers per field \[1, 1\]"]),
    "chain": (["--time-scale=4"], 0, [r"queued: idle worker building true with 1 waiting; cutter building true",
                                      r"chained: houses built true; then wood: idle worker true, cutter back at her tree true"]),
    "groups": ([], 0, [r"group 1 recalled: 3 of 3"]),
    "magic": ([], 0, [r"conversion: target now team 1"]),
    "magic_ind": (["--faction=ind"], 0, [r"lightning: enemy energy", r"warrior shielded [1-9]"]),
    "inspect": ([], 120, [r"clicked 481: selected true, panel 'Buffalo' with 2 stats, 0 command buttons, ordered false",
                          r"clicked \d+: selected true, panel '\w+' with 4 stats, 0 command buttons, ordered false",
                          r"mount order rings the horse: true"]),
    "hunt": ([], 2700, [r"hunt order marks the prey: true, hunters on it true",
                        r"buffalo dies: plays die, drawn above the ground true",
                        r"carcass faded with meat left: false", r"food \+[1-9]"]),
    "gold": ([], 2700, [r"mine entrance timbered in \d+\.\ds, gold before it: false", r"gold \+[1-9]\d*"]),
    "woodcut": ([], 1900, [r"wood\+[1-9]"]),
    "unhorse": (["--faction=usa", "--enemy=mex"], 0, [r"gauchos on foot alive \d+ dead [1-9]", r"horses alive [1-9]"]),
    "fire": (["--faction=ind", "--enemy=usa", "--seed=5"], 0, [r"\"\d+% burning\", \"\d+% burning\""]),
    "tepee": (["--faction=ind"], 0, [r"tepee gone true", r"\"up 70%\""]),
    "boats": (["--faction=usa", "--time-scale=4", ISLANDS], 0, [r"clicked boat selected true; sailed [1-9]\d* px, \d{1,2} px short",
                                                                  r"aboard 4 / 4", r"passengers 0, soldiers ashore"]),
    "swim": (["--faction=ind", ISLANDS], 0, [r"swam: true", r"canoe on water plays paddle"]),
    # The command panel for builders, farmers (only fields for the Mexican women) and every
    # building that trains something.
    "menus": ([], 300, [r"builders  \(\d+ units\): Build structure \(B\), Build expanded structure \(V\)",
                        r"farmers  \(\d+ units\): Field \(F\)"]),
    "stages": ([], 0, [r"structures (\d+): construction ends on the finished picture \1, burnt \1, rubble \1 \[\]"]),
    "furnace": ([], 0, [r"furnace glows: idle false, working true, after cancelling false"]),
    "repair": ([], 0, [r"right click: soldier to quarters true, workers repairing false",
                       r"repair command: repaired true"]),
    "buildqueue": (["--time-scale=4"], 0, [r"sites placed 3, built in order true, queued left 0"]),
    "poplimit": ([], 0, [r"warned on filling 1, on a train order 1"]),
    "picking": ([], 0, [r"roof \(picture centre, upper third\) +-> true", r"walls centre +-> true",
                        r"open corner of the walls' box +-> false"]),
    # The dead rot to bones, ruins smoulder, an eagle flies over.
    "remains": ([ISLANDS], 0, [r"remains: \[.*step [12].*step [12]", r"smoke plumes: [23], after 14s 0, flyers: [1-9]"]),
    # Expansion abilities: saboteurs empty and take a fort, the warrior spirit, the armored stagecoach.
    "saboteur": (["--faction=des"], 0, [r"saboteur: garrison \[5, 2, 0, 0\], fort now player 1"]),
    "spirit": (["--faction=ind"], 0, [r"before upgrade false, invoked true, morale 1\.\d+ -> 1\.\d+, energy left 0, again false, auras 3",
                                      r"afterwards morale \d\.\d+, auras 0"]),
    "coach": (["--faction=mex"], 0, [r"aboard 2 / 2, enlarged 4 / 4, enemy hit true, guards dead with the coach 4"]),
    "saveload": ([], 0, [r"before: units (\d+)", r"after: +units \d+"]),
    # The map editor: paint a lake (its rings grow), place things, save, read back, redraw
    # an original map, and drive it with mouse and keyboard events.
    "editor": ([], 0, [r"lake from the centre out \[\"Deep water\", \"Water\", \"Shallow water\", \"Shore\"",
                       r"blocks without a piece 0,", r"read back: tiles same, 10 placements, [1-9]\d* water cells",
                       r"lattice read back, 0 points differ", r"(\d+) of \1 known|1[5-9]\d{3} of 15853 known",
                       r"stroke painted Desert, right click removed 1, undo back to 10 placements"]),
    # Lockstep groundwork: a player's orders recorded at 60 fps, replayed without the interface
    # at 23 fps, must give the same game at every checksum (see run_replay).
    "replay": ([], 0, [r"replay: (1\d|[2-9]\d) of \1 checksums agree"]),
    # Lockstep over the network: a host at 60 fps and a client at 23 fps each give their own
    # people orders, with a computer player too; their checksums must agree (see run_network).
    "network": ([], 0, [r"network: (1\d|[2-9]\d) of \1 checksums agree"]),
    # Six computer players for ten game minutes: no script errors, and the waves go out.
    "aigame": (["--ai-vs-ai=1", "--players=mex,usa,ind,des,mex,usa", "--time-scale=4", "--trace-ai=1",
                "--map=[6 Players] - oasis.ulf"], 4500, [r"attacks with \d+ units"]),
}


def run_replay():
    """Record the "commands" scenario's orders, replay them bare, compare the checksums."""
    replay = os.path.join(tempfile.mkdtemp(), "check.replay")
    common = ["--fog=off", "--checksum-every=5"]
    record = subprocess.run(["godot", "--headless", "--fixed-fps", "60", "--path", GAME, "--",
                             "--scenario=commands", "--record=" + replay] + common,
                            capture_output=True, text=True, timeout=400).stdout
    played = subprocess.run(["godot", "--headless", "--fixed-fps", "23", "--path", GAME, "--",
                             "--replay=" + replay, "--report-after=1400"] + common,
                            capture_output=True, text=True, timeout=400).stdout
    sums = [dict(re.findall(r"tick (\d+) checksum (\w+)", out)) for out in (record, played)]
    shared = [t for t in sums[0] if t in sums[1]]
    agree = sum(sums[0][t] == sums[1][t] for t in shared)
    return record + played + "\nreplay: %d of %d checksums agree\n" % (agree, len(shared))


def run_network():
    """Host and join a three-people match on this machine; compare the two games."""
    port = str(47800 + os.getpid() % 100)
    common = ["--scenario=commands", "--fog=off", "--checksum-every=5"]
    host = subprocess.Popen(["godot", "--headless", "--fixed-fps", "60", "--path", GAME, "--",
                             "--host=" + port, "--humans=2", "--players=mex,usa,ind"] + common,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(2)
    client = subprocess.run(["godot", "--headless", "--fixed-fps", "23", "--path", GAME, "--",
                             "--join=127.0.0.1:" + port] + common,
                            capture_output=True, text=True, timeout=400).stdout
    try:
        hosted = host.communicate(timeout=60)[0]
    except subprocess.TimeoutExpired:
        host.kill()
        hosted = host.communicate()[0]
    sums = [dict(re.findall(r"tick (\d+) checksum (\w+)", out)) for out in (hosted, client)]
    shared = [t for t in sums[0] if t in sums[1]]
    agree = sum(sums[0][t] == sums[1][t] for t in shared)
    return hosted + client + "\nnetwork: %d of %d checksums agree\n" % (agree, len(shared))


def run(name):
    args, frames, expected = CHECKS[name]
    scenario = name.split("_")[0]
    command = ["godot", "--headless", "--path", GAME]
    if frames:
        command += ["--fixed-fps", "30"]
    if name == "parse":
        command += ["--", "--selftest=parse"]
    elif name == "editor":
        command += ["--", "--editor-selftest=1"]
    elif name == "aigame":
        command += ["--", "--fog=off"] + args
    else:
        command += ["--", "--scenario=" + scenario] + BASE + args
    if frames:
        command.append("--report-after=%d" % frames)
    # Extra options for every run, e.g. CHECK_ARGS="--log-assets=/tmp/log".
    command += os.environ.get("CHECK_ARGS", "").split()
    started = time.time()
    try:
        out = run_replay() if name == "replay" else run_network() if name == "network" else \
            subprocess.run(command, capture_output=True, text=True, timeout=400).stdout
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
