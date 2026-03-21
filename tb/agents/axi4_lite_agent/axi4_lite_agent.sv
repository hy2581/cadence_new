// AXI4-Lite Agent (Master mode)
class axi4_lite_agent extends uvm_agent;
    `uvm_component_utils(axi4_lite_agent)

    axi4_lite_driver    drv;
    axi4_lite_monitor   mon;
    axi4_lite_sequencer sqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axi4_lite_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            drv = axi4_lite_driver::type_id::create("drv", this);
            sqr = axi4_lite_sequencer::type_id::create("sqr", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
