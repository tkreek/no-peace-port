#!/usr/bin/env python3
"""Copies the asset folder for a release build, packed smaller without visible change.

    tools/pack_assets.py [--bleed=<pixels>] <assets folder> <destination folder>

- RGB and RGBA PNGs become <name>.webp, lossless: every visible pixel stays the same. The
  colour under transparent pixels is not kept as it is (the upscaler's leftovers, which
  pack badly) but filled in from the nearest visible pixels, out to --bleed pixels
  (default 8), and black beyond. Only that fill reaches the screen, where the GPU's
  mipmaps blend edge pixels with their transparent neighbours (drawn smaller than stored,
  e.g. zoomed out), and it blends there as well as the original colour did.
- Ground tiles (terrain/<biome>/ground_<n>.png: opaque, noisy texture) become lossy WebP
  at quality 95, about four times smaller and indistinguishable on screen.
- WAV sounds become Ogg Vorbis (quality 6; the originals are 22 kHz mono), about a sixth.
- Grey PNGs (shadows, team masks) stay PNG: WebP has no grey format, so the game would
  hold them at four times the memory. Everything else is copied.

The game reads <name>.webp / <name>.ogg wherever it asks for a missing <name>.png / .wav.
Needs numpy and Pillow (tools/.venv, see game/README.md) and ffmpeg with libvorbis.
"""
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image

PNG_RGB, PNG_RGBA = 2, 6
GROUND_TILE = re.compile(r"(^|/)terrain/[^/]+/ground_\d+\.png$")
LOSSY_QUALITY = 95
VORBIS_QUALITY = 6


def colour_png(path: str) -> bool:
    with open(path, "rb") as f:
        header = f.read(26)
    return header[:8] == b"\x89PNG\r\n\x1a\n" and header[25] in (PNG_RGB, PNG_RGBA)


def bleed(rgba: np.ndarray, radius: int, smooth: int = 2) -> np.ndarray:
    """RGB under fully transparent pixels, grown out from the visible ones a pixel a step for
    `radius` steps, black beyond. The first `smooth` steps take the mean of the filled
    4-neighbours (the ring the GPU blends into edges when drawing at 1x and 1/2); the
    rest copy a filled neighbour (flat runs pack smallest)."""
    known = rgba[..., 3] > 0
    if known.all() or not known.any():
        return rgba
    rgb = np.where(known[..., None], rgba[..., :3], 0).astype(np.uint32)
    h, w = known.shape
    shifts = []
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        shifts.append(((slice(max(dy, 0), h + min(dy, 0)), slice(max(dx, 0), w + min(dx, 0))),
                       (slice(max(-dy, 0), h + min(-dy, 0)), slice(max(-dx, 0), w + min(-dx, 0)))))
    for step in range(radius):
        if step < smooth:
            total = np.zeros((h, w, 3), np.uint32)
            count = np.zeros((h, w), np.uint32)
            for src, dst in shifts:
                total[dst] += rgb[src] * known[src][..., None]
                count[dst] += known[src]
            grown = known | (count > 0)
            new = grown & ~known
            rgb[new] = (total[new] + count[new, None] // 2) // count[new, None]
        else:
            grown = known.copy()
            for src, dst in shifts:
                take = ~grown[dst] & known[src]
                rgb[dst][take] = rgb[src][take]
                grown[dst] |= take
        if (grown == known).all():
            break
        known = grown
    out = rgba.copy()
    out[..., :3] = rgb.astype(np.uint8)
    return out


def to_webp(source: str, target: str, radius: int, lossy: bool) -> None:
    with Image.open(source) as image:
        image.load()
        if lossy:
            image.convert("RGB").save(target, "WEBP", quality=LOSSY_QUALITY, method=6)
            return
        if image.mode == "RGBA":
            image = Image.fromarray(bleed(np.asarray(image), radius), "RGBA")
        image.save(target, "WEBP", lossless=True, exact=True, quality=100, method=5)


def to_ogg(source: str, target: str) -> None:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", source, "-map_metadata", "-1",
                    "-c:a", "libvorbis", "-q:a", str(VORBIS_QUALITY), target], check=True)


def pack(job: tuple) -> None:
    kind, source, target, radius = job
    if kind == "ogg":
        to_ogg(source, target)
    else:
        to_webp(source, target, radius, kind == "lossy")


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--bleed=")]
    bleeds = [int(a.split("=", 1)[1]) for a in sys.argv[1:] if a.startswith("--bleed=")]
    if len(args) != 2:
        sys.exit(__doc__)
    source_root, target_root = args
    radius = bleeds[-1] if bleeds else 8
    jobs = []
    for folder, _, files in os.walk(source_root, followlinks=True):
        rel = os.path.relpath(folder, source_root)
        out = os.path.join(target_root, rel)
        os.makedirs(out, exist_ok=True)
        for name in files:
            source = os.path.join(folder, name)
            if name.endswith(".png") and colour_png(source):
                lossy = bool(GROUND_TILE.search(os.path.join(rel, name).replace(os.sep, "/")))
                jobs.append(("lossy" if lossy else "webp", source, os.path.join(out, name[:-4] + ".webp"), radius))
            elif name.endswith(".wav"):
                jobs.append(("ogg", source, os.path.join(out, name[:-4] + ".ogg"), radius))
            else:
                shutil.copy2(source, os.path.join(out, name))
    # Big sheets need a few hundred MB each while they bleed: not more workers than that.
    done = 0
    with ProcessPoolExecutor(max(1, min(os.cpu_count() or 1, 8))) as pool:
        for _ in pool.map(pack, jobs, chunksize=4):
            done += 1
            if sys.stdout.isatty():
                print(f"\r{done}/{len(jobs)} pictures and sounds", end="", flush=True)
    print(f"\r{done}/{len(jobs)} pictures and sounds")


if __name__ == "__main__":
    main()
