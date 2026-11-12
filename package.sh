#!/bin/bash
# Archivio locale arm64, nessun installer Intel e nessuna pubblicazione.
set -euo pipefail
cd "$(dirname "$0")"
./build-app.sh
mkdir -p dist
tar -czf dist/TBPowerAS-arm64.tar.gz "build/TBPower AS.app" build/tbpower-as-helper install-helper.sh Support LICENSE README.md
shasum -a 256 dist/TBPowerAS-arm64.tar.gz
