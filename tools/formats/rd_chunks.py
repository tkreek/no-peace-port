"""RDCHUNK container used by .alf maps (and possibly saves).

Header: "RDCHUNK.VERSION\\0", u32 version, u32 0, "RDLF", u32 ?.
Then chunks: char[8] name (NUL-padded), u32 next_chunk_offset (absolute), u32 packed flag,
if packed: u32 unpacked_size + LZW stream (MSB-first, 9..13 bit codes, early change, 256=clear, 257=end).
"""
import struct


MAX_BITS = 13


def lzw_decompress(data, expected_size=None):
    out = bytearray()
    bitpos, nbits = 0, 9
    total_bits = len(data) * 8
    table = [bytes([i]) for i in range(256)] + [b"", b""]
    prev = None
    while bitpos + nbits <= total_bits:
        byte = bitpos >> 3
        chunk = int.from_bytes(data[byte:byte + 4].ljust(4, b"\0"), "big")
        code = (chunk >> (32 - nbits - (bitpos & 7))) & ((1 << nbits) - 1)
        bitpos += nbits
        if code == 256:
            table, nbits, prev = table[:258], 9, None
            continue
        if code == 257:
            break
        if prev is None:
            entry = table[code]
        else:
            entry = table[code] if code < len(table) else prev + prev[:1]
            if len(table) < (1 << MAX_BITS):
                table.append(prev + entry[:1])
        out += entry
        prev = entry
        if len(table) + 1 >= (1 << nbits) and nbits < MAX_BITS:
            nbits += 1
        if expected_size is not None and len(out) >= expected_size:
            break
    return bytes(out)


def read_chunks(path):
    data = open(path, "rb").read()
    if not data.startswith(b"RDCHUNK.VERSION\0"):
        raise ValueError(f"{path}: not an RDCHUNK file")
    pos, chunks = 0x20, []
    while pos < len(data):
        name = data[pos:pos + 8].rstrip(b"\0").decode("latin1")
        next_offset, packed = struct.unpack_from("<II", data, pos + 8)
        body = data[pos + 16:next_offset]
        if packed:
            size = struct.unpack_from("<I", body)[0]
            body = lzw_decompress(body[4:], size)
            if len(body) != size:
                raise ValueError(f"{path}:{name}: unpacked {len(body)} of {size} bytes")
        chunks.append((name, body))
        pos = next_offset
    return chunks
