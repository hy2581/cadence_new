// ============================================================
// Enhanced Tile Controller (Bonus: multi-head, variable seq_len, task queue)
// Manages tiling loop with multi-head outer loop and runtime seq_len
// ============================================================
`include "fa_params_bonus.svh"

module tile_controller_bonus #(
    parameter MAX_SEQ_LEN    = 1024,
    parameter HEAD_DIM       = 64,
    parameter TILE_BR        = 4,
    parameter TILE_BC        = 16,
    parameter AXI_ADDR_WIDTH = 64,
    parameter DATA_WIDTH     = 16
)(
    input  logic                          clk,
    input  logic                          rst_n,

    input  logic                          start,
    output logic                          all_done,
    output logic                          busy,

    // Runtime configurable dimensions
    input  logic [15:0]                   cfg_seq_len,     // actual seq length (≤ MAX_SEQ_LEN)
    input  logic [7:0]                    cfg_num_heads,   // number of heads

    // Base addresses (for head 0, tile controller adds head offsets)
    input  logic [AXI_ADDR_WIDTH-1:0]    q_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0]    k_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0]    v_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0]    o_base_addr,
    input  logic [31:0]                  stride_bytes,
    input  logic [31:0]                  head_stride_bytes, // bytes between heads

    // DMA request interface
    output logic                          dma_rd_req,
    output logic [AXI_ADDR_WIDTH-1:0]    dma_rd_addr,
    output logic [15:0]                  dma_rd_len_bytes,
    output logic [1:0]                   dma_rd_target,
    input  logic                          dma_rd_done,

    output logic                          dma_wr_req,
    output logic [AXI_ADDR_WIDTH-1:0]    dma_wr_addr,
    output logic [15:0]                  dma_wr_len_bytes,
    input  logic                          dma_wr_done,

    // Compute core control
    output logic                          compute_start,
    output logic                          compute_first_kv,
    output logic                          compute_last_kv,
    input  logic                          compute_done,

    // Tile indices
    output logic [15:0]                  q_tile_idx,
    output logic [15:0]                  kv_tile_idx,
    output logic [7:0]                   head_idx,

    output logic                          kv_buf_sel,
    output logic                          o_writeback_start,
    input  logic                          o_writeback_done,

    // Task queue interface
    input  logic                          task_queue_mode,
    input  logic                          task_pop_valid,
    output logic                          task_pop_req,
    input  logic [AXI_ADDR_WIDTH-1:0]    tq_q_base,
    input  logic [AXI_ADDR_WIDTH-1:0]    tq_k_base,
    input  logic [AXI_ADDR_WIDTH-1:0]    tq_v_base,
    input  logic [AXI_ADDR_WIDTH-1:0]    tq_o_base,
    input  logic [31:0]                  tq_config
);

    localparam Q_TILE_BYTES  = TILE_BR * HEAD_DIM * (DATA_WIDTH / 8);
    localparam KV_TILE_BYTES = TILE_BC * HEAD_DIM * (DATA_WIDTH / 8);
    localparam O_TILE_BYTES  = TILE_BR * HEAD_DIM * (DATA_WIDTH / 8);

    // Derived runtime values
    logic [15:0] num_q_tiles, num_kv_tiles;
    assign num_q_tiles  = cfg_seq_len / TILE_BR;
    assign num_kv_tiles = cfg_seq_len / TILE_BC;

    // Active base addresses (from registers or task queue)
    logic [AXI_ADDR_WIDTH-1:0] act_q_base, act_k_base, act_v_base, act_o_base;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_TQ_POP,
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
        ST_NEXT_HEAD,
        ST_ALL_DONE
    } state_t;

    state_t state;
    logic [15:0] q_idx, kv_idx;
    logic [7:0]  h_idx;

    assign q_tile_idx = q_idx;
    assign kv_tile_idx = kv_idx;
    assign head_idx = h_idx;

    // Head offset calculation
    wire [AXI_ADDR_WIDTH-1:0] head_offset = AXI_ADDR_WIDTH'(h_idx) * AXI_ADDR_WIDTH'(head_stride_bytes);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            all_done           <= 1'b0;
            busy               <= 1'b0;
            q_idx              <= '0;
            kv_idx             <= '0;
            h_idx              <= '0;
            kv_buf_sel         <= 1'b0;
            dma_rd_req         <= 1'b0;
            dma_wr_req         <= 1'b0;
            compute_start      <= 1'b0;
            compute_first_kv   <= 1'b0;
            compute_last_kv    <= 1'b0;
            o_writeback_start  <= 1'b0;
            task_pop_req       <= 1'b0;
            act_q_base         <= '0;
            act_k_base         <= '0;
            act_v_base         <= '0;
            act_o_base         <= '0;
        end else begin
            all_done          <= 1'b0;
            compute_start     <= 1'b0;
            o_writeback_start <= 1'b0;
            task_pop_req      <= 1'b0;

            case (state)
                ST_IDLE: begin
                    dma_rd_req <= 1'b0;
                    dma_wr_req <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        h_idx <= '0;
                        if (task_queue_mode && task_pop_valid) begin
                            state <= ST_TQ_POP;
                        end else begin
                            act_q_base <= q_base_addr;
                            act_k_base <= k_base_addr;
                            act_v_base <= v_base_addr;
                            act_o_base <= o_base_addr;
                            q_idx      <= '0;
                            kv_idx     <= '0;
                            state      <= ST_LOAD_Q;
                        end
                    end
                end

                ST_TQ_POP: begin
                    task_pop_req <= 1'b1;
                    act_q_base   <= tq_q_base;
                    act_k_base   <= tq_k_base;
                    act_v_base   <= tq_v_base;
                    act_o_base   <= tq_o_base;
                    q_idx        <= '0;
                    kv_idx       <= '0;
                    h_idx        <= '0;
                    state        <= ST_LOAD_Q;
                end

                ST_LOAD_Q: begin
                    dma_rd_req       <= 1'b1;
                    dma_rd_addr      <= act_q_base + head_offset +
                                        AXI_ADDR_WIDTH'(q_idx) * AXI_ADDR_WIDTH'(stride_bytes) * TILE_BR;
                    dma_rd_len_bytes <= Q_TILE_BYTES[15:0];
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
                    dma_rd_addr      <= act_k_base + head_offset +
                                        AXI_ADDR_WIDTH'(kv_idx) * AXI_ADDR_WIDTH'(stride_bytes) * TILE_BC;
                    dma_rd_len_bytes <= KV_TILE_BYTES[15:0];
                    dma_rd_target    <= 2'd1;
                    state            <= ST_WAIT_KV;
                end

                ST_WAIT_KV: begin
                    dma_rd_req <= 1'b0;
                    if (dma_rd_done) begin
                        dma_rd_req       <= 1'b1;
                        dma_rd_addr      <= act_v_base + head_offset +
                                            AXI_ADDR_WIDTH'(kv_idx) * AXI_ADDR_WIDTH'(stride_bytes) * TILE_BC;
                        dma_rd_len_bytes <= KV_TILE_BYTES[15:0];
                        dma_rd_target    <= 2'd2;
                        state            <= ST_COMPUTE;
                    end
                end

                ST_COMPUTE: begin
                    dma_rd_req <= 1'b0;
                    if (dma_rd_done) begin
                        compute_start    <= 1'b1;
                        compute_first_kv <= (kv_idx == 0);
                        compute_last_kv  <= (kv_idx == num_kv_tiles - 1);
                        state            <= ST_WAIT_COMPUTE;
                    end
                end

                ST_WAIT_COMPUTE: begin
                    if (compute_done)
                        state <= ST_NEXT_KV;
                end

                ST_NEXT_KV: begin
                    if (kv_idx >= num_kv_tiles - 1) begin
                        state <= ST_WRITE_O;
                    end else begin
                        kv_idx     <= kv_idx + 1;
                        kv_buf_sel <= ~kv_buf_sel;
                        state      <= ST_LOAD_KV;
                    end
                end

                ST_WRITE_O: begin
                    dma_wr_req       <= 1'b1;
                    dma_wr_addr      <= act_o_base + head_offset +
                                        AXI_ADDR_WIDTH'(q_idx) * AXI_ADDR_WIDTH'(stride_bytes) * TILE_BR;
                    dma_wr_len_bytes <= O_TILE_BYTES[15:0];
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
                    if (q_idx >= num_q_tiles - 1) begin
                        state <= ST_NEXT_HEAD;
                    end else begin
                        q_idx <= q_idx + 1;
                        state <= ST_LOAD_Q;
                    end
                end

                ST_NEXT_HEAD: begin
                    if (h_idx >= cfg_num_heads - 1) begin
                        // Check task queue for more tasks
                        if (task_queue_mode && task_pop_valid) begin
                            state <= ST_TQ_POP;
                        end else begin
                            state <= ST_ALL_DONE;
                        end
                    end else begin
                        h_idx  <= h_idx + 1;
                        q_idx  <= '0;
                        kv_idx <= '0;
                        state  <= ST_LOAD_Q;
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
