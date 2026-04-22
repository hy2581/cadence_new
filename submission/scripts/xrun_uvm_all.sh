#!/bin/bash
# ============================================================
# Xcelium (xrun) UVM verification runner — Cadence Cloud native
# Mirrors run_uvm_all.sh but uses xrun instead of VCS.
# Intended host: sh02lo02 (Cadence Cloud, RHEL 8).
# Requires: `source /usr/share/Modules/init/sh && module load license xcelium`
# Usage:    bash xrun_uvm_all.sh                  # run all tests
#           bash xrun_uvm_all.sh fa_zero_test     # run a single test
# ============================================================
set -eu
cd "$(dirname "$0")/.."

OUTDIR=${OUTDIR:-/tmp/fa_xrun}
mkdir -p "$OUTDIR"

# ---------- Test list (mirrors run_uvm_all.sh) -----------------------------
TESTS=(
    # --- VP: Verification Points ---
    fa_zero_test
    fa_random_nocausal_test
    fa_random_causal_test
    fa_identity_test
    fa_boundary_test
    fa_maxval_test
    # --- REG: Register Model ---
    fa_reg_reset_test
    fa_reg_access_test
    fa_reg_stress_test
    fa_ral_test
    fa_reg_walk_test
    fa_reg_unmapped_test
    fa_reg_soft_reset_test
    # --- DMA ---
    fa_dma_test
    fa_dma_b2b_test
    fa_dma_addr_test
    # --- AXI Protocol ---
    fa_axi_protocol_test
    fa_axi_dual_mode_test
    fa_axi_regonly_test
    # --- Performance ---
    fa_perf_test
    fa_perf_compare_test
    # --- Coverage ---
    fa_coverage_test
    fa_coverage_closure_test
    # --- Comprehensive ---
    fa_comprehensive_test
)

RTL_FILES=(
    baseline/rtl/exp_lut_rom.sv
    baseline/rtl/exp_approx_unit.sv
    baseline/rtl/reciprocal_unit.sv
    baseline/rtl/causal_mask_unit.sv
    baseline/rtl/dot_product_array.sv
    baseline/rtl/online_softmax_unit.sv
    baseline/rtl/output_accumulator.sv
    baseline/rtl/compute_core.sv
    baseline/rtl/buffer_system.sv
    baseline/rtl/tile_controller.sv
    baseline/rtl/axi4_lite_slave.sv
    baseline/rtl/axi4_master_if.sv
    baseline/rtl/dma_engine.sv
    baseline/rtl/flash_attention_top.sv
)

TB_FILES=(
    baseline/tb/agents/axi4_lite_agent/axi4_lite_if.sv
    baseline/tb/agents/axi4_mem_agent/axi4_mem_if.sv
    baseline/tb/agents/axi4_protocol_checker.sv
    baseline/tb/agents/axi4_lite_protocol_checker.sv
    baseline/tb/uvm_env/fa_env_pkg.sv
    baseline/tb/tb_top/fa_tb_top.sv
)

INCDIRS=(
    +incdir+baseline/rtl/include
    +incdir+baseline/tb
    +incdir+baseline/tb/agents
    +incdir+baseline/tb/agents/axi4_lite_agent
    +incdir+baseline/tb/agents/axi4_mem_agent
    +incdir+baseline/tb/uvm_env
    +incdir+baseline/tb/sequences
    +incdir+baseline/tb/tests
)

# xrun common options (compile + elaborate + sim). Tests only differ in +UVM_TESTNAME.
#   -uvm + -uvmhome CDNS-1.2 : pull Cadence-provided UVM 1.2 libs (equiv. VCS -ntb_opts uvm-1.2)
#   -access +rwc             : read/write/connect dumping access
#   -assert                  : enable SystemVerilog assertions / SVA (for our axi protocol checkers)
#   -coverage all            : block + expression + FSM + toggle + assertion (≈ VCS -cm line+cond+fsm+branch+tgl+assert)
XRUN_COMMON=(
    -64bit
    -sv
    -timescale 1ns/1ps
    -uvm -uvmhome CDNS-1.2
    +define+SIMULATION
    -access +rwc
    -assert
    "${INCDIRS[@]}"
)

compile_once() {
    echo "============================================================"
    echo "  Elaborating (xrun -elaborate) — snapshot reused by all tests"
    echo "============================================================"
    local elab_log="$OUTDIR/elab.log"
    rm -rf xcelium.d INCA_libs waves.shm || true
    xrun \
        "${XRUN_COMMON[@]}" \
        "${RTL_FILES[@]}" \
        "${TB_FILES[@]}" \
        -elaborate \
        -snapshot fa_uvm:top \
        -l "$elab_log" 2>&1 | tail -80
    # xrun exits 0 even on some errors; check for elab errors explicitly.
    if grep -qE "^xmelab: \*[EF]," "$elab_log"; then
        echo "ELABORATION FAILED (see $elab_log)"
        return 1
    fi
    echo "Elaboration OK (snapshot = fa_uvm:top)"
}

run_test() {
    local tname=$1
    local log="$OUTDIR/log_${tname}.log"
    local cov="$OUTDIR/cov_${tname}"
    echo ""
    echo "------------------------------------------------------------"
    echo "  Running: $tname   ($(date))"
    echo "------------------------------------------------------------"
    xrun -R \
        -snapshot fa_uvm:top \
        +UVM_TESTNAME=$tname \
        +UVM_VERBOSITY=UVM_MEDIUM \
        -coverage all -covoverwrite -covworkdir "$cov" -covtest "$tname" \
        -l "$log" 2>&1 | tail -30
}

classify_test() {
    local tname=$1
    local log="$OUTDIR/log_${tname}.log"
    if [[ ! -f "$log" ]]; then
        echo "MISSING"; return
    fi
    # UVM final report prints "UVM_FATAL :    N" / "UVM_ERROR :    N"
    local fatal ferr
    fatal=$(grep -E "UVM_FATAL\s*:\s*[0-9]+" "$log" | tail -1 | grep -oE "[0-9]+$" || true)
    ferr=$(grep -E "UVM_ERROR\s*:\s*[0-9]+" "$log" | tail -1 | grep -oE "[0-9]+$" || true)
    if [[ -z "$fatal" || -z "$ferr" ]]; then
        echo "FAIL"
    elif [[ "$fatal" == "0" && "$ferr" == "0" ]]; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

compile_once

if [[ $# -eq 1 ]]; then
    run_test "$1"
    echo ""
    echo ">>> $1: $(classify_test "$1")"
    exit 0
fi

PASS=0
FAIL=0
SUMMARY=""
for t in "${TESTS[@]}"; do
    run_test "$t" || true
    s=$(classify_test "$t")
    echo "  >>> $t: $s"
    if [[ "$s" == "PASS" ]]; then
        PASS=$((PASS+1))
        SUMMARY="${SUMMARY}  PASS     $t
"
    else
        FAIL=$((FAIL+1))
        SUMMARY="${SUMMARY}  $s     $t
"
    fi
done

echo ""
echo "============================================================"
echo "  Xcelium UVM VERIFICATION SUMMARY"
echo "============================================================"
echo "  Total: ${#TESTS[@]}  PASS: $PASS  FAIL: $FAIL"
echo ""
echo "$SUMMARY"

# ---------- Merge coverage with imc (Integrated Metrics Center) --------------
if [[ $PASS -gt 0 ]]; then
    echo ""
    echo "Merging coverage with imc..."
    MERGE_TCL="$OUTDIR/imc_merge.tcl"
    {
        echo "merge \\"
        for t in "${TESTS[@]}"; do
            if [[ -d "$OUTDIR/cov_${t}" ]]; then
                echo "  $OUTDIR/cov_${t} \\"
            fi
        done
        echo "  -out $OUTDIR/cov_merged -overwrite"
        echo "load -run $OUTDIR/cov_merged"
        echo "report -detail -metrics overall -out $OUTDIR/coverage_report.txt -text -overwrite"
        echo "report -html -out $OUTDIR/coverage_report_html -metrics overall -overwrite"
        echo "exit"
    } > "$MERGE_TCL"
    imc -exec "$MERGE_TCL" -nostdout -l "$OUTDIR/imc_merge.log" 2>&1 | tail -20 || true
    echo ""
    echo "Coverage report: $OUTDIR/coverage_report.txt"
    echo "Coverage HTML:   $OUTDIR/coverage_report_html/"
fi
