// ============================================================
// AXI4 Master Interface
// Issues burst read/write transactions for DMA data transfers
// ============================================================
module axi4_master_if #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 128,
    parameter ID_WIDTH   = 4,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // --- AXI4 Master Interface ---
    // Write Address
    output logic [ID_WIDTH-1:0]     m_axi_awid,
    output logic [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output logic [7:0]              m_axi_awlen,
    output logic [2:0]              m_axi_awsize,
    output logic [1:0]              m_axi_awburst,
    output logic                    m_axi_awvalid,
    input  logic                    m_axi_awready,

    // Write Data
    output logic [DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [STRB_WIDTH-1:0]   m_axi_wstrb,
    output logic                    m_axi_wlast,
    output logic                    m_axi_wvalid,
    input  logic                    m_axi_wready,

    // Write Response
    input  logic [ID_WIDTH-1:0]     m_axi_bid,
    input  logic [1:0]              m_axi_bresp,
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready,

    // Read Address
    output logic [ID_WIDTH-1:0]     m_axi_arid,
    output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic                    m_axi_arvalid,
    input  logic                    m_axi_arready,

    // Read Data
    input  logic [ID_WIDTH-1:0]     m_axi_rid,
    input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic [1:0]              m_axi_rresp,
    input  logic                    m_axi_rlast,
    input  logic                    m_axi_rvalid,
    output logic                    m_axi_rready,

    // --- DMA Engine Interface ---
    // Read request
    input  logic                    rd_req,
    input  logic [ADDR_WIDTH-1:0]   rd_addr,
    input  logic [15:0]             rd_len_bytes,
    output logic                    rd_done,

    // Read data output
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    rd_data_valid,

    // Write request
    input  logic                    wr_req,
    input  logic [ADDR_WIDTH-1:0]   wr_addr,
    input  logic [15:0]             wr_len_bytes,
    output logic                    wr_done,

    // Write data input
    input  logic [DATA_WIDTH-1:0]   wr_data,
    input  logic                    wr_data_valid,
    output logic                    wr_data_ready
);

    localparam BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam SIZE_CODE = $clog2(BYTES_PER_BEAT);

    // Constant assignments
    assign m_axi_awid    = '0;
    assign m_axi_awsize  = SIZE_CODE[2:0];
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_arid    = '0;
    assign m_axi_arsize  = SIZE_CODE[2:0];
    assign m_axi_arburst = 2'b01;  // INCR
    assign m_axi_wstrb   = {STRB_WIDTH{1'b1}};
    assign m_axi_bready  = 1'b1;

    // --- Read Channel FSM ---
    typedef enum logic [1:0] {
        RD_IDLE, RD_ADDR, RD_DATA, RD_DONE
    } rd_state_t;

    rd_state_t rd_state;
    logic [15:0] rd_beats_total;
    logic [15:0] rd_beats_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state        <= RD_IDLE;
            m_axi_arvalid   <= 1'b0;
            m_axi_araddr    <= '0;
            m_axi_arlen     <= '0;
            m_axi_rready    <= 1'b0;
            rd_done         <= 1'b0;
            rd_data_valid   <= 1'b0;
            rd_beats_total  <= '0;
            rd_beats_cnt    <= '0;
        end else begin
            rd_done       <= 1'b0;
            rd_data_valid <= 1'b0;

            case (rd_state)
                RD_IDLE: begin
                    if (rd_req) begin
                        rd_beats_total <= (rd_len_bytes + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT;
                        m_axi_araddr   <= rd_addr;
                        m_axi_arlen    <= ((rd_len_bytes + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT) - 1;
                        m_axi_arvalid  <= 1'b1;
                        rd_beats_cnt   <= '0;
                        rd_state       <= RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        rd_state      <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_data       <= m_axi_rdata;
                        rd_data_valid <= 1'b1;
                        rd_beats_cnt  <= rd_beats_cnt + 1;
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            rd_state     <= RD_DONE;
                        end
                    end
                end

                RD_DONE: begin
                    rd_done  <= 1'b1;
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end

    // --- Write Channel FSM ---
    typedef enum logic [1:0] {
        WR_IDLE, WR_ADDR, WR_DATA, WR_DONE
    } wr_state_t;

    wr_state_t wr_state;
    logic [15:0] wr_beats_total;
    logic [15:0] wr_beats_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state        <= WR_IDLE;
            m_axi_awvalid   <= 1'b0;
            m_axi_awaddr    <= '0;
            m_axi_awlen     <= '0;
            m_axi_wvalid    <= 1'b0;
            m_axi_wlast     <= 1'b0;
            m_axi_wdata     <= '0;
            wr_done         <= 1'b0;
            wr_data_ready   <= 1'b0;
            wr_beats_total  <= '0;
            wr_beats_cnt    <= '0;
        end else begin
            wr_done  <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    if (wr_req) begin
                        wr_beats_total <= (wr_len_bytes + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT;
                        m_axi_awaddr   <= wr_addr;
                        m_axi_awlen    <= ((wr_len_bytes + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT) - 1;
                        m_axi_awvalid  <= 1'b1;
                        wr_beats_cnt   <= '0;
                        wr_state       <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        wr_data_ready <= 1'b1;
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (wr_data_valid && wr_data_ready) begin
                        m_axi_wdata  <= wr_data;
                        m_axi_wvalid <= 1'b1;
                        wr_beats_cnt <= wr_beats_cnt + 1;
                        m_axi_wlast  <= (wr_beats_cnt == wr_beats_total - 1);
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        if (m_axi_wlast) begin
                            wr_data_ready <= 1'b0;
                            m_axi_wlast   <= 1'b0;
                            wr_state      <= WR_DONE;
                        end
                    end
                end

                WR_DONE: begin
                    if (m_axi_bvalid) begin
                        wr_done  <= 1'b1;
                        wr_state <= WR_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
