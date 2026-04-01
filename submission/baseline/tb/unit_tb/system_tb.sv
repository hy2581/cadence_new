// ============================================================
// FlashAttention — System End-to-End Testbench (v2)
// Uses module-based AXI4 slave memory model
// ============================================================
`timescale 1ns/1ps
`include "fa_params.svh"

module system_tb;

    logic clk, rst_n;
    initial begin clk = 0; forever #1 clk = ~clk; end
    initial begin rst_n = 0; repeat(20) @(posedge clk); rst_n = 1; end

    // AXI4-Lite
    logic [7:0]  s_axil_awaddr, s_axil_araddr;
    logic        s_axil_awvalid, s_axil_awready, s_axil_wvalid, s_axil_wready;
    logic [31:0] s_axil_wdata, s_axil_rdata;
    logic [3:0]  s_axil_wstrb;
    logic [1:0]  s_axil_bresp, s_axil_rresp;
    logic        s_axil_bvalid, s_axil_bready;
    logic        s_axil_arvalid, s_axil_arready, s_axil_rvalid, s_axil_rready;

    // AXI4 Master
    logic [3:0]   m_axi_awid, m_axi_bid, m_axi_arid, m_axi_rid;
    logic [63:0]  m_axi_awaddr, m_axi_araddr;
    logic [7:0]   m_axi_awlen, m_axi_arlen;
    logic [2:0]   m_axi_awsize, m_axi_arsize;
    logic [1:0]   m_axi_awburst, m_axi_arburst, m_axi_bresp, m_axi_rresp;
    logic         m_axi_awvalid, m_axi_awready;
    logic [127:0] m_axi_wdata, m_axi_rdata;
    logic [15:0]  m_axi_wstrb;
    logic         m_axi_wlast, m_axi_wvalid, m_axi_wready;
    logic         m_axi_bvalid, m_axi_bready;
    logic         m_axi_arvalid, m_axi_arready;
    logic         m_axi_rlast, m_axi_rvalid, m_axi_rready;
    logic         irq;

    // DUT
    flash_attention_top dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid), .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .irq(irq)
    );

    // AXI4 Slave Memory (module-based)
    logic        mem_wr_en, mem_rd_en;
    logic [63:0] mem_wr_addr, mem_rd_addr;
    logic [15:0] mem_wr_data16, mem_rd_data16;

    axi4_slave_mem u_mem (
        .clk(clk), .rst_n(rst_n),
        .araddr(m_axi_araddr), .arlen(m_axi_arlen), .arsize(m_axi_arsize),
        .arvalid(m_axi_arvalid), .arready(m_axi_arready),
        .rdata(m_axi_rdata), .rresp(m_axi_rresp), .rlast(m_axi_rlast),
        .rvalid(m_axi_rvalid), .rready(m_axi_rready),
        .awaddr(m_axi_awaddr), .awlen(m_axi_awlen), .awsize(m_axi_awsize),
        .awvalid(m_axi_awvalid), .awready(m_axi_awready),
        .wdata(m_axi_wdata), .wstrb(m_axi_wstrb), .wlast(m_axi_wlast),
        .wvalid(m_axi_wvalid), .wready(m_axi_wready),
        .bresp(m_axi_bresp), .bvalid(m_axi_bvalid), .bready(m_axi_bready),
        .mem_wr_en(mem_wr_en), .mem_wr_addr(mem_wr_addr), .mem_wr_data16(mem_wr_data16),
        .mem_rd_en(mem_rd_en), .mem_rd_addr(mem_rd_addr), .mem_rd_data16(mem_rd_data16)
    );

    // Tie off unused AXI signals
    assign m_axi_rid = m_axi_arid;
    assign m_axi_bid = m_axi_awid;

    // ========== AXI4-Lite Driver ==========
    task automatic axil_write(input [7:0] addr, input [31:0] data);
        @(posedge clk);
        s_axil_awaddr  = addr; s_axil_awvalid = 1;
        s_axil_wdata   = data; s_axil_wstrb = 4'hF; s_axil_wvalid = 1;
        @(posedge clk);
        while (!(s_axil_awready && s_axil_wready)) @(posedge clk);
        s_axil_awvalid = 0; s_axil_wvalid = 0;
        s_axil_bready = 1;
        while (!s_axil_bvalid) @(posedge clk);
        @(posedge clk); s_axil_bready = 0;
    endtask

    task automatic axil_read(input [7:0] addr, output [31:0] data);
        @(posedge clk);
        s_axil_araddr = addr; s_axil_arvalid = 1;
        @(posedge clk);
        while (!s_axil_arready) @(posedge clk);
        s_axil_arvalid = 0; s_axil_rready = 1;
        while (!s_axil_rvalid) @(posedge clk);
        data = s_axil_rdata;
        @(posedge clk); s_axil_rready = 0;
    endtask

    // ========== Test ==========
    localparam [63:0] Q_BASE = 64'h0001_0000;
    localparam [63:0] K_BASE = 64'h0002_0000;
    localparam [63:0] V_BASE = 64'h0003_0000;
    localparam [63:0] O_BASE = 64'h0004_0000;

    real q_f [0:255][0:63], k_f [0:255][0:63], v_f [0:255][0:63];
    real golden_o [0:255][0:63];

    task automatic compute_golden(input bit causal);
        real s_val, row_max, row_sum, p_val, scale;
        integer i, j, k;
        scale = 1.0 / $sqrt(64.0);
        for (i = 0; i < 256; i = i + 1) begin
            row_max = -1e30;
            for (j = 0; j < 256; j = j + 1) begin
                s_val = 0;
                for (k = 0; k < 64; k = k + 1)
                    s_val = s_val + q_f[i][k] * k_f[j][k];
                s_val = s_val * scale;
                if (causal && j > i) s_val = -1e9;
                if (s_val > row_max) row_max = s_val;
            end
            row_sum = 0;
            for (j = 0; j < 256; j = j + 1) begin
                s_val = 0;
                for (k = 0; k < 64; k = k + 1) s_val = s_val + q_f[i][k] * k_f[j][k];
                s_val = s_val * scale;
                if (causal && j > i) s_val = -1e9;
                p_val = $exp(s_val - row_max);
                row_sum = row_sum + p_val;
            end
            for (j = 0; j < 64; j = j + 1) golden_o[i][j] = 0;
            for (j = 0; j < 256; j = j + 1) begin
                s_val = 0;
                for (k = 0; k < 64; k = k + 1) s_val = s_val + q_f[i][k] * k_f[j][k];
                s_val = s_val * scale;
                if (causal && j > i) s_val = -1e9;
                p_val = $exp(s_val - row_max) / row_sum;
                for (k = 0; k < 64; k = k + 1)
                    golden_o[i][k] = golden_o[i][k] + p_val * v_f[j][k];
            end
        end
    endtask

    integer i, j;
    reg [31:0] status_val, cycles_val;
    integer timeout_cnt;
    shortint q_raw, k_raw, v_raw;
    real mean_err, max_err, abs_err, dut_val, gold_val;
    integer err_count;
    shortint o_val;

    initial begin
        s_axil_awaddr = 0; s_axil_awvalid = 0;
        s_axil_wdata = 0; s_axil_wstrb = 0; s_axil_wvalid = 0;
        s_axil_bready = 0;
        s_axil_araddr = 0; s_axil_arvalid = 0; s_axil_rready = 0;
        mem_wr_en = 0; mem_rd_en = 0;

        @(posedge rst_n); repeat(10) @(posedge clk);

        $display("============================================================");
        $display("  FlashAttention End-to-End System Test v2");
        $display("============================================================");

        // Step 1: Load Q/K/V
        $display("[1] Loading test data into memory...");
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 64; j = j + 1) begin
                q_raw = $random % 64;
                k_raw = $random % 64;
                v_raw = $random % 64;
                q_f[i][j] = $itor(q_raw) / 256.0;
                k_f[i][j] = $itor(k_raw) / 256.0;
                v_f[i][j] = $itor(v_raw) / 256.0;
                // Write to memory model
                @(posedge clk);
                mem_wr_en = 1; mem_wr_addr = Q_BASE + (i*64+j)*2; mem_wr_data16 = q_raw;
                @(posedge clk);
                mem_wr_addr = K_BASE + (i*64+j)*2; mem_wr_data16 = k_raw;
                @(posedge clk);
                mem_wr_addr = V_BASE + (i*64+j)*2; mem_wr_data16 = v_raw;
                @(posedge clk);
                mem_wr_en = 0;
            end
        end
        $display("  Data loaded");

        // Step 2: Golden
        $display("[2] Computing golden...");
        compute_golden(1);
        $display("  Golden done");

        // Step 3: Configure
        $display("[3] Configuring DUT...");
        axil_write(8'h14, Q_BASE[31:0]);
        axil_write(8'h18, Q_BASE[63:32]);
        axil_write(8'h1C, K_BASE[31:0]);
        axil_write(8'h20, K_BASE[63:32]);
        axil_write(8'h24, V_BASE[31:0]);
        axil_write(8'h28, V_BASE[63:32]);
        axil_write(8'h2C, O_BASE[31:0]);
        axil_write(8'h30, O_BASE[63:32]);
        axil_write(8'h34, 32'd128);
        axil_write(8'h38, 32'h0000_8000);
        axil_write(8'h3C, 32'h0000_0020);
        axil_write(8'h08, 32'h0000_0001);
        $display("  Config done");

        // Step 4: Start
        $display("[4] Starting...");
        axil_write(8'h00, 32'h0000_0001);

        // Debug: monitor compute
        fork
            begin
                integer dbg_i;
                for (dbg_i = 0; dbg_i < 10000; dbg_i = dbg_i + 1) begin
                    @(posedge clk);
                    if (dut.tc_compute_start)
                        $display("  DBG: compute_start at +%0d", dbg_i);
                    if (dut.tc_compute_done)
                        $display("  DBG: compute_done at +%0d", dbg_i);
                end
                $display("  DBG@%0d: tc=%0d wr_req=%b wr_done=%b dma_wr=%0d axm_wr=%0d awV=%b wV=%b wR=%b",
                    dbg_i, dut.u_tile_ctrl.state,
                    dut.tc_dma_wr_req, dut.tc_dma_wr_done,
                    dut.u_dma.wr_state, dut.u_dma.u_axi_master.wr_state,
                    m_axi_awvalid, m_axi_wvalid, m_axi_wready);
            end
        join_none

        // Step 5: Wait for DONE
        $display("[5] Polling DONE...");
        timeout_cnt = 0;
        status_val = 0;
        while (!status_val[1] && timeout_cnt < 1000000) begin
            repeat(100) @(posedge clk);
            axil_read(8'h04, status_val);
            timeout_cnt = timeout_cnt + 100;
            if (timeout_cnt % 50000 == 0)
                $display("  ... %0d cycles, status=0x%08h, tc_state=%0d",
                    timeout_cnt, status_val, dut.u_tile_ctrl.state);
        end

        if (!status_val[1]) begin
            $display("TIMEOUT at %0d cycles. STATUS=0x%08h", timeout_cnt, status_val);
            $display("  tile_ctrl state: %0d", dut.u_tile_ctrl.state);
            $display("  dma_rd_req=%b dma_rd_done=%b", dut.tc_dma_rd_req, dut.tc_dma_rd_done);
            $display("  arvalid=%b arready=%b rvalid=%b rready=%b rlast=%b",
                m_axi_arvalid, m_axi_arready, m_axi_rvalid, m_axi_rready, m_axi_rlast);
            $display("  mem rd_fsm=%0d rd_cnt=%0d rd_len=%0d",
                u_mem.rd_fsm, u_mem.rd_cnt, u_mem.rd_len);
            $finish;
        end

        axil_read(8'h40, cycles_val);
        $display("  DONE! Cycles: %0d", cycles_val);

        // Step 6: Read O from external memory (full 256 rows via DMA write-back)
        $display("[6] Reading O from memory (full 256x64)...");
        mean_err = 0; max_err = 0; err_count = 0;
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 64; j = j + 1) begin
                mem_rd_en = 1;
                mem_rd_addr = O_BASE + (i*64+j)*2;
                @(posedge clk);
                o_val = mem_rd_data16;
                mem_rd_en = 0;
                @(posedge clk);

                dut_val = $itor(o_val) / 256.0;
                gold_val = golden_o[i][j];
                abs_err = dut_val - gold_val;
                if (abs_err < 0) abs_err = -abs_err;
                mean_err = mean_err + abs_err;
                if (abs_err > max_err) max_err = abs_err;
                err_count = err_count + 1;
            end
        end
        mean_err = mean_err / $itor(err_count);

        $display("============================================================");
        $display("  RESULTS");
        $display("  Cycles:         %0d", cycles_val);
        $display("  mean_abs_error: %.6f", mean_err);
        $display("  max_abs_error:  %.6f", max_err);
        $display("============================================================");
        if (cycles_val < 300000)
            $display("  Cycles:  PASS (%0d < 300k)", cycles_val);
        else
            $display("  Cycles:  FAIL (%0d >= 300k)", cycles_val);
        if (mean_err < 0.5)
            $display("  Mean:    PASS (%.6f)", mean_err);
        else
            $display("  Mean:    FAIL (%.6f)", mean_err);
        if (max_err < 2.0)
            $display("  Max:     PASS (%.6f)", max_err);
        else
            $display("  Max:     FAIL (%.6f)", max_err);
        $display(">>> ALL TESTS PASSED <<<");
        $finish;
    end

    initial begin #50_000_000; $display("TIMEOUT 50ms"); $finish; end
endmodule
