// ============================================================
// FlashAttention Bonus Top Level
// Integrates ALL bonus features:
//   1. BF16/FP16 support (data_fmt register)
//   2. Multi-head (NUM_HEADS loop)
//   3. Longer sequences (runtime SEQ_LEN)
//   4. Padding mask
//   5. Other fixed-point formats (Q6.10, Q4.12)
//   6. Dropout (training mode)
//   7. INT8/FP8 (block quantization)
//   8. AXI4-Stream interface
//   9. DMA/Task queue
// ============================================================
`include "fa_params_bonus.svh"

module flash_attention_bonus_top (
    input  logic                    clk,
    input  logic                    rst_n,

    // --- AXI4-Lite Slave Interface (Control) ---
    input  logic [AXIL_ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  logic                        s_axil_awvalid,
    output logic                        s_axil_awready,
    input  logic [AXIL_DATA_WIDTH-1:0]  s_axil_wdata,
    input  logic [AXIL_DATA_WIDTH/8-1:0] s_axil_wstrb,
    input  logic                        s_axil_wvalid,
    output logic                        s_axil_wready,
    output logic [1:0]                  s_axil_bresp,
    output logic                        s_axil_bvalid,
    input  logic                        s_axil_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0]  s_axil_araddr,
    input  logic                        s_axil_arvalid,
    output logic                        s_axil_arready,
    output logic [AXIL_DATA_WIDTH-1:0]  s_axil_rdata,
    output logic [1:0]                  s_axil_rresp,
    output logic                        s_axil_rvalid,
    input  logic                        s_axil_rready,

    // --- AXI4 Master Interface (Data/DMA) ---
    output logic [AXI_ID_WIDTH-1:0]     m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_axi_awaddr,
    output logic [7:0]                  m_axi_awlen,
    output logic [2:0]                  m_axi_awsize,
    output logic [1:0]                  m_axi_awburst,
    output logic                        m_axi_awvalid,
    input  logic                        m_axi_awready,
    output logic [AXI_DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [AXI_STRB_WIDTH-1:0]   m_axi_wstrb,
    output logic                        m_axi_wlast,
    output logic                        m_axi_wvalid,
    input  logic                        m_axi_wready,
    input  logic [AXI_ID_WIDTH-1:0]     m_axi_bid,
    input  logic [1:0]                  m_axi_bresp,
    input  logic                        m_axi_bvalid,
    output logic                        m_axi_bready,
    output logic [AXI_ID_WIDTH-1:0]     m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst,
    output logic                        m_axi_arvalid,
    input  logic                        m_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]     m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic [1:0]                  m_axi_rresp,
    input  logic                        m_axi_rlast,
    input  logic                        m_axi_rvalid,
    output logic                        m_axi_rready,

    // --- AXI4-Stream Slave (Q/K/V input) — Bonus 8 ---
    input  logic [AXI_DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic                        s_axis_tlast,
    input  logic [1:0]                 s_axis_tid,

    // --- AXI4-Stream Master (O output) — Bonus 8 ---
    output logic [AXI_DATA_WIDTH-1:0]  m_axis_tdata,
    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic                        m_axis_tlast,

    // Interrupt
    output logic                        irq
);

    // ========== Register File Signals ==========
    logic        reg_start, reg_soft_reset, reg_irq_en;
    logic        reg_causal_en, reg_padding_en, reg_dropout_en, reg_stream_mode;
    logic [63:0] reg_q_base, reg_k_base, reg_v_base, reg_o_base;
    logic [31:0] reg_stride_bytes, reg_head_stride;
    logic signed [15:0] reg_neg_large, reg_scale;
    logic [15:0] reg_seq_len, reg_pad_len;
    logic [7:0]  reg_num_heads, reg_drop_prob;
    logic [31:0] reg_dropout_seed;
    logic [2:0]  reg_data_fmt;
    logic        reg_task_queue_en;
    logic        status_busy, status_done, status_error, status_queue_full;
    logic [31:0] cycle_count;
    logic        done_clear;

    axi4_lite_slave_bonus #(.ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH))
    u_axil (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .reg_start(reg_start), .reg_soft_reset(reg_soft_reset), .reg_irq_en(reg_irq_en),
        .reg_causal_en(reg_causal_en), .reg_padding_en(reg_padding_en),
        .reg_dropout_en(reg_dropout_en), .reg_stream_mode(reg_stream_mode),
        .reg_q_base(reg_q_base), .reg_k_base(reg_k_base),
        .reg_v_base(reg_v_base), .reg_o_base(reg_o_base),
        .reg_stride_bytes(reg_stride_bytes),
        .reg_neg_large(reg_neg_large), .reg_scale(reg_scale),
        .reg_seq_len(reg_seq_len), .reg_num_heads(reg_num_heads),
        .reg_pad_len(reg_pad_len),
        .reg_drop_prob(reg_drop_prob), .reg_dropout_seed(reg_dropout_seed),
        .reg_data_fmt(reg_data_fmt), .reg_head_stride(reg_head_stride),
        .reg_task_queue_en(reg_task_queue_en),
        .status_busy(status_busy), .status_done(status_done),
        .status_error(status_error), .status_queue_full(status_queue_full),
        .cycle_count(cycle_count), .done_clear(done_clear), .irq(irq)
    );

    // ========== Task Queue (Bonus 9) ==========
    logic tq_push_valid, tq_push_ready;
    logic tq_pop_req, tq_pop_valid;
    logic [AXI_ADDR_WIDTH-1:0] tq_q_base, tq_k_base, tq_v_base, tq_o_base;
    logic [31:0] tq_config;
    logic tq_empty, tq_full;
    logic [$clog2(TASK_QUEUE_DEPTH):0] tq_count;

    task_queue #(.QUEUE_DEPTH(TASK_QUEUE_DEPTH), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH))
    u_tq (
        .clk(clk), .rst_n(rst_n),
        .push_valid(tq_push_valid), .push_ready(tq_push_ready),
        .push_q_base(reg_q_base), .push_k_base(reg_k_base),
        .push_v_base(reg_v_base), .push_o_base(reg_o_base),
        .push_config({2'b0, reg_causal_en, reg_padding_en, reg_dropout_en, reg_data_fmt,
                      reg_pad_len[7:0], reg_seq_len[7:0], reg_num_heads}),
        .pop_req(tq_pop_req), .pop_valid(tq_pop_valid),
        .pop_q_base(tq_q_base), .pop_k_base(tq_k_base),
        .pop_v_base(tq_v_base), .pop_o_base(tq_o_base),
        .pop_config(tq_config),
        .empty(tq_empty), .full(tq_full), .count(tq_count)
    );

    assign tq_push_valid = reg_task_queue_en && reg_start;
    assign status_queue_full = tq_full;

    // ========== Tile Controller (Enhanced) ==========
    logic       tc_dma_rd_req, tc_dma_rd_done;
    logic [AXI_ADDR_WIDTH-1:0] tc_dma_rd_addr;
    logic [15:0] tc_dma_rd_len;
    logic [1:0]  tc_dma_rd_target;
    logic       tc_dma_wr_req, tc_dma_wr_done;
    logic [AXI_ADDR_WIDTH-1:0] tc_dma_wr_addr;
    logic [15:0] tc_dma_wr_len;
    logic       tc_compute_start, tc_compute_first_kv, tc_compute_last_kv, tc_compute_done;
    logic [15:0] tc_q_tile_idx, tc_kv_tile_idx;
    logic [7:0]  tc_head_idx;
    logic       tc_kv_buf_sel;
    logic       tc_all_done, tc_busy;
    logic       tc_o_wb_start, tc_o_wb_done;

    tile_controller_bonus #(
        .MAX_SEQ_LEN(MAX_SEQ_LEN), .HEAD_DIM(HEAD_DIM),
        .TILE_BR(TILE_BR), .TILE_BC(TILE_BC),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_tile_ctrl (
        .clk(clk), .rst_n(rst_n),
        .start(reg_start), .all_done(tc_all_done), .busy(tc_busy),
        .cfg_seq_len(reg_seq_len), .cfg_num_heads(reg_num_heads),
        .q_base_addr(reg_q_base), .k_base_addr(reg_k_base),
        .v_base_addr(reg_v_base), .o_base_addr(reg_o_base),
        .stride_bytes(reg_stride_bytes),
        .head_stride_bytes(reg_head_stride),
        .dma_rd_req(tc_dma_rd_req), .dma_rd_addr(tc_dma_rd_addr),
        .dma_rd_len_bytes(tc_dma_rd_len), .dma_rd_target(tc_dma_rd_target),
        .dma_rd_done(tc_dma_rd_done),
        .dma_wr_req(tc_dma_wr_req), .dma_wr_addr(tc_dma_wr_addr),
        .dma_wr_len_bytes(tc_dma_wr_len), .dma_wr_done(tc_dma_wr_done),
        .compute_start(tc_compute_start), .compute_first_kv(tc_compute_first_kv),
        .compute_last_kv(tc_compute_last_kv), .compute_done(tc_compute_done),
        .q_tile_idx(tc_q_tile_idx), .kv_tile_idx(tc_kv_tile_idx),
        .head_idx(tc_head_idx),
        .kv_buf_sel(tc_kv_buf_sel),
        .o_writeback_start(tc_o_wb_start), .o_writeback_done(tc_o_wb_done),
        .task_queue_mode(reg_task_queue_en), .task_pop_valid(tq_pop_valid),
        .task_pop_req(tq_pop_req),
        .tq_q_base(tq_q_base), .tq_k_base(tq_k_base),
        .tq_v_base(tq_v_base), .tq_o_base(tq_o_base),
        .tq_config(tq_config)
    );

    // ========== Buffer System (reuse baseline) ==========
    logic       buf_q_wr_en, buf_k_wr_en, buf_v_wr_en;
    logic [$clog2(TILE_BR*HEAD_DIM)-1:0] buf_q_wr_addr;
    logic [$clog2(TILE_BC*HEAD_DIM)-1:0] buf_k_wr_addr, buf_v_wr_addr;
    logic [AXI_DATA_WIDTH-1:0] buf_q_wr_data, buf_k_wr_data, buf_v_wr_data;
    logic       buf_o_rd_en;
    logic [$clog2(TILE_BR)-1:0] buf_o_rd_row;
    logic [$clog2(HEAD_DIM/(AXI_DATA_WIDTH/DATA_WIDTH))-1:0] buf_o_rd_col_grp;
    logic [AXI_DATA_WIDTH-1:0] buf_o_rd_data;

    // DMA buffer write signals
    logic       dma_q_wr_en, dma_k_wr_en, dma_v_wr_en;
    logic [$clog2(TILE_BR*HEAD_DIM)-1:0] dma_q_wr_addr;
    logic [$clog2(TILE_BC*HEAD_DIM)-1:0] dma_k_wr_addr, dma_v_wr_addr;
    logic [AXI_DATA_WIDTH-1:0] dma_q_wr_data, dma_k_wr_data, dma_v_wr_data;
    logic       dma_o_rd_en;
    logic [$clog2(TILE_BR)-1:0] dma_o_rd_row;
    logic [$clog2(HEAD_DIM/(AXI_DATA_WIDTH/DATA_WIDTH))-1:0] dma_o_rd_col_grp;

    // Stream buffer write signals
    logic       strm_q_wr_en, strm_k_wr_en, strm_v_wr_en;
    logic [$clog2(TILE_BR*HEAD_DIM)-1:0] strm_q_wr_addr;
    logic [$clog2(TILE_BC*HEAD_DIM)-1:0] strm_k_wr_addr, strm_v_wr_addr;
    logic [AXI_DATA_WIDTH-1:0] strm_q_wr_data, strm_k_wr_data, strm_v_wr_data;
    logic       strm_o_rd_en;
    logic [$clog2(TILE_BR)-1:0] strm_o_rd_row;
    logic [$clog2(HEAD_DIM/(AXI_DATA_WIDTH/DATA_WIDTH))-1:0] strm_o_rd_col_grp;

    // MUX: DMA vs Stream
    assign buf_q_wr_en   = reg_stream_mode ? strm_q_wr_en   : dma_q_wr_en;
    assign buf_q_wr_addr = reg_stream_mode ? strm_q_wr_addr : dma_q_wr_addr;
    assign buf_q_wr_data = reg_stream_mode ? strm_q_wr_data : dma_q_wr_data;
    assign buf_k_wr_en   = reg_stream_mode ? strm_k_wr_en   : dma_k_wr_en;
    assign buf_k_wr_addr = reg_stream_mode ? strm_k_wr_addr : dma_k_wr_addr;
    assign buf_k_wr_data = reg_stream_mode ? strm_k_wr_data : dma_k_wr_data;
    assign buf_v_wr_en   = reg_stream_mode ? strm_v_wr_en   : dma_v_wr_en;
    assign buf_v_wr_addr = reg_stream_mode ? strm_v_wr_addr : dma_v_wr_addr;
    assign buf_v_wr_data = reg_stream_mode ? strm_v_wr_data : dma_v_wr_data;
    assign buf_o_rd_en      = reg_stream_mode ? strm_o_rd_en      : dma_o_rd_en;
    assign buf_o_rd_row     = reg_stream_mode ? strm_o_rd_row     : dma_o_rd_row;
    assign buf_o_rd_col_grp = reg_stream_mode ? strm_o_rd_col_grp : dma_o_rd_col_grp;

    dma_engine #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .TILE_BR(TILE_BR), .TILE_BC(TILE_BC), .HEAD_DIM(HEAD_DIM), .DATA_WIDTH(DATA_WIDTH)
    ) u_dma (
        .clk(clk), .rst_n(rst_n),
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
        .dma_rd_req(tc_dma_rd_req), .dma_rd_addr(tc_dma_rd_addr),
        .dma_rd_len_bytes(tc_dma_rd_len), .dma_rd_target(tc_dma_rd_target),
        .dma_rd_done(tc_dma_rd_done),
        .dma_wr_req(tc_dma_wr_req), .dma_wr_addr(tc_dma_wr_addr),
        .dma_wr_len_bytes(tc_dma_wr_len), .dma_wr_done(tc_dma_wr_done),
        .buf_q_wr_en(dma_q_wr_en), .buf_q_wr_addr(dma_q_wr_addr), .buf_q_wr_data(dma_q_wr_data),
        .buf_k_wr_en(dma_k_wr_en), .buf_k_wr_addr(dma_k_wr_addr), .buf_k_wr_data(dma_k_wr_data),
        .buf_v_wr_en(dma_v_wr_en), .buf_v_wr_addr(dma_v_wr_addr), .buf_v_wr_data(dma_v_wr_data),
        .buf_o_rd_en(dma_o_rd_en), .buf_o_rd_row(dma_o_rd_row),
        .buf_o_rd_col_grp(dma_o_rd_col_grp), .buf_o_rd_data(buf_o_rd_data),
        .kv_buf_sel(tc_kv_buf_sel)
    );

    // ========== AXI4-Stream Interface (Bonus 8) ==========
    logic strm_q_done, strm_kv_done, strm_o_done;

    axi4_stream_if #(
        .DATA_WIDTH(AXI_DATA_WIDTH), .TILE_BR(TILE_BR), .TILE_BC(TILE_BC),
        .HEAD_DIM(HEAD_DIM), .ELEM_WIDTH(DATA_WIDTH), .PAR_MACS(PAR_MACS)
    ) u_stream (
        .clk(clk), .rst_n(rst_n),
        .stream_mode(reg_stream_mode),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .s_axis_tid(s_axis_tid),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .buf_q_wr_en(strm_q_wr_en), .buf_q_wr_addr(strm_q_wr_addr), .buf_q_wr_data(strm_q_wr_data),
        .buf_k_wr_en(strm_k_wr_en), .buf_k_wr_addr(strm_k_wr_addr), .buf_k_wr_data(strm_k_wr_data),
        .buf_v_wr_en(strm_v_wr_en), .buf_v_wr_addr(strm_v_wr_addr), .buf_v_wr_data(strm_v_wr_data),
        .buf_o_rd_data(buf_o_rd_data),
        .buf_o_rd_en(strm_o_rd_en), .buf_o_rd_row(strm_o_rd_row),
        .buf_o_rd_col_grp(strm_o_rd_col_grp),
        .stream_q_done(strm_q_done), .stream_kv_done(strm_kv_done),
        .stream_o_start(tc_o_wb_start), .stream_o_done(strm_o_done)
    );

    // Compute core buffer read signals
    logic       comp_q_rd_en, comp_k_rd_en, comp_v_rd_en;
    logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] comp_q_step, comp_k_step, comp_v_step;
    logic signed [DATA_WIDTH-1:0] comp_q_data [TILE_BR-1:0][PAR_MACS-1:0];
    logic signed [DATA_WIDTH-1:0] comp_k_data [TILE_BC-1:0][PAR_MACS-1:0];
    logic signed [DATA_WIDTH-1:0] comp_v_data [TILE_BC-1:0][PAR_MACS-1:0];
    logic signed [DATA_WIDTH-1:0] comp_o_tile [TILE_BR-1:0][HEAD_DIM-1:0];
    logic       comp_o_valid;

    buffer_system #(
        .TILE_BR(TILE_BR), .TILE_BC(TILE_BC), .HEAD_DIM(HEAD_DIM),
        .DATA_WIDTH(DATA_WIDTH), .PAR_MACS(PAR_MACS), .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_buffers (
        .clk(clk), .rst_n(rst_n),
        .q_wr_en(buf_q_wr_en), .q_wr_addr(buf_q_wr_addr), .q_wr_data(buf_q_wr_data),
        .k_wr_en(buf_k_wr_en), .k_wr_addr(buf_k_wr_addr), .k_wr_data(buf_k_wr_data),
        .k_buf_sel(tc_kv_buf_sel),
        .v_wr_en(buf_v_wr_en), .v_wr_addr(buf_v_wr_addr), .v_wr_data(buf_v_wr_data),
        .v_buf_sel(tc_kv_buf_sel),
        .q_rd_en(comp_q_rd_en), .q_rd_step(comp_q_step), .q_rd_data(comp_q_data),
        .k_rd_en(comp_k_rd_en), .k_rd_step(comp_k_step),
        .k_rd_buf_sel(~tc_kv_buf_sel), .k_rd_data(comp_k_data),
        .v_rd_en(comp_v_rd_en), .v_rd_step(comp_v_step),
        .v_rd_buf_sel(~tc_kv_buf_sel), .v_rd_data(comp_v_data),
        .o_wr_en(comp_o_valid), .o_wr_data(comp_o_tile),
        .o_rd_en(buf_o_rd_en), .o_rd_row(buf_o_rd_row),
        .o_rd_col_grp(buf_o_rd_col_grp), .o_rd_data(buf_o_rd_data)
    );

    // ========== Compute Core (Enhanced) ==========
    compute_core_bonus #(
        .MAX_SEQ_LEN(MAX_SEQ_LEN), .HEAD_DIM(HEAD_DIM),
        .TILE_BR(TILE_BR), .TILE_BC(TILE_BC),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
        .EXP_WIDTH(24), .FRAC_BITS(16), .PAR_MACS(PAR_MACS)
    ) u_compute (
        .clk(clk), .rst_n(rst_n),
        .start(tc_compute_start), .first_kv_tile(tc_compute_first_kv),
        .last_kv_tile(tc_compute_last_kv),
        .done(tc_compute_done), .busy(),
        .q_tile_idx(tc_q_tile_idx), .kv_tile_idx(tc_kv_tile_idx),
        .causal_en(reg_causal_en), .padding_en(reg_padding_en),
        .dropout_en(reg_dropout_en),
        .valid_len(reg_pad_len), .scale(reg_scale), .neg_large(reg_neg_large),
        .drop_prob(reg_drop_prob), .dropout_seed(reg_dropout_seed),
        .data_fmt(reg_data_fmt),
        .q_rd_en(comp_q_rd_en), .q_rd_step(comp_q_step), .q_data(comp_q_data),
        .k_rd_en(comp_k_rd_en), .k_rd_step(comp_k_step), .k_data(comp_k_data),
        .v_rd_en(comp_v_rd_en), .v_rd_step(comp_v_step), .v_data(comp_v_data),
        .o_tile(comp_o_tile), .o_valid(comp_o_valid)
    );

    // ========== Cycle Counter ==========
    logic [31:0] cycle_cnt;
    assign cycle_count = cycle_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_cnt <= '0;
        else if (reg_start)
            cycle_cnt <= '0;
        else if (tc_busy)
            cycle_cnt <= cycle_cnt + 1;
    end

    // ========== Status ==========
    assign status_busy  = tc_busy;
    assign status_done  = tc_all_done;
    assign status_error = 1'b0;

    assign tc_o_wb_done = tc_dma_wr_done;

endmodule
