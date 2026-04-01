#!/bin/bash
# ============================================================
# Baseline VCS Simulation Script
# Usage: source /path/to/synopsys_env.sh && bash run_baseline.sh
# ============================================================
set -e
cd "$(dirname "$0")/.."

echo "============================================================"
echo "  FlashAttention Baseline — VCS Simulation"
echo "============================================================"

OUTDIR=/tmp/fa_submission
mkdir -p $OUTDIR

echo "[1/2] Compiling..."
vcs -full64 -sverilog \
    +incdir+baseline/rtl/include \
    baseline/rtl/exp_lut_rom.sv \
    baseline/rtl/exp_approx_unit.sv \
    baseline/rtl/reciprocal_unit.sv \
    baseline/rtl/causal_mask_unit.sv \
    baseline/rtl/dot_product_array.sv \
    baseline/rtl/online_softmax_unit.sv \
    baseline/rtl/output_accumulator.sv \
    baseline/rtl/compute_core.sv \
    baseline/rtl/buffer_system.sv \
    baseline/rtl/tile_controller.sv \
    baseline/rtl/axi4_lite_slave.sv \
    baseline/rtl/axi4_master_if.sv \
    baseline/rtl/dma_engine.sv \
    baseline/rtl/flash_attention_top.sv \
    baseline/tb/unit_tb/axi4_slave_mem.sv \
    baseline/tb/unit_tb/system_tb.sv \
    -timescale=1ns/1ps +define+SIMULATION \
    -o $OUTDIR/baseline_simv 2>&1 | tail -10

echo ""
echo "[2/2] Running simulation..."
$OUTDIR/baseline_simv 2>&1 | tail -20

echo ""
echo "============================================================"
echo "  Baseline simulation complete"
echo "============================================================"
