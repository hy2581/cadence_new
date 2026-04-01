// ============================================================
// FlashAttention Bonus — UVM Testbench Top
// ============================================================
`timescale 1ns/1ps
`include "fa_params_bonus.svh"

module fa_bonus_tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import fa_bonus_env_pkg::*;

    logic clk, rst_n;

    initial begin
        clk = 0;
        forever #1 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
    end

    // Interfaces (reuse baseline interfaces)
    axi4_lite_if axil_if (.clk(clk), .rst_n(rst_n));
    axi4_mem_if  mem_if  (.clk(clk), .rst_n(rst_n));

    // AXI4-Stream signals (directly wired)
    logic [127:0] s_axis_tdata;
    logic         s_axis_tvalid, s_axis_tready, s_axis_tlast;
    logic [1:0]   s_axis_tid;
    logic [127:0] m_axis_tdata;
    logic         m_axis_tvalid, m_axis_tready, m_axis_tlast;

    // Bonus DUT
    flash_attention_bonus_top u_dut (
        .clk(clk), .rst_n(rst_n),

        // AXI4-Lite
        .s_axil_awaddr  (axil_if.s_axil_awaddr),
        .s_axil_awvalid (axil_if.s_axil_awvalid),
        .s_axil_awready (axil_if.s_axil_awready),
        .s_axil_wdata   (axil_if.s_axil_wdata),
        .s_axil_wstrb   (axil_if.s_axil_wstrb),
        .s_axil_wvalid  (axil_if.s_axil_wvalid),
        .s_axil_wready  (axil_if.s_axil_wready),
        .s_axil_bresp   (axil_if.s_axil_bresp),
        .s_axil_bvalid  (axil_if.s_axil_bvalid),
        .s_axil_bready  (axil_if.s_axil_bready),
        .s_axil_araddr  (axil_if.s_axil_araddr),
        .s_axil_arvalid (axil_if.s_axil_arvalid),
        .s_axil_arready (axil_if.s_axil_arready),
        .s_axil_rdata   (axil_if.s_axil_rdata),
        .s_axil_rresp   (axil_if.s_axil_rresp),
        .s_axil_rvalid  (axil_if.s_axil_rvalid),
        .s_axil_rready  (axil_if.s_axil_rready),

        // AXI4 Master
        .m_axi_awid     (mem_if.m_axi_awid),
        .m_axi_awaddr   (mem_if.m_axi_awaddr),
        .m_axi_awlen    (mem_if.m_axi_awlen),
        .m_axi_awsize   (mem_if.m_axi_awsize),
        .m_axi_awburst  (mem_if.m_axi_awburst),
        .m_axi_awvalid  (mem_if.m_axi_awvalid),
        .m_axi_awready  (mem_if.m_axi_awready),
        .m_axi_wdata    (mem_if.m_axi_wdata),
        .m_axi_wstrb    (mem_if.m_axi_wstrb),
        .m_axi_wlast    (mem_if.m_axi_wlast),
        .m_axi_wvalid   (mem_if.m_axi_wvalid),
        .m_axi_wready   (mem_if.m_axi_wready),
        .m_axi_bid      (mem_if.m_axi_bid),
        .m_axi_bresp    (mem_if.m_axi_bresp),
        .m_axi_bvalid   (mem_if.m_axi_bvalid),
        .m_axi_bready   (mem_if.m_axi_bready),
        .m_axi_arid     (mem_if.m_axi_arid),
        .m_axi_araddr   (mem_if.m_axi_araddr),
        .m_axi_arlen    (mem_if.m_axi_arlen),
        .m_axi_arsize   (mem_if.m_axi_arsize),
        .m_axi_arburst  (mem_if.m_axi_arburst),
        .m_axi_arvalid  (mem_if.m_axi_arvalid),
        .m_axi_arready  (mem_if.m_axi_arready),
        .m_axi_rid      (mem_if.m_axi_rid),
        .m_axi_rdata    (mem_if.m_axi_rdata),
        .m_axi_rresp    (mem_if.m_axi_rresp),
        .m_axi_rlast    (mem_if.m_axi_rlast),
        .m_axi_rvalid   (mem_if.m_axi_rvalid),
        .m_axi_rready   (mem_if.m_axi_rready),

        // AXI4-Stream (tied off for non-stream tests)
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .s_axis_tid     (s_axis_tid),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),

        .irq()
    );

    // Default stream signals
    initial begin
        s_axis_tdata  = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tid    = '0;
        m_axis_tready = 1'b1;
    end

    // AXI4-Lite default init
    initial begin
        axil_if.s_axil_awaddr  = '0;
        axil_if.s_axil_awvalid = 1'b0;
        axil_if.s_axil_wdata   = '0;
        axil_if.s_axil_wstrb   = '0;
        axil_if.s_axil_wvalid  = 1'b0;
        axil_if.s_axil_bready  = 1'b0;
        axil_if.s_axil_araddr  = '0;
        axil_if.s_axil_arvalid = 1'b0;
        axil_if.s_axil_rready  = 1'b0;
    end

    // Register interfaces in config_db
    initial begin
        uvm_config_db#(virtual axi4_lite_if)::set(null, "*axil_agent*", "vif", axil_if);
        uvm_config_db#(virtual axi4_mem_if)::set(null, "*mem_agent*", "vif", mem_if);
    end

    // Run UVM test
    initial begin
        run_test();
    end

    // Timeout
    initial begin
        #50_000_000;
        `uvm_fatal("TIMEOUT", "Simulation timeout!")
    end

    // Waveform dump
    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("bonus_wave.vcd");
            $dumpvars(0, fa_bonus_tb_top);
        end
    end

endmodule
