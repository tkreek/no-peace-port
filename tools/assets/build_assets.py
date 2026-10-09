#!/usr/bin/env python3
"""Build the game's asset folder from the original installation and the upscaled set.

Usage: tools/assets/build_assets.py [--original original] [--out assets]

Reads the original archives (base game and expansion), maps and music from
<original>/install/Programm and <original>/expansion/install/Programm, and the upscaled
graphics from <original>/hd (tools/upscale/*). Writes an English-named, Godot-friendly copy
of everything the game uses:

  data/         JSON tables: object types, GUIDs, game constants, texts, editor defaults,
                sounds, terrain rules
  units/ animals/ buildings/ nature/ effects/ interface/
                sprite sheets (<name>.png + .json frames [+ .team.png team-colour mask]),
                animation sets (<name>.anims.json, replacing the original .bob files) and
                their team colour ramps (<name>.ramps.png)
  portraits/    command and selection pictures (PNG)
  terrain/      per landscape: atlas index and palette, upscaled tiles and ground textures,
                minimap colours, painting rules
  sounds/ music/
  maps/         skirmish maps (.ulf, zlib-packed)
  manifest.json original path -> asset path
  REPORT.md     what was left out (and why), untranslated words, name clashes

The game reads only this folder. Graphics come from the upscaled set alone; the original
pictures and palettes are not copied.
"""
import argparse
import collections
import json
import os
import re
import shutil
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "formats"))
sys.path.insert(0, HERE)
from rd_archive import GameFiles, normalize  # noqa: E402
from rd_chunks import read_chunks  # noqa: E402
import glossary  # noqa: E402

# Files the game's code loads by name (original paths), beyond what the data tables name.
CODE_ANIMS = [
    "global/gfx/explosion/explosiv.bob", "global/gfx/usa/zeiger/zeiger.bob",
    "global/gfx/positionsfahne/positionsfahne.bob", "global/gfx/blitzwolke/wolke_blitz.bob",
    "global/gfx/hagelwolke/hagel.bob", "global/gfx/regenwolke/regen.bob",
    "global/gfx/schutzschirm/schutzschirm.bob", "global/gfx/feuer/fire.bob",
    "global/gfx/status/resourcenicons/resourcenicons.bob",
]
CODE_SHEETS = [
    "global/gfx/status/leiste/bilderliste__1.spr", "global/gfx/menues/main/bilderliste__1.spr",
    "global/gfx/menues/selectgame/piclist00.spr", "global/gfx/usa/sonstigeicons/sonstigeicons.spr",
    "global/gfx/usa/sonstigeicons/iconserstereihe.spr", "global/gfx/usa/sonstigeicons/kleineicons.spr",
    "global/gfx/usa/icons/einheiten/usaeinheiten.spr",
]
CODE_IMAGES = [
    "global/gfx/menues/main/mainmenu2.pic", "global/gfx/menues/main/mainmenu.pic",
    "global/gfx/menues/selectgame/selectgame.pic", "global/gfx/ladebild/ladebild2.pic",
    "global/gfx/ladebild/ladebild1024768.pic", "global/gfx/status/leiste/leisterechts.pic",
]
# Data tables: the expansion's version where it has one.
TABLES = {
    "object_types": ["global/guids2/bobliste2.blf", "bobliste.blf"],
    "guids_prairie": ["global/guids2/guids.ini", "global/guids/guids.ini"],
    "guids_meadow": ["global/guids2/guids2.ini", "global/guids/guids2.ini"],
    "defs": ["global/guids2/defs.ini", "global/guids/defs.ini"],
}
TEXTS = ["global/guids2/texte-add-on.eng", "global/guids2/text2-add-on.eng",
         "global/guids/texte.eng", "global/guids/text2.eng"]
MENU_TEXTS = ["global/guids2/menu.eng", "global/guids/menu.eng"]
DEFS_KEYS = {"Sichtweite": "sight_range", "ReichweiteFernwaffe": "ranged_range",
             "MindestReichweite": "min_range", "KampffrequenzNah": "melee_rate",
             "KampffrequenzFern": "ranged_rate", "LaufenSpeed": "walk_speed",
             "Nahrung": "start_food", "Holz": "start_wood", "Leder": "start_leather",
             "Gold": "start_gold", "Gewehre": "start_guns"}
MUSIC = {"tit": "title", "usa": "americans", "mex": "mexicans", "ind": "natives", "des": "outlaws",
         "abr": "statistics", "briefing": "briefing", "credits": "credits", "credits2": "credits_expansion"}


class Builder:
    def __init__(self, original, out):
        self.original = original
        self.out = out
        self.hd = os.path.join(original, "hd")
        self.install = os.path.join(original, "install", "Programm")
        self.addon = os.path.join(original, "expansion", "install", "Programm")
        self.files = GameFiles(self.install, self.addon if os.path.isdir(self.addon) else None)
        self.manifest = {}          # original (normalized) -> asset path
        self.taken = {}             # asset path -> original
        self.untranslated = collections.Counter()
        self.clashes = []
        self.missing = []           # (original, reason)
        self.used = set()           # original files consumed (incl. those converted)

    # ------------------------------------------------------------ naming

    def word(self, w):
        if w.isdigit():
            return w
        if w in glossary.WORDS:
            return glossary.WORDS[w]
        if w not in KNOWN_ENGLISH:
            self.untranslated[w] += 1
        return w

    def name(self, stem):
        """Translate one file or folder name (no extension) into snake_case English."""
        s = stem.lower()
        for phrase, english in glossary.PHRASES.items():
            before = r"(?<=_)" if phrase.startswith("_") else r"(?<![a-zäöüß])"
            s = re.sub(before + re.escape(phrase.lstrip("_")) + r"(?![a-zäöüß])", " " + english.lstrip("_") + " ", s)
        words = re.findall(r"[a-zäöüß]+|\d+", s)
        out = [self.word(w) for w in words]
        text = "_".join(w for w in out if w)
        return re.sub(r"_+", "_", text).strip("_") or "unnamed"

    def path(self, original, extension=None, suffix=""):
        """Asset path (without the root) for an original path: folders renamed, every name
        translated, `suffix` added to the file name and `extension` (when given) replacing
        its own. Registered in the manifest; clashing names get a number."""
        key = normalize(original)
        base, rest = "", key
        for prefix, new in glossary.FOLDERS:
            if key == prefix or key.startswith(prefix + "/"):
                base, rest = new, key[len(prefix) + 1:]
                break
        parts = rest.split("/") if rest else []
        folders = [self.name(p) for p in parts[:-1]]
        stem, ext = os.path.splitext(parts[-1]) if parts else ("", "")
        name = self.name(stem)
        if suffix and not name.endswith(suffix):
            name += suffix
        new = "/".join([p for p in [base] + folders if p] + [name + (extension if extension is not None else ext)])
        if new in self.taken and self.taken[new] != key:
            folder, base = os.path.split(new)
            dot = base.find(".") if extension != "" else -1
            root, ext2 = (os.path.join(folder, base[:dot]), base[dot:]) if dot > 0 else (new, "")
            n = 2
            while f"{root}_{n}{ext2}" in self.taken:
                n += 1
            self.clashes.append((key, self.taken[new], f"{root}_{n}{ext2}"))
            new = f"{root}_{n}{ext2}"
        self.taken[new] = key
        self.manifest[key] = new
        return new

    # ------------------------------------------------------------ output helpers

    def write(self, rel, data):
        target = os.path.join(self.out, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        mode = "w" if isinstance(data, str) else "wb"
        with open(target, mode, **({"encoding": "utf-8"} if mode == "w" else {})) as f:
            f.write(data)

    def write_json(self, rel, value):
        self.write(rel, json.dumps(value, ensure_ascii=False, separators=(",", ":")))

    def copy(self, source, rel):
        target = os.path.join(self.out, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(source, target)

    def read(self, original):
        self.used.add(normalize(original))
        return self.files.read(original)

    def read_first(self, candidates):
        for c in candidates:
            if self.files.exists(c):
                return self.read(c)
        raise KeyError(candidates[0])

    # ------------------------------------------------------------ graphics

    def sheet(self, original):
        """Copy the upscaled version of a sprite sheet; returns its asset base path or None."""
        key = normalize(original)
        hd = os.path.join(self.hd, key)
        if not os.path.exists(hd + ".json"):
            self.missing.append((key, "no upscaled version"))
            return None
        if key in self.manifest:
            return self.manifest[key]
        self.used.add(key)
        rel = self.path(key, "", "_shadow" if key.endswith(".shw") else "")
        meta = json.load(open(hd + ".json"))
        self.write_json(rel + ".json", meta)
        self.copy(hd + ".png", rel + ".png")
        if meta.get("team") and os.path.exists(hd + ".team.png"):
            self.copy(hd + ".team.png", rel + ".team.png")
        return rel

    def anims(self, bob_path):
        """Convert a .bob animation set; returns its asset path (.anims.json) or None."""
        key = normalize(bob_path)
        if key + "#anims" in self.manifest:
            return self.manifest[key + "#anims"]
        if not self.files.exists(key):
            self.missing.append((key, "animation set not in the archives"))
            return None
        text = self.read(key).decode("latin1")
        directory = os.path.dirname(key)
        sheets, anims, section, current, palettes = [], [], None, None, 0
        for raw in text.splitlines():
            line = raw.strip()
            if line.startswith("ColTab#"):
                section = "palette"
                palettes += 1
            elif line.startswith("SubSpriteFile#"):
                section = "sheet"
                sheets.append({"file": "", "shadow": False})
            elif line.startswith("AnimBlock#"):
                section = "anim"
                current = {"sheet": 0, "directions": 1, "frames_per_direction": 1, "frames": [],
                           "durations": [], "loop_back": 1}
                anims.append(current)
            elif "=" in line and section:
                k, v = line.split("=", 1)
                v = v.strip()
                if section == "sheet" and k == "Filename":
                    sheets[-1]["file"] = v
                elif section == "sheet" and k == "Typ":
                    sheets[-1]["shadow"] = v == "DARK"
                elif section == "anim" and k == "SubSpriteFile":
                    current["sheet"] = int(v)
                elif section == "anim" and k == "AnzDirections":
                    current["directions"] = int(v)
                elif section == "anim" and k == "AnzFramesProAnim":
                    current["frames_per_direction"] = int(v)
                elif section == "anim" and k == "AnimList":
                    numbers = [int(n) for n in v.split(",") if n.strip().lstrip("-").isdigit()]
                    i = 0
                    while i < len(numbers):
                        if numbers[i] < 0:
                            current["loop_back"] = -numbers[i]
                            break
                        current["frames"].append(numbers[i])
                        current["durations"].append(numbers[i + 1] if i + 1 < len(numbers) else 100)
                        i += 2
        out_sheets = []
        for s in sheets:
            rel = self.sheet(directory + "/" + s["file"].replace("\\", "/")) if s["file"] else None
            out_sheets.append({"file": rel or "", "shadow": s["shadow"], "original": s["file"]})
        rel = self.path(key, ".anims.json")
        self.manifest[key + "#anims"] = rel
        for s in out_sheets:  # sheets by path relative to the animation set
            if s["file"]:
                s["file"] = os.path.relpath(s["file"], os.path.dirname(rel))
        ramps = os.path.join(self.hd, key + ".ramps.png")
        has_ramps = os.path.exists(ramps)
        if has_ramps:
            self.copy(ramps, rel.replace(".anims.json", ".ramps.png"))
        # "teams": colour rows (base + team variants) the original had, i.e. how many players
        # the set can be tinted for (1 = not team-coloured).
        self.write_json(rel, {"sheets": out_sheets, "anims": anims, "ramps": has_ramps, "teams": max(1, palettes)})
        return rel

    def image(self, original):
        """Upscaled still picture as PNG; returns its asset path or None."""
        key = normalize(original)
        hd = os.path.join(self.hd, key + ".png")
        if not os.path.exists(hd):
            self.missing.append((key, "no upscaled version"))
            return None
        if key in self.manifest:
            return self.manifest[key]
        self.used.add(key)
        rel = self.path(key, ".png")
        self.copy(hd, rel)
        return rel

    # ------------------------------------------------------------ data tables

    def object_types(self):
        d = self.read_first(TABLES["object_types"])
        capacity = struct.unpack_from("<I", d, 4)[0]
        bobs = [d[8 + i * 88 + 4:8 + i * 88 + 84].split(b"\0")[0].decode("latin1").replace("\\", "/").lower()
                for i in range(capacity)]
        pos, types = 8 + capacity * 88, []
        while pos + 0x104 + 32 <= len(d):
            bary = pos + 0x104
            name = d[pos:pos + 0x50].split(b"\0")[0].decode("latin1")
            kind = struct.unpack_from("<I", d, pos + 0x54)[0]
            entry = {"id": len(types), "name": self.type_name(name), "original_name": name, "kind": 0,
                     "anims": "", "anim": 0, "shadow_anim": -1}
            if kind == 0xFFFFFFFF:
                types.append(entry)
                pos = bary
                continue
            if d[bary:bary + 4] != b"BARY":
                break
            bob_id = struct.unpack_from("<I", d, pos + 0x50)[0]
            bob = bobs[bob_id] if bob_id < len(bobs) else ""
            anim, shadow = struct.unpack_from("<ii", d, pos + 0x6C)
            ax, ay, w, h, cols, rows, count = struct.unpack_from("<iiIIIII", d, bary + 4)
            cells = list(struct.unpack_from(f"<{count}I", d, bary + 32))
            entry.update({"kind": kind, "anim": anim, "shadow_anim": shadow,
                          "footprint": {"anchor": [ax, ay], "size": [w, h], "grid": [cols, rows], "cells": cells}})
            if bob and not bob.startswith("editor"):
                entry["anims"] = self.anims(bob) or ""
            types.append(entry)
            pos = bary + 32 + count * 4
        self.write_json("data/object_types.json", types)
        return types

    def type_name(self, name):
        """English type name; riding versions ("+Pferd") end in _mounted."""
        n = name.replace("+Pferd", "_mounted").replace("BefehlshPferd", "Befehlshaber_mounted")
        return self.name(n.replace("+", "_").replace(".", "_"))

    def ini_pairs(self, data):
        for line in data.decode("latin1").splitlines():
            clean = line.split("//")[0].strip()
            if "=" in clean:
                k, v = clean.split("=", 1)
                yield k.strip(), v.strip()

    def tables(self):
        guids = {}
        for table in ("guids_prairie", "guids_meadow"):
            for k, v in self.ini_pairs(self.read_first(TABLES[table])):
                if k.lstrip("-").isdigit() and v.lstrip("-").isdigit():
                    guids[k] = int(v)
        self.write_json("data/guids.json", guids)
        defs = {}
        for k, v in self.ini_pairs(self.read_first(TABLES["defs"])):
            m = re.match(r"([A-Za-zäöü]+?)(Werte)?(\d*)$", k)
            if not m or not v.lstrip("-").isdigit():
                continue
            base = DEFS_KEYS.get(m.group(1), m.group(1))
            if m.group(2):
                continue  # the number of tiers, implied by the lists
            if m.group(3):
                defs.setdefault(base, [])
                index = int(m.group(3))
                while len(defs[base]) <= index:
                    defs[base].append(0)
                defs[base][index] = int(v)
            else:
                defs[base] = int(v)
        self.write_json("data/defs.json", defs)
        for out, files in (("data/texts.json", TEXTS), ("data/menu_texts.json", MENU_TEXTS)):
            texts = {}
            for f in files:
                if not self.files.exists(f):
                    continue
                for line in self.read(f).decode("latin1").replace("\r", "").split("\n"):
                    k = line.split("=", 1)[0].strip()
                    if "=" in line and k.isdigit() and k not in texts:
                        texts[k] = line[line.find("=") + 1:].strip()
            self.write_json(out, texts)

    def defaults(self):
        """Defaults.dat (the expansion editor's object data) -> data/defaults.json."""
        if not self.files.exists("defaults.dat"):
            self.missing.append(("defaults.dat", "expansion missing"))
            return
        text = self.read("defaults.dat").decode("latin1")
        factions = {"1910": "ind", "1911": "mex", "1912": "des", "1913": "usa"}
        kinds = {"2182": "structure", "2183": "unit", "2184": "upgrade", "2185": "hero"}
        fixes = {"Gewehr 2|923": 926}
        out, faction, kind, depth, group_depth, current, current_depth = {}, "", "", 0, {}, None, -1

        def label(line):
            return line.split("|", 1)[1].split('"', 1)[0] if "|" in line else ""
        for raw in text.splitlines():
            line = raw.strip()
            if line == "{":
                depth += 1
                continue
            if line == "}":
                if depth == current_depth:
                    current, current_depth = None, -1
                g = group_depth.pop(depth - 1, None)
                if g == "faction":
                    faction = ""
                elif g == "kind":
                    kind = ""
                depth -= 1
                continue
            if line.startswith(("GROUP", "NEUTRALGROUP", "HIDDENGROUP")):
                ident = label(line)
                if ident in factions:
                    faction = factions[ident]
                    group_depth[depth] = "faction"
                elif ident in kinds:
                    kind = kinds[ident]
                    group_depth[depth] = "kind"
                continue
            if line.startswith("UNIT"):
                quoted = line.split('"')[1]
                ident = label(line)
                guid = fixes.get(quoted, int(ident) if ident.isdigit() else 0)
                name = quoted.split("|")[0]
                if ". " in name:
                    name = name[name.find(" ") + 1:]
                fields = line.split('"')[2].split()
                current = {"name_de": name, "faction": faction, "kind": kind, "properties": {},
                           "values": {}, "types": [int(f) for f in fields[4:] if f.lstrip("-").isdigit()]}
                out[str(guid)] = current
                current_depth = depth + 1
                continue
            if current is None:
                continue
            if line.startswith("BILD"):
                icon = line.split('"')[1].replace("\\", "/")
                current["icon"] = self.image(icon) or ""
                continue
            parts = line.split()
            if len(parts) >= 4 and parts[0].isdigit() and parts[1] in "+-" and parts[3].lstrip("-").isdigit():
                current["values"][parts[0]] = int(parts[3])
                if parts[1] == "+":
                    current["properties"][parts[0]] = int(parts[3])
        self.write_json("data/defaults.json", out)

    def sounds(self):
        d = self.read("sfx/sfxguids.dat")
        count = struct.unpack_from("<I", d, 4)[0]
        pos, sounds = 8, {}
        for _ in range(count):
            ident, volume = struct.unpack_from("<II", d, pos)
            path = d[pos + 8:pos + 108].split(b"\0")[0].decode("latin1")
            rel = self.sound(path)
            if rel:
                sounds[str(ident)] = {"file": rel, "volume": volume}
            pos += 108
        objects = struct.unpack_from("<I", d, pos)[0]
        pos += 4
        events = {}
        for _ in range(objects):
            guid, n = struct.unpack_from("<II", d, pos)
            table = {}
            for k in range(min(n, 20)):
                event = struct.unpack_from("<I", d, pos + 8 + k * 4)[0]
                sound = struct.unpack_from("<I", d, pos + 88 + k * 4)[0]
                table.setdefault(str(event), []).append(sound)
            events[str(guid)] = table
            pos += 168
        for extra in ("sfx/missions/gewonnen.mp3", "sfx/missions/verloren.mp3"):
            self.sound(extra)
        self.write_json("data/sounds.json", {"sounds": sounds, "events": events})

    def sound(self, original):
        key = normalize(original)
        if not self.files.exists(key):
            self.missing.append((key, "sound named by the sound table but not in the archives"))
            return None
        if key in self.manifest:
            return self.manifest[key]
        rel = self.path(key)
        self.write(rel, self.read(key))
        return rel

    # ------------------------------------------------------------ terrain, maps, music

    def terrain(self, biome, english):
        directory = f"{biome}/gfx/landschaft"
        data = self.read(f"{directory}/steppe.pic")
        width, height = struct.unpack_from("<II", data, 4)
        palette = list(data[20:20 + 768])
        pixels = data[24 + 768:24 + 768 + width * height]
        out = f"terrain/{english}"
        self.write(f"{out}/atlas_index.png", png_gray(width, height, pixels))
        self.write_json(f"{out}/atlas_palette.json", palette)
        mini = self.read(f"{directory}/minimap.pic")
        colors = bytearray()
        for i in range((len(mini) - 20) // 2):
            v = struct.unpack_from("<H", mini, 20 + i * 2)[0]
            r, g, b = (v >> 10) & 31, (v >> 5) & 31, v & 31
            colors += bytes([(r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2)])
        self.write(f"{out}/minimap_colors.png", png_rgb(len(colors) // 3, 1, bytes(colors)))
        hd = os.path.join(self.hd, "terrain", biome)
        for f in sorted(os.listdir(hd)):
            self.copy(os.path.join(hd, f), f"{out}/{f}")
        gfs = "steppe.gfs" if biome == "steppe" else "wiese.gfs"
        if self.files.exists(gfs):
            self.write_json(f"{out}/rules.json", terrain_rules(self.read(gfs)))
        else:
            self.missing.append((gfs, "expansion missing: the map editor cannot paint terrain"))
        for name in self.files.names():
            if name.startswith(directory + "/"):
                self.manifest.setdefault(name, out)

    def maps(self):
        seen = {}
        for directory in (os.path.join(self.addon, "Levels"), os.path.join(self.install, "Levels")):
            if not os.path.isdir(directory):
                continue
            for f in sorted(os.listdir(directory)):
                if not f.lower().endswith((".alf", ".ulf")):
                    continue
                title = os.path.splitext(f)[0]
                rel = f"maps/{title}.ulf"
                self.manifest[f"levels/{f.lower()}"] = rel
                if title.lower() in seen:
                    continue  # the expansion's update of a base map wins
                seen[title.lower()] = f
                self.write(rel, repack_map(os.path.join(directory, f)))

    def music(self):
        for directory in (os.path.join(self.install, "Music"), os.path.join(self.addon, "Music")):
            if not os.path.isdir(directory):
                continue
            for f in sorted(os.listdir(directory)):
                stem = os.path.splitext(f)[0].lower()
                rel = f"music/{MUSIC.get(stem, self.name(stem))}.mp3"
                self.manifest[f"music/{f.lower()}"] = rel
                self.copy(os.path.join(directory, f), rel)

    def extras(self):
        """Graphics and sounds nothing uses yet but a later feature may (corpses rotting,
        smoke, gulls, dying voices ...): every remaining animation set with upscaled
        sheets, and the sounds outside the campaign."""
        skip = ("global/gfx/menues", "kampagne", "editor_daten", "global/guids")
        for name in sorted(self.files.names()):
            if name in self.manifest or name.startswith(skip):
                continue
            if name.endswith(".bob"):
                text = self.files.read(name).decode("latin1")
                sheets = [line.split("=", 1)[1].strip() for line in text.splitlines()
                          if line.strip().startswith("Filename") and not line.strip().endswith(".ftb")]
                folder = os.path.dirname(name)
                if sheets and all(os.path.exists(os.path.join(self.hd, normalize(folder + "/" + s)) + ".json") for s in sheets):
                    self.anims(name)
            elif name.startswith(("sfx/static", "sfx/voices")) and name.endswith((".wav", ".mp3")):
                self.sound(name)

    def portraits(self):
        for name in sorted(self.files.names()):
            if name.startswith("potraits/") and name.endswith(".bmp") and name not in self.manifest:
                self.image(name)

    # ------------------------------------------------------------ report

    def report(self):
        left = collections.defaultdict(list)
        for name in sorted(set(self.files.names())):
            if name in self.used or name in self.manifest:
                continue
            left[why_left_out(name)].append(name)
        lines = ["# Asset build report", "",
                 "Generated by `tools/assets/build_assets.py`. Original files the game does not use",
                 "(yet), upscaled pictures that were missing, untranslated words and name clashes.", ""]
        lines += ["## Left out", ""]
        for reason in sorted(left, key=lambda r: -len(left[r])):
            names = left[reason]
            lines.append(f"### {reason} ({len(names)})")
            lines.append("")
            folders = collections.Counter(os.path.dirname(n) or "(root)" for n in names)
            for folder, count in sorted(folders.items()):
                sample = [os.path.basename(n) for n in names if (os.path.dirname(n) or "(root)") == folder][:6]
                lines.append(f"- `{folder}/` {count}: {', '.join(sample)}{' …' if count > 6 else ''}")
            lines.append("")
        lines += ["## Missing", ""] + [f"- `{k}`: {why}" for k, why in sorted(set(self.missing))] + [""]
        lines += ["## Untranslated words", "",
                  "Kept as they are in asset names; add them to `tools/assets/glossary.py`.", ""]
        lines += [", ".join(f"{w} ({c})" for w, c in sorted(self.untranslated.items()))] + [""]
        lines += ["## Name clashes", ""] + [f"- `{a}` and `{b}` -> `{new}`" for a, b, new in self.clashes] + [""]
        self.write("REPORT.md", "\n".join(lines))
        self.write_json("manifest.json", dict(sorted(self.manifest.items())))
        return left

    def build(self):
        if os.path.isdir(self.out):
            shutil.rmtree(self.out)
        os.makedirs(self.out)
        self.tables()
        self.object_types()
        for bob in CODE_ANIMS:
            self.anims(bob)
        for sheet in CODE_SHEETS:
            self.sheet(sheet)
        for image in CODE_IMAGES:
            self.image(image)
        self.defaults()
        self.portraits()
        self.sounds()
        self.extras()
        self.terrain("steppe", "prairie")
        self.terrain("wiese", "meadow")
        self.maps()
        self.music()
        left = self.report()
        print(f"{len(self.manifest)} entries in the manifest; {sum(len(v) for v in left.values())} original "
              f"files left out; {len(self.missing)} missing; {len(self.untranslated)} untranslated words; "
              f"{len(self.clashes)} clashes")


KNOWN_ENGLISH = set()
for _v in glossary.WORDS.values():
    KNOWN_ENGLISH.update(_v.split("_"))
for _v in glossary.PHRASES.values():
    KNOWN_ENGLISH.update(_v.split("_"))
KNOWN_ENGLISH.update(glossary.NAMES)
KNOWN_ENGLISH.update(["a", "b", "c", "d", "e", "x", "y", "z", "lt", "capt", "st", "spx", "bmp", "pic"])


def why_left_out(name):
    n = name.lower()
    ext = os.path.splitext(n)[1]
    if ext == ".ftb":
        return "Palettes (the upscaled graphics carry their own colours)"
    if ext in (".spx", ".shw", ".spr", ".pic", ".bmp") and not n.startswith(("global/gfx/menues", "potraits")):
        return "Original pictures of graphics the upscaled set replaces, or not used"
    if ext == ".mod":
        return "Campaign AI modules (kimodules), not used"
    if n.startswith(("kampagne", "global/gfx/menues/kampagne", "global/gfx/menues/selectkampagne",
                     "global/gfx/menues/selectmission", "global/gfx/menues/mission")) or "kampagne" in n or "mission" in n:
        return "Campaign and missions, not implemented"
    if any(m in n for m in ("/multi", "/net", "verbindung", "chat", "selectnetname", "selectplayer", "accept", "ingamemulti")):
        return "Multiplayer menus, not implemented"
    if n.startswith("global/gfx/menues"):
        return "Other original menu screens (the game draws its own)"
    if "font" in n:
        return "Bitmap fonts (the game uses a system serif)"
    if "credits" in n or "logos" in n:
        return "Credits and logos"
    if ext in (".wav", ".mp3"):
        return "Sounds the sound table does not name"
    if n.startswith("potraits"):
        return "Portraits without an upscaled version"
    if n.startswith("editor_daten") or "leveled" in n:
        return "Level editor data (the map editor uses its own)"
    if ext in (".ini", ".def", ".bin", ".dat", ".blf", ".eng", ".cfg", ".tmp", ".prj"):
        return "Other data files (superseded tables, ids, rules.def tech tree, editor configs)"
    if ext == ".bob":
        return "Animation sets no object type or code uses"
    return "Other"


# ------------------------------------------------------------ format helpers

def png_gray(width, height, pixels):
    raw = b"".join(b"\0" + pixels[y * width:(y + 1) * width] for y in range(height))
    return _png(width, height, 0, raw)


def png_rgb(width, height, rgb):
    raw = b"".join(b"\0" + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))
    return _png(width, height, 2, raw)


def _png(width, height, colour_type, raw):
    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, colour_type, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def repack_map(path):
    """A level file with every chunk zlib-packed (as the expansion editor writes them)."""
    data = open(path, "rb").read()
    out = bytearray(data[:0x20])
    for name, body in read_chunks(path):
        packed = zlib.compress(body, 9)
        header = name.encode("latin1")[:8].ljust(8, b"\0")
        start = len(out)
        out += header + struct.pack("<III", start + 16 + 4 + len(packed), 2, len(body)) + packed
    return bytes(out)


def terrain_rules(data):
    """The level editor's terrain rules (.gfs) as JSON (see game/scripts/formats/terrain_rules.gd)."""
    n = (len(data) - 0xA8) // 4
    v = list(struct.unpack_from(f"<{n}i", data, 0xA8))
    flags = v[840:30840]
    materials = []
    for k in range(18):
        o = 0xA8 + 4 * (30840 + k * 623) + 16
        materials.append(data[o:o + 64].split(b"\0")[0].decode("latin1").split("#")[0])
    records, i = [], 42056
    while i + 7 <= n:
        if v[i] == 0 and i + 1 < n and v[i + 1] == 1:
            i += 1
            continue
        if v[i] != 1:
            break
        variants, a, b, w, h, code = v[i + 1:i + 7]
        grids = [v[i + 7 + 64 * k:i + 7 + 64 * (k + 1)] for k in range(variants)]
        records.append({"a": a, "b": b, "size": [w, h], "shape": code, "grids": grids})
        i += 7 + 64 * variants
    return {"materials": materials, "flags": flags, "blocks": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--original", default=os.path.join(ROOT, "original"))
    parser.add_argument("--out", default=os.path.join(ROOT, "assets"))
    args = parser.parse_args()
    Builder(args.original, args.out).build()


if __name__ == "__main__":
    main()
