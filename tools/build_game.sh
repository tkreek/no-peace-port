#!/usr/bin/env bash
# Builds a standalone copy of the game in build/: the program (america-remastered), its
# packed scripts and scenes (america-remastered.pck) and a link to the asset folder.
# Run it with ./build/america-remastered; no Godot project or editor needed.
#
# The program is this machine's Godot runtime, so the build runs on this system. Copy the
# real assets/ folder in place of the link to move the build elsewhere.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
mkdir -p build
"$GODOT" --headless --path game --export-pack Linux ../build/america-remastered.pck
cp "$(command -v "$GODOT")" build/america-remastered
[ -e build/assets ] || ln -s ../assets build/assets
echo "Built: build/america-remastered"
