#!/usr/bin/env bash
# 本地 (cloud agent) 端: 把 tools/sky130_synth_hs/scripts/ + submission/baseline/rtl/ 打成 tar
# 然后通过 cadence_runner.py upload 推到远端 FILES tab
set -e

ROOT="$(cd "$(dirname "$0")"/../.. && pwd)"      # /workspace
SYNTH_DIR="$ROOT/tools/sky130_synth_hs"
RTL_DIR="$ROOT/submission/baseline/rtl"
STAGE=/tmp/sky130_synth_hs_stage
TAR=/tmp/sky130_synth_hs.tar.gz

[ -d "$RTL_DIR" ] || { echo "RTL dir missing: $RTL_DIR"; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/sky130_synth_hs"
cp -r "$SYNTH_DIR/scripts" "$STAGE/sky130_synth_hs/"
cp -r "$RTL_DIR" "$STAGE/sky130_synth_hs/"

cd "$STAGE"
tar czf "$TAR" sky130_synth_hs/
echo "packed -> $TAR ($(du -h $TAR | cut -f1))"

cd "$ROOT"
python3 tools/cadence_runner.py upload "$TAR"
echo "upload OK"
