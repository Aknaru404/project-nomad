#!/usr/bin/env bash
# Downloads the third-party web assets bundled into the iPad app. They are not committed.
# Versions match what the NOMAD server uses (admin/package.json and the pinned CyberChef image).
set -euo pipefail

MAPLIBRE_VERSION=4.7.1
PMTILES_VERSION=4.4.0
CYBERCHEF_VERSION=10.19.4
# Crosstalk-Solutions/project-nomad-maps commit holding base-assets.tar.gz (styles, sprites, fonts).
NOMAD_MAPS_COMMIT=5b444051914fbf4960be2e64c0fb11f507db7efd

cd "$(dirname "$0")/../NOMAD/Resources"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "MapLibre $MAPLIBRE_VERSION and PMTiles $PMTILES_VERSION"
mkdir -p Web/vendor
curl -fsSL "https://registry.npmjs.org/maplibre-gl/-/maplibre-gl-$MAPLIBRE_VERSION.tgz" | tar xz -C "$tmp"
cp "$tmp/package/dist/maplibre-gl.js" "$tmp/package/dist/maplibre-gl.css" Web/vendor/
rm -rf "$tmp/package"
curl -fsSL "https://registry.npmjs.org/pmtiles/-/pmtiles-$PMTILES_VERSION.tgz" | tar xz -C "$tmp"
cp "$tmp/package/dist/pmtiles.js" Web/vendor/

echo "NOMAD map styles, sprites and fonts"
rm -rf MapAssets && mkdir -p MapAssets
curl -fsSL "https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad-maps/$NOMAD_MAPS_COMMIT/base-assets.tar.gz" \
  | tar xz -C MapAssets --strip-components=1
test -f MapAssets/nomad-base-styles.json

echo "CyberChef $CYBERCHEF_VERSION"
rm -rf CyberChef && mkdir -p CyberChef
curl -fsSL -o "$tmp/cyberchef.zip" \
  "https://github.com/gchq/CyberChef/releases/download/v$CYBERCHEF_VERSION/CyberChef_v$CYBERCHEF_VERSION.zip"
unzip -q "$tmp/cyberchef.zip" -d CyberChef
mv "CyberChef/CyberChef_v$CYBERCHEF_VERSION.html" CyberChef/CyberChef.html

echo "Done"
