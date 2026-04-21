#!/usr/bin/env bash
# 本地 (cloud agent) 端: 把 tools/sky130_synth_hs/scripts/ + submission/baseline/rtl/ 打成 tar
# 然后通过 cadence_runner.py upload 推到远端 FILES tab
#
# 已知坑 (见 tools/ACCESS.md §5.8)：FILES tab upload 不会覆盖同名文件，
# 会变成 foo.tar(N).gz，远端脚本仍然解旧 tar。为了回避，这个脚本：
#   1. 先远端强制 rm foo.tar.gz 和所有 foo.tar(N).gz
#   2. 再 upload，落名 sky130_synth_hs.tar.gz
#   3. md5 校验远端和本地的是同一个包
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
LOCAL_MD5=$(md5sum "$TAR" | cut -d' ' -f1)
echo "packed -> $TAR ($(du -h $TAR | cut -f1)) md5=$LOCAL_MD5"

cd "$ROOT"

# Step 1: 远端强制清理所有旧 tar (容错：任何一条失败都继续)
echo "[pack] clearing remote sky130_synth_hs*.tar.gz ..."
python3 tools/cadence_runner.py exec \
  'cd "$HOME/neere/Start Mate Desktop" && rm -f sky130_synth_hs.tar.gz "sky130_synth_hs.tar(1).gz" "sky130_synth_hs.tar(2).gz" "sky130_synth_hs.tar(3).gz"; ls -la sky130_synth_hs*.tar.gz 2>&1 | head -5' \
  --after 5000 || true

# Step 2: upload
python3 tools/cadence_runner.py upload "$TAR"

# Step 3: verify
echo "[pack] verifying remote md5 matches local ..."
python3 tools/cadence_runner.py exec \
  'md5sum "$HOME/neere/Start Mate Desktop/sky130_synth_hs.tar.gz" 2>&1; ls -la "$HOME/neere/Start Mate Desktop/"sky130_synth_hs*.tar.gz 2>&1' \
  --after 5000 || true
echo "[pack] local md5: $LOCAL_MD5"
echo "[pack] if remote md5 matches, you're good; if not, name the tar something unique (add a timestamp) and update run.sh"
