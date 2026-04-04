// ============================================================
// AXI4 Protocol Checker — SVA Assertions
// Validates AXI4 protocol compliance on master interface
// ============================================================
module axi4_protocol_checker #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 128,
    parameter ID_WIDTH   = 4
)(
    input logic                    clk,
    input logic                    rst_n,

    // Write Address Channel
    input logic [ID_WIDTH-1:0]     awid,
    input logic [ADDR_WIDTH-1:0]   awaddr,
    input logic [7:0]              awlen,
    input logic [2:0]              awsize,
    input logic [1:0]              awburst,
    input logic                    awvalid,
    input logic                    awready,

    // Write Data Channel
    input logic [DATA_WIDTH-1:0]   wdata,
    input logic [DATA_WIDTH/8-1:0] wstrb,
    input logic                    wlast,
    input logic                    wvalid,
    input logic                    wready,

    // Write Response Channel
    input logic [ID_WIDTH-1:0]     bid,
    input logic [1:0]              bresp,
    input logic                    bvalid,
    input logic                    bready,

    // Read Address Channel
    input logic [ID_WIDTH-1:0]     arid,
    input logic [ADDR_WIDTH-1:0]   araddr,
    input logic [7:0]              arlen,
    input logic [2:0]              arsize,
    input logic [1:0]              arburst,
    input logic                    arvalid,
    input logic                    arready,

    // Read Data Channel
    input logic [ID_WIDTH-1:0]     rid,
    input logic [DATA_WIDTH-1:0]   rdata,
    input logic [1:0]              rresp,
    input logic                    rlast,
    input logic                    rvalid,
    input logic                    rready
);

    // =============== Transaction Counters ===============
    int aw_count, w_count, b_count;
    int ar_count, r_count;
    int aw_outstanding, ar_outstanding;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_count <= 0; w_count <= 0; b_count <= 0;
            ar_count <= 0; r_count <= 0;
            aw_outstanding <= 0; ar_outstanding <= 0;
        end else begin
            if (awvalid && awready) begin
                aw_count <= aw_count + 1;
                aw_outstanding <= aw_outstanding + 1;
            end
            if (wvalid && wready && wlast) w_count <= w_count + 1;
            if (bvalid && bready) begin
                b_count <= b_count + 1;
                aw_outstanding <= aw_outstanding - 1;
            end
            if (arvalid && arready) begin
                ar_count <= ar_count + 1;
                ar_outstanding <= ar_outstanding + 1;
            end
            if (rvalid && rready && rlast) begin
                r_count <= r_count + 1;
                ar_outstanding <= ar_outstanding - 1;
            end
        end
    end

    // =============== Write Address Channel ===============

    // AW_STABLE: Once AWVALID is asserted, AWADDR/AWLEN/AWSIZE/AWBURST must stay stable
    property aw_stable_p(signal);
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> ($stable(signal) && awvalid);
    endproperty

    AW_ADDR_STABLE: assert property (aw_stable_p(awaddr))
        else $error("AXI4: AWADDR changed while AWVALID && !AWREADY");
    AW_LEN_STABLE: assert property (aw_stable_p(awlen))
        else $error("AXI4: AWLEN changed while AWVALID && !AWREADY");
    AW_SIZE_STABLE: assert property (aw_stable_p(awsize))
        else $error("AXI4: AWSIZE changed while AWVALID && !AWREADY");
    AW_BURST_STABLE: assert property (aw_stable_p(awburst))
        else $error("AXI4: AWBURST changed while AWVALID && !AWREADY");
    AW_ID_STABLE: assert property (aw_stable_p(awid))
        else $error("AXI4: AWID changed while AWVALID && !AWREADY");

    // AWVALID cannot deassert without handshake
    AW_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> awvalid
    ) else $error("AXI4: AWVALID deasserted without AWREADY");

    // AWSIZE must not exceed data bus width
    AW_SIZE_VALID: assert property (
        @(posedge clk) disable iff (!rst_n)
        awvalid |-> (awsize <= $clog2(DATA_WIDTH/8))
    ) else $error("AXI4: AWSIZE exceeds data bus width");

    // AWBURST: only FIXED(0), INCR(1), WRAP(2) allowed
    AW_BURST_VALID: assert property (
        @(posedge clk) disable iff (!rst_n)
        awvalid |-> (awburst inside {2'b00, 2'b01, 2'b10})
    ) else $error("AXI4: AWBURST invalid value");

    // =============== Write Data Channel ===============

    property w_stable_p(signal);
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> ($stable(signal) && wvalid);
    endproperty

    W_DATA_STABLE: assert property (w_stable_p(wdata))
        else $error("AXI4: WDATA changed while WVALID && !WREADY");
    W_STRB_STABLE: assert property (w_stable_p(wstrb))
        else $error("AXI4: WSTRB changed while WVALID && !WREADY");
    W_LAST_STABLE: assert property (w_stable_p(wlast))
        else $error("AXI4: WLAST changed while WVALID && !WREADY");

    W_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> wvalid
    ) else $error("AXI4: WVALID deasserted without WREADY");

    // =============== Write Response Channel ===============

    B_RESP_STABLE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (bvalid && !bready) |=> ($stable(bresp) && bvalid)
    ) else $error("AXI4: BRESP changed while BVALID && !BREADY");

    B_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (bvalid && !bready) |=> bvalid
    ) else $error("AXI4: BVALID deasserted without BREADY");

    // =============== Read Address Channel ===============

    property ar_stable_p(signal);
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> ($stable(signal) && arvalid);
    endproperty

    AR_ADDR_STABLE: assert property (ar_stable_p(araddr))
        else $error("AXI4: ARADDR changed while ARVALID && !ARREADY");
    AR_LEN_STABLE: assert property (ar_stable_p(arlen))
        else $error("AXI4: ARLEN changed while ARVALID && !ARREADY");
    AR_SIZE_STABLE: assert property (ar_stable_p(arsize))
        else $error("AXI4: ARSIZE changed while ARVALID && !ARREADY");
    AR_BURST_STABLE: assert property (ar_stable_p(arburst))
        else $error("AXI4: ARBURST changed while ARVALID && !ARREADY");
    AR_ID_STABLE: assert property (ar_stable_p(arid))
        else $error("AXI4: ARID changed while ARVALID && !ARREADY");

    AR_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> arvalid
    ) else $error("AXI4: ARVALID deasserted without ARREADY");

    AR_SIZE_VALID: assert property (
        @(posedge clk) disable iff (!rst_n)
        arvalid |-> (arsize <= $clog2(DATA_WIDTH/8))
    ) else $error("AXI4: ARSIZE exceeds data bus width");

    AR_BURST_VALID: assert property (
        @(posedge clk) disable iff (!rst_n)
        arvalid |-> (arburst inside {2'b00, 2'b01, 2'b10})
    ) else $error("AXI4: ARBURST invalid value");

    // =============== Read Data Channel ===============

    property r_stable_p(signal);
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> ($stable(signal) && rvalid);
    endproperty

    R_DATA_STABLE: assert property (r_stable_p(rdata))
        else $error("AXI4: RDATA changed while RVALID && !RREADY");
    R_RESP_STABLE: assert property (r_stable_p(rresp))
        else $error("AXI4: RRESP changed while RVALID && !RREADY");
    R_LAST_STABLE: assert property (r_stable_p(rlast))
        else $error("AXI4: RLAST changed while RVALID && !RREADY");

    R_VALID_HOLD: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> rvalid
    ) else $error("AXI4: RVALID deasserted without RREADY");

    // =============== X-Checks (no X/Z on control signals) ===============

    AW_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(awvalid)
    ) else $error("AXI4: AWVALID is X/Z");

    W_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(wvalid)
    ) else $error("AXI4: WVALID is X/Z");

    B_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(bvalid)
    ) else $error("AXI4: BVALID is X/Z");

    AR_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(arvalid)
    ) else $error("AXI4: ARVALID is X/Z");

    R_NO_X: assert property (
        @(posedge clk) disable iff (!rst_n) !$isunknown(rvalid)
    ) else $error("AXI4: RVALID is X/Z");

    // =============== Coverage ===============

    covergroup axi4_txn_cg @(posedge clk);
        option.per_instance = 1;

        aw_burst_cp: coverpoint awburst iff (awvalid && awready) {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }
        aw_len_cp: coverpoint awlen iff (awvalid && awready) {
            bins single = {0};
            bins short_burst = {[1:3]};
            bins mid_burst = {[4:15]};
            bins long_burst = {[16:$]};
        }
        aw_size_cp: coverpoint awsize iff (awvalid && awready) {
            bins byte_1  = {3'd0};
            bins byte_2  = {3'd1};
            bins byte_4  = {3'd2};
            bins byte_8  = {3'd3};
            bins byte_16 = {3'd4};
        }
        ar_burst_cp: coverpoint arburst iff (arvalid && arready) {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }
        ar_len_cp: coverpoint arlen iff (arvalid && arready) {
            bins single = {0};
            bins short_burst = {[1:3]};
            bins mid_burst = {[4:15]};
            bins long_burst = {[16:$]};
        }
        bresp_cp: coverpoint bresp iff (bvalid && bready) {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }
        rresp_cp: coverpoint rresp iff (rvalid && rready) {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }
    endgroup

    axi4_txn_cg cg_inst = new();

    // =============== Final Report ===============
    final begin
        $display("AXI4_CHECKER: AW=%0d W=%0d B=%0d | AR=%0d R=%0d",
                 aw_count, w_count, b_count, ar_count, r_count);
    end

endmodule
