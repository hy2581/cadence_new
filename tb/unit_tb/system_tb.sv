// ============================================================
// FlashAttention — System End-to-End Testbench (v2)
// Uses module-based AXI4 slave memory model
// ============================================================
`timescale 1ns/1ps
`include "fa_params.svh"

module system_tb;

    logic clk, rst_n;
    real clk_half_ns;
    initial begin
        clk_half_ns = 1.0;
        void'($value$plusargs("FA_CLK_HALF_NS=%f", clk_half_ns));
        clk = 0;
        forever #(clk_half_ns) clk = ~clk;
    end
    initial begin
        rst_n = 0;
        repeat(20) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    end

    string fa_dump_vcd_path;
    integer fa_dump_vcd_depth;
    initial begin
        fa_dump_vcd_depth = 0;
        if ($value$plusargs("FA_DUMP_VCD=%s", fa_dump_vcd_path)) begin
            void'($value$plusargs("FA_DUMP_VCD_DEPTH=%d", fa_dump_vcd_depth));
            $display("FA_DUMP_VCD: dumping system_tb.dut depth %0d to %s",
                fa_dump_vcd_depth, fa_dump_vcd_path);
            $dumpfile(fa_dump_vcd_path);
            if (fa_dump_vcd_depth == 1)
                $dumpvars(1, dut);
            else if (fa_dump_vcd_depth == 2)
                $dumpvars(2, dut);
            else
                $dumpvars(0, dut);
        end
    end

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

    task automatic mem_write16(input [63:0] addr, input [15:0] data);
        @(negedge clk);
        mem_wr_en     = 1'b1;
        mem_wr_addr   = addr;
        mem_wr_data16 = data;
        @(negedge clk);
        mem_wr_en     = 1'b0;
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
    localparam real MEAN_LIMIT = 0.03;
    localparam real MAX_LIMIT = 0.10;
    localparam real CAUSAL_ROW0_LIMIT = 0.02;

    reg [31:0] status_val, cycles_val;
    reg [31:0] rd_bytes_val, wr_bytes_val;
    integer timeout_cnt;
    shortint q_raw, k_raw, v_raw;
    real mean_err, max_err, abs_err, dut_val, gold_val;
    real row0_causal_err, row0_abs_err;
    integer err_count;
    shortint o_val;
    bit test_pass;

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
                mem_write16(Q_BASE + (i*64+j)*2, q_raw);
                mem_write16(K_BASE + (i*64+j)*2, k_raw);
                mem_write16(V_BASE + (i*64+j)*2, v_raw);
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
        axil_read(8'h44, rd_bytes_val);
        axil_read(8'h48, wr_bytes_val);
        $display("  DONE! Cycles: %0d", cycles_val);

        // Step 6: Read O from external memory (full 256 rows via DMA write-back)
        $display("[6] Reading O from memory (full 256x64)...");
        mean_err = 0; max_err = 0; err_count = 0; row0_causal_err = 0;
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
                if (i == 0) begin
                    row0_abs_err = dut_val - v_f[0][j];
                    if (row0_abs_err < 0) row0_abs_err = -row0_abs_err;
                    if (row0_abs_err > row0_causal_err) row0_causal_err = row0_abs_err;
                end
                err_count = err_count + 1;
            end
        end
        mean_err = mean_err / $itor(err_count);

        $display("============================================================");
        $display("  RESULTS");
        $display("  Cycles:         %0d", cycles_val);
        $display("  RD_BYTES:       %0d", rd_bytes_val);
        $display("  WR_BYTES:       %0d", wr_bytes_val);
        $display("  mean_abs_error: %.6f", mean_err);
        $display("  max_abs_error:  %.6f", max_err);
        $display("  row0_causal:    %.6f", row0_causal_err);
        $display("============================================================");
        test_pass = 1'b1;
        if (cycles_val < 300000)
            $display("  Cycles:  PASS (%0d < 300k)", cycles_val);
        else begin
            $display("  Cycles:  FAIL (%0d >= 300k)", cycles_val);
            test_pass = 1'b0;
        end
        if (mean_err <= MEAN_LIMIT)
            $display("  Mean:    PASS (%.6f)", mean_err);
        else begin
            $display("  Mean:    FAIL (%.6f)", mean_err);
            test_pass = 1'b0;
        end
        if (max_err <= MAX_LIMIT)
            $display("  Max:     PASS (%.6f)", max_err);
        else begin
            $display("  Max:     FAIL (%.6f)", max_err);
            test_pass = 1'b0;
        end
        if (row0_causal_err <= CAUSAL_ROW0_LIMIT)
            $display("  Causal:  PASS (row0 max err %.6f)", row0_causal_err);
        else begin
            $display("  Causal:  FAIL (row0 max err %.6f)", row0_causal_err);
            test_pass = 1'b0;
        end
        if (rd_bytes_val == 32'd2260992)
            $display("  RD_BYTES: PASS (%0d)", rd_bytes_val);
        else begin
            $display("  RD_BYTES: FAIL (%0d != 2260992)", rd_bytes_val);
            test_pass = 1'b0;
        end
        if (wr_bytes_val == 32'd32768)
            $display("  WR_BYTES: PASS (%0d)", wr_bytes_val);
        else begin
            $display("  WR_BYTES: FAIL (%0d != 32768)", wr_bytes_val);
            test_pass = 1'b0;
        end
        if (!test_pass)
            $fatal(1, "FlashAttention system test failed");
        $display(">>> ALL TESTS PASSED <<<");
        $finish;
    end

    initial begin #50_000_000; $display("TIMEOUT 50ms"); $finish; end
endmodule
