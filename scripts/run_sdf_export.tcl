# Export SDF/DDC from an existing gate netlist without overwriting DC evidence.

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
set OUT_DIR [file normalize [env_or_default SDF_EXPORT_OUT_DIR [file join $WS build dc_sdf_export]]]
set REPORT_DIR [file join $OUT_DIR reports]
set NETLIST_DIR [file join $OUT_DIR netlist]
set WORK_DIR [file join $OUT_DIR work_dc]
set TOP [env_or_default SDF_EXPORT_TOP "flash_attention_top"]
set IN_NETLIST [file normalize [env_or_default SDF_EXPORT_NETLIST [file join $WS build dc_quality_lint_timing_20260518_1523 netlist fa_top_netlist.v]]]
set IN_SDC [file normalize [env_or_default SDF_EXPORT_SDC [file join $WS build dc_quality_lint_timing_20260518_1523 netlist fa_top.sdc]]]
set SDF_VERSION [env_or_default SDF_EXPORT_VERSION "2.1"]

file mkdir $OUT_DIR
file mkdir $REPORT_DIR
file mkdir $NETLIST_DIR
file mkdir $WORK_DIR

if {![file exists $IN_NETLIST]} {
    puts "ERROR: input netlist not found: $IN_NETLIST"
    exit 2
}
if {![file exists $IN_SDC]} {
    puts "ERROR: input SDC not found: $IN_SDC"
    exit 2
}

set snps_install_root [env_or_default SYNOPSYS ""]
set syn_lib_dir ""
if {$snps_install_root ne ""} {
    set maybe_syn_lib [file join $snps_install_root libraries syn]
    if {[file isdirectory $maybe_syn_lib]} {
        set syn_lib_dir [file normalize $maybe_syn_lib]
    }
}

set target_from_env [env_or_default DC_TARGET_LIB ""]
set sky130_target_from_env [env_or_default SKY130_TARGET_LIB ""]
set user_home [env_or_default HOME ""]
set sky130_hs_default_target ""
if {$user_home ne ""} {
    set sky130_hs_default_target [file join $user_home cadence_codex_run_20260430_2114 pdk sky130_fd_sc_hs db sky130_fd_sc_hs__tt_025C_1v80_noccsn.db]
}

set PDK_LIB [first_existing_file [list \
    $target_from_env \
    $sky130_target_from_env \
    $sky130_hs_default_target \
    [file join $WS lib NangateOpenCellLibrary.db] \
    [file join $syn_lib_dir class.db] \
    [file join $syn_lib_dir lsi_10k.db] \
]]

if {$PDK_LIB eq ""} {
    puts "ERROR: no target .db library found."
    exit 2
}

set DW_LIB [env_or_default DC_DW_LIB [first_existing_file [list \
    [file join $syn_lib_dir dw_foundation.sldb] \
    /eda/synopsys2025/syn/X-2025.06-SP4/libraries/syn/dw_foundation.sldb \
]]]

puts "=============================================="
puts " SDF export setup"
puts "=============================================="
puts "Project root  : $WS"
puts "Output dir    : $OUT_DIR"
puts "Input netlist : $IN_NETLIST"
puts "Input SDC     : $IN_SDC"
puts "Target library: $PDK_LIB"
puts "DW library    : $DW_LIB"
puts "=============================================="

set_app_var target_library [list $PDK_LIB]
if {$DW_LIB ne ""} {
    set_app_var synthetic_library [list $DW_LIB]
    set_app_var link_library [list "*" $PDK_LIB $DW_LIB]
} else {
    set_app_var link_library [list "*" $PDK_LIB]
}
set_app_var search_path [list [file dirname $IN_NETLIST] $NETLIST_DIR $syn_lib_dir]
define_design_lib work -path $WORK_DIR

puts "=============================================="
puts "Reading gate netlist"
puts "=============================================="
read_verilog $IN_NETLIST
current_design $TOP
link

puts "=============================================="
puts "Applying exported SDC"
puts "=============================================="
source $IN_SDC

report_or_warn [file join $REPORT_DIR dc_sdf_export_check_design.rpt] {check_design}
report_or_warn [file join $REPORT_DIR dc_sdf_export_qor.rpt] {report_qor}
report_or_warn [file join $REPORT_DIR dc_sdf_export_timing_max.rpt] {report_timing -path full -delay max -max_paths 20 -nosplit}
report_or_warn [file join $REPORT_DIR dc_sdf_export_timing_min.rpt] {report_timing -path full -delay min -max_paths 10 -nosplit}

set OUT_DDC [file join $NETLIST_DIR fa_top.ddc]
set OUT_SDF [file join $NETLIST_DIR fa_top.sdf]
set OUT_SPEF [file join $NETLIST_DIR fa_top.spef]

puts "=============================================="
puts "Writing DDC/SDF/SPEF"
puts "=============================================="
if {[catch {write -format ddc -hierarchy -output $OUT_DDC} err]} {
    puts "WARNING: failed to write DDC $OUT_DDC: $err"
} else {
    puts "DDC: $OUT_DDC"
}
if {[catch {write_sdf -version $SDF_VERSION $OUT_SDF} err]} {
    puts "ERROR: failed to write SDF $OUT_SDF: $err"
    exit 3
} else {
    puts "SDF: $OUT_SDF"
}
if {[catch {write_parasitics -output $OUT_SPEF} err]} {
    puts "WARNING: failed to write parasitics/SPEF $OUT_SPEF: $err"
} else {
    puts "SPEF/parasitics: $OUT_SPEF"
}

puts ""
puts "SDF export complete."
puts "Reports: $REPORT_DIR"
puts "Netlist exports: $NETLIST_DIR"
puts ""

exit
