"""Readers for Related Designs' America sprite formats.

.ftb  "C256" palette: 256 x RGB555 (u16). Index 0 is the magenta colour key.
.spx  "RDSX" paletted sprite list, .shw "RDSW" shadow list. Layout:
        magic, u32 frame_count, then frames back to back:
        u32 index, i32 hotspot_x, i32 hotspot_y, u32 width, u32 height,
        u32 row_offsets[height + 1] (relative to row data start), row data
      The frame is drawn with its hotspot on the object's ground anchor.
      Each row is a sequence of (u8 skip, u8 count, count pixel bytes) runs until the
      row width is filled. Shadow rows carry no pixel bytes.
"""
import struct
import zlib

TRANSPARENT = (0, 0, 0, 0)


def read_palette(path):
    data = open(path, "rb").read()
    if data[:4] != b"C256":
        raise ValueError(f"{path}: not a C256 palette")
    colors = []
    for (value,) in struct.iter_unpack("<H", data[4:4 + 512]):
        r, g, b = (value >> 10) & 31, (value >> 5) & 31, value & 31
        colors.append(((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2), 255))
    return colors


class Frame:
    def __init__(self, x, y, width, height, rows):
        self.x, self.y, self.width, self.height = x, y, width, height
        self.rows = rows  # per row: list of (start_x, bytes or count)


def read_sprites(path):
    data = open(path, "rb").read()
    magic = data[:4]
    if magic not in (b"RDSX", b"RDSW"):
        raise ValueError(f"{path}: unknown sprite magic {magic!r}")
    shadow = magic == b"RDSW"
    count = struct.unpack_from("<I", data, 4)[0]
    offset = 8
    frames = []
    for _ in range(count):
        _index, x, y, width, height = struct.unpack_from("<IiiII", data, offset)
        table = struct.unpack_from(f"<{height + 1}I", data, offset + 20)
        base = offset + 20 + 4 * (height + 1)
        rows = []
        for row in range(height):
            pos, end, col, runs = base + table[row], base + table[row + 1], 0, []
            while pos < end:
                skip, n = data[pos], data[pos + 1]
                pos += 2
                col += skip
                if shadow:
                    runs.append((col, n))
                else:
                    runs.append((col, data[pos:pos + n]))
                    pos += n
                col += n
            rows.append(runs)
        frames.append(Frame(x, y, width, height, rows))
        offset = base + table[height]
    return frames, shadow


def frame_rgba(frame, palette=None, shadow_alpha=110):
    """Return a flat RGBA list (width*height tuples)."""
    pixels = [TRANSPARENT] * (frame.width * frame.height)
    for y, runs in enumerate(frame.rows):
        for start, payload in runs:
            if isinstance(payload, int):
                for i in range(payload):
                    pixels[y * frame.width + start + i] = (0, 0, 0, shadow_alpha)
            else:
                for i, index in enumerate(payload):
                    pixels[y * frame.width + start + i] = palette[index]
    return pixels


def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for p in pixels[y * width:(y + 1) * width]:
            raw.extend(p)
    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)
