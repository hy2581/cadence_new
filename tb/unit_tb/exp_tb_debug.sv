`timescale 1ns/1ps
module exp_tb_debug;
    parameter IN_WIDTH=40;
    parameter FRAC_IN=8;
    parameter OUT_WIDTH=24;
    parameter FRAC_OUT=16;

    logic clk, rst_n, valid_in, valid_out;
    logic signed [IN_WIDTH-1:0] x_in;
    logic signed [15:0] neg_large;
    logic [OUT_WIDTH-1:0] exp_out;

    exp_approx_unit #(
        .IN_WIDTH(IN_WIDTH),.FRAC_IN(FRAC_IN),
        .OUT_WIDTH(OUT_WIDTH),.FRAC_OUT(FRAC_OUT)
    ) dut (.*);

    initial begin clk=0; forever #1 clk=~clk; end
    initial begin
        rst_n=0; valid_in=0; neg_large=16'h8000; x_in=0;
        repeat(10) @(posedge clk); rst_n=1;
    end

    initial begin
        @(posedge rst_n); repeat(5) @(posedge clk);

        // Test exp(0): x_in = 0
        @(posedge clk); x_in = 0; valid_in = 1;
        @(posedge clk); valid_in = 0;
        // After S1 registers:
        @(posedge clk);
        $display("exp(0) S1: idx_p1=%0d low=%b high=%b", dut.idx_p1, dut.clamp_low_p1, dut.clamp_high_p1);
        // After S2:
        @(posedge clk);
        $display("exp(0) S2: lut_val=0x%06h (%0d) low=%b high=%b", dut.lut_val_p2, dut.lut_val_p2, dut.clamp_low_p2, dut.clamp_high_p2);
        // After S3:
        @(posedge clk);
        $display("exp(0) S3: result=0x%06h (%0d) valid=%b -> %.6f", dut.result_p3, dut.result_p3, dut.valid_p3, $itor(exp_out)/65536.0);

        repeat(3) @(posedge clk);

        // Test exp(-1): x_in = -256
        @(posedge clk); x_in = -256; valid_in = 1;
        @(posedge clk); valid_in = 0;
        @(posedge clk);
        $display("exp(-1) S1: idx_p1=%0d low=%b high=%b", dut.idx_p1, dut.clamp_low_p1, dut.clamp_high_p1);
        @(posedge clk);
        $display("exp(-1) S2: lut_val=0x%06h (%0d)", dut.lut_val_p2, dut.lut_val_p2);
        @(posedge clk);
        $display("exp(-1) S3: result=0x%06h valid=%b -> %.6f", dut.result_p3, dut.valid_p3, $itor(exp_out)/65536.0);

        // Check LUT directly
        $display("LUT[819]=%0d LUT[768]=%0d LUT[0]=%0d", dut.exp_lut[819], dut.exp_lut[768], dut.exp_lut[0]);

        repeat(3) @(posedge clk);
        $finish;
    end
endmodule
