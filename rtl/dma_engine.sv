// ============================================================
// DMA Engine
// Bridges tile_controller requests to AXI4 master transactions
// Routes read data to appropriate buffers (Q/K/V)
// Routes O buffer data to AXI4 write channel
// ============================================================
module dma_engine #(
    parameter AXI_ADDR_WIDTH = 64,
    parameter AXI_DATA_WIDTH = 128,
    parameter AXI_ID_WIDTH   = 4,
    parameter TILE_BR    = 4,
    parameter TILE_BC    = 16,
    parameter HEAD_DIM   = 64,
    parameter DATA_WIDTH = 16
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // --- AXI4 Master ports (directly to external AXI4 interface) ---
    output logic [AXI_ID_WIDTH-1:0]    m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]                 m_axi_awlen,
    output logic [2:0]                 m_axi_awsize,
    output logic [1:0]                 m_axi_awburst,
    output logic                       m_axi_awvalid,
    input  logic                       m_axi_awready,
    output logic [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                       m_axi_wlast,
    output logic                       m_axi_wvalid,
    input  logic                       m_axi_wready,
    input  logic [AXI_ID_WIDTH-1:0]    m_axi_bid,
    input  logic [1:0]                 m_axi_bresp,
    input  logic                       m_axi_bvalid,
    output logic                       m_axi_bready,
    output logic [AXI_ID_WIDTH-1:0]    m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]                 m_axi_arlen,
    output logic [2:0]                 m_axi_arsize,
    output logic [1:0]                 m_axi_arburst,
    output logic                       m_axi_arvalid,
    input  logic                       m_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]    m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]                 m_axi_rresp,
    input  logic                       m_axi_rlast,
    input  logic                       m_axi_rvalid,
    output logic                       m_axi_rready,

    // --- Tile controller interface ---
    input  logic                       dma_rd_req,
    input  logic [AXI_ADDR_WIDTH-1:0]  dma_rd_addr,
    input  logic [15:0]                dma_rd_len_bytes,
    input  logic [1:0]                 dma_rd_target,   // 0=Q, 1=K, 2=V
    output logic                       dma_rd_done,

    input  logic                       dma_wr_req,
    input  logic [AXI_ADDR_WIDTH-1:0]  dma_wr_addr,
    input  logic [15:0]                dma_wr_len_bytes,
    output logic                       dma_wr_done,

    // --- Buffer write interface (Q/K/V) ---
    output logic                       buf_q_wr_en,
    output logic [$clog2(TILE_BR*HEAD_DIM)-1:0] buf_q_wr_addr,
    output logic [AXI_DATA_WIDTH-1:0]  buf_q_wr_data,

    output logic                       buf_k_wr_en,
    output logic [$clog2(TILE_BC*HEAD_DIM)-1:0] buf_k_wr_addr,
    output logic [AXI_DATA_WIDTH-1:0]  buf_k_wr_data,

    output logic                       buf_v_wr_en,
    output logic [$clog2(TILE_BC*HEAD_DIM)-1:0] buf_v_wr_addr,
    output logic [AXI_DATA_WIDTH-1:0]  buf_v_wr_data,

    // --- O buffer read interface ---
    output logic                       buf_o_rd_en,
    output logic [$clog2(TILE_BR)-1:0] buf_o_rd_row,
    output logic [$clog2(HEAD_DIM/(AXI_DATA_WIDTH/DATA_WIDTH))-1:0] buf_o_rd_col_grp,
    input  logic [AXI_DATA_WIDTH-1:0]  buf_o_rd_data,

    // Buffer sel
    input  logic                       kv_buf_sel
);

    localparam ELEMS_PER_BEAT = AXI_DATA_WIDTH / DATA_WIDTH;

    // AXI master instance
    logic        axi_rd_req;
    logic [AXI_ADDR_WIDTH-1:0] axi_rd_addr;
    logic [15:0] axi_rd_len;
    logic        axi_rd_done;
    logic [AXI_DATA_WIDTH-1:0] axi_rd_data;
    logic        axi_rd_data_valid;

    logic        axi_wr_req;
    logic [AXI_ADDR_WIDTH-1:0] axi_wr_addr;
    logic [15:0] axi_wr_len;
    logic        axi_wr_done;
    logic [AXI_DATA_WIDTH-1:0] axi_wr_data;
    logic        axi_wr_data_valid;
    logic        axi_wr_data_ready;

    axi4_master_if #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH), .ID_WIDTH(AXI_ID_WIDTH)
    ) u_axi_master (
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
        .rd_req(axi_rd_req), .rd_addr(axi_rd_addr), .rd_len_bytes(axi_rd_len),
        .rd_done(axi_rd_done), .rd_data(axi_rd_data), .rd_data_valid(axi_rd_data_valid),
        .wr_req(axi_wr_req), .wr_addr(axi_wr_addr), .wr_len_bytes(axi_wr_len),
        .wr_done(axi_wr_done), .wr_data(axi_wr_data),
        .wr_data_valid(axi_wr_data_valid), .wr_data_ready(axi_wr_data_ready)
    );

    // --- Read data routing ---
    logic [1:0]  rd_target_reg;
    logic [15:0] rd_beat_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_rd_req    <= 1'b0;
            rd_target_reg <= '0;
            rd_beat_cnt   <= '0;
            dma_rd_done   <= 1'b0;
            buf_q_wr_en   <= 1'b0;
            buf_k_wr_en   <= 1'b0;
            buf_v_wr_en   <= 1'b0;
        end else begin
            dma_rd_done <= 1'b0;
            buf_q_wr_en <= 1'b0;
            buf_k_wr_en <= 1'b0;
            buf_v_wr_en <= 1'b0;

            // Capture DMA read request and hold axi_rd_req until done
            if (dma_rd_req && !axi_rd_req) begin
                axi_rd_req    <= 1'b1;
                axi_rd_addr   <= dma_rd_addr;
                axi_rd_len    <= dma_rd_len_bytes;
                rd_target_reg <= dma_rd_target;
                rd_beat_cnt   <= '0;
            end
            if (axi_rd_done) begin
                axi_rd_req <= 1'b0;
            end

            if (axi_rd_data_valid) begin
                case (rd_target_reg)
                    2'd0: begin
                        buf_q_wr_en   <= 1'b1;
                        buf_q_wr_addr <= rd_beat_cnt[$clog2(TILE_BR*HEAD_DIM)-1:0];
                        buf_q_wr_data <= axi_rd_data;
                    end
                    2'd1: begin
                        buf_k_wr_en   <= 1'b1;
                        buf_k_wr_addr <= rd_beat_cnt[$clog2(TILE_BC*HEAD_DIM)-1:0];
                        buf_k_wr_data <= axi_rd_data;
                    end
                    2'd2: begin
                        buf_v_wr_en   <= 1'b1;
                        buf_v_wr_addr <= rd_beat_cnt[$clog2(TILE_BC*HEAD_DIM)-1:0];
                        buf_v_wr_data <= axi_rd_data;
                    end
                    default: ;
                endcase
                rd_beat_cnt <= rd_beat_cnt + 1;
            end

            if (axi_rd_done)
                dma_rd_done <= 1'b1;
        end
    end

    // --- Write data routing (O buffer → AXI) ---
    logic [15:0] wr_beat_cnt;
    logic [15:0] wr_beats_total;
    logic        wr_active;

    localparam O_COLS_PER_BEAT = AXI_DATA_WIDTH / DATA_WIDTH;
    localparam O_BEATS_PER_ROW = HEAD_DIM / O_COLS_PER_BEAT;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_wr_req       <= 1'b0;
            dma_wr_done      <= 1'b0;
            wr_active        <= 1'b0;
            wr_beat_cnt      <= '0;
            wr_beats_total   <= '0;
            axi_wr_data_valid <= 1'b0;
            buf_o_rd_en      <= 1'b0;
        end else begin
            dma_wr_done      <= 1'b0;
            buf_o_rd_en      <= 1'b0;
            axi_wr_data_valid <= 1'b0;

            if (dma_wr_req && !wr_active) begin
                axi_wr_req     <= 1'b1;
                axi_wr_addr    <= dma_wr_addr;
                axi_wr_len     <= dma_wr_len_bytes;
                wr_active      <= 1'b1;
                wr_beat_cnt    <= '0;
                wr_beats_total <= TILE_BR * O_BEATS_PER_ROW;
            end

            if (wr_active && axi_wr_data_ready) begin
                buf_o_rd_en      <= 1'b1;
                buf_o_rd_row     <= wr_beat_cnt / O_BEATS_PER_ROW;
                buf_o_rd_col_grp <= wr_beat_cnt % O_BEATS_PER_ROW;
                axi_wr_data      <= buf_o_rd_data;
                axi_wr_data_valid <= 1'b1;
                wr_beat_cnt      <= wr_beat_cnt + 1;

                if (wr_beat_cnt == wr_beats_total - 1)
                    wr_active <= 1'b0;
            end

            if (axi_wr_done) begin
                dma_wr_done <= 1'b1;
                axi_wr_req  <= 1'b0;
            end
        end
    end

endmodule
