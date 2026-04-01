// ============================================================
// Enhanced AXI4-Lite Slave (Bonus) — Baseline-compatible style
// Always-ready handshake, single-cycle write, extended registers
// ============================================================
`include "fa_params_bonus.svh"

module axi4_lite_slave_bonus #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic [ADDR_WIDTH-1:0]     s_axil_awaddr,
    input  logic                       s_axil_awvalid,
    output logic                       s_axil_awready,
    input  logic [DATA_WIDTH-1:0]     s_axil_wdata,
    input  logic [DATA_WIDTH/8-1:0]   s_axil_wstrb,
    input  logic                       s_axil_wvalid,
    output logic                       s_axil_wready,
    output logic [1:0]                s_axil_bresp,
    output logic                       s_axil_bvalid,
    input  logic                       s_axil_bready,
    input  logic [ADDR_WIDTH-1:0]     s_axil_araddr,
    input  logic                       s_axil_arvalid,
    output logic                       s_axil_arready,
    output logic [DATA_WIDTH-1:0]     s_axil_rdata,
    output logic [1:0]                s_axil_rresp,
    output logic                       s_axil_rvalid,
    input  logic                       s_axil_rready,

    output logic                       reg_start,
    output logic                       reg_soft_reset,
    output logic                       reg_irq_en,
    output logic                       reg_causal_en,
    output logic                       reg_padding_en,
    output logic                       reg_dropout_en,
    output logic                       reg_stream_mode,
    output logic [63:0]               reg_q_base,
    output logic [63:0]               reg_k_base,
    output logic [63:0]               reg_v_base,
    output logic [63:0]               reg_o_base,
    output logic [31:0]               reg_stride_bytes,
    output logic signed [15:0]        reg_neg_large,
    output logic signed [15:0]        reg_scale,
    output logic [15:0]               reg_seq_len,
    output logic [7:0]                reg_num_heads,
    output logic [15:0]               reg_pad_len,
    output logic [7:0]                reg_drop_prob,
    output logic [31:0]               reg_dropout_seed,
    output logic [2:0]                reg_data_fmt,
    output logic [31:0]               reg_head_stride,
    output logic                       reg_task_queue_en,

    input  logic                       status_busy,
    input  logic                       status_done,
    input  logic                       status_error,
    input  logic                       status_queue_full,
    input  logic [31:0]               cycle_count,
    output logic                       done_clear,
    output logic                       irq
);

    // Internal registers
    logic [31:0] r_ctrl, r_cfg;
    logic [31:0] r_q_base_l, r_q_base_h;
    logic [31:0] r_k_base_l, r_k_base_h;
    logic [31:0] r_v_base_l, r_v_base_h;
    logic [31:0] r_o_base_l, r_o_base_h;
    logic [31:0] r_stride, r_neg_large_r, r_scale_r;
    logic [31:0] r_seq_len, r_num_heads;
    logic [31:0] r_pad_len, r_dropout_cfg;
    logic [31:0] r_data_fmt, r_head_stride, r_task_ctrl;
    logic        r_done_sticky;

    // Ready signals
    logic aw_ready_r, w_ready_r, ar_ready_r;
    logic rd_valid_r;
    logic [DATA_WIDTH-1:0] rd_data_r;

    assign s_axil_awready = aw_ready_r;
    assign s_axil_wready  = w_ready_r;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_arready = ar_ready_r;
    assign s_axil_rdata   = rd_data_r;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = rd_valid_r;

    // Write logic (baseline-compatible: always ready)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_ready_r     <= 1'b1;
            w_ready_r      <= 1'b1;
            s_axil_bvalid  <= 1'b0;
            reg_start      <= 1'b0;
            reg_soft_reset <= 1'b0;
            done_clear     <= 1'b0;
            r_ctrl         <= '0;
            r_cfg          <= '0;
            r_q_base_l     <= '0; r_q_base_h <= '0;
            r_k_base_l     <= '0; r_k_base_h <= '0;
            r_v_base_l     <= '0; r_v_base_h <= '0;
            r_o_base_l     <= '0; r_o_base_h <= '0;
            r_stride       <= 32'd128;
            r_neg_large_r  <= 32'hFFFF8000;
            r_scale_r      <= 32'h00000020;
            r_seq_len      <= 32'd256;
            r_num_heads    <= 32'd1;
            r_pad_len      <= '0;
            r_dropout_cfg  <= '0;
            r_data_fmt     <= '0;
            r_head_stride  <= '0;
            r_task_ctrl    <= '0;
            r_done_sticky  <= 1'b0;
        end else begin
            reg_start      <= 1'b0;
            reg_soft_reset <= 1'b0;
            done_clear     <= 1'b0;

            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;

            if (s_axil_awvalid && s_axil_awready && s_axil_wvalid && s_axil_wready) begin
                s_axil_bvalid <= 1'b1;
                case (s_axil_awaddr)
                    8'h00: begin
                        r_ctrl <= s_axil_wdata;
                        if (s_axil_wdata[0]) reg_start      <= 1'b1;
                        if (s_axil_wdata[1]) reg_soft_reset <= 1'b1;
                    end
                    8'h04: begin
                        if (s_axil_wdata[1]) begin
                            r_done_sticky <= 1'b0;
                            done_clear    <= 1'b1;
                        end
                    end
                    8'h08: r_cfg        <= s_axil_wdata;
                    8'h0C: r_seq_len    <= s_axil_wdata;
                    8'h10: r_num_heads  <= s_axil_wdata;
                    8'h14: r_q_base_l   <= s_axil_wdata;
                    8'h18: r_q_base_h   <= s_axil_wdata;
                    8'h1C: r_k_base_l   <= s_axil_wdata;
                    8'h20: r_k_base_h   <= s_axil_wdata;
                    8'h24: r_v_base_l   <= s_axil_wdata;
                    8'h28: r_v_base_h   <= s_axil_wdata;
                    8'h2C: r_o_base_l   <= s_axil_wdata;
                    8'h30: r_o_base_h   <= s_axil_wdata;
                    8'h34: r_stride     <= s_axil_wdata;
                    8'h38: r_neg_large_r <= s_axil_wdata;
                    8'h3C: r_scale_r    <= s_axil_wdata;
                    8'h44: r_pad_len    <= s_axil_wdata;
                    8'h48: r_dropout_cfg <= s_axil_wdata;
                    8'h4C: r_task_ctrl  <= s_axil_wdata;
                    8'h50: r_data_fmt   <= s_axil_wdata;
                    8'h54: r_head_stride <= s_axil_wdata;
                    default: ;
                endcase
            end

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
                    8'h04: rd_data_r <= {28'd0, status_queue_full, status_error, r_done_sticky, status_busy};
                    8'h08: rd_data_r <= r_cfg;
                    8'h0C: rd_data_r <= r_seq_len;
                    8'h10: rd_data_r <= r_num_heads;
                    8'h14: rd_data_r <= r_q_base_l;
                    8'h18: rd_data_r <= r_q_base_h;
                    8'h1C: rd_data_r <= r_k_base_l;
                    8'h20: rd_data_r <= r_k_base_h;
                    8'h24: rd_data_r <= r_v_base_l;
                    8'h28: rd_data_r <= r_v_base_h;
                    8'h2C: rd_data_r <= r_o_base_l;
                    8'h30: rd_data_r <= r_o_base_h;
                    8'h34: rd_data_r <= r_stride;
                    8'h38: rd_data_r <= r_neg_large_r;
                    8'h3C: rd_data_r <= r_scale_r;
                    8'h40: rd_data_r <= cycle_count;
                    8'h44: rd_data_r <= r_pad_len;
                    8'h48: rd_data_r <= r_dropout_cfg;
                    8'h4C: rd_data_r <= r_task_ctrl;
                    8'h50: rd_data_r <= r_data_fmt;
                    8'h54: rd_data_r <= r_head_stride;
                    default: rd_data_r <= 32'hDEADBEEF;
                endcase
            end
        end
    end

    // Output assignments
    assign reg_irq_en       = r_ctrl[2];
    assign reg_causal_en    = r_cfg[0];
    assign reg_padding_en   = r_cfg[1];
    assign reg_dropout_en   = r_cfg[2];
    assign reg_stream_mode  = r_cfg[3];
    assign reg_q_base       = {r_q_base_h, r_q_base_l};
    assign reg_k_base       = {r_k_base_h, r_k_base_l};
    assign reg_v_base       = {r_v_base_h, r_v_base_l};
    assign reg_o_base       = {r_o_base_h, r_o_base_l};
    assign reg_stride_bytes = r_stride;
    assign reg_neg_large    = r_neg_large_r[15:0];
    assign reg_scale        = r_scale_r[15:0];
    assign reg_seq_len      = r_seq_len[15:0];
    assign reg_num_heads    = r_num_heads[7:0];
    assign reg_pad_len      = r_pad_len[15:0];
    assign reg_drop_prob    = r_dropout_cfg[7:0];
    assign reg_dropout_seed = r_dropout_cfg;
    assign reg_data_fmt     = r_data_fmt[2:0];
    assign reg_head_stride  = r_head_stride;
    assign reg_task_queue_en = r_task_ctrl[0];

    assign irq = reg_irq_en & r_done_sticky;

endmodule
