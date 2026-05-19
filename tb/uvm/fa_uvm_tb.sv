`timescale 1ns/1ps

module fa_uvm_tb;
    import uvm_pkg::*;
    import fa_uvm_pkg::*;

    logic clk;
    logic rst_n;
    logic irq;

    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
    end

    fa_axil_if        axil_if(.clk(clk), .rst_n(rst_n));
    fa_axi4_master_if axi_if(.clk(clk), .rst_n(rst_n));
    fa_mem_access_if  mem_if(.clk(clk));

    flash_attention_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axil_awaddr(axil_if.awaddr),
        .s_axil_awvalid(axil_if.awvalid),
        .s_axil_awready(axil_if.awready),
        .s_axil_wdata(axil_if.wdata),
        .s_axil_wstrb(axil_if.wstrb),
        .s_axil_wvalid(axil_if.wvalid),
        .s_axil_wready(axil_if.wready),
        .s_axil_bresp(axil_if.bresp),
        .s_axil_bvalid(axil_if.bvalid),
        .s_axil_bready(axil_if.bready),
        .s_axil_araddr(axil_if.araddr),
        .s_axil_arvalid(axil_if.arvalid),
        .s_axil_arready(axil_if.arready),
        .s_axil_rdata(axil_if.rdata),
        .s_axil_rresp(axil_if.rresp),
        .s_axil_rvalid(axil_if.rvalid),
        .s_axil_rready(axil_if.rready),
        .m_axi_awid(axi_if.awid),
        .m_axi_awaddr(axi_if.awaddr),
        .m_axi_awlen(axi_if.awlen),
        .m_axi_awsize(axi_if.awsize),
        .m_axi_awburst(axi_if.awburst),
        .m_axi_awvalid(axi_if.awvalid),
        .m_axi_awready(axi_if.awready),
        .m_axi_wdata(axi_if.wdata),
        .m_axi_wstrb(axi_if.wstrb),
        .m_axi_wlast(axi_if.wlast),
        .m_axi_wvalid(axi_if.wvalid),
        .m_axi_wready(axi_if.wready),
        .m_axi_bid(axi_if.bid),
        .m_axi_bresp(axi_if.bresp),
        .m_axi_bvalid(axi_if.bvalid),
        .m_axi_bready(axi_if.bready),
        .m_axi_arid(axi_if.arid),
        .m_axi_araddr(axi_if.araddr),
        .m_axi_arlen(axi_if.arlen),
        .m_axi_arsize(axi_if.arsize),
        .m_axi_arburst(axi_if.arburst),
        .m_axi_arvalid(axi_if.arvalid),
        .m_axi_arready(axi_if.arready),
        .m_axi_rid(axi_if.rid),
        .m_axi_rdata(axi_if.rdata),
        .m_axi_rresp(axi_if.rresp),
        .m_axi_rlast(axi_if.rlast),
        .m_axi_rvalid(axi_if.rvalid),
        .m_axi_rready(axi_if.rready),
        .irq(irq)
    );

    axi4_slave_mem u_mem (
        .clk(clk),
        .rst_n(rst_n),
        .araddr(axi_if.araddr),
        .arlen(axi_if.arlen),
        .arsize(axi_if.arsize),
        .arvalid(axi_if.arvalid),
        .arready(axi_if.arready),
        .rdata(axi_if.rdata),
        .rresp(axi_if.rresp),
        .rlast(axi_if.rlast),
        .rvalid(axi_if.rvalid),
        .rready(axi_if.rready),
        .awaddr(axi_if.awaddr),
        .awlen(axi_if.awlen),
        .awsize(axi_if.awsize),
        .awvalid(axi_if.awvalid),
        .awready(axi_if.awready),
        .wdata(axi_if.wdata),
        .wstrb(axi_if.wstrb),
        .wlast(axi_if.wlast),
        .wvalid(axi_if.wvalid),
        .wready(axi_if.wready),
        .bresp(axi_if.bresp),
        .bvalid(axi_if.bvalid),
        .bready(axi_if.bready),
        .mem_wr_en(mem_if.mem_wr_en),
        .mem_wr_addr(mem_if.mem_wr_addr),
        .mem_wr_data16(mem_if.mem_wr_data16),
        .mem_rd_en(mem_if.mem_rd_en),
        .mem_rd_addr(mem_if.mem_rd_addr),
        .mem_rd_data16(mem_if.mem_rd_data16)
    );

    assign axi_if.rid = axi_if.arid;
    assign axi_if.bid = axi_if.awid;

    initial begin
        uvm_config_db#(virtual fa_axil_if)::set(null, "*", "axil_vif", axil_if);
        uvm_config_db#(virtual fa_axi4_master_if)::set(null, "*", "axi_vif", axi_if);
        uvm_config_db#(virtual fa_mem_access_if)::set(null, "*", "mem_vif", mem_if);
        run_test();
    end

    initial begin
        #50_000_000;
        `uvm_fatal("TIMEOUT", "fa_uvm_tb timeout")
    end
endmodule
