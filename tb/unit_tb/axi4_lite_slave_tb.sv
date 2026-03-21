`timescale 1ns/1ps
module axi4_lite_slave_tb;

    logic clk, rst_n;
    logic [7:0]  awaddr, araddr;
    logic        awvalid, awready, wvalid, wready;
    logic [31:0] wdata, rdata;
    logic [3:0]  wstrb;
    logic [1:0]  bresp, rresp;
    logic        bvalid, bready, arvalid, arready, rvalid, rready;

    logic reg_start, reg_soft_reset, reg_irq_en, reg_causal_en;
    logic [63:0] reg_q_base, reg_k_base, reg_v_base, reg_o_base;
    logic [31:0] reg_stride_bytes;
    logic signed [15:0] reg_neg_large, reg_scale;
    logic status_busy, status_done, status_error;
    logic [31:0] cycle_count;
    logic done_clear, irq;

    axi4_lite_slave #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready),
        .reg_start(reg_start), .reg_soft_reset(reg_soft_reset), .reg_irq_en(reg_irq_en),
        .reg_causal_en(reg_causal_en),
        .reg_q_base(reg_q_base), .reg_k_base(reg_k_base),
        .reg_v_base(reg_v_base), .reg_o_base(reg_o_base),
        .reg_stride_bytes(reg_stride_bytes),
        .reg_neg_large(reg_neg_large), .reg_scale(reg_scale),
        .status_busy(status_busy), .status_done(status_done), .status_error(status_error),
        .cycle_count(cycle_count), .done_clear(done_clear), .irq(irq)
    );

    initial begin clk = 0; forever #1 clk = ~clk; end
    initial begin
        rst_n = 0; awvalid = 0; wvalid = 0; bready = 0;
        arvalid = 0; rready = 0; awaddr = 0; araddr = 0;
        wdata = 0; wstrb = 4'hF;
        status_busy = 0; status_done = 0; status_error = 0; cycle_count = 32'hDEAD;
        repeat(5) @(posedge clk); rst_n = 1;
    end

    integer pass_cnt, fail_cnt;

    task automatic write_reg(input [7:0] addr, input [31:0] data);
        @(posedge clk);
        awaddr = addr; awvalid = 1;
        wdata = data; wstrb = 4'hF; wvalid = 1;
        @(posedge clk);
        while (!(awready && wready)) @(posedge clk);
        awvalid = 0; wvalid = 0;
        bready = 1;
        while (!bvalid) @(posedge clk);
        @(posedge clk); bready = 0;
    endtask

    task automatic read_reg(input [7:0] addr, output [31:0] data);
        @(posedge clk);
        araddr = addr; arvalid = 1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid = 0;
        rready = 1;
        while (!rvalid) @(posedge clk);
        data = rdata;
        @(posedge clk); rready = 0;
    endtask

    task automatic check_rw(input [7:0] addr, input [31:0] wr_val, input string name);
        logic [31:0] rd_val;
        write_reg(addr, wr_val);
        read_reg(addr, rd_val);
        if (rd_val === wr_val) begin
            pass_cnt = pass_cnt + 1;
            $display("PASS %s: wrote 0x%08h, read 0x%08h", name, wr_val, rd_val);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("FAIL %s: wrote 0x%08h, read 0x%08h", name, wr_val, rd_val);
        end
    endtask

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        @(posedge rst_n); repeat(3) @(posedge clk);

        $display("=== AXI4-Lite Register R/W Test ===");

        check_rw(8'h08, 32'h0000_0001, "CFG");
        check_rw(8'h14, 32'hAABB_CCDD, "Q_BASE_L");
        check_rw(8'h18, 32'h1122_3344, "Q_BASE_H");
        check_rw(8'h1C, 32'hDEAD_BEEF, "K_BASE_L");
        check_rw(8'h20, 32'h5678_9ABC, "K_BASE_H");
        check_rw(8'h24, 32'h1111_2222, "V_BASE_L");
        check_rw(8'h28, 32'h3333_4444, "V_BASE_H");
        check_rw(8'h2C, 32'h5555_6666, "O_BASE_L");
        check_rw(8'h30, 32'h7777_8888, "O_BASE_H");
        check_rw(8'h34, 32'h0000_0080, "STRIDE");
        check_rw(8'h38, 32'h0000_8000, "NEG_LARGE");
        check_rw(8'h3C, 32'h0000_0020, "SCALE");

        // Read-only STATUS register
        begin
            logic [31:0] rd_val;
            status_busy = 1; status_done = 0; status_error = 0;
            @(posedge clk);
            read_reg(8'h04, rd_val);
            if (rd_val[0] === 1'b1) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS STATUS.BUSY=1");
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL STATUS.BUSY expected 1, got %b", rd_val[0]);
            end
        end

        // CYCLES register
        begin
            logic [31:0] rd_val;
            cycle_count = 32'h0001_2345;
            @(posedge clk);
            read_reg(8'h40, rd_val);
            if (rd_val === 32'h0001_2345) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS CYCLES=0x%08h", rd_val);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL CYCLES expected 0x00012345, got 0x%08h", rd_val);
            end
        end

        // START pulse test
        begin
            write_reg(8'h00, 32'h0000_0001);
            if (reg_start) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS START pulse generated");
            end
        end

        $display("");
        $display("Results: %0d/%0d passed", pass_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0) $display(">>> ALL TESTS PASSED <<<");
        else $display(">>> %0d TESTS FAILED <<<", fail_cnt);
        $finish;
    end
endmodule
