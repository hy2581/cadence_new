// ============================================================
// AXI4 Slave Memory Model — Module-based (RTL style)
// Clean timing, no procedural blocks
// ============================================================
`timescale 1ns/1ps
module axi4_slave_mem (
    input  logic         clk,
    input  logic         rst_n,

    // AXI4 Read Address
    input  logic [63:0]  araddr,
    input  logic [7:0]   arlen,
    input  logic [2:0]   arsize,
    input  logic         arvalid,
    output logic         arready,

    // AXI4 Read Data
    output logic [127:0] rdata,
    output logic [1:0]   rresp,
    output logic         rlast,
    output logic         rvalid,
    input  logic         rready,

    // AXI4 Write Address
    input  logic [63:0]  awaddr,
    input  logic [7:0]   awlen,
    input  logic [2:0]   awsize,
    input  logic         awvalid,
    output logic         awready,

    // AXI4 Write Data
    input  logic [127:0] wdata,
    input  logic [15:0]  wstrb,
    input  logic         wlast,
    input  logic         wvalid,
    output logic         wready,

    // AXI4 Write Response
    output logic [1:0]   bresp,
    output logic         bvalid,
    input  logic         bready,

    // Memory load/read interface (for TB setup)
    input  logic         mem_wr_en,
    input  logic [63:0]  mem_wr_addr,
    input  logic [15:0]  mem_wr_data16,

    input  logic         mem_rd_en,
    input  logic [63:0]  mem_rd_addr,
    output logic [15:0]  mem_rd_data16
);

    // Byte-addressable memory
    reg [7:0] mem [*];

    // --- TB memory access ---
    always @(posedge clk) begin
        if (mem_wr_en) begin
            mem[mem_wr_addr]     = mem_wr_data16[7:0];
            mem[mem_wr_addr + 1] = mem_wr_data16[15:8];
        end
    end

    always @(*) begin
        if (mem_rd_en) begin
            reg [7:0] lo, hi;
            lo = mem.exists(mem_rd_addr) ? mem[mem_rd_addr] : 8'h0;
            hi = mem.exists(mem_rd_addr+1) ? mem[mem_rd_addr+1] : 8'h0;
            mem_rd_data16 = {hi, lo};
        end else begin
            mem_rd_data16 = 16'h0;
        end
    end

    // ========== Read Channel FSM ==========
    typedef enum logic [1:0] { RD_IDLE, RD_DATA } rd_fsm_t;
    rd_fsm_t rd_fsm;

    reg [63:0] rd_addr;
    reg [8:0]  rd_cnt;  // 9-bit to count up to 256
    reg [8:0]  rd_len;  // arlen + 1
    reg [2:0]  rd_size;

    assign rresp = 2'b00;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_fsm   <= RD_IDLE;
            arready  <= 1'b0;
            rvalid   <= 1'b0;
            rlast    <= 1'b0;
            rdata    <= '0;
            rd_addr  <= '0;
            rd_cnt   <= '0;
            rd_len   <= '0;
            rd_size  <= '0;
        end else begin
            case (rd_fsm)
                RD_IDLE: begin
                    rvalid <= 1'b0;
                    rlast  <= 1'b0;
                    if (arvalid) begin
                        arready <= 1'b1;
                        rd_addr <= araddr;
                        rd_len  <= {1'b0, arlen} + 9'd1;
                        rd_size <= arsize;
                        rd_cnt  <= '0;
                        rd_fsm  <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    arready <= 1'b0;

                    if (!rvalid) begin
                        // Present new data
                        integer b, beat_bytes;
                        beat_bytes = 1 << rd_size;
                        for (b = 0; b < 16; b = b + 1)
                            rdata[b*8 +: 8] <= (b < beat_bytes && mem.exists(rd_addr + b)) ?
                                                mem[rd_addr + b] : 8'h0;
                        rvalid <= 1'b1;
                        rlast  <= (rd_cnt == rd_len - 1);
                    end else if (rvalid && rready) begin
                        // Beat accepted
                        rd_cnt <= rd_cnt + 1;
                        if (rlast) begin
                            // Transfer complete
                            rvalid <= 1'b0;
                            rlast  <= 1'b0;
                            rd_fsm <= RD_IDLE;
                        end else begin
                            // Advance to next beat
                            integer b2, beat_bytes2;
                            beat_bytes2 = 1 << rd_size;
                            rd_addr <= rd_addr + (64'd1 << rd_size);
                            for (b2 = 0; b2 < 16; b2 = b2 + 1)
                                rdata[b2*8 +: 8] <= (b2 < beat_bytes2 &&
                                    mem.exists(rd_addr + (64'd1 << rd_size) + b2)) ?
                                    mem[rd_addr + (64'd1 << rd_size) + b2] : 8'h0;
                            rlast <= (rd_cnt + 1 == rd_len - 1);
                        end
                    end
                end
            endcase
        end
    end

    // ========== Write Channel FSM ==========
    typedef enum logic [1:0] { WR_IDLE, WR_DATA, WR_RESP } wr_fsm_t;
    wr_fsm_t wr_fsm;

    reg [63:0] wr_addr;
    reg [2:0]  wr_size;

    assign bresp = 2'b00;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_fsm  <= WR_IDLE;
            awready <= 1'b0;
            wready  <= 1'b0;
            bvalid  <= 1'b0;
            wr_addr <= '0;
            wr_size <= '0;
        end else begin
            case (wr_fsm)
                WR_IDLE: begin
                    bvalid <= 1'b0;
                    if (awvalid) begin
                        awready <= 1'b1;
                        wr_addr <= awaddr;
                        wr_size <= awsize;
                        wr_fsm  <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    awready <= 1'b0;
                    wready  <= 1'b1;

                    if (wvalid && wready) begin
                        integer b, beat_bytes;
                        beat_bytes = 1 << wr_size;
                        for (b = 0; b < beat_bytes; b = b + 1)
                            if (wstrb[b])
                                mem[wr_addr + b] = wdata[b*8 +: 8];
                        wr_addr <= wr_addr + (64'd1 << wr_size);

                        if (wlast) begin
                            wready <= 1'b0;
                            bvalid <= 1'b1;
                            wr_fsm <= WR_RESP;
                        end
                    end
                end

                WR_RESP: begin
                    if (bvalid && bready) begin
                        bvalid <= 1'b0;
                        wr_fsm <= WR_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
