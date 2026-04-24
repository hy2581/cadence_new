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

    // ========== AXI Write Probe (FA_WB_DBG) ==========
    // Counts AXI write handshakes per burst and total bytes written to memory,
    // and logs every AW channel transaction to localize write-loss bugs.
`ifdef FA_WB_DBG
    int wb_total_beats;
    int wb_total_aw;
    logic [63:0] wb_last_awaddr;
    logic [7:0]  wb_last_awlen;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_total_beats  <= 0;
            wb_total_aw     <= 0;
            wb_last_awaddr  <= '0;
            wb_last_awlen   <= '0;
        end else begin
            if (mem_if.m_axi_awvalid && mem_if.m_axi_awready) begin
                wb_total_aw    <= wb_total_aw + 1;
                wb_last_awaddr <= mem_if.m_axi_awaddr;
                wb_last_awlen  <= mem_if.m_axi_awlen;
                $display("[FA_WB_DBG %0t] AW #%0d addr=0x%016h len=%0d",
                         $time, wb_total_aw + 1, mem_if.m_axi_awaddr, mem_if.m_axi_awlen + 1);
            end
            if (mem_if.m_axi_wvalid && mem_if.m_axi_wready) begin
                wb_total_beats <= wb_total_beats + 1;
            end
            if (mem_if.m_axi_bvalid && mem_if.m_axi_bready) begin
                $display("[FA_WB_DBG %0t] B-resp; total_beats=%0d total_aw=%0d",
                         $time, wb_total_beats + ((mem_if.m_axi_wvalid && mem_if.m_axi_wready)?1:0),
                         wb_total_aw);
            end
            // 打印 AW 的第一拍写数据 (8 个 16-bit element)，用来判断写数据是否为 0
            if (mem_if.m_axi_wvalid && mem_if.m_axi_wready && wb_total_aw < 10) begin
                $display("[FA_WB_DBG %0t] W  aw=%0d beat=%0d wdata[0..3]=%04h %04h %04h %04h",
                    $time, wb_total_aw, wb_total_beats,
                    mem_if.m_axi_wdata[15:0], mem_if.m_axi_wdata[31:16],
                    mem_if.m_axi_wdata[47:32], mem_if.m_axi_wdata[63:48]);
            end
        end
    end

    // Probe buffer_system write activity + dp_start/dp_done snapshots
    int q_wr_cnt, k_wr_cnt, v_wr_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_wr_cnt <= 0; k_wr_cnt <= 0; v_wr_cnt <= 0;
        end else begin
            if (u_dut.u_buffers.q_wr_en) begin
                q_wr_cnt <= q_wr_cnt + 1;
                if (q_wr_cnt < 4)
                    $display("[FA_WB_DBG %0t] Q_WR #%0d addr=%0d wdata[0..3]=%04h %04h %04h %04h",
                        $time, q_wr_cnt + 1, u_dut.u_buffers.q_wr_addr,
                        u_dut.u_buffers.q_wr_data[15:0],
                        u_dut.u_buffers.q_wr_data[31:16],
                        u_dut.u_buffers.q_wr_data[47:32],
                        u_dut.u_buffers.q_wr_data[63:48]);
            end
            if (u_dut.u_buffers.k_wr_en) begin
                k_wr_cnt <= k_wr_cnt + 1;
                if (k_wr_cnt < 4)
                    $display("[FA_WB_DBG %0t] K_WR #%0d buf=%0d addr=%0d wdata[0..3]=%04h %04h %04h %04h",
                        $time, k_wr_cnt + 1, u_dut.u_buffers.k_buf_sel, u_dut.u_buffers.k_wr_addr,
                        u_dut.u_buffers.k_wr_data[15:0],
                        u_dut.u_buffers.k_wr_data[31:16],
                        u_dut.u_buffers.k_wr_data[47:32],
                        u_dut.u_buffers.k_wr_data[63:48]);
            end
            if (u_dut.u_buffers.v_wr_en) v_wr_cnt <= v_wr_cnt + 1;
        end
    end

    // Probe at first dp_start: dump q_mem / k_mem sample addresses
    int dp_start_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) dp_start_cnt <= 0;
        else if (u_dut.u_compute.dp_start && dp_start_cnt < 2) begin
            dp_start_cnt <= dp_start_cnt + 1;
            $display("[FA_WB_DBG %0t] DP_START #%0d: q_wr_total=%0d k_wr_total=%0d v_wr_total=%0d",
                $time, dp_start_cnt + 1, q_wr_cnt, k_wr_cnt, v_wr_cnt);
            $display("[FA_WB_DBG %0t]   q_mem[0..7]=%04h %04h %04h %04h %04h %04h %04h %04h",
                $time,
                u_dut.u_buffers.q_mem[0], u_dut.u_buffers.q_mem[1],
                u_dut.u_buffers.q_mem[2], u_dut.u_buffers.q_mem[3],
                u_dut.u_buffers.q_mem[4], u_dut.u_buffers.q_mem[5],
                u_dut.u_buffers.q_mem[6], u_dut.u_buffers.q_mem[7]);
            $display("[FA_WB_DBG %0t]   q_mem[63 64 127 128 191 192 255]=%04h %04h %04h %04h %04h %04h %04h",
                $time,
                u_dut.u_buffers.q_mem[63], u_dut.u_buffers.q_mem[64],
                u_dut.u_buffers.q_mem[127], u_dut.u_buffers.q_mem[128],
                u_dut.u_buffers.q_mem[191], u_dut.u_buffers.q_mem[192],
                u_dut.u_buffers.q_mem[255]);
            $display("[FA_WB_DBG %0t]   k_mem[0][0..3]=%04h %04h %04h %04h  k_mem[0][1023]=%04h  k_mem[1][0]=%04h",
                $time,
                u_dut.u_buffers.k_mem[0][0], u_dut.u_buffers.k_mem[0][1],
                u_dut.u_buffers.k_mem[0][2], u_dut.u_buffers.k_mem[0][3],
                u_dut.u_buffers.k_mem[0][1023], u_dut.u_buffers.k_mem[1][0]);
        end
    end

    // Probe dp data_valid cycles — first 3 cycles of dot product stream
    int dpv_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) dpv_cnt <= 0;
        else if (u_dut.u_compute.dp_data_valid && dpv_cnt < 3) begin
            dpv_cnt <= dpv_cnt + 1;
            $display("[FA_WB_DBG %0t] DP_DATAV #%0d: q_rd_step=%0d k_rd_step=%0d q_data[0][0..3]=%04h %04h %04h %04h k_data[0][0..3]=%04h %04h %04h %04h",
                $time, dpv_cnt + 1,
                u_dut.u_compute.q_rd_step, u_dut.u_compute.k_rd_step,
                u_dut.u_compute.q_data[0][0], u_dut.u_compute.q_data[0][1],
                u_dut.u_compute.q_data[0][2], u_dut.u_compute.q_data[0][3],
                u_dut.u_compute.k_data[0][0], u_dut.u_compute.k_data[0][1],
                u_dut.u_compute.k_data[0][2], u_dut.u_compute.k_data[0][3]);
        end
    end

    // Probe dp_done — dump dp_scores samples
    int dpd_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) dpd_cnt <= 0;
        else if (u_dut.u_compute.dp_done && dpd_cnt < 2) begin
            dpd_cnt <= dpd_cnt + 1;
            $display("[FA_WB_DBG %0t] DP_DONE #%0d: dp_scores[0][0..3]=%010h %010h %010h %010h  dp_scores[3][15]=%010h",
                $time, dpd_cnt + 1,
                u_dut.u_compute.dp_scores[0][0], u_dut.u_compute.dp_scores[0][1],
                u_dut.u_compute.dp_scores[0][2], u_dut.u_compute.dp_scores[0][3],
                u_dut.u_compute.dp_scores[3][15]);
        end
    end

    // Probe Q-tile transitions — capture compute_core start on each Q-tile
    int qtile_start_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) qtile_start_cnt <= 0;
        else if (u_dut.u_compute.start && u_dut.u_compute.first_kv_tile && qtile_start_cnt < 4) begin
            qtile_start_cnt <= qtile_start_cnt + 1;
            $display("[FA_WB_DBG %0t] QTILE_START #%0d (first_kv): cc.state=%0d m_old[0]=%010h l_old[0]=%010h q_tile_idx=%0d kv_buf_sel=%0d",
                $time, qtile_start_cnt + 1,
                u_dut.u_compute.state,
                u_dut.u_compute.m_old[0],
                u_dut.u_compute.l_old[0],
                u_dut.u_compute.q_tile_idx,
                u_dut.u_tile_ctrl.kv_buf_sel);
        end
    end

    // Probe softmax completion — print first sm_valid in each of first 4 Q-tiles.
    int smp_count;
    int smp_last_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin smp_count <= 0; smp_last_q <= -1; end
        else if (u_dut.u_compute.u_softmax.results_valid &&
                 u_dut.u_compute.q_tile_idx != smp_last_q && smp_count < 4) begin
            smp_last_q <= u_dut.u_compute.q_tile_idx;
            smp_count <= smp_count + 1;
            $display("[FA_WB_DBG %0t] SM_VALID_Q%0d: m_new[0]=%010h l_new[0]=%010h rescale[0]=%010h p_matrix[0][0]=%06h first_tile=%0d",
                $time, u_dut.u_compute.q_tile_idx,
                u_dut.u_compute.u_softmax.m_new[0],
                u_dut.u_compute.u_softmax.l_new[0],
                u_dut.u_compute.u_softmax.rescale[0],
                u_dut.u_compute.u_softmax.p_matrix[0][0],
                u_dut.u_compute.first_kv_tile);
        end
    end

    // Also print original first-3 sm_valid (covers multi-KV-tile sequence in Q-tile 0)
    int smp_count_kv;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) smp_count_kv <= 0;
        else if (u_dut.u_compute.u_softmax.results_valid && smp_count_kv < 3) begin
            smp_count_kv <= smp_count_kv + 1;
            $display("[FA_WB_DBG %0t] SM_VALID #%0d: m_new[0]=%010h l_new[0]=%010h rescale[0]=%010h p_matrix[0][0]=%06h",
                $time, smp_count_kv + 1,
                u_dut.u_compute.u_softmax.m_new[0],
                u_dut.u_compute.u_softmax.l_new[0],
                u_dut.u_compute.u_softmax.rescale[0],
                u_dut.u_compute.u_softmax.p_matrix[0][0]);
        end
    end

    // Probe compute_core → buffer_system o_wr_en pulse + a few sample values
    // Use a hierarchical reference into the DUT. Print the first 3 pulses only.
    int ovp_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) ovp_count <= 0;
        else if (u_dut.comp_o_valid && ovp_count < 3) begin
            ovp_count <= ovp_count + 1;
            $display("[FA_WB_DBG %0t] O_VALID pulse #%0d: o_tile[0][0..3]=%04h %04h %04h %04h  o_tile[1][0]=%04h  o_tile[3][63]=%04h",
                $time, ovp_count + 1,
                u_dut.comp_o_tile[0][0], u_dut.comp_o_tile[0][1],
                u_dut.comp_o_tile[0][2], u_dut.comp_o_tile[0][3],
                u_dut.comp_o_tile[1][0], u_dut.comp_o_tile[3][63]);
            $display("[FA_WB_DBG %0t]   OA: l_new[0..3]=%010h %010h %010h %010h",
                $time,
                u_dut.u_compute.l_new[0],
                u_dut.u_compute.l_new[1],
                u_dut.u_compute.l_new[2],
                u_dut.u_compute.l_new[3]);
            $display("[FA_WB_DBG %0t]   OA: recip_vals[0..3]=%010h %010h %010h %010h",
                $time,
                u_dut.u_compute.u_oa.recip_vals[0],
                u_dut.u_compute.u_oa.recip_vals[1],
                u_dut.u_compute.u_oa.recip_vals[2],
                u_dut.u_compute.u_oa.recip_vals[3]);
            $display("[FA_WB_DBG %0t]   OA: o_acc[0][0..3]=%010h %010h %010h %010h  o_acc[1][0]=%010h",
                $time,
                u_dut.u_compute.u_oa.o_acc[0][0],
                u_dut.u_compute.u_oa.o_acc[0][1],
                u_dut.u_compute.u_oa.o_acc[0][2],
                u_dut.u_compute.u_oa.o_acc[0][3],
                u_dut.u_compute.u_oa.o_acc[1][0]);
            $display("[FA_WB_DBG %0t]   OSX: m_new[0..3]=%010h %010h %010h %010h",
                $time,
                u_dut.u_compute.m_new[0],
                u_dut.u_compute.m_new[1],
                u_dut.u_compute.m_new[2],
                u_dut.u_compute.m_new[3]);
            $display("[FA_WB_DBG %0t]   STATES: oa.state=%0d  sm.state=%0d  cc.state=%0d  m_old[0]=%010h l_old[0]=%010h",
                $time,
                u_dut.u_compute.u_oa.state,
                u_dut.u_compute.u_softmax.state,
                u_dut.u_compute.state,
                u_dut.u_compute.m_old[0],
                u_dut.u_compute.l_old[0]);
        end
    end
`endif

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
            // Xcelium 24.09 的 $shm_open 不支持 string 变量 (xmelab: *E,STRNOT)
            // 这里固定文件名；路径由 xrun 在工作目录内/目录外经由 cwd 选择。
            $shm_open("waves.shm");
            $shm_probe(fa_tb_top, "AS");
            $display("[fa_tb_top] SHM dump enabled -> ./waves.shm (probe: fa_tb_top / AS)");
        end
    end

endmodule
