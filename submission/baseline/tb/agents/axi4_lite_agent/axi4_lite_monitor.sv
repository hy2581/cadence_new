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
        bit [7:0]  aw_addr;
        bit [31:0] w_data;
        bit aw_seen, w_seen;
        forever begin
            @(posedge vif.clk);
            if (vif.s_axil_awvalid && vif.s_axil_awready) begin
                aw_addr = vif.s_axil_awaddr;
                aw_seen = 1;
            end
            if (vif.s_axil_wvalid && vif.s_axil_wready) begin
                w_data = vif.s_axil_wdata;
                w_seen = 1;
            end
            if (aw_seen && w_seen) begin
                axi4_lite_txn txn = axi4_lite_txn::type_id::create("wr_txn");
                txn.is_write = 1;
                txn.addr     = aw_addr;
                txn.data     = w_data;
                ap.write(txn);
                aw_seen = 0;
                w_seen  = 0;
            end
        end
    endtask

    task monitor_reads();
        bit [7:0] pending_addr;
        forever begin
            axi4_lite_txn txn;
            @(posedge vif.clk);
            if (vif.s_axil_arvalid && vif.s_axil_arready)
                pending_addr = vif.s_axil_araddr;
            if (vif.s_axil_rvalid && vif.s_axil_rready) begin
                txn = axi4_lite_txn::type_id::create("rd_txn");
                txn.is_write = 0;
                txn.addr     = pending_addr;
                txn.rdata    = vif.s_axil_rdata;
                txn.resp     = vif.s_axil_rresp;
                ap.write(txn);
            end
        end
    endtask
endclass
