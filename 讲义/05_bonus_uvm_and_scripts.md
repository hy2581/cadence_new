# 第 5 章：Bonus UVM 验证 + scripts/seqgen_stub

本章覆盖最后 10 个文件：

| § | 文件 | 行数 | 角色 |
|---|------|------|------|
| 5.1 | `bonus/tb/uvm_env/fa_bonus_env_pkg.sv` | 27 | 环境包 |
| 5.2 | `bonus/tb/uvm_env/fa_bonus_env.sv` | 29 | UVM env |
| 5.3 | `bonus/tb/uvm_env/fa_bonus_scoreboard.sv` | 122 | 黄金模型 + bonus mask 支持 |
| 5.4 | `bonus/tb/uvm_env/fa_bonus_coverage.sv` | 133 | bonus 覆盖率 |
| 5.5 | `bonus/tb/sequences/fa_bonus_sequences.sv` | 273 | bonus 序列 |
| 5.6 | `bonus/tb/tests/fa_bonus_tests.sv` | 684 | 24 个 bonus 测试 |
| 5.7 | `bonus/tb/tb_top/fa_bonus_tb_top.sv` | 152 | bonus UVM TB 顶层 |
| 5.8 | `bonus/tb/bonus_system_tb.sv` | 821 | bonus 直接 TB (19 项) |
| 5.9 | `scripts/seqgen_stub.v` | 57 | DC 综合后 gate-sim 兼容 stub |

> Bonus UVM 验证环境结构与 baseline 高度相似。**为节省篇幅，本章主要展示 bonus 与 baseline 的差异点**，相同的部分（agent/driver/monitor 等）请回看第 3 章。

---

## 5.1 `bonus/tb/uvm_env/fa_bonus_env_pkg.sv`

### 5.1.1 完整源代码

```systemverilog
package fa_bonus_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Reuse baseline agents
    `include "agents/axi4_lite_agent/axi4_lite_txn.sv"
    `include "agents/axi4_lite_agent/axi4_lite_driver.sv"
    `include "agents/axi4_lite_agent/axi4_lite_monitor.sv"
    `include "agents/axi4_lite_agent/axi4_lite_sequencer.sv"
    `include "agents/axi4_lite_agent/axi4_lite_agent.sv"
    `include "agents/axi4_mem_agent/axi4_mem_agent.sv"

    // Reuse baseline sequences (reg_write, reg_read)
    `include "sequences/fa_sequences.sv"

    // Bonus-specific components
    `include "bonus/tb/uvm_env/fa_bonus_scoreboard.sv"
    `include "bonus/tb/uvm_env/fa_bonus_coverage.sv"
    `include "bonus/tb/uvm_env/fa_bonus_env.sv"

    // Bonus sequences and tests
    `include "bonus/tb/sequences/fa_bonus_sequences.sv"
    `include "bonus/tb/tests/fa_bonus_tests.sv"
endpackage
```

### 5.1.2 解释

- 直接复用 baseline 的 4 个 agent 文件 + baseline 的基础 reg_write/reg_read sequence。
- 新增 4 个 bonus 文件（scoreboard / coverage / env / sequences / tests）。
- **过于简单，无需图示**。

---

## 5.2 `bonus/tb/uvm_env/fa_bonus_env.sv`

### 5.2.1 完整源代码

```systemverilog
class fa_bonus_env extends uvm_env;
    `uvm_component_utils(fa_bonus_env)

    axi4_lite_agent      axil_agent;
    axi4_mem_agent       mem_agent;
    fa_bonus_scoreboard  scoreboard;
    fa_bonus_coverage    coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axil_agent = axi4_lite_agent::type_id::create("axil_agent", this);
        mem_agent  = axi4_mem_agent::type_id::create("mem_agent", this);
        scoreboard = fa_bonus_scoreboard::type_id::create("scoreboard", this);
        coverage   = fa_bonus_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        axil_agent.mon.ap.connect(coverage.analysis_export);
    endfunction
endclass
```

### 5.2.2 解释

- 比 baseline `fa_env` **少了 RAL** （`fa_reg_block` / `fa_reg_adapter` / `uvm_reg_predictor`） — bonus 测试不需要 RAL 前门，所有寄存器访问通过 sequence 直接发 `axi4_lite_txn`。
- 其他 4 个组件（agent × 2、scoreboard、coverage）都按 baseline 风格实例化。
- **过于简单，无需图示**。

---

## 5.3 `bonus/tb/uvm_env/fa_bonus_scoreboard.sv`

### 5.3.1 概述

baseline scoreboard 的扩展，黄金模型加了 **padding mask 支持** (`valid_len`) 和稍微宽松的误差阈值 (1.5 vs baseline 的 1.0)。基本结构相同。

### 5.3.2 关键差异片段

#### 块 ① 新字段

```systemverilog
class fa_bonus_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fa_bonus_scoreboard)
    int seq_len = 256;
    int head_dim = 64;
    bit causal_en;
    int valid_len;             // NEW: padding boundary
    /* 其他字段与 baseline 同 */
```

#### 块 ② Golden model 加 padding mask（行 49–96 关键节选）

```systemverilog
        for (int i = 0; i < seq_len; i++) begin
            real o_row[];
            o_row = new[head_dim];
            for (int d = 0; d < head_dim; d++) o_row[d] = 0.0;

            row_max = -1e30;
            for (int j = 0; j < seq_len; j++) begin
                if (causal_en && j > i)                    score = -128.0;     // causal mask
                else if (valid_len > 0 && j >= valid_len)  score = -128.0;     // padding mask  [NEW]
                else begin
                    score = 0.0;
                    for (int k = 0; k < head_dim; k++)
                        score = score + q_f[i][k] * k_f[j][k];
                    score = score * scale;
                end
                if (score > row_max) row_max = score;
            end

            row_sum = 0.0;
            for (int j = 0; j < seq_len; j++) begin
                /* same conditional skip pattern */
                row_sum = row_sum + $exp(score - row_max);
            end

            for (int j = 0; j < seq_len; j++) begin
                /* same skip pattern */
                p_val = $exp(score - row_max) / row_sum;
                for (int d = 0; d < head_dim; d++)
                    o_row[d] = o_row[d] + p_val * v_f[j][d];
            end

            for (int d = 0; d < head_dim; d++)
                golden_o[i][d] = shortint'($rtoi(o_row[d] * 256.0));
        end
```

**说明：** 在 baseline 的 SDPA 实现中加了一个判断 `valid_len > 0 && j >= valid_len → score = -128`。这与 bonus 硬件中 `mask_unit` 的行为对齐。代码风格上的一个改动是：score 计算被同时复用在三个 phase（求 max、求 sum、求 p_val），baseline 是把 `s_f` 完整展开成中间矩阵；bonus 用即时 recompute 来节省内存，但代价是浮点乘法做了 3 倍。

#### 块 ③ 阈值调整

```systemverilog
    function void check_result(string test_name);
        /* same comparison loop */
        if (max_abs_error <= 1.5)        // [NEW] threshold = 1.5 (baseline = 1.0)
            `uvm_info(test_name, $sformatf("PASS mean=%.6f max=%.6f",
                                            mean_abs_error, max_abs_error), UVM_LOW)
        else
            `uvm_error(test_name, $sformatf("FAIL mean=%.6f max=%.6f",
                                             mean_abs_error, max_abs_error))
    endfunction
```

**说明：** 阈值从 1.0 放宽到 1.5，给 bonus 多种数据格式（BF16、Q6.10）的额外量化误差留 buffer。**实测仍然 max_abs=0.238，远低于 1.5**。

---

## 5.4 `bonus/tb/uvm_env/fa_bonus_coverage.sv`

### 5.4.1 概述

133 行，比 baseline coverage 简化（不含 RAL/burst 等），但增加了 bonus 特定的 covergroup（多头数、padding、dropout）。

### 5.4.2 关键 covergroup 示例

```systemverilog
class fa_bonus_coverage extends uvm_subscriber #(axi4_lite_txn);
    `uvm_component_utils(fa_bonus_coverage)
    bit causal_en, padding_en, dropout_en, stream_mode;
    bit [2:0] data_fmt;
    bit [7:0] num_heads;
    int exec_cycles;

    covergroup fa_bonus_config_cg;
        causal_cp:    coverpoint causal_en   { bins en={1}; bins dis={0}; }
        padding_cp:   coverpoint padding_en  { bins en={1}; bins dis={0}; }
        dropout_cp:   coverpoint dropout_en  { bins en={1}; bins dis={0}; }
        stream_cp:    coverpoint stream_mode { bins en={1}; bins dis={0}; }
        fmt_cp:       coverpoint data_fmt {
            bins q8_8  = {3'd0};
            bins q6_10 = {3'd1};
            bins q4_12 = {3'd2};
            bins bf16  = {3'd3};
            bins int8  = {3'd4};
        }
        nh_cp: coverpoint num_heads {
            bins single = {1};
            bins few    = {[2:4]};
            bins many   = {[5:$]};
        }
        // crosses
        causal_x_pad: cross causal_cp, padding_cp;
        fmt_x_nh:     cross fmt_cp, nh_cp;
    endgroup
    /* + 4 个其他 covergroup, sample_* tasks */
endclass
```

**说明：** 4 个 covergroup：`fa_bonus_config_cg`（功能开关 + 数据格式 + 多头数）、`fa_bonus_perf_cg`（执行周期）、`fa_bonus_dma_cg`（DMA 大小）、`fa_bonus_vp_cg`（24 个 VP 完成度）。**比 baseline 的 10 个 covergroup 少**，但更聚焦于 bonus 特性。**结构简单，无需图示**。

---

## 5.5 `bonus/tb/sequences/fa_bonus_sequences.sv`

### 5.5.1 概述

273 行，包含 7 个 bonus sequence。最重要的是 `fa_bonus_config_seq` (写 22 个寄存器并启动) 和 `fa_bonus_poll_done_seq`（轮询）。

### 5.5.2 关键 sequence — `fa_bonus_config_seq`（节选）

```systemverilog
class fa_bonus_config_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_config_seq)
    bit [63:0] q_base, k_base, v_base, o_base;
    bit [31:0] stride_bytes;
    bit [15:0] neg_large, scale;
    bit causal_en, padding_en, dropout_en;
    bit [2:0]  data_fmt;
    bit [15:0] valid_len, seq_len_runtime;
    bit [7:0]  num_heads;
    bit [7:0]  drop_prob;
    bit [31:0] dropout_seed;
    bit [31:0] head_stride;

    function new(string name = "fa_bonus_config_seq");
        super.new(name);
        stride_bytes    = 32'd128;
        neg_large       = 16'h8000;
        scale           = 16'h0020;
        seq_len_runtime = 256;
        num_heads       = 1;
        head_stride     = 32'd0;
    endfunction

    task body();
        // Bonus 寄存器：先写新增的
        if (seq_len_runtime != 256)
            write_reg(8'h0C, seq_len_runtime);          // SEQ_LEN_REG
        if (num_heads != 1)
            write_reg(8'h10, {24'd0, num_heads});       // NUM_HEADS_REG
        // 然后是 baseline 的基址、stride、scale
        write_reg(8'h14, q_base[31:0]);     write_reg(8'h18, q_base[63:32]);
        write_reg(8'h1C, k_base[31:0]);     write_reg(8'h20, k_base[63:32]);
        write_reg(8'h24, v_base[31:0]);     write_reg(8'h28, v_base[63:32]);
        write_reg(8'h2C, o_base[31:0]);     write_reg(8'h30, o_base[63:32]);
        write_reg(8'h34, stride_bytes);
        write_reg(8'h38, {16'h0, neg_large});
        write_reg(8'h3C, {16'h0, scale});
        // Bonus 寄存器
        if (padding_en)            write_reg(8'h44, valid_len);          // PAD_LEN
        if (dropout_en) begin
            write_reg(8'h48, {drop_prob, dropout_seed[23:0]});           // DROPOUT_CFG
        end
        if (data_fmt != 0)         write_reg(8'h50, {29'd0, data_fmt});  // DATA_FMT
        if (head_stride != 0)      write_reg(8'h54, head_stride);        // HEAD_STRIDE
        // CFG 集合 4 个 enable 位
        write_reg(8'h08, {28'd0, 1'b0/*stream*/, dropout_en, padding_en, causal_en});
        // 启动
        write_reg(8'h00, 32'h0000_0001);   // CTRL.START
    endtask

    task write_reg(bit [7:0] addr, bit [31:0] data);
        fa_reg_write_seq wr;
        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = addr; wr.data = data;
        wr.start(m_sequencer);
    endtask
endclass
```

**说明：** 比 baseline `fa_config_and_start_seq` 多了对 7 个新寄存器的条件写：`SEQ_LEN_REG / NUM_HEADS_REG / PAD_LEN / DROPOUT_CFG / DATA_FMT / HEAD_STRIDE`。CFG 寄存器位拼接也扩展到 4 个 enable 位（causal/padding/dropout/stream）。

其余 6 个 sequence 类似 baseline 的对应类（`fa_bonus_poll_done_seq`、`fa_bonus_reg_write_seq`、`fa_bonus_padding_seq`、`fa_bonus_multihead_seq` 等），结构上无新意，**省略代码展示**。

---

## 5.6 `bonus/tb/tests/fa_bonus_tests.sv`

### 5.6.1 概述

684 行，24 个 bonus 测试，按 baseline 的 6 大 verification domain 组织（VP / REG / DMA / AXI / PERF / COV + COMP）。**结构与 baseline 24 测试基本相同**，但每个测试都有 bonus 特性变体（如 padding test 启用 `padding_en`，BF16 test 设 `data_fmt=3`）。

### 5.6.2 基类 + 一个典型测试

#### 块 ① 基类 `fa_bonus_base_test`（行 6–105 关键节选）

```systemverilog
class fa_bonus_base_test extends uvm_test;
    `uvm_component_utils(fa_bonus_base_test)
    fa_bonus_env env;
    bit [63:0] Q_BASE = 64'h0001_0000;
    bit [63:0] K_BASE = 64'h0002_0000;
    bit [63:0] V_BASE = 64'h0003_0000;
    bit [63:0] O_BASE = 64'h0004_0000;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = fa_bonus_env::type_id::create("env", this);
    endfunction

    /* 数据生成函数 (gen_random / gen_zero / gen_identity / gen_max / gen_boundary)
       与 baseline 完全相同 */

    task run_bonus_attention(input bit causal, input shortint q[][],
                              input shortint k[][], input shortint v[][]);
        fa_bonus_config_seq    cfg;
        fa_bonus_poll_done_seq poll;

        env.mem_agent.preload_matrix(Q_BASE, q.size(), q[0].size(), q);
        env.mem_agent.preload_matrix(K_BASE, k.size(), k[0].size(), k);
        env.mem_agent.preload_matrix(V_BASE, v.size(), v[0].size(), v);

        env.scoreboard.q_data    = q;
        env.scoreboard.k_data    = k;
        env.scoreboard.v_data    = v;
        env.scoreboard.causal_en = causal;
        env.scoreboard.valid_len = 0;

        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = causal;
        cfg.start(env.axil_agent.sqr);

        poll = fa_bonus_poll_done_seq::type_id::create("poll");
        poll.start(env.axil_agent.sqr);

        env.mem_agent.readback_matrix(O_BASE, 256, 64, env.scoreboard.dut_o);
        env.scoreboard.compute_golden();
        env.scoreboard.check_result(causal ? "CAUSAL" : "NOCAUSAL");

        env.coverage.sample_config(causal, 0, 0, 0, 0, 1, 0);
        env.coverage.sample_perf(poll.cycles);
    endtask
endclass
```

#### 块 ② 一个 bonus 测试示例（VP01 zero）

```systemverilog
class fab_zero_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_zero_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP01: Zero input test (Bonus)", UVM_LOW)
        gen_zero_matrix(q, 256, 64);
        gen_zero_matrix(k, 256, 64);
        gen_zero_matrix(v, 256, 64);
        run_bonus_attention(0, q, k, v);
        env.coverage.sample_vp("zero");
        phase.drop_objection(this);
    endtask
endclass
```

**说明：** 与 baseline `fa_zero_test` 完全相同的结构，只是基类换成 `fa_bonus_base_test`，调用 `run_bonus_attention` 而非 `run_attention`。**24 个测试都是这种模板的 bonus 版本**，代码重复度高，省略其他 23 个。**整体结构与 baseline 测试图（[§3.4.2](images/03_test_suite.png)）相同**，无需重新作图。

---

## 5.7 `bonus/tb/tb_top/fa_bonus_tb_top.sv`

### 5.7.1 概述

bonus UVM 的顶层 HDL 模块，与 baseline `fa_tb_top` 结构相同，只是：
- DUT 实例化 `flash_attention_bonus_top`（多 9 个 AXI4-Stream 端口）。
- 协议检查器仍是 baseline 的两个（AXI4 + AXI4-Lite）。
- bonus 没有独立 stream 协议检查器（AXI4-Stream 是简单 valid/ready，断言相对简单）。

**架构图与 baseline TB 顶层 ([§3.4.3](images/03_uvm_env.png)) 同构，无需重绘**。

### 5.7.2 关键差异片段

```systemverilog
module fa_bonus_tb_top;
    /* clk/rst 同 baseline */

    axi4_lite_if axil_if (.clk(clk), .rst_n(rst_n));
    axi4_mem_if  mem_if  (.clk(clk), .rst_n(rst_n));

    /* AXI4-Stream signals (driven by future stream tests) */
    logic [127:0] s_axis_tdata = 0;
    logic         s_axis_tvalid = 0;
    logic         s_axis_tready;
    logic         s_axis_tlast = 0;
    logic [1:0]   s_axis_tid = 0;
    logic [127:0] m_axis_tdata;
    logic         m_axis_tvalid;
    logic         m_axis_tready = 1;
    logic         m_axis_tlast;

    flash_attention_bonus_top u_dut (
        .clk(clk), .rst_n(rst_n),
        /* 17 axil + 30 axi master 同 baseline */
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .s_axis_tid(s_axis_tid),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .irq()
    );

    /* protocol checkers same as baseline */
    /* config_db set, run_test, timeout */
endmodule
```

**说明：** bonus tb 顶层只是 baseline tb 的"DUT 替换 + 多 9 个 stream 端口"。Stream 端口在 UVM 测试中没有真正驱动（默认 `tvalid=0`），因为 stream 模式只在专门的 stream 测试中启用。

---

## 5.8 `bonus/tb/bonus_system_tb.sv`

### 5.8.1 概述

821 行，bonus 直接 TB（非 UVM），由 `scripts/run_bonus.sh` 调用。包含 **19 项独立测试**，覆盖每个 bonus 功能（BF16、multi-head、variable len、padding、dropout、INT8、Stream、Task Queue）。结构上是单 `initial` block 内 procedural code 顺序执行。

### 5.8.2 总体结构（节选）

```systemverilog
`timescale 1ns/1ps
`include "fa_params_bonus.svh"

module bonus_system_tb;
    /* clk, rst, axil/axi master signals 同 baseline system_tb */
    /* axi4-stream signals */

    flash_attention_bonus_top dut (/*...*/);
    axi4_slave_mem u_mem (/*...*/);

    /* AXI4-Lite write/read tasks (同 baseline) */
    task axil_write(input [7:0] addr, input [31:0] data); /*...*/ endtask
    task axil_read (input [7:0] addr, output [31:0] data); /*...*/ endtask

    /* helper: load matrix, fp golden model, error check */

    // ===== 19 sub-tests =====
    initial begin
        wait(rst_n);
        repeat(50) @(posedge clk);

        $display("\n=== Bonus Test 1: Q8.8 baseline equivalence ===");
        run_test_q8_8(/*...*/);

        $display("\n=== Bonus Test 2: Multi-head (4 heads) ===");
        run_test_multihead(4);

        $display("\n=== Bonus Test 3: Variable seq_len 128 ===");
        run_test_var_seq(128);

        $display("\n=== Bonus Test 4: Padding mask (valid_len=200) ===");
        run_test_padding(200);

        $display("\n=== Bonus Test 5: Dropout (drop_prob=64) ===");
        run_test_dropout(64);

        /* ... 14 more sub-tests ... */

        $display("\n=== ALL 19 BONUS TESTS COMPLETE ===");
        $finish;
    end
endmodule
```

**说明：** 每个 sub-test 是一个 task，封装"配置寄存器 → 启动 → 等 done → 读回 O → fp 比对"。整体上更像 directed test 而不是 random/coverage-driven，速度快但覆盖率低，**用作 quick smoke test**。**结构简单（线性脚本），无需图示**。

---

## 5.9 `scripts/seqgen_stub.v`

### 5.9.1 概述

DC (Design Compiler) 综合后产生的 gate-level netlist 中可能包含两个工艺无关的中间单元 `**SEQGEN**` 和 `SELECT_OP`，标准工艺库里没有，所以仿真时找不到模块定义。这个文件提供两个**行为模型**让 gate-sim 能跑起来。

### 5.9.2 完整源代码

```systemverilog
// Temporary SEQGEN behavioral model for gate-level simulation of generic netlists.
module \**SEQGEN** (clear, preset, next_state, clocked_on, data_in, enable, Q,
                    synch_clear, synch_preset, synch_toggle, synch_enable);
    input clear, preset, next_state, clocked_on, data_in, enable;
    input synch_clear, synch_preset, synch_toggle, synch_enable;
    output reg Q;

    always @(posedge clocked_on or posedge clear or posedge preset) begin
        if (clear)              Q <= 1'b0;
        else if (preset)        Q <= 1'b1;
        else begin
            if (synch_clear)        Q <= 1'b0;
            else if (synch_preset)  Q <= 1'b1;
            else if (synch_toggle)  Q <= ~Q;
            else if (synch_enable)  Q <= next_state;
            else if (enable)        Q <= data_in;
        end
    end
endmodule

// Temporary SELECT_OP behavioral model for generic mapped netlists.
module SELECT_OP (
    DATA1, DATA2, ..., DATA15,
    CONTROL1, CONTROL2, ..., CONTROL15,
    Z
);
    input DATA1, DATA2, ..., DATA15;
    input CONTROL1, CONTROL2, ..., CONTROL15;
    output Z;

    assign Z = CONTROL1  ? DATA1  :
               CONTROL2  ? DATA2  :
               /* ... 13 more priority cascades ... */
               CONTROL15 ? DATA15 : 1'b0;
endmodule
```

### 5.9.3 解释

- **`**SEQGEN**`**：是 DC 工艺无关阶段（compile-stage 1）产生的"通用触发器"单元 — 同时支持异步 clear/preset、同步 clear/preset/toggle/enable。后续 mapping 阶段会替换成具体工艺库的 DFF。如果直接对 compile-stage netlist 跑 sim 就会缺这个单元，所以 stub 提供等价行为。模块名外面的 `\` 转义反斜杠是因为 `**` 在 Verilog 标识符里需要转义。
- **`SELECT_OP`**：DC 通用 mux 单元，15 选 1 的优先级编码 mux（与一般 4 选 1 mux 不同，这是个 priority encoder）。`Z = CONTROL1 ? DATA1 : CONTROL2 ? DATA2 : ... : 0`。
- **由 `scripts/run_postsim.sh` 在 gate-sim 时与 netlist 一起编译**，仅用于绕过工具链 bug 而不是产品 RTL。
- **过于简单（两个 stub），无需图示**。

---

## 全书完结语

至此，`/home/hy258/cadence/submission` 下所有 56 个 .v / .sv / .svh 文件全部讲解完毕：

| 章节 | 文件数 | 累计行数 | 关键产出 |
|------|-------|---------|---------|
| 第 0 章 总览 | — | — | 项目背景、顶层架构图 |
| 第 1 章 Baseline 计算通路 | 11 | ~1620 | 7 个流水架构图 |
| 第 2 章 Baseline 存储与总线 | 4 | ~840 | 4 个架构图 |
| 第 3 章 Baseline UVM 验证 | 20 | ~3700 | 2 个 UVM 层次图 |
| 第 4 章 Bonus RTL | 12 | ~2050 | 3 个 Bonus 架构图 |
| 第 5 章 Bonus UVM + scripts | 10 | ~2360 | — |
| **合计** | **57** (含 stub) | **~10,570** | **17 张图** |

**重要观察 / 设计模式总结**：

1. **FSM 是 baseline 的核心范式**：12 状态 tile_controller、6 状态 compute_core、4 状态 dot_product、6 状态 online_softmax、7 状态 output_accumulator、4+4 状态 dma_engine 读写… 几乎每个时序模块都是一个明确的 FSM。这种风格调试容易、综合友好。

2. **流水化与时分复用的折中**：dot_product 用 64 个并行 MAC（高并行）、online_softmax 用单个 exp 单元时分复用（高复用），output_accumulator 把 rescale 串行化（低并行）— 不同模块按面积/吞吐 trade-off 选择不同策略。

3. **Q8.8 + 40-bit 累加器的算术 budget**：刚好够 256 个 16×16 乘法累加而不溢出，再加 8-bit headroom — 经过仔细数值分析。

4. **Online softmax 的 m,ℓ 滚动状态**：是 FlashAttention 算法核心，由 compute_core 的 always_ff 持久化跨 KV tile 维护。

5. **K/V 双缓冲 ping-pong**：通过 `tc_kv_buf_sel` 和 `~tc_kv_buf_sel` 在 dma_engine 和 compute_core 之间反向选择，实现"加载下一 tile / 计算当前 tile"重叠。但 baseline 的 `tile_controller` FSM 实际是严格串行（DMA→compute→DMA→compute），ping-pong 没有真正发挥作用 —— bonus 的 task_queue 才解决了这个吞吐瓶颈。

6. **UVM 验证完整度**：24 baseline + 24 bonus = 48 测试，覆盖功能正确性、寄存器、DMA、AXI 协议、性能、覆盖率。两套协议检查器 (39 条 SVA) 始终监控总线。验证结果 `mean_abs_err=0.013`、`max_abs_err=0.238`，远低于 1.0 / 1.5 阈值，说明硬件实现与浮点 reference 模型偏差很小。

7. **Bonus 的 9 项功能用最少代码改动实现**：很多模块（dropout / mask / quantizer / stream）都只需要 80–150 行小模块；最大改动是 `compute_core_bonus` (375 行) 和顶层 `flash_attention_bonus_top` (369 行)，因为要 multiplex 多种数据格式 + 集成所有新模块。

