// ============================================================
// FlashAttention Accelerator — Top Level
// Integrates: AXI4-Lite Slave, DMA Engine, Tile Controller,
//             Buffer System, Compute Core
// ============================================================
`include "fa_params.svh"

module flash_attention_top (
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

    // --- AXI4 Master Interface (Data) ---
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

    // Interrupt
    output logic                        irq
);

    // ========== Register File Signals ==========
    logic        reg_start, reg_soft_reset, reg_irq_en, reg_causal_en;
    logic [63:0] reg_q_base, reg_k_base, reg_v_base, reg_o_base;
    logic [31:0] reg_stride_bytes;
    logic signed [15:0] reg_neg_large, reg_scale;
    logic        status_busy, status_done, status_error;
    logic [31:0] cycle_count;
    logic        done_clear;

    axi4_lite_slave #(.ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH))
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
        .reg_causal_en(reg_causal_en),
        .reg_q_base(reg_q_base), .reg_k_base(reg_k_base),
        .reg_v_base(reg_v_base), .reg_o_base(reg_o_base),
        .reg_stride_bytes(reg_stride_bytes),
        .reg_neg_large(reg_neg_large), .reg_scale(reg_scale),
        .status_busy(status_busy), .status_done(status_done), .status_error(status_error),
        .cycle_count(cycle_count), .done_clear(done_clear), .irq(irq)
    );

    // ========== DMA / Tile Controller / Buffer Signals ==========
    logic       tc_dma_rd_req, tc_dma_rd_done;
    logic [AXI_ADDR_WIDTH-1:0] tc_dma_rd_addr;
    logic [15:0] tc_dma_rd_len;
    logic [1:0]  tc_dma_rd_target;
    logic       tc_dma_wr_req, tc_dma_wr_done;
    logic [AXI_ADDR_WIDTH-1:0] tc_dma_wr_addr;
    logic [15:0] tc_dma_wr_len;
    logic       tc_compute_start, tc_compute_first_kv, tc_compute_last_kv, tc_compute_done;
    logic [$clog2(SEQ_LEN)-1:0] tc_q_tile_idx, tc_kv_tile_idx;
    logic       tc_kv_buf_sel;
    logic       tc_all_done, tc_busy;
    logic       tc_o_wb_start, tc_o_wb_done;

    tile_controller #(
        .SEQ_LEN(SEQ_LEN), .HEAD_DIM(HEAD_DIM), .TILE_BR(TILE_BR), .TILE_BC(TILE_BC),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_tile_ctrl (
        .clk(clk), .rst_n(rst_n),
        .start(reg_start), .all_done(tc_all_done), .busy(tc_busy),
        .q_base_addr(reg_q_base), .k_base_addr(reg_k_base),
        .v_base_addr(reg_v_base), .o_base_addr(reg_o_base),
        .stride_bytes(reg_stride_bytes),
        .dma_rd_req(tc_dma_rd_req), .dma_rd_addr(tc_dma_rd_addr),
        .dma_rd_len_bytes(tc_dma_rd_len), .dma_rd_target(tc_dma_rd_target),
        .dma_rd_done(tc_dma_rd_done),
        .dma_wr_req(tc_dma_wr_req), .dma_wr_addr(tc_dma_wr_addr),
        .dma_wr_len_bytes(tc_dma_wr_len), .dma_wr_done(tc_dma_wr_done),
        .compute_start(tc_compute_start), .compute_first_kv(tc_compute_first_kv),
        .compute_last_kv(tc_compute_last_kv), .compute_done(tc_compute_done),
        .q_tile_idx(tc_q_tile_idx), .kv_tile_idx(tc_kv_tile_idx),
        .kv_buf_sel(tc_kv_buf_sel),
        .o_writeback_start(tc_o_wb_start), .o_writeback_done(tc_o_wb_done)
    );

    // Buffer wires
    logic       buf_q_wr_en, buf_k_wr_en, buf_v_wr_en;
    logic [$clog2(TILE_BR*HEAD_DIM)-1:0] buf_q_wr_addr;
    logic [$clog2(TILE_BC*HEAD_DIM)-1:0] buf_k_wr_addr, buf_v_wr_addr;
    logic [AXI_DATA_WIDTH-1:0] buf_q_wr_data, buf_k_wr_data, buf_v_wr_data;
    logic       buf_o_rd_en;
    logic [$clog2(TILE_BR)-1:0] buf_o_rd_row;
    logic [$clog2(HEAD_DIM/(AXI_DATA_WIDTH/DATA_WIDTH))-1:0] buf_o_rd_col_grp;
    logic [AXI_DATA_WIDTH-1:0] buf_o_rd_data;

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
        .buf_q_wr_en(buf_q_wr_en), .buf_q_wr_addr(buf_q_wr_addr), .buf_q_wr_data(buf_q_wr_data),
        .buf_k_wr_en(buf_k_wr_en), .buf_k_wr_addr(buf_k_wr_addr), .buf_k_wr_data(buf_k_wr_data),
        .buf_v_wr_en(buf_v_wr_en), .buf_v_wr_addr(buf_v_wr_addr), .buf_v_wr_data(buf_v_wr_data),
        .buf_o_rd_en(buf_o_rd_en), .buf_o_rd_row(buf_o_rd_row),
        .buf_o_rd_col_grp(buf_o_rd_col_grp), .buf_o_rd_data(buf_o_rd_data),
        .kv_buf_sel(tc_kv_buf_sel)
    );

    // Compute core buffer read signals
    logic       comp_q_rd_en, comp_k_rd_en, comp_v_rd_en;
    logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] comp_q_step, comp_k_step, comp_v_step;
    logic signed [DATA_WIDTH-1:0] comp_q_data [TILE_BR-1:0][PAR_MACS-1:0];
    logic signed [DATA_WIDTH-1:0] comp_k_data [TILE_BC-1:0][PAR_MACS-1:0];
    logic signed [DATA_WIDTH-1:0] comp_v_data [TILE_BC-1:0][PAR_MACS-1:0];
    logic signed [DATA_WIDTH-1:0] comp_o_tile [TILE_BR-1:0][HEAD_DIM-1:0];
    logic       comp_o_valid;

    localparam PAR_MACS = 8;

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

    compute_core #(
        .SEQ_LEN(SEQ_LEN), .HEAD_DIM(HEAD_DIM), .TILE_BR(TILE_BR), .TILE_BC(TILE_BC),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
        .EXP_WIDTH(24), .FRAC_BITS(16), .PAR_MACS(PAR_MACS)
    ) u_compute (
        .clk(clk), .rst_n(rst_n),
        .start(tc_compute_start), .first_kv_tile(tc_compute_first_kv),
        .last_kv_tile(tc_compute_last_kv),
        .done(tc_compute_done), .busy(),
        .q_tile_idx(tc_q_tile_idx), .kv_tile_idx(tc_kv_tile_idx),
        .causal_en(reg_causal_en), .scale(reg_scale), .neg_large(reg_neg_large),
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
    assign status_error = 1'b0;  // placeholder

    // O writeback done
    assign tc_o_wb_done = tc_dma_wr_done;

endmodule
