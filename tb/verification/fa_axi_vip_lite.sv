// ============================================================
// FlashAttention lightweight AXI VIP-lite monitors
// Checks key AXI4-Lite and AXI4 Master protocol rules used by
// the contest baseline testbench. This is not a commercial VIP
// replacement; it is a focused protocol checker for this IP.
// ============================================================
`timescale 1ns/1ps

module fa_axil_vip_lite_monitor #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [ADDR_WIDTH-1:0]   awaddr,
    input  logic                    awvalid,
    input  logic                    awready,
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [DATA_WIDTH/8-1:0] wstrb,
    input  logic                    wvalid,
    input  logic                    wready,
    input  logic [1:0]              bresp,
    input  logic                    bvalid,
    input  logic                    bready,
    input  logic [ADDR_WIDTH-1:0]   araddr,
    input  logic                    arvalid,
    input  logic                    arready,
    input  logic [DATA_WIDTH-1:0]   rdata,
    input  logic [1:0]              rresp,
    input  logic                    rvalid,
    input  logic                    rready,

    output longint unsigned         aw_count,
    output longint unsigned         w_count,
    output longint unsigned         b_count,
    output longint unsigned         ar_count,
    output longint unsigned         r_count
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    logic aw_stall_q, w_stall_q, ar_stall_q, r_stall_q;
    logic [ADDR_WIDTH-1:0] awaddr_hold, araddr_hold;
    logic [DATA_WIDTH-1:0] wdata_hold, rdata_hold;
    logic [STRB_WIDTH-1:0] wstrb_hold;
    logic [1:0] rresp_hold;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_stall_q <= 1'b0;
            w_stall_q  <= 1'b0;
            ar_stall_q <= 1'b0;
            r_stall_q  <= 1'b0;
            aw_count   <= 0;
            w_count    <= 0;
            b_count    <= 0;
            ar_count   <= 0;
            r_count    <= 0;
        end else begin
            if (awvalid && $isunknown({awaddr, awvalid, awready}))
                $fatal(1, "AXIL VIP-lite: X/Z on AW channel");
            if (wvalid && $isunknown({wdata, wstrb, wvalid, wready}))
                $fatal(1, "AXIL VIP-lite: X/Z on W channel");
            if (arvalid && $isunknown({araddr, arvalid, arready}))
                $fatal(1, "AXIL VIP-lite: X/Z on AR channel");
            if (rvalid && $isunknown({rdata, rresp, rvalid, rready}))
                $fatal(1, "AXIL VIP-lite: X/Z on R channel");
            if (bvalid && $isunknown({bresp, bvalid, bready}))
                $fatal(1, "AXIL VIP-lite: X/Z on B channel");

            if (aw_stall_q) begin
                if (!awvalid)
                    $fatal(1, "AXIL VIP-lite: AWVALID dropped before AWREADY");
                if (awaddr !== awaddr_hold)
                    $fatal(1, "AXIL VIP-lite: AWADDR changed while stalled");
            end
            if (w_stall_q) begin
                if (!wvalid)
                    $fatal(1, "AXIL VIP-lite: WVALID dropped before WREADY");
                if (wdata !== wdata_hold || wstrb !== wstrb_hold)
                    $fatal(1, "AXIL VIP-lite: W payload changed while stalled");
            end
            if (ar_stall_q) begin
                if (!arvalid)
                    $fatal(1, "AXIL VIP-lite: ARVALID dropped before ARREADY");
                if (araddr !== araddr_hold)
                    $fatal(1, "AXIL VIP-lite: ARADDR changed while stalled");
            end
            if (r_stall_q) begin
                if (!rvalid)
                    $fatal(1, "AXIL VIP-lite: RVALID dropped before RREADY");
                if (rdata !== rdata_hold || rresp !== rresp_hold)
                    $fatal(1, "AXIL VIP-lite: R payload changed while stalled");
            end

            if (wvalid && wready && wstrb == '0)
                $fatal(1, "AXIL VIP-lite: zero WSTRB write is not used by this verification plan");
            if (bvalid && bresp != 2'b00)
                $fatal(1, "AXIL VIP-lite: non-OKAY BRESP");
            if (rvalid && rresp != 2'b00)
                $fatal(1, "AXIL VIP-lite: non-OKAY RRESP");

            if (awvalid && awready)
                aw_count <= aw_count + 1;
            if (wvalid && wready)
                w_count <= w_count + 1;
            if (bvalid && bready)
                b_count <= b_count + 1;
            if (arvalid && arready)
                ar_count <= ar_count + 1;
            if (rvalid && rready)
                r_count <= r_count + 1;

            if (awvalid && !awready) begin
                aw_stall_q   <= 1'b1;
                awaddr_hold  <= awaddr;
            end else begin
                aw_stall_q   <= 1'b0;
            end

            if (wvalid && !wready) begin
                w_stall_q    <= 1'b1;
                wdata_hold   <= wdata;
                wstrb_hold   <= wstrb;
            end else begin
                w_stall_q    <= 1'b0;
            end

            if (arvalid && !arready) begin
                ar_stall_q   <= 1'b1;
                araddr_hold  <= araddr;
            end else begin
                ar_stall_q   <= 1'b0;
            end

            if (rvalid && !rready) begin
                r_stall_q    <= 1'b1;
                rdata_hold   <= rdata;
                rresp_hold   <= rresp;
            end else begin
                r_stall_q    <= 1'b0;
            end
        end
    end

endmodule

module fa_axi4_master_vip_lite_monitor #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 128,
    parameter ID_WIDTH   = 4
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [ID_WIDTH-1:0]     awid,
    input  logic [ADDR_WIDTH-1:0]   awaddr,
    input  logic [7:0]              awlen,
    input  logic [2:0]              awsize,
    input  logic [1:0]              awburst,
    input  logic                    awvalid,
    input  logic                    awready,
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [DATA_WIDTH/8-1:0] wstrb,
    input  logic                    wlast,
    input  logic                    wvalid,
    input  logic                    wready,
    input  logic [ID_WIDTH-1:0]     bid,
    input  logic [1:0]              bresp,
    input  logic                    bvalid,
    input  logic                    bready,
    input  logic [ID_WIDTH-1:0]     arid,
    input  logic [ADDR_WIDTH-1:0]   araddr,
    input  logic [7:0]              arlen,
    input  logic [2:0]              arsize,
    input  logic [1:0]              arburst,
    input  logic                    arvalid,
    input  logic                    arready,
    input  logic [ID_WIDTH-1:0]     rid,
    input  logic [DATA_WIDTH-1:0]   rdata,
    input  logic [1:0]              rresp,
    input  logic                    rlast,
    input  logic                    rvalid,
    input  logic                    rready,

    output longint unsigned         aw_count,
    output longint unsigned         w_beat_count,
    output longint unsigned         b_count,
    output longint unsigned         ar_count,
    output longint unsigned         r_beat_count,
    output longint unsigned         read_bytes,
    output longint unsigned         write_bytes
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam SIZE_CODE  = $clog2(STRB_WIDTH);

    logic aw_stall_q, w_stall_q, ar_stall_q, r_stall_q;
    logic [ID_WIDTH-1:0] awid_hold, arid_hold, rid_hold;
    logic [ADDR_WIDTH-1:0] awaddr_hold, araddr_hold;
    logic [7:0] awlen_hold, arlen_hold;
    logic [2:0] awsize_hold, arsize_hold;
    logic [1:0] awburst_hold, arburst_hold, rresp_hold;
    logic [DATA_WIDTH-1:0] wdata_hold, rdata_hold;
    logic [STRB_WIDTH-1:0] wstrb_hold;
    logic wlast_hold, rlast_hold;

    logic wr_active, rd_active;
    logic [8:0] wr_expected_beats, wr_seen_beats;
    logic [8:0] rd_expected_beats, rd_seen_beats;

    function automatic logic [12:0] offset_plus_bytes(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0] len,
        input logic [2:0] size
    );
        begin
            offset_plus_bytes = {1'b0, addr[11:0]} + ((({5'd0, len} + 13'd1) << size));
        end
    endfunction

    function automatic longint unsigned burst_byte_count(
        input logic [7:0] len,
        input logic [2:0] size
    );
        begin
            burst_byte_count = (longint'(len) + 1) << size;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_stall_q       <= 1'b0;
            w_stall_q        <= 1'b0;
            ar_stall_q       <= 1'b0;
            r_stall_q        <= 1'b0;
            wr_active        <= 1'b0;
            rd_active        <= 1'b0;
            wr_expected_beats <= '0;
            wr_seen_beats    <= '0;
            rd_expected_beats <= '0;
            rd_seen_beats    <= '0;
            aw_count         <= 0;
            w_beat_count     <= 0;
            b_count          <= 0;
            ar_count         <= 0;
            r_beat_count     <= 0;
            read_bytes       <= 0;
            write_bytes      <= 0;
        end else begin
            if (awvalid && $isunknown({awid, awaddr, awlen, awsize, awburst, awvalid, awready}))
                $fatal(1, "AXI4 VIP-lite: X/Z on AW channel");
            if (wvalid && $isunknown({wdata, wstrb, wlast, wvalid, wready}))
                $fatal(1, "AXI4 VIP-lite: X/Z on W channel");
            if (bvalid && $isunknown({bid, bresp, bvalid, bready}))
                $fatal(1, "AXI4 VIP-lite: X/Z on B channel");
            if (arvalid && $isunknown({arid, araddr, arlen, arsize, arburst, arvalid, arready}))
                $fatal(1, "AXI4 VIP-lite: X/Z on AR channel");
            if (rvalid && $isunknown({rid, rdata, rresp, rlast, rvalid, rready}))
                $fatal(1, "AXI4 VIP-lite: X/Z on R channel");

            if (aw_stall_q) begin
                if (!awvalid)
                    $fatal(1, "AXI4 VIP-lite: AWVALID dropped before AWREADY");
                if (awid !== awid_hold || awaddr !== awaddr_hold || awlen !== awlen_hold ||
                    awsize !== awsize_hold || awburst !== awburst_hold)
                    $fatal(1, "AXI4 VIP-lite: AW payload changed while stalled");
            end
            if (w_stall_q) begin
                if (!wvalid)
                    $fatal(1, "AXI4 VIP-lite: WVALID dropped before WREADY");
                if (wdata !== wdata_hold || wstrb !== wstrb_hold || wlast !== wlast_hold)
                    $fatal(1, "AXI4 VIP-lite: W payload changed while stalled");
            end
            if (ar_stall_q) begin
                if (!arvalid)
                    $fatal(1, "AXI4 VIP-lite: ARVALID dropped before ARREADY");
                if (arid !== arid_hold || araddr !== araddr_hold || arlen !== arlen_hold ||
                    arsize !== arsize_hold || arburst !== arburst_hold)
                    $fatal(1, "AXI4 VIP-lite: AR payload changed while stalled");
            end
            if (r_stall_q) begin
                if (!rvalid)
                    $fatal(1, "AXI4 VIP-lite: RVALID dropped before RREADY");
                if (rid !== rid_hold || rdata !== rdata_hold || rresp !== rresp_hold ||
                    rlast !== rlast_hold)
                    $fatal(1, "AXI4 VIP-lite: R payload changed while stalled");
            end

            if (awvalid && awready) begin
                if (wr_active)
                    $fatal(1, "AXI4 VIP-lite: new AW before previous write burst completed");
                if (awsize != SIZE_CODE[2:0])
                    $fatal(1, "AXI4 VIP-lite: illegal AWSIZE");
                if (awburst != 2'b01)
                    $fatal(1, "AXI4 VIP-lite: illegal AWBURST");
                if (awaddr[SIZE_CODE-1:0] != '0)
                    $fatal(1, "AXI4 VIP-lite: unaligned AWADDR");
                if (offset_plus_bytes(awaddr, awlen, awsize) > 13'd4096)
                    $fatal(1, "AXI4 VIP-lite: write burst crosses 4KB boundary");
                wr_active         <= 1'b1;
                wr_expected_beats <= {1'b0, awlen} + 9'd1;
                wr_seen_beats     <= '0;
                aw_count          <= aw_count + 1;
                write_bytes       <= write_bytes + burst_byte_count(awlen, awsize);
            end

            if (wvalid && wready) begin
                if (!wr_active)
                    $fatal(1, "AXI4 VIP-lite: W beat without active AW burst");
                if (wstrb != {STRB_WIDTH{1'b1}})
                    $fatal(1, "AXI4 VIP-lite: WSTRB is not full for 128-bit writeback");
                if (wlast != (wr_seen_beats == wr_expected_beats - 1))
                    $fatal(1, "AXI4 VIP-lite: WLAST does not match AWLEN");
                wr_seen_beats <= wr_seen_beats + 1;
                w_beat_count  <= w_beat_count + 1;
                if (wlast)
                    wr_active <= 1'b0;
            end

            if (bvalid) begin
                if (bresp != 2'b00)
                    $fatal(1, "AXI4 VIP-lite: non-OKAY BRESP");
                if (bready)
                    b_count <= b_count + 1;
            end

            if (arvalid && arready) begin
                if (rd_active)
                    $fatal(1, "AXI4 VIP-lite: new AR before previous read burst completed");
                if (arsize != SIZE_CODE[2:0])
                    $fatal(1, "AXI4 VIP-lite: illegal ARSIZE");
                if (arburst != 2'b01)
                    $fatal(1, "AXI4 VIP-lite: illegal ARBURST");
                if (araddr[SIZE_CODE-1:0] != '0)
                    $fatal(1, "AXI4 VIP-lite: unaligned ARADDR");
                if (offset_plus_bytes(araddr, arlen, arsize) > 13'd4096)
                    $fatal(1, "AXI4 VIP-lite: read burst crosses 4KB boundary");
                rd_active         <= 1'b1;
                rd_expected_beats <= {1'b0, arlen} + 9'd1;
                rd_seen_beats     <= '0;
                ar_count          <= ar_count + 1;
                read_bytes        <= read_bytes + burst_byte_count(arlen, arsize);
            end

            if (rvalid && rready) begin
                if (!rd_active)
                    $fatal(1, "AXI4 VIP-lite: R beat without active AR burst");
                if (rresp != 2'b00)
                    $fatal(1, "AXI4 VIP-lite: non-OKAY RRESP");
                if (rlast != (rd_seen_beats == rd_expected_beats - 1))
                    $fatal(1, "AXI4 VIP-lite: RLAST does not match ARLEN");
                rd_seen_beats <= rd_seen_beats + 1;
                r_beat_count  <= r_beat_count + 1;
                if (rlast)
                    rd_active <= 1'b0;
            end

            if (awvalid && !awready) begin
                aw_stall_q  <= 1'b1;
                awid_hold   <= awid;
                awaddr_hold <= awaddr;
                awlen_hold  <= awlen;
                awsize_hold <= awsize;
                awburst_hold <= awburst;
            end else begin
                aw_stall_q <= 1'b0;
            end

            if (wvalid && !wready) begin
                w_stall_q  <= 1'b1;
                wdata_hold <= wdata;
                wstrb_hold <= wstrb;
                wlast_hold <= wlast;
            end else begin
                w_stall_q <= 1'b0;
            end

            if (arvalid && !arready) begin
                ar_stall_q  <= 1'b1;
                arid_hold   <= arid;
                araddr_hold <= araddr;
                arlen_hold  <= arlen;
                arsize_hold <= arsize;
                arburst_hold <= arburst;
            end else begin
                ar_stall_q <= 1'b0;
            end

            if (rvalid && !rready) begin
                r_stall_q  <= 1'b1;
                rid_hold   <= rid;
                rdata_hold <= rdata;
                rresp_hold <= rresp;
                rlast_hold <= rlast;
            end else begin
                r_stall_q <= 1'b0;
            end
        end
    end

endmodule
