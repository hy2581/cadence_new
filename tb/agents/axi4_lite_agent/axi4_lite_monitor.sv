// AXI4-Lite Monitor
class axi4_lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_lite_monitor)

    virtual axi4_lite_if vif;
    uvm_analysis_port #(axi4_lite_txn) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axi4_lite_if not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_writes();
            monitor_reads();
        join
    endtask

    task monitor_writes();
        forever begin
            axi4_lite_txn txn;
            @(posedge vif.clk);
            if (vif.s_axil_awvalid && vif.s_axil_awready &&
                vif.s_axil_wvalid && vif.s_axil_wready) begin
                txn = axi4_lite_txn::type_id::create("wr_txn");
                txn.is_write = 1;
                txn.addr     = vif.s_axil_awaddr;
                txn.data     = vif.s_axil_wdata;
                ap.write(txn);
            end
        end
    endtask

    task monitor_reads();
        forever begin
            axi4_lite_txn txn;
            @(posedge vif.clk);
            if (vif.s_axil_rvalid && vif.s_axil_rready) begin
                txn = axi4_lite_txn::type_id::create("rd_txn");
                txn.is_write = 0;
                txn.rdata    = vif.s_axil_rdata;
                txn.resp     = vif.s_axil_rresp;
                ap.write(txn);
            end
        end
    endtask
endclass
