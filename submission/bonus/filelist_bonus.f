// FlashAttention Bonus — File List
+incdir+bonus/rtl/include
+incdir+rtl/include

// Baseline RTL modules (reused)
rtl/exp_lut_rom.sv
rtl/exp_approx_unit.sv
rtl/reciprocal_unit.sv
rtl/dot_product_array.sv
rtl/online_softmax_unit.sv
rtl/output_accumulator.sv
rtl/buffer_system.sv
rtl/axi4_master_if.sv
rtl/dma_engine.sv

// Bonus RTL modules (new)
bonus/rtl/bf16_exp_unit.sv
bonus/rtl/bf16_reciprocal_unit.sv
bonus/rtl/int8_quantizer.sv
bonus/rtl/mask_unit.sv
bonus/rtl/dropout_unit.sv
bonus/rtl/task_queue.sv
bonus/rtl/axi4_stream_if.sv
bonus/rtl/axi4_lite_slave_bonus.sv
bonus/rtl/tile_controller_bonus.sv
bonus/rtl/compute_core_bonus.sv
bonus/rtl/flash_attention_bonus_top.sv

// UVM Testbench interfaces
tb/agents/axi4_lite_agent/axi4_lite_if.sv
tb/agents/axi4_mem_agent/axi4_mem_if.sv

// UVM Environment package
+incdir+tb
+incdir+tb/uvm_env
+incdir+tb/agents/axi4_lite_agent
+incdir+tb/agents/axi4_mem_agent
+incdir+tb/sequences
+incdir+tb/tests
+incdir+bonus/tb
+incdir+bonus/tb/uvm_env
+incdir+bonus/tb/sequences
+incdir+bonus/tb/tests
bonus/tb/uvm_env/fa_bonus_env_pkg.sv

// Bonus UVM TB top
bonus/tb/tb_top/fa_bonus_tb_top.sv
