// ============================================================
// Enhanced Mask Unit — Causal + Padding Mask (Bonus 4)
// ============================================================
`include "fa_params_bonus.svh"

module mask_unit #(
    parameter TILE_BR   = 4,
    parameter TILE_BC   = 16,
    parameter SEQ_LEN   = 256,
    parameter DATA_WIDTH = 16
)(
    input  logic                       causal_en,
    input  logic                       padding_en,
    input  logic [$clog2(SEQ_LEN):0]   valid_len,
    input  logic [$clog2(SEQ_LEN)-1:0] q_row_base,
    input  logic [$clog2(SEQ_LEN)-1:0] kv_col_base,
    input  logic signed [DATA_WIDTH-1:0] neg_large,
    output logic signed [DATA_WIDTH-1:0] mask_val [TILE_BR-1:0][TILE_BC-1:0]
);

    integer r, c;
    logic [$clog2(SEQ_LEN)-1:0] abs_row, abs_col;
    logic causal_masked, padding_masked;

    always_comb begin
        for (r = 0; r < TILE_BR; r = r + 1) begin
            for (c = 0; c < TILE_BC; c = c + 1) begin
                abs_row = q_row_base + r[$clog2(SEQ_LEN)-1:0];
                abs_col = kv_col_base + c[$clog2(SEQ_LEN)-1:0];

                causal_masked = causal_en && (abs_col > abs_row);
                padding_masked = padding_en && ({1'b0, abs_col} >= valid_len);

                mask_val[r][c] = (causal_masked || padding_masked) ? neg_large : {DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule
