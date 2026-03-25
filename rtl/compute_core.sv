// ============================================================
// Compute Core
// Orchestrates: dot_product → causal_mask → online_softmax → output_accumulator
// For a single (Q-tile, KV-tile) pair
// ============================================================
module compute_core #(
    parameter SEQ_LEN    = 256,
    parameter HEAD_DIM   = 64,
    parameter TILE_BR    = 4,
    parameter TILE_BC    = 16,
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 40,
    parameter EXP_WIDTH  = 24,
    parameter FRAC_BITS  = 16,
    parameter PAR_MACS   = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // Control
    input  logic                          start,
    input  logic                          first_kv_tile,
    input  logic                          last_kv_tile,
    output logic                          done,
    output logic                          busy,

    // Tile indices for causal mask
    input  logic [$clog2(SEQ_LEN)-1:0]   q_tile_idx,
    input  logic [$clog2(SEQ_LEN)-1:0]   kv_tile_idx,

    // Configuration
    input  logic                          causal_en,
    input  logic signed [DATA_WIDTH-1:0]  scale,
    input  logic signed [15:0]            neg_large,

    // Q tile buffer read interface (B_r × PAR_MACS per cycle, NUM_STEPS cycles)
    output logic                          q_rd_en,
    output logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] q_rd_step,
    input  logic signed [DATA_WIDTH-1:0]  q_data [TILE_BR-1:0][PAR_MACS-1:0],

    // K tile buffer read interface
    output logic                          k_rd_en,
    output logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] k_rd_step,
    input  logic signed [DATA_WIDTH-1:0]  k_data [TILE_BC-1:0][PAR_MACS-1:0],

    // V tile buffer read interface (B_c × PAR_MACS per cycle)
    output logic                          v_rd_en,
    output logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] v_rd_step,
    input  logic signed [DATA_WIDTH-1:0]  v_data [TILE_BC-1:0][PAR_MACS-1:0],

    // Output: O tile (B_r × d), valid on last KV tile
    output logic signed [DATA_WIDTH-1:0]  o_tile [TILE_BR-1:0][HEAD_DIM-1:0],
    output logic                          o_valid
);

    localparam IDX_W = $clog2(SEQ_LEN);
    localparam NUM_STEPS = HEAD_DIM / PAR_MACS;

    // State machine
    typedef enum logic [2:0] {
        S_IDLE,
        S_DOT_PRODUCT,
        S_MASK,
        S_SOFTMAX,
        S_ACCUMULATE,
        S_DONE
    } state_t;

    state_t state;

    // Dot product signals
    logic dp_start, dp_done, dp_busy;
    logic signed [ACC_WIDTH-1:0] dp_scores [TILE_BR-1:0][TILE_BC-1:0];
    logic dp_scores_valid;
    logic dp_data_valid;
    logic [$clog2(NUM_STEPS):0] dp_step;

    dot_product_array #(
        .TILE_BR(TILE_BR), .TILE_BC(TILE_BC), .HEAD_DIM(HEAD_DIM),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .PAR_MACS(PAR_MACS)
    ) u_dp (
        .clk(clk), .rst_n(rst_n),
        .start(dp_start), .done(dp_done), .busy(dp_busy),
        .q_data(q_data), .k_data(k_data), .data_valid(dp_data_valid),
        .scale(scale),
        .scores(dp_scores), .scores_valid(dp_scores_valid)
    );

    // Masked scores
    logic signed [ACC_WIDTH-1:0] masked_scores [TILE_BR-1:0][TILE_BC-1:0];

    // Online softmax signals
    logic sm_start, sm_done, sm_busy;
    logic signed [ACC_WIDTH-1:0] m_old [TILE_BR-1:0];
    logic [ACC_WIDTH-1:0]        l_old [TILE_BR-1:0];
    logic signed [ACC_WIDTH-1:0] m_new [TILE_BR-1:0];
    logic [ACC_WIDTH-1:0]        l_new [TILE_BR-1:0];
    logic [EXP_WIDTH-1:0]        p_matrix [TILE_BR-1:0][TILE_BC-1:0];
    logic [ACC_WIDTH-1:0]        rescale_vals [TILE_BR-1:0];
    logic                        sm_valid;

    online_softmax_unit #(
        .TILE_BR(TILE_BR), .TILE_BC(TILE_BC),
        .SCORE_WIDTH(ACC_WIDTH), .EXP_WIDTH(EXP_WIDTH), .FRAC_BITS(FRAC_BITS)
    ) u_softmax (
        .clk(clk), .rst_n(rst_n),
        .start(sm_start), .first_tile(first_kv_tile), .done(sm_done), .busy(sm_busy),
        .scores(masked_scores), .neg_large(neg_large),
        .m_old(m_old), .l_old(l_old),
        .m_new(m_new), .l_new(l_new),
        .p_matrix(p_matrix), .rescale(rescale_vals), .results_valid(sm_valid)
    );

    // Output accumulator signals
    logic oa_start, oa_done, oa_busy;
    logic oa_v_valid;
    logic [$clog2(NUM_STEPS):0] oa_v_step;

    output_accumulator #(
        .TILE_BR(TILE_BR), .TILE_BC(TILE_BC), .HEAD_DIM(HEAD_DIM),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
        .EXP_WIDTH(EXP_WIDTH), .FRAC_BITS(FRAC_BITS), .PAR_COLS(PAR_MACS)
    ) u_oa (
        .clk(clk), .rst_n(rst_n),
        .start(oa_start), .first_tile(first_kv_tile), .last_tile(last_kv_tile),
        .done(oa_done), .busy(oa_busy),
        .p_matrix(p_matrix),
        .v_data(v_data), .v_valid(oa_v_valid),
        .rescale(rescale_vals), .l_values(l_new),
        .o_out(o_tile), .o_valid(o_valid)
    );

    // Persistent softmax state across KV tiles
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int r = 0; r < TILE_BR; r++) begin
                m_old[r] <= {ACC_WIDTH{1'b1}};  // -inf
                l_old[r] <= '0;
            end
        end else if (sm_valid) begin
            for (int r = 0; r < TILE_BR; r++) begin
                m_old[r] <= m_new[r];
                l_old[r] <= l_new[r];
            end
        end else if (state == S_IDLE && start && first_kv_tile) begin
            for (int r = 0; r < TILE_BR; r++) begin
                m_old[r] <= {ACC_WIDTH{1'b1}};
                l_old[r] <= '0;
            end
        end
    end

    // Main control FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            done      <= 1'b0;
            busy      <= 1'b0;
            dp_start  <= 1'b0;
            sm_start  <= 1'b0;
            oa_start  <= 1'b0;
            dp_step   <= '0;
            dp_data_valid <= 1'b0;
            q_rd_en   <= 1'b0;
            k_rd_en   <= 1'b0;
            v_rd_en   <= 1'b0;
            oa_v_valid <= 1'b0;
            oa_v_step <= '0;
        end else begin
            done     <= 1'b0;
            dp_start <= 1'b0;
            sm_start <= 1'b0;
            oa_start <= 1'b0;
            dp_data_valid <= 1'b0;
            q_rd_en  <= 1'b0;
            k_rd_en  <= 1'b0;
            v_rd_en  <= 1'b0;
            oa_v_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state    <= S_DOT_PRODUCT;
                        busy     <= 1'b1;
                        dp_start <= 1'b1;
                        dp_step  <= '0;
                    end
                end

                S_DOT_PRODUCT: begin
                    if (!dp_done && dp_busy) begin
                        // Stream Q and K data to dot-product unit
                        q_rd_en <= 1'b1;
                        k_rd_en <= 1'b1;
                        q_rd_step <= dp_step[$clog2(NUM_STEPS)-1:0];
                        k_rd_step <= dp_step[$clog2(NUM_STEPS)-1:0];
                        dp_data_valid <= 1'b1;
                        dp_step <= dp_step + 1;
                    end
                    if (dp_done) begin
                        state <= S_MASK;
                    end
                end

                S_MASK: begin
                    // Apply causal mask
                    for (int r = 0; r < TILE_BR; r++) begin
                        for (int c = 0; c < TILE_BC; c++) begin
                            logic mask_bit;
                            logic [IDX_W-1:0] abs_row, abs_col;
                            abs_row = q_tile_idx * TILE_BR + IDX_W'(r);
                            abs_col = kv_tile_idx * TILE_BC + IDX_W'(c);
                            mask_bit = causal_en & (abs_col > abs_row);
                            if (mask_bit)
                                masked_scores[r][c] <= {{(ACC_WIDTH-16){neg_large[15]}}, neg_large};
                            else
                                masked_scores[r][c] <= dp_scores[r][c];
                        end
                    end
                    state    <= S_SOFTMAX;
                    sm_start <= 1'b1;
                end

                S_SOFTMAX: begin
                    if (sm_done) begin
                        state    <= S_ACCUMULATE;
                        oa_start <= 1'b1;
                        oa_v_step <= '0;
                    end
                end

                S_ACCUMULATE: begin
                    if (oa_busy && !oa_done) begin
                        v_rd_en    <= 1'b1;
                        v_rd_step  <= oa_v_step[$clog2(NUM_STEPS)-1:0];
                        oa_v_valid <= 1'b1;
                        oa_v_step  <= oa_v_step + 1;
                    end
                    if (oa_done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
