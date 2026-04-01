// ============================================================
// FlashAttention Bonus UVM Environment Package
// ============================================================
package fa_bonus_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Reuse baseline agents
    `include "agents/axi4_lite_agent/axi4_lite_txn.sv"
    `include "agents/axi4_lite_agent/axi4_lite_driver.sv"
    `include "agents/axi4_lite_agent/axi4_lite_monitor.sv"
    `include "agents/axi4_lite_agent/axi4_lite_sequencer.sv"
    `include "agents/axi4_lite_agent/axi4_lite_agent.sv"
    `include "agents/axi4_mem_agent/axi4_mem_agent.sv"

    // Reuse baseline sequences (reg_write, reg_read)
    `include "sequences/fa_sequences.sv"

    // Bonus-specific components
    `include "bonus/tb/uvm_env/fa_bonus_scoreboard.sv"
    `include "bonus/tb/uvm_env/fa_bonus_coverage.sv"
    `include "bonus/tb/uvm_env/fa_bonus_env.sv"

    // Bonus sequences and tests
    `include "bonus/tb/sequences/fa_bonus_sequences.sv"
    `include "bonus/tb/tests/fa_bonus_tests.sv"
endpackage
