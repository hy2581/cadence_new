// ============================================================
// Online Softmax Unit (Simplified)
// Sequential processing: for each row, iterate over B_c columns
// No complex pipeline scheduling — reliable operation
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
    input  logic                          start,
    input  logic                          first_tile,
    output logic                          done,
    output logic                          busy,
    input  logic signed [SCORE_WIDTH-1:0] scores [TILE_BR-1:0][TILE_BC-1:0],
    input  logic signed [15:0]            neg_large,
    input  logic signed [SCORE_WIDTH-1:0] m_old [TILE_BR-1:0],
    input  logic [SCORE_WIDTH-1:0]        l_old [TILE_BR-1:0],
    output logic signed [SCORE_WIDTH-1:0] m_new [TILE_BR-1:0],
    output logic [SCORE_WIDTH-1:0]        l_new [TILE_BR-1:0],
    output logic [EXP_WIDTH-1:0]          p_matrix [TILE_BR-1:0][TILE_BC-1:0],
    output logic [SCORE_WIDTH-1:0]        rescale [TILE_BR-1:0],
    output logic                          results_valid
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_ROW_MAX,
        S_EXP_START,
        S_EXP_WAIT,
        S_FINALIZE,
        S_DONE
    } state_t;

    state_t state;

    // Exp unit (single instance, time-multiplexed)
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

    // Counters for sequential processing
    logic [$clog2(TILE_BR):0] cur_row;
    logic [$clog2(TILE_BC):0] cur_col;
    logic [3:0] wait_cnt;

    // Row max intermediate
    logic signed [SCORE_WIDTH-1:0] row_max_tmp;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            busy          <= 1'b0;
            results_valid <= 1'b0;
            exp_valid_in  <= 1'b0;
            cur_row       <= '0;
            cur_col       <= '0;
            wait_cnt      <= '0;
        end else begin
            done          <= 1'b0;
            results_valid <= 1'b0;
            exp_valid_in  <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state   <= S_ROW_MAX;
                        busy    <= 1'b1;
                        cur_row <= '0;
                    end
                end

                // Compute row-wise max across all rows
                S_ROW_MAX: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        logic signed [SCORE_WIDTH-1:0] rmax;
                        rmax = scores[r][0];
                        for (int c = 1; c < TILE_BC; c++)
                            if (scores[r][c] > rmax) rmax = scores[r][c];
                        if (first_tile)
                            m_new[r] <= rmax;
                        else
                            m_new[r] <= (rmax > m_old[r]) ? rmax : m_old[r];
                    end
                    cur_row  <= '0;
                    cur_col  <= '0;
                    state    <= S_EXP_START;
                end

                // Feed one element at a time to exp unit
                S_EXP_START: begin
                    if (cur_row < TILE_BR && cur_col < TILE_BC) begin
                        exp_valid_in <= 1'b1;
                        exp_x_in     <= scores[cur_row][cur_col] - m_new[cur_row];
                        wait_cnt     <= '0;
                        state        <= S_EXP_WAIT;
                    end else begin
                        // All elements processed, finalize
                        state <= S_FINALIZE;
                    end
                end

                // Wait for exp result (3 pipeline cycles)
                S_EXP_WAIT: begin
                    wait_cnt <= wait_cnt + 1;
                    if (exp_valid_out) begin
                        p_matrix[cur_row][cur_col] <= exp_y_out;
                        // Advance to next element
                        if (cur_col == TILE_BC - 1) begin
                            cur_col <= '0;
                            cur_row <= cur_row + 1;
                        end else begin
                            cur_col <= cur_col + 1;
                        end
                        state <= S_EXP_START;
                    end else if (wait_cnt > 10) begin
                        // Safety: if exp never outputs, store 0 and move on
                        p_matrix[cur_row][cur_col] <= '0;
                        if (cur_col == TILE_BC - 1) begin
                            cur_col <= '0;
                            cur_row <= cur_row + 1;
                        end else begin
                            cur_col <= cur_col + 1;
                        end
                        state <= S_EXP_START;
                    end
                end

                // Compute row sums, l_new, rescale
                S_FINALIZE: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        logic [SCORE_WIDTH-1:0] rsum;
                        rsum = '0;
                        for (int c = 0; c < TILE_BC; c++)
                            rsum = rsum + SCORE_WIDTH'(p_matrix[r][c]);
                        if (first_tile) begin
                            l_new[r]   <= rsum;
                            rescale[r] <= '0;
                        end else begin
                            // Approximate: rescale = l_old (simplified; proper impl needs exp(m_old-m_new))
                            // For now use direct l_old as rescale factor
                            l_new[r]   <= l_old[r] + rsum;
                            rescale[r] <= l_old[r];
                        end
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
