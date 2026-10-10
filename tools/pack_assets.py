#!/usr/bin/env python3
"""Copies the asset folder for a release build, storing colour pictures as lossless WebP.

    tools/pack_assets.py [--trim=<pixels>] <assets folder> <destination folder>

RGB and RGBA PNGs become <name>.webp with the very same pixels (including the colour under
transparent pixels), about half the size; the game reads <name>.webp wherever it asks for
<name>.png that is missing. Grey pictures (shadows, team masks) stay PNG: WebP has no grey
format, so the game would hold them at four times the memory. Everything else is copied.
--trim=<pixels> blacks out the colour under transparent pixels farther than that from any
visible one (it only shows when a picture is drawn much smaller than it is stored), so it
packs smaller. Needs ImageMagick (magick) with WebP support.
"""
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

PNG_RGB, PNG_RGBA = 2, 6


def colour_png(path: str) -> bool:
    with open(path, "rb") as f:
        header = f.read(26)
    return header[:8] == b"\x89PNG\r\n\x1a\n" and header[25] in (PNG_RGB, PNG_RGBA)


def to_webp(source: str, target: str, trim: int) -> None:
    cleanup = []
    if trim > 0:
        # Alpha becomes "visible pixel within trim", transparent pixels outside it turn
        # black, then the real alpha goes back on.
        cleanup = ["(", "+clone", "-alpha", "extract", "-threshold", "0",
                   "-morphology", "Dilate", f"Disk:{trim}", ")",
                   "-compose", "CopyOpacity", "-composite", "-background", "black",
                   "-alpha", "background", "-alpha", "on",
                   "(", source, "-alpha", "extract", ")", "-compose", "CopyOpacity", "-composite"]
    subprocess.run(
        ["magick", source, *cleanup, "-define", "webp:lossless=true", "-define", "webp:exact=true",
         "-define", "webp:method=4", "-quality", "100", target],
        check=True)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--trim=")]
    trims = [int(a.split("=", 1)[1]) for a in sys.argv[1:] if a.startswith("--trim=")]
    if len(args) != 2:
        sys.exit(__doc__)
    source_root, target_root = args
    trim = trims[-1] if trims else 0
    jobs = []
    for folder, _, files in os.walk(source_root, followlinks=True):
        out = os.path.join(target_root, os.path.relpath(folder, source_root))
        os.makedirs(out, exist_ok=True)
        for name in files:
            source = os.path.join(folder, name)
            if name.endswith(".png") and colour_png(source):
                jobs.append((source, os.path.join(out, name[:-4] + ".webp")))
            else:
                shutil.copy2(source, os.path.join(out, name))
    done = 0
    with ThreadPoolExecutor(os.cpu_count()) as pool:
        for _ in pool.map(lambda job: to_webp(*job, trim), jobs):
            done += 1
            print(f"\r{done}/{len(jobs)} pictures", end="", flush=True)
    print()


if __name__ == "__main__":
    main()
