`ifndef FA_PARAMS_SVH
`define FA_PARAMS_SVH

// ============================================================
// FlashAttention Accelerator — Global Parameters
// ============================================================

// --- Baseline fixed dimensions ---
`ifdef FA_SEQ_LEN_OVERRIDE
parameter SEQ_LEN       = `FA_SEQ_LEN_OVERRIDE;
`else
parameter SEQ_LEN       = 256;
`endif
parameter HEAD_DIM      = 64;

// --- Tiling parameters ---
parameter TILE_BR       = 4;     // Q tile rows
parameter TILE_BC       = 16;    // K/V tile rows
parameter NUM_Q_TILES   = SEQ_LEN / TILE_BR;   // 64
parameter NUM_KV_TILES  = SEQ_LEN / TILE_BC;   // 16

// --- Data widths ---
parameter DATA_WIDTH    = 16;    // Q8.8 fixed-point
parameter FRAC_BITS     = 8;     // fractional bits in Q8.8
parameter ACC_WIDTH     = 40;    // accumulator width for dot-products
parameter EXP_WIDTH     = 24;    // exp output width (wider for precision)
parameter SCORE_WIDTH   = 40;    // score/softmax intermediate width

// --- AXI parameters ---
parameter AXI_ADDR_WIDTH  = 64;
parameter AXI_DATA_WIDTH  = 128; // 8 Q8.8 values per beat
parameter AXI_ID_WIDTH    = 4;
parameter AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8;

parameter AXIL_ADDR_WIDTH = 8;
parameter AXIL_DATA_WIDTH = 32;

// --- AXI burst ---
parameter AXI_BURST_LEN   = 16;  // beats per burst

// --- Register map offsets ---
parameter REG_CTRL         = 8'h00;
parameter REG_STATUS       = 8'h04;
parameter REG_CFG          = 8'h08;
parameter REG_Q_BASE_L     = 8'h14;
parameter REG_Q_BASE_H     = 8'h18;
parameter REG_K_BASE_L     = 8'h1C;
parameter REG_K_BASE_H     = 8'h20;
parameter REG_V_BASE_L     = 8'h24;
parameter REG_V_BASE_H     = 8'h28;
parameter REG_O_BASE_L     = 8'h2C;
parameter REG_O_BASE_H     = 8'h30;
parameter REG_STRIDE_BYTES = 8'h34;
parameter REG_NEG_LARGE    = 8'h38;
parameter REG_SCALE        = 8'h3C;
parameter REG_CYCLES       = 8'h40;
parameter REG_RD_BYTES     = 8'h44;
parameter REG_WR_BYTES     = 8'h48;
parameter REG_VALID_LEN    = 8'h4C;
parameter REG_HEAD_COUNT   = 8'h50;
parameter REG_HEAD_STRIDE  = 8'h54;
parameter REG_QUEUE_STATUS = 8'h58;
parameter REG_FORMAT       = 8'h5C;
parameter REG_DROPOUT_CTRL = 8'h60;
parameter REG_DROPOUT_RATE = 8'h64;
parameter REG_DROPOUT_SEED = 8'h68;

// --- CTRL register bits ---
parameter CTRL_START      = 0;
parameter CTRL_SOFT_RESET = 1;
parameter CTRL_IRQ_EN     = 2;

// --- STATUS register bits ---
parameter STATUS_BUSY     = 0;
parameter STATUS_DONE     = 1;
parameter STATUS_ERROR    = 2;

// --- CFG register bits ---
parameter CFG_CAUSAL_EN   = 0;

// --- External data format modes ---
// All modes use the existing 16-bit tensor lane spacing. INT8/FP8 use the
// lower byte of each lane; the internal compute path remains Q8.8.
parameter FORMAT_Q8_8      = 3'd0;
parameter FORMAT_Q6_10     = 3'd1;
parameter FORMAT_Q4_12     = 3'd2;
parameter FORMAT_INT8_Q4_4 = 3'd3;
parameter FORMAT_FP8_E4M3  = 3'd4;
parameter FORMAT_FP16      = 3'd5;
parameter FORMAT_BF16      = 3'd6;

// --- Default values ---
parameter DEFAULT_STRIDE  = HEAD_DIM * 2;           // d * sizeof(Q8.8)
parameter DEFAULT_NEG_LARGE = 16'h8000;             // -128.0 in Q8.8
parameter DEFAULT_SCALE   = 16'h0020;               // 1/8 ≈ 1/√64 in Q8.8
parameter DEFAULT_VALID_LEN = SEQ_LEN;
parameter DEFAULT_HEAD_COUNT = 1;
parameter DEFAULT_HEAD_STRIDE_BYTES = SEQ_LEN * DEFAULT_STRIDE;

// --- Parallelism ---
parameter PAR_MACS       = 1;     // parallel MACs per dot-product per cycle

// --- Exp LUT ---
parameter EXP_LUT_DEPTH  = 1024;
parameter EXP_LUT_WIDTH  = 24;

`endif
