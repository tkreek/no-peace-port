"""BobListe.blf ("RDBF"): the object type table.

Part 1: u32 capacity (1000), then `capacity` records of
        { u32 ?; char bob_path[80]; i32 ? }  -- the .bob file list (index = bob id).
Part 2: one record per object type (index = graphics/type id used by maps and GUIDS.INI):
        char name[0x50]; u32 bob_id @0x50; u32 kind @0x54; ... u32 anim @0x6c;
        u32 shadow_anim @0x70; ... (0x104 bytes, partly uninitialised memory), then
        "BARY" i32 anchor_x, anchor_y; u32 width_px, height_px, cols, rows, count;
        u32 cells[count]   -- 16 px footprint/collision grid.
"""
import struct


def read_bobliste(path):
    d = open(path, "rb").read()
    if d[:4] != b"RDBF":
        raise ValueError("not RDBF")
    capacity = struct.unpack_from("<I", d, 4)[0]
    bobs = []
    for i in range(capacity):
        o = 8 + i * 88
        bobs.append(d[o + 4:o + 84].split(b"\0")[0].decode("latin1").replace("\\", "/").lower())
    pos = 8 + capacity * 88
    types = []
    while pos + 0x104 + 32 <= len(d):
        name = d[pos:pos + 0x50].split(b"\0")[0].decode("latin1")
        bob_id, kind = struct.unpack_from("<II", d, pos + 0x50)
        anim, shadow = struct.unpack_from("<ii", d, pos + 0x6C)
        bary = pos + 0x104
        if kind == 0xFFFFFFFF:  # (expansion) placeholder record without a footprint
            types.append(dict(id=len(types), name=name, bob=bob_id, bob_path="", kind=0, anim=anim,
                              shadow_anim=shadow, footprint=dict(anchor=(0, 0), size=(0, 0), cols=0, rows=0, cells=())))
            pos = bary
            continue
        if d[bary:bary + 4] != b"BARY":
            break  # trailing data after the last type record
        ax, ay, w, h, cols, rows, count = struct.unpack_from("<iiIIIII", d, bary + 4)
        cells = struct.unpack_from(f"<{count}I", d, bary + 32)
        types.append(dict(id=len(types), name=name, bob=bob_id, bob_path=bobs[bob_id] if bob_id < len(bobs) else "",
                          kind=kind, anim=anim, shadow_anim=shadow,
                          footprint=dict(anchor=(ax, ay), size=(w, h), cols=cols, rows=rows, cells=cells)))
        pos = bary + 32 + 4 * count
    return bobs, types, pos
