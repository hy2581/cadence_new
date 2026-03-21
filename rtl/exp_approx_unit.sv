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
    input  logic signed [15:0]          neg_large,
    output logic                        valid_out,
    output logic [OUT_WIDTH-1:0]        exp_out
);

    // LUT: 1024 entries covering x from -16.0 to +4.0
    // step = 20.0/1024 ≈ 0.01953125
    // index = (x_real + 16.0) / 0.01953125 = (x_real + 16.0) * 51.2
    localparam LUT_SIZE = 1024;
    reg [OUT_WIDTH-1:0] exp_lut [0:LUT_SIZE-1];

    integer _i;
    real _x_val, _e_val;
    integer _i_val;
    initial begin
        for (_i = 0; _i < LUT_SIZE; _i = _i + 1) begin
            _x_val = -16.0 + ($itor(_i) * 20.0 / 1024.0);
            _e_val = $exp(_x_val);
            _i_val = $rtoi(_e_val * 65536.0);
            if (_i_val > ((1 << OUT_WIDTH) - 1))
                exp_lut[_i] = {OUT_WIDTH{1'b1}};
            else
                exp_lut[_i] = _i_val[OUT_WIDTH-1:0];
        end
    end

    // Stage 1: convert x_in to LUT index (combinational prep + register)
    logic valid_p1;
    logic [9:0] idx_p1;
    logic clamp_low_p1, clamp_high_p1;

    // Combinational index computation (verified in debug)
    reg signed [IN_WIDTH-1:0] x_plus_16_c;
    reg signed [IN_WIDTH-1:0] idx_calc_c;

    always @(*) begin
        x_plus_16_c = x_in + (16 * (1 << FRAC_IN));
        idx_calc_c  = x_plus_16_c / 5;
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

    // Stage 2: LUT read (combinational read, then register)
    logic valid_p2;
    logic [OUT_WIDTH-1:0] lut_val_p2;
    logic clamp_low_p2, clamp_high_p2;

    wire [OUT_WIDTH-1:0] lut_rd_val = exp_lut[idx_p1];

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
