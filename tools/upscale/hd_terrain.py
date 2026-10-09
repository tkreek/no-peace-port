#!/usr/bin/env python3
"""Build the "enhanced" 2x terrain set for both biomes with Real-ESRGAN.

The original terrain is a 640x12000 paletted atlas of 32x32 tiles whose palette indices
below 40 are placeholders for tiling ground textures (steppeN.pic). Output per biome:

  <out>/<biome>/terrain_atlas.png   RGBA, 64x64 per tile, ATLAS_COLUMNS tiles per row:
                                    RGB = upscaled literal art (cliffs, shores), A = its coverage
  <out>/<biome>/terrain_layers.png  L, same layout: ground texture layer under each pixel
  <out>/<biome>/ground_<N>.png      RGB, 2x ground texture N (seamless)
  <out>/<biome>/terrain.json        {"scale": 2, "tile": 64, "columns": ATLAS_COLUMNS, "tiles": n}

Tiles are upscaled individually: neighbouring tiles in the atlas are unrelated on the map, so
each tile is padded with the tiles that most often surround it on real maps (counted over all
skirmish and campaign maps), falling back to edge clamping. With real context on every side
the upscaler produces matching detail at tile borders, so no seams appear in the map.

Usage: hd_terrain.py <install dir> <out dir> [--biome steppe|wiese]
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "formats"))
from rd_archive import GameFiles  # noqa: E402
from rd_chunks import read_chunks  # noqa: E402
from hd_sprites import ESRGAN, MODEL, bleed  # noqa: E402

TILE = 32
SCALE = 2
PAD = 8
GROUND_LAYERS = 40
ATLAS_COLUMNS = 64
CHUNK_TILES = 20           # tiles per side in one upscaler input image
DETAIL_BLEND = 0.3
GROUND_WRAP = 32


def read_indexed_pic(data):
    w, h = int.from_bytes(data[4:8], "little"), int.from_bytes(data[8:12], "little")
    palette = np.frombuffer(data, np.uint8, 768, 20).reshape(256, 3)
    pixels = np.frombuffer(data, np.uint8, w * h, 24 + 768).reshape(h, w)
    return palette, pixels


def esrgan(images, workdir):
    """Upscale a list of RGB arrays 4x in one run."""
    src, dst = os.path.join(workdir, "in"), os.path.join(workdir, "out")
    for d in (src, dst):
        shutil_rm(d)
        os.makedirs(d)
    for i, image in enumerate(images):
        Image.fromarray(image).save(os.path.join(src, f"{i:04d}.png"))
    subprocess.run([ESRGAN, "-i", src, "-o", dst, "-n", MODEL, "-f", "png"],
                   cwd=os.path.dirname(ESRGAN), check=True, stdout=subprocess.DEVNULL)
    return [np.asarray(Image.open(os.path.join(dst, f"{i:04d}.png")).convert("RGB")) for i in range(len(images))]


def shutil_rm(path):
    import shutil
    shutil.rmtree(path, ignore_errors=True)


def to_2x(upscaled4, source):
    """4x upscaler output down to 2x, with some plain-Lanczos detail mixed back in."""
    h, w = source.shape[:2]
    size = (w * SCALE, h * SCALE)
    a = np.asarray(Image.fromarray(upscaled4).resize(size, Image.LANCZOS)).astype(np.float32)
    b = np.asarray(Image.fromarray(source).resize(size, Image.LANCZOS)).astype(np.float32)
    return (a * (1 - DETAIL_BLEND) + b * DETAIL_BLEND).clip(0, 255).astype(np.uint8)


def spread_layers(index):
    """Give literal pixels (>= GROUND_LAYERS) the nearest placeholder layer, so every pixel
    knows which ground shows through where the art is partly transparent."""
    layer = index.astype(np.int32).copy()
    known = layer < GROUND_LAYERS
    for _ in range(TILE):
        if known.all():
            break
        grown = layer.copy()
        grown_known = known.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(np.roll(layer, dy, 0), dx, 1)
            shifted_known = np.roll(np.roll(known, dy, 0), dx, 1)
            take = ~grown_known & shifted_known
            grown[take] = shifted[take]
            grown_known |= take
        layer, known = grown, grown_known
    layer[~known] = 0
    return layer.astype(np.uint8)


DIRECTIONS = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def neighbour_table(map_paths):
    """For each tile and direction, the tile most often found there on real maps."""
    import collections
    import glob
    import struct
    counts = collections.defaultdict(collections.Counter)
    for path in map_paths:
        chunks = dict(read_chunks(path))
        columns, rows = struct.unpack_from("<II", chunks["LVL_INFO"], 0x114)
        grid = np.frombuffer(chunks["LVMATRIX"], "<u4", columns * rows).reshape(rows, columns) & 0xFFFF
        for dy, dx in DIRECTIONS:
            a = grid[max(0, -dy):rows - max(0, dy), max(0, -dx):columns - max(0, dx)]
            b = grid[max(0, dy):rows - max(0, -dy) or None, max(0, dx):columns - max(0, -dx) or None]
            for t, n in zip(a.ravel().tolist(), b.ravel().tolist()):
                counts[(t, dy, dx)][n] += 1
    return {key: counter.most_common(1)[0][0] for key, counter in counts.items()}


def padded_tile(rgb, t, columns, neighbours):
    """A tile with PAD pixels of context from its most likely map neighbours."""
    def tile_pixels(index):
        ty, tx = divmod(index, columns)
        return rgb[ty * TILE:(ty + 1) * TILE, tx * TILE:(tx + 1) * TILE]
    out = np.pad(tile_pixels(t), ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
    size = TILE + 2 * PAD
    for dy, dx in DIRECTIONS:
        n = neighbours.get((t, dy, dx))
        if n is None:
            continue
        src = tile_pixels(n)
        ys = slice(0, PAD) if dy < 0 else (slice(size - PAD, size) if dy > 0 else slice(PAD, PAD + TILE))
        xs = slice(0, PAD) if dx < 0 else (slice(size - PAD, size) if dx > 0 else slice(PAD, PAD + TILE))
        sy = slice(TILE - PAD, TILE) if dy < 0 else (slice(0, PAD) if dy > 0 else slice(0, TILE))
        sx = slice(TILE - PAD, TILE) if dx < 0 else (slice(0, PAD) if dx > 0 else slice(0, TILE))
        out[ys, xs] = src[sy, sx]
    return out


def build_atlas(files, biome, out_dir, workdir, neighbours):
    palette, index = read_indexed_pic(files.read(f"{biome}/gfx/landschaft/steppe.pic"))
    columns = index.shape[1] // TILE
    count = (index.shape[0] // TILE) * columns
    literal = index >= GROUND_LAYERS
    rgb = palette[index]
    rgb = bleed(rgb, literal, steps=TILE)
    layers = spread_layers(index)

    hd_tile = TILE * SCALE
    rows_out = (count + ATLAS_COLUMNS - 1) // ATLAS_COLUMNS
    atlas = np.zeros((rows_out * hd_tile, ATLAS_COLUMNS * hd_tile, 4), np.uint8)
    layer_map = np.zeros((rows_out * hd_tile, ATLAS_COLUMNS * hd_tile), np.uint8)
    padded_size = TILE + 2 * PAD

    def tile_slice(t):
        ty, tx = divmod(t, columns)
        return slice(ty * TILE, ty * TILE + TILE), slice(tx * TILE, tx * TILE + TILE)

    for start in range(0, count, CHUNK_TILES * CHUNK_TILES):
        chunk = list(range(start, min(count, start + CHUNK_TILES * CHUNK_TILES)))
        canvas = np.zeros((CHUNK_TILES * padded_size, CHUNK_TILES * padded_size, 3), np.uint8)
        for k, t in enumerate(chunk):
            tile = padded_tile(rgb, t, columns, neighbours)
            cy, cx = divmod(k, CHUNK_TILES)
            canvas[cy * padded_size:(cy + 1) * padded_size, cx * padded_size:(cx + 1) * padded_size] = tile
        upscaled = to_2x(esrgan([canvas], workdir)[0], canvas)
        for k, t in enumerate(chunk):
            cy, cx = divmod(k, CHUNK_TILES)
            y0 = (cy * padded_size + PAD) * SCALE
            x0 = (cx * padded_size + PAD) * SCALE
            ys, xs = tile_slice(t)
            oy, ox = divmod(t, ATLAS_COLUMNS)
            dst = (slice(oy * hd_tile, (oy + 1) * hd_tile), slice(ox * hd_tile, (ox + 1) * hd_tile))
            atlas[dst[0], dst[1], :3] = upscaled[y0:y0 + hd_tile, x0:x0 + hd_tile]
            coverage = np.pad(literal[ys, xs].astype(np.uint8) * 255, PAD, mode="edge")
            coverage = np.asarray(Image.fromarray(coverage).resize(
                (padded_size * SCALE, padded_size * SCALE), Image.LANCZOS))
            atlas[dst[0], dst[1], 3] = coverage[PAD * SCALE:PAD * SCALE + hd_tile, PAD * SCALE:PAD * SCALE + hd_tile]
            layer_map[dst[0], dst[1]] = np.kron(layers[ys, xs], np.ones((SCALE, SCALE), np.uint8))
        print(f"{biome}: tiles {start}..{chunk[-1]} of {count}", flush=True)

    Image.fromarray(atlas, "RGBA").save(os.path.join(out_dir, "terrain_atlas.png"))
    Image.fromarray(layer_map, "L").save(os.path.join(out_dir, "terrain_layers.png"))
    return count


def build_ground(files, biome, out_dir, workdir):
    sources = []
    for n in range(GROUND_LAYERS):
        path = f"{biome}/gfx/landschaft/steppe{n}.pic"
        if files.exists(path):
            palette, index = read_indexed_pic(files.read(path))
            sources.append((n, palette[index]))
    padded = [np.pad(img, ((GROUND_WRAP, GROUND_WRAP), (GROUND_WRAP, GROUND_WRAP), (0, 0)), mode="wrap")
              for _, img in sources]
    for (n, img), up, pad in zip(sources, esrgan(padded, workdir), padded):
        full = to_2x(up, pad)
        w = GROUND_WRAP * SCALE
        Image.fromarray(full[w:w + img.shape[0] * SCALE, w:w + img.shape[1] * SCALE]).save(
            os.path.join(out_dir, f"ground_{n}.png"))
    print(f"{biome}: {len(sources)} ground textures", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("install_dir")
    parser.add_argument("out_dir")
    parser.add_argument("--biome", action="append")
    args = parser.parse_args()
    files = GameFiles(args.install_dir)
    import glob
    maps = glob.glob(os.path.join(args.install_dir, "Levels", "*.alf"))
    campaign = os.path.join(HERE, "..", "..", "original", "extracted", "america4", "Kampagne")
    maps += glob.glob(os.path.join(campaign, "*.alf"))
    neighbours = neighbour_table(maps)
    print(f"neighbour table from {len(maps)} maps: {len(neighbours)} entries", flush=True)
    for biome in args.biome or ["steppe", "wiese"]:
        out = os.path.join(args.out_dir, biome)
        os.makedirs(out, exist_ok=True)
        with tempfile.TemporaryDirectory() as workdir:
            build_ground(files, biome, out, workdir)
            count = build_atlas(files, biome, out, workdir, neighbours)
        with open(os.path.join(out, "terrain.json"), "w") as f:
            json.dump({"scale": SCALE, "tile": TILE * SCALE, "columns": ATLAS_COLUMNS, "tiles": count}, f)
    print("done", flush=True)


if __name__ == "__main__":
    main()
