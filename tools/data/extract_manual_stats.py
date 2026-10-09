#!/usr/bin/env python3
"""Extract unit and structure stats from the original manual into game/data/stats.json.

The manual (MANUAL/USEGUIDE.PDF on the CD, converted with `pdftotext -layout`) lists every
unit and structure per faction with cost, life energy, damage, production place and
prerequisites. Entries are matched to the game's GUIDs through TEXTE.eng names.

Usage: extract_manual_stats.py <manual.txt> <TEXTE.eng> <out.json>
"""
import json
import re
import sys

SECTIONS = [  # (heading, faction, kind, GUID range)
    ("Native American units", "ind", "unit", range(150, 200)),
    ("Native American tepees", "ind", "structure", range(100, 150)),
    ("Mexican units", "mex", "unit", range(250, 300)),
    ("Mexican structures", "mex", "structure", range(200, 250)),
    ("Outlaw units", "des", "unit", range(350, 400)),
    ("Outlaw buildings", "des", "structure", range(300, 350)),
    ("American units", "usa", "unit", range(450, 500)),
    ("American structures", "usa", "structure", range(400, 450)),
]
SECTION_END = re.compile(r"^\s*(Native American|Mexican|Outlaw|American) (upgrades|units|structures|tepees|buildings)\s*$")
RESOURCE_WORDS = {"food": "food", "wood": "wood", "gold": "gold", "leather": "leather",
                  "rifle": "guns", "rifles": "guns", "gun": "guns", "guns": "guns", "horse": "horses"}


def load_texts(path):
    texts = {}
    for line in open(path, encoding="latin1"):
        key, _, value = line.strip().partition("=")
        if key.isdigit():
            texts.setdefault(int(key), value.strip())
    return texts


ALIASES = {  # manual wording -> TEXTE.eng wording
    "animalprocessingfacility": "animalprocessing",
    "woodprocessingfacility": "woodprocessing",
    "basement": "cellar",
    "slaughterhouse": "stockyard",
}


def normalize(name):
    key = re.sub(r"[^a-z]", "", name.lower())
    return ALIASES.get(key, key)


def parse_cost(text):
    text = re.sub(r"\(mounted[^)]*\)", "", text)  # optional horse when mounted
    cost = {}
    text = re.sub(r"(\d+)\s+units? of\s+", r"\1 ", text.lower())  # "250 units of wood"
    for amount, word in re.findall(r"(\d+)\s+([a-z]+)", text):
        key = RESOURCE_WORDS.get(word)
        if key:
            cost[key] = cost.get(key, 0) + int(amount)
    living = re.search(r"(\d+)\s+living space", text.lower())
    if living:
        cost["population"] = int(living.group(1))
    return cost


def parse_damage(text):
    numbers = [int(n) for n in re.findall(r"\d+", text)]
    return numbers[0] if numbers else 0


def sections(lines):
    for heading, faction, kind, guids in SECTIONS:
        start = next(i for i, l in enumerate(lines) if l.strip() == heading)
        end = next((i for i in range(start + 1, len(lines)) if SECTION_END.match(lines[i])), len(lines))
        yield faction, kind, guids, lines[start + 1:end]


def entries(block):
    """Split a section into (name, {field: value}) at lines followed by a known field."""
    fields = ("Place of production", "Prerequisites", "Cost", "Life energy", "Energy",
              "Damage per blow", "Function")
    current, out = None, []
    for i, raw in enumerate(block):
        line = raw.strip()
        if not line:
            continue
        nxt = next((block[j].strip() for j in range(i + 1, min(i + 4, len(block))) if block[j].strip()), "")
        if not any(line.lower().startswith(f.lower() + ":") for f in fields) and \
                any(nxt.lower().startswith(f.lower() + ":") for f in fields) and len(line) < 40 \
                and not line.startswith("(") and not line.lower().startswith("cost"):
            current = [line, {}]
            out.append(current)
            continue
        if current is None:
            continue
        for f in fields:
            if line.lower().startswith(f.lower() + ":"):
                current[1][f] = line.split(":", 1)[1].strip()
                last = f
                break
        else:
            if current[1] and last in ("Cost", "Function", "Prerequisites") and not line.startswith("•"):
                current[1][last] += " " + line
    return out


def main():
    manual, texts_path, out_path = sys.argv[1:4]
    lines = open(manual, encoding="utf-8", errors="replace").read().splitlines()
    texts = load_texts(texts_path)
    stats, unmatched = {}, []
    for faction, kind, guids, block in sections(lines):
        names = {normalize(texts[g]): g for g in guids if g in texts}
        for name, f in entries(block):
            guid = names.get(normalize(name))
            if guid is None:
                unmatched.append(f"{faction}:{name}")
                continue
            entry = {"name": texts[guid], "faction": faction, "kind": kind,
                     "cost": parse_cost(f.get("Cost", ""))}
            if "Life energy" in f or "Energy" in f:
                entry["health"] = parse_damage(f.get("Life energy", f.get("Energy", "")))
            if "Damage per blow" in f:
                entry["damage"] = parse_damage(f["Damage per blow"])
            if "Place of production" in f:
                place = normalize(f["Place of production"])
                entry["produced_at"] = next((g for n, g in
                                             {normalize(texts[x]): x for x in range(100, 450) if x in texts}.items()
                                             if n == place), f["Place of production"])
            residence = re.search(r"Residence for\s+(\d+)\s+units", f.get("Function", ""))
            if residence:
                entry["housing"] = int(residence.group(1))
            if "Prerequisites" in f and f["Prerequisites"].lower() != "none":
                entry["prerequisites"] = f["Prerequisites"]
            stats[guid] = entry
    with open(out_path, "w") as out:
        json.dump({str(k): v for k, v in sorted(stats.items())}, out, indent=1, ensure_ascii=False)
    print(f"{len(stats)} entries; unmatched: {unmatched}")


if __name__ == "__main__":
    main()
