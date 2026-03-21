// ============================================================
// Buffer System
// On-chip SRAM buffers for Q, K, V tiles and O accumulation
// Supports double-buffering for K/V (ping-pong)
// ============================================================
module buffer_system #(
    parameter TILE_BR    = 4,
    parameter TILE_BC    = 16,
    parameter HEAD_DIM   = 64,
    parameter DATA_WIDTH = 16,
    parameter PAR_MACS   = 8,
    parameter AXI_DATA_WIDTH = 128
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // --- DMA write interface (loading tiles from external memory) ---
    input  logic                          q_wr_en,
    input  logic [$clog2(TILE_BR*HEAD_DIM)-1:0] q_wr_addr,
    input  logic [AXI_DATA_WIDTH-1:0]     q_wr_data,

    input  logic                          k_wr_en,
    input  logic [$clog2(TILE_BC*HEAD_DIM)-1:0] k_wr_addr,
    input  logic [AXI_DATA_WIDTH-1:0]     k_wr_data,
    input  logic                          k_buf_sel,     // 0 or 1 for ping-pong

    input  logic                          v_wr_en,
    input  logic [$clog2(TILE_BC*HEAD_DIM)-1:0] v_wr_addr,
    input  logic [AXI_DATA_WIDTH-1:0]     v_wr_data,
    input  logic                          v_buf_sel,

    // --- Compute core read interface ---
    // Q: B_r rows × PAR_MACS elements, indexed by step
    input  logic                          q_rd_en,
    input  logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] q_rd_step,
    output logic signed [DATA_WIDTH-1:0]  q_rd_data [TILE_BR-1:0][PAR_MACS-1:0],

    // K: B_c rows × PAR_MACS elements
    input  logic                          k_rd_en,
    input  logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] k_rd_step,
    input  logic                          k_rd_buf_sel,
    output logic signed [DATA_WIDTH-1:0]  k_rd_data [TILE_BC-1:0][PAR_MACS-1:0],

    // V: B_c rows × PAR_MACS elements
    input  logic                          v_rd_en,
    input  logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] v_rd_step,
    input  logic                          v_rd_buf_sel,
    output logic signed [DATA_WIDTH-1:0]  v_rd_data [TILE_BC-1:0][PAR_MACS-1:0],

    // --- O write-back interface ---
    input  logic                          o_wr_en,
    input  logic signed [DATA_WIDTH-1:0]  o_wr_data [TILE_BR-1:0][HEAD_DIM-1:0],

    input  logic                          o_rd_en,
    input  logic [$clog2(TILE_BR)-1:0]    o_rd_row,
    output logic [AXI_DATA_WIDTH-1:0]     o_rd_data,
    input  logic [$clog2(HEAD_DIM/(AXI_DATA_WIDTH/DATA_WIDTH))-1:0] o_rd_col_grp
);

    localparam Q_DEPTH = TILE_BR * HEAD_DIM;      // 4*64 = 256
    localparam KV_DEPTH = TILE_BC * HEAD_DIM;     // 16*64 = 1024
    localparam ELEMS_PER_BEAT = AXI_DATA_WIDTH / DATA_WIDTH;  // 128/16 = 8

    // --- Q Buffer (single) ---
    logic signed [DATA_WIDTH-1:0] q_mem [Q_DEPTH-1:0];

    // Write (from DMA, AXI_DATA_WIDTH bits = 8 elements per beat)
    always_ff @(posedge clk) begin
        if (q_wr_en) begin
            for (int i = 0; i < ELEMS_PER_BEAT; i++)
                q_mem[q_wr_addr * ELEMS_PER_BEAT + i] <=
                    DATA_WIDTH'(q_wr_data[i*DATA_WIDTH +: DATA_WIDTH]);
        end
    end

    // Read (PAR_MACS elements per row per step)
    always_comb begin
        for (int r = 0; r < TILE_BR; r++)
            for (int p = 0; p < PAR_MACS; p++)
                q_rd_data[r][p] = q_mem[r * HEAD_DIM + q_rd_step * PAR_MACS + p];
    end

    // --- K Buffers (double, ping-pong) ---
    logic signed [DATA_WIDTH-1:0] k_mem [1:0][KV_DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (k_wr_en) begin
            for (int i = 0; i < ELEMS_PER_BEAT; i++)
                k_mem[k_buf_sel][k_wr_addr * ELEMS_PER_BEAT + i] <=
                    DATA_WIDTH'(k_wr_data[i*DATA_WIDTH +: DATA_WIDTH]);
        end
    end

    always_comb begin
        for (int r = 0; r < TILE_BC; r++)
            for (int p = 0; p < PAR_MACS; p++)
                k_rd_data[r][p] = k_mem[k_rd_buf_sel][r * HEAD_DIM + k_rd_step * PAR_MACS + p];
    end

    // --- V Buffers (double, ping-pong) ---
    logic signed [DATA_WIDTH-1:0] v_mem [1:0][KV_DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (v_wr_en) begin
            for (int i = 0; i < ELEMS_PER_BEAT; i++)
                v_mem[v_buf_sel][v_wr_addr * ELEMS_PER_BEAT + i] <=
                    DATA_WIDTH'(v_wr_data[i*DATA_WIDTH +: DATA_WIDTH]);
        end
    end

    always_comb begin
        for (int r = 0; r < TILE_BC; r++)
            for (int p = 0; p < PAR_MACS; p++)
                v_rd_data[r][p] = v_mem[v_rd_buf_sel][r * HEAD_DIM + v_rd_step * PAR_MACS + p];
    end

    // --- O Buffer ---
    logic signed [DATA_WIDTH-1:0] o_mem [TILE_BR-1:0][HEAD_DIM-1:0];

    always_ff @(posedge clk) begin
        if (o_wr_en) begin
            for (int r = 0; r < TILE_BR; r++)
                for (int j = 0; j < HEAD_DIM; j++)
                    o_mem[r][j] <= o_wr_data[r][j];
        end
    end

    // Read O for DMA write-back (ELEMS_PER_BEAT elements per beat)
    always_comb begin
        for (int i = 0; i < ELEMS_PER_BEAT; i++)
            o_rd_data[i*DATA_WIDTH +: DATA_WIDTH] =
                o_mem[o_rd_row][o_rd_col_grp * ELEMS_PER_BEAT + i];
    end

endmodule
