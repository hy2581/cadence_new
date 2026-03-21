// ============================================================
// Reciprocal Approximation Unit (Newton-Raphson)
// Computes 1/x for unsigned fixed-point input
// Method: LUT initial guess + 2 Newton-Raphson iterations
//   x_{n+1} = x_n * (2 - d * x_n)
// ============================================================
module reciprocal_unit #(
    parameter WIDTH     = 40,
    parameter FRAC_BITS = 16
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 valid_in,
    input  logic [WIDTH-1:0]     d_in,          // unsigned fixed-point denominator
    output logic                 valid_out,
    output logic [WIDTH-1:0]     recip_out       // unsigned fixed-point ≈ 1/d_in
);

    // --- LUT for initial guess ---
    // Normalize d_in to [0.5, 1.0) by finding leading one, then use top 8 bits as LUT index
    // LUT stores 1/x * 2^FRAC_BITS for normalized x

    localparam LUT_DEPTH = 256;
    logic [WIDTH-1:0] recip_lut [0:LUT_DEPTH-1];

    integer _ri;
    initial begin
        for (_ri = 0; _ri < LUT_DEPTH; _ri = _ri + 1) begin
            recip_lut[_ri] = WIDTH'(int'((1.0 / (0.5 + (real'(_ri) / real'(LUT_DEPTH)) * 0.5)) * (2.0 ** FRAC_BITS) + 0.5));
        end
    end

    // Stage 1: find leading one and normalize
    logic valid_s1;
    logic [$clog2(WIDTH)-1:0] lz_count;
    logic [WIDTH-1:0] d_norm;
    logic [WIDTH-1:0] d_saved;
    logic [$clog2(WIDTH)-1:0] shift_amt;

    function automatic [$clog2(WIDTH)-1:0] count_leading_zeros(input [WIDTH-1:0] val);
        for (int i = WIDTH-1; i >= 0; i--) begin
            if (val[i]) return $clog2(WIDTH)'(WIDTH - 1 - i);
        end
        return $clog2(WIDTH)'(WIDTH);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1  <= 1'b0;
            d_norm    <= '0;
            d_saved   <= '0;
            shift_amt <= '0;
        end else begin
            valid_s1 <= valid_in;
            d_saved  <= d_in;
            lz_count  = count_leading_zeros(d_in);
            shift_amt <= lz_count;
            d_norm    <= d_in << lz_count;
        end
    end

    // Stage 2: LUT lookup for initial guess
    logic valid_s2;
    logic [WIDTH-1:0] x0;
    logic [WIDTH-1:0] d_s2;
    logic [$clog2(WIDTH)-1:0] shift_s2;
    logic [7:0] lut_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s2 <= 1'b0;
            x0       <= '0;
            d_s2     <= '0;
            shift_s2 <= '0;
        end else begin
            valid_s2 <= valid_s1;
            d_s2     <= d_saved;
            shift_s2 <= shift_amt;
            lut_idx   = d_norm[WIDTH-1 -: 8];
            x0       <= recip_lut[lut_idx] << shift_amt;
        end
    end

    // Stage 3: Newton-Raphson iteration 1
    // x1 = x0 * (2 - d * x0)
    logic valid_s3;
    logic [WIDTH-1:0] x1;
    logic [WIDTH-1:0] d_s3;
    logic [2*WIDTH-1:0] d_x0;
    logic [WIDTH-1:0] two_minus;
    logic [2*WIDTH-1:0] x1_full;

    localparam [WIDTH-1:0] TWO_FP = WIDTH'(2) << FRAC_BITS;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s3 <= 1'b0;
            x1       <= '0;
            d_s3     <= '0;
        end else begin
            valid_s3  <= valid_s2;
            d_s3      <= d_s2;
            d_x0       = (d_s2 * x0) >> FRAC_BITS;
            two_minus  = TWO_FP - d_x0[WIDTH-1:0];
            x1_full    = (x0 * two_minus) >> FRAC_BITS;
            x1        <= x1_full[WIDTH-1:0];
        end
    end

    // Stage 4: Newton-Raphson iteration 2
    // x2 = x1 * (2 - d * x1)
    logic valid_s4;
    logic [WIDTH-1:0] x2;
    logic [2*WIDTH-1:0] d_x1;
    logic [WIDTH-1:0] two_minus2;
    logic [2*WIDTH-1:0] x2_full;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s4 <= 1'b0;
            x2       <= '0;
        end else begin
            valid_s4   <= valid_s3;
            d_x1        = (d_s3 * x1) >> FRAC_BITS;
            two_minus2  = TWO_FP - d_x1[WIDTH-1:0];
            x2_full     = (x1 * two_minus2) >> FRAC_BITS;
            x2         <= x2_full[WIDTH-1:0];
        end
    end

    assign valid_out = valid_s4;
    assign recip_out = x2;

endmodule
