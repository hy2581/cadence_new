// ============================================================
// FlashAttention — UVM Testbench Top
// AXI protocol checkers always enabled
// ============================================================
`timescale 1ns/1ps

`include "fa_params.svh"

module fa_tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import fa_env_pkg::*;

    // Clock and reset
    logic clk, rst_n;

    initial begin
        clk = 0;
        forever #1 clk = ~clk;  // 500 MHz
    end

    initial begin
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
    end

    // Interfaces
    axi4_lite_if axil_if (.clk(clk), .rst_n(rst_n));
    axi4_mem_if  mem_if  (.clk(clk), .rst_n(rst_n));

    // DUT instantiation
    flash_attention_top u_dut (
        .clk(clk),
        .rst_n(rst_n),

        // AXI4-Lite Slave
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

        .irq()
    );

    // ========== Protocol Checkers ==========
`ifdef ENABLE_PROTOCOL_CHECK
    axi4_lite_protocol_checker #(
        .ADDR_WIDTH(8), .DATA_WIDTH(32)
    ) u_axil_checker (
        .clk(clk), .rst_n(rst_n),
        .awaddr  (axil_if.s_axil_awaddr),
        .awvalid (axil_if.s_axil_awvalid),
        .awready (axil_if.s_axil_awready),
        .wdata   (axil_if.s_axil_wdata),
        .wstrb   (axil_if.s_axil_wstrb),
        .wvalid  (axil_if.s_axil_wvalid),
        .wready  (axil_if.s_axil_wready),
        .bresp   (axil_if.s_axil_bresp),
        .bvalid  (axil_if.s_axil_bvalid),
        .bready  (axil_if.s_axil_bready),
        .araddr  (axil_if.s_axil_araddr),
        .arvalid (axil_if.s_axil_arvalid),
        .arready (axil_if.s_axil_arready),
        .rdata   (axil_if.s_axil_rdata),
        .rresp   (axil_if.s_axil_rresp),
        .rvalid  (axil_if.s_axil_rvalid),
        .rready  (axil_if.s_axil_rready)
    );

    axi4_protocol_checker #(
        .ADDR_WIDTH(64), .DATA_WIDTH(128), .ID_WIDTH(4)
    ) u_axi_checker (
        .clk(clk), .rst_n(rst_n),
        .awid    (mem_if.m_axi_awid),
        .awaddr  (mem_if.m_axi_awaddr),
        .awlen   (mem_if.m_axi_awlen),
        .awsize  (mem_if.m_axi_awsize),
        .awburst (mem_if.m_axi_awburst),
        .awvalid (mem_if.m_axi_awvalid),
        .awready (mem_if.m_axi_awready),
        .wdata   (mem_if.m_axi_wdata),
        .wstrb   (mem_if.m_axi_wstrb),
        .wlast   (mem_if.m_axi_wlast),
        .wvalid  (mem_if.m_axi_wvalid),
        .wready  (mem_if.m_axi_wready),
        .bid     (mem_if.m_axi_bid),
        .bresp   (mem_if.m_axi_bresp),
        .bvalid  (mem_if.m_axi_bvalid),
        .bready  (mem_if.m_axi_bready),
        .arid    (mem_if.m_axi_arid),
        .araddr  (mem_if.m_axi_araddr),
        .arlen   (mem_if.m_axi_arlen),
        .arsize  (mem_if.m_axi_arsize),
        .arburst (mem_if.m_axi_arburst),
        .arvalid (mem_if.m_axi_arvalid),
        .arready (mem_if.m_axi_arready),
        .rid     (mem_if.m_axi_rid),
        .rdata   (mem_if.m_axi_rdata),
        .rresp   (mem_if.m_axi_rresp),
        .rlast   (mem_if.m_axi_rlast),
        .rvalid  (mem_if.m_axi_rvalid),
        .rready  (mem_if.m_axi_rready)
    );
`endif

    // ========== Config DB ==========
    initial begin
        uvm_config_db#(virtual axi4_lite_if)::set(null, "*axil_agent*", "vif", axil_if);
        uvm_config_db#(virtual axi4_mem_if)::set(null, "*mem_agent*", "vif", mem_if);
    end

    // Initialize AXI4-Lite signals
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

    // Run UVM test
    initial begin
        run_test();
    end

    // Simulation timeout
    initial begin
        #20_000_000;
        `uvm_fatal("TIMEOUT", "Simulation timeout!")
    end


    // Dump waveforms
    // 1) VCD (兼容 VCS / 其他仿真器)   —— +DUMP_VCD
    // 2) SHM (Xcelium 原生)            —— +DUMP_SHM [+SHM_PATH=<path>]
    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("wave.vcd");
            $dumpvars(0, fa_tb_top);
        end
        if ($test$plusargs("DUMP_SHM")) begin
            string shm_path;
            if (!$value$plusargs("SHM_PATH=%s", shm_path))
                shm_path = "waves.shm";
            $shm_open(shm_path);
            $shm_probe(fa_tb_top, "AS");
            $display("[fa_tb_top] SHM dump enabled -> %s (probe: fa_tb_top / AS)", shm_path);
        end
    end

endmodule
