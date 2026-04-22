#!/bin/bash
# ============================================================
# Remote driver for Xcelium UVM simulation on Cadence Cloud (sh02lo02).
#   - Unpacks submission tarball into /tmp
#   - Loads license + xcelium modules
#   - Runs xrun_uvm_all.sh
#   - Packages logs + merged coverage into a result tarball
#   - Copies the tarball and a summary log to the FILES tab
#     (real path on the remote: $HOME/neere/Start Mate Desktop/)
#
# Invoked from the client side as e.g.:
#   python3 tools/cadence_runner.py exec \
#     'cd /tmp && rm -rf submission && tar xzf "$HOME/neere/Start Mate Desktop/submission_xrun.tar.gz" \
#      && cd submission && nohup bash scripts/xrun_remote_driver.sh \
#           > /tmp/xrun_outer.log 2>&1 & echo PID=$!' \
#     --open-term --after 8000
# ============================================================
set -u

TAG=${TAG:-$(date +%Y%m%d_%H%M%S)}
OUTDIR=/tmp/fa_xrun
FILES_TAB="$HOME/neere/Start Mate Desktop"

mkdir -p "$OUTDIR"
: > "$OUTDIR/driver.log"
exec > >(tee -a "$OUTDIR/driver.log") 2>&1

echo "[xrun-driver] tag=$TAG host=$(hostname) date=$(date -Is)"

# ---- 1. Load Cadence modules (license + xcelium) -----------------
if [[ -f /usr/share/Modules/init/sh ]]; then
    # shellcheck disable=SC1091
    source /usr/share/Modules/init/sh
else
    echo "[xrun-driver] WARNING: modules init script not found; assuming PATH is already set up"
fi
module load license xcelium || {
    echo "[xrun-driver] ERROR: cannot load license/xcelium modules"
    exit 2
}
module list 2>&1
command -v xrun
command -v imc || true
xrun -version | head -5 || true

# ---- 2. Run UVM test suite ---------------------------------------
# ENV overrides:
#   WAVE_TEST=<name>       → 在 <name> 上启用 SHM 波形 dump
cd "$(dirname "$0")/.."
echo "[xrun-driver] cwd=$(pwd)  wave='${WAVE_TEST:-}'"
WAVE_TEST="${WAVE_TEST:-}" bash scripts/xrun_uvm_all.sh 2>&1 | tee "$OUTDIR/xrun_all.log"
XRUN_RC=${PIPESTATUS[0]}
echo "[xrun-driver] xrun_uvm_all.sh rc=$XRUN_RC"

# SPEC_CHECK grep: 赛题 2.1(8) 误差门限
SPEC_SUM="$OUTDIR/spec_check_${TAG}.txt"
{
    echo "=== SPEC_CHECK 汇总 (赛题 2.1(8): mean<=0.03 max<=0.10) ==="
    grep -H "SPEC_CHECK" "$OUTDIR"/log_*.log 2>/dev/null || echo "(no SPEC_CHECK found)"
} > "$SPEC_SUM"
cat "$SPEC_SUM"

# ---- 3. Build a compact summary ----------------------------------
SUMMARY="$OUTDIR/summary_${TAG}.txt"
{
    echo "=== Xcelium UVM Simulation Summary ==="
    echo "host       : $(hostname)"
    echo "date       : $(date -Is)"
    echo "outdir     : $OUTDIR"
    echo "xrun_rc    : $XRUN_RC"
    echo
    echo "=== Per-test classification (UVM_ERROR / UVM_FATAL = 0 => PASS) ==="
    for f in "$OUTDIR"/log_*.log; do
        [[ -f $f ]] || continue
        t=$(basename "$f" .log); t=${t#log_}
        fatal=$(grep -E "UVM_FATAL\s*:\s*[0-9]+" "$f" | tail -1 | grep -oE "[0-9]+$" || echo NA)
        ferr=$(grep -E "UVM_ERROR\s*:\s*[0-9]+" "$f" | tail -1 | grep -oE "[0-9]+$" || echo NA)
        if [[ "$fatal" == "0" && "$ferr" == "0" ]]; then v=PASS; else v=FAIL; fi
        printf "  %-34s %s  (UVM_ERROR=%s UVM_FATAL=%s)\n" "$t" "$v" "$ferr" "$fatal"
    done
    echo
    echo "=== Elaboration tail (last 30 lines) ==="
    tail -n 30 "$OUTDIR/elab.log" 2>/dev/null || echo "(no elab.log)"
    echo
    echo "=== Coverage summary (if imc merge succeeded) ==="
    head -n 80 "$OUTDIR/coverage_report.txt" 2>/dev/null || echo "(no coverage_report.txt)"
} > "$SUMMARY"
cat "$SUMMARY"

# ---- 4. Pack results for download via FILES tab ------------------
RESULT_TGZ="$FILES_TAB/xrun_result_${TAG}.tar.gz"
mkdir -p "$FILES_TAB"

# Keep tarball reasonably small: logs + merged coverage (+ waves if dumped).
TMPPACK=$(mktemp -d)
mkdir -p "$TMPPACK/fa_xrun"
cp "$OUTDIR"/*.log             "$TMPPACK/fa_xrun/" 2>/dev/null || true
cp "$OUTDIR"/driver.log        "$TMPPACK/fa_xrun/" 2>/dev/null || true
cp "$OUTDIR"/summary_*.txt     "$TMPPACK/fa_xrun/" 2>/dev/null || true
cp "$OUTDIR"/spec_check_*.txt  "$TMPPACK/fa_xrun/" 2>/dev/null || true
cp "$OUTDIR"/imc_merge.log     "$TMPPACK/fa_xrun/" 2>/dev/null || true
cp "$OUTDIR"/coverage_report.txt "$TMPPACK/fa_xrun/" 2>/dev/null || true
# SHM 波形目录 (如果有) — 直接整体打包
for shm in "$OUTDIR"/waves_*.shm; do
    [[ -d $shm ]] || continue
    size=$(du -sm "$shm" | awk '{print $1}')
    echo "[xrun-driver] pack SHM dir $shm (${size}M)"
    cp -r "$shm" "$TMPPACK/fa_xrun/"
done
# HTML coverage directory (can be big — only if present and < 50 MB)
if [[ -d $OUTDIR/coverage_report_html ]]; then
    size=$(du -sm "$OUTDIR/coverage_report_html" | awk '{print $1}')
    if (( size < 50 )); then
        cp -r "$OUTDIR/coverage_report_html" "$TMPPACK/fa_xrun/"
    else
        echo "[xrun-driver] skipping coverage_report_html (size ${size}M)"
    fi
fi
tar czf "$RESULT_TGZ" -C "$TMPPACK" fa_xrun
rm -rf "$TMPPACK"
echo "[xrun-driver] result tarball -> $RESULT_TGZ"

# Also drop the summary directly in FILES tab so the polling agent can see it fast.
cp "$SUMMARY" "$FILES_TAB/xrun_summary_${TAG}.txt" 2>/dev/null || true

# ---- 5. Marker file so the polling loop on the client side wakes up ------
echo "xrun_result_${TAG}.tar.gz" > "$FILES_TAB/xrun_done_${TAG}.marker"

echo "[xrun-driver] DONE   rc=$XRUN_RC"
exit $XRUN_RC
