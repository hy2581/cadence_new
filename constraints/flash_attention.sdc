# ============================================================
# SDC Constraints for FlashAttention Accelerator
# Target: Sky130 default 100 MHz (10 ns period)
# ============================================================

proc sdc_env_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

set CLK_PERIOD      [sdc_env_or_default DC_CLOCK_PERIOD 10.0]
set CLK_UNCERTAINTY [sdc_env_or_default DC_CLOCK_UNCERTAINTY 0.1]
set CLK_TRANSITION  [sdc_env_or_default DC_CLOCK_TRANSITION 0.1]
set INPUT_DELAY     [sdc_env_or_default DC_INPUT_DELAY 1.0]
set OUTPUT_DELAY    [sdc_env_or_default DC_OUTPUT_DELAY 1.0]
set AXI_DELAY       [sdc_env_or_default DC_AXI_DELAY 0.5]
set MAX_FANOUT      [sdc_env_or_default DC_MAX_FANOUT 32]
set MAX_TRANSITION  [sdc_env_or_default DC_MAX_TRANSITION 1.0]

# --- Clock Definition ---
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty $CLK_UNCERTAINTY [get_clocks clk]
set_clock_transition $CLK_TRANSITION [get_clocks clk]

proc input_ports {pattern} {
    return [filter_collection [get_ports -quiet $pattern] "direction == in"]
}

proc output_ports {pattern} {
    return [filter_collection [get_ports -quiet $pattern] "direction == out"]
}

proc set_input_delay_if_any {delay clock pattern} {
    set ports [input_ports $pattern]
    if {[sizeof_collection $ports] > 0} {
        set_input_delay $delay -clock $clock $ports
    }
}

proc set_output_delay_if_any {delay clock pattern} {
    set ports [output_ports $pattern]
    if {[sizeof_collection $ports] > 0} {
        set_output_delay $delay -clock $clock $ports
    }
}

# --- Reset ---
set_false_path -from [get_ports rst_n]

# --- Input Delays ---
set_input_delay $INPUT_DELAY -clock clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]

# --- Output Delays ---
set_output_delay $OUTPUT_DELAY -clock clk [all_outputs]

# --- AXI4-Lite Slave Interface ---
set_input_delay_if_any  $AXI_DELAY clk s_axil_*
set_output_delay_if_any $AXI_DELAY clk s_axil_*

# --- AXI4 Master Interface ---
set_input_delay_if_any  $AXI_DELAY clk m_axi_*ready
set_input_delay_if_any  $AXI_DELAY clk m_axi_r*
set_input_delay_if_any  $AXI_DELAY clk m_axi_b*
set_output_delay_if_any $AXI_DELAY clk m_axi_a*
set_output_delay_if_any $AXI_DELAY clk m_axi_w*

# --- Area Constraint ---
# Contest-2 requires area below 2M NAND2-equivalent gates. A finite target
# prevents Design Compiler from spending hours in open-ended area recovery.
set_max_area 2000000

# --- Design Rules ---
set_max_fanout $MAX_FANOUT [current_design]
set_max_transition $MAX_TRANSITION [current_design]
