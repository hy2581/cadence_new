#!/bin/bash
# ============================================================
# Bonus VCS Simulation Script (Direct TB — 19 tests)
# Usage: source /path/to/synopsys_env.sh && bash run_bonus.sh
# ============================================================
set -e
cd "$(dirname "$0")/.."

echo "============================================================"
echo "  FlashAttention Bonus — VCS Simulation (19 tests)"
echo "============================================================"

OUTDIR=/tmp/fa_submission
mkdir -p $OUTDIR

echo "[1/2] Compiling..."
vcs -full64 -sverilog \
    +incdir+bonus/rtl/include \
    +incdir+baseline/rtl/include \
    baseline/rtl/exp_lut_rom.sv \
    baseline/rtl/exp_approx_unit.sv \
    baseline/rtl/reciprocal_unit.sv \
    baseline/rtl/dot_product_array.sv \
    baseline/rtl/online_softmax_unit.sv \
    baseline/rtl/output_accumulator.sv \
    baseline/rtl/buffer_system.sv \
    baseline/rtl/axi4_master_if.sv \
    baseline/rtl/dma_engine.sv \
    bonus/rtl/task_queue.sv \
    bonus/rtl/axi4_stream_if.sv \
    bonus/rtl/bf16_exp_unit.sv \
    bonus/rtl/bf16_reciprocal_unit.sv \
    bonus/rtl/int8_quantizer.sv \
    bonus/rtl/axi4_lite_slave_bonus.sv \
    bonus/rtl/tile_controller_bonus.sv \
    bonus/rtl/compute_core_bonus.sv \
    bonus/rtl/flash_attention_bonus_top.sv \
    baseline/tb/unit_tb/axi4_slave_mem.sv \
    bonus/tb/bonus_system_tb.sv \
    -timescale=1ns/1ps +define+SIMULATION \
    -o $OUTDIR/bonus_simv 2>&1 | tail -10

echo ""
echo "[2/2] Running simulation..."
$OUTDIR/bonus_simv 2>&1

echo ""
echo "============================================================"
echo "  Bonus simulation complete"
echo "============================================================"
