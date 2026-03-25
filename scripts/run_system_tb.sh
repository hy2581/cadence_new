#!/bin/bash
# ============================================================
# VCS Compile & Run — FlashAttention System TB
# ============================================================
set -e

export SNPSLMD_LICENSE_FILE=27000@lizhen
export VCS_HOME=/usr/synopsys/vcs-L-2016.06

cd /workspace

echo "================================================"
echo " FlashAttention System TB — VCS Compile & Run"
echo "================================================"

# --- Compile ---
echo "[1/2] Compiling..."
vcs -full64 -sverilog \
    +incdir+rtl/include \
    +define+SIMULATION \
    -timescale=1ns/1ps \
    -LDFLAGS "-Wl,--no-as-needed -Wl,--unresolved-symbols=ignore-in-shared-libs" \
    rtl/exp_lut_rom.sv \
    rtl/exp_approx_unit.sv \
    rtl/reciprocal_unit.sv \
    rtl/causal_mask_unit.sv \
    rtl/dot_product_array.sv \
    rtl/online_softmax_unit.sv \
    rtl/output_accumulator.sv \
    rtl/compute_core.sv \
    rtl/buffer_system.sv \
    rtl/tile_controller.sv \
    rtl/axi4_lite_slave.sv \
    rtl/axi4_master_if.sv \
    rtl/dma_engine.sv \
    rtl/flash_attention_top.sv \
    tb/unit_tb/axi4_slave_mem.sv \
    tb/unit_tb/system_tb.sv \
    -o simv_system \
    -l compile.log \
    2>&1 | tail -30

if [ ! -f simv_system ]; then
    echo "COMPILATION FAILED!"
    echo "Check compile.log for details"
    exit 1
fi

echo ""
echo "[2/2] Running simulation..."
./simv_system -l sim.log 2>&1 | tail -50

echo ""
echo "================================================"
echo " Simulation complete"
echo " Compile log: compile.log"
echo " Sim log: sim.log"
echo "================================================"
