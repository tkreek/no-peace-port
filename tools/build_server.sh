#!/usr/bin/env bash
# Packs the dedicated server for a Linux x86_64 machine:
#   build/america-server-linux-x86_64.tar.gz
# holding america-server/ with the game program and its .pck (scripts only: a server needs
# none of the original game's assets), the systemd unit and SETUP.md (server/README.md).
# Copy the archive to the server and follow SETUP.md.
#
# Needs the Godot export templates, as tools/build_game.sh does.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}

out=build/server/america-server
rm -rf build/server
mkdir -p "$out"
"$GODOT" --headless --path game --export-release Linux "../$out/america-remastered.x86_64"
cp server/america-server@.service "$out/"
cp server/README.md "$out/SETUP.md"
protocol=$(sed -nE 's/^const PROTOCOL := ([0-9]+)/\1/p' game/scripts/core/net.gd)
printf 'commit %s\nprotocol %s\nbuilt %s\n' "$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- game || echo +changes)" \
	"$protocol" "$(date -u +%Y-%m-%dT%H:%MZ)" > "$out/VERSION"
tar -C build/server -czf build/america-server-linux-x86_64.tar.gz america-server
echo "Built: build/america-server-linux-x86_64.tar.gz ($(du -h build/america-server-linux-x86_64.tar.gz | cut -f1), protocol $protocol)"
