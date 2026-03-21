// ============================================================
// Online Softmax Unit
// Implements the online (streaming) softmax for FlashAttention:
//   For each row r in [0, B_r):
//     1. m_new = max(m_old, rowmax(S[r][0:B_c]))
//     2. P[r][c] = exp(S[r][c] - m_new)  for c in [0, B_c)
//     3. l_new = l_old * exp(m_old - m_new) + rowsum(P[r][:])
//     4. rescale = l_old * exp(m_old - m_new) / l_new
//   Outputs: P matrix (B_r x B_c), l_new, m_new, rescale per row
// ============================================================
module online_softmax_unit #(
    parameter TILE_BR     = 4,
    parameter TILE_BC     = 16,
    parameter SCORE_WIDTH = 40,
    parameter EXP_WIDTH   = 24,
    parameter FRAC_BITS   = 16
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // Control
    input  logic                          start,
    input  logic                          first_tile,      // 1 if this is the first KV tile (init m,l)
    output logic                          done,
    output logic                          busy,

    // Input scores from dot-product (after causal mask applied)
    input  logic signed [SCORE_WIDTH-1:0] scores [TILE_BR-1:0][TILE_BC-1:0],
    input  logic signed [15:0]            neg_large,

    // State: running m, l per row (input from previous iteration)
    input  logic signed [SCORE_WIDTH-1:0] m_old [TILE_BR-1:0],
    input  logic [SCORE_WIDTH-1:0]        l_old [TILE_BR-1:0],

    // Outputs
    output logic signed [SCORE_WIDTH-1:0] m_new [TILE_BR-1:0],
    output logic [SCORE_WIDTH-1:0]        l_new [TILE_BR-1:0],
    output logic [EXP_WIDTH-1:0]          p_matrix [TILE_BR-1:0][TILE_BC-1:0],
    output logic [SCORE_WIDTH-1:0]        rescale [TILE_BR-1:0],  // l_old * exp(m_old - m_new) / l_new
    output logic                          results_valid
);

    // FSM
    typedef enum logic [2:0] {
        S_IDLE,
        S_ROW_MAX,
        S_EXP_COMPUTE,
        S_ROW_SUM,
        S_RESCALE,
        S_DONE
    } state_t;

    state_t state;
    logic [$clog2(TILE_BR):0] row_cnt;

    // Internal storage
    logic signed [SCORE_WIDTH-1:0] row_max [TILE_BR-1:0];
    logic [EXP_WIDTH-1:0]          exp_vals [TILE_BR-1:0][TILE_BC-1:0];
    logic [SCORE_WIDTH-1:0]        row_sum  [TILE_BR-1:0];
    logic [EXP_WIDTH-1:0]          exp_m_diff [TILE_BR-1:0];  // exp(m_old - m_new)

    // Exp unit interface (shared, time-multiplexed)
    logic                          exp_valid_in, exp_valid_out;
    logic signed [SCORE_WIDTH-1:0] exp_x_in;
    logic [EXP_WIDTH-1:0]          exp_y_out;

    exp_approx_unit #(
        .IN_WIDTH(SCORE_WIDTH), .FRAC_IN(FRAC_BITS),
        .OUT_WIDTH(EXP_WIDTH), .FRAC_OUT(FRAC_BITS)
    ) u_exp (
        .clk(clk), .rst_n(rst_n),
        .valid_in(exp_valid_in), .x_in(exp_x_in), .neg_large(neg_large),
        .valid_out(exp_valid_out), .exp_out(exp_y_out)
    );

    // Exp computation state
    logic [$clog2(TILE_BR):0]  exp_row;
    logic [$clog2(TILE_BC):0]  exp_col;
    logic                      exp_phase;  // 0: score exp, 1: m_diff exp
    logic [3:0]                exp_pipe_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            busy          <= 1'b0;
            results_valid <= 1'b0;
            exp_valid_in  <= 1'b0;
            exp_row       <= '0;
            exp_col       <= '0;
            exp_phase     <= 1'b0;
            exp_pipe_cnt  <= '0;
        end else begin
            done          <= 1'b0;
            results_valid <= 1'b0;
            exp_valid_in  <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_ROW_MAX;
                        busy  <= 1'b1;
                    end
                end

                // Stage 1: compute row-wise max, then update m_new
                S_ROW_MAX: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        logic signed [SCORE_WIDTH-1:0] rmax;
                        rmax = scores[r][0];
                        for (int c = 1; c < TILE_BC; c++)
                            if (scores[r][c] > rmax)
                                rmax = scores[r][c];
                        row_max[r] <= rmax;
                        if (first_tile)
                            m_new[r] <= rmax;
                        else
                            m_new[r] <= (rmax > m_old[r]) ? rmax : m_old[r];
                    end
                    state    <= S_EXP_COMPUTE;
                    exp_row  <= '0;
                    exp_col  <= '0;
                    exp_phase <= 1'b0;
                    exp_pipe_cnt <= '0;
                end

                // Stage 2: compute exp(score - m_new) for all elements + exp(m_old - m_new)
                S_EXP_COMPUTE: begin
                    if (exp_phase == 1'b0) begin
                        // Feed scores through exp unit
                        if (exp_row < TILE_BR && exp_col < TILE_BC) begin
                            exp_valid_in <= 1'b1;
                            exp_x_in     <= scores[exp_row][exp_col] - m_new[exp_row];
                            if (exp_col == TILE_BC - 1) begin
                                exp_col <= '0;
                                exp_row <= exp_row + 1;
                            end else begin
                                exp_col <= exp_col + 1;
                            end
                        end

                        // Collect exp outputs (3-cycle pipeline delay)
                        if (exp_valid_out) begin
                            logic [$clog2(TILE_BR):0] out_r;
                            logic [$clog2(TILE_BC):0] out_c;
                            // Track output position
                            exp_pipe_cnt <= exp_pipe_cnt + 1;
                            out_r = exp_pipe_cnt / TILE_BC;
                            out_c = exp_pipe_cnt % TILE_BC;
                            if (out_r < TILE_BR)
                                exp_vals[out_r][out_c] <= exp_y_out;
                        end

                        if (exp_row >= TILE_BR && !exp_valid_out && exp_pipe_cnt >= TILE_BR * TILE_BC) begin
                            exp_phase    <= 1'b1;
                            exp_row      <= '0;
                            exp_pipe_cnt <= '0;
                        end
                    end else begin
                        // Compute exp(m_old - m_new) for each row
                        if (exp_row < TILE_BR) begin
                            exp_valid_in <= 1'b1;
                            exp_x_in     <= first_tile ? '0 : (m_old[exp_row] - m_new[exp_row]);
                            exp_row      <= exp_row + 1;
                        end
                        if (exp_valid_out) begin
                            exp_m_diff[exp_pipe_cnt] <= exp_y_out;
                            exp_pipe_cnt <= exp_pipe_cnt + 1;
                        end
                        if (exp_pipe_cnt >= TILE_BR && !exp_valid_out)
                            state <= S_ROW_SUM;
                    end
                end

                // Stage 3: row sums and l_new
                S_ROW_SUM: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        logic [SCORE_WIDTH-1:0] rsum;
                        rsum = '0;
                        for (int c = 0; c < TILE_BC; c++)
                            rsum = rsum + SCORE_WIDTH'(exp_vals[r][c]);
                        row_sum[r] <= rsum;
                        if (first_tile)
                            l_new[r] <= rsum;
                        else
                            l_new[r] <= ((l_old[r] * SCORE_WIDTH'(exp_m_diff[r])) >> FRAC_BITS) + rsum;
                    end
                    state <= S_RESCALE;
                end

                // Stage 4: compute rescale factor
                S_RESCALE: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        if (first_tile)
                            rescale[r] <= '0;
                        else
                            rescale[r] <= (l_old[r] * SCORE_WIDTH'(exp_m_diff[r])) >> FRAC_BITS;
                        for (int c = 0; c < TILE_BC; c++)
                            p_matrix[r][c] <= exp_vals[r][c];
                    end
                    state <= S_DONE;
                end

                S_DONE: begin
                    results_valid <= 1'b1;
                    done          <= 1'b1;
                    busy          <= 1'b0;
                    state         <= S_IDLE;
                end
            endcase
        end
    end

endmodule
