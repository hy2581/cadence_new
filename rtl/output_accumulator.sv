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
    input  logic [ACC_WIDTH-1:0]          rescale [TILE_BR-1:0],

    // l_new per row (for final normalization)
    input  logic [ACC_WIDTH-1:0]          l_values [TILE_BR-1:0],

    // Output O tile: B_r × d, available when done
    output logic signed [DATA_WIDTH-1:0]  o_out [TILE_BR-1:0][HEAD_DIM-1:0],
    output logic                          o_valid
);

    localparam NUM_V_STEPS = HEAD_DIM / PAR_COLS;  // 64/8 = 8

    // O accumulator (B_r × d, ACC_WIDTH bits)
    logic signed [ACC_WIDTH-1:0] o_acc [TILE_BR-1:0][HEAD_DIM-1:0];

    typedef enum logic [2:0] {
        S_IDLE,
        S_RESCALE,
        S_PV_MULT,
        S_NORMALIZE,
        S_DONE
    } state_t;

    state_t state;
    logic [$clog2(NUM_V_STEPS):0] v_step;
    logic [$clog2(HEAD_DIM):0] col_base;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            done    <= 1'b0;
            busy    <= 1'b0;
            o_valid <= 1'b0;
            v_step  <= '0;
            col_base <= '0;
            for (int r = 0; r < TILE_BR; r++)
                for (int j = 0; j < HEAD_DIM; j++)
                    o_acc[r][j] <= '0;
        end else begin
            done    <= 1'b0;
            o_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= first_tile ? S_PV_MULT : S_RESCALE;
                        busy  <= 1'b1;
                        v_step <= '0;
                        col_base <= '0;
                        if (first_tile) begin
                            for (int r = 0; r < TILE_BR; r++)
                                for (int j = 0; j < HEAD_DIM; j++)
                                    o_acc[r][j] <= '0;
                        end
                    end
                end

                // Rescale existing O: O_old *= rescale / l_new
                S_RESCALE: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        for (int j = 0; j < HEAD_DIM; j++) begin
                            if (l_values[r] != '0)
                                o_acc[r][j] <= (o_acc[r][j] * signed'({1'b0, rescale[r]})) >>> FRAC_BITS;
                            else
                                o_acc[r][j] <= '0;
                        end
                    end
                    state    <= S_PV_MULT;
                    v_step   <= '0;
                    col_base <= '0;
                end

                // P · V accumulation: streamed over PAR_COLS columns per cycle
                S_PV_MULT: begin
                    if (v_valid) begin
                        for (int r = 0; r < TILE_BR; r++) begin
                            for (int p = 0; p < PAR_COLS; p++) begin
                                logic signed [ACC_WIDTH-1:0] pv_sum;
                                pv_sum = '0;
                                for (int c = 0; c < TILE_BC; c++) begin
                                    pv_sum = pv_sum +
                                        (signed'({1'b0, p_matrix[r][c]}) * ACC_WIDTH'(v_data[c][p])) >>> FRAC_BITS;
                                end
                                o_acc[r][col_base + p] <= o_acc[r][col_base + p] + pv_sum;
                            end
                        end
                        col_base <= col_base + PAR_COLS;
                        v_step   <= v_step + 1;
                        if (v_step == NUM_V_STEPS - 1)
                            state <= last_tile ? S_NORMALIZE : S_DONE;
                    end
                end

                // Final normalization: O /= l
                S_NORMALIZE: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        for (int j = 0; j < HEAD_DIM; j++) begin
                            logic signed [ACC_WIDTH-1:0] normalized;
                            if (l_values[r] != '0)
                                normalized = (o_acc[r][j] << FRAC_BITS) /
                                             signed'({1'b0, l_values[r]});
                            else
                                normalized = '0;
                            // Truncate to Q8.8
                            o_out[r][j] <= DATA_WIDTH'(normalized >>> (FRAC_BITS - 8));
                        end
                    end
                    state <= S_DONE;
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
