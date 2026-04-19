#!/bin/bash
cd /work/cadence/submission

OUTDIR=/tmp/fa_bonus_uvm
mkdir -p $OUTDIR

export VCS_INTERNAL_NO_PROC_STAT=1
export SNPS_VCS_INTERNAL_PROC_STAT_FIX=1

echo "Building VCS fopen fix..."
gcc -shared -fPIC -o /tmp/vcs_fopen_fix.so /work/cadence/submission/vcs_fopen_fix.c -ldl 2>&1
if [ -f /tmp/vcs_fopen_fix.so ]; then
    export LD_PRELOAD=/tmp/vcs_fopen_fix.so
    echo "LD_PRELOAD fix loaded"
fi

echo '============================================================'
echo '  Compiling Bonus UVM testbench...'
echo '============================================================'

RTL_FILES="
    baseline/rtl/exp_lut_rom.sv
    baseline/rtl/exp_approx_unit.sv
    baseline/rtl/reciprocal_unit.sv
    baseline/rtl/dot_product_array.sv
    baseline/rtl/online_softmax_unit.sv
    baseline/rtl/output_accumulator.sv
    baseline/rtl/buffer_system.sv
    baseline/rtl/axi4_master_if.sv
    baseline/rtl/dma_engine.sv
    bonus/rtl/bf16_exp_unit.sv
    bonus/rtl/bf16_reciprocal_unit.sv
    bonus/rtl/int8_quantizer.sv
    bonus/rtl/mask_unit.sv
    bonus/rtl/dropout_unit.sv
    bonus/rtl/task_queue.sv
    bonus/rtl/axi4_stream_if.sv
    bonus/rtl/axi4_lite_slave_bonus.sv
    bonus/rtl/tile_controller_bonus.sv
    bonus/rtl/compute_core_bonus.sv
    bonus/rtl/flash_attention_bonus_top.sv
"

TB_FILES="
    baseline/tb/agents/axi4_lite_agent/axi4_lite_if.sv
    baseline/tb/agents/axi4_mem_agent/axi4_mem_if.sv
    bonus/tb/uvm_env/fa_bonus_env_pkg.sv
    bonus/tb/tb_top/fa_bonus_tb_top.sv
"

vcs -full64 -sverilog -ntb_opts uvm-1.2 \
    +incdir+bonus/rtl/include \
    +incdir+baseline/rtl/include \
    +incdir+baseline/tb \
    +incdir+baseline/tb/agents \
    +incdir+baseline/tb/agents/axi4_lite_agent \
    +incdir+baseline/tb/agents/axi4_mem_agent \
    +incdir+baseline/tb/uvm_env \
    +incdir+baseline/tb/sequences \
    +incdir+baseline/tb/tests \
    +incdir+bonus/tb \
    +incdir+bonus/tb/uvm_env \
    +incdir+bonus/tb/sequences \
    +incdir+bonus/tb/tests \
    $RTL_FILES \
    $TB_FILES \
    -timescale=1ns/1ps +define+SIMULATION \
    -LDFLAGS "-Wl,--no-as-needed" \
    -o $OUTDIR/bonus_uvm_simv 2>&1

COMPILE_RC=$?
echo ""
echo "VCS compile exit code: $COMPILE_RC"

if [ $COMPILE_RC -ne 0 ]; then
    echo "COMPILE FAILED"
    exit 1
fi

echo ""
echo "=== Compile succeeded, running tests ==="

TESTS=(
    fab_zero_test
    fab_random_nocausal_test
    fab_random_causal_test
    fab_identity_test
    fab_boundary_test
    fab_maxval_test
    fab_reg_reset_test
    fab_reg_access_test
    fab_reg_stress_test
    fab_reg_frontdoor_test
    fab_reg_walk_test
    fab_reg_unmapped_test
    fab_reg_soft_reset_test
    fab_dma_test
    fab_dma_b2b_test
    fab_dma_addr_test
    fab_axi_protocol_test
    fab_axi_dual_mode_test
    fab_axi_regonly_test
    fab_perf_test
    fab_perf_compare_test
    fab_coverage_test
    fab_coverage_closure_test
    fab_comprehensive_test
)

PASS=0
FAIL=0
SUMMARY=""
for t in "${TESTS[@]}"; do
    echo ""
    echo "------------------------------------------------------------"
    echo "  Running: $t  ($(date))"
    echo "------------------------------------------------------------"
    timeout 300 $OUTDIR/bonus_uvm_simv +UVM_TESTNAME=$t \
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
echo "  BONUS UVM VERIFICATION SUMMARY"
echo "============================================================"
echo "  Total: ${#TESTS[@]}  PASS: $PASS  FAIL: $FAIL"
echo ""
echo "$SUMMARY"
echo "============================================================"
