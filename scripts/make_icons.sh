#!/bin/bash
# Renders the Mousse brand assets and installs them into the asset catalog.
# Usage: ./scripts/make_icons.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ASSETS="Mousse/Assets.xcassets"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift scripts/render_icons.swift "$TMP"

cp "$TMP/MenuBarIcon.pdf" "$ASSETS/MenuBarIcon.imageset/MenuBarIcon.pdf"

ICONSET="$ASSETS/AppIcon.appiconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/icon_1024.png" --out "$ICONSET/icon_${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$TMP/icon_1024.png" --out "$ICONSET/icon_${size}@2x.png" >/dev/null
done
echo "==> Icons installed into $ASSETS"
