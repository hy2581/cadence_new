// AXI4-Lite Sequencer
class axi4_lite_sequencer extends uvm_sequencer #(axi4_lite_txn);
    `uvm_component_utils(axi4_lite_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
