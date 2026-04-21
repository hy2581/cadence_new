#!/usr/bin/env bash
# ============================================================
#  Sky130 + Genus 综合驱动器 (HS 库 — 赛题官方钦点)
#
#  调用前置:
#    1. 已经把 /workspace/tools/sky130_synth_hs/ 的内容 (scripts/ + rtl/) 解到 /tmp/sky130_synth_hs
#    2. /home/share/sky130A.tar.gz 已经解到 /tmp/sky130_pdk/sky130A
#       (本脚本会自动按需解压, ~30s, 1.5GB)
#    3. 远端 shell = bash; cwd = /tmp/sky130_synth_hs
#
#  产物:
#    $WORK/reports/    timing/area/power/qor 报告
#    $WORK/results/    综合后网表 + sdc
#    $WORK/genus_run.log  完整运行日志
#    $SHARE/sky130_synth_hs_result_<TS>.tar.gz   打包到 FILES tab 方便下载
# ============================================================
set -u
set -o pipefail

WORK=/tmp/sky130_synth_hs
PDK_TAR=/home/share/sky130A.tar.gz
PDK_DIR=/tmp/sky130_pdk
SHARE="$HOME/neere/Start Mate Desktop"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$WORK/genus_run.log"
RESULT_TAR="$SHARE/sky130_synth_hs_result_${TS}.tar.gz"

mkdir -p "$WORK"
cd "$WORK" || { echo "WORK dir $WORK missing"; exit 2; }

# ---- 1. 准备 PDK (按需解压) -------------------------------
HS_LIB="$PDK_DIR/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib"
if [ ! -f "$HS_LIB" ]; then
    echo "[setup] sky130A not yet extracted; untar $PDK_TAR -> $PDK_DIR (~30s)..."
    mkdir -p "$PDK_DIR"
    tar xzf "$PDK_TAR" -C "$PDK_DIR" || { echo "PDK untar failed"; exit 3; }
fi
[ -f "$HS_LIB" ] || { echo "HS lib still missing after extract: $HS_LIB"; exit 4; }
echo "[setup] HS lib OK: $HS_LIB"

# ---- 2. 加载 EDA modules ---------------------------------
source /usr/share/Modules/init/bash
module load license ddi
GENUS_BIN=$(command -v genus || true)
[ -n "$GENUS_BIN" ] || { echo "genus not in PATH after module load"; exit 5; }
echo "[setup] genus = $GENUS_BIN"

# ---- 3. 跑 Genus -----------------------------------------
{
  echo "==================== env ===================="
  date
  whoami
  hostname
  echo "WORK=$WORK"
  echo "HS_LIB=$HS_LIB"
  $GENUS_BIN -version | head -3
  echo "==================== run ===================="
} > "$LOG" 2>&1

genus -batch -no_gui -files scripts/genus_synth.tcl >> "$LOG" 2>&1
RC=$?

echo "==================== exit code: $RC ====================" >> "$LOG"

# ---- 4. 打包结果 ------------------------------------------
PACKED=$WORK/packed_${TS}
mkdir -p "$PACKED"
[ -d "$WORK/reports" ] && cp -r "$WORK/reports" "$PACKED/"
[ -d "$WORK/results" ] && cp -r "$WORK/results" "$PACKED/"
cp "$LOG" "$PACKED/" 2>/dev/null || true
[ -f "$WORK/genus.log" ] && cp "$WORK/genus.log" "$PACKED/"
[ -f "$WORK/genus.cmd" ] && cp "$WORK/genus.cmd" "$PACKED/"

tar czf "$RESULT_TAR" -C "$PACKED" . 2>>"$LOG"
echo "[done] result tar: $RESULT_TAR" >> "$LOG"

# 顺手把 log 单独复制一份到 FILES，避免 tar 里嵌套不好看
cp "$LOG" "$SHARE/genus_run_hs_${TS}.log"

echo "DONE rc=$RC tar=$RESULT_TAR"
exit $RC
