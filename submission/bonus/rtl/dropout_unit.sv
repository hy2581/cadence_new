// ============================================================
// Dropout Unit — LFSR-based (Bonus 6)
// Applies dropout mask after softmax with configurable rate.
// Uses 32-bit Galois LFSR for pseudo-random generation.
// ============================================================
`include "fa_params_bonus.svh"

module dropout_unit #(
    parameter WIDTH      = 16,
    parameter LFSR_WIDTH = 32,
    parameter FRAC_BITS  = 8
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    enable,
    input  logic [LFSR_WIDTH-1:0]  seed,
    input  logic                    seed_load,
    input  logic [7:0]             drop_prob,      // 0-255: probability (255 = ~100% drop)
    input  logic                    in_valid,
    input  logic signed [WIDTH-1:0] data_in,
    output logic signed [WIDTH-1:0] data_out,
    output logic                    out_valid,
    output logic                    drop_mask
);

    logic [LFSR_WIDTH-1:0] lfsr_reg;
    logic                  feedback;

    // Galois LFSR: x^32 + x^22 + x^2 + x + 1
    assign feedback = lfsr_reg[31] ^ lfsr_reg[21] ^ lfsr_reg[1] ^ lfsr_reg[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr_reg <= 32'hDEAD_BEEF;
        else if (seed_load)
            lfsr_reg <= (seed == '0) ? 32'hDEAD_BEEF : seed;
        else if (in_valid && enable)
            lfsr_reg <= {lfsr_reg[LFSR_WIDTH-2:0], feedback};
    end

    wire should_drop = enable && (lfsr_reg[7:0] < drop_prob);

    // Rescale surviving values by 1/(1-p) approximation:
    // For simplicity, we use a shift-based approach.
    // When drop_prob < 128 (p < 0.5), scale by ~2x when p~0.5
    // This is a simplified version; exact rescaling is complex in fixed-point.
    logic signed [WIDTH+8-1:0] scaled;
    logic [7:0] inv_keep;

    always_comb begin
        inv_keep = 8'd255 - drop_prob;
        if (inv_keep == 0)
            scaled = '0;
        else
            scaled = ({{8{data_in[WIDTH-1]}}, data_in} <<< FRAC_BITS) / {{(WIDTH){1'b0}}, inv_keep};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= '0;
            out_valid <= 1'b0;
            drop_mask <= 1'b0;
        end else begin
            out_valid <= in_valid;
            if (!in_valid) begin
                data_out  <= '0;
                drop_mask <= 1'b0;
            end else if (!enable) begin
                data_out  <= data_in;
                drop_mask <= 1'b0;
            end else if (should_drop) begin
                data_out  <= '0;
                drop_mask <= 1'b1;
            end else begin
                data_out  <= scaled[WIDTH-1:0];
                drop_mask <= 1'b0;
            end
        end
    end

endmodule
