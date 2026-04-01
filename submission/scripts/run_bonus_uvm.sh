#!/bin/bash
# ============================================================
# Bonus UVM Simulation Script (5 UVM tests)
# Usage: source /path/to/synopsys_env.sh && bash run_bonus_uvm.sh [TESTNAME]
# Available tests:
#   fa_bonus_causal_test    — Baseline causal attention
#   fa_bonus_padding_test   — Padding mask
#   fa_bonus_dropout_test   — Dropout mode
#   fa_bonus_bf16_test      — BF16 format
#   fa_bonus_combined_test  — Combined features (2 heads + causal + padding)
# ============================================================
set -e
cd "$(dirname "$0")/.."

TESTNAME=${1:-fa_bonus_causal_test}
OUTDIR=/tmp/fa_submission
mkdir -p $OUTDIR

echo "============================================================"
echo "  FlashAttention Bonus — UVM Test: $TESTNAME"
echo "============================================================"

# Compile (only if binary doesn't exist)
if [ ! -f $OUTDIR/bonus_uvm_simv ]; then
    echo "[1/2] Compiling UVM..."
    vcs -full64 -sverilog -ntb_opts uvm-1.2 \
        -timescale=1ns/1ps \
        +incdir+bonus/rtl/include \
        +incdir+baseline/rtl/include \
        +incdir+baseline/tb \
        +incdir+baseline/tb/uvm_env \
        +incdir+baseline/tb/agents/axi4_lite_agent \
        +incdir+baseline/tb/agents/axi4_mem_agent \
        +incdir+baseline/tb/sequences \
        +incdir+baseline/tb/tests \
        +incdir+bonus/tb \
        +incdir+bonus/tb/uvm_env \
        +incdir+bonus/tb/sequences \
        +incdir+bonus/tb/tests \
        baseline/rtl/exp_lut_rom.sv \
        baseline/rtl/exp_approx_unit.sv \
        baseline/rtl/reciprocal_unit.sv \
        baseline/rtl/dot_product_array.sv \
        baseline/rtl/online_softmax_unit.sv \
        baseline/rtl/output_accumulator.sv \
        baseline/rtl/buffer_system.sv \
        baseline/rtl/axi4_master_if.sv \
        baseline/rtl/dma_engine.sv \
        bonus/rtl/bf16_exp_unit.sv \
        bonus/rtl/bf16_reciprocal_unit.sv \
        bonus/rtl/int8_quantizer.sv \
        bonus/rtl/mask_unit.sv \
        bonus/rtl/dropout_unit.sv \
        bonus/rtl/task_queue.sv \
        bonus/rtl/axi4_stream_if.sv \
        bonus/rtl/axi4_lite_slave_bonus.sv \
        bonus/rtl/tile_controller_bonus.sv \
        bonus/rtl/compute_core_bonus.sv \
        bonus/rtl/flash_attention_bonus_top.sv \
        baseline/tb/agents/axi4_lite_agent/axi4_lite_if.sv \
        baseline/tb/agents/axi4_mem_agent/axi4_mem_if.sv \
        bonus/tb/uvm_env/fa_bonus_env_pkg.sv \
        bonus/tb/tb_top/fa_bonus_tb_top.sv \
        +define+SIMULATION \
        -o $OUTDIR/bonus_uvm_simv 2>&1 | tail -10
fi

echo ""
echo "[2/2] Running UVM test: $TESTNAME..."
$OUTDIR/bonus_uvm_simv +UVM_TESTNAME=$TESTNAME +UVM_VERBOSITY=UVM_LOW 2>&1 | tail -30

echo ""
echo "============================================================"
echo "  UVM test $TESTNAME complete"
echo "============================================================"
