// ============================================================
// Dot-Product Array
// Computes S_ij = Q_tile · K_tile^T for one tile pair
// Input: B_r rows of Q (each d elements), B_c rows of K (each d elements)
// Output: B_r × B_c score values
// Processing: streams d elements over multiple cycles
// ============================================================
module dot_product_array #(
    parameter TILE_BR    = 4,
    parameter TILE_BC    = 16,
    parameter HEAD_DIM   = 64,
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 40,
    parameter PAR_MACS   = 8     // parallel MACs per dot-product per cycle
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // Control
    input  logic                    start,
    output logic                    done,
    output logic                    busy,

    // Q tile data: B_r rows, streamed PAR_MACS elements per cycle
    input  logic signed [DATA_WIDTH-1:0] q_data [TILE_BR-1:0][PAR_MACS-1:0],
    // K tile data: B_c rows, streamed PAR_MACS elements per cycle
    input  logic signed [DATA_WIDTH-1:0] k_data [TILE_BC-1:0][PAR_MACS-1:0],
    input  logic                    data_valid,

    // Scale factor (Q8.8)
    input  logic signed [DATA_WIDTH-1:0] scale,

    // Output scores: B_r × B_c
    output logic signed [ACC_WIDTH-1:0]  scores [TILE_BR-1:0][TILE_BC-1:0],
    output logic                    scores_valid
);

    localparam NUM_STEPS = HEAD_DIM / PAR_MACS;  // 64/PAR_MACS
    localparam SCALE_COLS = 8;

    // Accumulator array
    logic signed [ACC_WIDTH-1:0] acc [TILE_BR-1:0][TILE_BC-1:0];
    logic signed [DATA_WIDTH-1:0] q_data_q [TILE_BR-1:0][PAR_MACS-1:0];
    logic signed [DATA_WIDTH-1:0] k_data_q [TILE_BC-1:0][PAR_MACS-1:0];
    logic data_valid_q;
    logic [$clog2(NUM_STEPS):0] step_cnt;
    logic [$clog2(TILE_BR):0] scale_row;
    logic [$clog2(TILE_BC):0] scale_col_base;

    typedef enum logic [1:0] {
        S_IDLE,
        S_ACCUMULATE,
        S_SCALE,
        S_DONE
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            step_cnt     <= '0;
            scale_row    <= '0;
            scale_col_base <= '0;
            scores_valid <= 1'b0;
            done         <= 1'b0;
            busy         <= 1'b0;
            data_valid_q <= 1'b0;
            for (int r = 0; r < TILE_BR; r++)
                for (int c = 0; c < TILE_BC; c++)
                    acc[r][c] <= '0;
        end else begin
            scores_valid <= 1'b0;
            done         <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state    <= S_ACCUMULATE;
                        step_cnt <= '0;
                        scale_row <= '0;
                        scale_col_base <= '0;
                        busy     <= 1'b1;
                        data_valid_q <= 1'b0;
                        for (int r = 0; r < TILE_BR; r++)
                            for (int c = 0; c < TILE_BC; c++)
                                acc[r][c] <= '0;
                    end
                end

                S_ACCUMULATE: begin
                    if (data_valid) begin
                        for (int r = 0; r < TILE_BR; r++)
                            for (int p = 0; p < PAR_MACS; p++)
                                q_data_q[r][p] <= q_data[r][p];
                        for (int c = 0; c < TILE_BC; c++)
                            for (int p = 0; p < PAR_MACS; p++)
                                k_data_q[c][p] <= k_data[c][p];
                    end

                    if (data_valid_q) begin
                        for (int r = 0; r < TILE_BR; r++) begin
                            for (int c = 0; c < TILE_BC; c++) begin
                                logic signed [ACC_WIDTH-1:0] partial_sum;
                                logic signed [ACC_WIDTH-1:0] product_ext;
                                logic signed [2*DATA_WIDTH-1:0] product;
                                partial_sum = '0;
                                for (int p = 0; p < PAR_MACS; p++) begin
                                    product = q_data_q[r][p] * k_data_q[c][p];
                                    product_ext = product;
                                    partial_sum = partial_sum + product_ext;
                                end
                                acc[r][c] <= acc[r][c] + partial_sum;
                            end
                        end
                        step_cnt <= step_cnt + 1;
                        if (step_cnt == NUM_STEPS - 1) begin
                            scale_row <= '0;
                            scale_col_base <= '0;
                            state <= S_SCALE;
                        end
                    end
                    data_valid_q <= data_valid;
                end

                S_SCALE: begin
                    data_valid_q <= 1'b0;
                    for (int c = 0; c < SCALE_COLS; c++) begin
                        logic signed [ACC_WIDTH+DATA_WIDTH-1:0] scaled_product;
                        logic signed [ACC_WIDTH-1:0] scaled_score;
                        // acc is in Q16.16 (two Q8.8 multiplied), scale is Q8.8.
                        scaled_product = acc[scale_row][scale_col_base + c] * scale;
                        scaled_score = scaled_product >>> 8;
                        scores[scale_row][scale_col_base + c] <= scaled_score;
                    end

                    if (scale_col_base == TILE_BC - SCALE_COLS) begin
                        scale_col_base <= '0;
                        if (scale_row == TILE_BR - 1)
                            state <= S_DONE;
                        else
                            scale_row <= scale_row + 1;
                    end else begin
                        scale_col_base <= scale_col_base + SCALE_COLS;
                    end
                end

                S_DONE: begin
                    data_valid_q <= 1'b0;
                    scores_valid <= 1'b1;
                    done         <= 1'b1;
                    busy         <= 1'b0;
                    state        <= S_IDLE;
                end
            endcase
        end
    end

endmodule
