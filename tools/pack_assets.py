#!/usr/bin/env python3
"""Copies the asset folder for a release build, storing colour pictures as lossless WebP.

    tools/pack_assets.py <assets folder> <destination folder>

RGB and RGBA PNGs become <name>.webp with the very same pixels (including the colour under
transparent pixels), about half the size; the game reads <name>.webp wherever it asks for
<name>.png that is missing. Grey pictures (shadows, team masks) stay PNG: WebP has no grey
format, so the game would hold them at four times the memory. Everything else is copied.
Needs ImageMagick (magick) with WebP support.
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


def to_webp(source: str, target: str) -> None:
    subprocess.run(
        ["magick", source, "-define", "webp:lossless=true", "-define", "webp:exact=true",
         "-define", "webp:method=4", "-quality", "100", target],
        check=True)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source_root, target_root = sys.argv[1], sys.argv[2]
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
        for _ in pool.map(lambda job: to_webp(*job), jobs):
            done += 1
            print(f"\r{done}/{len(jobs)} pictures", end="", flush=True)
    print()


if __name__ == "__main__":
    main()
