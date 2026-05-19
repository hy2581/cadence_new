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
    logic        reg_start, reg_soft_reset, reg_causal_en;
    logic [63:0] reg_q_base, reg_k_base, reg_v_base, reg_o_base;
    logic [31:0] reg_stride_bytes;
    logic signed [15:0] reg_neg_large, reg_scale;
    logic [31:0] reg_valid_len, reg_head_count, reg_head_stride_bytes;
    logic [2:0]  reg_format_mode;
    logic        reg_dropout_en;
    logic [7:0]  reg_dropout_rate;
    logic [31:0] reg_dropout_seed;
    logic        status_busy, status_done, status_error;
    logic [31:0] cycle_count;
    logic [31:0] rd_bytes_count, wr_bytes_count;
    logic        datapath_rst_n;
    logic [7:0]  queue_pending_count, queue_completed_count;
    logic        queue_overflow;

    assign datapath_rst_n = rst_n & ~reg_soft_reset;

    axi4_lite_slave #(
        .ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .DATA_WIDTH(AXIL_DATA_WIDTH),
        .DEFAULT_VALID_LEN(DEFAULT_VALID_LEN),
        .DEFAULT_HEAD_COUNT(DEFAULT_HEAD_COUNT),
        .DEFAULT_HEAD_STRIDE_BYTES(DEFAULT_HEAD_STRIDE_BYTES)
    )
    u_axil (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .reg_start(reg_start), .reg_soft_reset(reg_soft_reset),
        .reg_causal_en(reg_causal_en),
        .reg_q_base(reg_q_base), .reg_k_base(reg_k_base),
        .reg_v_base(reg_v_base), .reg_o_base(reg_o_base),
        .reg_stride_bytes(reg_stride_bytes),
        .reg_valid_len(reg_valid_len),
        .reg_head_count(reg_head_count),
        .reg_head_stride_bytes(reg_head_stride_bytes),
        .reg_format_mode(reg_format_mode),
        .reg_dropout_en(reg_dropout_en),
        .reg_dropout_rate(reg_dropout_rate),
        .reg_dropout_seed(reg_dropout_seed),
        .reg_neg_large(reg_neg_large), .reg_scale(reg_scale),
        .status_busy(status_busy), .status_done(status_done), .status_error(status_error),
        .cycle_count(cycle_count),
        .rd_bytes(rd_bytes_count), .wr_bytes(wr_bytes_count),
        .queue_pending_count(queue_pending_count),
        .queue_completed_count(queue_completed_count),
        .queue_overflow(queue_overflow),
        .irq(irq)
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
    logic [$clog2(SEQ_LEN/TILE_BR)-1:0] tc_q_tile_idx;
    logic [$clog2(SEQ_LEN/TILE_BC)-1:0] tc_kv_tile_idx;
    logic       tc_kv_buf_sel;
    logic       tc_all_done, tc_busy;
    logic       tc_dma_rd_req_q, tc_dma_wr_req_q;

    localparam JOB_QUEUE_DEPTH = 2;
    localparam VALID_LEN_W = $clog2(SEQ_LEN) + 1;

    typedef struct packed {
        logic [63:0] q_base;
        logic [63:0] k_base;
        logic [63:0] v_base;
        logic [63:0] o_base;
        logic [31:0] stride_bytes;
        logic [31:0] valid_len;
        logic [7:0]  head_count;
        logic [31:0] head_stride_bytes;
        logic        causal_en;
        logic [2:0]  format_mode;
        logic        dropout_en;
        logic [7:0]  dropout_rate;
        logic [31:0] dropout_seed;
        logic signed [15:0] neg_large;
        logic signed [15:0] scale;
    } job_cfg_t;

    job_cfg_t active_job;
    job_cfg_t queued_jobs [JOB_QUEUE_DEPTH-1:0];
    logic [1:0] queued_job_count;
    logic       active_job_valid;
    logic       launch_pending;
    logic       dispatch_start;

    function automatic job_cfg_t current_reg_job();
        job_cfg_t job;
        begin
            job.q_base            = reg_q_base;
            job.k_base            = reg_k_base;
            job.v_base            = reg_v_base;
            job.o_base            = reg_o_base;
            job.stride_bytes      = reg_stride_bytes;
            job.valid_len         = reg_valid_len;
            job.head_count        = (reg_head_count[7:0] == 8'd0) ? 8'd1 : reg_head_count[7:0];
            job.head_stride_bytes = (reg_head_stride_bytes == 32'd0) ?
                                    32'(DEFAULT_HEAD_STRIDE_BYTES) : reg_head_stride_bytes;
            job.causal_en         = reg_causal_en;
            job.format_mode       = reg_format_mode;
            job.dropout_en        = reg_dropout_en;
            job.dropout_rate      = reg_dropout_rate;
            job.dropout_seed      = reg_dropout_seed;
            job.neg_large         = reg_neg_large;
            job.scale             = reg_scale;
            current_reg_job       = job;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_job_valid     <= 1'b0;
            launch_pending       <= 1'b0;
            dispatch_start       <= 1'b0;
            queued_job_count     <= '0;
            queue_pending_count  <= '0;
            queue_completed_count <= '0;
            queue_overflow       <= 1'b0;
            active_job           <= '0;
            for (int i = 0; i < JOB_QUEUE_DEPTH; i++)
                queued_jobs[i] <= '0;
        end else begin
            dispatch_start <= 1'b0;

            if (reg_soft_reset) begin
                active_job_valid      <= 1'b0;
                launch_pending        <= 1'b0;
                queued_job_count      <= '0;
                queue_pending_count   <= '0;
                queue_completed_count <= '0;
                queue_overflow        <= 1'b0;
            end else begin
                if (launch_pending) begin
                    dispatch_start   <= 1'b1;
                    launch_pending   <= 1'b0;
                    active_job_valid <= 1'b1;
                end

                if (tc_all_done) begin
                    active_job_valid <= 1'b0;
                    if (queue_completed_count != 8'hFF)
                        queue_completed_count <= queue_completed_count + 1'b1;

                    if (queued_job_count != 0) begin
                        active_job      <= queued_jobs[0];
                        queued_jobs[0]  <= queued_jobs[1];
                        queued_jobs[1]  <= '0;
                        queued_job_count <= queued_job_count - 1'b1;
                        launch_pending  <= 1'b1;
                    end
                end

                if (reg_start) begin
                    if (!active_job_valid && !launch_pending && !tc_busy) begin
                        active_job     <= current_reg_job();
                        launch_pending <= 1'b1;
                    end else if (queued_job_count < 2'(JOB_QUEUE_DEPTH)) begin
                        queued_jobs[queued_job_count] <= current_reg_job();
                        queued_job_count <= queued_job_count + 1'b1;
                    end else begin
                        queue_overflow <= 1'b1;
                    end
                end

                queue_pending_count <= {6'd0, queued_job_count};
            end
        end
    end

    logic [VALID_LEN_W-1:0] active_valid_len_cfg;
    assign active_valid_len_cfg = (active_job.valid_len == 32'd0 || active_job.valid_len > 32'(SEQ_LEN)) ?
                                  VALID_LEN_W'(SEQ_LEN) : active_job.valid_len[VALID_LEN_W-1:0];

    tile_controller #(
        .SEQ_LEN(SEQ_LEN), .HEAD_DIM(HEAD_DIM), .TILE_BR(TILE_BR), .TILE_BC(TILE_BC),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_tile_ctrl (
        .clk(clk), .rst_n(datapath_rst_n),
        .start(dispatch_start), .all_done(tc_all_done), .busy(tc_busy),
        .q_base_addr(active_job.q_base), .k_base_addr(active_job.k_base),
        .v_base_addr(active_job.v_base), .o_base_addr(active_job.o_base),
        .stride_bytes(active_job.stride_bytes),
        .valid_len(active_valid_len_cfg),
        .head_count(active_job.head_count),
        .head_stride_bytes(active_job.head_stride_bytes),
        .causal_en(active_job.causal_en),
        .dma_rd_req(tc_dma_rd_req), .dma_rd_addr(tc_dma_rd_addr),
        .dma_rd_len_bytes(tc_dma_rd_len), .dma_rd_target(tc_dma_rd_target),
        .dma_rd_done(tc_dma_rd_done),
        .dma_wr_req(tc_dma_wr_req), .dma_wr_addr(tc_dma_wr_addr),
        .dma_wr_len_bytes(tc_dma_wr_len), .dma_wr_done(tc_dma_wr_done),
        .compute_start(tc_compute_start), .compute_first_kv(tc_compute_first_kv),
        .compute_last_kv(tc_compute_last_kv), .compute_done(tc_compute_done),
        .q_tile_idx(tc_q_tile_idx), .kv_tile_idx(tc_kv_tile_idx),
        .kv_buf_sel(tc_kv_buf_sel)
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
        .clk(clk), .rst_n(datapath_rst_n),
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
        .buf_o_rd_col_grp(buf_o_rd_col_grp), .buf_o_rd_data(buf_o_rd_data)
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
        .clk(clk), .rst_n(datapath_rst_n),
        .q_wr_en(buf_q_wr_en), .q_wr_addr(buf_q_wr_addr), .q_wr_data(buf_q_wr_data),
        .k_wr_en(buf_k_wr_en), .k_wr_addr(buf_k_wr_addr), .k_wr_data(buf_k_wr_data),
        .k_buf_sel(tc_kv_buf_sel),
        .v_wr_en(buf_v_wr_en), .v_wr_addr(buf_v_wr_addr), .v_wr_data(buf_v_wr_data),
        .v_buf_sel(tc_kv_buf_sel),
        .format_mode(active_job.format_mode),
        .q_rd_en(comp_q_rd_en), .q_rd_step(comp_q_step), .q_rd_data(comp_q_data),
        .k_rd_en(comp_k_rd_en), .k_rd_step(comp_k_step),
        .k_rd_buf_sel(tc_kv_buf_sel), .k_rd_data(comp_k_data),
        .v_rd_en(comp_v_rd_en), .v_rd_step(comp_v_step),
        .v_rd_buf_sel(tc_kv_buf_sel), .v_rd_data(comp_v_data),
        .o_wr_en(comp_o_valid), .o_wr_data(comp_o_tile),
        .o_rd_en(buf_o_rd_en), .o_rd_row(buf_o_rd_row),
        .o_rd_col_grp(buf_o_rd_col_grp), .o_rd_data(buf_o_rd_data)
    );

    compute_core #(
        .SEQ_LEN(SEQ_LEN), .HEAD_DIM(HEAD_DIM), .TILE_BR(TILE_BR), .TILE_BC(TILE_BC),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
        .EXP_WIDTH(24), .FRAC_BITS(16), .PAR_MACS(PAR_MACS)
    ) u_compute (
        .clk(clk), .rst_n(datapath_rst_n),
        .start(tc_compute_start), .first_kv_tile(tc_compute_first_kv),
        .last_kv_tile(tc_compute_last_kv),
        .done(tc_compute_done), .busy(),
        .q_tile_idx(tc_q_tile_idx), .kv_tile_idx(tc_kv_tile_idx),
        .causal_en(active_job.causal_en), .valid_len(active_valid_len_cfg),
        .dropout_en(active_job.dropout_en),
        .dropout_rate(active_job.dropout_rate),
        .dropout_seed(active_job.dropout_seed),
        .scale(active_job.scale), .neg_large(active_job.neg_large),
        .q_rd_en(comp_q_rd_en), .q_rd_step(comp_q_step), .q_data(comp_q_data),
        .k_rd_en(comp_k_rd_en), .k_rd_step(comp_k_step), .k_data(comp_k_data),
        .v_rd_en(comp_v_rd_en), .v_rd_step(comp_v_step), .v_data(comp_v_data),
        .o_tile(comp_o_tile), .o_valid(comp_o_valid)
    );

    // ========== Cycle Counter ==========
    logic [31:0] cycle_cnt;
    assign cycle_count = cycle_cnt;

    always_ff @(posedge clk or negedge datapath_rst_n) begin
        if (!datapath_rst_n)
            cycle_cnt <= '0;
        else if (dispatch_start)
            cycle_cnt <= '0;
        else if (tc_busy)
            cycle_cnt <= cycle_cnt + 1;
    end

    always_ff @(posedge clk or negedge datapath_rst_n) begin
        if (!datapath_rst_n) begin
            rd_bytes_count  <= '0;
            wr_bytes_count  <= '0;
            tc_dma_rd_req_q <= 1'b0;
            tc_dma_wr_req_q <= 1'b0;
        end else begin
            tc_dma_rd_req_q <= tc_dma_rd_req;
            tc_dma_wr_req_q <= tc_dma_wr_req;
            if (dispatch_start) begin
                rd_bytes_count <= '0;
                wr_bytes_count <= '0;
            end else begin
                if (tc_dma_rd_req && !tc_dma_rd_req_q)
                    rd_bytes_count <= rd_bytes_count + {16'd0, tc_dma_rd_len};
                if (tc_dma_wr_req && !tc_dma_wr_req_q)
                    wr_bytes_count <= wr_bytes_count + {16'd0, tc_dma_wr_len};
            end
        end
    end

    // ========== Status ==========
    assign status_busy  = tc_busy | active_job_valid | launch_pending | (queued_job_count != 0);
    assign status_done  = tc_all_done;
    assign status_error = queue_overflow;
endmodule
