#!/usr/bin/env bash
# Packs magisk_module/ into a flashable Magisk module zip.
set -euo pipefail
cd "$(dirname "$0")"

OUT="hwlevel_p0_override.zip"
rm -f "$OUT"
cd magisk_module
zip -r9 "../$OUT" . -x ".*" "last_run.log"
cd ..

echo "Built $OUT"
echo "Install it either:"
echo "  - via the Magisk app: Modules -> Install from storage -> $OUT"
echo "  - or in TWRP/fastbootd: flash it like any other zip"
