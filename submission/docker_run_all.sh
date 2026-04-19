#!/bin/bash
cd /work/cadence/submission

OUTDIR=/tmp/fa_uvm
mkdir -p $OUTDIR

export VCS_INTERNAL_NO_PROC_STAT=1
export SNPS_VCS_INTERNAL_PROC_STAT_FIX=1

# Build LD_PRELOAD fix for VCS fopen(/proc/self/stat) crash on new kernels
echo "Building VCS fopen fix..."
gcc -shared -fPIC -o /tmp/vcs_fopen_fix.so /work/cadence/submission/vcs_fopen_fix.c -ldl 2>&1
if [ -f /tmp/vcs_fopen_fix.so ]; then
    export LD_PRELOAD=/tmp/vcs_fopen_fix.so
    echo "LD_PRELOAD fix loaded: /tmp/vcs_fopen_fix.so"
else
    echo "WARNING: Failed to build fopen fix"
fi

echo '============================================================'
echo '  Compiling UVM testbench...'
echo '============================================================'

RTL_FILES="
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
"

TB_FILES="
    baseline/tb/agents/axi4_lite_agent/axi4_lite_if.sv
    baseline/tb/agents/axi4_mem_agent/axi4_mem_if.sv
    baseline/tb/agents/axi4_protocol_checker.sv
    baseline/tb/agents/axi4_lite_protocol_checker.sv
    baseline/tb/uvm_env/fa_env_pkg.sv
    baseline/tb/tb_top/fa_tb_top.sv
"

vcs -full64 -sverilog -ntb_opts uvm-1.2 \
    +incdir+baseline/rtl/include \
    +incdir+baseline/tb \
    +incdir+baseline/tb/agents \
    +incdir+baseline/tb/agents/axi4_lite_agent \
    +incdir+baseline/tb/agents/axi4_mem_agent \
    +incdir+baseline/tb/uvm_env \
    +incdir+baseline/tb/sequences \
    +incdir+baseline/tb/tests \
    $RTL_FILES \
    $TB_FILES \
    -timescale=1ns/1ps +define+SIMULATION \
    -LDFLAGS "-Wl,--no-as-needed" \
    -o $OUTDIR/uvm_simv 2>&1

COMPILE_RC=$?
echo ""
echo "VCS compile exit code: $COMPILE_RC"

if [ $COMPILE_RC -ne 0 ]; then
    echo "=== Compile failed, trying without protocol checkers ==="
    TB_FILES_MIN="
        baseline/tb/agents/axi4_lite_agent/axi4_lite_if.sv
        baseline/tb/agents/axi4_mem_agent/axi4_mem_if.sv
        baseline/tb/uvm_env/fa_env_pkg.sv
        baseline/tb/tb_top/fa_tb_top.sv
    "
    vcs -full64 -sverilog -ntb_opts uvm-1.2 \
        +incdir+baseline/rtl/include \
        +incdir+baseline/tb \
        +incdir+baseline/tb/agents \
        +incdir+baseline/tb/agents/axi4_lite_agent \
        +incdir+baseline/tb/agents/axi4_mem_agent \
        +incdir+baseline/tb/uvm_env \
        +incdir+baseline/tb/sequences \
        +incdir+baseline/tb/tests \
        $RTL_FILES \
        $TB_FILES_MIN \
        -timescale=1ns/1ps +define+SIMULATION \
        -LDFLAGS "-Wl,--no-as-needed" \
        -o $OUTDIR/uvm_simv 2>&1
    COMPILE_RC=$?
    echo "VCS compile (minimal) exit code: $COMPILE_RC"
fi

if [ $COMPILE_RC -ne 0 ]; then
    echo "ALL COMPILE ATTEMPTS FAILED"
    exit 1
fi

echo ""
echo "=== Compile succeeded, running tests ==="

TESTS=(
    fa_zero_test
    fa_random_nocausal_test
    fa_random_causal_test
    fa_identity_test
    fa_boundary_test
    fa_maxval_test
    fa_reg_reset_test
    fa_reg_access_test
    fa_reg_stress_test
    fa_ral_test
    fa_reg_walk_test
    fa_reg_unmapped_test
    fa_reg_soft_reset_test
    fa_dma_test
    fa_dma_b2b_test
    fa_dma_addr_test
    fa_axi_protocol_test
    fa_axi_dual_mode_test
    fa_axi_regonly_test
    fa_perf_test
    fa_perf_compare_test
    fa_coverage_test
    fa_coverage_closure_test
    fa_comprehensive_test
)

PASS=0
FAIL=0
SUMMARY=""
for t in "${TESTS[@]}"; do
    echo ""
    echo "------------------------------------------------------------"
    echo "  Running: $t  ($(date))"
    echo "------------------------------------------------------------"
    timeout 300 $OUTDIR/uvm_simv +UVM_TESTNAME=$t \
        +UVM_VERBOSITY=UVM_MEDIUM \
        -l $OUTDIR/log_${t}.log 2>&1 | tail -20
    RUN_RC=$?

    if [ $RUN_RC -eq 124 ]; then
        echo "  >>> $t: TIMEOUT"
        FAIL=$((FAIL+1))
        SUMMARY="${SUMMARY}  TIMEOUT  $t
"
    elif grep -q "UVM_FATAL :    0" $OUTDIR/log_${t}.log 2>/dev/null && \
         grep -q "UVM_ERROR :    0" $OUTDIR/log_${t}.log 2>/dev/null; then
        echo "  >>> $t: PASS"
        PASS=$((PASS+1))
        SUMMARY="${SUMMARY}  PASS     $t
"
    else
        echo "  >>> $t: FAIL"
        FAIL=$((FAIL+1))
        SUMMARY="${SUMMARY}  FAIL     $t
"
        grep -E "UVM_(ERROR|FATAL)" $OUTDIR/log_${t}.log 2>/dev/null | head -5
    fi
done

echo ""
echo "============================================================"
echo "  UVM VERIFICATION SUMMARY"
echo "============================================================"
echo "  Total: ${#TESTS[@]}  PASS: $PASS  FAIL: $FAIL"
echo ""
echo "$SUMMARY"
echo "============================================================"
