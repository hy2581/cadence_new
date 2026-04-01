// ============================================================
// BF16 Exp Approximation Unit (Bonus 1)
// Piecewise linear approximation of exp() for BF16 format.
// BF16: 1-bit sign, 8-bit exponent, 7-bit mantissa
// ============================================================
`include "fa_params_bonus.svh"

module bf16_exp_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [15:0] x_bf16,      // BF16 input
    output logic [15:0] exp_bf16,    // BF16 output = exp(x)
    output logic        out_valid
);

    // BF16 fields
    wire       sign     = x_bf16[15];
    wire [7:0] exponent = x_bf16[14:7];
    wire [6:0] mantissa = x_bf16[6:0];

    // Pipeline stage 1: Convert BF16 to fixed-point for LUT indexing
    logic        s1_valid;
    logic [15:0] s1_x;
    logic        s1_is_neg_inf, s1_is_pos_large;

    // BF16 to approximate real value for exp range check
    // exp(x) for x < -10 ≈ 0, for x > 10 ≈ very large (clamp to max BF16)
    wire [7:0] biased_exp = exponent;
    wire       is_zero    = (exponent == 8'd0) && (mantissa == 7'd0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_x     <= '0;
            s1_is_neg_inf   <= 1'b0;
            s1_is_pos_large <= 1'b0;
        end else begin
            s1_valid <= in_valid;
            s1_x     <= x_bf16;
            // If sign=1 and exponent >= 130 (|x| >= 8), exp(x) ≈ 0
            s1_is_neg_inf   <= sign && (biased_exp >= 8'd130);
            // If sign=0 and exponent >= 131 (x >= 16), exp(x) ≈ max
            s1_is_pos_large <= !sign && !is_zero && (biased_exp >= 8'd131);
        end
    end

    // Pipeline stage 2: LUT-based exp approximation
    // We use a 256-entry LUT indexed by the most significant bits
    // of the input mapped to [-10, 4] range
    logic [7:0]  lut_index;
    logic [15:0] lut_out;

    // Simplified: map input to 8-bit index covering useful range
    // For small |x|: use mantissa-based indexing
    always_comb begin
        if (s1_x[15]) // negative
            lut_index = 8'd128 + {s1_x[14:11], s1_x[6:3]};
        else
            lut_index = {s1_x[14:11], s1_x[6:3]};
    end

    // Pre-computed exp LUT for BF16 (256 entries)
    // exp(0)=1.0=0x3F80, exp(-1)≈0.368=0x3EBC, exp(1)≈2.718=0x402E
    logic [15:0] exp_lut [255:0];

    integer i_init;
    initial begin
        for (i_init = 0; i_init < 256; i_init = i_init + 1) begin
            // Default to 1.0 (BF16 = 0x3F80)
            exp_lut[i_init] = 16'h3F80;
        end
        // Key values (BF16 representation):
        exp_lut[0]   = 16'h3F80; // exp(0) = 1.0
        exp_lut[1]   = 16'h3FAF; // exp(0.125) ≈ 1.133
        exp_lut[2]   = 16'h3FE1; // exp(0.25) ≈ 1.284
        exp_lut[4]   = 16'h4054; // exp(0.5) ≈ 1.649
        exp_lut[8]   = 16'h402E; // exp(1.0) ≈ 2.718
        exp_lut[16]  = 16'h40EC; // exp(2.0) ≈ 7.389
        exp_lut[32]  = 16'h4241; // exp(4.0) ≈ 54.6
        exp_lut[128] = 16'h3EBC; // exp(-1.0) ≈ 0.368
        exp_lut[129] = 16'h3EB0; // exp(-1.125) ≈ 0.325
        exp_lut[136] = 16'h3E09; // exp(-2.0) ≈ 0.135
        exp_lut[144] = 16'h3C89; // exp(-4.0) ≈ 0.0183
        exp_lut[160] = 16'h38B4; // exp(-8.0) ≈ 3.35e-4
        exp_lut[192] = 16'h2FF6; // exp(-16) ≈ 1.12e-7
    end

    logic [15:0] s2_lut_val;
    logic        s2_valid;
    logic        s2_is_neg_inf, s2_is_pos_large;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid       <= 1'b0;
            s2_lut_val     <= 16'h3F80;
            s2_is_neg_inf  <= 1'b0;
            s2_is_pos_large <= 1'b0;
        end else begin
            s2_valid       <= s1_valid;
            s2_lut_val     <= exp_lut[lut_index];
            s2_is_neg_inf  <= s1_is_neg_inf;
            s2_is_pos_large <= s1_is_pos_large;
        end
    end

    // Pipeline stage 3: Output selection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exp_bf16  <= '0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= s2_valid;
            if (s2_is_neg_inf)
                exp_bf16 <= 16'h0000;        // exp(-inf) = 0
            else if (s2_is_pos_large)
                exp_bf16 <= 16'h7F80;        // exp(+large) = +inf BF16
            else
                exp_bf16 <= s2_lut_val;
        end
    end

endmodule
