// ============================================================
// AXI4-Lite Protocol Checker — SVA Assertions
// Validates AXI4-Lite protocol compliance on slave interface
// ============================================================
module axi4_lite_protocol_checker #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input logic                    clk,
    input logic                    rst_n,

    // Write Address
    input logic [ADDR_WIDTH-1:0]   awaddr,
    input logic                    awvalid,
    input logic                    awready,

    // Write Data
    input logic [DATA_WIDTH-1:0]   wdata,
    input logic [DATA_WIDTH/8-1:0] wstrb,
    input logic                    wvalid,
    input logic                    wready,

    // Write Response
    input logic [1:0]              bresp,
    input logic                    bvalid,
    input logic                    bready,

    // Read Address
    input logic [ADDR_WIDTH-1:0]   araddr,
    input logic                    arvalid,
    input logic                    arready,

    // Read Data
    input logic [DATA_WIDTH-1:0]   rdata,
    input logic [1:0]              rresp,
    input logic                    rvalid,
    input logic                    rready
);

    // Transaction counters
    int wr_count, rd_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_count <= 0; rd_count <= 0;
        end else begin
            if (bvalid && bready) wr_count <= wr_count + 1;
            if (rvalid && rready) rd_count <= rd_count + 1;
        end
    end

    // =============== Write Address Channel ===============

    AXIL_AW_STABLE_ADDR: assert property (
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> ($stable(awaddr) && awvalid)
    ) else $error("AXIL: AWADDR changed while AWVALID && !AWREADY");

    AXIL_AW_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> awvalid
    ) else $error("AXIL: AWVALID deasserted without AWREADY");

    AXIL_AW_ALIGN: assert property (
        @(posedge clk) disable iff (!rst_n)
        awvalid |-> (awaddr[1:0] == 2'b00)
    ) else $error("AXIL: AWADDR not 4-byte aligned");

    // =============== Write Data Channel ===============

    AXIL_W_STABLE_DATA: assert property (
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> ($stable(wdata) && wvalid)
    ) else $error("AXIL: WDATA changed while WVALID && !WREADY");

    AXIL_W_STABLE_STRB: assert property (
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> ($stable(wstrb) && wvalid)
    ) else $error("AXIL: WSTRB changed while WVALID && !WREADY");

    AXIL_W_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> wvalid
    ) else $error("AXIL: WVALID deasserted without WREADY");

    // =============== Write Response Channel ===============

    AXIL_B_STABLE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (bvalid && !bready) |=> ($stable(bresp) && bvalid)
    ) else $error("AXIL: BRESP changed while BVALID && !BREADY");

    AXIL_B_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (bvalid && !bready) |=> bvalid
    ) else $error("AXIL: BVALID deasserted without BREADY");

    // =============== Read Address Channel ===============

    AXIL_AR_STABLE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> ($stable(araddr) && arvalid)
    ) else $error("AXIL: ARADDR changed while ARVALID && !ARREADY");

    AXIL_AR_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> arvalid
    ) else $error("AXIL: ARVALID deasserted without ARREADY");

    AXIL_AR_ALIGN: assert property (
        @(posedge clk) disable iff (!rst_n)
        arvalid |-> (araddr[1:0] == 2'b00)
    ) else $error("AXIL: ARADDR not 4-byte aligned");

    // =============== Read Data Channel ===============

    AXIL_R_STABLE_DATA: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> ($stable(rdata) && rvalid)
    ) else $error("AXIL: RDATA changed while RVALID && !RREADY");

    AXIL_R_STABLE_RESP: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> ($stable(rresp) && rvalid)
    ) else $error("AXIL: RRESP changed while RVALID && !RREADY");

    AXIL_R_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> rvalid
    ) else $error("AXIL: RVALID deasserted without RREADY");

    // =============== X-Checks ===============

    AXIL_AW_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(awvalid)
    ) else $error("AXIL: AWVALID is X/Z");

    AXIL_W_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(wvalid)
    ) else $error("AXIL: WVALID is X/Z");

    AXIL_B_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(bvalid)
    ) else $error("AXIL: BVALID is X/Z");

    AXIL_AR_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(arvalid)
    ) else $error("AXIL: ARVALID is X/Z");

    AXIL_R_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(rvalid)
    ) else $error("AXIL: RVALID is X/Z");

    // =============== Coverage ===============

    covergroup axil_txn_cg @(posedge clk);
        option.per_instance = 1;

        wr_addr_cp: coverpoint awaddr iff (awvalid && awready) {
            bins ctrl       = {8'h00};
            bins status     = {8'h04};
            bins cfg        = {8'h08};
            bins q_base_l   = {8'h14};
            bins q_base_h   = {8'h18};
            bins k_base_l   = {8'h1C};
            bins k_base_h   = {8'h20};
            bins v_base_l   = {8'h24};
            bins v_base_h   = {8'h28};
            bins o_base_l   = {8'h2C};
            bins o_base_h   = {8'h30};
            bins stride     = {8'h34};
            bins neg_large  = {8'h38};
            bins scale      = {8'h3C};
            bins invalid    = default;
        }
        rd_addr_cp: coverpoint araddr iff (arvalid && arready) {
            bins ctrl       = {8'h00};
            bins status     = {8'h04};
            bins cfg        = {8'h08};
            bins q_base_l   = {8'h14};
            bins q_base_h   = {8'h18};
            bins k_base_l   = {8'h1C};
            bins k_base_h   = {8'h20};
            bins v_base_l   = {8'h24};
            bins v_base_h   = {8'h28};
            bins o_base_l   = {8'h2C};
            bins o_base_h   = {8'h30};
            bins stride     = {8'h34};
            bins neg_large  = {8'h38};
            bins scale      = {8'h3C};
            bins cycles     = {8'h40};
            bins invalid    = default;
        }
        wstrb_cp: coverpoint wstrb iff (wvalid && wready) {
            bins all_bytes = {4'hF};
            bins partial   = default;
        }
        bresp_cp: coverpoint bresp iff (bvalid && bready) {
            bins okay = {2'b00};
            bins err  = default;
        }
        rresp_cp: coverpoint rresp iff (rvalid && rready) {
            bins okay = {2'b00};
            bins err  = default;
        }
    endgroup

    axil_txn_cg cg_inst = new();

    final begin
        $display("AXIL_CHECKER: WR=%0d RD=%0d", wr_count, rd_count);
    end

endmodule
