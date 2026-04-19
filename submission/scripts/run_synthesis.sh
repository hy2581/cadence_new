#!/bin/bash
# ============================================================
# DC Synthesis Script — TSMC 12nm
# ============================================================
set -e
cd "$(dirname "$0")/.."

OUTDIR=/tmp/fa_synth
mkdir -p $OUTDIR

TSMC_LIB="/home/hy258/lib_new/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn12ffcllbwp6t16p96cpd_120a"

cat > $OUTDIR/fa_synth.tcl << 'DCSCRIPT'
# ============================================================
# FlashAttention DC Synthesis
# ============================================================

set DESIGN flash_attention_top
set RTL_DIR "../baseline/rtl"
set TSMC_LIB_DIR $::env(TSMC_LIB_DIR)

# Target library
set target_library "${TSMC_LIB_DIR}/tcbn12ffcllbwp6t16p96cpdtt1v25c.db"
set link_library   "* $target_library"

set_app_var search_path [list $RTL_DIR ${RTL_DIR}/include $TSMC_LIB_DIR]

# Read design
analyze -format sverilog [list \
    ${RTL_DIR}/include/fa_params.svh \
    ${RTL_DIR}/exp_lut_rom.sv \
    ${RTL_DIR}/exp_approx_unit.sv \
    ${RTL_DIR}/reciprocal_unit.sv \
    ${RTL_DIR}/causal_mask_unit.sv \
    ${RTL_DIR}/dot_product_array.sv \
    ${RTL_DIR}/online_softmax_unit.sv \
    ${RTL_DIR}/output_accumulator.sv \
    ${RTL_DIR}/compute_core.sv \
    ${RTL_DIR}/buffer_system.sv \
    ${RTL_DIR}/tile_controller.sv \
    ${RTL_DIR}/axi4_lite_slave.sv \
    ${RTL_DIR}/axi4_master_if.sv \
    ${RTL_DIR}/dma_engine.sv \
    ${RTL_DIR}/flash_attention_top.sv \
]
elaborate $DESIGN

current_design $DESIGN
link

# Clock constraint: 500MHz (2ns period)
set CLK_PERIOD 2.0
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks clk]
set_clock_transition 0.05 [get_clocks clk]

# Input/output delays
set_input_delay  [expr $CLK_PERIOD * 0.2] -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay [expr $CLK_PERIOD * 0.2] -clock clk [all_outputs]

# Reset
set_false_path -from [get_ports rst_n]

# Driving/loading
set_driving_cell -lib_cell BUFFD1BWP6T16P96CPD [all_inputs]
set_load 0.01 [all_outputs]

# Max area (no limit)
set_max_area 0

# Compile
compile_ultra -no_autoungroup

# Reports
report_timing -max_paths 10 > reports/timing.rpt
report_area -hierarchy > reports/area.rpt
report_power > reports/power.rpt
report_qor > reports/qor.rpt
report_constraint -all_violators > reports/violations.rpt

# Write outputs
write -format verilog -hierarchy -output results/${DESIGN}_netlist.v
write -format ddc -hierarchy -output results/${DESIGN}.ddc
write_sdc results/${DESIGN}.sdc
write_sdf results/${DESIGN}.sdf

echo "========================================"
echo "  Synthesis Complete"
echo "========================================"
report_qor | grep -A5 "Timing"
report_area | grep "Total cell area"

exit
DCSCRIPT

# Create output directories
mkdir -p $OUTDIR/reports $OUTDIR/results

echo "============================================================"
echo "  Running DC Synthesis"
echo "  Library: TSMC 12nm tcbn12ffcllbwp6t16p96cpd"
echo "============================================================"

export TSMC_LIB_DIR="$TSMC_LIB"

cd $OUTDIR
dc_shell -f fa_synth.tcl 2>&1 | tee synth.log | tail -30

echo ""
echo "============================================================"
echo "  Synthesis outputs in: $OUTDIR/results/"
echo "  Reports in: $OUTDIR/reports/"
echo "============================================================"
