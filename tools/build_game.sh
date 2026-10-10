#!/usr/bin/env bash
# Builds standalone copies of the game for Linux and Windows (x86_64) in build/:
#   build/linux/america-remastered.x86_64 + .pck
#   build/windows/america-remastered.exe  + .pck
# each with an assets/ folder beside the program. No Godot project or editor needed to run.
#
# Usage: tools/build_game.sh [linux|windows ...]   (default: both)
#   COPY_ASSETS=1  copy the asset folder instead of linking it, so the build folder can be
#                  zipped and moved to another machine. The copy stores colour pictures as
#                  lossless WebP, with the colour under transparent pixels kept only near
#                  visible ones (tools/pack_assets.py --trim=8, needs ImageMagick).
#   ZIP=1          also pack each build into build/america-remastered-<platform>.zip
#                  (implies COPY_ASSETS=1).
#
# Needs the Godot export templates matching the installed Godot version
# (~/.local/share/godot/export_templates/<version>/), from the official release's
# Godot_v<version>-stable_export_templates.tpz.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
ZIP=${ZIP:-0}
COPY_ASSETS=${COPY_ASSETS:-$ZIP}
platforms=("$@")
[ ${#platforms[@]} -gt 0 ] || platforms=(linux windows)

version=$("$GODOT" --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?\.[a-z0-9]+).*/\1/')
templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$version"
if [ ! -f "$templates/version.txt" ]; then
	echo "Missing Godot export templates for $version in $templates" >&2
	exit 1
fi

if [ "$COPY_ASSETS" = 1 ]; then
	rm -rf build/packed-assets build/packed-assets.tmp
fi

for platform in "${platforms[@]}"; do
	case "$platform" in
		linux) preset=Linux; program=america-remastered.x86_64 ;;
		windows) preset=Windows; program=america-remastered.exe ;;
		*) echo "Unknown platform: $platform (linux or windows)" >&2; exit 1 ;;
	esac
	out="build/$platform"
	mkdir -p "$out"
	"$GODOT" --headless --path game --export-release "$preset" "../$out/$program"
	rm -rf "$out/assets"
	if [ "$COPY_ASSETS" = 1 ]; then
		# Packed once, then shared by each platform's copy.
		if [ ! -d build/packed-assets ]; then
			tools/pack_assets.py --trim=8 assets build/packed-assets.tmp
			mv build/packed-assets.tmp build/packed-assets
		fi
		cp -r build/packed-assets "$out/assets"
	else
		ln -s ../../assets "$out/assets"
	fi
	if [ "$ZIP" = 1 ]; then
		rm -f "build/america-remastered-$platform.zip"
		(cd build && mv "$platform" america-remastered \
			&& zip -qr "america-remastered-$platform.zip" america-remastered; \
			mv america-remastered "$platform")
	fi
	echo "Built: $out/$program"
done
