// ============================================================
// Online Softmax Unit
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
    input  logic signed [SCORE_WIDTH-1:0] m_old [TILE_BR-1:0],
    input  logic [SCORE_WIDTH-1:0]        l_old [TILE_BR-1:0],
    output logic signed [SCORE_WIDTH-1:0] m_new [TILE_BR-1:0],
    output logic [SCORE_WIDTH-1:0]        l_new [TILE_BR-1:0],
    output logic [EXP_WIDTH-1:0]          p_matrix [TILE_BR-1:0][TILE_BC-1:0],
    output logic [EXP_WIDTH-1:0]          rescale [TILE_BR-1:0],
    output logic                          results_valid
);

    typedef enum logic [3:0] {
        S_IDLE,
        S_ROW_MAX,
        S_EXP_START,
        S_EXP_WAIT,
        S_SUM,
        S_RESCALE_START,
        S_RESCALE_WAIT,
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
        .valid_in(exp_valid_in), .x_in(exp_x_in),
        .valid_out(exp_valid_out), .exp_out(exp_y_out)
    );

    // Counters for sequential processing
    logic [$clog2(TILE_BR):0] cur_row;
    logic [$clog2(TILE_BC):0] cur_col;
    logic [$clog2(TILE_BR):0] out_row;
    logic [$clog2(TILE_BC):0] out_col;
    logic [7:0] wait_cnt;

    // Balanced 16-way row max tree.
    logic signed [SCORE_WIDTH-1:0] row_max_l1 [TILE_BR-1:0][7:0];
    logic signed [SCORE_WIDTH-1:0] row_max_l2 [TILE_BR-1:0][3:0];
    logic signed [SCORE_WIDTH-1:0] row_max_l3 [TILE_BR-1:0][1:0];
    logic signed [SCORE_WIDTH-1:0] row_max_balanced [TILE_BR-1:0];
    logic [SCORE_WIDTH-1:0] row_sum [TILE_BR-1:0];

    generate
        for (genvar mr = 0; mr < TILE_BR; mr++) begin : gen_row_max
            for (genvar mc1 = 0; mc1 < 8; mc1++) begin : gen_row_max_l1
                assign row_max_l1[mr][mc1] =
                    (scores[mr][2*mc1] > scores[mr][2*mc1 + 1]) ?
                    scores[mr][2*mc1] : scores[mr][2*mc1 + 1];
            end
            for (genvar mc2 = 0; mc2 < 4; mc2++) begin : gen_row_max_l2
                assign row_max_l2[mr][mc2] =
                    (row_max_l1[mr][2*mc2] > row_max_l1[mr][2*mc2 + 1]) ?
                    row_max_l1[mr][2*mc2] : row_max_l1[mr][2*mc2 + 1];
            end
            for (genvar mc3 = 0; mc3 < 2; mc3++) begin : gen_row_max_l3
                assign row_max_l3[mr][mc3] =
                    (row_max_l2[mr][2*mc3] > row_max_l2[mr][2*mc3 + 1]) ?
                    row_max_l2[mr][2*mc3] : row_max_l2[mr][2*mc3 + 1];
            end
            assign row_max_balanced[mr] =
                (row_max_l3[mr][0] > row_max_l3[mr][1]) ?
                row_max_l3[mr][0] : row_max_l3[mr][1];
        end
    endgenerate

    function automatic [SCORE_WIDTH-1:0] scale_l_value(
        input logic [SCORE_WIDTH-1:0] old_l,
        input logic [EXP_WIDTH-1:0] factor
    );
        logic [SCORE_WIDTH+EXP_WIDTH-1:0] product;
        begin
            product = old_l * factor;
            scale_l_value = SCORE_WIDTH'(product >> FRAC_BITS);
        end
    endfunction

    function automatic logic [SCORE_WIDTH-1:0] row_sum16(
        input logic [EXP_WIDTH-1:0] row_probs [TILE_BC-1:0]
    );
        logic [SCORE_WIDTH-1:0] level1 [0:7];
        logic [SCORE_WIDTH-1:0] level2 [0:3];
        logic [SCORE_WIDTH-1:0] level3 [0:1];
        begin
            for (int i = 0; i < 8; i++)
                level1[i] = SCORE_WIDTH'(row_probs[2*i]) + SCORE_WIDTH'(row_probs[2*i + 1]);
            for (int i = 0; i < 4; i++)
                level2[i] = level1[2*i] + level1[2*i + 1];
            for (int i = 0; i < 2; i++)
                level3[i] = level2[2*i] + level2[2*i + 1];
            row_sum16 = level3[0] + level3[1];
        end
    endfunction

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
                        if (first_tile)
                            m_new[r] <= row_max_balanced[r];
                        else
                            m_new[r] <= (row_max_balanced[r] > m_old[r]) ? row_max_balanced[r] : m_old[r];
                    end
                    cur_row  <= '0;
                    cur_col  <= '0;
                    out_row  <= '0;
                    out_col  <= '0;
                    wait_cnt <= '0;
                    state    <= S_EXP_START;
                end

                // Pipeline exp: feed one element per cycle, collect results after 3-cycle delay
                S_EXP_START: begin
                    if (cur_row < TILE_BR) begin
                        exp_valid_in <= 1'b1;
                        exp_x_in     <= scores[cur_row][cur_col] - m_new[cur_row];
                        // Advance input pointer
                        if (cur_col == TILE_BC - 1) begin
                            cur_col <= '0;
                            cur_row <= cur_row + 1;
                        end else begin
                            cur_col <= cur_col + 1;
                        end
                        wait_cnt <= wait_cnt + 1;  // track total inputs fed
                        state <= S_EXP_START;       // stay in this state!
                    end else begin
                        exp_valid_in <= 1'b0;
                        // All inputs fed, wait for last outputs
                        state <= S_EXP_WAIT;
                    end

                    // Collect exp outputs (arrive 3 cycles after input)
                    if (exp_valid_out) begin
                        // output_row/col tracks which element this output belongs to
                        p_matrix[out_row][out_col] <= exp_y_out;
                        if (out_col == TILE_BC - 1) begin
                            out_col <= '0;
                            out_row <= out_row + 1;
                        end else begin
                            out_col <= out_col + 1;
                        end
                    end
                end

                // Drain remaining exp pipeline outputs
                S_EXP_WAIT: begin
                    if (exp_valid_out) begin
                        p_matrix[out_row][out_col] <= exp_y_out;
                        if (out_col == TILE_BC - 1) begin
                            out_col <= '0;
                            out_row <= out_row + 1;
                        end else begin
                            out_col <= out_col + 1;
                        end
                    end
                    // All outputs collected when out_row reaches TILE_BR
                    if (out_row >= TILE_BR && !exp_valid_out)
                        state <= S_SUM;
                end

                // Compute row sums for this K/V tile.
                S_SUM: begin
                    for (int r = 0; r < TILE_BR; r++) begin
                        logic [SCORE_WIDTH-1:0] rsum;
                        rsum = row_sum16(p_matrix[r]);
                        row_sum[r] <= rsum;
                        if (first_tile) begin
                            l_new[r]   <= rsum;
                            rescale[r] <= '0;
                        end
                    end
                    if (first_tile) begin
                        state <= S_DONE;
                    end else begin
                        cur_row <= '0;
                        out_row <= '0;
                        state   <= S_RESCALE_START;
                    end
                end

                // Reuse the exp unit to compute exp(m_old - m_new) per row.
                S_RESCALE_START: begin
                    if (cur_row < TILE_BR) begin
                        exp_valid_in <= 1'b1;
                        exp_x_in     <= m_old[cur_row] - m_new[cur_row];
                        cur_row      <= cur_row + 1;
                    end else begin
                        exp_valid_in <= 1'b0;
                        state        <= S_RESCALE_WAIT;
                    end

                    if (exp_valid_out) begin
                        rescale[out_row] <= exp_y_out;
                        l_new[out_row]   <= scale_l_value(l_old[out_row], exp_y_out) + row_sum[out_row];
                        out_row          <= out_row + 1;
                    end
                end

                S_RESCALE_WAIT: begin
                    if (exp_valid_out) begin
                        rescale[out_row] <= exp_y_out;
                        l_new[out_row]   <= scale_l_value(l_old[out_row], exp_y_out) + row_sum[out_row];
                        out_row          <= out_row + 1;
                    end
                    if (out_row >= TILE_BR && !exp_valid_out)
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
