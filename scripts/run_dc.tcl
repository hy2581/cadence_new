# ============================================================
# Design Compiler Synthesis Script for FlashAttention Accelerator
# Usage: dc_shell -f scripts/run_dc.tcl
# ============================================================

# --- Library setup (customize for your PDK) ---
# set target_library "your_target_lib.db"
# set link_library   "* $target_library"
# For demo, use GTECH (generic technology)
set synthetic_library "dw_foundation.sldb"

# --- Read RTL ---
set search_path [list ./rtl ./rtl/include]
define_design_lib work -path ./work_dc

analyze -format sverilog -define SYNTHESIS {
    rtl/include/fa_params.svh
    rtl/exp_approx_unit.sv
    rtl/reciprocal_unit.sv
    rtl/causal_mask_unit.sv
    rtl/dot_product_array.sv
    rtl/online_softmax_unit.sv
    rtl/output_accumulator.sv
    rtl/compute_core.sv
    rtl/buffer_system.sv
    rtl/tile_controller.sv
    rtl/axi4_lite_slave.sv
    rtl/axi4_master_if.sv
    rtl/dma_engine.sv
    rtl/flash_attention_top.sv
}

elaborate flash_attention_top
current_design flash_attention_top

# --- Constraints ---
source constraints/flash_attention.sdc

# --- Compile ---
puts "Starting compile_ultra..."
compile_ultra -no_autoungroup

# --- Reports ---
file mkdir reports/dc_synthesis

report_area -hierarchy > reports/dc_synthesis/area.rpt
report_timing -max_paths 20 > reports/dc_synthesis/timing.rpt
report_power > reports/dc_synthesis/power.rpt
report_qor > reports/dc_synthesis/qor.rpt
report_reference -hierarchy > reports/dc_synthesis/reference.rpt

# --- Write outputs ---
file mkdir netlist
write -format verilog -hierarchy -output netlist/fa_top_netlist.v
write_sdc -nosplit netlist/fa_top.sdc
write_sdf netlist/fa_top.sdf

puts "Synthesis complete. Check reports/dc_synthesis/"
exit
