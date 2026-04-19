// AXI4-Lite Master Driver
class axi4_lite_driver extends uvm_driver #(axi4_lite_txn);
    `uvm_component_utils(axi4_lite_driver)

    virtual axi4_lite_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axi4_lite_if not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        axi4_lite_txn txn;
        wait(vif.rst_n === 1'b1);
        @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(txn);
            drive_txn(txn);
            seq_item_port.item_done();
        end
    endtask

    task drive_txn(axi4_lite_txn txn);
        if (txn.is_write)
            drive_write(txn);
        else
            drive_read(txn);
    endtask

    task drive_write(axi4_lite_txn txn);
        // Write address + data simultaneously
        @(posedge vif.clk);
        vif.s_axil_awaddr  <= txn.addr;
        vif.s_axil_awvalid <= 1'b1;
        vif.s_axil_wdata   <= txn.data;
        vif.s_axil_wstrb   <= 4'hF;
        vif.s_axil_wvalid  <= 1'b1;

        // Wait for both ready
        fork
            begin
                wait(vif.s_axil_awready);
                @(posedge vif.clk);
                vif.s_axil_awvalid <= 1'b0;
            end
            begin
                wait(vif.s_axil_wready);
                @(posedge vif.clk);
                vif.s_axil_wvalid <= 1'b0;
            end
        join

        // Wait for write response
        vif.s_axil_bready <= 1'b1;
        wait(vif.s_axil_bvalid);
        txn.resp = vif.s_axil_bresp;
        @(posedge vif.clk);
        vif.s_axil_bready <= 1'b0;
    endtask

    task drive_read(axi4_lite_txn txn);
        @(posedge vif.clk);
        vif.s_axil_araddr  <= txn.addr;
        vif.s_axil_arvalid <= 1'b1;

        wait(vif.s_axil_arready);
        @(posedge vif.clk);
        vif.s_axil_arvalid <= 1'b0;

        vif.s_axil_rready <= 1'b1;
        wait(vif.s_axil_rvalid);
        txn.rdata = vif.s_axil_rdata;
        txn.resp  = vif.s_axil_rresp;
        @(posedge vif.clk);
        vif.s_axil_rready <= 1'b0;
    endtask
endclass
