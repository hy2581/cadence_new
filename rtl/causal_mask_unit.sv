// ============================================================
// Causal Mask Unit
// Generates mask signals for FlashAttention causal masking
// When col_idx > row_idx, the score should be replaced with NEG_LARGE
// ============================================================
module causal_mask_unit #(
    parameter SEQ_LEN   = 256,
    parameter TILE_BR   = 4,
    parameter TILE_BC   = 16,
    parameter IDX_WIDTH = $clog2(SEQ_LEN)
)(
    input  logic                    causal_en,
    input  logic [IDX_WIDTH-1:0]    q_tile_idx,     // which Q tile (0..NUM_Q_TILES-1)
    input  logic [IDX_WIDTH-1:0]    kv_tile_idx,    // which KV tile (0..NUM_KV_TILES-1)
    input  logic [$clog2(TILE_BR)-1:0] row_in_tile, // row within Q tile (0..B_r-1)
    input  logic [$clog2(TILE_BC)-1:0] col_in_tile, // col within KV tile (0..B_c-1)
    output logic                    mask_out         // 1 = masked (replace with NEG_LARGE)
);

    logic [IDX_WIDTH-1:0] abs_row, abs_col;

    always_comb begin
        abs_row = q_tile_idx * TILE_BR + IDX_WIDTH'(row_in_tile);
        abs_col = kv_tile_idx * TILE_BC + IDX_WIDTH'(col_in_tile);
        mask_out = causal_en & (abs_col > abs_row);
    end

endmodule
