// ============================================================
// Buffer System
// On-chip SRAM buffers for Q, K, V tiles and O accumulation
// Supports double-buffering for K/V (ping-pong)
// ============================================================
module buffer_system #(
    parameter TILE_BR    = 4,
    parameter TILE_BC    = 16,
    parameter HEAD_DIM   = 64,
    parameter DATA_WIDTH = 16,
    parameter PAR_MACS   = 8,
    parameter AXI_DATA_WIDTH = 128
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // --- DMA write interface (loading tiles from external memory) ---
    input  logic                          q_wr_en,
    input  logic [$clog2(TILE_BR*HEAD_DIM)-1:0] q_wr_addr,
    input  logic [AXI_DATA_WIDTH-1:0]     q_wr_data,

    input  logic                          k_wr_en,
    input  logic [$clog2(TILE_BC*HEAD_DIM)-1:0] k_wr_addr,
    input  logic [AXI_DATA_WIDTH-1:0]     k_wr_data,
    input  logic                          k_buf_sel,     // 0 or 1 for ping-pong

    input  logic                          v_wr_en,
    input  logic [$clog2(TILE_BC*HEAD_DIM)-1:0] v_wr_addr,
    input  logic [AXI_DATA_WIDTH-1:0]     v_wr_data,
    input  logic                          v_buf_sel,
    input  logic [2:0]                    format_mode,

    // --- Compute core read interface ---
    // Q: B_r rows × PAR_MACS elements, indexed by step
    input  logic                          q_rd_en,
    input  logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] q_rd_step,
    output logic signed [DATA_WIDTH-1:0]  q_rd_data [TILE_BR-1:0][PAR_MACS-1:0],

    // K: B_c rows × PAR_MACS elements
    input  logic                          k_rd_en,
    input  logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] k_rd_step,
    input  logic                          k_rd_buf_sel,
    output logic signed [DATA_WIDTH-1:0]  k_rd_data [TILE_BC-1:0][PAR_MACS-1:0],

    // V: B_c rows × PAR_MACS elements
    input  logic                          v_rd_en,
    input  logic [$clog2(HEAD_DIM/PAR_MACS)-1:0] v_rd_step,
    input  logic                          v_rd_buf_sel,
    output logic signed [DATA_WIDTH-1:0]  v_rd_data [TILE_BC-1:0][PAR_MACS-1:0],

    // --- O write-back interface ---
    input  logic                          o_wr_en,
    input  logic signed [DATA_WIDTH-1:0]  o_wr_data [TILE_BR-1:0][HEAD_DIM-1:0],

    input  logic                          o_rd_en,
    input  logic [$clog2(TILE_BR)-1:0]    o_rd_row,
    output logic [AXI_DATA_WIDTH-1:0]     o_rd_data,
    input  logic [$clog2(HEAD_DIM/(AXI_DATA_WIDTH/DATA_WIDTH))-1:0] o_rd_col_grp
);

    localparam Q_DEPTH = TILE_BR * HEAD_DIM;      // 4*64 = 256
    localparam KV_DEPTH = TILE_BC * HEAD_DIM;     // 16*64 = 1024
    localparam ELEMS_PER_BEAT = AXI_DATA_WIDTH / DATA_WIDTH;  // 128/16 = 8
    localparam FORMAT_Q8_8      = 3'd0;
    localparam FORMAT_Q6_10     = 3'd1;
    localparam FORMAT_Q4_12     = 3'd2;
    localparam FORMAT_INT8_Q4_4 = 3'd3;
    localparam FORMAT_FP8_E4M3  = 3'd4;
    localparam FORMAT_FP16      = 3'd5;
    localparam FORMAT_BF16      = 3'd6;

    function automatic longint signed round_shift_right_signed(
        input longint signed value,
        input int unsigned shift
    );
        longint signed mag;
        begin
            if (shift == 0) begin
                round_shift_right_signed = value;
            end else if (value >= 0) begin
                round_shift_right_signed = (value + (64'sd1 <<< (shift - 1))) >>> shift;
            end else begin
                mag = -value;
                round_shift_right_signed = -((mag + (64'sd1 <<< (shift - 1))) >>> shift);
            end
        end
    endfunction

    function automatic longint signed apply_signed_shift(
        input longint signed value,
        input int signed shift
    );
        begin
            if (shift >= 0)
                apply_signed_shift = value <<< shift;
            else
                apply_signed_shift = round_shift_right_signed(value, int'(-shift));
        end
    endfunction

    function automatic longint unsigned round_shift_right_unsigned(
        input longint unsigned value,
        input int unsigned shift
    );
        begin
            if (shift == 0)
                round_shift_right_unsigned = value;
            else
                round_shift_right_unsigned = (value + (64'd1 << (shift - 1))) >> shift;
        end
    endfunction

    function automatic longint unsigned apply_unsigned_shift(
        input longint unsigned value,
        input int signed shift
    );
        begin
            if (shift >= 0)
                apply_unsigned_shift = value << shift;
            else
                apply_unsigned_shift = round_shift_right_unsigned(value, int'(-shift));
        end
    endfunction

    function automatic logic signed [DATA_WIDTH-1:0] saturate_q8(
        input longint signed value
    );
        begin
            if (value > 64'sd32767)
                saturate_q8 = 16'sh7FFF;
            else if (value < -64'sd32768)
                saturate_q8 = 16'sh8000;
            else
                saturate_q8 = value[DATA_WIDTH-1:0];
        end
    endfunction

    function automatic logic signed [7:0] saturate_i8(input longint signed value);
        begin
            if (value > 64'sd127)
                saturate_i8 = 8'sh7F;
            else if (value < -64'sd128)
                saturate_i8 = 8'sh80;
            else
                saturate_i8 = value[7:0];
        end
    endfunction

    function automatic int msb_index(input longint unsigned value);
        begin
            msb_index = 0;
            for (int i = 0; i < 63; i++) begin
                if (value[i])
                    msb_index = i;
            end
        end
    endfunction

    function automatic logic signed [DATA_WIDTH-1:0] fp16_to_q8(input logic [15:0] raw);
        logic sign;
        int exp_raw;
        int frac;
        int exp_unbiased;
        int shift;
        longint signed scaled;
        longint signed mant;
        begin
            sign = raw[15];
            exp_raw = raw[14:10];
            frac = raw[9:0];
            if (exp_raw == 31) begin
                fp16_to_q8 = sign ? 16'sh8000 : 16'sh7FFF;
            end else if (exp_raw == 0 && frac == 0) begin
                fp16_to_q8 = '0;
            end else begin
                if (exp_raw == 0) begin
                    mant = frac;
                    exp_unbiased = -14;
                end else begin
                    mant = 1024 + frac;
                    exp_unbiased = exp_raw - 15;
                end
                shift = exp_unbiased - 2;
                scaled = apply_signed_shift(mant, shift);
                fp16_to_q8 = saturate_q8(sign ? -scaled : scaled);
            end
        end
    endfunction

    function automatic logic signed [DATA_WIDTH-1:0] bf16_to_q8(input logic [15:0] raw);
        logic sign;
        int exp_raw;
        int frac;
        int exp_unbiased;
        int shift;
        longint signed scaled;
        longint signed mant;
        begin
            sign = raw[15];
            exp_raw = raw[14:7];
            frac = raw[6:0];
            if (exp_raw == 255) begin
                bf16_to_q8 = sign ? 16'sh8000 : 16'sh7FFF;
            end else if (exp_raw == 0 && frac == 0) begin
                bf16_to_q8 = '0;
            end else begin
                if (exp_raw == 0) begin
                    mant = frac;
                    exp_unbiased = -126;
                end else begin
                    mant = 128 + frac;
                    exp_unbiased = exp_raw - 127;
                end
                shift = exp_unbiased + 1;
                scaled = apply_signed_shift(mant, shift);
                bf16_to_q8 = saturate_q8(sign ? -scaled : scaled);
            end
        end
    endfunction

    function automatic logic signed [DATA_WIDTH-1:0] fp8_e4m3_to_q8(input logic [7:0] raw);
        logic sign;
        int exp_raw;
        int frac;
        int exp_unbiased;
        int shift;
        longint signed scaled;
        longint signed mant;
        begin
            sign = raw[7];
            exp_raw = raw[6:3];
            frac = raw[2:0];
            if (exp_raw == 15) begin
                fp8_e4m3_to_q8 = sign ? 16'sh8000 : 16'sh7FFF;
            end else if (exp_raw == 0 && frac == 0) begin
                fp8_e4m3_to_q8 = '0;
            end else begin
                if (exp_raw == 0) begin
                    mant = frac;
                    exp_unbiased = -6;
                end else begin
                    mant = 8 + frac;
                    exp_unbiased = exp_raw - 7;
                end
                shift = exp_unbiased + 5;
                scaled = apply_signed_shift(mant, shift);
                fp8_e4m3_to_q8 = saturate_q8(sign ? -scaled : scaled);
            end
        end
    endfunction

    function automatic logic [15:0] q8_to_fp16(input logic signed [DATA_WIDTH-1:0] value);
        logic sign;
        longint unsigned mag;
        int exp_unbiased;
        int exp_raw;
        int shift;
        longint unsigned sig;
        begin
            if (value == '0) begin
                q8_to_fp16 = 16'h0000;
            end else begin
                sign = value[DATA_WIDTH-1];
                mag = sign ? longint'(-value) : longint'(value);
                exp_unbiased = msb_index(mag) - 8;
                if (exp_unbiased > 15) begin
                    q8_to_fp16 = {sign, 5'd30, 10'h3FF};
                end else if (exp_unbiased < -14) begin
                    sig = apply_unsigned_shift(mag, 16);
                    if (sig > 1023)
                        sig = 1023;
                    q8_to_fp16 = {sign, 5'd0, sig[9:0]};
                end else begin
                    shift = 10 - exp_unbiased - 8;
                    sig = apply_unsigned_shift(mag, shift);
                    if (sig >= 2048) begin
                        sig = sig >> 1;
                        exp_unbiased++;
                    end
                    exp_raw = exp_unbiased + 15;
                    if (exp_raw >= 31)
                        q8_to_fp16 = {sign, 5'd30, 10'h3FF};
                    else
                        q8_to_fp16 = {sign, exp_raw[4:0], (sig[9:0])};
                end
            end
        end
    endfunction

    function automatic logic [15:0] q8_to_bf16(input logic signed [DATA_WIDTH-1:0] value);
        logic sign;
        longint unsigned mag;
        int exp_unbiased;
        int exp_raw;
        int shift;
        longint unsigned sig;
        begin
            if (value == '0) begin
                q8_to_bf16 = 16'h0000;
            end else begin
                sign = value[DATA_WIDTH-1];
                mag = sign ? longint'(-value) : longint'(value);
                exp_unbiased = msb_index(mag) - 8;
                shift = 7 - exp_unbiased - 8;
                sig = apply_unsigned_shift(mag, shift);
                if (sig >= 256) begin
                    sig = sig >> 1;
                    exp_unbiased++;
                end
                exp_raw = exp_unbiased + 127;
                if (exp_raw >= 255)
                    q8_to_bf16 = {sign, 8'd254, 7'h7F};
                else if (exp_raw <= 0)
                    q8_to_bf16 = {sign, 8'd0, 7'd0};
                else
                    q8_to_bf16 = {sign, exp_raw[7:0], sig[6:0]};
            end
        end
    endfunction

    function automatic logic [7:0] q8_to_fp8_e4m3(input logic signed [DATA_WIDTH-1:0] value);
        logic sign;
        longint unsigned mag;
        int exp_unbiased;
        int exp_raw;
        int shift;
        longint unsigned sig;
        begin
            if (value == '0) begin
                q8_to_fp8_e4m3 = 8'h00;
            end else begin
                sign = value[DATA_WIDTH-1];
                mag = sign ? longint'(-value) : longint'(value);
                exp_unbiased = msb_index(mag) - 8;
                if (exp_unbiased < -6) begin
                    sig = apply_unsigned_shift(mag, 1);
                    if (sig > 7)
                        sig = 7;
                    q8_to_fp8_e4m3 = {sign, 4'd0, sig[2:0]};
                end else begin
                    shift = 3 - exp_unbiased - 8;
                    sig = apply_unsigned_shift(mag, shift);
                    if (sig >= 16) begin
                        sig = sig >> 1;
                        exp_unbiased++;
                    end
                    exp_raw = exp_unbiased + 7;
                    if (exp_raw >= 15)
                        q8_to_fp8_e4m3 = {sign, 4'd14, 3'h7};
                    else
                        q8_to_fp8_e4m3 = {sign, exp_raw[3:0], sig[2:0]};
                end
            end
        end
    endfunction

    function automatic logic signed [DATA_WIDTH-1:0] external_to_q8(
        input logic [DATA_WIDTH-1:0] raw,
        input logic [2:0] fmt
    );
        logic signed [15:0] raw_signed;
        logic signed [7:0] raw_i8;
        begin
            raw_signed = raw;
            raw_i8 = raw[7:0];
            case (fmt)
                FORMAT_Q6_10:     external_to_q8 = saturate_q8(round_shift_right_signed(raw_signed, 2));
                FORMAT_Q4_12:     external_to_q8 = saturate_q8(round_shift_right_signed(raw_signed, 4));
                FORMAT_INT8_Q4_4: external_to_q8 = saturate_q8(longint'(raw_i8) <<< 4);
                FORMAT_FP8_E4M3:  external_to_q8 = fp8_e4m3_to_q8(raw[7:0]);
                FORMAT_FP16:      external_to_q8 = fp16_to_q8(raw);
                FORMAT_BF16:      external_to_q8 = bf16_to_q8(raw);
                default:          external_to_q8 = raw_signed;
            endcase
        end
    endfunction

    function automatic logic [DATA_WIDTH-1:0] q8_to_external(
        input logic signed [DATA_WIDTH-1:0] value,
        input logic [2:0] fmt
    );
        logic signed [7:0] i8;
        begin
            case (fmt)
                FORMAT_Q6_10: begin
                    q8_to_external = saturate_q8(longint'(value) <<< 2);
                end
                FORMAT_Q4_12: begin
                    q8_to_external = saturate_q8(longint'(value) <<< 4);
                end
                FORMAT_INT8_Q4_4: begin
                    i8 = saturate_i8(round_shift_right_signed(value, 4));
                    q8_to_external = {8'h00, i8};
                end
                FORMAT_FP8_E4M3: begin
                    q8_to_external = {8'h00, q8_to_fp8_e4m3(value)};
                end
                FORMAT_FP16: begin
                    q8_to_external = q8_to_fp16(value);
                end
                FORMAT_BF16: begin
                    q8_to_external = q8_to_bf16(value);
                end
                default: begin
                    q8_to_external = value;
                end
            endcase
        end
    endfunction

    // --- Q Buffer (single) ---
    logic signed [DATA_WIDTH-1:0] q_mem [Q_DEPTH-1:0];

    // Write (from DMA, AXI_DATA_WIDTH bits = 8 elements per beat)
    always_ff @(posedge clk) begin
        if (q_wr_en) begin
            for (int i = 0; i < ELEMS_PER_BEAT; i++)
                q_mem[q_wr_addr * ELEMS_PER_BEAT + i] <=
                    external_to_q8(q_wr_data[i*DATA_WIDTH +: DATA_WIDTH], format_mode);
        end
    end

    // Read (PAR_MACS elements per row per step)
    always_comb begin
        for (int r = 0; r < TILE_BR; r++)
            for (int p = 0; p < PAR_MACS; p++)
                q_rd_data[r][p] = q_mem[r * HEAD_DIM + q_rd_step * PAR_MACS + p];
    end

    // --- K Buffers (double, ping-pong) ---
    logic signed [DATA_WIDTH-1:0] k_mem [1:0][KV_DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (k_wr_en) begin
            for (int i = 0; i < ELEMS_PER_BEAT; i++)
                k_mem[k_buf_sel][k_wr_addr * ELEMS_PER_BEAT + i] <=
                    external_to_q8(k_wr_data[i*DATA_WIDTH +: DATA_WIDTH], format_mode);
        end
    end

    always_comb begin
        for (int r = 0; r < TILE_BC; r++)
            for (int p = 0; p < PAR_MACS; p++)
                k_rd_data[r][p] = k_mem[k_rd_buf_sel][r * HEAD_DIM + k_rd_step * PAR_MACS + p];
    end

    // --- V Buffers (double, ping-pong) ---
    logic signed [DATA_WIDTH-1:0] v_mem [1:0][KV_DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (v_wr_en) begin
            for (int i = 0; i < ELEMS_PER_BEAT; i++)
                v_mem[v_buf_sel][v_wr_addr * ELEMS_PER_BEAT + i] <=
                    external_to_q8(v_wr_data[i*DATA_WIDTH +: DATA_WIDTH], format_mode);
        end
    end

    always_comb begin
        for (int r = 0; r < TILE_BC; r++)
            for (int p = 0; p < PAR_MACS; p++)
                v_rd_data[r][p] = v_mem[v_rd_buf_sel][r * HEAD_DIM + v_rd_step * PAR_MACS + p];
    end

    // --- O Buffer ---
    logic signed [DATA_WIDTH-1:0] o_mem [TILE_BR-1:0][HEAD_DIM-1:0];

    always_ff @(posedge clk) begin
        if (o_wr_en) begin
            for (int r = 0; r < TILE_BR; r++)
                for (int j = 0; j < HEAD_DIM; j++)
                    o_mem[r][j] <= o_wr_data[r][j];
        end
    end

    // Read O for DMA write-back (ELEMS_PER_BEAT elements per beat)
    always_comb begin
        for (int i = 0; i < ELEMS_PER_BEAT; i++)
            o_rd_data[i*DATA_WIDTH +: DATA_WIDTH] =
                q8_to_external(o_mem[o_rd_row][o_rd_col_grp * ELEMS_PER_BEAT + i], format_mode);
    end

endmodule
