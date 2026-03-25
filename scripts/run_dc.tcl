# ============================================================
# Design Compiler Synthesis Script for FlashAttention Accelerator
# Library: NangateOpenCellLibrary (FreePDK45, 45nm)
# Usage: dc_shell -f scripts/run_dc.tcl | tee dc_synth.log
# ============================================================

# --- Set working directory ---
set WS "/workspace"

# --- Library setup ---
set PDK_LIB "${WS}/lib/NangateOpenCellLibrary.db"
set DW_LIB "/usr/synopsys/dc-L-2016.03-SP1/libraries/syn/dw_foundation.sldb"

set_app_var target_library $PDK_LIB
set_app_var link_library   "* $PDK_LIB"
set_app_var synthetic_library $DW_LIB
set_app_var search_path    [list ${WS}/rtl ${WS}/rtl/include /usr/synopsys/dc-L-2016.03-SP1/libraries/syn]

# --- Work library ---
file mkdir ${WS}/work_dc
define_design_lib work -path ${WS}/work_dc

# --- Read RTL (with SYNTHESIS define) ---
puts "=============================================="
puts " Reading RTL..."
puts "=============================================="

analyze -format sverilog -define SYNTHESIS [list \
    ${WS}/rtl/exp_lut_rom.sv \
    ${WS}/rtl/exp_approx_unit.sv \
    ${WS}/rtl/reciprocal_unit.sv \
    ${WS}/rtl/causal_mask_unit.sv \
    ${WS}/rtl/dot_product_array.sv \
    ${WS}/rtl/online_softmax_unit.sv \
    ${WS}/rtl/output_accumulator.sv \
    ${WS}/rtl/compute_core.sv \
    ${WS}/rtl/buffer_system.sv \
    ${WS}/rtl/tile_controller.sv \
    ${WS}/rtl/axi4_lite_slave.sv \
    ${WS}/rtl/axi4_master_if.sv \
    ${WS}/rtl/dma_engine.sv \
    ${WS}/rtl/flash_attention_top.sv \
]

puts "=============================================="
puts " Elaborating flash_attention_top..."
puts "=============================================="

elaborate flash_attention_top
current_design flash_attention_top
link

# --- Check design ---
puts "=============================================="
puts " Checking design..."
puts "=============================================="
file mkdir ${WS}/reports
redirect -file ${WS}/reports/dc_check_design.rpt { check_design }

# --- Constraints ---
puts "=============================================="
puts " Applying constraints..."
puts "=============================================="
source ${WS}/constraints/flash_attention.sdc

# --- Set input transition and output load ---
set_input_transition 0.1 [remove_from_collection [all_inputs] [get_ports clk]]
set_load 0.01 [all_outputs]

# --- Compile ---
puts "=============================================="
puts " Compiling (compile -map_effort medium)..."
puts "=============================================="
compile -map_effort low -area_effort low

# --- Reports ---
puts "=============================================="
puts " Generating reports..."
puts "=============================================="

redirect -file ${WS}/reports/dc_area.rpt          { report_area -hierarchy }
redirect -file ${WS}/reports/dc_area_nosplit.rpt   { report_area -hierarchy -nosplit }
redirect -file ${WS}/reports/dc_timing_max.rpt     { report_timing -path full -delay max -max_paths 20 -nosplit }
redirect -file ${WS}/reports/dc_timing_min.rpt     { report_timing -path full -delay min -max_paths 10 -nosplit }
redirect -file ${WS}/reports/dc_power.rpt          { report_power -nosplit }
redirect -file ${WS}/reports/dc_qor.rpt            { report_qor }
redirect -file ${WS}/reports/dc_reference.rpt      { report_reference -hierarchy -nosplit }
redirect -file ${WS}/reports/dc_resources.rpt      { report_resources -hierarchy -nosplit }

# --- Write outputs ---
file mkdir ${WS}/netlist
write -format verilog -hierarchy -output ${WS}/netlist/fa_top_netlist.v
write_sdc -nosplit ${WS}/netlist/fa_top.sdc

# --- Summary ---
puts ""
puts "=============================================="
puts " DC Synthesis Complete"
puts "=============================================="
puts " Target Library: NangateOpenCellLibrary (45nm)"
puts " Reports: reports/dc_*.rpt"
puts " Netlist: netlist/fa_top_netlist.v"
puts "=============================================="

# Print key results inline
puts ""
puts "=== AREA SUMMARY ==="
report_area
puts ""
puts "=== TIMING SUMMARY ==="
report_timing -max_paths 1
puts ""

exit
