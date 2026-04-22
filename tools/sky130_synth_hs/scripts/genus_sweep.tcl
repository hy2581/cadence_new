# ============================================================
#  Genus Fmax 扫描脚本 — 读取 env var CLK_PERIOD (ns)
#  在同一进程内重复跑若干周期，每次把报告落到 reports_<period>ns/
# ============================================================
set DESIGN flash_attention_top
set WORK   [pwd]
set PDK    /tmp/sky130_pdk/sky130A
set HS_LIB $PDK/libs.ref/sky130_fd_sc_hs/lib

if {[info exists ::env(CLK_PERIOD)]} {
    set PERIOD $::env(CLK_PERIOD)
} else {
    set PERIOD 10.0
}
set PERIOD_TAG [format "%.1f" $PERIOD]
regsub {\.} $PERIOD_TAG "p" PERIOD_TAG
set OUTDIR "reports_${PERIOD_TAG}ns"

# --- 库 ---
set_db init_lib_search_path $HS_LIB
set_db library              {sky130_fd_sc_hs__tt_025C_1v80.lib}

# --- HDL ---
set_db hdl_search_path      "$WORK/rtl $WORK/rtl/include"
set_db hdl_error_on_blackbox true

set RTL_FILES [list \
    rtl/exp_lut_rom.sv          \
    rtl/exp_approx_unit.sv      \
    rtl/reciprocal_unit.sv      \
    rtl/causal_mask_unit.sv     \
    rtl/dot_product_array.sv    \
    rtl/online_softmax_unit.sv  \
    rtl/output_accumulator.sv   \
    rtl/compute_core.sv         \
    rtl/buffer_system.sv        \
    rtl/tile_controller.sv      \
    rtl/axi4_lite_slave.sv      \
    rtl/axi4_master_if.sv       \
    rtl/dma_engine.sv           \
    rtl/flash_attention_top.sv  \
]

read_hdl -sv -define {SYNTHESIS} $RTL_FILES
elaborate $DESIGN
current_design $DESIGN
check_design -unresolved

# --- 时序 ---
create_clock -name clk -period $PERIOD [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]
set_clock_transition  0.1 [get_clocks clk]
set_input_delay  [expr $PERIOD * 0.20] -clock clk \
    [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay [expr $PERIOD * 0.20] -clock clk [all_outputs]
set_false_path -from [get_ports rst_n]
set_load 0.02 [all_outputs]
set_max_fanout    32  [current_design]
set_max_transition 0.5 [current_design]

# --- 综合策略：效果偏向时序，以便压紧主频 ---
set_db syn_generic_effort high
set_db syn_map_effort     high
set_db syn_opt_effort     high
set_db lp_insert_clock_gating false

puts "==== Fmax sweep: target period = $PERIOD ns ===="
puts "==== syn_generic ===="
syn_generic
puts "==== syn_map ===="
syn_map
puts "==== syn_opt ===="
syn_opt

file mkdir $OUTDIR
file mkdir results

write_hdl > results/${DESIGN}_netlist_${PERIOD_TAG}ns.v
write_sdc > results/${DESIGN}_${PERIOD_TAG}ns.sdc

foreach {fname cmd} {
    design.rpt        "report_design"
    timing_max.rpt    "report_timing -max_paths 50"
    timing_top20.rpt  "report_timing -max_paths 20 -nworst 5"
    area.rpt          "report_area -depth 10"
    power.rpt         "report_power"
    qor.rpt           "report_qor"
    gates_nand2eq.rpt "report_area -normalize_with_gate sky130_fd_sc_hs__nand2_1"
} {
    set rc [catch { eval "$cmd > $OUTDIR/$fname" } err]
    if {$rc != 0} { puts "report FAILED: $fname : $err" }
}

puts "================================================"
puts "  Sweep done at PERIOD=$PERIOD ns -> $OUTDIR"
puts "================================================"
exit 0
