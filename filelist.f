// FlashAttention Accelerator — File List
// RTL include path
+incdir+rtl/include

// RTL source files
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

// Testbench interfaces
tb/agents/axi4_lite_agent/axi4_lite_if.sv
tb/agents/axi4_mem_agent/axi4_mem_if.sv

// UVM environment package
+incdir+tb
+incdir+tb/uvm_env
+incdir+tb/agents/axi4_lite_agent
+incdir+tb/agents/axi4_mem_agent
+incdir+tb/sequences
+incdir+tb/tests
tb/uvm_env/fa_env_pkg.sv

// Testbench top
tb/tb_top/fa_tb_top.sv
