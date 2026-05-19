# Design Compiler 2025 synthesis script for FlashAttention.
#
# Recommended wrapper:
#   bash scripts/run_dc.sh
#
# Important environment variables:
#   PROJECT_ROOT   Repository root. Defaults to the current directory.
#   DC_OUT_DIR     Output directory. Defaults to $PROJECT_ROOT/build/dc.
#   DC_TARGET_LIB  Real target .db library. Defaults to the Sky130 library
#                  configured by scripts/sky130_env.sh when available.
#   DC_DW_LIB      Optional DesignWare .sldb override.
#   DC_COMPILE_CMD Optional compile command. Defaults to compile_ultra.
#   DC_ENABLE_TSMC12_FALLBACK
#                  Optional legacy fallback. Keep unset/0 for final Sky130 runs.

proc env_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

proc first_existing_file {candidates} {
    foreach f $candidates {
        if {$f ne "" && [file exists $f]} {
            return [file normalize $f]
        }
    }
    return ""
}

proc report_or_warn {path command_body} {
    puts "Report: $path"
    if {[catch {redirect -file $path $command_body} err]} {
        puts "WARNING: failed to write $path: $err"
    }
}

set WS [file normalize [env_or_default PROJECT_ROOT [pwd]]]
set OUT_DIR [file normalize [env_or_default DC_OUT_DIR [file join $WS build dc]]]
set REPORT_DIR [file join $OUT_DIR reports]
set NETLIST_DIR [file join $OUT_DIR netlist]
set WORK_DIR [file join $OUT_DIR work_dc]

file mkdir $OUT_DIR
file mkdir $REPORT_DIR
file mkdir $NETLIST_DIR
file mkdir $WORK_DIR

if {[catch {set_svf [file join $OUT_DIR default.svf]} err]} {
    puts "WARNING: set_svf failed: $err"
}

set snps_install_root [env_or_default SYNOPSYS ""]
if {$snps_install_root eq ""} {
    set snps_install_root [first_existing_file [list \
        /eda/synopsys2025/syn/X-2025.06-SP4/libraries/syn/dw_foundation.sldb \
    ]]
    if {$snps_install_root ne ""} {
        set snps_install_root [file dirname [file dirname [file dirname $snps_install_root]]]
    }
}

set syn_lib_dir ""
if {$snps_install_root ne ""} {
    set maybe_syn_lib [file join $snps_install_root libraries syn]
    if {[file isdirectory $maybe_syn_lib]} {
        set syn_lib_dir [file normalize $maybe_syn_lib]
    }
}

set target_from_env [env_or_default DC_TARGET_LIB ""]
set sky130_home [env_or_default SKY130_HOME ""]
set sky130_target_from_env [env_or_default SKY130_TARGET_LIB ""]
set user_home [env_or_default HOME ""]
set sky130_hs_default_target ""
set sky130_hd_default_target ""
if {$sky130_home ne ""} {
    set sky130_hd_default_target [file join $sky130_home sky130_hd_v3.db]
}
if {$user_home ne ""} {
    set sky130_hs_default_target [file join $user_home cadence_codex_run_20260430_2114 pdk sky130_fd_sc_hs db sky130_fd_sc_hs__tt_025C_1v80_noccsn.db]
}
set allow_tsmc12_fallback [env_or_default DC_ENABLE_TSMC12_FALLBACK "0"]
set tsmc_home ""
set tsmc12_lib_name ""
set tsmc12_lib_rev ""
set tsmc12_corner ""
set tsmc12_lib_dir ""
set tsmc12_target_from_env ""
set tsmc12_default_target ""
if {$allow_tsmc12_fallback eq "1"} {
    set tsmc_home [env_or_default TSMCHOME ""]
    set tsmc12_lib_name [env_or_default TSMC12_LIB_NAME "tcbn12ffcllbwp6t16p96cpd"]
    set tsmc12_lib_rev [env_or_default TSMC12_LIB_REV "120a"]
    set tsmc12_corner [env_or_default TSMC12_CORNER "ssgnp0p72v125c"]
    set tsmc12_lib_dir [env_or_default TSMC12_LIB_DIR ""]
    if {$tsmc12_lib_dir eq "" && $tsmc_home ne ""} {
        set tsmc12_lib_dir [file join $tsmc_home digital Front_End timing_power_noise NLDM "${tsmc12_lib_name}_${tsmc12_lib_rev}"]
    }
    set tsmc12_target_from_env [env_or_default TSMC12_TARGET_LIB ""]
    if {$tsmc12_lib_dir ne ""} {
        set tsmc12_default_target [file join $tsmc12_lib_dir "${tsmc12_lib_name}${tsmc12_corner}.db"]
    }
}

set PDK_LIB [first_existing_file [list \
    $target_from_env \
    $sky130_target_from_env \
    $sky130_hs_default_target \
    $sky130_hd_default_target \
    $tsmc12_target_from_env \
    $tsmc12_default_target \
    [file join $WS lib NangateOpenCellLibrary.db] \
    [file join $syn_lib_dir class.db] \
    [file join $syn_lib_dir lsi_10k.db] \
]]

if {$PDK_LIB eq ""} {
    puts "ERROR: no target .db library found."
    puts "Set DC_TARGET_LIB=/absolute/path/to/your/standard_cell.db and rerun."
    exit 2
}

set using_sky130_default [expr {$PDK_LIB ne "" && (($sky130_hs_default_target ne "" && [file normalize $PDK_LIB] eq [file normalize $sky130_hs_default_target]) || ($sky130_hd_default_target ne "" && [file normalize $PDK_LIB] eq [file normalize $sky130_hd_default_target]))}]
set using_sky130_env [expr {$PDK_LIB ne "" && $sky130_target_from_env ne "" && [file normalize $PDK_LIB] eq [file normalize $sky130_target_from_env]}]
set using_tsmc12_default [expr {$PDK_LIB ne "" && $tsmc12_default_target ne "" && [file normalize $PDK_LIB] eq [file normalize $tsmc12_default_target]}]
if {!$using_sky130_default && !$using_sky130_env && !$using_tsmc12_default && $target_from_env eq "" && ![file exists [file join $WS lib NangateOpenCellLibrary.db]]} {
    puts "WARNING: no Sky130 target library was found from environment variables."
    puts "WARNING: using fallback target library: $PDK_LIB"
    puts "WARNING: reports from fallback libraries are for flow validation only, not final QoR."
}

set DW_LIB [env_or_default DC_DW_LIB [first_existing_file [list \
    [file join $syn_lib_dir dw_foundation.sldb] \
    /eda/synopsys2025/syn/X-2025.06-SP4/libraries/syn/dw_foundation.sldb \
]]]

puts "=============================================="
puts " DC 2025 FlashAttention synthesis setup"
puts "=============================================="
puts "Project root  : $WS"
puts "Output dir    : $OUT_DIR"
puts "Target library: $PDK_LIB"
puts "SKY130_HOME   : $sky130_home"
puts "Sky130 target : $sky130_target_from_env"
puts "TSMC12 fallback: $allow_tsmc12_fallback"
puts "DW library    : $DW_LIB"
puts "Syn lib dir   : $syn_lib_dir"
puts "=============================================="

set_app_var target_library [list $PDK_LIB]
if {$DW_LIB ne ""} {
    set_app_var synthetic_library [list $DW_LIB]
    set_app_var link_library [list "*" $PDK_LIB $DW_LIB]
} else {
    set_app_var link_library [list "*" $PDK_LIB]
}

set search_dirs [list [file join $WS rtl] [file join $WS rtl include]]
if {$syn_lib_dir ne ""} {
    lappend search_dirs $syn_lib_dir
}
set_app_var search_path $search_dirs

set max_cores [env_or_default DC_MAX_CORES ""]
if {$max_cores ne ""} {
    if {[catch {set_host_options -max_cores $max_cores} err]} {
        puts "WARNING: set_host_options failed: $err"
    }
}

define_design_lib work -path $WORK_DIR

set rtl_files [list \
    [file join $WS rtl exp_lut_rom.sv] \
    [file join $WS rtl exp_approx_unit.sv] \
    [file join $WS rtl reciprocal_unit.sv] \
    [file join $WS rtl causal_mask_unit.sv] \
    [file join $WS rtl dot_product_array.sv] \
    [file join $WS rtl online_softmax_unit.sv] \
    [file join $WS rtl output_accumulator.sv] \
    [file join $WS rtl compute_core.sv] \
    [file join $WS rtl buffer_system.sv] \
    [file join $WS rtl tile_controller.sv] \
    [file join $WS rtl axi4_lite_slave.sv] \
    [file join $WS rtl axi4_master_if.sv] \
    [file join $WS rtl dma_engine.sv] \
    [file join $WS rtl flash_attention_top.sv] \
]

foreach f $rtl_files {
    if {![file exists $f]} {
        puts "ERROR: missing RTL file: $f"
        exit 3
    }
}

puts "=============================================="
puts "Reading RTL"
puts "=============================================="
analyze -format sverilog -define {SYNTHESIS} $rtl_files

puts "=============================================="
puts "Elaborating flash_attention_top"
puts "=============================================="
elaborate flash_attention_top
current_design flash_attention_top
link

puts "=============================================="
puts "Checking design"
puts "=============================================="
report_or_warn [file join $REPORT_DIR dc_check_design.rpt] {check_design}

puts "=============================================="
puts "Applying constraints"
puts "=============================================="
set constraint_file [file join $WS constraints flash_attention.sdc]
if {[file exists $constraint_file]} {
    source $constraint_file
} else {
    puts "WARNING: constraint file not found: $constraint_file"
}

if {[sizeof_collection [get_ports -quiet clk]] > 0} {
    set_input_transition 0.1 [remove_from_collection [all_inputs] [get_ports clk]]
}
set_load 0.01 [all_outputs]

puts "=============================================="
puts "Compiling"
puts "=============================================="
set compile_cmd [env_or_default DC_COMPILE_CMD "compile_ultra -no_autoungroup"]
puts "Compile command: $compile_cmd"
if {[catch {eval $compile_cmd} err]} {
    puts "WARNING: compile command failed: $err"
    puts "WARNING: retrying with compile -map_effort medium -area_effort low"
    compile -map_effort medium -area_effort low
}

puts "=============================================="
puts "Generating reports"
puts "=============================================="
report_or_warn [file join $REPORT_DIR dc_area.rpt] {report_area -hierarchy}
report_or_warn [file join $REPORT_DIR dc_area_nosplit.rpt] {report_area -hierarchy -nosplit}
report_or_warn [file join $REPORT_DIR dc_timing_max.rpt] {report_timing -path full -delay max -max_paths 20 -nosplit}
report_or_warn [file join $REPORT_DIR dc_timing_min.rpt] {report_timing -path full -delay min -max_paths 10 -nosplit}
report_or_warn [file join $REPORT_DIR dc_power.rpt] {report_power -nosplit}
report_or_warn [file join $REPORT_DIR dc_qor.rpt] {report_qor}
report_or_warn [file join $REPORT_DIR dc_reference.rpt] {report_reference -hierarchy -nosplit}
report_or_warn [file join $REPORT_DIR dc_resources.rpt] {report_resources -hierarchy -nosplit}

puts "=============================================="
puts "Writing netlist and SDC"
puts "=============================================="
write -format verilog -hierarchy -output [file join $NETLIST_DIR fa_top_netlist.v]
write_sdc -nosplit [file join $NETLIST_DIR fa_top.sdc]

puts ""
puts "=============================================="
puts "DC synthesis complete"
puts "Reports: $REPORT_DIR"
puts "Netlist: $NETLIST_DIR/fa_top_netlist.v"
puts "=============================================="
puts ""

puts "=== AREA SUMMARY ==="
report_area
puts ""
puts "=== TIMING SUMMARY ==="
report_timing -max_paths 1
puts ""

exit
