# ============================================================
#  Genus 综合脚本 — Sky130 sky130_fd_sc_hs (官方钦点库)
#  顶层 : flash_attention_top
#
#  路径假设（由 run.sh 设置好）：
#    PDK :  /tmp/sky130_pdk/sky130A
#    RTL :  /tmp/sky130_synth_hs/rtl  （已经从 submission/baseline/rtl 同步过来）
#    WORK:  /tmp/sky130_synth_hs       （Genus 当前工作目录）
#
#  Liberty 角：sky130_fd_sc_hs__tt_025C_1v80.lib  (typical, 1.8V, 25C)
#  目标主频   ：100 MHz (10 ns) — Sky130 HS 上的"拿得到数据"起点；正负 slack 都
#             记录到 reports/，后续可以迭代收紧周期
# ============================================================

set DESIGN flash_attention_top
set WORK   [pwd]
set PDK    /tmp/sky130_pdk/sky130A
set HS_LIB $PDK/libs.ref/sky130_fd_sc_hs/lib

# --- 库 ---
set_db init_lib_search_path  $HS_LIB
set_db library               {sky130_fd_sc_hs__tt_025C_1v80.lib}

# 注：不加载 cell LEF。sky130A 的 cell LEF (sky130_fd_sc_hs.lef) 引用了 li1/met1/
# pwell/nwell 等层，这些层只在 SkyWater 的 cadence tech LEF 里定义，而 PDK tar 里
# 没有 tech LEF。强行 set_db lef_library 会导致 PHYS-100/PHYS-10/TUI-48 错误并
# abort 综合。Genus 不需要 cell LEF 就可以做 syn_generic/syn_map/syn_opt，PnR
# 阶段（Innovus）才需要。

# --- HDL 搜索路径 ---
set_db hdl_search_path       "$WORK/rtl $WORK/rtl/include"
set_db hdl_error_on_blackbox true

# --- 读 RTL（按依赖顺序排列：底层 → 顶层）---
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

# --- 顶层综合 ---
elaborate $DESIGN
current_design $DESIGN
check_design -unresolved

# --- 时序约束 (内嵌；不读 submission/.../flash_attention.sdc 是因为它的 2ns 太激进) ---
set CLK_PERIOD 10.0
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]
set_clock_transition  0.1 [get_clocks clk]

set_input_delay  [expr $CLK_PERIOD * 0.20] -clock clk \
    [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay [expr $CLK_PERIOD * 0.20] -clock clk [all_outputs]
set_false_path -from [get_ports rst_n]

set_load 0.02 [all_outputs]

set_max_fanout    32  [current_design]
set_max_transition 0.5 [current_design]

# --- 综合策略 (medium = 时间 / 质量平衡) ---
set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium

# 不做 clock gating，避免初次综合就被 lib 中没注册的 latch-based ICG 踩坑
set_db lp_insert_clock_gating false

# --- 三个综合阶段 ---
puts "==== syn_generic ===="
syn_generic

puts "==== syn_map ===="
syn_map

puts "==== syn_opt ===="
syn_opt

# --- 报告输出 ---
file mkdir reports
file mkdir results

# 先把综合后的数据库写下来，哪怕后续报告命令失败，至少 netlist 和 db 拿得到
write_hdl > results/${DESIGN}_netlist.v
write_sdc > results/${DESIGN}.sdc
write_db results/${DESIGN}_post_syn.db

# 接下来是一堆报告；用 Tcl 的 catch {} 包一层，单条失败不影响后续
foreach {fname cmd} {
    design.rpt        "report_design"
    timing_max.rpt    "report_timing -max_paths 50"
    timing_top20.rpt  "report_timing -max_paths 20 -nworst 5"
    area.rpt          "report_area -depth 10"
    area_summary.rpt  "report_area -summary"
    area_detail.rpt   "report_area -detail"
    gates.rpt         "report_area -gates"
    power.rpt         "report_power"
    qor.rpt           "report_qor"
    messages.rpt      "report_messages"
    clock_gating.rpt  "report_clock_gating"
    gates_nand2eq.rpt "report_area -normalize_with_gate sky130_fd_sc_hs__nand2_1"
} {
    set rc [catch {
        set fh [open "reports/$fname" w]
        puts $fh [eval $cmd]
        close $fh
    } err]
    if {$rc != 0} {
        puts "report FAILED: $fname : $err"
        catch { close $fh }
    } else {
        puts "report OK: $fname"
    }
}

puts "================================================"
puts "  Genus synthesis finished: $DESIGN"
puts "  See ./reports/  and  ./results/"
puts "================================================"
exit 0
