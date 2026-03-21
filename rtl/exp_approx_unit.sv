// ============================================================
// Exp Approximation Unit
// Computes exp(x) for signed fixed-point input (Q8.8 or wider)
// Method: exp(x) = 2^(x / ln2) = 2^(x * LOG2E)
//   Split into integer part (shift) + fractional part (LUT)
// ============================================================
module exp_approx_unit #(
    parameter IN_WIDTH  = 40,
    parameter FRAC_IN   = 8,
    parameter OUT_WIDTH = 24,
    parameter FRAC_OUT  = 16
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    valid_in,
    input  logic signed [IN_WIDTH-1:0] x_in,       // signed fixed-point input
    input  logic signed [15:0]     neg_large,       // -inf threshold (Q8.8)
    output logic                    valid_out,
    output logic [OUT_WIDTH-1:0]    exp_out          // unsigned fixed-point output
);

    // LOG2E ≈ 1.4427 in Q1.15 = 16'd47274 (1.4427 * 32768)
    localparam logic signed [16:0] LOG2E = 17'sd47274;

    // Pipeline stage 1: multiply x * LOG2E
    logic signed [IN_WIDTH+16:0] product_s1;
    logic valid_s1;
    logic signed [IN_WIDTH-1:0] x_s1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1  <= 1'b0;
            product_s1 <= '0;
            x_s1      <= '0;
        end else begin
            valid_s1 <= valid_in;
            x_s1     <= x_in;
            if (x_in < {{(IN_WIDTH-16){neg_large[15]}}, neg_large})
                product_s1 <= '0;  // underflow → exp = 0
            else
                product_s1 <= x_in * LOG2E;
        end
    end

    // Pipeline stage 2: extract integer and fractional parts, LUT + shift
    // product is in Q(INT_BITS).(FRAC_IN+15) format
    // We need to extract the value in terms of 2^(int_part) * LUT(frac_part)
    localparam PROD_FRAC = FRAC_IN + 15;

    logic [7:0]  lut_addr;
    logic [15:0] lut_value;
    logic signed [7:0] int_part;
    logic valid_s2;

    // Exp2 LUT: stores 2^(frac/256) * 65536 for frac in [0, 255]
    logic [15:0] exp2_lut [0:255];

    initial begin
        for (int i = 0; i < 256; i++) begin
            real frac_val = real'(i) / 256.0;
            exp2_lut[i] = 16'(int'((2.0 ** frac_val) * (2.0 ** FRAC_OUT) + 0.5));
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s2 <= 1'b0;
            lut_addr <= '0;
            int_part <= '0;
        end else begin
            valid_s2 <= valid_s1;
            if (product_s1 == '0 && x_s1 < 0) begin
                int_part <= -8'sd128;  // signal underflow
                lut_addr <= 8'd0;
            end else begin
                // int_part = product >> PROD_FRAC (signed)
                int_part <= product_s1[IN_WIDTH+16 -: 8];
                // frac_part top 8 bits after the integer
                lut_addr <= product_s1[PROD_FRAC-1 -: 8];
            end
        end
    end

    always_comb begin
        lut_value = exp2_lut[lut_addr];
    end

    // Pipeline stage 3: shift LUT output by integer part
    logic valid_s3;
    logic [OUT_WIDTH-1:0] result;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s3 <= 1'b0;
            result   <= '0;
        end else begin
            valid_s3 <= valid_s2;
            if (int_part < -8'sd16) begin
                result <= '0;  // too negative, exp ≈ 0
            end else if (int_part >= 8'sd8) begin
                result <= {OUT_WIDTH{1'b1}};  // saturate
            end else begin
                // Shift LUT value: positive int_part shifts left, negative shifts right
                if (int_part >= 0)
                    result <= OUT_WIDTH'(({8'b0, lut_value} << int_part[3:0]));
                else
                    result <= OUT_WIDTH'(lut_value >> (-int_part[3:0]));
            end
        end
    end

    assign valid_out = valid_s3;
    assign exp_out   = result;

endmodule
