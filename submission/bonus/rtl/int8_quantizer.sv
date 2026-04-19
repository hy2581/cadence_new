// ============================================================
// INT8 Block Quantizer/Dequantizer (Bonus 7)
// Per-block quantization with shared scale factor.
// Input: Q8.8 or higher precision → INT8 + scale
// ============================================================
`include "fa_params_bonus.svh"

module int8_quantizer #(
    parameter BLOCK_SIZE = 16,
    parameter IN_WIDTH   = 16,
    parameter FRAC_BITS  = 8
)(
    input  logic                         clk,
    input  logic                         rst_n,

    // Quantize path: wide input → INT8 + scale
    input  logic                         quant_valid,
    input  logic signed [IN_WIDTH-1:0]  quant_data [BLOCK_SIZE-1:0],
    output logic signed [7:0]           quant_out  [BLOCK_SIZE-1:0],
    output logic [15:0]                 quant_scale,   // Q8.8 scale factor
    output logic                         quant_done,

    // Dequantize path: INT8 * scale → wide output
    input  logic                         dequant_valid,
    input  logic signed [7:0]           dequant_data [BLOCK_SIZE-1:0],
    input  logic [15:0]                 dequant_scale,
    output logic signed [IN_WIDTH-1:0]  dequant_out  [BLOCK_SIZE-1:0],
    output logic                         dequant_done
);

    // --- Quantize: find block max, compute scale, quantize ---
    logic signed [IN_WIDTH-1:0] abs_val;
    logic signed [IN_WIDTH-1:0] block_max;

    integer qi;
    always_comb begin
        block_max = 0;
        for (qi = 0; qi < BLOCK_SIZE; qi = qi + 1) begin
            abs_val = quant_data[qi] < 0 ? -quant_data[qi] : quant_data[qi];
            if (abs_val > block_max)
                block_max = abs_val;
        end
    end

    // Scale = block_max / 127 (in Q8.8)
    // Inv_scale = 127 / block_max (for quantization multiply)
    logic [15:0] scale_reg;
    logic signed [7:0] q_results [BLOCK_SIZE-1:0];
    logic quant_done_reg;

    integer qj;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scale_reg      <= 16'h0100; // 1.0
            quant_done_reg <= 1'b0;
            for (qj = 0; qj < BLOCK_SIZE; qj = qj + 1)
                q_results[qj] <= 8'd0;
        end else if (quant_valid) begin
            if (block_max == 0) begin
                scale_reg <= 16'h0100;
                for (qj = 0; qj < BLOCK_SIZE; qj = qj + 1)
                    q_results[qj] <= 8'd0;
            end else begin
                // scale = block_max (as Q8.8 value, already in that format)
                scale_reg <= block_max[15:0];
                for (qj = 0; qj < BLOCK_SIZE; qj = qj + 1) begin
                    // q = round(data * 127 / block_max)
                    q_results[qj] <= (quant_data[qj] * 127) / block_max;
                end
            end
            quant_done_reg <= 1'b1;
        end else begin
            quant_done_reg <= 1'b0;
        end
    end

    assign quant_scale = scale_reg;
    assign quant_done  = quant_done_reg;

    genvar gi;
    generate
        for (gi = 0; gi < BLOCK_SIZE; gi = gi + 1) begin : gen_qout
            assign quant_out[gi] = q_results[gi];
        end
    endgenerate

    // --- Dequantize: INT8 * scale → Q8.8 ---
    logic signed [IN_WIDTH-1:0] dq_results [BLOCK_SIZE-1:0];
    logic dequant_done_reg;

    integer di;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dequant_done_reg <= 1'b0;
            for (di = 0; di < BLOCK_SIZE; di = di + 1)
                dq_results[di] <= '0;
        end else if (dequant_valid) begin
            for (di = 0; di < BLOCK_SIZE; di = di + 1) begin
                // result = int8_val * scale / 127
                dq_results[di] <= ({{(IN_WIDTH-8){dequant_data[di][7]}}, dequant_data[di]} *
                                   $signed({1'b0, dequant_scale})) / 127;
            end
            dequant_done_reg <= 1'b1;
        end else begin
            dequant_done_reg <= 1'b0;
        end
    end

    assign dequant_done = dequant_done_reg;

    genvar dgi;
    generate
        for (dgi = 0; dgi < BLOCK_SIZE; dgi = dgi + 1) begin : gen_dqout
            assign dequant_out[dgi] = dq_results[dgi];
        end
    endgenerate

endmodule
