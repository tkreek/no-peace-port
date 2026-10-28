#!/usr/bin/env python3
"""Applies the project's committed asset edits (asset_patches/) on top of the asset folder.

    tools/assets/patch_assets.py apply   [--assets assets] [--patches asset_patches] [--force]
    tools/assets/patch_assets.py status  [--assets ...] [--patches ...]
    tools/assets/patch_assets.py capture <file in the asset folder or maps/> ... [--assets ...] [--patches ...]
    tools/assets/patch_assets.py restore [--assets ...]
    tools/assets/patch_assets.py zip     <out.zip> [--assets ...]

The asset folder (the shared asset pack, unzipped) is never committed.
What is committed is asset_patches/, laid out like the asset folder:

  <path>.patch.json   changes to the table <path>.json: a JSON merge patch (RFC 7386:
                      objects merge key by key, null removes a key, anything else replaces).
                      Lists of objects that each have an "id" (data/object_types.json) are
                      patched by id, as {"$by_id": {"<id>": <merge patch, or null to drop>}};
                      an id the list lacks is appended.
  anything else       copied in, adding a file or replacing the original one.

The first run keeps the folder as it came in <assets>/.pristine/ (every .json file, the
originals of files it replaces later, and a size and hash of every file), so `apply` can
always start again from the originals: removing or changing a patch and applying again
gives the same result as a fresh folder. `apply` refuses to overwrite a patched file edited
by hand since the last apply (keep the edit with `capture` first, or drop it with --force).

`capture` turns edits made in the asset folder into patches: a .json file becomes the merge
patch from its original, any other file is copied. A map saved by the map editor (maps/
beside the asset folder) goes to asset_patches/maps/.

`zip` packs the folder as it came, without the patches or .pristine/, for sharing.
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PRISTINE = ".pristine"
PATCH_SUFFIX = ".patch.json"
BY_ID = "$by_id"


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, value, pretty=False):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        if pretty:
            json.dump(value, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
        else:  # as tools/assets/build_assets.py writes them
            json.dump(value, f, ensure_ascii=False, separators=(",", ":"))


# --- Merge patches ---

def by_id(value):
    """The list as {str(id): item} when every item is an object with a distinct "id", else None."""
    if not isinstance(value, list) or not value or not all(isinstance(v, dict) and "id" in v for v in value):
        return None
    keyed = {str(v["id"]): v for v in value}
    return keyed if len(keyed) == len(value) else None


def merge(target, patch):
    if isinstance(patch, dict) and BY_ID in patch and isinstance(target, list):
        out = list(target)
        index = {str(v.get("id")): i for i, v in enumerate(out) if isinstance(v, dict)}
        dropped = set()
        for key, change in patch[BY_ID].items():
            if change is None:
                dropped.add(key)
            elif key in index:
                out[index[key]] = merge(out[index[key]], change)
            else:
                out.append(merge({}, change))
        return [v for v in out if not (isinstance(v, dict) and str(v.get("id")) in dropped)]
    if not isinstance(patch, dict):
        return patch
    out = dict(target) if isinstance(target, dict) else {}
    for key, change in patch.items():
        if change is None:
            out.pop(key, None)
        else:
            out[key] = merge(out.get(key), change)
    return out


def diff(old, new):
    """The merge patch that turns old into new (None when they are the same)."""
    if old == new:
        return None
    old_keyed, new_keyed = by_id(old), by_id(new)
    if old_keyed is not None and new_keyed is not None:
        changes = {k: None for k in old_keyed if k not in new_keyed}
        for key, item in new_keyed.items():
            change = diff(old_keyed[key], item) if key in old_keyed else item
            if key not in old_keyed or change is not None:
                changes[key] = change
        return {BY_ID: changes}
    if isinstance(old, dict) and isinstance(new, dict) and not any(v is None for v in new.values()):
        changes = {k: None for k in old if k not in new}
        for key, value in new.items():
            change = diff(old[key], value) if key in old else value
            if key not in old or change is not None:
                changes[key] = change
        return changes
    return new


# --- The asset folder and its originals ---

class Assets:
    def __init__(self, root):
        self.root = os.path.abspath(root)
        self.pristine = os.path.join(self.root, PRISTINE)
        self.index_path = os.path.join(self.pristine, "index.json")
        self.applied_path = os.path.join(self.pristine, "applied.json")
        self.lost_path = os.path.join(self.pristine, "lost.json")
        if not os.path.isfile(os.path.join(self.root, "data", "object_types.json")):
            sys.exit(f"No asset folder at {self.root}: unzip the shared asset pack "
                     "in the project folder (see README.md).")
        if not os.path.isdir(self.pristine):
            self.snapshot()
        self.index = load_json(self.index_path)
        self.applied = load_json(self.applied_path)
        self.lost = set(load_json(self.lost_path)) if os.path.exists(self.lost_path) else set()

    def path(self, rel):
        return os.path.join(self.root, rel)

    def kept(self, rel):
        return os.path.join(self.pristine, "files", rel)

    def files(self):
        for folder, dirs, names in os.walk(self.root):
            dirs[:] = sorted(d for d in dirs if not d.startswith("."))
            for name in sorted(names):
                yield os.path.relpath(os.path.join(folder, name), self.root).replace(os.sep, "/")

    def snapshot(self):
        print(f"Keeping the originals in {self.pristine} ...")
        index = {}
        for rel in self.files():
            source = self.path(rel)
            stat = os.stat(source)
            index[rel] = [stat.st_size, stat.st_mtime_ns, sha256(source)]
            if rel.endswith(".json"):
                os.makedirs(os.path.dirname(self.kept(rel)), exist_ok=True)
                shutil.copy2(source, self.kept(rel))
        save_json(os.path.join(self.pristine, "index.json"), index)
        save_json(os.path.join(self.pristine, "applied.json"), {})

    def save_state(self):
        save_json(self.applied_path, self.applied)
        save_json(self.lost_path, sorted(self.lost))

    def original_exists(self, rel):
        return rel in self.index

    def original_path(self, rel):
        """Where the original of rel is (kept, or in place if never patched), or None: not
        an original file, or one replaced in place before it was kept."""
        if not self.original_exists(rel):
            return None
        if os.path.exists(self.kept(rel)):
            return self.kept(rel)
        return self.path(rel) if rel not in self.applied and os.path.exists(self.path(rel)) else None

    def unchanged(self, rel):
        size, mtime, digest = self.index[rel]
        stat = os.stat(self.path(rel))
        return stat.st_size == size and (stat.st_mtime_ns == mtime or sha256(self.path(rel)) == digest)

    def keep_original(self, rel):
        if not self.original_exists(rel) or os.path.exists(self.kept(rel)) or not os.path.exists(self.path(rel)):
            return
        if not self.unchanged(rel):
            if rel not in self.lost:
                print(f"warning: {rel} was changed in place, its original is not kept (unzip the "
                      "asset pack again to get it back)")
                self.lost.add(rel)
            return
        os.makedirs(os.path.dirname(self.kept(rel)), exist_ok=True)
        shutil.copy2(self.path(rel), self.kept(rel))

    def hand_edited(self):
        """Patched files whose content differs from what the last apply wrote."""
        return [rel for rel, digest in sorted(self.applied.items())
                if not os.path.exists(self.path(rel)) or sha256(self.path(rel)) != digest]

    def restore(self):
        for rel in sorted(self.applied):
            if os.path.exists(self.kept(rel)):
                shutil.copy2(self.kept(rel), self.path(rel))
            elif self.original_exists(rel):
                pass  # replaced in place before it was kept (see keep_original)
            elif os.path.exists(self.path(rel)):
                os.remove(self.path(rel))
        self.applied = {}
        self.save_state()


# --- The patches ---

def patches(root):
    """{asset path: patch file} for every file in the patches folder."""
    out = {}
    if not os.path.isdir(root):
        return out
    for folder, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(names):
            if name.startswith(".") or (name == "README.md" and folder == root):
                continue
            source = os.path.join(folder, name)
            rel = os.path.relpath(source, root).replace(os.sep, "/")
            if rel.endswith(PATCH_SUFFIX):
                rel = rel[:-len(PATCH_SUFFIX)] + ".json"
            if rel in out:
                sys.exit(f"{rel} is both patched and replaced in {root}")
            out[rel] = source
    return out


def apply(assets, patch_root, force=False):
    edited = assets.hand_edited()
    if edited and not force:
        sys.exit("Edited by hand since the last apply (keep the edits with `capture`, or drop "
                 "them with --force):\n  " + "\n  ".join(edited))
    assets.restore()
    todo = patches(patch_root)
    for rel, source in sorted(todo.items()):
        target = assets.path(rel)
        assets.keep_original(rel)
        if source.endswith(PATCH_SUFFIX):
            original = assets.original_path(rel)
            if original is None:
                sys.exit(f"{os.path.relpath(source)} patches {rel}, which the asset folder lacks")
            save_json(target, merge(load_json(original), load_json(source)))
        else:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copyfile(source, target)
        assets.applied[rel] = sha256(target)
    assets.save_state()
    print(f"Applied {len(todo)} patch{'es' if len(todo) != 1 else ''} from {os.path.relpath(patch_root)}.")


def status(assets, patch_root):
    todo = patches(patch_root)
    stale = [rel for rel, source in todo.items() if rel not in assets.applied]
    gone = [rel for rel in assets.applied if rel not in todo]
    edited = set(assets.hand_edited())
    for rel in assets.files():
        if rel not in assets.applied and (not assets.original_exists(rel) or not assets.unchanged(rel)):
            edited.add(rel)
    removed = [rel for rel in assets.index if rel not in assets.applied and not os.path.exists(assets.path(rel))]
    for title, rels in (("Not applied yet (run apply)", stale), ("Patch removed (run apply)", gone),
                        ("Edited, not captured", sorted(edited)), ("Missing from the asset folder", removed)):
        if rels:
            print(f"{title}:\n  " + "\n  ".join(sorted(rels)))
    if not (stale or gone or edited or removed):
        print(f"Up to date: {len(assets.applied)} patched file{'s' if len(assets.applied) != 1 else ''}.")


def capture(assets, patch_root, files):
    maps_dir = os.path.join(os.path.dirname(assets.root), "maps")
    for name in files:
        full = os.path.abspath(name)
        if full.startswith(assets.root + os.sep):
            rel = os.path.relpath(full, assets.root).replace(os.sep, "/")
        elif full.startswith(maps_dir + os.sep) and os.path.dirname(full) == maps_dir:
            rel = "maps/" + os.path.basename(full)
        else:
            sys.exit(f"{name} is neither in {assets.root} nor in {maps_dir}")
        if not os.path.isfile(full):
            sys.exit(f"No file {name}")
        replace = os.path.join(patch_root, rel)
        merge_patch = os.path.join(patch_root, rel[:-len(".json")] + PATCH_SUFFIX) if rel.endswith(".json") else None
        if rel not in assets.applied:
            assets.keep_original(rel)  # still the original unless it was edited in place
        original = assets.original_path(rel) or (assets.kept(rel) if os.path.exists(assets.kept(rel)) else None)
        if merge_patch and original:
            change = diff(load_json(original), load_json(full))
            if change is None:
                print(f"{rel}: same as the original, no patch")
                if os.path.exists(merge_patch):
                    os.remove(merge_patch)
            else:
                save_json(merge_patch, change, pretty=True)
                print(f"{rel} -> {os.path.relpath(merge_patch)}")
        else:
            os.makedirs(os.path.dirname(replace), exist_ok=True)
            shutil.copyfile(full, replace)
            note = "  (replaces an original file: commit only your own work)" if assets.original_exists(rel) else ""
            print(f"{rel} -> {os.path.relpath(replace)}{note}")
        if rel.startswith("maps/") and full.startswith(maps_dir):
            continue  # the editor's copy stays where it is; apply adds it to the asset folder
        assets.applied[rel] = sha256(full)  # captured: no longer an uncaptured edit
    assets.save_state()


def make_zip(assets, out):
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as pack:
        for rel in sorted(assets.index):
            source = assets.original_path(rel)
            if source:
                pack.write(source, "assets/" + rel)
                count += 1
            else:
                print(f"warning: no original kept of {rel}, left out")
    print(f"Wrote {out}: {count} original files, without the patches.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["apply", "status", "capture", "restore", "zip"])
    parser.add_argument("files", nargs="*")
    parser.add_argument("--assets", default=os.path.join(ROOT, "assets"))
    parser.add_argument("--patches", default=os.path.join(ROOT, "asset_patches"))
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    assets = Assets(args.assets)
    patch_root = os.path.abspath(args.patches)
    if args.command == "apply":
        apply(assets, patch_root, args.force)
    elif args.command == "status":
        status(assets, patch_root)
    elif args.command == "capture":
        if not args.files:
            sys.exit("capture: name the edited files")
        capture(assets, patch_root, args.files)
    elif args.command == "restore":
        assets.restore()
        print("Back to the originals.")
    elif len(args.files) != 1:
        sys.exit("zip: name the zip file to write")
    else:
        make_zip(assets, args.files[0])


if __name__ == "__main__":
    main()
