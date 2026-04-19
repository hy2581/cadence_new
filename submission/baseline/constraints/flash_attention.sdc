# ============================================================
# SDC Constraints for FlashAttention Accelerator
# Target: 500 MHz (2 ns period)
# ============================================================

# --- Clock Definition ---
create_clock -name clk -period 2.0 [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks clk]
set_clock_transition 0.05 [get_clocks clk]

# --- Reset ---
set_false_path -from [get_ports rst_n]

# --- Input Delays ---
set_input_delay 0.5 -clock clk [remove_from_collection [all_inputs] {clk rst_n}]

# --- Output Delays ---
set_output_delay 0.5 -clock clk [all_outputs]

# --- AXI4-Lite Slave Interface ---
set_input_delay  0.3 -clock clk [get_ports s_axil_*]
set_output_delay 0.3 -clock clk [get_ports s_axil_*]

# --- AXI4 Master Interface ---
set_input_delay  0.3 -clock clk [get_ports m_axi_*ready]
set_input_delay  0.3 -clock clk [get_ports m_axi_r*]
set_input_delay  0.3 -clock clk [get_ports m_axi_b*]
set_output_delay 0.3 -clock clk [get_ports m_axi_a*]
set_output_delay 0.3 -clock clk [get_ports m_axi_w*]

# --- Area Optimization ---
set_max_area 0

# --- Design Rules ---
set_max_fanout 32 [current_design]
set_max_transition 0.2 [current_design]
