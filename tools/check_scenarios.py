#!/usr/bin/env python3
"""Run the game's developer scenarios headless and check what they print.

Usage: tools/check_scenarios.py [name ...]   (no names: all of them)
       CHECK_ARGS="--opt=value ..." passes extra options to every run;
       CHECK_JOBS=n runs at most n checks at once (default: half the CPUs).

Each check starts `godot --headless` with a scenario (see game/scripts/dev/scenarios.gd),
waits for it to finish, and requires every expected pattern in the output and no script
error. Scenarios that never quit on their own are bounded with --report-after frames.
Every run uses --fixed-fps, so none waits on the wall clock.
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
    "tutorial1": (["--mission=base/tut_01", "--time-scale=4"], 0, [r"joined: 4 of 4", r"tepee standing in its spot; wood 800",
                                                                   r"TUTORIAL 1 WON"]),
    "mission-saveload": (["--mission=base/ind_02", "--time-scale=4"], 0, [r"before: modules \d+, handles (\d+) alive \1,",
                                                                         r"after: +modules \d+, handles (\d+) alive \1,",
                                                                         r"later: +modules [1-9]"]),
    "cheats": (["--mission=base/ind_02"], 0, [r"cheats: food \+1000, fog false -> true, victim dead true, trigger \d+ forced true, speed 4x",
                                               r"speed back to 1x", r"overlay open true, \d+ lines; fired shows the cheat true; \d+ modules: \w+",
                                               r"won by cheat: true"]),
    "tutorial3": (["--mission=base/tut_03", "--time-scale=6"], 0, [r"caught a horse", r"horse in the corral", r"five mounted shooters",
                                                                   r"trappers gone", r"TUTORIAL 3 WON"]),
    "tutorial2": (["--mission=base/tut_02", "--time-scale=6", "--trace-mission=1"], 0, [r"trigger 15 : \[9, 143\]",
                                                                   r"five arrow shooters", r"TUTORIAL 2 WON"]),
    # The campaign driver (game/scripts/dev/mission_driver.gd) cheats a mission's script to its
    # win: Native 3 the long way (15 horses for the Sioux, the ambush, Fetterman's patrol),
    # American 1 with a headquarters where the player may build it.
    "stealwagon": (["--mission=base/des_01", "--time-scale=4"], 0, [r"barbers \d+ can steal \[true",
                                                                   r"stolen after \d+ s with (8\d|9\d)% energy left, unordered"]),
    "drive_ind03": (["--mission=base/ind_03", "--time-scale=8"], 0, [r"fired 17 [\s\S]*fired 3 ", r"DRIVE base/ind_03 WON"]),
    "drive_usa01": (["--mission=base/usa_01", "--time-scale=8"], 0, [r"cheat for trigger 19 .*-> 1", r"DRIVE base/usa_01 WON"]),
    "abandoned": (["--map=[4 Players] - forts.ulf"], 0, [r"store left \d+; guns (\d+) -> (?!\1;)\d+; loads of at most 2"]),
    "repairshot": (["--faction=usa", "--enemy=mex"], 0, [r"computer true, repairing 2, soldiers at workers [1-9]\d*, workers dead 2, back at the house [1-9]"]),
    "rob": (["--faction=des"], 1200, [r"robber can rob true, barber can steal true", r"our gold \+[1-9]",
                                      r"wagon team 1"]),
    "horses": ([], 0, [r"mounted: true \(horse gone true\)", r"horses 1 / 5, cowboy on foot again true"]),
    "cattle": (["--faction=usa"], 0, [r"cow team 1", r"sold: cow gone true"]),
    "horseroom": (["--faction=usa", "--time-scale=4"], 0, [r"horse room: offered true, queued 3, horses 5 / 5, next waits true, "
                                                            r"offered when full false, queued when full false"]),
    "camouflage": (["--faction=ind"], 0, [r"after the trapper: energy"]),
    "pitfall": (["--faction=ind"], 0, [r"pit spent"]),
    "quarters": ([], 0, [r"capacity \d, quartered \d", r"hit beyond the open range: true", r"after release: quartered 0, outside (\d+) on \1 cells"]),
    "research": ([], 2100, [r"researched: \[925\] rifle 2 now:true"]),
    "liquor": (["--faction=des", "--time-scale=4"], 0, [r"liquor offered true, queued true, wood left 25, second one false",
                                                        r"liquor done: food \+40, queue empty true"]),
    "trade": (["--time-scale=4"], 0, [r"queued: truetruetrue", r"\"guns\": 24"]),
    "orders": ([], 0, [r"queued Field worker: true", r"rally flag: true"]),
    "food": ([], 300, [r"workers per field \[1, 1\]"]),
    "chain": (["--time-scale=4"], 0, [r"queued: idle worker building true with 1 waiting; cutter building true",
                                      r"chained: houses built true; then wood: idle worker true, cutter back at her tree true"]),
    # Builders of a wood store or gold warehouse gather for it once it stands; a house's go idle.
    "dropoffs": (["--time-scale=4"], 0, [r"drop-offs: wood store built true, builders on wood (\d) of \1, wood \+[1-9]\d* delivered there true; "
                                         r"gold warehouse built true, builders on gold (\d) of \2, warehoused [1-9]\d* there true; "
                                         r"house built true, its builder idle true"]),
    "groups": ([], 0, [r"group 1 recalled: 3 of 3", r"group buttons: 1,2\n",
                       r"group 2 button: building true, view [0-9]{1,2} px away, lit 2", r"group 2 key: building true"]),
    "heal": (["--faction=usa"], 0, [r"heal: life lost (\d+); healed 1[3-6]\d for 1[3-6]\d energy, energy now \d\b"]),
    "magic": ([], 0, [r"conversion: target now team 1"]),
    # Fights end when sides change: a converted soldier and his attackers, then a new ally.
    "turncoat": (["--faction=mex"], 0, [r"turncoat: hit before true, converted true; then turncoat energy kept true, ours kept true; "
                                        r"attackers on him 0, he attacks ours false",
                                        r"alliance: hit before true; then energy kept true, attackers on him 0"]),
    "spells": (["--faction=ind"], 300, [r"spells ready: 2 medicine men with Eagle eye, Lightning dance, Hail dance, Rain dance, Protective dance; our field food 300, enemy field food 300, 5 enemies"]),
    "magic_ind": (["--faction=ind"], 0, [r"eagle eye: eagles circling 1", r"lightning: enemy energy", r"warrior shielded [1-9]"]),
    "cover": ([], 0, [r"cover: .* (\d+) spots, \1 show through; in the open shows through false",
                      r"behind a wall off the cover cells shows through true"]),
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
    # Plateaus: up the ramp to one, to the foot of the cliff of one without a ramp.
    "plateau": (["--map=[2 Players] - mount gnibbelput.ulf"], 0, [r"reachable true, cut off true",
                r"cut off plateau: \d+ px short, level 0 -> 0 \(highest 0\), by a ramp false",
                r"ramped plateau: \d px short, level 0 -> 1 \(highest 1\), by a ramp true"]),
    # Ramps lie on the ground: whoever climbs one is drawn over all of it.
    "ramp": (["--map=[2 Players] - mount gnibbelput.ulf"], 0, [r"on the first (\d+) walkers, [1-9]\d* above where it stands, \1 drawn over it"]),
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
    "poplimit": (["--time-scale=4"], 0, [r"warned on filling 1, on a train order 0; queued true, held when done true, warned 1; out once room: true"]),
    "picking": ([], 0, [r"roof \(picture centre, upper third\) +-> true", r"walls centre +-> true",
                        r"open corner of the walls' box +-> false"]),
    "buildpick": ([], 0, [r"buildings \d+: [1-9]\d+ points on their pictures and outlines, 0 missed",
                          r"beside: worker takes the click on itself true, the building just off it true",
                          r"behind: worker shows through true and takes the click true"]),
    # The dead rot to bones, ruins smoulder, gulls fly over.
    "remains": ([ISLANDS], 0, [r"remains: \[.*step [12].*step [12]", r"smoke plumes: [23], after 14s 0, flyers: [1-9]"]),
    # Expansion abilities: saboteurs empty and take a fort, the warrior spirit, the armored stagecoach.
    "saboteur": (["--faction=des"], 0, [r"saboteur: garrison \[5, 2, 0, 0\], fort now player 1"]),
    "disarm": (["--faction=des"], 0, [r"disarm: trap animation true, trap now player 1 after [345]\.\d s, saboteur alive true"]),
    "scoutdisarm_trapper": (["--faction=usa", "--disarmer=461"], 0, [r"disarm by \w[\w ]*: can true, butcher animation true, trap gone true after [345]\.\d s, alive true"]),
    "scoutdisarm_militiaman": (["--faction=mex", "--disarmer=261"], 0, [r"disarm by \w[\w ]*: can true, butcher animation true, trap gone true after [345]\.\d s, alive true"]),
    "scoutdisarm_hunter": (["--faction=des", "--disarmer=358"], 0, [r"disarm by \w[\w ]*: can true, butcher animation true, trap gone true after [345]\.\d s, alive true"]),
    "scoutdisarm_archer": (["--faction=ind", "--disarmer=156"], 0, [r"disarm by \w[\w ]*: can true, butcher animation true, trap gone true after [345]\.\d s, alive true"]),
    "wall_usa": (["--faction=usa"], 0, [r"wall buttons: basic \[\], expanded \[\d+\]\n", r"wall dragged: 6 pieces placed", r"wall: planned 26 pieces, built 24 \(\w+\), all walls true; inside stays in true, outside stays out true"]),
    "wall_mex": (["--faction=mex"], 0, [r"wall buttons: basic \[\], expanded \[\d+\]\n", r"wall dragged: 6 pieces placed", r"wall: planned 26 pieces, built 24 \(\w+\), all walls true; inside stays in true, outside stays out true"]),
    "wall_des": (["--faction=des"], 0, [r"wall buttons: basic \[\], expanded \[\d+\]\n", r"wall dragged: 6 pieces placed", r"wall: planned 26 pieces, built 24 \(\w+\), all walls true; inside stays in true, outside stays out true"]),
    # Attacking round barriers (game/scripts/dev/scenarios/combat_scenarios.gd): assassins sent
    # at an enemy walled in stop outside the wall; sent the long way round the water, the
    # squad shares one search instead of each searching again and again.
    "wallattack": (["--faction=usa", "--attacker=362", "--count=30"], 0,
                   [r"barrier attack: nearest \[(9\d|1[0-4]\d), .*victim hurt false"]),
    "wallattack_far": (["--faction=usa", "--attacker=362", "--count=30", "--across=water", ISLANDS], 0,
                       [r"barrier attack: range 64, \d+ steps .*, ([1-9]|[1-5]\d) path searches"]),
    "ambush": (["--faction=des"], 0, [r"ambush: under the mound true, burst out true, then attacking true"]),
    "spirit": (["--faction=ind"], 0, [r"before upgrade false, invoked true, damage x1\.00 -> x1\.05, energy left 0, again false, auras 3",
                                      r"afterwards damage x1\.00, auras 0"]),
    "coach": (["--faction=mex"], 0, [r"aboard 2 / 2, enlarged 4 / 4, enemy hit true, guards dead with the coach 4"]),
    "saveload": ([], 0, [r"before: units (\d+)", r"after: +units \d+"]),
    # Named saves through the game menu: offered name, overwrite asked, list, delete, load.
    "savelist": ([], 0, [r"offered: .+ \d{4}-\d\d-\d\d \d\d\.\d\d\n", r"saved: menu closed true, file true",
                         r"overwrite asked true: Save over “Fort by the river”\?",
                         r"listed: Fort by the river \| Second try \| Quicksave\n", r"places: (\w[\w ]*) \| \1 \| \1\n",
                         r"after delete: Fort by the river \| Quicksave\n",
                         r"before: units (\d+), buildings (\d+)[\s\S]*after: +units \1, buildings \2"]),
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
    # The host's teams reach the client through the lobby; alliances change on the way.
    "network": ([], 0, [r"network: (1\d|[2-9]\d) of \1 checksums agree", r"client teams: \[1, 1, 0\]",
                        r"DIPLOMACY: .*\n[\s\S]*DIPLOMACY: "]),
    # The same through a dedicated server without assets: two clients, the server only relays
    # (see run_dedicated); it compares their checksums too and must find no drift.
    "dedicated": ([], 0, [r"dedicated: (1\d|[2-9]\d) of \1 checksums agree", r"Match started on .*team 2.*team 2",
                          r"Match over: the lobby is open again", r"client teams: \[2, 2, 1\] \[2, 2, 1\]"]),
    # Teams and diplomacy (game/scripts/dev/scenarios/team_scenarios.gd).
    "teamgame": (["--ai-vs-ai=1", "--players=mex,usa,ind,des", "--teams=1,1,2,2", "--time-scale=8", "--cheats=1",
                  "--map=[4 Players] - crossroads.ulf"], 0,
                 [r"teams at the start: 1:t1 2:A\+v 3:W 4:W \| 2:t1 1:A\+v 3:W 4:W \| 3:t2 1:W 2:W 4:A\+v \| 4:t2 1:W 2:W 3:A\+v",
                  r"team game: hits between allies 0, between enemies [1-9]\d*; over true",
                  r"GAME OVER: player 1 wins \(left: \[1, 2\]\)"]),
    "diplomacy": (["--players=mex,usa,ind", "--cheats=1", "--difficulty=1", "--map=[4 Players] - forts.ulf"], 0,
                  [r"diplomacy page rows: 2, menu entry true",
                   r"1 allies 2: 1:t0 2:A 3:W \| 2:t0 1:W\+v 3:W .*; 2 sees for 1 true, 1 sees for 2 false",
                   r"DIPLOMACY: .*Mexicans.*Americans",
                   r"the computer does not answer: 1:t0 2:A 3:W \| 2:t0 1:W\+v",
                   r"sent \(ours/2's/3's\): food -200/\+100/\+100, wood -200/\+100/\+100, gold -200/\+100/\+100, "
                   r"guns -4/\+2/\+2; 2's score \+6\d\d",
                   r"short of a second package: ours 50, 2's \+100",
                   r"1 declares 2 an enemy: 1:t0 2:W 3:W \| 2:t0 1:W 3:W",
                   r"3 gone, 2 not answering: game over false",
                   r"2 answered: 1:t0 2:A\+v 3:W \| 2:t0 1:A\+v .*; game over true",
                   r"GAME OVER: player 1 wins \(left: \[1, 2\]\)"]),
    "pacts": (["--players=mex,usa,ind,des", "--difficulty=3", "--time-scale=8"], 0,
              [r"pacts: 1:t0 2:W 3:W 4:W \| 2:t0 1:W 3:A\+v 4:A\+v \| 3:t0 1:W 2:A\+v 4:A\+v \| 4:t0 1:W 2:A\+v 3:A\+v"]),
    "teamsave": (["--players=mex,usa,ind,des", "--teams=1,1,2,2"], 0, [r"before: (.*)\n[\s\S]*after: +\1\n"]),
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
                             "--host=" + port, "--humans=2", "--players=mex,usa,ind", "--teams=1,1"] + common,
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
    return hosted + client + "\nnetwork: %d of %d checksums agree\nclient teams: %s\n" % (
        agree, len(shared), " ".join(re.findall(r"teams: (\[[\d, ]*\])", client)))


def run_dedicated():
    """A dedicated server (no asset folder) and two clients; compare the clients' games."""
    port = str(47900 + os.getpid() % 100)
    common = ["--scenario=commands", "--fog=off", "--checksum-every=5", "--password=check"]
    server = subprocess.Popen(["godot", "--headless", "--path", GAME, "--", "--dedicated=" + port,
                               "--password=check", "--humans=2", "--players=mex,usa,ind", "--teams=2,2,1",
                               "--assets-dir=/nonexistent"],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(2)
    clients = []
    for fps in ("60", "23"):
        clients.append(subprocess.Popen(["godot", "--headless", "--fixed-fps", fps, "--path", GAME, "--",
                                         "--join=127.0.0.1:" + port] + common,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
        time.sleep(1)  # the first in plays the first people
    played = [c.communicate(timeout=400)[0] for c in clients]
    time.sleep(1)
    server.terminate()
    served = server.communicate(timeout=30)[0]
    sums = [dict(re.findall(r"tick (\d+) checksum (\w+)", out)) for out in played]
    shared = [t for t in sums[0] if t in sums[1]]
    agree = sum(sums[0][t] == sums[1][t] for t in shared)
    if "Out of sync" in served:
        agree = 0
    teams = " ".join(" ".join(re.findall(r"teams: (\[[\d, ]*\])", out)) for out in played)
    return served + "".join(played) + "\ndedicated: %d of %d checksums agree\nclient teams: %s\n" % (
        agree, len(shared), teams)


def run(name):
    args, frames, expected = CHECKS[name]
    scenario = name.split("_")[0]
    # A fixed frame rate also stops Godot keeping to the wall clock: the run goes as fast
    # as it can, every frame one 30th of a second of game time.
    command = ["godot", "--headless", "--fixed-fps", "30", "--path", GAME]
    if name == "parse":
        command += ["--", "--selftest=parse"]
    elif name == "editor":
        command += ["--", "--editor-selftest=1"]
    elif name == "aigame":
        command += ["--", "--fog=off"] + args
    else:
        command += ["--", "--scenario=" + scenario] + BASE + args
    # Each run saves its games in a folder of its own, removed afterwards.
    saves = tempfile.TemporaryDirectory(prefix="check-saves-")
    command.append("--save-dir=" + saves.name)
    if frames:
        command.append("--report-after=%d" % frames)
    # Extra options for every run, e.g. CHECK_ARGS="--log-assets=/tmp/log".
    command += os.environ.get("CHECK_ARGS", "").split()
    started = time.time()
    try:
        out = run_replay() if name == "replay" else run_network() if name == "network" else \
            run_dedicated() if name == "dedicated" else \
            subprocess.run(command, capture_output=True, text=True, timeout=400).stdout
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        out += "\nTIMEOUT"
    saves.cleanup()
    problems = [p for p in expected if not re.search(p, out)]
    if "SCRIPT ERROR" in out:
        problems.append("script error: " + out[out.index("SCRIPT ERROR"):].split("\n", 3)[0:3].__str__())
    if "TIMEOUT" in out:
        problems.append("timed out")
    return name, problems, time.time() - started


def main():
    names = sys.argv[1:] or list(CHECKS)
    failed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=int(os.environ.get("CHECK_JOBS", 0)) or os.cpu_count() // 2 or 2) as pool:
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
