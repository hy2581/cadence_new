// FlashAttention UVM Environment
class fa_env extends uvm_env;
    `uvm_component_utils(fa_env)

    axi4_lite_agent   axil_agent;
    axi4_mem_agent    mem_agent;
    fa_scoreboard     scoreboard;
    fa_coverage       coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axil_agent = axi4_lite_agent::type_id::create("axil_agent", this);
        mem_agent  = axi4_mem_agent::type_id::create("mem_agent", this);
        scoreboard = fa_scoreboard::type_id::create("scoreboard", this);
        coverage   = fa_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        axil_agent.mon.ap.connect(coverage.analysis_export);
    endfunction
endclass
