// ============================================================
// Tile Controller
// Manages the tiling loop: iterates over Q-tiles and KV-tiles
// Generates addresses for DMA transfers and controls compute core
// ============================================================
module tile_controller #(
    parameter SEQ_LEN        = 256,
    parameter HEAD_DIM       = 64,
    parameter TILE_BR        = 4,
    parameter TILE_BC        = 16,
    parameter AXI_ADDR_WIDTH = 64,
    parameter DATA_WIDTH     = 16
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // Start / Done from main FSM
    input  logic                          start,
    output logic                          all_done,
    output logic                          busy,

    // Configuration registers
    input  logic [AXI_ADDR_WIDTH-1:0]     q_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0]     k_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0]     v_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0]     o_base_addr,
    input  logic [31:0]                   stride_bytes,

    // DMA request interface
    output logic                          dma_rd_req,
    output logic [AXI_ADDR_WIDTH-1:0]     dma_rd_addr,
    output logic [15:0]                   dma_rd_len_bytes,
    output logic [1:0]                    dma_rd_target,   // 0=Q, 1=K, 2=V
    input  logic                          dma_rd_done,

    output logic                          dma_wr_req,
    output logic [AXI_ADDR_WIDTH-1:0]     dma_wr_addr,
    output logic [15:0]                   dma_wr_len_bytes,
    input  logic                          dma_wr_done,

    // Compute core control
    output logic                          compute_start,
    output logic                          compute_first_kv,
    output logic                          compute_last_kv,
    input  logic                          compute_done,

    // Tile indices (for causal mask)
    output logic [$clog2(SEQ_LEN)-1:0]   q_tile_idx,
    output logic [$clog2(SEQ_LEN)-1:0]   kv_tile_idx,

    // Buffer sel for ping-pong
    output logic                          kv_buf_sel,

    // O write-back trigger
    output logic                          o_writeback_start,
    input  logic                          o_writeback_done
);

    localparam NUM_Q_TILES  = SEQ_LEN / TILE_BR;
    localparam NUM_KV_TILES = SEQ_LEN / TILE_BC;
    localparam Q_TILE_BYTES = TILE_BR * HEAD_DIM * (DATA_WIDTH / 8);
    localparam KV_TILE_BYTES = TILE_BC * HEAD_DIM * (DATA_WIDTH / 8);
    localparam O_TILE_BYTES = TILE_BR * HEAD_DIM * (DATA_WIDTH / 8);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LOAD_Q,
        ST_WAIT_Q,
        ST_LOAD_KV,
        ST_WAIT_KV,
        ST_COMPUTE,
        ST_WAIT_COMPUTE,
        ST_NEXT_KV,
        ST_WRITE_O,
        ST_WAIT_O,
        ST_NEXT_Q,
        ST_ALL_DONE
    } state_t;

    state_t state;
    logic [$clog2(NUM_Q_TILES):0]  q_idx;
    logic [$clog2(NUM_KV_TILES):0] kv_idx;
    localparam integer TILE_IDX_W = $clog2(SEQ_LEN);

    assign q_tile_idx  = TILE_IDX_W'(q_idx);
    assign kv_tile_idx = TILE_IDX_W'(kv_idx);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            all_done           <= 1'b0;
            busy               <= 1'b0;
            q_idx              <= '0;
            kv_idx             <= '0;
            kv_buf_sel         <= 1'b0;
            dma_rd_req         <= 1'b0;
            dma_wr_req         <= 1'b0;
            compute_start      <= 1'b0;
            compute_first_kv   <= 1'b0;
            compute_last_kv    <= 1'b0;
            o_writeback_start  <= 1'b0;
        end else begin
            all_done          <= 1'b0;
            compute_start     <= 1'b0;
            o_writeback_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    dma_rd_req <= 1'b0;
                    dma_wr_req <= 1'b0;
                    if (start) begin
                        state  <= ST_LOAD_Q;
                        busy   <= 1'b1;
                        q_idx  <= '0;
                        kv_idx <= '0;
                    end
                end

                ST_LOAD_Q: begin
                    dma_rd_req       <= 1'b1;
                    dma_rd_addr      <= q_base_addr + AXI_ADDR_WIDTH'(q_idx) * AXI_ADDR_WIDTH'(stride_bytes) * TILE_BR;
                    dma_rd_len_bytes <= Q_TILE_BYTES;
                    dma_rd_target    <= 2'd0;
                    state            <= ST_WAIT_Q;
                end

                ST_WAIT_Q: begin
                    dma_rd_req <= 1'b0;
                    if (dma_rd_done) begin
                        kv_idx     <= '0;
                        kv_buf_sel <= 1'b0;
                        state      <= ST_LOAD_KV;
                    end
                end

                ST_LOAD_KV: begin
                    dma_rd_req       <= 1'b1;
                    dma_rd_addr      <= k_base_addr + AXI_ADDR_WIDTH'(kv_idx) * AXI_ADDR_WIDTH'(stride_bytes) * TILE_BC;
                    dma_rd_len_bytes <= KV_TILE_BYTES;
                    dma_rd_target    <= 2'd1;
                    state            <= ST_WAIT_KV;
                end

                ST_WAIT_KV: begin
                    dma_rd_req <= 1'b0;
                    if (dma_rd_done) begin
                        // Load V tile
                        dma_rd_req       <= 1'b1;
                        dma_rd_addr      <= v_base_addr + AXI_ADDR_WIDTH'(kv_idx) * AXI_ADDR_WIDTH'(stride_bytes) * TILE_BC;
                        dma_rd_len_bytes <= KV_TILE_BYTES;
                        dma_rd_target    <= 2'd2;
                        state            <= ST_COMPUTE;
                    end
                end

                ST_COMPUTE: begin
                    dma_rd_req <= 1'b0;
                    if (dma_rd_done) begin
                        compute_start    <= 1'b1;
                        compute_first_kv <= (kv_idx == 0);
                        compute_last_kv  <= (kv_idx == NUM_KV_TILES - 1);
                        state            <= ST_WAIT_COMPUTE;
                    end
                end

                ST_WAIT_COMPUTE: begin
                    if (compute_done) begin
                        state <= ST_NEXT_KV;
                    end
                end

                ST_NEXT_KV: begin
                    if (kv_idx == NUM_KV_TILES - 1) begin
                        state <= ST_WRITE_O;
                    end else begin
                        kv_idx     <= kv_idx + 1;
                        kv_buf_sel <= ~kv_buf_sel;
                        state      <= ST_LOAD_KV;
                    end
                end

                ST_WRITE_O: begin
                    dma_wr_req       <= 1'b1;
                    dma_wr_addr      <= o_base_addr + AXI_ADDR_WIDTH'(q_idx) * AXI_ADDR_WIDTH'(stride_bytes) * TILE_BR;
                    dma_wr_len_bytes <= O_TILE_BYTES;
                    o_writeback_start <= 1'b1;
                    state            <= ST_WAIT_O;
                end

                ST_WAIT_O: begin
                    if (dma_wr_done) begin
                        dma_wr_req <= 1'b0;
                        state <= ST_NEXT_Q;
                    end
                end

                ST_NEXT_Q: begin
                    if (q_idx == NUM_Q_TILES - 1) begin
                        state <= ST_ALL_DONE;
                    end else begin
                        q_idx <= q_idx + 1;
                        state <= ST_LOAD_Q;
                    end
                end

                ST_ALL_DONE: begin
                    all_done <= 1'b1;
                    busy     <= 1'b0;
                    state    <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
