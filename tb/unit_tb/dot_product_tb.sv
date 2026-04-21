`timescale 1ns/1ps
module dot_product_tb;
    parameter TILE_BR    = 4;
    parameter TILE_BC    = 16;
    parameter HEAD_DIM   = 64;
    parameter DATA_WIDTH = 16;
    parameter ACC_WIDTH  = 40;
    parameter PAR_MACS   = 8;
    localparam NUM_STEPS = HEAD_DIM / PAR_MACS;

    logic clk, rst_n;
    logic start, done, busy;
    logic signed [DATA_WIDTH-1:0] q_data [TILE_BR-1:0][PAR_MACS-1:0];
    logic signed [DATA_WIDTH-1:0] k_data [TILE_BC-1:0][PAR_MACS-1:0];
    logic data_valid;
    logic signed [DATA_WIDTH-1:0] scale;
    logic signed [ACC_WIDTH-1:0] scores [TILE_BR-1:0][TILE_BC-1:0];
    logic scores_valid;

    dot_product_array #(
        .TILE_BR(TILE_BR), .TILE_BC(TILE_BC), .HEAD_DIM(HEAD_DIM),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .PAR_MACS(PAR_MACS)
    ) dut (.*);

    initial begin clk = 0; forever #1 clk = ~clk; end
    initial begin
        rst_n = 0; start = 0; data_valid = 0;
        scale = 16'h0020; // 1/8 ~= 1/sqrt(64)
        repeat(5) @(posedge clk); rst_n = 1;
    end

    // Q and K storage
    logic signed [DATA_WIDTH-1:0] Q_mem [TILE_BR-1:0][HEAD_DIM-1:0];
    logic signed [DATA_WIDTH-1:0] K_mem [TILE_BC-1:0][HEAD_DIM-1:0];

    integer i, j, k, step;
    integer pass_cnt, fail_cnt;

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        @(posedge rst_n); repeat(3) @(posedge clk);

        $display("=== Dot Product Array Test ===");

        // TC1: All ones
        $display("TC1: Q=1, K=1 (Q8.8 = 256)");
        for (i = 0; i < TILE_BR; i = i + 1)
            for (j = 0; j < HEAD_DIM; j = j + 1)
                Q_mem[i][j] = 16'sh0100; // 1.0 in Q8.8
        for (i = 0; i < TILE_BC; i = i + 1)
            for (j = 0; j < HEAD_DIM; j = j + 1)
                K_mem[i][j] = 16'sh0100;

        // Start
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;

        // Feed data step by step
        for (step = 0; step < NUM_STEPS; step = step + 1) begin
            @(posedge clk);
            for (i = 0; i < TILE_BR; i = i + 1)
                for (j = 0; j < PAR_MACS; j = j + 1)
                    q_data[i][j] = Q_mem[i][step * PAR_MACS + j];
            for (i = 0; i < TILE_BC; i = i + 1)
                for (j = 0; j < PAR_MACS; j = j + 1)
                    k_data[i][j] = K_mem[i][step * PAR_MACS + j];
            data_valid = 1;
        end
        @(posedge clk); data_valid = 0;

        // Wait for result
        wait(done); @(posedge clk);

        // Expected: Q[r] dot K[c] = 64 * 1 * 1 * 256 * 256 = 64 * 65536 = 4194304
        // After scale (*1/8 >> 8): 4194304 * 32 / 256 = 524288
        // Actually: scale = 0x0020 = 32 (0.125 in Q8.8)
        // acc = sum of 64 * (256 * 256) = 64 * 65536 = 4194304 (in Q16.16)
        // scaled = 4194304 * 32 >> 8 = 4194304 * 32 / 256 = 524288
        $display("Score[0][0] = %0d (expected ~524288 for dot(ones,ones)*scale)", scores[0][0]);
        if (scores[0][0] > 400000 && scores[0][0] < 700000) begin
            pass_cnt = pass_cnt + 1;
            $display("PASS TC1: Score in expected range");
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("FAIL TC1: Score out of range");
        end

        // TC2: Zero input
        $display("");
        $display("TC2: Q=0, K=0");
        for (i = 0; i < TILE_BR; i = i + 1)
            for (j = 0; j < HEAD_DIM; j = j + 1)
                Q_mem[i][j] = 0;
        for (i = 0; i < TILE_BC; i = i + 1)
            for (j = 0; j < HEAD_DIM; j = j + 1)
                K_mem[i][j] = 0;

        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        for (step = 0; step < NUM_STEPS; step = step + 1) begin
            @(posedge clk);
            for (i = 0; i < TILE_BR; i = i + 1)
                for (j = 0; j < PAR_MACS; j = j + 1)
                    q_data[i][j] = 0;
            for (i = 0; i < TILE_BC; i = i + 1)
                for (j = 0; j < PAR_MACS; j = j + 1)
                    k_data[i][j] = 0;
            data_valid = 1;
        end
        @(posedge clk); data_valid = 0;
        wait(done); @(posedge clk);

        if (scores[0][0] === 0) begin
            pass_cnt = pass_cnt + 1;
            $display("PASS TC2: Score = 0");
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("FAIL TC2: Score = %0d, expected 0", scores[0][0]);
        end

        $display("");
        $display("Results: %0d/%0d passed", pass_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0) $display(">>> ALL TESTS PASSED <<<");
        else $display(">>> %0d TESTS FAILED <<<", fail_cnt);
        $finish;
    end
endmodule
