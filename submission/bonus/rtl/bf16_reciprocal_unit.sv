// ============================================================
// BF16 Reciprocal Unit (Bonus 1)
// Newton-Raphson reciprocal for BF16: 1/x
// ============================================================
`include "fa_params_bonus.svh"

module bf16_reciprocal_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [15:0] x_bf16,
    output logic [15:0] recip_bf16,
    output logic        out_valid
);

    // BF16 reciprocal using exponent manipulation + LUT refinement
    // 1/x: flip exponent around bias (127), refine mantissa with LUT

    wire       sign     = x_bf16[15];
    wire [7:0] exponent = x_bf16[14:7];
    wire [6:0] mantissa = x_bf16[6:0];

    // Stage 1: Initial estimate via exponent inversion
    logic        s1_valid;
    logic        s1_sign;
    logic [7:0]  s1_exp_inv;
    logic [6:0]  s1_mantissa;
    logic        s1_is_zero;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid    <= 1'b0;
            s1_sign     <= 1'b0;
            s1_exp_inv  <= 8'd127;
            s1_mantissa <= '0;
            s1_is_zero  <= 1'b0;
        end else begin
            s1_valid    <= in_valid;
            s1_sign     <= sign;
            s1_is_zero  <= (exponent == 8'd0);
            // 1/(2^e * m) ≈ 2^(-e) * (1/m)
            // New exponent = 2*bias - exponent - adjustment
            if (mantissa == 7'd0)
                s1_exp_inv <= 9'd254 - {1'b0, exponent};
            else
                s1_exp_inv <= 9'd253 - {1'b0, exponent};
            s1_mantissa <= mantissa;
        end
    end

    // Stage 2: Mantissa reciprocal LUT (128 entries for 7-bit mantissa)
    logic [6:0] recip_mantissa_lut [127:0];

    integer k;
    initial begin
        // 1/(1.m) where m is 7-bit fraction
        // Precompute: recip_mantissa ≈ (128 / (128 + m)) * 128 - 128
        for (k = 0; k < 128; k = k + 1) begin
            recip_mantissa_lut[k] = (128 * 128 / (128 + k)) - 128;
        end
    end

    logic        s2_valid;
    logic        s2_sign;
    logic [7:0]  s2_exponent;
    logic [6:0]  s2_mantissa;
    logic        s2_is_zero;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid    <= 1'b0;
            s2_sign     <= 1'b0;
            s2_exponent <= 8'd127;
            s2_mantissa <= '0;
            s2_is_zero  <= 1'b0;
        end else begin
            s2_valid    <= s1_valid;
            s2_sign     <= s1_sign;
            s2_exponent <= s1_exp_inv;
            s2_mantissa <= recip_mantissa_lut[s1_mantissa];
            s2_is_zero  <= s1_is_zero;
        end
    end

    // Stage 3: Assemble result
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            recip_bf16 <= 16'h3F80; // 1.0
            out_valid  <= 1'b0;
        end else begin
            out_valid <= s2_valid;
            if (s2_is_zero)
                recip_bf16 <= {s2_sign, 8'hFF, 7'h00}; // ±inf
            else
                recip_bf16 <= {s2_sign, s2_exponent, s2_mantissa};
        end
    end

endmodule
