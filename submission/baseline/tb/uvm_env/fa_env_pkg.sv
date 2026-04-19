// FlashAttention UVM Environment Package — Enhanced
package fa_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "agents/axi4_lite_agent/axi4_lite_txn.sv"
    `include "agents/axi4_lite_agent/axi4_lite_driver.sv"
    `include "agents/axi4_lite_agent/axi4_lite_monitor.sv"
    `include "agents/axi4_lite_agent/axi4_lite_sequencer.sv"
    `include "agents/axi4_lite_agent/axi4_lite_agent.sv"

    `include "agents/axi4_mem_agent/axi4_mem_agent.sv"

    `include "uvm_env/fa_reg_model.sv"
    `include "uvm_env/fa_scoreboard.sv"
    `include "uvm_env/fa_coverage.sv"
    `include "uvm_env/fa_env.sv"

    `include "sequences/fa_sequences.sv"
    `include "tests/fa_tests.sv"
endpackage
