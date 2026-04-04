// FlashAttention UVM Environment
class fa_env extends uvm_env;
    `uvm_component_utils(fa_env)

    axi4_lite_agent   axil_agent;
    axi4_mem_agent    mem_agent;
    fa_scoreboard     scoreboard;
    fa_coverage       coverage;

    fa_reg_block      reg_model;
    fa_reg_adapter    reg_adapter;
    uvm_reg_predictor #(axi4_lite_txn) reg_predictor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axil_agent = axi4_lite_agent::type_id::create("axil_agent", this);
        mem_agent  = axi4_mem_agent::type_id::create("mem_agent", this);
        scoreboard = fa_scoreboard::type_id::create("scoreboard", this);
        coverage   = fa_coverage::type_id::create("coverage", this);

        reg_model = fa_reg_block::type_id::create("reg_model");
        reg_model.build();

        reg_adapter = fa_reg_adapter::type_id::create("reg_adapter");
        reg_predictor = uvm_reg_predictor #(axi4_lite_txn)::type_id::create("reg_predictor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        axil_agent.mon.ap.connect(coverage.analysis_export);

        reg_model.default_map.set_sequencer(axil_agent.sqr, reg_adapter);
        reg_model.default_map.set_auto_predict(0);

        reg_predictor.map     = reg_model.default_map;
        reg_predictor.adapter = reg_adapter;
        axil_agent.mon.ap.connect(reg_predictor.bus_in);
    endfunction
endclass
