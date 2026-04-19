// ============================================================
// AXI4-Lite Slave Interface + Register File
// Implements the control/status register space for FlashAttention
// ============================================================
module axi4_lite_slave #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // AXI4-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  logic                    s_axil_awvalid,
    output logic                    s_axil_awready,

    // AXI4-Lite Write Data Channel
    input  logic [DATA_WIDTH-1:0]   s_axil_wdata,
    input  logic [DATA_WIDTH/8-1:0] s_axil_wstrb,
    input  logic                    s_axil_wvalid,
    output logic                    s_axil_wready,

    // AXI4-Lite Write Response
    output logic [1:0]              s_axil_bresp,
    output logic                    s_axil_bvalid,
    input  logic                    s_axil_bready,

    // AXI4-Lite Read Address Channel
    input  logic [ADDR_WIDTH-1:0]   s_axil_araddr,
    input  logic                    s_axil_arvalid,
    output logic                    s_axil_arready,

    // AXI4-Lite Read Data Channel
    output logic [DATA_WIDTH-1:0]   s_axil_rdata,
    output logic [1:0]              s_axil_rresp,
    output logic                    s_axil_rvalid,
    input  logic                    s_axil_rready,

    // Register outputs to datapath
    output logic                    reg_start,        // pulse
    output logic                    reg_soft_reset,    // pulse
    output logic                    reg_irq_en,
    output logic                    reg_causal_en,
    output logic [63:0]             reg_q_base,
    output logic [63:0]             reg_k_base,
    output logic [63:0]             reg_v_base,
    output logic [63:0]             reg_o_base,
    output logic [31:0]             reg_stride_bytes,
    output logic signed [15:0]      reg_neg_large,
    output logic signed [15:0]      reg_scale,

    // Status inputs from datapath
    input  logic                    status_busy,
    input  logic                    status_done,
    input  logic                    status_error,
    input  logic [31:0]             cycle_count,

    // Done clear (write-1-to-clear)
    output logic                    done_clear,

    // Interrupt output
    output logic                    irq
);

    // Internal registers
    logic [31:0] r_ctrl;
    logic [31:0] r_cfg;
    logic [31:0] r_q_base_l, r_q_base_h;
    logic [31:0] r_k_base_l, r_k_base_h;
    logic [31:0] r_v_base_l, r_v_base_h;
    logic [31:0] r_o_base_l, r_o_base_h;
    logic [31:0] r_stride;
    logic [31:0] r_neg_large;
    logic [31:0] r_scale;
    logic        r_done_sticky;

    // Write state machine
    logic aw_ready_r, w_ready_r;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic wr_en;

    // Read state machine
    logic ar_ready_r;
    logic [DATA_WIDTH-1:0] rd_data_r;
    logic rd_valid_r;

    assign s_axil_awready = aw_ready_r;
    assign s_axil_wready  = w_ready_r;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_arready = ar_ready_r;
    assign s_axil_rdata   = rd_data_r;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = rd_valid_r;

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_ready_r      <= 1'b1;
            w_ready_r       <= 1'b1;
            s_axil_bvalid   <= 1'b0;
            wr_en           <= 1'b0;
            wr_addr         <= '0;
            r_ctrl          <= '0;
            r_cfg           <= '0;
            r_q_base_l      <= '0; r_q_base_h <= '0;
            r_k_base_l      <= '0; r_k_base_h <= '0;
            r_v_base_l      <= '0; r_v_base_h <= '0;
            r_o_base_l      <= '0; r_o_base_h <= '0;
            r_stride        <= 32'd128;  // default d*2
            r_neg_large     <= 32'hFFFF8000;
            r_scale         <= 32'h00000020;
            r_done_sticky   <= 1'b0;
            reg_start       <= 1'b0;
            reg_soft_reset  <= 1'b0;
            done_clear      <= 1'b0;
        end else begin
            reg_start      <= 1'b0;
            reg_soft_reset <= 1'b0;
            done_clear     <= 1'b0;

            // Write response handshake
            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;

            // Write address + data accepted
            if (s_axil_awvalid && s_axil_awready && s_axil_wvalid && s_axil_wready) begin
                s_axil_bvalid <= 1'b1;
                case (s_axil_awaddr)
                    8'h00: begin  // CTRL
                        r_ctrl <= s_axil_wdata;
                        if (s_axil_wdata[0]) reg_start      <= 1'b1;
                        if (s_axil_wdata[1]) reg_soft_reset  <= 1'b1;
                    end
                    8'h04: begin  // STATUS (write-1-to-clear DONE)
                        if (s_axil_wdata[1]) begin
                            r_done_sticky <= 1'b0;
                            done_clear    <= 1'b1;
                        end
                    end
                    8'h08: r_cfg        <= s_axil_wdata;
                    8'h14: r_q_base_l   <= s_axil_wdata;
                    8'h18: r_q_base_h   <= s_axil_wdata;
                    8'h1C: r_k_base_l   <= s_axil_wdata;
                    8'h20: r_k_base_h   <= s_axil_wdata;
                    8'h24: r_v_base_l   <= s_axil_wdata;
                    8'h28: r_v_base_h   <= s_axil_wdata;
                    8'h2C: r_o_base_l   <= s_axil_wdata;
                    8'h30: r_o_base_h   <= s_axil_wdata;
                    8'h34: r_stride     <= s_axil_wdata;
                    8'h38: r_neg_large  <= s_axil_wdata;
                    8'h3C: r_scale      <= s_axil_wdata;
                    default: ;
                endcase
            end

            // Sticky done flag
            if (status_done)
                r_done_sticky <= 1'b1;
        end
    end

    // Read logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_ready_r <= 1'b1;
            rd_valid_r <= 1'b0;
            rd_data_r  <= '0;
        end else begin
            if (rd_valid_r && s_axil_rready)
                rd_valid_r <= 1'b0;

            if (s_axil_arvalid && s_axil_arready) begin
                rd_valid_r <= 1'b1;
                case (s_axil_araddr)
                    8'h00: rd_data_r <= r_ctrl;
                    8'h04: rd_data_r <= {29'd0, status_error, r_done_sticky, status_busy};
                    8'h08: rd_data_r <= r_cfg;
                    8'h14: rd_data_r <= r_q_base_l;
                    8'h18: rd_data_r <= r_q_base_h;
                    8'h1C: rd_data_r <= r_k_base_l;
                    8'h20: rd_data_r <= r_k_base_h;
                    8'h24: rd_data_r <= r_v_base_l;
                    8'h28: rd_data_r <= r_v_base_h;
                    8'h2C: rd_data_r <= r_o_base_l;
                    8'h30: rd_data_r <= r_o_base_h;
                    8'h34: rd_data_r <= r_stride;
                    8'h38: rd_data_r <= r_neg_large;
                    8'h3C: rd_data_r <= r_scale;
                    8'h40: rd_data_r <= cycle_count;
                    default: rd_data_r <= 32'hDEADBEEF;
                endcase
            end
        end
    end

    // Output assignments
    assign reg_irq_en      = r_ctrl[2];
    assign reg_causal_en   = r_cfg[0];
    assign reg_q_base      = {r_q_base_h, r_q_base_l};
    assign reg_k_base      = {r_k_base_h, r_k_base_l};
    assign reg_v_base      = {r_v_base_h, r_v_base_l};
    assign reg_o_base      = {r_o_base_h, r_o_base_l};
    assign reg_stride_bytes = r_stride;
    assign reg_neg_large   = r_neg_large[15:0];
    assign reg_scale       = r_scale[15:0];

    // IRQ
    assign irq = reg_irq_en & r_done_sticky;

endmodule
