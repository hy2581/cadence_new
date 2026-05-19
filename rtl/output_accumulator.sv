// ============================================================
// Output Accumulator
// Accumulates O = rescale * O_old + P · V for FlashAttention
// For each KV-tile iteration:
//   O_new[r][j] = rescale[r] * O_old[r][j] + Σ_c P[r][c] * V[c][j]
// After last KV-tile: normalize O by dividing by l (done externally or here)
// ============================================================
module output_accumulator #(
    parameter TILE_BR    = 4,
    parameter TILE_BC    = 16,
    parameter HEAD_DIM   = 64,
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 40,
    parameter EXP_WIDTH  = 24,
    parameter FRAC_BITS  = 16,
    parameter PAR_COLS   = 8    // parallel V columns processed per cycle
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // Control
    input  logic                          start,
    input  logic                          first_tile,
    input  logic                          last_tile,      // final KV tile → produce output
    output logic                          done,
    output logic                          busy,

    // P matrix from softmax (B_r × B_c)
    input  logic [EXP_WIDTH-1:0]          p_matrix [TILE_BR-1:0][TILE_BC-1:0],

    // V tile data: B_c rows × d cols, streamed PAR_COLS per cycle
    input  logic signed [DATA_WIDTH-1:0]  v_data [TILE_BC-1:0][PAR_COLS-1:0],
    input  logic                          v_valid,

    // Rescale factor per row (from softmax)
    input  logic [EXP_WIDTH-1:0]          rescale [TILE_BR-1:0],

    // l_new per row (for final normalization)
    input  logic [ACC_WIDTH-1:0]          l_values [TILE_BR-1:0],

    // Output O tile: B_r × d, available when done
    output logic signed [DATA_WIDTH-1:0]  o_out [TILE_BR-1:0][HEAD_DIM-1:0],
    output logic                          o_valid
);

    localparam NUM_V_STEPS = HEAD_DIM / PAR_COLS;  // 64/PAR_COLS
    localparam RESCALE_COLS = 4;
    localparam DATA_FRAC_BITS = 8;
    localparam RECIP_FRAC_BITS = 30;
    localparam RECIP_QUOT_BITS = 16;
    localparam SUM_L1_COUNT = (TILE_BC + 1) / 2;
    localparam SUM_L2_COUNT = (SUM_L1_COUNT + 1) / 2;
    localparam SUM_L3_COUNT = (SUM_L2_COUNT + 1) / 2;
    localparam SUM_L4_COUNT = (SUM_L3_COUNT + 1) / 2;
    localparam RESCALE_PRODUCT_WIDTH = ACC_WIDTH + EXP_WIDTH + 1;
    localparam RECIP_NUM_WIDTH = ACC_WIDTH + RECIP_QUOT_BITS;
    localparam NORM_PRODUCT_WIDTH = ACC_WIDTH + RECIP_QUOT_BITS + 1;
    localparam logic [RECIP_NUM_WIDTH-1:0] RECIP_NUMERATOR =
        ({{(RECIP_NUM_WIDTH-1){1'b0}}, 1'b1} << RECIP_FRAC_BITS);
    localparam signed [NORM_PRODUCT_WIDTH-1:0] DATA_MAX =
        {{(NORM_PRODUCT_WIDTH-DATA_WIDTH){1'b0}}, 1'b0, {(DATA_WIDTH-1){1'b1}}};
    localparam signed [NORM_PRODUCT_WIDTH-1:0] DATA_MIN =
        {{(NORM_PRODUCT_WIDTH-DATA_WIDTH){1'b1}}, 1'b1, {(DATA_WIDTH-1){1'b0}}};

    // O accumulator (B_r × d, ACC_WIDTH bits)
    logic signed [ACC_WIDTH-1:0] o_acc [TILE_BR-1:0][HEAD_DIM-1:0];

    function automatic logic signed [ACC_WIDTH-1:0] scale_accumulator(
        input logic signed [ACC_WIDTH-1:0] acc,
        input logic [EXP_WIDTH-1:0] factor
    );
        logic signed [RESCALE_PRODUCT_WIDTH-1:0] product;
        logic signed [ACC_WIDTH-1:0] shifted;
        begin
            product = acc * $signed({1'b0, factor});
            shifted = product >>> FRAC_BITS;
            scale_accumulator = shifted;
        end
    endfunction

    function automatic logic signed [ACC_WIDTH-1:0] prob_times_value(
        input logic [EXP_WIDTH-1:0] prob,
        input logic signed [DATA_WIDTH-1:0] value
    );
        logic signed [EXP_WIDTH+DATA_WIDTH:0] product;
        logic signed [ACC_WIDTH-1:0] shifted;
        begin
            product = $signed({1'b0, prob}) * value;
            shifted = product >>> DATA_FRAC_BITS;
            prob_times_value = shifted;
        end
    endfunction

    function automatic logic signed [ACC_WIDTH-1:0] weighted_value_sum(
        input logic [EXP_WIDTH-1:0] probs [TILE_BC-1:0],
        input logic signed [DATA_WIDTH-1:0] values [TILE_BC-1:0]
    );
        logic signed [ACC_WIDTH-1:0] term [TILE_BC-1:0];
        logic signed [ACC_WIDTH-1:0] level1 [SUM_L1_COUNT-1:0];
        logic signed [ACC_WIDTH-1:0] level2 [SUM_L2_COUNT-1:0];
        logic signed [ACC_WIDTH-1:0] level3 [SUM_L3_COUNT-1:0];
        logic signed [ACC_WIDTH-1:0] level4 [SUM_L4_COUNT-1:0];
        begin
            for (int i = 0; i < TILE_BC; i++) begin
                term[i] = prob_times_value(probs[i], values[i]);
            end
            for (int i = 0; i < SUM_L1_COUNT; i++) begin
                if ((2 * i + 1) < TILE_BC)
                    level1[i] = term[2 * i] + term[2 * i + 1];
                else
                    level1[i] = term[2 * i];
            end
            for (int i = 0; i < SUM_L2_COUNT; i++) begin
                if ((2 * i + 1) < SUM_L1_COUNT)
                    level2[i] = level1[2 * i] + level1[2 * i + 1];
                else
                    level2[i] = level1[2 * i];
            end
            for (int i = 0; i < SUM_L3_COUNT; i++) begin
                if ((2 * i + 1) < SUM_L2_COUNT)
                    level3[i] = level2[2 * i] + level2[2 * i + 1];
                else
                    level3[i] = level2[2 * i];
            end
            for (int i = 0; i < SUM_L4_COUNT; i++) begin
                if ((2 * i + 1) < SUM_L3_COUNT)
                    level4[i] = level3[2 * i] + level3[2 * i + 1];
                else
                    level4[i] = level3[2 * i];
            end
            weighted_value_sum = level4[0];
        end
    endfunction

    function automatic logic signed [DATA_WIDTH-1:0] saturate_to_data(
        input logic signed [NORM_PRODUCT_WIDTH-1:0] value
    );
        begin
            if (value > DATA_MAX)
                saturate_to_data = {1'b0, {(DATA_WIDTH-1){1'b1}}};
            else if (value < DATA_MIN)
                saturate_to_data = {1'b1, {(DATA_WIDTH-1){1'b0}}};
            else
                saturate_to_data = value[DATA_WIDTH-1:0];
        end
    endfunction

    typedef enum logic [2:0] {
        S_IDLE,
        S_RESCALE,
        S_PV_MULT,
        S_RECIP_PREP,
        S_RECIP_DIV,
        S_NORMALIZE_MUL,
        S_NORMALIZE_WRITE,
        S_DONE
    } state_t;

    state_t state;
    logic [$clog2(NUM_V_STEPS):0] v_step;
    logic [$clog2(HEAD_DIM):0] col_base;
    logic [$clog2(HEAD_DIM):0] rescale_col_base;
    logic [$clog2(HEAD_DIM):0] norm_col;
    logic [$clog2(TILE_BR):0] recip_row;
    logic [RECIP_QUOT_BITS-1:0] recip_values [TILE_BR-1:0];
    logic [RECIP_NUM_WIDTH-1:0] recip_remaining;
    logic [RECIP_NUM_WIDTH-1:0] recip_denom_shifted;
    logic [RECIP_QUOT_BITS-1:0] recip_quotient;
    logic [$clog2(RECIP_QUOT_BITS):0] recip_bit;
    logic signed [NORM_PRODUCT_WIDTH-1:0] norm_scaled [TILE_BR-1:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            done    <= 1'b0;
            busy    <= 1'b0;
            o_valid <= 1'b0;
            v_step  <= '0;
            col_base <= '0;
            rescale_col_base <= '0;
            norm_col <= '0;
            recip_row <= '0;
            recip_remaining <= '0;
            recip_denom_shifted <= '0;
            recip_quotient <= '0;
            recip_bit <= '0;
            for (int r = 0; r < TILE_BR; r++)
                for (int j = 0; j < HEAD_DIM; j++)
                    o_acc[r][j] <= '0;
            for (int r = 0; r < TILE_BR; r++)
                recip_values[r] <= '0;
            for (int r = 0; r < TILE_BR; r++)
                norm_scaled[r] <= '0;
        end else begin
            done    <= 1'b0;
            o_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= first_tile ? S_PV_MULT : S_RESCALE;
                        busy  <= first_tile;
                        v_step <= '0;
                        col_base <= '0;
                        rescale_col_base <= '0;
                        norm_col <= '0;
                        recip_row <= '0;
                        if (first_tile) begin
                            for (int r = 0; r < TILE_BR; r++)
                                for (int j = 0; j < HEAD_DIM; j++)
                                    o_acc[r][j] <= '0;
                        end
                    end
                end

                // Rescale the unnormalized numerator with exp(m_old - m_new).
                S_RESCALE: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        for (int j = 0; j < RESCALE_COLS; j++) begin
                            if (l_values[r] != '0)
                                o_acc[r][rescale_col_base + j] <=
                                    scale_accumulator(o_acc[r][rescale_col_base + j],
                                                      rescale[r]);
                            else
                                o_acc[r][rescale_col_base + j] <= '0;
                        end
                    end
                    if (rescale_col_base == HEAD_DIM - RESCALE_COLS) begin
                        state    <= S_PV_MULT;
                        busy     <= 1'b1;
                        v_step   <= '0;
                        col_base <= '0;
                        rescale_col_base <= '0;
                    end else begin
                        rescale_col_base <= rescale_col_base + RESCALE_COLS;
                    end
                end

                // P · V accumulation: streamed over PAR_COLS columns per cycle
                S_PV_MULT: begin
                    if (v_valid) begin
                        for (int r = 0; r < TILE_BR; r++) begin
                            for (int p = 0; p < PAR_COLS; p++) begin
                                logic signed [ACC_WIDTH-1:0] pv_sum;
                                logic [EXP_WIDTH-1:0] prob_row [TILE_BC-1:0];
                                logic signed [DATA_WIDTH-1:0] value_col [TILE_BC-1:0];
                                for (int c = 0; c < TILE_BC; c++) begin
                                    prob_row[c] = p_matrix[r][c];
                                    value_col[c] = v_data[c][p];
                                end
                                pv_sum = weighted_value_sum(prob_row, value_col);
                                o_acc[r][col_base + p] <= o_acc[r][col_base + p] + pv_sum;
                            end
                        end
                        col_base <= col_base + PAR_COLS;
                        v_step   <= v_step + 1;
                        if (v_step == NUM_V_STEPS - 1) begin
                            norm_col <= '0;
                            recip_row <= '0;
                            busy <= 1'b0;
                            state <= last_tile ? S_RECIP_PREP : S_DONE;
                        end
                    end
                end

                // Compute one reciprocal per row, then reuse it for all columns.
                // recip ~= floor(2^RECIP_FRAC_BITS / l_values[row]).
                S_RECIP_PREP: begin
                    if (l_values[recip_row] == '0) begin
                        recip_values[recip_row] <= '0;
                        if (recip_row == TILE_BR - 1) begin
                            norm_col <= '0;
                            state <= S_NORMALIZE_MUL;
                        end else begin
                            recip_row <= recip_row + 1;
                        end
                    end else begin
                        recip_remaining <= RECIP_NUMERATOR;
                        recip_denom_shifted <=
                            {{(RECIP_NUM_WIDTH-ACC_WIDTH){1'b0}}, l_values[recip_row]} << (RECIP_QUOT_BITS - 1);
                        recip_quotient <= '0;
                        recip_bit <= RECIP_QUOT_BITS - 1;
                        state <= S_RECIP_DIV;
                    end
                end

                S_RECIP_DIV: begin
                    logic [RECIP_QUOT_BITS-1:0] next_quotient;
                    logic [RECIP_NUM_WIDTH-1:0] next_remaining;

                    next_quotient = recip_quotient;
                    next_remaining = recip_remaining;
                    if (recip_remaining >= recip_denom_shifted) begin
                        next_remaining = recip_remaining - recip_denom_shifted;
                        next_quotient[recip_bit] = 1'b1;
                    end

                    recip_remaining <= next_remaining;
                    recip_quotient <= next_quotient;
                    recip_denom_shifted <= recip_denom_shifted >> 1;

                    if (recip_bit == 0) begin
                        recip_values[recip_row] <= next_quotient;
                        if (recip_row == TILE_BR - 1) begin
                            norm_col <= '0;
                            state <= S_NORMALIZE_MUL;
                        end else begin
                            recip_row <= recip_row + 1;
                            state <= S_RECIP_PREP;
                        end
                    end else begin
                        recip_bit <= recip_bit - 1;
                    end
                end

                S_NORMALIZE_MUL: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        logic signed [NORM_PRODUCT_WIDTH-1:0] product;
                        product = o_acc[r][norm_col] * $signed({1'b0, recip_values[r]});
                        norm_scaled[r] <= product >>> (RECIP_FRAC_BITS - DATA_FRAC_BITS);
                    end
                    state <= S_NORMALIZE_WRITE;
                end

                S_NORMALIZE_WRITE: begin
                    for (int r = 0; r < TILE_BR; r++)
                        o_out[r][norm_col] <= saturate_to_data(norm_scaled[r]);
                    if (norm_col == HEAD_DIM - 1)
                        state <= S_DONE;
                    else begin
                        norm_col <= norm_col + 1;
                        state <= S_NORMALIZE_MUL;
                    end
                end

                S_DONE: begin
                    o_valid <= last_tile;
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    state   <= S_IDLE;
                end
            endcase
        end
    end

endmodule
