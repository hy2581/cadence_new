// ============================================================
// FlashAttention Baseline Enhanced Verification Testbench
// Adds RAL-like register mirror checks, AXI VIP-lite monitors,
// DMA range/count checks, functional/performance checks, and
// functional coverage for the contest verification completion.
// ============================================================
`timescale 1ns/1ps
`include "fa_params.svh"

module fa_verification_tb;

    localparam [63:0] Q_BASE = 64'h0001_0000;
    localparam [63:0] K_BASE = 64'h0002_0000;
    localparam [63:0] V_BASE = 64'h0003_0000;
    localparam [63:0] O_BASE = 64'h0004_0000;

    localparam longint unsigned TENSOR_BYTES        = 32768;
    localparam longint unsigned EXPECT_Q_READ_BYTES = 32768;
    localparam longint unsigned EXPECT_K_READ_BYTES = 1114112;
    localparam longint unsigned EXPECT_V_READ_BYTES = 1114112;
    localparam longint unsigned EXPECT_O_WR_BYTES   = 32768;
    localparam longint unsigned EXPECT_RD_BYTES     = 2260992;
    localparam longint unsigned EXPECT_WR_BYTES     = 32768;

    localparam real MEAN_LIMIT        = 0.03;
    localparam real MAX_LIMIT         = 0.10;
    localparam real CAUSAL_ROW0_LIMIT = 0.02;

    logic clk, rst_n;
    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end
    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
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

    assign m_axi_rid = m_axi_arid;
    assign m_axi_bid = m_axi_awid;

    longint unsigned axil_aw_count, axil_w_count, axil_b_count, axil_ar_count, axil_r_count;
    longint unsigned axi_aw_count, axi_w_beat_count, axi_b_count, axi_ar_count, axi_r_beat_count;
    longint unsigned axi_read_bytes, axi_write_bytes;

    fa_axil_vip_lite_monitor u_axil_vip (
        .clk(clk), .rst_n(rst_n),
        .awaddr(s_axil_awaddr), .awvalid(s_axil_awvalid), .awready(s_axil_awready),
        .wdata(s_axil_wdata), .wstrb(s_axil_wstrb), .wvalid(s_axil_wvalid), .wready(s_axil_wready),
        .bresp(s_axil_bresp), .bvalid(s_axil_bvalid), .bready(s_axil_bready),
        .araddr(s_axil_araddr), .arvalid(s_axil_arvalid), .arready(s_axil_arready),
        .rdata(s_axil_rdata), .rresp(s_axil_rresp), .rvalid(s_axil_rvalid), .rready(s_axil_rready),
        .aw_count(axil_aw_count), .w_count(axil_w_count), .b_count(axil_b_count),
        .ar_count(axil_ar_count), .r_count(axil_r_count)
    );

    fa_axi4_master_vip_lite_monitor u_axi_vip (
        .clk(clk), .rst_n(rst_n),
        .awid(m_axi_awid), .awaddr(m_axi_awaddr), .awlen(m_axi_awlen), .awsize(m_axi_awsize),
        .awburst(m_axi_awburst), .awvalid(m_axi_awvalid), .awready(m_axi_awready),
        .wdata(m_axi_wdata), .wstrb(m_axi_wstrb), .wlast(m_axi_wlast),
        .wvalid(m_axi_wvalid), .wready(m_axi_wready),
        .bid(m_axi_bid), .bresp(m_axi_bresp), .bvalid(m_axi_bvalid), .bready(m_axi_bready),
        .arid(m_axi_arid), .araddr(m_axi_araddr), .arlen(m_axi_arlen), .arsize(m_axi_arsize),
        .arburst(m_axi_arburst), .arvalid(m_axi_arvalid), .arready(m_axi_arready),
        .rid(m_axi_rid), .rdata(m_axi_rdata), .rresp(m_axi_rresp), .rlast(m_axi_rlast),
        .rvalid(m_axi_rvalid), .rready(m_axi_rready),
        .aw_count(axi_aw_count), .w_beat_count(axi_w_beat_count), .b_count(axi_b_count),
        .ar_count(axi_ar_count), .r_beat_count(axi_r_beat_count),
        .read_bytes(axi_read_bytes), .write_bytes(axi_write_bytes)
    );

    logic [9:0]  lut_cov_addr;
    logic [23:0] lut_cov_data;
    exp_lut_rom u_lut_cov (
        .addr(lut_cov_addr),
        .data(lut_cov_data)
    );

    logic                          exp_cov_valid_in, exp_cov_valid_out;
    logic signed [39:0]            exp_cov_x_in;
    logic [23:0]                   exp_cov_out;
    exp_approx_unit #(
        .IN_WIDTH(40), .FRAC_IN(16),
        .OUT_WIDTH(24), .FRAC_OUT(16)
    ) u_exp_cov (
        .clk(clk), .rst_n(rst_n),
        .valid_in(exp_cov_valid_in), .x_in(exp_cov_x_in),
        .valid_out(exp_cov_valid_out), .exp_out(exp_cov_out)
    );

    logic [7:0]  self_axil_awaddr, self_axil_araddr;
    logic        self_axil_awvalid, self_axil_awready;
    logic        self_axil_wvalid, self_axil_wready;
    logic [31:0] self_axil_wdata, self_axil_rdata;
    logic [3:0]  self_axil_wstrb;
    logic [1:0]  self_axil_bresp, self_axil_rresp;
    logic        self_axil_bvalid, self_axil_bready;
    logic        self_axil_arvalid, self_axil_arready;
    logic        self_axil_rvalid, self_axil_rready;

    logic [3:0]   self_axi_awid, self_axi_bid, self_axi_arid, self_axi_rid;
    logic [63:0]  self_axi_awaddr, self_axi_araddr;
    logic [7:0]   self_axi_awlen, self_axi_arlen;
    logic [2:0]   self_axi_awsize, self_axi_arsize;
    logic [1:0]   self_axi_awburst, self_axi_arburst, self_axi_bresp, self_axi_rresp;
    logic         self_axi_awvalid, self_axi_awready;
    logic [127:0] self_axi_wdata, self_axi_rdata;
    logic [15:0]  self_axi_wstrb;
    logic         self_axi_wlast, self_axi_wvalid, self_axi_wready;
    logic         self_axi_bvalid, self_axi_bready;
    logic         self_axi_arvalid, self_axi_arready;
    logic         self_axi_rlast, self_axi_rvalid, self_axi_rready;

    longint unsigned self_axil_aw_count, self_axil_w_count, self_axil_b_count;
    longint unsigned self_axil_ar_count, self_axil_r_count;
    longint unsigned self_axi_aw_count, self_axi_w_beat_count, self_axi_b_count;
    longint unsigned self_axi_ar_count, self_axi_r_beat_count;
    longint unsigned self_axi_read_bytes, self_axi_write_bytes;

    fa_axil_vip_lite_monitor u_axil_vip_selftest (
        .clk(clk), .rst_n(rst_n),
        .awaddr(self_axil_awaddr), .awvalid(self_axil_awvalid), .awready(self_axil_awready),
        .wdata(self_axil_wdata), .wstrb(self_axil_wstrb),
        .wvalid(self_axil_wvalid), .wready(self_axil_wready),
        .bresp(self_axil_bresp), .bvalid(self_axil_bvalid), .bready(self_axil_bready),
        .araddr(self_axil_araddr), .arvalid(self_axil_arvalid), .arready(self_axil_arready),
        .rdata(self_axil_rdata), .rresp(self_axil_rresp),
        .rvalid(self_axil_rvalid), .rready(self_axil_rready),
        .aw_count(self_axil_aw_count), .w_count(self_axil_w_count),
        .b_count(self_axil_b_count), .ar_count(self_axil_ar_count),
        .r_count(self_axil_r_count)
    );

    fa_axi4_master_vip_lite_monitor u_axi_vip_selftest (
        .clk(clk), .rst_n(rst_n),
        .awid(self_axi_awid), .awaddr(self_axi_awaddr), .awlen(self_axi_awlen),
        .awsize(self_axi_awsize), .awburst(self_axi_awburst),
        .awvalid(self_axi_awvalid), .awready(self_axi_awready),
        .wdata(self_axi_wdata), .wstrb(self_axi_wstrb), .wlast(self_axi_wlast),
        .wvalid(self_axi_wvalid), .wready(self_axi_wready),
        .bid(self_axi_bid), .bresp(self_axi_bresp),
        .bvalid(self_axi_bvalid), .bready(self_axi_bready),
        .arid(self_axi_arid), .araddr(self_axi_araddr), .arlen(self_axi_arlen),
        .arsize(self_axi_arsize), .arburst(self_axi_arburst),
        .arvalid(self_axi_arvalid), .arready(self_axi_arready),
        .rid(self_axi_rid), .rdata(self_axi_rdata), .rresp(self_axi_rresp),
        .rlast(self_axi_rlast), .rvalid(self_axi_rvalid), .rready(self_axi_rready),
        .aw_count(self_axi_aw_count), .w_beat_count(self_axi_w_beat_count),
        .b_count(self_axi_b_count), .ar_count(self_axi_ar_count),
        .r_beat_count(self_axi_r_beat_count),
        .read_bytes(self_axi_read_bytes), .write_bytes(self_axi_write_bytes)
    );

    // RAL-like mirror model
    logic [31:0] reg_mirror [0:255];

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_data,
        input logic [31:0] new_data,
        input logic [3:0]  strb
    );
        logic [31:0] merged;
        begin
            merged = old_data;
            for (int b = 0; b < 4; b++) begin
                if (strb[b])
                    merged[b*8 +: 8] = new_data[b*8 +: 8];
            end
            apply_wstrb = merged;
        end
    endfunction

    function automatic bit reg_is_rw(input logic [7:0] addr);
        begin
            case (addr)
                REG_CTRL, REG_CFG,
                REG_Q_BASE_L, REG_Q_BASE_H, REG_K_BASE_L, REG_K_BASE_H,
                REG_V_BASE_L, REG_V_BASE_H, REG_O_BASE_L, REG_O_BASE_H,
                REG_STRIDE_BYTES, REG_NEG_LARGE, REG_SCALE: reg_is_rw = 1'b1;
                default: reg_is_rw = 1'b0;
            endcase
        end
    endfunction

    function automatic int dma_region(
        input bit is_write,
        input logic [63:0] addr,
        input longint unsigned bytes
    );
        begin
            dma_region = -1;
            if (!is_write && addr >= Q_BASE && (addr + bytes) <= (Q_BASE + TENSOR_BYTES))
                dma_region = 0;
            else if (!is_write && addr >= K_BASE && (addr + bytes) <= (K_BASE + TENSOR_BYTES))
                dma_region = 1;
            else if (!is_write && addr >= V_BASE && (addr + bytes) <= (V_BASE + TENSOR_BYTES))
                dma_region = 2;
            else if (is_write && addr >= O_BASE && (addr + bytes) <= (O_BASE + TENSOR_BYTES))
                dma_region = 3;
        end
    endfunction

    function automatic longint unsigned burst_byte_count(
        input logic [7:0] len,
        input logic [2:0] size
    );
        begin
            burst_byte_count = (longint'(len) + 1) << size;
        end
    endfunction

    task automatic rm_reset();
        for (int a = 0; a < 256; a++) begin
            reg_mirror[a] = 32'h0;
        end
        reg_mirror[REG_STRIDE_BYTES] = 32'd128;
        reg_mirror[REG_NEG_LARGE]    = 32'hFFFF_8000;
        reg_mirror[REG_SCALE]        = 32'h0000_0020;
    endtask

    task automatic rm_predict_write(
        input logic [7:0]  addr,
        input logic [31:0] data,
        input logic [3:0]  strb
    );
        logic [31:0] merged;
        begin
            merged = apply_wstrb(reg_mirror[addr], data, strb);
            if (addr == REG_CTRL) begin
                reg_mirror[addr] = {merged[31:3], merged[2], 2'b00};
            end else if (addr == REG_STATUS) begin
                if (apply_wstrb(32'h0, data, strb)[STATUS_DONE])
                    reg_mirror[REG_STATUS][STATUS_DONE] = 1'b0;
            end else if (reg_is_rw(addr)) begin
                reg_mirror[addr] = merged;
            end
        end
    endtask

    covergroup reg_access_cg with function sample(bit is_write, bit [7:0] addr, bit [3:0] strb);
        option.per_instance = 1;
        cp_kind: coverpoint is_write {
            bins read  = {0};
            bins write = {1};
        }
        cp_addr: coverpoint addr {
            bins ctrl       = {REG_CTRL};
            bins status     = {REG_STATUS};
            bins cfg        = {REG_CFG};
            bins q_base_l   = {REG_Q_BASE_L};
            bins q_base_h   = {REG_Q_BASE_H};
            bins k_base_l   = {REG_K_BASE_L};
            bins k_base_h   = {REG_K_BASE_H};
            bins v_base_l   = {REG_V_BASE_L};
            bins v_base_h   = {REG_V_BASE_H};
            bins o_base_l   = {REG_O_BASE_L};
            bins o_base_h   = {REG_O_BASE_H};
            bins stride     = {REG_STRIDE_BYTES};
            bins neg_large  = {REG_NEG_LARGE};
            bins scale      = {REG_SCALE};
            bins cycles     = {REG_CYCLES};
            bins rd_bytes   = {REG_RD_BYTES};
            bins wr_bytes   = {REG_WR_BYTES};
        }
        cp_strb: coverpoint strb iff (is_write) {
            bins full       = {4'hF};
            bins low_half   = {4'h3};
            bins byte0      = {4'h1};
            bins partial    = default;
        }
        cross cp_kind, cp_addr;
    endgroup

    covergroup flow_cg with function sample(int event_id);
        option.per_instance = 1;
        cp_event: coverpoint event_id {
            bins soft_reset = {0};
            bins start      = {1};
            bins busy       = {2};
            bins done       = {3};
            bins done_clear = {4};
            bins causal     = {5};
        }
    endgroup

    covergroup dma_cg with function sample(int region, bit is_write, int beats);
        option.per_instance = 1;
        cp_region: coverpoint region {
            bins q_read  = {0};
            bins k_read  = {1};
            bins v_read  = {2};
            bins o_write = {3};
        }
        cp_kind: coverpoint is_write {
            bins read  = {0};
            bins write = {1};
        }
        cp_beats: coverpoint beats {
            bins q_o_tile = {32};
            bins kv_tile  = {128};
        }
    endgroup

    covergroup axi_cg with function sample(int channel, int beats, int size_code);
        option.per_instance = 1;
        cp_channel: coverpoint channel {
            bins aw = {0};
            bins w  = {1};
            bins b  = {2};
            bins ar = {3};
            bins r  = {4};
        }
        cp_beats: coverpoint beats {
            bins single    = {1};
            bins q_o_tile  = {32};
            bins kv_tile   = {128};
            bins other     = default;
        }
        cp_size: coverpoint size_code {
            bins bytes16 = {4};
        }
    endgroup

    covergroup perf_cg with function sample(int cycles, int mean_bucket, int max_bucket, int causal_bucket);
        option.per_instance = 1;
        cp_cycles: coverpoint cycles {
            bins under_300k = {[0:299999]};
            illegal_bins over_300k = {[300000:$]};
        }
        cp_mean: coverpoint mean_bucket {
            bins pass = {0};
            illegal_bins fail = {1};
        }
        cp_max: coverpoint max_bucket {
            bins pass = {0};
            illegal_bins fail = {1};
        }
        cp_causal: coverpoint causal_bucket {
            bins pass = {0};
            illegal_bins fail = {1};
        }
    endgroup

    covergroup exp_cg with function sample(int event_id);
        option.per_instance = 1;
        cp_event: coverpoint event_id {
            bins lut_sweep  = {0};
            bins clamp_low  = {1};
            bins nominal    = {2};
            bins clamp_high = {3};
        }
    endgroup

    covergroup vip_stall_cg with function sample(int event_id);
        option.per_instance = 1;
        cp_event: coverpoint event_id {
            bins axil_aw = {0};
            bins axil_w  = {1};
            bins axil_ar = {2};
            bins axil_r  = {3};
            bins axi_aw  = {4};
            bins axi_w   = {5};
            bins axi_ar  = {6};
            bins axi_r   = {7};
        }
    endgroup

    reg_access_cg reg_cov;
    flow_cg      flow_cov;
    dma_cg       dma_cov;
    axi_cg       axi_cov;
    perf_cg      perf_cov;
    exp_cg       exp_cov;
    vip_stall_cg vip_stall_cov;

    longint unsigned dma_q_read_bytes, dma_k_read_bytes, dma_v_read_bytes, dma_o_write_bytes;
    longint unsigned dma_total_read_bytes, dma_total_write_bytes;
    longint unsigned dma_ar_count, dma_aw_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_q_read_bytes    <= 0;
            dma_k_read_bytes    <= 0;
            dma_v_read_bytes    <= 0;
            dma_o_write_bytes   <= 0;
            dma_total_read_bytes <= 0;
            dma_total_write_bytes <= 0;
            dma_ar_count        <= 0;
            dma_aw_count        <= 0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                longint unsigned burst_bytes;
                int region;
                burst_bytes = burst_byte_count(m_axi_arlen, m_axi_arsize);
                region = dma_region(1'b0, m_axi_araddr, burst_bytes);
                if (region < 0)
                    $fatal(1, "DMA check: AR range out of Q/K/V bounds addr=0x%016h bytes=%0d", m_axi_araddr, burst_bytes);
                dma_cov.sample(region, 1'b0, m_axi_arlen + 1);
                axi_cov.sample(3, m_axi_arlen + 1, m_axi_arsize);
                dma_ar_count <= dma_ar_count + 1;
                dma_total_read_bytes <= dma_total_read_bytes + burst_bytes;
                case (region)
                    0: dma_q_read_bytes <= dma_q_read_bytes + burst_bytes;
                    1: dma_k_read_bytes <= dma_k_read_bytes + burst_bytes;
                    2: dma_v_read_bytes <= dma_v_read_bytes + burst_bytes;
                    default: ;
                endcase
            end

            if (m_axi_awvalid && m_axi_awready) begin
                longint unsigned burst_bytes;
                int region;
                burst_bytes = burst_byte_count(m_axi_awlen, m_axi_awsize);
                region = dma_region(1'b1, m_axi_awaddr, burst_bytes);
                if (region != 3)
                    $fatal(1, "DMA check: AW range out of O bounds addr=0x%016h bytes=%0d", m_axi_awaddr, burst_bytes);
                dma_cov.sample(region, 1'b1, m_axi_awlen + 1);
                axi_cov.sample(0, m_axi_awlen + 1, m_axi_awsize);
                dma_aw_count <= dma_aw_count + 1;
                dma_o_write_bytes <= dma_o_write_bytes + burst_bytes;
                dma_total_write_bytes <= dma_total_write_bytes + burst_bytes;
            end

            if (m_axi_wvalid && m_axi_wready)
                axi_cov.sample(1, 1, m_axi_awsize);
            if (m_axi_bvalid && m_axi_bready)
                axi_cov.sample(2, 1, 4);
            if (m_axi_rvalid && m_axi_rready)
                axi_cov.sample(4, 1, m_axi_arsize);
        end
    end

    task automatic axil_write(
        input logic [7:0]  addr,
        input logic [31:0] data,
        input logic [3:0]  strb
    );
        begin
            @(posedge clk);
            s_axil_awaddr  = addr;
            s_axil_awvalid = 1'b1;
            s_axil_wdata   = data;
            s_axil_wstrb   = strb;
            s_axil_wvalid  = 1'b1;
            @(posedge clk);
            while (!(s_axil_awready && s_axil_wready)) begin
                @(posedge clk);
            end
            s_axil_awvalid = 1'b0;
            s_axil_wvalid  = 1'b0;
            s_axil_bready  = 1'b1;
            while (!s_axil_bvalid) begin
                @(posedge clk);
            end
            if (s_axil_bresp != 2'b00)
                $fatal(1, "AXI-Lite write BRESP error at addr=0x%02h", addr);
            @(posedge clk);
            s_axil_bready = 1'b0;
            reg_cov.sample(1'b1, addr, strb);
            rm_predict_write(addr, data, strb);
        end
    endtask

    task automatic axil_read(input logic [7:0] addr, output logic [31:0] data);
        begin
            @(posedge clk);
            s_axil_araddr  = addr;
            s_axil_arvalid = 1'b1;
            @(posedge clk);
            while (!s_axil_arready) begin
                @(posedge clk);
            end
            s_axil_arvalid = 1'b0;
            s_axil_rready  = 1'b1;
            while (!s_axil_rvalid) begin
                @(posedge clk);
            end
            if (s_axil_rresp != 2'b00)
                $fatal(1, "AXI-Lite read RRESP error at addr=0x%02h", addr);
            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready = 1'b0;
            reg_cov.sample(1'b0, addr, 4'h0);
        end
    endtask

    task automatic axil_read_check(
        input logic [7:0]  addr,
        input logic [31:0] expected,
        input string       name
    );
        logic [31:0] actual;
        begin
            axil_read(addr, actual);
            if (actual !== expected)
                $fatal(1, "Register check failed for %s addr=0x%02h actual=0x%08h expected=0x%08h",
                    name, addr, actual, expected);
        end
    endtask

    task automatic rm_write_check(
        input logic [7:0]  addr,
        input logic [31:0] data,
        input logic [3:0]  strb,
        input string       name
    );
        begin
            axil_write(addr, data, strb);
            if (reg_is_rw(addr))
                axil_read_check(addr, reg_mirror[addr], name);
        end
    endtask

    task automatic init_selftest_signals();
        begin
            lut_cov_addr = '0;
            exp_cov_valid_in = 1'b0;
            exp_cov_x_in = '0;

            self_axil_awaddr = '0;
            self_axil_araddr = '0;
            self_axil_awvalid = 1'b0;
            self_axil_awready = 1'b0;
            self_axil_wvalid = 1'b0;
            self_axil_wready = 1'b0;
            self_axil_wdata = '0;
            self_axil_rdata = '0;
            self_axil_wstrb = '0;
            self_axil_bresp = 2'b00;
            self_axil_rresp = 2'b00;
            self_axil_bvalid = 1'b0;
            self_axil_bready = 1'b0;
            self_axil_arvalid = 1'b0;
            self_axil_arready = 1'b0;
            self_axil_rvalid = 1'b0;
            self_axil_rready = 1'b0;

            self_axi_awid = '0;
            self_axi_bid = '0;
            self_axi_arid = '0;
            self_axi_rid = '0;
            self_axi_awaddr = '0;
            self_axi_araddr = '0;
            self_axi_awlen = '0;
            self_axi_arlen = '0;
            self_axi_awsize = 3'd4;
            self_axi_arsize = 3'd4;
            self_axi_awburst = 2'b01;
            self_axi_arburst = 2'b01;
            self_axi_bresp = 2'b00;
            self_axi_rresp = 2'b00;
            self_axi_awvalid = 1'b0;
            self_axi_awready = 1'b0;
            self_axi_wdata = '0;
            self_axi_rdata = '0;
            self_axi_wstrb = '0;
            self_axi_wlast = 1'b0;
            self_axi_wvalid = 1'b0;
            self_axi_wready = 1'b0;
            self_axi_bvalid = 1'b0;
            self_axi_bready = 1'b0;
            self_axi_arvalid = 1'b0;
            self_axi_arready = 1'b0;
            self_axi_rlast = 1'b0;
            self_axi_rvalid = 1'b0;
            self_axi_rready = 1'b0;
        end
    endtask

    task automatic drive_exp_cov(
        input logic signed [39:0] x_value,
        input int                 event_id,
        output logic [23:0]       y_value
    );
        begin
            @(negedge clk);
            exp_cov_x_in = x_value;
            exp_cov_valid_in = 1'b1;
            @(posedge clk);
            @(negedge clk);
            exp_cov_valid_in = 1'b0;
            wait (exp_cov_valid_out === 1'b1);
            y_value = exp_cov_out;
            exp_cov.sample(event_id);
            @(posedge clk);
        end
    endtask

    task automatic run_exp_lut_sanity_tests();
        logic [23:0] prev_data;
        logic [23:0] exp_y;
        begin
            $display("[EXP] Sweeping LUT and checking exp approximation clamps");
            lut_cov_addr = 10'd0;
            #1;
            prev_data = lut_cov_data;
            exp_cov.sample(0);
            for (int idx = 1; idx < 1024; idx++) begin
                lut_cov_addr = idx[9:0];
                #1;
                if (lut_cov_data < prev_data)
                    $fatal(1, "EXP LUT monotonicity failed at addr=%0d data=0x%06h prev=0x%06h",
                        idx, lut_cov_data, prev_data);
                prev_data = lut_cov_data;
            end

            drive_exp_cov(-40'sd1310720, 1, exp_y);
            if (exp_y != 24'd0)
                $fatal(1, "EXP clamp-low check failed: exp_y=0x%06h", exp_y);

            drive_exp_cov(40'sd0, 2, exp_y);
            if (exp_y < 24'h00F000 || exp_y > 24'h011000)
                $fatal(1, "EXP nominal exp(0) check failed: exp_y=0x%06h", exp_y);

            drive_exp_cov(40'sd327680, 3, exp_y);
            if (exp_y != 24'hFFFFFF)
                $fatal(1, "EXP clamp-high check failed: exp_y=0x%06h", exp_y);
            $display("[EXP] LUT and exp approximation checks passed");
        end
    endtask

    task automatic run_vip_stall_selftest();
        begin
            $display("[VIP] Exercising isolated AXI stall and payload-stability checks");

            self_axil_awaddr = 8'h20;
            self_axil_awvalid = 1'b1;
            self_axil_awready = 1'b0;
            vip_stall_cov.sample(0);
            repeat (2) @(posedge clk);
            @(negedge clk);
            self_axil_awready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axil_awvalid = 1'b0;
            self_axil_awready = 1'b0;

            self_axil_wdata = 32'hCAFE_1234;
            self_axil_wstrb = 4'h3;
            self_axil_wvalid = 1'b1;
            self_axil_wready = 1'b0;
            vip_stall_cov.sample(1);
            repeat (2) @(posedge clk);
            @(negedge clk);
            self_axil_wready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axil_wvalid = 1'b0;
            self_axil_wready = 1'b0;

            self_axil_bresp = 2'b00;
            self_axil_bvalid = 1'b1;
            self_axil_bready = 1'b0;
            @(posedge clk);
            @(negedge clk);
            self_axil_bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axil_bvalid = 1'b0;
            self_axil_bready = 1'b0;

            self_axil_araddr = 8'h44;
            self_axil_arvalid = 1'b1;
            self_axil_arready = 1'b0;
            vip_stall_cov.sample(2);
            repeat (2) @(posedge clk);
            @(negedge clk);
            self_axil_arready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axil_arvalid = 1'b0;
            self_axil_arready = 1'b0;

            self_axil_rdata = 32'h1234_ABCD;
            self_axil_rresp = 2'b00;
            self_axil_rvalid = 1'b1;
            self_axil_rready = 1'b0;
            vip_stall_cov.sample(3);
            repeat (2) @(posedge clk);
            @(negedge clk);
            self_axil_rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axil_rvalid = 1'b0;
            self_axil_rready = 1'b0;

            self_axi_awid = 4'h2;
            self_axi_awaddr = 64'h0000_0000_0000_1000;
            self_axi_awlen = 8'd1;
            self_axi_awsize = 3'd4;
            self_axi_awburst = 2'b01;
            self_axi_awvalid = 1'b1;
            self_axi_awready = 1'b0;
            vip_stall_cov.sample(4);
            repeat (2) @(posedge clk);
            @(negedge clk);
            self_axi_awready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axi_awvalid = 1'b0;
            self_axi_awready = 1'b0;
            @(posedge clk);

            self_axi_wdata = 128'h0001_0002_0003_0004_0005_0006_0007_0008;
            self_axi_wstrb = 16'hFFFF;
            self_axi_wlast = 1'b0;
            self_axi_wvalid = 1'b1;
            self_axi_wready = 1'b0;
            vip_stall_cov.sample(5);
            repeat (2) @(posedge clk);
            @(negedge clk);
            self_axi_wready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axi_wdata = 128'h1001_1002_1003_1004_1005_1006_1007_1008;
            self_axi_wlast = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axi_wvalid = 1'b0;
            self_axi_wready = 1'b0;
            self_axi_wlast = 1'b0;

            self_axi_bid = 4'h2;
            self_axi_bresp = 2'b00;
            self_axi_bvalid = 1'b1;
            self_axi_bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axi_bvalid = 1'b0;
            self_axi_bready = 1'b0;

            self_axi_arid = 4'h5;
            self_axi_araddr = 64'h0000_0000_0000_2000;
            self_axi_arlen = 8'd1;
            self_axi_arsize = 3'd4;
            self_axi_arburst = 2'b01;
            self_axi_arvalid = 1'b1;
            self_axi_arready = 1'b0;
            vip_stall_cov.sample(6);
            repeat (2) @(posedge clk);
            @(negedge clk);
            self_axi_arready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axi_arvalid = 1'b0;
            self_axi_arready = 1'b0;
            @(posedge clk);

            self_axi_rid = 4'h5;
            self_axi_rdata = 128'h2001_2002_2003_2004_2005_2006_2007_2008;
            self_axi_rresp = 2'b00;
            self_axi_rlast = 1'b0;
            self_axi_rvalid = 1'b1;
            self_axi_rready = 1'b0;
            vip_stall_cov.sample(7);
            repeat (2) @(posedge clk);
            @(negedge clk);
            self_axi_rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axi_rdata = 128'h3001_3002_3003_3004_3005_3006_3007_3008;
            self_axi_rlast = 1'b1;
            @(posedge clk);
            @(negedge clk);
            self_axi_rvalid = 1'b0;
            self_axi_rready = 1'b0;
            self_axi_rlast = 1'b0;

            if (self_axil_aw_count == 0 || self_axil_w_count == 0 ||
                self_axil_ar_count == 0 || self_axil_r_count == 0 ||
                self_axi_aw_count == 0 || self_axi_w_beat_count < 2 ||
                self_axi_ar_count == 0 || self_axi_r_beat_count < 2)
                $fatal(1, "VIP self-test did not observe expected isolated handshakes");
            $display("[VIP] Isolated stall checks passed");
        end
    endtask

    task automatic mem_write16(input logic [63:0] addr, input logic [15:0] data);
        begin
            @(negedge clk);
            mem_wr_en     = 1'b1;
            mem_wr_addr   = addr;
            mem_wr_data16 = data;
            @(negedge clk);
            mem_wr_en     = 1'b0;
        end
    endtask

    real q_f [0:255][0:63], k_f [0:255][0:63], v_f [0:255][0:63];
    real golden_o [0:255][0:63];

    task automatic compute_golden(input bit causal);
        real s_val, row_max, row_sum, p_val, scale;
        integer gi, gj, gk;
        begin
            scale = 1.0 / $sqrt(64.0);
            for (gi = 0; gi < 256; gi++) begin
                row_max = -1e30;
                for (gj = 0; gj < 256; gj++) begin
                    s_val = 0.0;
                    for (gk = 0; gk < 64; gk++)
                        s_val = s_val + q_f[gi][gk] * k_f[gj][gk];
                    s_val = s_val * scale;
                    if (causal && gj > gi)
                        s_val = -1e9;
                    if (s_val > row_max)
                        row_max = s_val;
                end

                row_sum = 0.0;
                for (gj = 0; gj < 256; gj++) begin
                    s_val = 0.0;
                    for (gk = 0; gk < 64; gk++)
                        s_val = s_val + q_f[gi][gk] * k_f[gj][gk];
                    s_val = s_val * scale;
                    if (causal && gj > gi)
                        s_val = -1e9;
                    p_val = $exp(s_val - row_max);
                    row_sum = row_sum + p_val;
                end

                for (gk = 0; gk < 64; gk++)
                    golden_o[gi][gk] = 0.0;

                for (gj = 0; gj < 256; gj++) begin
                    s_val = 0.0;
                    for (gk = 0; gk < 64; gk++)
                        s_val = s_val + q_f[gi][gk] * k_f[gj][gk];
                    s_val = s_val * scale;
                    if (causal && gj > gi)
                        s_val = -1e9;
                    p_val = $exp(s_val - row_max) / row_sum;
                    for (gk = 0; gk < 64; gk++)
                        golden_o[gi][gk] = golden_o[gi][gk] + p_val * v_f[gj][gk];
                end
            end
        end
    endtask

    task automatic run_register_model_tests();
        begin
            $display("[REG] Checking reset defaults and register model behavior");
            axil_read_check(REG_CTRL, 32'h0, "CTRL reset");
            axil_read_check(REG_STATUS, 32'h0, "STATUS reset");
            axil_read_check(REG_CFG, 32'h0, "CFG reset");
            axil_read_check(REG_Q_BASE_L, 32'h0, "Q_BASE_L reset");
            axil_read_check(REG_Q_BASE_H, 32'h0, "Q_BASE_H reset");
            axil_read_check(REG_K_BASE_L, 32'h0, "K_BASE_L reset");
            axil_read_check(REG_K_BASE_H, 32'h0, "K_BASE_H reset");
            axil_read_check(REG_V_BASE_L, 32'h0, "V_BASE_L reset");
            axil_read_check(REG_V_BASE_H, 32'h0, "V_BASE_H reset");
            axil_read_check(REG_O_BASE_L, 32'h0, "O_BASE_L reset");
            axil_read_check(REG_O_BASE_H, 32'h0, "O_BASE_H reset");
            axil_read_check(REG_STRIDE_BYTES, 32'd128, "STRIDE reset");
            axil_read_check(REG_NEG_LARGE, 32'hFFFF_8000, "NEG_LARGE reset");
            axil_read_check(REG_SCALE, 32'h0000_0020, "SCALE reset");
            axil_read_check(REG_CYCLES, 32'h0, "CYCLES reset");
            axil_read_check(REG_RD_BYTES, 32'h0, "RD_BYTES reset");
            axil_read_check(REG_WR_BYTES, 32'h0, "WR_BYTES reset");

            rm_write_check(REG_CFG, 32'h0000_0001, 4'hF, "CFG causal");
            flow_cov.sample(5);
            rm_write_check(REG_Q_BASE_L, 32'h1122_3344, 4'hF, "Q_BASE_L full write");
            rm_write_check(REG_Q_BASE_L, 32'h0000_AA55, 4'h3, "Q_BASE_L byte strobe");
            axil_read_check(REG_Q_BASE_L, 32'h1122_AA55, "Q_BASE_L byte strobe expected");
            rm_write_check(REG_NEG_LARGE, 32'hFFFF_9000, 4'hF, "NEG_LARGE write");
            rm_write_check(REG_SCALE, 32'h0000_0020, 4'hF, "SCALE write");
            rm_write_check(REG_SCALE, 32'h0000_0021, 4'h1, "SCALE byte0 strobe");

            axil_write(REG_CYCLES, 32'hDEAD_BEEF, 4'hF);
            axil_read_check(REG_CYCLES, 32'h0, "CYCLES RO write ignored");
            axil_write(REG_RD_BYTES, 32'hCAFE_BABE, 4'hF);
            axil_read_check(REG_RD_BYTES, 32'h0, "RD_BYTES RO write ignored");
            axil_write(REG_WR_BYTES, 32'hFEED_1234, 4'hF);
            axil_read_check(REG_WR_BYTES, 32'h0, "WR_BYTES RO write ignored");

            axil_write(REG_STATUS, 32'h0000_0002, 4'hF);
            axil_read_check(REG_STATUS, 32'h0, "STATUS W1C before done");

            axil_write(REG_CTRL, 32'h0000_0002, 4'hF);
            flow_cov.sample(0);
            repeat (4) @(posedge clk);
            axil_read_check(REG_CTRL, 32'h0, "CTRL soft_reset pulse");
            axil_read_check(REG_STATUS, 32'h0, "STATUS after soft_reset");
            $display("[REG] Register model checks passed");
        end
    endtask

    integer i, j;
    shortint q_raw, k_raw, v_raw;
    logic [31:0] status_val, cycles_val, rd_bytes_val, wr_bytes_val;
    integer timeout_cnt;
    bit busy_seen;
    real mean_err, max_err, abs_err, dut_val, gold_val;
    real row0_causal_err, row0_abs_err;
    integer err_count;
    shortint o_val;
    bit test_pass;

    initial begin
        reg_cov  = new();
        flow_cov = new();
        dma_cov  = new();
        axi_cov  = new();
        perf_cov = new();
        exp_cov = new();
        vip_stall_cov = new();
        rm_reset();
        init_selftest_signals();

        s_axil_awaddr = '0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata = '0;
        s_axil_wstrb = '0;
        s_axil_wvalid = 1'b0;
        s_axil_bready = 1'b0;
        s_axil_araddr = '0;
        s_axil_arvalid = 1'b0;
        s_axil_rready = 1'b0;
        mem_wr_en = 1'b0;
        mem_rd_en = 1'b0;
        mem_wr_addr = '0;
        mem_rd_addr = '0;
        mem_wr_data16 = '0;

        @(posedge rst_n);
        repeat (10) @(posedge clk);

        $display("============================================================");
        $display("  FlashAttention Verification Completion TB");
        $display("============================================================");

        run_exp_lut_sanity_tests();
        run_vip_stall_selftest();
        run_register_model_tests();

        $display("[DATA] Loading deterministic random Q/K/V vectors");
        for (i = 0; i < 256; i++) begin
            for (j = 0; j < 64; j++) begin
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

        $display("[GOLDEN] Computing FP32 causal golden model");
        compute_golden(1'b1);

        $display("[CFG] Programming DUT through AXI4-Lite register model");
        rm_write_check(REG_Q_BASE_L, Q_BASE[31:0], 4'hF, "Q_BASE_L");
        rm_write_check(REG_Q_BASE_H, Q_BASE[63:32], 4'hF, "Q_BASE_H");
        rm_write_check(REG_K_BASE_L, K_BASE[31:0], 4'hF, "K_BASE_L");
        rm_write_check(REG_K_BASE_H, K_BASE[63:32], 4'hF, "K_BASE_H");
        rm_write_check(REG_V_BASE_L, V_BASE[31:0], 4'hF, "V_BASE_L");
        rm_write_check(REG_V_BASE_H, V_BASE[63:32], 4'hF, "V_BASE_H");
        rm_write_check(REG_O_BASE_L, O_BASE[31:0], 4'hF, "O_BASE_L");
        rm_write_check(REG_O_BASE_H, O_BASE[63:32], 4'hF, "O_BASE_H");
        rm_write_check(REG_STRIDE_BYTES, 32'd128, 4'hF, "STRIDE_BYTES");
        rm_write_check(REG_NEG_LARGE, 32'h0000_8000, 4'hF, "NEG_LARGE runtime");
        rm_write_check(REG_SCALE, 32'h0000_0020, 4'hF, "SCALE runtime");
        rm_write_check(REG_CFG, 32'h0000_0001, 4'hF, "CFG causal runtime");
        flow_cov.sample(5);

        $display("[RUN] Starting DUT");
        axil_write(REG_CTRL, 32'h0000_0001, 4'hF);
        flow_cov.sample(1);

        timeout_cnt = 0;
        status_val = 32'h0;
        busy_seen = 1'b0;
        while (!status_val[STATUS_DONE] && timeout_cnt < 1000000) begin
            repeat (100) @(posedge clk);
            axil_read(REG_STATUS, status_val);
            timeout_cnt = timeout_cnt + 100;
            if (status_val[STATUS_BUSY] && !busy_seen) begin
                busy_seen = 1'b1;
                flow_cov.sample(2);
            end
            if (timeout_cnt % 50000 == 0) begin
                $display("  ... %0d cycles, STATUS=0x%08h", timeout_cnt, status_val);
            end
        end

        if (!status_val[STATUS_DONE])
            $fatal(1, "Timed out waiting for STATUS.DONE, STATUS=0x%08h", status_val);
        if (!busy_seen)
            $fatal(1, "STATUS.BUSY was never observed during execution");
        flow_cov.sample(3);

        axil_read(REG_CYCLES, cycles_val);
        axil_read(REG_RD_BYTES, rd_bytes_val);
        axil_read(REG_WR_BYTES, wr_bytes_val);

        $display("[CHECK] Reading O memory and comparing against golden");
        mean_err = 0.0;
        max_err = 0.0;
        err_count = 0;
        row0_causal_err = 0.0;
        for (i = 0; i < 256; i++) begin
            for (j = 0; j < 64; j++) begin
                mem_rd_en = 1'b1;
                mem_rd_addr = O_BASE + (i*64+j)*2;
                @(posedge clk);
                o_val = mem_rd_data16;
                mem_rd_en = 1'b0;
                @(posedge clk);

                dut_val = $itor(o_val) / 256.0;
                gold_val = golden_o[i][j];
                abs_err = dut_val - gold_val;
                if (abs_err < 0.0)
                    abs_err = -abs_err;
                mean_err = mean_err + abs_err;
                if (abs_err > max_err)
                    max_err = abs_err;
                if (i == 0) begin
                    row0_abs_err = dut_val - v_f[0][j];
                    if (row0_abs_err < 0.0)
                        row0_abs_err = -row0_abs_err;
                    if (row0_abs_err > row0_causal_err)
                        row0_causal_err = row0_abs_err;
                end
                err_count++;
            end
        end
        mean_err = mean_err / $itor(err_count);

        test_pass = 1'b1;
        if (cycles_val >= 32'd300000) begin
            $display("  FAIL cycles=%0d >= 300000", cycles_val);
            test_pass = 1'b0;
        end
        if (mean_err > MEAN_LIMIT) begin
            $display("  FAIL mean_abs_error=%.6f > %.6f", mean_err, MEAN_LIMIT);
            test_pass = 1'b0;
        end
        if (max_err > MAX_LIMIT) begin
            $display("  FAIL max_abs_error=%.6f > %.6f", max_err, MAX_LIMIT);
            test_pass = 1'b0;
        end
        if (row0_causal_err > CAUSAL_ROW0_LIMIT) begin
            $display("  FAIL row0_causal=%.6f > %.6f", row0_causal_err, CAUSAL_ROW0_LIMIT);
            test_pass = 1'b0;
        end

        if (rd_bytes_val != EXPECT_RD_BYTES[31:0])
            $fatal(1, "RD_BYTES register mismatch actual=%0d expected=%0d", rd_bytes_val, EXPECT_RD_BYTES);
        if (wr_bytes_val != EXPECT_WR_BYTES[31:0])
            $fatal(1, "WR_BYTES register mismatch actual=%0d expected=%0d", wr_bytes_val, EXPECT_WR_BYTES);

        if (dma_q_read_bytes != EXPECT_Q_READ_BYTES)
            $fatal(1, "Q read byte mismatch actual=%0d expected=%0d", dma_q_read_bytes, EXPECT_Q_READ_BYTES);
        if (dma_k_read_bytes != EXPECT_K_READ_BYTES)
            $fatal(1, "K read byte mismatch actual=%0d expected=%0d", dma_k_read_bytes, EXPECT_K_READ_BYTES);
        if (dma_v_read_bytes != EXPECT_V_READ_BYTES)
            $fatal(1, "V read byte mismatch actual=%0d expected=%0d", dma_v_read_bytes, EXPECT_V_READ_BYTES);
        if (dma_o_write_bytes != EXPECT_O_WR_BYTES)
            $fatal(1, "O write byte mismatch actual=%0d expected=%0d", dma_o_write_bytes, EXPECT_O_WR_BYTES);
        if (dma_total_read_bytes != EXPECT_RD_BYTES)
            $fatal(1, "DMA total read byte mismatch actual=%0d expected=%0d", dma_total_read_bytes, EXPECT_RD_BYTES);
        if (dma_total_write_bytes != EXPECT_WR_BYTES)
            $fatal(1, "DMA total write byte mismatch actual=%0d expected=%0d", dma_total_write_bytes, EXPECT_WR_BYTES);
        if (axi_read_bytes != EXPECT_RD_BYTES)
            $fatal(1, "AXI VIP read byte mismatch actual=%0d expected=%0d", axi_read_bytes, EXPECT_RD_BYTES);
        if (axi_write_bytes != EXPECT_WR_BYTES)
            $fatal(1, "AXI VIP write byte mismatch actual=%0d expected=%0d", axi_write_bytes, EXPECT_WR_BYTES);

        perf_cov.sample(cycles_val,
            (mean_err <= MEAN_LIMIT) ? 0 : 1,
            (max_err <= MAX_LIMIT) ? 0 : 1,
            (row0_causal_err <= CAUSAL_ROW0_LIMIT) ? 0 : 1);

        axil_write(REG_STATUS, 32'h0000_0002, 4'hF);
        flow_cov.sample(4);
        axil_read(REG_STATUS, status_val);
        if (status_val[STATUS_DONE])
            $fatal(1, "STATUS.DONE did not clear after W1C write");

        $display("============================================================");
        $display("  VERIFICATION COMPLETION SUMMARY");
        $display("  Cycles:             %0d", cycles_val);
        $display("  RD_BYTES:           %0d", rd_bytes_val);
        $display("  WR_BYTES:           %0d", wr_bytes_val);
        $display("  DMA Q/K/V read:     %0d / %0d / %0d", dma_q_read_bytes, dma_k_read_bytes, dma_v_read_bytes);
        $display("  DMA O write:        %0d", dma_o_write_bytes);
        $display("  AXI AR/AW bursts:   %0d / %0d", axi_ar_count, axi_aw_count);
        $display("  AXI R/W beats:      %0d / %0d", axi_r_beat_count, axi_w_beat_count);
        $display("  AXIL R/W accesses:  %0d / %0d", axil_ar_count, axil_aw_count);
        $display("  mean_abs_error:     %.6f", mean_err);
        $display("  max_abs_error:      %.6f", max_err);
        $display("  row0_causal:        %.6f", row0_causal_err);
        $display("  Functional coverage reg/flow/dma/axi/perf/exp/vip: %.2f %.2f %.2f %.2f %.2f %.2f %.2f",
            reg_cov.get_inst_coverage(), flow_cov.get_inst_coverage(),
            dma_cov.get_inst_coverage(), axi_cov.get_inst_coverage(),
            perf_cov.get_inst_coverage(), exp_cov.get_inst_coverage(),
            vip_stall_cov.get_inst_coverage());
        $display("============================================================");

        if (!test_pass)
            $fatal(1, "FlashAttention enhanced verification failed");

        $display(">>> VERIFICATION COMPLETION TESTS PASSED <<<");
        $finish;
    end

    initial begin
        #50_000_000;
        $fatal(1, "Verification completion TB timeout");
    end

endmodule
