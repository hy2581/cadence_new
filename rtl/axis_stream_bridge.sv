// ============================================================
// AXI4-Stream ready/valid bridge
// Small synthesizable FIFO path used to expose and verify an AXI4-Stream
// data-movement interface independently from the AXI4 memory-mapped core.
// ============================================================
module axis_stream_bridge #(
    parameter DATA_WIDTH = 128,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter DEPTH      = 4
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [DATA_WIDTH-1:0]   s_axis_tdata,
    input  logic [KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  logic                    s_axis_tlast,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,

    output logic [DATA_WIDTH-1:0]   m_axis_tdata,
    output logic [KEEP_WIDTH-1:0]   m_axis_tkeep,
    output logic                    m_axis_tlast,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready
);

    localparam PTR_W = $clog2(DEPTH);
    localparam COUNT_W = $clog2(DEPTH + 1);

    logic [DATA_WIDTH-1:0] fifo_data [DEPTH-1:0];
    logic [KEEP_WIDTH-1:0] fifo_keep [DEPTH-1:0];
    logic                  fifo_last [DEPTH-1:0];
    logic [PTR_W-1:0]      wr_ptr;
    logic [PTR_W-1:0]      rd_ptr;
    logic [COUNT_W-1:0]    count;

    assign s_axis_tready = (count < COUNT_W'(DEPTH));
    assign m_axis_tvalid = (count != '0);
    assign m_axis_tdata  = fifo_data[rd_ptr];
    assign m_axis_tkeep  = fifo_keep[rd_ptr];
    assign m_axis_tlast  = fifo_last[rd_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                fifo_data[i] <= '0;
                fifo_keep[i] <= '0;
                fifo_last[i] <= 1'b0;
            end
        end else begin
            logic do_push;
            logic do_pop;
            do_push = s_axis_tvalid && s_axis_tready;
            do_pop  = m_axis_tvalid && m_axis_tready;

            if (do_push) begin
                fifo_data[wr_ptr] <= s_axis_tdata;
                fifo_keep[wr_ptr] <= s_axis_tkeep;
                fifo_last[wr_ptr] <= s_axis_tlast;
                wr_ptr <= (wr_ptr == PTR_W'(DEPTH - 1)) ? '0 : wr_ptr + 1'b1;
            end

            if (do_pop)
                rd_ptr <= (rd_ptr == PTR_W'(DEPTH - 1)) ? '0 : rd_ptr + 1'b1;

            case ({do_push, do_pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
