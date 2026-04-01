// ============================================================
// AXI4-Stream Interface Wrapper (Bonus 8)
// Provides streaming Q/K/V input and O output alongside
// the existing AXI4 Master+DMA interface.
// ============================================================
`include "fa_params_bonus.svh"

module axi4_stream_if #(
    parameter DATA_WIDTH    = 128,
    parameter TILE_BR       = 4,
    parameter TILE_BC       = 16,
    parameter HEAD_DIM      = 64,
    parameter ELEM_WIDTH    = 16,
    parameter PAR_MACS      = 8
)(
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        stream_mode,

    // AXI4-Stream Slave (Q/K/V input)
    input  logic [DATA_WIDTH-1:0]      s_axis_tdata,
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic                        s_axis_tlast,
    input  logic [1:0]                 s_axis_tid,    // 0=Q, 1=K, 2=V

    // AXI4-Stream Master (O output)
    output logic [DATA_WIDTH-1:0]      m_axis_tdata,
    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic                        m_axis_tlast,

    // Internal buffer write interface (to buffer_system)
    output logic                        buf_q_wr_en,
    output logic [$clog2(TILE_BR*HEAD_DIM)-1:0] buf_q_wr_addr,
    output logic [DATA_WIDTH-1:0]      buf_q_wr_data,
    output logic                        buf_k_wr_en,
    output logic [$clog2(TILE_BC*HEAD_DIM)-1:0] buf_k_wr_addr,
    output logic [DATA_WIDTH-1:0]      buf_k_wr_data,
    output logic                        buf_v_wr_en,
    output logic [$clog2(TILE_BC*HEAD_DIM)-1:0] buf_v_wr_addr,
    output logic [DATA_WIDTH-1:0]      buf_v_wr_data,

    // Internal O read interface (from buffer_system)
    input  logic [DATA_WIDTH-1:0]      buf_o_rd_data,
    output logic                        buf_o_rd_en,
    output logic [$clog2(TILE_BR)-1:0] buf_o_rd_row,
    output logic [$clog2(HEAD_DIM/(DATA_WIDTH/ELEM_WIDTH))-1:0] buf_o_rd_col_grp,

    // Tile load/store done signals
    output logic                        stream_q_done,
    output logic                        stream_kv_done,
    input  logic                        stream_o_start,
    output logic                        stream_o_done
);

    localparam ELEMS_PER_BEAT = DATA_WIDTH / ELEM_WIDTH; // 8
    localparam Q_BEATS  = (TILE_BR * HEAD_DIM) / ELEMS_PER_BEAT;
    localparam KV_BEATS = (TILE_BC * HEAD_DIM) / ELEMS_PER_BEAT;

    // Input state machine
    typedef enum logic [2:0] {
        S_IDLE, S_LOAD_Q, S_LOAD_K, S_LOAD_V, S_STORE_O
    } state_t;

    state_t state, next_state;
    logic [15:0] beat_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            beat_cnt <= '0;
        end else if (!stream_mode) begin
            state    <= S_IDLE;
            beat_cnt <= '0;
        end else begin
            state <= next_state;
            if (state != next_state)
                beat_cnt <= '0;
            else if ((state == S_STORE_O && m_axis_tvalid && m_axis_tready) ||
                     (state != S_STORE_O && state != S_IDLE && s_axis_tvalid && s_axis_tready))
                beat_cnt <= beat_cnt + 1;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (stream_mode && s_axis_tvalid) begin
                    case (s_axis_tid)
                        2'd0: next_state = S_LOAD_Q;
                        2'd1: next_state = S_LOAD_K;
                        2'd2: next_state = S_LOAD_V;
                        default: next_state = S_IDLE;
                    endcase
                end else if (stream_o_start) begin
                    next_state = S_STORE_O;
                end
            end
            S_LOAD_Q: if (s_axis_tvalid && s_axis_tready && (beat_cnt == Q_BEATS - 1 || s_axis_tlast))
                          next_state = S_IDLE;
            S_LOAD_K: if (s_axis_tvalid && s_axis_tready && (beat_cnt == KV_BEATS - 1 || s_axis_tlast))
                          next_state = S_IDLE;
            S_LOAD_V: if (s_axis_tvalid && s_axis_tready && (beat_cnt == KV_BEATS - 1 || s_axis_tlast))
                          next_state = S_IDLE;
            S_STORE_O: if (m_axis_tvalid && m_axis_tready && (beat_cnt == Q_BEATS - 1))
                          next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    // Buffer write control
    wire input_handshake = s_axis_tvalid && s_axis_tready;

    assign s_axis_tready = stream_mode && (state == S_LOAD_Q || state == S_LOAD_K || state == S_LOAD_V);

    assign buf_q_wr_en   = (state == S_LOAD_Q) && input_handshake;
    assign buf_q_wr_addr = beat_cnt[$clog2(TILE_BR*HEAD_DIM)-1:0];
    assign buf_q_wr_data = s_axis_tdata;

    assign buf_k_wr_en   = (state == S_LOAD_K) && input_handshake;
    assign buf_k_wr_addr = beat_cnt[$clog2(TILE_BC*HEAD_DIM)-1:0];
    assign buf_k_wr_data = s_axis_tdata;

    assign buf_v_wr_en   = (state == S_LOAD_V) && input_handshake;
    assign buf_v_wr_addr = beat_cnt[$clog2(TILE_BC*HEAD_DIM)-1:0];
    assign buf_v_wr_data = s_axis_tdata;

    // O output
    localparam O_COL_GROUPS = HEAD_DIM / ELEMS_PER_BEAT;

    assign buf_o_rd_en      = (state == S_STORE_O);
    assign buf_o_rd_row     = beat_cnt[$clog2(TILE_BR)-1+$clog2(O_COL_GROUPS):$clog2(O_COL_GROUPS)];
    assign buf_o_rd_col_grp = beat_cnt[$clog2(O_COL_GROUPS)-1:0];

    assign m_axis_tdata  = buf_o_rd_data;
    assign m_axis_tvalid = (state == S_STORE_O);
    assign m_axis_tlast  = (state == S_STORE_O) && (beat_cnt == Q_BEATS - 1);

    // Done signals
    assign stream_q_done  = (state == S_LOAD_Q) && input_handshake &&
                            (beat_cnt == Q_BEATS - 1 || s_axis_tlast);
    assign stream_kv_done = ((state == S_LOAD_K) || (state == S_LOAD_V)) && input_handshake &&
                            (beat_cnt == KV_BEATS - 1 || s_axis_tlast);
    assign stream_o_done  = (state == S_STORE_O) && m_axis_tvalid && m_axis_tready &&
                            (beat_cnt == Q_BEATS - 1);

endmodule
