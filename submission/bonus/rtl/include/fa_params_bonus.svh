`ifndef FA_PARAMS_BONUS_SVH
`define FA_PARAMS_BONUS_SVH

// ============================================================
// FlashAttention Accelerator — Enhanced Parameters (Bonus)
// Supports: multi-head, variable seq len, multi-format,
//           padding mask, dropout, task queue, AXI4-Stream
// ============================================================

// --- Configurable dimensions ---
parameter SEQ_LEN         = 256;
parameter HEAD_DIM        = 64;
parameter NUM_HEADS       = 1;
parameter MAX_SEQ_LEN     = 1024;

// --- Tiling parameters ---
parameter TILE_BR         = 4;
parameter TILE_BC         = 16;
parameter NUM_Q_TILES     = SEQ_LEN / TILE_BR;
parameter NUM_KV_TILES    = SEQ_LEN / TILE_BC;

// --- Data format selection ---
// 0 = Q8.8 (baseline), 1 = Q6.10, 2 = Q4.12, 3 = BF16, 4 = INT8
parameter DATA_FMT_Q8_8   = 3'd0;
parameter DATA_FMT_Q6_10  = 3'd1;
parameter DATA_FMT_Q4_12  = 3'd2;
parameter DATA_FMT_BF16   = 3'd3;
parameter DATA_FMT_INT8   = 3'd4;

// --- Data widths ---
parameter DATA_WIDTH      = 16;
parameter FRAC_BITS       = 8;
parameter ACC_WIDTH        = 40;
parameter EXP_WIDTH        = 24;
parameter SCORE_WIDTH      = 40;

// --- AXI parameters ---
parameter AXI_ADDR_WIDTH   = 64;
parameter AXI_DATA_WIDTH   = 128;
parameter AXI_ID_WIDTH     = 4;
parameter AXI_STRB_WIDTH   = AXI_DATA_WIDTH / 8;

parameter AXIL_ADDR_WIDTH  = 8;
parameter AXIL_DATA_WIDTH  = 32;

parameter AXI_BURST_LEN    = 16;

// --- Register map offsets (extended for bonus) ---
parameter REG_CTRL          = 8'h00;
parameter REG_STATUS        = 8'h04;
parameter REG_CFG           = 8'h08;
parameter REG_SEQ_LEN_REG   = 8'h0C;
parameter REG_NUM_HEADS_REG = 8'h10;
parameter REG_Q_BASE_L      = 8'h14;
parameter REG_Q_BASE_H      = 8'h18;
parameter REG_K_BASE_L      = 8'h1C;
parameter REG_K_BASE_H      = 8'h20;
parameter REG_V_BASE_L      = 8'h24;
parameter REG_V_BASE_H      = 8'h28;
parameter REG_O_BASE_L      = 8'h2C;
parameter REG_O_BASE_H      = 8'h30;
parameter REG_STRIDE_BYTES  = 8'h34;
parameter REG_NEG_LARGE     = 8'h38;
parameter REG_SCALE         = 8'h3C;
parameter REG_CYCLES        = 8'h40;
parameter REG_PAD_LEN       = 8'h44;
parameter REG_DROPOUT_CFG   = 8'h48;
parameter REG_TASK_CTRL     = 8'h4C;
parameter REG_DATA_FMT      = 8'h50;
parameter REG_HEAD_STRIDE   = 8'h54;

// --- CTRL register bits ---
parameter CTRL_START       = 0;
parameter CTRL_SOFT_RESET  = 1;
parameter CTRL_IRQ_EN      = 2;

// --- STATUS register bits ---
parameter STATUS_BUSY      = 0;
parameter STATUS_DONE      = 1;
parameter STATUS_ERROR     = 2;
parameter STATUS_QUEUE_FULL = 3;

// --- CFG register bits ---
parameter CFG_CAUSAL_EN    = 0;
parameter CFG_PADDING_EN   = 1;
parameter CFG_DROPOUT_EN   = 2;
parameter CFG_STREAM_MODE  = 3;

// --- Default values ---
parameter DEFAULT_STRIDE   = HEAD_DIM * 2;
parameter DEFAULT_NEG_LARGE = 16'h8000;
parameter DEFAULT_SCALE    = 16'h0020;

// --- Parallelism ---
parameter PAR_MACS         = 8;

// --- Exp LUT ---
parameter EXP_LUT_DEPTH   = 256;
parameter EXP_LUT_WIDTH   = 16;

// --- Dropout ---
parameter DROPOUT_LFSR_WIDTH = 32;

// --- Task Queue ---
parameter TASK_QUEUE_DEPTH = 4;

`endif
