// ============================================================
// Task Queue — Multi-task chaining (Bonus 9)
// FIFO-based configuration queue for continuous attention ops.
// Host pushes task descriptors; HW pops and executes sequentially.
// ============================================================
`include "fa_params_bonus.svh"

module task_queue #(
    parameter QUEUE_DEPTH     = 4,
    parameter AXI_ADDR_WIDTH  = 64
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // Host push interface
    input  logic                          push_valid,
    output logic                          push_ready,
    input  logic [AXI_ADDR_WIDTH-1:0]    push_q_base,
    input  logic [AXI_ADDR_WIDTH-1:0]    push_k_base,
    input  logic [AXI_ADDR_WIDTH-1:0]    push_v_base,
    input  logic [AXI_ADDR_WIDTH-1:0]    push_o_base,
    input  logic [31:0]                  push_config,  // {causal_en, padding_en, dropout_en, data_fmt, seq_len, ...}

    // HW pop interface
    input  logic                          pop_req,
    output logic                          pop_valid,
    output logic [AXI_ADDR_WIDTH-1:0]    pop_q_base,
    output logic [AXI_ADDR_WIDTH-1:0]    pop_k_base,
    output logic [AXI_ADDR_WIDTH-1:0]    pop_v_base,
    output logic [AXI_ADDR_WIDTH-1:0]    pop_o_base,
    output logic [31:0]                  pop_config,

    // Status
    output logic                          empty,
    output logic                          full,
    output logic [$clog2(QUEUE_DEPTH):0] count
);

    localparam ENTRY_WIDTH = 4 * AXI_ADDR_WIDTH + 32;
    localparam PTR_WIDTH   = $clog2(QUEUE_DEPTH);

    logic [ENTRY_WIDTH-1:0] fifo_mem [QUEUE_DEPTH-1:0];
    logic [PTR_WIDTH:0] wr_ptr, rd_ptr;

    assign count = wr_ptr - rd_ptr;
    assign empty = (count == 0);
    assign full  = (count == QUEUE_DEPTH[PTR_WIDTH:0]);
    assign push_ready = !full;
    assign pop_valid  = !empty;

    wire [ENTRY_WIDTH-1:0] push_data = {push_config, push_o_base, push_v_base, push_k_base, push_q_base};
    wire [ENTRY_WIDTH-1:0] pop_data  = fifo_mem[rd_ptr[PTR_WIDTH-1:0]];

    assign pop_q_base  = pop_data[AXI_ADDR_WIDTH-1:0];
    assign pop_k_base  = pop_data[2*AXI_ADDR_WIDTH-1:AXI_ADDR_WIDTH];
    assign pop_v_base  = pop_data[3*AXI_ADDR_WIDTH-1:2*AXI_ADDR_WIDTH];
    assign pop_o_base  = pop_data[4*AXI_ADDR_WIDTH-1:3*AXI_ADDR_WIDTH];
    assign pop_config  = pop_data[ENTRY_WIDTH-1:4*AXI_ADDR_WIDTH];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (push_valid && push_ready) begin
            fifo_mem[wr_ptr[PTR_WIDTH-1:0]] <= push_data;
            wr_ptr <= wr_ptr + 1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_ptr <= '0;
        else if (pop_req && pop_valid)
            rd_ptr <= rd_ptr + 1;
    end

endmodule
