#!/usr/bin/env python3
"""Upscale the original still images with Real-ESRGAN.

Covers what hd_sprites.py (animation sheets) and hd_terrain.py leave out:
  - portraits (Potraits/**/*.bmp): unit, building and upgrade buttons, selection portraits;
    50 px originals, written at 4x with the magenta colour key turned into alpha;
  - full-screen pictures (*.pic under global/gfx: menu backdrops, loading screens, status
    bar panels), written at 2x.

Output: <out>/<original path>.png (RGBA), which the game prefers over the original file.

Usage: hd_images.py <install dir> <out dir> [--addon <expansion install dir>]
"""
import argparse
import io
import os
import struct
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "formats"))
sys.path.insert(0, HERE)
from rd_archive import GameFiles  # noqa: E402
from hd_sprites import DETAIL_BLEND, upscale_batch, resize  # noqa: E402

PORTRAIT_SCALE = 4
PICTURE_SCALE = 2


class Job:
    def __init__(self, path, rgb, alpha, scale):
        self.path = path
        self.rgb = rgb
        self.alpha = alpha
        self.scale = scale


def decode_bmp(data):
    # Some original BMPs carry wrong size fields in their headers; the pixel data is intact.
    data = bytearray(data)
    offset = struct.unpack_from("<I", data, 10)[0]
    struct.pack_into("<I", data, 2, len(data))
    struct.pack_into("<I", data, 34, len(data) - offset)
    return np.asarray(Image.open(io.BytesIO(bytes(data))).convert("RGB"))


def decode_pic(data):
    if data[:4] != b"RDIC":
        raise ValueError("not RDIC")
    w, h = struct.unpack_from("<II", data, 4)
    kind = data[16:20]
    if kind == b"COLS":
        palette = np.frombuffer(data, np.uint8, 768, 20).reshape(256, 3)
        pixels = np.frombuffer(data, np.uint8, w * h, 24 + 768)
        return palette[pixels].reshape(h, w, 3)
    if kind == b"P16B":
        v = np.frombuffer(data, "<u2", w * h, 20).reshape(h, w).astype(np.uint32)
        rgb = np.stack([((v >> 10) & 31) << 3, ((v >> 5) & 31) << 3, (v & 31) << 3], -1).astype(np.uint8)
        return rgb | (rgb >> 5)
    if kind == b"PRGB":
        return np.frombuffer(data, np.uint8, w * h * 3, 20).reshape(h, w, 3).copy()
    raise ValueError(f"unsupported pic {kind!r}")


def key_alpha(rgb):
    """Magenta colour key -> alpha; keyed pixels take their neighbours' colour so the
    upscaler does not smear pink into the edges."""
    keyed = (rgb[..., 0] > 240) & (rgb[..., 1] < 20) & (rgb[..., 2] > 240)
    alpha = np.where(keyed, 0, 255).astype(np.uint8)
    if not keyed.any() or keyed.all():
        return rgb, alpha
    rgb = rgb.astype(np.float32).copy()
    filled = ~keyed
    for _ in range(64):
        if filled.all():
            break
        acc = np.zeros_like(rgb)
        count = np.zeros(filled.shape, np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted = np.roll(filled, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * shifted[..., None]
            count += shifted
        grow = ~filled & (count > 0)
        rgb[grow] = acc[grow] / count[grow][:, None]
        filled |= grow
    return rgb.astype(np.uint8), alpha


def finish(job, upscaled, out_root):
    h, w = job.alpha.shape
    size = (w * job.scale, h * job.scale)
    rgb = resize(upscaled, size)
    detail = resize(job.rgb, size)
    rgb = (rgb.astype(np.float32) * (1 - DETAIL_BLEND) + detail.astype(np.float32) * DETAIL_BLEND).astype(np.uint8)
    alpha = resize(job.alpha, size, Image.BILINEAR)
    alpha = np.where(alpha > 128, 255, np.where(alpha < 40, 0, alpha)).astype(np.uint8)
    out = os.path.join(out_root, job.path + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    Image.fromarray(np.dstack([rgb, alpha]), "RGBA").save(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("install_dir")
    parser.add_argument("out_dir")
    parser.add_argument("--addon", default=None)
    parser.add_argument("--batch", type=int, default=80)
    args = parser.parse_args()
    files = GameFiles(args.install_dir, args.addon)
    wanted = []
    for name in sorted(set(files.names())):
        if name.startswith("potraits/") and name.endswith(".bmp"):
            wanted.append((name, PORTRAIT_SCALE))
        elif name.startswith("global/gfx/") and name.endswith(".pic") and not name.startswith("global/gfx/fog"):
            wanted.append((name, PICTURE_SCALE))
    print(f"{len(wanted)} images", flush=True)
    pending = []
    for name, scale in wanted:
        if os.path.exists(os.path.join(args.out_dir, name + ".png")):
            continue
        try:
            data = files.read(name)
            rgb = decode_bmp(data) if name.endswith(".bmp") else decode_pic(data)
        except Exception as error:
            print(f"skip {name}: {error}", flush=True)
            continue
        rgb, alpha = key_alpha(rgb)
        pending.append(Job(name, rgb, alpha, scale))
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
            finish(job, upscaled[job.path], out_root)
            print(f"ok {job.path}", flush=True)


if __name__ == "__main__":
    main()
