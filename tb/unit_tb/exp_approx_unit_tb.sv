`timescale 1ns/1ps
module exp_approx_unit_tb;

    parameter IN_WIDTH  = 40;
    parameter FRAC_IN   = 8;
    parameter OUT_WIDTH = 24;
    parameter FRAC_OUT  = 16;

    logic clk, rst_n;
    logic valid_in, valid_out;
    logic signed [IN_WIDTH-1:0] x_in;
    logic signed [15:0] neg_large;
    logic [OUT_WIDTH-1:0] exp_out;

    exp_approx_unit #(
        .IN_WIDTH(IN_WIDTH), .FRAC_IN(FRAC_IN),
        .OUT_WIDTH(OUT_WIDTH), .FRAC_OUT(FRAC_OUT)
    ) dut (.*);

    initial begin clk = 0; forever #1 clk = ~clk; end
    initial begin
        rst_n = 0; valid_in = 0; neg_large = 16'h8000;
        x_in = 0;
        repeat(10) @(posedge clk); rst_n = 1;
    end

    integer pass_cnt, fail_cnt, total;
    real max_err;

    task automatic test_exp(input real x_real, input string label);
        real expected, got, err;
        // Drive input for exactly one cycle
        @(posedge clk);
        x_in = IN_WIDTH'($rtoi(x_real * (2.0**FRAC_IN)));
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
        x_in = 0;
        // Pipeline is 3 stages: wait 3 cycles then sample
        @(posedge clk); // S1 done
        @(posedge clk); // S2 done
        @(posedge clk); // S3 done — result available now
        got = $itor(exp_out) / (2.0**FRAC_OUT);

        if (x_real < -10.0) expected = 0.0;
        else expected = $exp(x_real);
        if (expected > 0.001)
            err = (got - expected) / expected;
        else
            err = got - expected;
        if (err < 0) err = -err;
        total = total + 1;
        if (err > max_err) max_err = err;
        if (err < 0.15 || expected < 0.001) begin
            pass_cnt = pass_cnt + 1;
            $display("PASS %s: x=%.4f exp=%.6f got=%.6f err=%.2f%%", label, x_real, expected, got, err*100);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("FAIL %s: x=%.4f exp=%.6f got=%.6f err=%.2f%%", label, x_real, expected, got, err*100);
        end
    endtask

    initial begin
        pass_cnt = 0; fail_cnt = 0; total = 0; max_err = 0;
        @(posedge rst_n);
        repeat(5) @(posedge clk);

        $display("=== exp_approx_unit Test ===");
        test_exp(0.0,   "exp(0)");
        test_exp(0.5,   "exp(0.5)");
        test_exp(1.0,   "exp(1)");
        test_exp(-1.0,  "exp(-1)");
        test_exp(-2.0,  "exp(-2)");
        test_exp(-5.0,  "exp(-5)");
        test_exp(-10.0, "exp(-10)");
        test_exp(2.0,   "exp(2)");
        test_exp(-0.5,  "exp(-0.5)");
        test_exp(0.1,   "exp(0.1)");

        $display("");
        $display("Results: %0d/%0d passed, max_rel_err=%.2f%%", pass_cnt, total, max_err*100);
        if (fail_cnt == 0) $display(">>> ALL TESTS PASSED <<<");
        else $display(">>> %0d TESTS FAILED <<<", fail_cnt);
        $finish;
    end
endmodule
