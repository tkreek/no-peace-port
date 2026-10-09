#!/usr/bin/env python3
"""Build the "enhanced" 2x sprite set with Real-ESRGAN.

For every .bob animation descriptor in the original archives, each sub-sprite file is
converted into a 2x RGBA atlas plus metadata the engine loads instead of decoding the
original at runtime:

  <out>/<sprite path>.png        RGBA atlas at 2x (paletted/true-colour bodies) or LA (shadows)
  <out>/<sprite path>.team.png   L mask of team-coloured pixels (paletted bodies with team colours)
  <out>/<sprite path>.json       {"scale": 2, "frames": [[x, y, w, h, hotspot_x, hotspot_y], ...]}
  <out>/<bob path>.ramps.png     64 x 9 RGBA: row t = team t's colour as a function of shading

Team colours: paletted sprites carry 8 team palette variants. Team-coloured pixels are
rendered as grey shading (the average luminance of that palette entry over all teams), upscaled
with the rest of the image, and re-tinted in the shader through the team's ramp. One upscale
serves every team.

Usage: hd_sprites.py <install dir with america*.rda> <out dir> [--only <path prefix>]
                     [--addon <expansion install dir>]
With --addon, files the expansion replaces are regenerated even if they already exist.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "formats"))
from rd_archive import GameFiles, normalize  # noqa: E402

ESRGAN = os.path.join(HERE, "..", "bin", "realesrgan", "realesrgan-ncnn-vulkan")
MODEL = "realesrgan-x4plus"
SCALE = 2
PAD = 6               # source pixels between frames, filled by colour bleeding
ATLAS_WIDTH = 2048    # source pixels
DETAIL_BLEND = 0.25   # share of plain Lanczos kept to preserve the original grain
RAMP_SAMPLES = 64


# ---------------------------------------------------------------- original formats

def read_palette(data):
    if data[:4] != b"C256":
        raise ValueError("not a C256 palette")
    v = np.frombuffer(data, "<u2", 256, 4).astype(np.uint32)
    r, g, b = (v >> 10) & 31, (v >> 5) & 31, v & 31
    return np.stack([(r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2)], 1).astype(np.uint8)


def read_bob(text):
    palettes, sprites = [], []
    section = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("ColTab#"):
            section = "pal"
        elif line.startswith("SubSpriteFile#"):
            section = "spr"
            sprites.append({"file": "", "shadow": False})
        elif line.startswith("AnimBlock#"):
            section = None
        elif "=" in line and section:
            key, value = line.split("=", 1)
            if section == "pal" and key == "Filename":
                palettes.append(value.strip())
            elif section == "spr" and key == "Filename":
                sprites[-1]["file"] = value.strip()
            elif section == "spr" and key == "Typ":
                sprites[-1]["shadow"] = value.strip() == "DARK"
    return palettes, sprites


def decode_rdsx(data):
    """Return list of (hotspot_x, hotspot_y, index_or_coverage uint8[h,w], mask bool[h,w])."""
    shadow = data[:4] == b"RDSW"
    count = int.from_bytes(data[4:8], "little")
    pos, frames = 8, []
    for _ in range(count):
        _, hx, hy, w, h = np.frombuffer(data, "<i4", 5, pos)
        table = np.frombuffer(data, "<u4", h + 1, pos + 20)
        base = pos + 20 + 4 * (h + 1)
        index = np.zeros((h, w), np.uint8)
        mask = np.zeros((h, w), bool)
        for y in range(h):
            p, end, x = base + table[y], base + table[y + 1], 0
            while p < end:
                x += data[p]
                n = data[p + 1]
                p += 2
                mask[y, x:x + n] = True
                if not shadow:
                    index[y, x:x + n] = np.frombuffer(data, np.uint8, n, p)
                    p += n
                x += n
        frames.append((int(hx), int(hy), index, mask))
        pos = base + int(table[h])
    return shadow, frames


def decode_rddx(data):
    w, h = int.from_bytes(data[4:8], "little"), int.from_bytes(data[8:12], "little")
    v = np.frombuffer(data, "<u2", w * h, 20).reshape(h, w).astype(np.uint32)
    rgb = np.stack([((v >> 10) & 31) << 3, ((v >> 5) & 31) << 3, (v & 31) << 3], -1).astype(np.uint8)
    rgb |= rgb >> 5
    mask = v != 0
    table = 20 + w * h * 2
    frames = []
    if data[table:table + 4] == b"STAB":
        n = int.from_bytes(data[table + 4:table + 8], "little")
        for i in range(n):
            _, x, y, fw, fh, hx, hy = np.frombuffer(data, "<i4", 7, table + 8 + i * 28)
            frames.append((int(hx), int(hy), rgb[y:y + fh, x:x + fw], mask[y:y + fh, x:x + fw]))
    else:
        frames.append((0, 0, rgb, mask))
    return frames


# ---------------------------------------------------------------- image helpers

def pack(sizes):
    """Shelf-pack frame sizes into ATLAS_WIDTH; returns positions and atlas size (with PAD)."""
    x = y = shelf = 0
    positions = []
    width = 0
    for w, h in sizes:
        if x + w + PAD > ATLAS_WIDTH and x > 0:
            x, y, shelf = 0, y + shelf + PAD, 0
        positions.append((x + PAD, y + PAD))
        x += w + PAD
        shelf = max(shelf, h)
        width = max(width, x + PAD)
    return positions, (max(width, 1), y + shelf + 2 * PAD)


def bleed(rgb, mask, steps=PAD + 2):
    """Extend opaque colours into transparent pixels so upscaling doesn't pull in black."""
    rgb = rgb.astype(np.float32)
    weight = mask.astype(np.float32)
    acc = rgb * weight[..., None]
    for _ in range(steps):
        empty = weight == 0
        if not empty.any():
            break
        shifted_acc = np.zeros_like(acc)
        shifted_w = np.zeros_like(weight)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            shifted_acc += np.roll(np.roll(acc, dy, 0), dx, 1)
            shifted_w += np.roll(np.roll(weight, dy, 0), dx, 1)
        grow = empty & (shifted_w > 0)
        acc[grow] = shifted_acc[grow] / shifted_w[grow, None]
        weight[grow] = 1.0
    acc[weight == 0] = 0
    return acc.clip(0, 255).astype(np.uint8)


def resize(array, size, resample=Image.LANCZOS):
    return np.asarray(Image.fromarray(array).resize(size, resample))


def sharpen_alpha(alpha):
    a = alpha.astype(np.float32) / 255.0
    a = np.clip((a - 0.5) * 1.8 + 0.5, 0, 1)
    return (a * 255).astype(np.uint8)


def luminance(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


# ---------------------------------------------------------------- jobs

class Job:
    """One sprite file to convert; `source` is the padded atlas fed to the upscaler."""

    def __init__(self, path, kind):
        self.path = path
        self.kind = kind  # "paletted" | "truecolor" | "shadow"
        self.frames = []  # (x, y, w, h, hx, hy) in source pixels
        self.rgb = None
        self.alpha = None
        self.team = None


def build_paletted(files, path, palette, team_indices, team_keys):
    shadow, frames = decode_rdsx(files.read(path))
    if shadow:
        return build_shadow(path, frames)
    job = Job(path, "paletted")
    positions, (w, h) = pack([f[2].shape[::-1] for f in frames])
    index = np.zeros((h, w), np.uint8)
    mask = np.zeros((h, w), bool)
    for (x, y), (hx, hy, idx, m) in zip(positions, frames):
        fh, fw = idx.shape
        index[y:y + fh, x:x + fw] = idx
        mask[y:y + fh, x:x + fw] = m
        job.frames.append((x, y, fw, fh, hx, hy))
    colors = palette.copy()
    if team_indices is not None and len(team_indices):
        grey = (team_keys * 255).astype(np.uint8)
        colors[team_indices] = grey[:, None]
        job.team = np.isin(index, team_indices) & mask
        if not job.team.any():
            job.team = None
    job.rgb = bleed(colors[index], mask)
    job.alpha = mask.astype(np.uint8) * 255
    return job


def build_truecolor(files, path):
    frames = decode_rddx(files.read(path))
    job = Job(path, "truecolor")
    positions, (w, h) = pack([f[2].shape[1::-1] for f in frames])
    rgb = np.zeros((h, w, 3), np.uint8)
    mask = np.zeros((h, w), bool)
    for (x, y), (hx, hy, img, m) in zip(positions, frames):
        fh, fw = m.shape
        rgb[y:y + fh, x:x + fw] = img
        mask[y:y + fh, x:x + fw] = m
        job.frames.append((x, y, fw, fh, hx, hy))
    job.rgb = bleed(rgb, mask)
    job.alpha = mask.astype(np.uint8) * 255
    return job


def build_shadow(path, frames):
    job = Job(path, "shadow")
    positions, (w, h) = pack([f[3].shape[::-1] for f in frames])
    alpha = np.zeros((h, w), np.uint8)
    for (x, y), (hx, hy, _, m) in zip(positions, frames):
        fh, fw = m.shape
        alpha[y:y + fh, x:x + fw] = m * 255
        job.frames.append((x, y, fw, fh, hx, hy))
    job.alpha = alpha
    return job


def team_ramps(palettes):
    """Team indices, their grey keys, and a (9, RAMP_SAMPLES, 4) ramp image."""
    base, teams = palettes[0], palettes[1:9]
    changed = np.zeros(256, bool)
    for t in teams:
        changed |= (t != base).any(1)
    changed[0] = False
    indices = np.nonzero(changed)[0]
    ramps = np.zeros((9, RAMP_SAMPLES, 4), np.uint8)
    ramps[..., 3] = 255
    if not len(indices):
        return indices, np.zeros(0), ramps
    keys = np.mean([luminance(t[indices].astype(np.float32)) for t in teams], 0) / 255.0
    order = np.argsort(keys)
    sorted_keys = keys[order]
    samples = np.linspace(0, 1, RAMP_SAMPLES)
    for row, t in enumerate(teams, start=1):
        colors = t[indices][order].astype(np.float32)
        for c in range(3):
            ramps[row, :, c] = np.interp(samples, sorted_keys, colors[:, c]).astype(np.uint8)
    ramps[0] = ramps[1]
    return indices, keys, ramps


def upscale_batch(jobs, workdir):
    """Run Real-ESRGAN once over every job's RGB atlas; returns {path: 4x RGB array}."""
    src, dst = os.path.join(workdir, "in"), os.path.join(workdir, "out")
    os.makedirs(src, exist_ok=True)
    os.makedirs(dst, exist_ok=True)
    names = {}
    for i, job in enumerate(jobs):
        if job.rgb is None:
            continue
        name = f"{i:05d}.png"
        Image.fromarray(job.rgb).save(os.path.join(src, name))
        names[name] = job
    if not names:
        return {}
    print(f"Real-ESRGAN: {len(names)} atlases, "
          f"{sum(j.rgb.shape[0] * j.rgb.shape[1] for j in names.values()) / 1e6:.1f} Mpx", flush=True)
    subprocess.run([ESRGAN, "-i", src, "-o", dst, "-n", MODEL, "-f", "png"],
                   cwd=os.path.dirname(ESRGAN), check=True, stdout=subprocess.DEVNULL)
    return {names[n].path: np.asarray(Image.open(os.path.join(dst, n)).convert("RGB")) for n in names}


def finish(job, upscaled, out_root):
    h, w = job.alpha.shape
    size = (w * SCALE, h * SCALE)
    out = os.path.join(out_root, job.path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if job.kind == "shadow":
        alpha = resize(job.alpha, size, Image.BILINEAR)
        Image.fromarray(np.stack([np.zeros_like(alpha), alpha], -1), "LA").save(out + ".png", optimize=False)
    else:
        rgb = resize(upscaled, size)
        detail = resize(job.rgb, size)
        rgb = (rgb.astype(np.float32) * (1 - DETAIL_BLEND) + detail.astype(np.float32) * DETAIL_BLEND).astype(np.uint8)
        alpha = sharpen_alpha(resize(job.alpha, size))
        Image.fromarray(np.dstack([rgb, alpha]), "RGBA").save(out + ".png")
        if job.team is not None:
            team = resize(job.team.astype(np.uint8) * 255, size)
            Image.fromarray(team, "L").save(out + ".team.png")
    frames = [[x * SCALE, y * SCALE, fw * SCALE, fh * SCALE, hx * SCALE, hy * SCALE]
              for x, y, fw, fh, hx, hy in job.frames]
    with open(out + ".json", "w") as f:
        json.dump({"scale": SCALE, "kind": job.kind, "team": job.team is not None, "frames": frames}, f)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("install_dir")
    parser.add_argument("out_dir")
    parser.add_argument("--only", default="", help="only .bob files under this path prefix")
    parser.add_argument("--batch", type=int, default=60, help="sprite files per upscaler run")
    parser.add_argument("--addon", default=None, help="expansion pack install dir")
    args = parser.parse_args()

    files = GameFiles(args.install_dir, args.addon)
    bobs = sorted(n for n in files.names() if n.endswith(".bob") and n.startswith(normalize(args.only)))
    print(f"{len(bobs)} animation descriptors", flush=True)

    pending, done = [], set()
    for bob_path in bobs:
        directory = os.path.dirname(bob_path)
        palettes_files, sprites = read_bob(files.read(bob_path).decode("latin1"))
        palettes = [read_palette(files.read(f"{directory}/{p}")) for p in palettes_files
                    if files.exists(f"{directory}/{p}")]
        indices, keys, ramps = team_ramps(palettes) if len(palettes) >= 9 else (None, None, None)
        if ramps is not None:
            out = os.path.join(args.out_dir, bob_path + ".ramps.png")
            os.makedirs(os.path.dirname(out), exist_ok=True)
            Image.fromarray(ramps, "RGBA").save(out)
        for sprite in sprites:
            path = normalize(f"{directory}/{sprite['file']}")
            if path in done or not files.exists(path):
                continue
            done.add(path)
            if os.path.exists(os.path.join(args.out_dir, path + ".json")) and not files.from_addon(path):
                continue  # already converted (resumable); expansion files are redone
            try:
                if path.endswith(".spr"):
                    pending.append(build_truecolor(files, path))
                elif palettes:
                    pending.append(build_paletted(files, path, palettes[0], indices, keys))
            except Exception as error:  # keep going; report at the end
                print(f"skip {path}: {error}", flush=True)
            if len(pending) >= args.batch:
                flush(pending, args.out_dir)
                pending = []
    flush(pending, args.out_dir)
    print("done", flush=True)


def flush(jobs, out_root):
    if not jobs:
        return
    with tempfile.TemporaryDirectory() as workdir:
        upscaled = upscale_batch(jobs, workdir)
        for job in jobs:
            finish(job, upscaled.get(job.path), out_root)
            print(f"ok {job.path}", flush=True)


if __name__ == "__main__":
    main()
