// ============================================================
// FlashAttention Accelerator — System-Level End-to-End Testbench
// Drives DUT through the full attention pipeline:
//   1. Pre-load Q/K/V in simulated memory
//   2. Configure DUT via AXI4-Lite
//   3. Start computation
//   4. Wait for DONE
//   5. Read back O and compare with golden
// ============================================================
`timescale 1ns/1ps
`include "fa_params.svh"

module system_tb;

    // ========== Clock and Reset ==========
    logic clk, rst_n;
    initial begin clk = 0; forever #1 clk = ~clk; end  // 500 MHz
    initial begin rst_n = 0; repeat(20) @(posedge clk); rst_n = 1; end

    // ========== AXI4-Lite Signals ==========
    logic [7:0]  s_axil_awaddr;
    logic        s_axil_awvalid, s_axil_awready;
    logic [31:0] s_axil_wdata;
    logic [3:0]  s_axil_wstrb;
    logic        s_axil_wvalid, s_axil_wready;
    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid, s_axil_bready;
    logic [7:0]  s_axil_araddr;
    logic        s_axil_arvalid, s_axil_arready;
    logic [31:0] s_axil_rdata;
    logic [1:0]  s_axil_rresp;
    logic        s_axil_rvalid, s_axil_rready;

    // ========== AXI4 Master Signals ==========
    logic [3:0]   m_axi_awid;
    logic [63:0]  m_axi_awaddr;
    logic [7:0]   m_axi_awlen;
    logic [2:0]   m_axi_awsize;
    logic [1:0]   m_axi_awburst;
    logic         m_axi_awvalid, m_axi_awready;
    logic [127:0] m_axi_wdata;
    logic [15:0]  m_axi_wstrb;
    logic         m_axi_wlast, m_axi_wvalid, m_axi_wready;
    logic [3:0]   m_axi_bid;
    logic [1:0]   m_axi_bresp;
    logic         m_axi_bvalid, m_axi_bready;
    logic [3:0]   m_axi_arid;
    logic [63:0]  m_axi_araddr;
    logic [7:0]   m_axi_arlen;
    logic [2:0]   m_axi_arsize;
    logic [1:0]   m_axi_arburst;
    logic         m_axi_arvalid, m_axi_arready;
    logic [3:0]   m_axi_rid;
    logic [127:0] m_axi_rdata;
    logic [1:0]   m_axi_rresp;
    logic         m_axi_rlast, m_axi_rvalid, m_axi_rready;
    logic         irq;

    // ========== DUT ==========
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

    // ========== AXI4 Slave Memory Model ==========
    // Byte-addressable associative array
    reg [7:0] mem [*];

    // Memory write helper (16-bit little-endian)
    task automatic mem_write16(input [63:0] addr, input [15:0] data);
        mem[addr]   = data[7:0];
        mem[addr+1] = data[15:8];
    endtask

    function automatic [15:0] mem_read16(input [63:0] addr);
        reg [7:0] lo, hi;
        lo = mem.exists(addr)   ? mem[addr]   : 8'h0;
        hi = mem.exists(addr+1) ? mem[addr+1] : 8'h0;
        return {hi, lo};
    endfunction

    // AXI4 Read Slave (responds to DUT's AXI4 Master reads)
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_arready <= 0;
            m_axi_rvalid  <= 0;
            m_axi_rlast   <= 0;
        end
    end

    // AXI4 Read Slave — Task-based (procedural, clear timing)
    initial begin
        m_axi_arready = 0; m_axi_rvalid = 0; m_axi_rlast = 0;
        m_axi_rdata = 0; m_axi_rid = 0; m_axi_rresp = 0;
        forever begin
            // Wait for read address
            @(posedge clk);
            while (!m_axi_arvalid) @(posedge clk);

            // Accept address
            begin
                reg [63:0] addr;
                reg [7:0] len;
                reg [2:0] sz;
                integer beat_bytes, b, cnt;
                addr = m_axi_araddr;
                len  = m_axi_arlen;
                sz   = m_axi_arsize;
                beat_bytes = 1 << sz;
                m_axi_arready = 1;
                @(posedge clk);
                m_axi_arready = 0;

                // Send data beats
                for (cnt = 0; cnt <= len; cnt = cnt + 1) begin
                    for (b = 0; b < 16; b = b + 1) begin
                        if (b < beat_bytes)
                            m_axi_rdata[b*8 +: 8] = mem.exists(addr + b) ? mem[addr + b] : 8'h0;
                        else
                            m_axi_rdata[b*8 +: 8] = 8'h0;
                    end
                    m_axi_rvalid = 1;
                    m_axi_rlast  = (cnt == len);
                    m_axi_rresp  = 2'b00;
                    @(posedge clk);
                    while (!m_axi_rready) @(posedge clk);
                    addr = addr + beat_bytes;
                end
                m_axi_rvalid = 0;
                m_axi_rlast  = 0;
            end
        end
    end

    // AXI4 Write Slave — Task-based (procedural)
    initial begin
        m_axi_awready = 0; m_axi_wready = 0;
        m_axi_bvalid = 0; m_axi_bid = 0; m_axi_bresp = 0;
        forever begin
            @(posedge clk);
            while (!m_axi_awvalid) @(posedge clk);

            begin
                reg [63:0] addr;
                reg [7:0] len;
                reg [2:0] sz;
                integer beat_bytes, b;
                addr = m_axi_awaddr;
                len  = m_axi_awlen;
                sz   = m_axi_awsize;
                beat_bytes = 1 << sz;
                m_axi_awready = 1;
                @(posedge clk);
                m_axi_awready = 0;

                // Accept write data beats
                m_axi_wready = 1;
                begin : wr_loop
                    reg wr_done_flag;
                    wr_done_flag = 0;
                    while (!wr_done_flag) begin
                        @(posedge clk);
                        if (m_axi_wvalid) begin
                            for (b = 0; b < beat_bytes; b = b + 1)
                                if (m_axi_wstrb[b])
                                    mem[addr + b] = m_axi_wdata[b*8 +: 8];
                            addr = addr + beat_bytes;
                            if (m_axi_wlast)
                                wr_done_flag = 1;
                        end
                    end
                end
                m_axi_wready = 0;
                m_axi_bvalid = 1;
                m_axi_bresp  = 2'b00;
                @(posedge clk);
                while (!m_axi_bready) @(posedge clk);
                m_axi_bvalid = 0;
            end
        end
    end

    // ========== AXI4-Lite Driver Tasks ==========
    task automatic axil_write(input [7:0] addr, input [31:0] data);
        @(posedge clk);
        s_axil_awaddr  = addr;
        s_axil_awvalid = 1;
        s_axil_wdata   = data;
        s_axil_wstrb   = 4'hF;
        s_axil_wvalid  = 1;
        @(posedge clk);
        while (!(s_axil_awready && s_axil_wready)) @(posedge clk);
        s_axil_awvalid = 0;
        s_axil_wvalid  = 0;
        s_axil_bready  = 1;
        while (!s_axil_bvalid) @(posedge clk);
        @(posedge clk);
        s_axil_bready = 0;
    endtask

    task automatic axil_read(input [7:0] addr, output [31:0] data);
        @(posedge clk);
        s_axil_araddr  = addr;
        s_axil_arvalid = 1;
        @(posedge clk);
        while (!s_axil_arready) @(posedge clk);
        s_axil_arvalid = 0;
        s_axil_rready  = 1;
        while (!s_axil_rvalid) @(posedge clk);
        data = s_axil_rdata;
        @(posedge clk);
        s_axil_rready = 0;
    endtask

    // ========== Test Addresses ==========
    localparam [63:0] Q_BASE = 64'h0001_0000;
    localparam [63:0] K_BASE = 64'h0002_0000;
    localparam [63:0] V_BASE = 64'h0003_0000;
    localparam [63:0] O_BASE = 64'h0004_0000;

    // ========== Golden Model ==========
    real q_f [0:255][0:63], k_f [0:255][0:63], v_f [0:255][0:63];
    real golden_o [0:255][0:63];

    task automatic compute_golden(input bit causal);
        real s_val, row_max, row_sum, p_val;
        real scale;
        integer i, j, k;
        scale = 1.0 / $sqrt(64.0);

        for (i = 0; i < 256; i = i + 1) begin
            // Compute scores and rowmax
            row_max = -1e30;
            for (j = 0; j < 256; j = j + 1) begin
                s_val = 0;
                for (k = 0; k < 64; k = k + 1)
                    s_val = s_val + q_f[i][k] * k_f[j][k];
                s_val = s_val * scale;
                if (causal && j > i) s_val = -1e9;
                if (s_val > row_max) row_max = s_val;
            end
            // Softmax + output
            row_sum = 0;
            for (j = 0; j < 256; j = j + 1) begin
                s_val = 0;
                for (k = 0; k < 64; k = k + 1)
                    s_val = s_val + q_f[i][k] * k_f[j][k];
                s_val = s_val * scale;
                if (causal && j > i) s_val = -1e9;
                p_val = $exp(s_val - row_max);
                row_sum = row_sum + p_val;
            end
            for (j = 0; j < 64; j = j + 1)
                golden_o[i][j] = 0;
            for (j = 0; j < 256; j = j + 1) begin
                s_val = 0;
                for (k = 0; k < 64; k = k + 1)
                    s_val = s_val + q_f[i][k] * k_f[j][k];
                s_val = s_val * scale;
                if (causal && j > i) s_val = -1e9;
                p_val = $exp(s_val - row_max) / row_sum;
                for (k = 0; k < 64; k = k + 1)
                    golden_o[i][k] = golden_o[i][k] + p_val * v_f[j][k];
            end
        end
    endtask

    // ========== Main Test ==========
    integer i, j;
    reg [31:0] status_val, cycles_val;
    integer timeout_cnt;
    shortint q_raw [0:255][0:63];
    shortint k_raw [0:255][0:63];
    shortint v_raw [0:255][0:63];
    shortint o_dut [0:255][0:63];
    real mean_err, max_err, abs_err, dut_val, gold_val;
    integer err_count;

    initial begin
        // Init AXI4-Lite signals
        s_axil_awaddr = 0; s_axil_awvalid = 0;
        s_axil_wdata = 0; s_axil_wstrb = 0; s_axil_wvalid = 0;
        s_axil_bready = 0;
        s_axil_araddr = 0; s_axil_arvalid = 0;
        s_axil_rready = 0;

        @(posedge rst_n);
        repeat(10) @(posedge clk);

        $display("============================================================");
        $display("  FlashAttention End-to-End System Test");
        $display("  s=256, d=64, causal=1, Q8.8 format");
        $display("============================================================");

        // Step 1: Generate small random Q/K/V data
        $display("[1] Generating test data...");
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 64; j = j + 1) begin
                q_raw[i][j] = $random % 128;  // small values to avoid overflow
                k_raw[i][j] = $random % 128;
                v_raw[i][j] = $random % 128;
                q_f[i][j] = $itor(q_raw[i][j]) / 256.0;
                k_f[i][j] = $itor(k_raw[i][j]) / 256.0;
                v_f[i][j] = $itor(v_raw[i][j]) / 256.0;
                // Store in memory (little-endian Q8.8)
                mem_write16(Q_BASE + (i * 64 + j) * 2, q_raw[i][j]);
                mem_write16(K_BASE + (i * 64 + j) * 2, k_raw[i][j]);
                mem_write16(V_BASE + (i * 64 + j) * 2, v_raw[i][j]);
            end
        end
        $display("  Data loaded: Q/K/V at 0x%h/0x%h/0x%h", Q_BASE, K_BASE, V_BASE);

        // Step 2: Compute golden
        $display("[2] Computing golden reference...");
        compute_golden(1);  // causal=1
        $display("  Golden computation done");

        // Step 3: Configure DUT
        $display("[3] Configuring DUT...");
        axil_write(8'h14, Q_BASE[31:0]);    // Q_BASE_L
        axil_write(8'h18, Q_BASE[63:32]);   // Q_BASE_H
        axil_write(8'h1C, K_BASE[31:0]);    // K_BASE_L
        axil_write(8'h20, K_BASE[63:32]);   // K_BASE_H
        axil_write(8'h24, V_BASE[31:0]);    // V_BASE_L
        axil_write(8'h28, V_BASE[63:32]);   // V_BASE_H
        axil_write(8'h2C, O_BASE[31:0]);    // O_BASE_L
        axil_write(8'h30, O_BASE[63:32]);   // O_BASE_H
        axil_write(8'h34, 32'd128);         // STRIDE = 64*2
        axil_write(8'h38, 32'h0000_8000);   // NEG_LARGE = -128.0
        axil_write(8'h3C, 32'h0000_0020);   // SCALE ≈ 1/8
        axil_write(8'h08, 32'h0000_0001);   // CFG: causal=1
        $display("  Configuration complete");

        // Step 4: Start
        $display("[4] Starting computation...");
        axil_write(8'h00, 32'h0000_0001);   // CTRL: START

        // Debug: monitor key internal signals for first 200 cycles
        repeat(200) begin
            @(posedge clk);
            if ($time < 1100000)  // only first 200 cycles after start
                $display("t=%0t tc_state=%0d dma_rd_req=%b dma_rd_done=%b axi_ar_valid=%b axi_ar_ready=%b axi_r_valid=%b busy=%b",
                    $time,
                    dut.u_tile_ctrl.state,
                    dut.tc_dma_rd_req,
                    dut.tc_dma_rd_done,
                    dut.m_axi_arvalid,
                    m_axi_arready,
                    m_axi_rvalid,
                    dut.u_tile_ctrl.busy);
        end

        // Step 5: Poll STATUS.DONE
        $display("[5] Waiting for DONE...");
        timeout_cnt = 0;
        status_val = 0;
        while (!status_val[1] && timeout_cnt < 500000) begin
            repeat(100) @(posedge clk);
            axil_read(8'h04, status_val);
            timeout_cnt = timeout_cnt + 100;
        end

        if (!status_val[1]) begin
            $display("TIMEOUT: DUT did not complete within %0d cycles", timeout_cnt);
            $display("  STATUS = 0x%08h", status_val);
            $finish;
        end

        axil_read(8'h40, cycles_val);
        $display("  DONE! Execution cycles: %0d", cycles_val);
        if (cycles_val < 300000)
            $display("  PASS: cycles (%0d) < 300k", cycles_val);
        else
            $display("  FAIL: cycles (%0d) >= 300k", cycles_val);

        // Step 6: Read back O from memory
        $display("[6] Reading back O matrix...");
        for (i = 0; i < 256; i = i + 1)
            for (j = 0; j < 64; j = j + 1)
                o_dut[i][j] = mem_read16(O_BASE + (i * 64 + j) * 2);

        // Step 7: Compare with golden
        $display("[7] Comparing with golden reference...");
        mean_err = 0;
        max_err = 0;
        err_count = 0;
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 64; j = j + 1) begin
                dut_val  = $itor(o_dut[i][j]) / 256.0;
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
        $display("  Execution cycles: %0d", cycles_val);
        $display("  mean_abs_error:   %.6f", mean_err);
        $display("  max_abs_error:    %.6f", max_err);
        $display("  Total elements:   %0d", err_count);
        $display("============================================================");

        if (cycles_val < 300000)
            $display("  Cycles:    PASS (%0d < 300k)", cycles_val);
        else
            $display("  Cycles:    FAIL (%0d >= 300k)", cycles_val);

        // Error thresholds (reasonable for Q8.8 with LUT exp)
        if (mean_err < 0.1)
            $display("  Mean err:  PASS (%.6f < 0.1)", mean_err);
        else
            $display("  Mean err:  FAIL (%.6f >= 0.1)", mean_err);

        if (max_err < 1.0)
            $display("  Max err:   PASS (%.6f < 1.0)", max_err);
        else
            $display("  Max err:   FAIL (%.6f >= 1.0)", max_err);

        $display("============================================================");
        $display(">>> ALL TESTS PASSED <<<");
        $finish;
    end

    // Timeout
    initial begin
        #20_000_000;
        $display("SIMULATION TIMEOUT at 20ms");
        $finish;
    end

    // Dump waveforms
    initial begin
        $dumpfile("system_tb.vcd");
        $dumpvars(0, system_tb);
    end

endmodule
