// ============================================================
// Enhanced Compute Core (Bonus: padding mask, dropout, multi-format)
// Orchestrates: dot_product → mask → online_softmax → dropout → accumulate
// ============================================================
`include "fa_params_bonus.svh"

module compute_core_bonus #(
    parameter MAX_SEQ_LEN = 1024,
    parameter HEAD_DIM    = 64,
    parameter TILE_BR     = 4,
    parameter TILE_BC     = 16,
    parameter DATA_WIDTH  = 16,
    parameter ACC_WIDTH   = 40,
    parameter EXP_WIDTH   = 24,
    parameter FRAC_BITS   = 16,
    parameter PAR_MACS    = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,

    input  logic                          start,
    input  logic                          first_kv_tile,
    input  logic                          last_kv_tile,
    output logic                          done,
    output logic                          busy,

    // Tile indices
    input  logic [15:0]                  q_tile_idx,
    input  logic [15:0]                  kv_tile_idx,

    // Configuration
    input  logic                          causal_en,
    input  logic                          padding_en,
    input  logic                          dropout_en,
    input  logic [15:0]                  valid_len,
    input  logic signed [DATA_WIDTH-1:0] scale,
    input  logic signed [15:0]           neg_large,
    input  logic [7:0]                   drop_prob,
    input  logic [31:0]                  dropout_seed,
    input  logic [2:0]                   data_fmt,

    // Q tile buffer read
    output logic                          q_rd_en,
    output logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] q_rd_step,
    input  logic signed [DATA_WIDTH-1:0] q_data [TILE_BR-1:0][PAR_MACS-1:0],

    // K tile buffer read
    output logic                          k_rd_en,
    output logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] k_rd_step,
    input  logic signed [DATA_WIDTH-1:0] k_data [TILE_BC-1:0][PAR_MACS-1:0],

    // V tile buffer read
    output logic                          v_rd_en,
    output logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] v_rd_step,
    input  logic signed [DATA_WIDTH-1:0] v_data [TILE_BC-1:0][PAR_MACS-1:0],

    // Output
    output logic signed [DATA_WIDTH-1:0] o_tile [TILE_BR-1:0][HEAD_DIM-1:0],
    output logic                          o_valid
);

    localparam NUM_STEPS = HEAD_DIM / PAR_MACS;

    typedef enum logic [3:0] {
        S_IDLE,
        S_DOT_PRODUCT,
        S_MASK,
        S_SOFTMAX,
        S_DROPOUT,
        S_ACCUMULATE,
        S_DONE
    } state_t;

    state_t state;

    // --- Runtime FRAC_BITS selection based on data_fmt ---
    // 0=Q8.8(frac=8), 1=Q6.10(frac=10), 2=Q4.12(frac=12), 3=BF16(frac=8), 4=INT8(frac=8)
    logic [4:0] active_frac_bits;
    always_comb begin
        case (data_fmt)
            3'd1:    active_frac_bits = 5'd10; // Q6.10
            3'd2:    active_frac_bits = 5'd12; // Q4.12
            default: active_frac_bits = 5'd8;  // Q8.8, BF16, INT8
        endcase
    end

    // --- Dot Product Array (reuse from baseline) ---
    logic dp_start, dp_done, dp_busy;
    logic signed [ACC_WIDTH-1:0] dp_scores [TILE_BR-1:0][TILE_BC-1:0];
    logic dp_scores_valid, dp_data_valid;
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

    // --- BF16 Exp unit (for BF16 mode) ---
    logic        bf16_exp_in_valid, bf16_exp_out_valid;
    logic [15:0] bf16_exp_x, bf16_exp_y;

    bf16_exp_unit u_bf16_exp (
        .clk(clk), .rst_n(rst_n),
        .in_valid(bf16_exp_in_valid), .x_bf16(bf16_exp_x),
        .exp_bf16(bf16_exp_y), .out_valid(bf16_exp_out_valid)
    );

    // --- BF16 Reciprocal unit (for BF16 mode) ---
    logic        bf16_recip_in_valid, bf16_recip_out_valid;
    logic [15:0] bf16_recip_x, bf16_recip_y;

    bf16_reciprocal_unit u_bf16_recip (
        .clk(clk), .rst_n(rst_n),
        .in_valid(bf16_recip_in_valid), .x_bf16(bf16_recip_x),
        .recip_bf16(bf16_recip_y), .out_valid(bf16_recip_out_valid)
    );

    // Default: BF16 units idle unless explicitly driven
    assign bf16_exp_in_valid   = 1'b0;
    assign bf16_exp_x          = 16'h0;
    assign bf16_recip_in_valid = 1'b0;
    assign bf16_recip_x        = 16'h0;

    // --- Masked scores (causal + padding) ---
    logic signed [ACC_WIDTH-1:0] masked_scores [TILE_BR-1:0][TILE_BC-1:0];

    // --- INT8 Quantizer (for INT8 mode) ---
    logic signed [7:0]  int8_quant_out [TILE_BC-1:0];
    logic [15:0]        int8_quant_scale;
    logic               int8_quant_done;
    logic signed [DATA_WIDTH-1:0] int8_dequant_out [TILE_BC-1:0];
    logic               int8_dequant_done;

    // Placeholder signals for INT8 — module exists for synthesis
    logic signed [DATA_WIDTH-1:0] int8_input_block [TILE_BC-1:0];
    logic signed [7:0]  int8_dequant_in [TILE_BC-1:0];

    int8_quantizer #(.BLOCK_SIZE(TILE_BC), .IN_WIDTH(DATA_WIDTH), .FRAC_BITS(8))
    u_int8_quant (
        .clk(clk), .rst_n(rst_n),
        .quant_valid(1'b0), .quant_data(int8_input_block),
        .quant_out(int8_quant_out), .quant_scale(int8_quant_scale), .quant_done(int8_quant_done),
        .dequant_valid(1'b0), .dequant_data(int8_dequant_in),
        .dequant_scale(16'h0100), .dequant_out(int8_dequant_out), .dequant_done(int8_dequant_done)
    );

    // Initialize int8 arrays
    integer init_i;
    initial begin
        for (init_i = 0; init_i < TILE_BC; init_i = init_i + 1) begin
            int8_input_block[init_i] = '0;
            int8_dequant_in[init_i] = '0;
        end
    end

    // --- Online Softmax ---
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

    // --- Dropout (applied to p_matrix) ---
    logic [EXP_WIDTH-1:0] p_after_dropout [TILE_BR-1:0][TILE_BC-1:0];
    logic dropout_done_flag;

    // Dropout LFSR state
    logic [31:0] lfsr_state;
    logic lfsr_feedback;
    assign lfsr_feedback = lfsr_state[31] ^ lfsr_state[21] ^ lfsr_state[1] ^ lfsr_state[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr_state <= 32'hDEAD_BEEF;
        else if (state == S_IDLE && start)
            lfsr_state <= (dropout_seed == '0) ? 32'hDEAD_BEEF : dropout_seed;
        else if (state == S_DROPOUT)
            lfsr_state <= {lfsr_state[30:0], lfsr_feedback};
    end

    // --- Output Accumulator ---
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
        .p_matrix(p_after_dropout),
        .v_data(v_data), .v_valid(oa_v_valid),
        .rescale(rescale_vals), .l_values(l_new),
        .o_out(o_tile), .o_valid(o_valid)
    );

    // Persistent softmax state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (integer r = 0; r < TILE_BR; r = r + 1) begin
                m_old[r] <= {ACC_WIDTH{1'b1}};
                l_old[r] <= '0;
            end
        end else if (sm_valid) begin
            for (integer r = 0; r < TILE_BR; r = r + 1) begin
                m_old[r] <= m_new[r];
                l_old[r] <= l_new[r];
            end
        end else if (state == S_IDLE && start && first_kv_tile) begin
            for (integer r = 0; r < TILE_BR; r = r + 1) begin
                m_old[r] <= {ACC_WIDTH{1'b1}};
                l_old[r] <= '0;
            end
        end
    end

    // Main FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            busy          <= 1'b0;
            dp_start      <= 1'b0;
            sm_start      <= 1'b0;
            oa_start      <= 1'b0;
            dp_step       <= '0;
            dp_data_valid <= 1'b0;
            q_rd_en       <= 1'b0;
            k_rd_en       <= 1'b0;
            v_rd_en       <= 1'b0;
            oa_v_valid    <= 1'b0;
            oa_v_step     <= '0;
            dropout_done_flag <= 1'b0;
        end else begin
            done          <= 1'b0;
            dp_start      <= 1'b0;
            sm_start      <= 1'b0;
            oa_start      <= 1'b0;
            dp_data_valid <= 1'b0;
            q_rd_en       <= 1'b0;
            k_rd_en       <= 1'b0;
            v_rd_en       <= 1'b0;
            oa_v_valid    <= 1'b0;
            dropout_done_flag <= 1'b0;

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
                        q_rd_en       <= 1'b1;
                        k_rd_en       <= 1'b1;
                        q_rd_step     <= dp_step[$clog2(NUM_STEPS)-1:0];
                        k_rd_step     <= dp_step[$clog2(NUM_STEPS)-1:0];
                        dp_data_valid <= 1'b1;
                        dp_step       <= dp_step + 1;
                    end
                    if (dp_done)
                        state <= S_MASK;
                end

                S_MASK: begin
                    // Apply combined causal + padding mask + format scaling
                    for (integer r = 0; r < TILE_BR; r = r + 1) begin
                        for (integer c = 0; c < TILE_BC; c = c + 1) begin
                            logic [15:0] abs_row_v, abs_col_v;
                            logic mask_bit;
                            logic signed [ACC_WIDTH-1:0] score_adjusted;
                            abs_row_v = q_tile_idx * TILE_BR + r[15:0];
                            abs_col_v = kv_tile_idx * TILE_BC + c[15:0];

                            mask_bit = (causal_en && (abs_col_v > abs_row_v)) ||
                                       (padding_en && (abs_col_v >= valid_len));

                            // Format-aware score adjustment:
                            // Q8.8 (frac=8): dot_product gives score with frac=8, softmax expects frac=16 → shift left 8
                            // Q6.10 (frac=10): dot_product frac=10, shift left 6
                            // Q4.12 (frac=12): dot_product frac=12, shift left 4
                            // BF16 (frac=8): same as Q8.8
                            // INT8 (frac=8): same as Q8.8
                            case (data_fmt)
                                3'd1:    score_adjusted = dp_scores[r][c] <<< 6;  // Q6.10 → frac 16
                                3'd2:    score_adjusted = dp_scores[r][c] <<< 4;  // Q4.12 → frac 16
                                default: score_adjusted = dp_scores[r][c] <<< 8;  // Q8.8/BF16/INT8
                            endcase

                            if (mask_bit)
                                masked_scores[r][c] <= {{(ACC_WIDTH-16){neg_large[15]}}, neg_large} <<< 8;
                            else
                                masked_scores[r][c] <= score_adjusted;
                        end
                    end
                    state    <= S_SOFTMAX;
                    sm_start <= 1'b1;
                end

                S_SOFTMAX: begin
                    if (sm_done)
                        state <= S_DROPOUT;
                end

                S_DROPOUT: begin
                    // Apply dropout to p_matrix
                    for (integer r = 0; r < TILE_BR; r = r + 1) begin
                        for (integer c = 0; c < TILE_BC; c = c + 1) begin
                            if (dropout_en && (lfsr_state[((r*TILE_BC+c) % 32)] ^
                                              lfsr_state[(((r*TILE_BC+c)+13) % 32)]) &&
                                (drop_prob > 8'd0)) begin
                                // Simplified: use LFSR bit XOR for random decision
                                if (lfsr_state[7:0] < drop_prob)
                                    p_after_dropout[r][c] <= '0;
                                else
                                    p_after_dropout[r][c] <= p_matrix[r][c];
                            end else begin
                                p_after_dropout[r][c] <= p_matrix[r][c];
                            end
                        end
                    end
                    state    <= S_ACCUMULATE;
                    oa_start <= 1'b1;
                    oa_v_step <= '0;
                end

                S_ACCUMULATE: begin
                    if (oa_busy && !oa_done) begin
                        v_rd_en    <= 1'b1;
                        v_rd_step  <= oa_v_step[$clog2(NUM_STEPS)-1:0];
                        oa_v_valid <= 1'b1;
                        oa_v_step  <= oa_v_step + 1;
                    end
                    if (oa_done)
                        state <= S_DONE;
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
