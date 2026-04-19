// ============================================================
// Output Accumulator — Pipelined Normalization
// Uses reciprocal_unit for division to avoid deep combinational paths.
// S_RESCALE serialized per row; S_NORMALIZE uses reciprocal + multiply.
// ============================================================
module output_accumulator #(
    parameter TILE_BR    = 4,
    parameter TILE_BC    = 16,
    parameter HEAD_DIM   = 64,
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 40,
    parameter EXP_WIDTH  = 24,
    parameter FRAC_BITS  = 16,
    parameter PAR_COLS   = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,

    input  logic                          start,
    input  logic                          first_tile,
    input  logic                          last_tile,
    output logic                          done,
    output logic                          busy,

    input  logic [EXP_WIDTH-1:0]          p_matrix [TILE_BR-1:0][TILE_BC-1:0],

    input  logic signed [DATA_WIDTH-1:0]  v_data [TILE_BC-1:0][PAR_COLS-1:0],
    input  logic                          v_valid,

    input  logic [ACC_WIDTH-1:0]          rescale [TILE_BR-1:0],
    input  logic [ACC_WIDTH-1:0]          l_values [TILE_BR-1:0],

    output logic signed [DATA_WIDTH-1:0]  o_out [TILE_BR-1:0][HEAD_DIM-1:0],
    output logic                          o_valid,

    output logic                          v_request
);

    localparam NUM_V_STEPS = HEAD_DIM / PAR_COLS;

    logic signed [ACC_WIDTH-1:0] o_acc [TILE_BR-1:0][HEAD_DIM-1:0];

    typedef enum logic [3:0] {
        S_IDLE,
        S_RESCALE,
        S_PV_MULT,
        S_NORM_RECIP_FEED,
        S_NORM_RECIP_DRAIN,
        S_NORM_MULT,
        S_DONE
    } state_t;

    state_t state;
    logic [$clog2(NUM_V_STEPS):0] v_step;
    logic [$clog2(HEAD_DIM):0]    col_base;
    logic [$clog2(TILE_BR):0]     rescale_row;
    logic                         is_last_tile_r;

    // Reciprocal unit for normalization
    logic                  recip_valid_in, recip_valid_out;
    logic [ACC_WIDTH-1:0]  recip_d_in;
    logic [ACC_WIDTH-1:0]  recip_out;

    reciprocal_unit #(.WIDTH(ACC_WIDTH), .FRAC_BITS(FRAC_BITS)) u_recip (
        .clk(clk), .rst_n(rst_n),
        .valid_in(recip_valid_in), .d_in(recip_d_in),
        .valid_out(recip_valid_out), .recip_out(recip_out)
    );

    // Stored reciprocals for each row
    logic [ACC_WIDTH-1:0] recip_vals [TILE_BR-1:0];
    logic [$clog2(TILE_BR):0] recip_feed_row;
    logic [$clog2(TILE_BR):0] recip_recv_row;

    // Normalization multiply state
    logic [$clog2(TILE_BR):0]  norm_row;
    logic [$clog2(HEAD_DIM):0] norm_col;

    assign v_request = (state == S_PV_MULT);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            done           <= 1'b0;
            busy           <= 1'b0;
            o_valid        <= 1'b0;
            v_step         <= '0;
            col_base       <= '0;
            rescale_row    <= '0;
            is_last_tile_r <= 1'b0;
            recip_valid_in <= 1'b0;
            recip_feed_row <= '0;
            recip_recv_row <= '0;
            norm_row       <= '0;
            norm_col       <= '0;
            for (int r = 0; r < TILE_BR; r++) begin
                recip_vals[r] <= '0;
                for (int j = 0; j < HEAD_DIM; j++)
                    o_acc[r][j] <= '0;
            end
        end else begin
            done           <= 1'b0;
            o_valid        <= 1'b0;
            recip_valid_in <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        busy           <= 1'b1;
                        is_last_tile_r <= last_tile;
                        if (first_tile) begin
                            for (int r = 0; r < TILE_BR; r++)
                                for (int j = 0; j < HEAD_DIM; j++)
                                    o_acc[r][j] <= '0;
                            state    <= S_PV_MULT;
                            v_step   <= '0;
                            col_base <= '0;
                        end else begin
                            state       <= S_RESCALE;
                            rescale_row <= '0;
                        end
                    end
                end

                // Serialize rescale: one row per cycle
                S_RESCALE: begin
                    for (int j = 0; j < HEAD_DIM; j++) begin
                        if (l_values[rescale_row] != '0)
                            o_acc[rescale_row][j] <=
                                (o_acc[rescale_row][j] * signed'({1'b0, rescale[rescale_row]})) >>> FRAC_BITS;
                        else
                            o_acc[rescale_row][j] <= '0;
                    end
                    if (rescale_row == TILE_BR - 1) begin
                        state    <= S_PV_MULT;
                        v_step   <= '0;
                        col_base <= '0;
                    end else begin
                        rescale_row <= rescale_row + 1;
                    end
                end

                // P · V accumulation (same as before, driven by external v_valid)
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
                        if (v_step == NUM_V_STEPS - 1) begin
                            if (is_last_tile_r) begin
                                state          <= S_NORM_RECIP_FEED;
                                recip_feed_row <= '0;
                                recip_recv_row <= '0;
                            end else begin
                                state <= S_DONE;
                            end
                        end
                    end
                end

                // Feed l_values to reciprocal unit (one per cycle)
                S_NORM_RECIP_FEED: begin
                    if (recip_feed_row < TILE_BR) begin
                        recip_valid_in <= 1'b1;
                        recip_d_in     <= l_values[recip_feed_row];
                        recip_feed_row <= recip_feed_row + 1;
                    end
                    if (recip_valid_out) begin
                        recip_vals[recip_recv_row] <= recip_out;
                        recip_recv_row <= recip_recv_row + 1;
                    end
                    if (recip_feed_row >= TILE_BR && !recip_valid_out &&
                        recip_recv_row < TILE_BR) begin
                        state <= S_NORM_RECIP_DRAIN;
                    end
                    if (recip_recv_row >= TILE_BR) begin
                        state    <= S_NORM_MULT;
                        norm_row <= '0;
                        norm_col <= '0;
                    end
                end

                // Wait for remaining reciprocal results
                S_NORM_RECIP_DRAIN: begin
                    if (recip_valid_out) begin
                        recip_vals[recip_recv_row] <= recip_out;
                        recip_recv_row <= recip_recv_row + 1;
                    end
                    if (recip_recv_row >= TILE_BR) begin
                        state    <= S_NORM_MULT;
                        norm_row <= '0;
                        norm_col <= '0;
                    end
                end

                // Normalize: O[r][j] = (o_acc[r][j] * recip_vals[r]) >> FRAC_BITS
                // Process PAR_COLS columns per cycle
                S_NORM_MULT: begin
                    for (int p = 0; p < PAR_COLS; p++) begin
                        if (norm_col + p < HEAD_DIM) begin
                            logic signed [ACC_WIDTH-1:0] normalized;
                            if (recip_vals[norm_row] != '0)
                                normalized = (o_acc[norm_row][norm_col + p] *
                                              signed'({1'b0, recip_vals[norm_row]})) >>> FRAC_BITS;
                            else
                                normalized = '0;
                            o_out[norm_row][norm_col + p] <=
                                DATA_WIDTH'(normalized >>> (FRAC_BITS - 8));
                        end
                    end
                    if (norm_col + PAR_COLS >= HEAD_DIM) begin
                        norm_col <= '0;
                        if (norm_row == TILE_BR - 1)
                            state <= S_DONE;
                        else
                            norm_row <= norm_row + 1;
                    end else begin
                        norm_col <= norm_col + PAR_COLS;
                    end
                end

                S_DONE: begin
                    o_valid <= is_last_tile_r;
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    state   <= S_IDLE;
                end
            endcase
        end
    end

endmodule
