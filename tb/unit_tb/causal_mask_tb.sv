`timescale 1ns/1ps
module causal_mask_tb;
    parameter SEQ_LEN = 256;
    parameter TILE_BR = 4;
    parameter TILE_BC = 16;
    localparam IDX_W = $clog2(SEQ_LEN);

    logic causal_en;
    logic [IDX_W-1:0] q_tile_idx, kv_tile_idx;
    logic [$clog2(TILE_BR)-1:0] row_in_tile;
    logic [$clog2(TILE_BC)-1:0] col_in_tile;
    logic mask_out;

    causal_mask_unit #(
        .SEQ_LEN(SEQ_LEN), .TILE_BR(TILE_BR), .TILE_BC(TILE_BC)
    ) dut (.*);

    integer pass_cnt, fail_cnt;
    integer abs_row, abs_col;
    logic expected;

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        $display("=== Causal Mask Unit Test ===");

        // Test with causal_en = 1
        causal_en = 1;

        // TC1: First row (row=0), should mask everything except col=0
        q_tile_idx = 0; row_in_tile = 0;
        kv_tile_idx = 0; col_in_tile = 0;
        #1;
        if (mask_out == 0) pass_cnt = pass_cnt + 1; else fail_cnt = fail_cnt + 1;
        $display("row=0,col=0: mask=%b (expect 0) %s", mask_out, mask_out==0?"PASS":"FAIL");

        col_in_tile = 1;
        #1;
        if (mask_out == 1) pass_cnt = pass_cnt + 1; else fail_cnt = fail_cnt + 1;
        $display("row=0,col=1: mask=%b (expect 1) %s", mask_out, mask_out==1?"PASS":"FAIL");

        // TC2: Diagonal (row=col)
        q_tile_idx = 3; row_in_tile = 2; // abs_row = 14
        kv_tile_idx = 0; col_in_tile = 14; // abs_col = 14
        #1;
        if (mask_out == 0) pass_cnt = pass_cnt + 1; else fail_cnt = fail_cnt + 1;
        $display("row=14,col=14: mask=%b (expect 0) %s", mask_out, mask_out==0?"PASS":"FAIL");

        col_in_tile = 15; // abs_col = 15
        #1;
        if (mask_out == 1) pass_cnt = pass_cnt + 1; else fail_cnt = fail_cnt + 1;
        $display("row=14,col=15: mask=%b (expect 1) %s", mask_out, mask_out==1?"PASS":"FAIL");

        // TC3: Last row can see everything
        q_tile_idx = 63; row_in_tile = 3; // abs_row = 255
        kv_tile_idx = 15; col_in_tile = 15; // abs_col = 255
        #1;
        if (mask_out == 0) pass_cnt = pass_cnt + 1; else fail_cnt = fail_cnt + 1;
        $display("row=255,col=255: mask=%b (expect 0) %s", mask_out, mask_out==0?"PASS":"FAIL");

        // TC4: causal_en = 0 → never mask
        causal_en = 0;
        q_tile_idx = 0; row_in_tile = 0;
        kv_tile_idx = 15; col_in_tile = 15;
        #1;
        if (mask_out == 0) pass_cnt = pass_cnt + 1; else fail_cnt = fail_cnt + 1;
        $display("causal_en=0, row=0,col=255: mask=%b (expect 0) %s", mask_out, mask_out==0?"PASS":"FAIL");

        $display("");
        $display("Results: %0d/%0d passed", pass_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0) $display(">>> ALL TESTS PASSED <<<");
        else $display(">>> %0d TESTS FAILED <<<", fail_cnt);
        $finish;
    end
endmodule
