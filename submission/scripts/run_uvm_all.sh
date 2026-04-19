#!/bin/bash
# ============================================================
# Run all UVM verification tests — Complete Suite
# Covers: VP, AXI VIP, Register, DMA, AXI Protocol, Perf, Cov
# Usage: bash run_uvm_all.sh [test_name]
# ============================================================
set -e
cd "$(dirname "$0")/.."

OUTDIR=/tmp/fa_uvm
mkdir -p $OUTDIR

# ==================== Test List ====================
# Section 1: Verification Points (VP)
# Section 2: Register Model (REG)
# Section 3: DMA
# Section 4: AXI Protocol
# Section 5: Performance
# Section 6: Coverage-Driven
# Section 7: Comprehensive
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

compile_uvm() {
    echo "============================================================"
    echo "  Compiling UVM testbench (protocol checkers enabled)..."
    echo "============================================================"
    vcs -full64 -sverilog -ntb_opts uvm-1.2 \
        +incdir+baseline/rtl/include \
        +incdir+baseline/tb \
        +incdir+baseline/tb/agents \
        +incdir+baseline/tb/agents/axi4_lite_agent \
        +incdir+baseline/tb/agents/axi4_mem_agent \
        +incdir+baseline/tb/uvm_env \
        +incdir+baseline/tb/sequences \
        +incdir+baseline/tb/tests \
        ${RTL_FILES[@]} \
        ${TB_FILES[@]} \
        -timescale=1ns/1ps +define+SIMULATION \
        -assert svaext \
        -cm line+cond+fsm+branch+tgl+assert \
        -o $OUTDIR/uvm_simv 2>&1 | tail -20

    if [ $? -ne 0 ]; then
        echo "COMPILE FAILED"
        exit 1
    fi
    echo "Compile OK"
}

run_test() {
    local tname=$1
    echo ""
    echo "------------------------------------------------------------"
    echo "  Running: $tname"
    echo "------------------------------------------------------------"
    $OUTDIR/uvm_simv +UVM_TESTNAME=$tname \
        -cm line+cond+fsm+branch+tgl+assert \
        -cm_dir $OUTDIR/cm_${tname} \
        +UVM_VERBOSITY=UVM_MEDIUM \
        -l $OUTDIR/log_${tname}.log 2>&1 | tail -30
    echo ""
}

# Compile once
compile_uvm

if [ $# -eq 1 ]; then
    # Run single test
    run_test $1
else
    # Run all tests
    PASS=0
    FAIL=0
    for t in "${TESTS[@]}"; do
        run_test $t
        if grep -q "UVM_ERROR :    0" $OUTDIR/log_${t}.log 2>/dev/null; then
            echo "  >>> $t: PASS"
            PASS=$((PASS+1))
        else
            echo "  >>> $t: FAIL (check $OUTDIR/log_${t}.log)"
            FAIL=$((FAIL+1))
        fi
    done

    echo ""
    echo "============================================================"
    echo "  UVM VERIFICATION SUMMARY"
    echo "============================================================"
    echo "  Total: ${#TESTS[@]}  PASS: $PASS  FAIL: $FAIL"
    echo ""
    echo "  Test Categories:"
    echo "    VP (Verification Points):    6 tests"
    echo "    REG (Register Model):        7 tests"
    echo "    DMA:                         3 tests"
    echo "    AXI Protocol:                3 tests"
    echo "    Performance:                 2 tests"
    echo "    Coverage:                    2 tests"
    echo "    Comprehensive:               1 test"
    echo "============================================================"

    # Merge coverage from all tests
    if [ $PASS -gt 0 ]; then
        echo ""
        echo "Merging coverage from all tests..."
        CM_DIRS=""
        for t in "${TESTS[@]}"; do
            if [ -d "$OUTDIR/cm_${t}" ]; then
                CM_DIRS="$CM_DIRS -dir $OUTDIR/cm_${t}/simv.vdb"
            fi
        done
        if [ -n "$CM_DIRS" ]; then
            urg $CM_DIRS -report $OUTDIR/coverage_report \
                -format both 2>&1 | tail -10
            echo ""
            echo "Coverage report: $OUTDIR/coverage_report"
            echo "  HTML: $OUTDIR/coverage_report/dashboard.html"
            echo "  Text: $OUTDIR/coverage_report/modport.txt"
        fi
    fi
fi
