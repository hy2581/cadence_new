`timescale 1ns/1ps
module exp_debug;
    parameter IN_WIDTH = 40;
    parameter FRAC_IN = 8;

    reg signed [IN_WIDTH-1:0] x_in;
    reg signed [IN_WIDTH-1:0] x_plus_16;
    reg signed [IN_WIDTH-1:0] idx_calc;
    reg signed [IN_WIDTH-1:0] offset;

    initial begin
        offset = 16 * (1 << FRAC_IN); // 16 * 256 = 4096

        x_in = 0;
        x_plus_16 = x_in + offset;
        idx_calc = x_plus_16 / 5;
        $display("x=0.0:  x_in=%0d x_plus_16=%0d idx=%0d (expect ~819)", x_in, x_plus_16, idx_calc);

        x_in = -256;
        x_plus_16 = x_in + offset;
        idx_calc = x_plus_16 / 5;
        $display("x=-1.0: x_in=%0d x_plus_16=%0d idx=%0d (expect ~768)", x_in, x_plus_16, idx_calc);

        x_in = 256;
        x_plus_16 = x_in + offset;
        idx_calc = x_plus_16 / 5;
        $display("x=1.0:  x_in=%0d x_plus_16=%0d idx=%0d (expect ~870)", x_in, x_plus_16, idx_calc);

        x_in = 512;
        x_plus_16 = x_in + offset;
        idx_calc = x_plus_16 / 5;
        $display("x=2.0:  x_in=%0d x_plus_16=%0d idx=%0d (expect ~921)", x_in, x_plus_16, idx_calc);

        x_in = -4096; // x=-16.0
        x_plus_16 = x_in + offset;
        idx_calc = x_plus_16 / 5;
        $display("x=-16:  x_in=%0d x_plus_16=%0d idx=%0d (expect 0)", x_in, x_plus_16, idx_calc);

        $finish;
    end
endmodule
