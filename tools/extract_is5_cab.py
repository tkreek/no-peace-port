#!/usr/bin/env python3
"""Extract the America CDs' InstallShield 5 DATA1.CAB (base game and expansion pack).

unshield parses the file table fine but fails on most of these cabinets' payloads,
which are stored as a sequence of [u16 length][raw-deflate block] chunks. We take the
file table from `unshield -D 3 l` and inflate the chunks ourselves; the few files
stored the way unshield expects (e.g. the expansion's executables) are left to it.

Usage: tools/extract_is5_cab.py <DATA1.CAB> <output-dir>
"""
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib


def file_table(cab_path):
    log = subprocess.run(["unshield", "-D", "3", "l", cab_path], capture_output=True, text=True)
    text = log.stdout + log.stderr
    descriptors = re.findall(
        r"File descriptor offset (\d+):.*?Name offset:\s+([0-9a-f]+).*?"
        r"Compressed size:\s+([0-9a-f]+).*?Data offset:\s+([0-9a-f]+)",
        text, re.S)
    # Entries without a name are placeholders that `unshield l` doesn't list.
    descriptors = [(i, size, off) for i, name_off, size, off in descriptors if int(name_off, 16)]
    names = re.findall(r"^\s+\d+\s+(\S.*)$", log.stdout, re.M)[:-1]  # drop "N files" summary
    if len(names) != len(descriptors):
        sys.exit(f"table mismatch: {len(names)} names vs {len(descriptors)} descriptors")
    return [(name.replace("\\", "/"), int(off, 16), int(size, 16))
            for name, (_, size, off) in zip(names, descriptors)]


def extract(cab, offset, compressed_size, out):
    cab.seek(offset)
    end = offset + compressed_size
    while cab.tell() < end:
        (length,) = struct.unpack("<H", cab.read(2))
        out.write(zlib.decompressobj(-15).decompress(cab.read(length)))


def main():
    cab_path, out_root = sys.argv[1:3]
    fallback = []
    with open(cab_path, "rb") as cab:
        for name, offset, size in file_table(cab_path):
            path = os.path.join(out_root, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            try:
                with open(path, "wb") as out:
                    extract(cab, offset, size, out)
            except zlib.error:
                os.remove(path)
                fallback.append(name)
                continue
            print(f"{os.path.getsize(path):>11} {name}")
    if fallback:
        # Let unshield extract the remaining files, then move them into place.
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["unshield", "-d", tmp, "x", cab_path], capture_output=True)
            for name in fallback:
                source = os.path.join(tmp, name)
                if os.path.exists(source):
                    shutil.move(source, os.path.join(out_root, name))
                    print(f"{os.path.getsize(os.path.join(out_root, name)):>11} {name} (unshield)")
                else:
                    print(f"FAILED {name}")


if __name__ == "__main__":
    main()
