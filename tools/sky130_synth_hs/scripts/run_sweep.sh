#!/usr/bin/env bash
# ============================================================
#  Genus Fmax 扫描远端 driver
#  依次在同一 WORK 下跑 CLK_PERIOD = 8 / 6 / 5 / 4 ns
#  每次产出 reports_<p>ns/{qor,timing_max,area,power,gates_nand2eq}.rpt
#  扫完把全部结果 + sweep log 打包到 FILES tab
# ============================================================
set -u
set -o pipefail

WORK=/tmp/sky130_synth_hs
PDK_TAR=/home/share/sky130A.tar.gz
PDK_DIR=/tmp/sky130_pdk
SHARE="$HOME/neere/Start Mate Desktop"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$WORK/genus_sweep_${TS}.log"
RESULT_TAR="$SHARE/sky130_synth_hs_sweep_${TS}.tar.gz"

mkdir -p "$WORK"
cd "$WORK" || { echo "WORK dir $WORK missing"; exit 2; }

# 1. PDK
HS_LIB="$PDK_DIR/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib"
if [ ! -f "$HS_LIB" ]; then
    echo "[setup] untar PDK..."
    mkdir -p "$PDK_DIR"
    tar xzf "$PDK_TAR" -C "$PDK_DIR"
fi
[ -f "$HS_LIB" ] || { echo "HS lib missing"; exit 4; }

# 2. modules
source /usr/share/Modules/init/bash
module load license ddi

# 3. sweep
# 目的: 找隐含 Fmax 上限。从当前已知 100MHz MET+1102ps 出发，逐级加压。
#   10 ns = 100 MHz  (baseline)
#    8 ns = 125 MHz
#    6 ns = 166 MHz
#    5 ns = 200 MHz
#    4 ns = 250 MHz
# 跑到第一次 slack 严重为负 (<-500ps) 就停，说明越过了物理极限。
PERIODS=(8.0 6.0 5.0 4.0)

{
  echo "==================== Fmax sweep begin ===================="
  date
  hostname
  echo "WORK=$WORK"
  genus -version | head -2
} > "$LOG" 2>&1

for P in "${PERIODS[@]}"; do
    echo "============================================================" | tee -a "$LOG"
    echo "  Running Genus at CLK_PERIOD=${P}ns" | tee -a "$LOG"
    echo "============================================================" | tee -a "$LOG"
    CLK_PERIOD=$P genus -batch -no_gui -files scripts/genus_sweep.tcl >> "$LOG" 2>&1
    RC=$?
    echo "  -> exit rc=$RC at ${P}ns" | tee -a "$LOG"

    # 早停条件: 解析 qor，WNS < -1000 ps (-1 ns) 就跳出 (节省单点 ~6h 综合时间)
    PTAG=$(echo "$P" | tr '.' 'p')
    QOR="$WORK/reports_${PTAG}ns/qor.rpt"
    if [ -f "$QOR" ]; then
        WNS=$(awk '/Critical Path Slack/ {print $(NF-1)}' "$QOR" | head -1)
        echo "  WNS @ ${P}ns: $WNS" | tee -a "$LOG"
        if [ -n "$WNS" ] && awk "BEGIN{exit !($WNS < -1000)}" 2>/dev/null; then
            echo "  EARLY STOP: WNS=${WNS}ps < -1000ps at ${P}ns; skipping tighter periods" | tee -a "$LOG"
            break
        fi
    else
        echo "  WARN: $QOR missing; continuing" | tee -a "$LOG"
    fi
done

# 4. 打包
PACKED=$WORK/packed_sweep_${TS}
mkdir -p "$PACKED"
for d in "$WORK"/reports_*ns; do
    [ -d "$d" ] && cp -r "$d" "$PACKED/"
done
[ -d "$WORK/results" ] && cp -r "$WORK/results" "$PACKED/"
cp "$LOG" "$PACKED/"

tar czf "$RESULT_TAR" -C "$PACKED" . 2>>"$LOG"
cp "$LOG" "$SHARE/genus_sweep_${TS}.log"

echo "DONE tar=$RESULT_TAR" | tee -a "$LOG"
exit 0
