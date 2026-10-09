"""Read-only access to the original RDAR archives (america0..4.rda).

Layout: "RDAR", u32 ?, u32 count, then `count` x { char name[124]; u32 offset } from byte 12.
A file ends where the next one starts. Names are normalised to lower case with forward slashes.
"""
import os
import struct


def normalize(name):
    return name.replace("\\", "/").removeprefix("./").lower()


class RdaArchive:
    def __init__(self, path):
        self.path = path
        self.entries = {}
        with open(path, "rb") as f:
            header = f.read(12)
            if header[:4] != b"RDAR":
                raise ValueError(f"{path}: not an RDAR archive")
            count = struct.unpack_from("<I", header, 8)[0]
            table = f.read(count * 128)
            size = os.path.getsize(path)
        names, offsets = [], []
        for i in range(count):
            record = table[i * 128:(i + 1) * 128]
            names.append(record[:124].split(b"\0")[0].decode("latin1"))
            offsets.append(struct.unpack_from("<I", record, 124)[0])
        for i, name in enumerate(names):
            end = offsets[i + 1] if i + 1 < count else size
            self.entries[normalize(name)] = (offsets[i], end - offsets[i])

    def read(self, name):
        offset, size = self.entries[normalize(name)]
        with open(self.path, "rb") as f:
            f.seek(offset)
            return f.read(size)


class GameFiles:
    """All five archives of an installation, searched in order."""

    def __init__(self, install_dir, addon_dir=None):
        self.archives = []
        self.addon_archives = []
        for i in (9, 8, 7, 6, 5, 0, 1, 2, 3, 4):  # expansion archives take priority
            for directory in filter(None, (addon_dir, install_dir)):
                path = os.path.join(directory, f"america{i}.rda")
                if os.path.exists(path) and all(a.path != path for a in self.archives):
                    archive = RdaArchive(path)
                    self.archives.append(archive)
                    if i >= 5:
                        self.addon_archives.append(archive)
        if not self.archives:
            raise FileNotFoundError(f"no america*.rda in {install_dir}")

    def from_addon(self, name):
        """True if the file is served from an expansion archive."""
        key = normalize(name)
        for archive in self.archives:
            if key in archive.entries:
                return archive in self.addon_archives
        return False

    def read(self, name):
        key = normalize(name)
        for archive in self.archives:
            if key in archive.entries:
                return archive.read(key)
        raise KeyError(name)

    def exists(self, name):
        key = normalize(name)
        return any(key in a.entries for a in self.archives)

    def names(self):
        for archive in self.archives:
            yield from archive.entries
