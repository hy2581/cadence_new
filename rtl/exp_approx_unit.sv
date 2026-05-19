// ============================================================
// Exp Approximation Unit — Simplified Direct LUT
// Input:  signed fixed-point Q(IN_WIDTH-FRAC_IN).FRAC_IN
// Output: unsigned fixed-point Q(OUT_WIDTH-FRAC_OUT).FRAC_OUT
// Range:  exp(x) for x in [-16, +4]
// Method: Single-cycle LUT with 3-stage pipeline for timing
// ============================================================
module exp_approx_unit #(
    parameter IN_WIDTH  = 40,
    parameter FRAC_IN   = 8,
    parameter OUT_WIDTH = 24,
    parameter FRAC_OUT  = 16
)(
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        valid_in,
    input  logic signed [IN_WIDTH-1:0]  x_in,
    output logic                        valid_out,
    output logic [OUT_WIDTH-1:0]        exp_out
);

    // LUT: 1024 entries covering x from -16.0 to +4.0
    // step = 20.0/1024 ≈ 0.01953125
    // index = (x_real + 16.0) / 0.01953125 = (x_real + 16.0) * 51.2
    localparam LUT_SIZE = 1024;

    // Stage 1: convert x_in to LUT index (combinational prep + register)
    logic valid_p1;
    logic [9:0] idx_p1;
    logic clamp_low_p1, clamp_high_p1;

    // Combinational index computation:
    // idx ~= (x + 16) * 1024 / 20, with x represented in Q*.FRAC_IN.
    // 13107 / 2^8 is a close fixed-point approximation to 1024 / 20.
    localparam int INDEX_MUL = 13107;
    localparam int INDEX_SHIFT = FRAC_IN + 8;
    reg signed [IN_WIDTH-1:0] x_plus_16_c;
    reg signed [IN_WIDTH-1:0] idx_calc_c;
    reg signed [IN_WIDTH+14:0] idx_num_c;

    always @(*) begin
        x_plus_16_c = x_in + (16 * (1 << FRAC_IN));
        idx_num_c   = x_plus_16_c * INDEX_MUL;
        idx_calc_c  = idx_num_c >>> INDEX_SHIFT;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_p1      <= 0;
            idx_p1        <= 0;
            clamp_low_p1  <= 0;
            clamp_high_p1 <= 0;
        end else begin
            valid_p1 <= valid_in;
            if (x_plus_16_c <= 0) begin
                idx_p1        <= 0;
                clamp_low_p1  <= 1;
                clamp_high_p1 <= 0;
            end else if (idx_calc_c >= LUT_SIZE) begin
                idx_p1        <= LUT_SIZE - 1;
                clamp_low_p1  <= 0;
                clamp_high_p1 <= 1;
            end else begin
                idx_p1        <= idx_calc_c[9:0];
                clamp_low_p1  <= 0;
                clamp_high_p1 <= 0;
            end
        end
    end

    // LUT ROM instance (after idx_p1 declaration)
    wire [OUT_WIDTH-1:0] lut_rom_data;
    exp_lut_rom u_lut_rom (.addr(idx_p1), .data(lut_rom_data));

    // Stage 2: LUT read (combinational read, then register)
    logic valid_p2;
    logic [OUT_WIDTH-1:0] lut_val_p2;
    logic clamp_low_p2, clamp_high_p2;

    wire [OUT_WIDTH-1:0] lut_rd_val = lut_rom_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_p2      <= 0;
            lut_val_p2    <= 0;
            clamp_low_p2  <= 0;
            clamp_high_p2 <= 0;
        end else begin
            valid_p2      <= valid_p1;
            lut_val_p2    <= lut_rd_val;
            clamp_low_p2  <= clamp_low_p1;
            clamp_high_p2 <= clamp_high_p1;
        end
    end

    // Stage 3: output
    logic valid_p3;
    logic [OUT_WIDTH-1:0] result_p3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_p3  <= 0;
            result_p3 <= 0;
        end else begin
            valid_p3 <= valid_p2;
            if (clamp_low_p2)
                result_p3 <= 0;
            else if (clamp_high_p2)
                result_p3 <= {OUT_WIDTH{1'b1}};
            else
                result_p3 <= lut_val_p2;
        end
    end

    assign valid_out = valid_p3;
    assign exp_out   = result_p3;

endmodule
