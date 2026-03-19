# FlashAttention 高性能硬件加速器 IP 设计 — 解决计划书

> **赛题**：赛题二 — 基于大模型推理的 FlashAttention 高性能硬件加速器 IP 设计
> **赛事**：第九届中国研究生创芯大赛 · Cadence 企业命题

---

## 一、赛题需求总览

### 1.1 核心目标

设计一个**可综合 RTL IP**，实现 FlashAttention-style 的 Scaled Dot-Product Attention (SDPA) 硬件加速器，在不显式存储完整注意力矩阵的前提下完成端到端注意力计算。

### 1.2 固定输入规模（Baseline）

| 参数 | 值 |
|---|---|
| 序列长度 s | 256 |
| Head 维度 d | 64 |
| Q/K/V/O 形状 | [256, 64] |
| Batch | 1 |
| Head | 1 |

### 1.3 数据格式

| 数据 | 格式 | 位宽 |
|---|---|---|
| 输入 Q/K/V | Q8.8 有符号定点 | 16-bit |
| 点积累加 | 有符号定点 | ≥ 40-bit |
| Softmax 中间值 | 允许更高位宽/分段缩放 | 自定义 |
| 输出 O | Q8.8 有符号定点 | 16-bit |

### 1.4 性能约束

| 指标 | 要求 |
|---|---|
| 主频 | 尽可能高（Synopsys Design Compiler 综合报告） |
| 面积 | 等效逻辑门 ≤ 200 万门 |
| 延迟 | 单次 attention (s=256, d=64, causal) < 300k cycles |
| 带宽 | 提供 RD/WR BYTES 统计与优化分析 |

### 1.5 接口规范

- **AXI4-Lite Slave**（控制通路）：主机配置寄存器，启动/查询状态
- **AXI4 Master + DMA**（数据通路）：加速器主动从外存读取 Q/K/V，计算完成后写回 O

### 1.6 FlashAttention 核心约束

1. **禁止**显式存储完整 S = QK^T 注意力矩阵（256×256 = 64K 项）
2. **必须**使用在线（online）softmax 算法
3. **必须**分块（tiling）处理 K/V

---

## 二、算法方案设计

### 2.1 标准 SDPA 公式

对每个 query 位置 i：

```
O[i] = Σ_j { softmax(Q[i]·K[j]^T / √d) · V[j] }
```

其中 causal mask 要求当 j > i 时，score 置为 -inf（使用 NEG_LARGE 寄存器值近似）。

### 2.2 FlashAttention 在线算法

采用经典的 **Online Softmax + Tiling** 策略，按 K/V 的 tile 维度迭代：

**符号定义**：
- `B_c`：K/V tile 大小（列方向分块数），即每次加载的 K/V 行数
- `B_r`：Q tile 大小（行方向分块数），即每次处理的 Q 行数
- `T_c = ceil(s / B_c)`：K/V tile 总数
- `T_r = ceil(s / B_r)`：Q tile 总数

**算法伪代码**：

```
for each Q-tile i (B_r rows of Q):
    初始化：m_i = -inf, l_i = 0, O_i = 0

    for each KV-tile j (B_c rows of K and V):
        // 1. 加载当前 tile
        K_j = K[j*B_c : (j+1)*B_c, :]   // shape [B_c, d]
        V_j = V[j*B_c : (j+1)*B_c, :]   // shape [B_c, d]

        // 2. 计算局部分数
        S_ij = Q_i · K_j^T / scale        // shape [B_r, B_c]

        // 3. 应用 causal mask（若 col_index > row_index 则置为 NEG_LARGE）

        // 4. Online softmax 更新
        m_new = max(m_i, rowmax(S_ij))
        P_ij  = exp(S_ij - m_new)         // 局部 softmax 指数
        l_new = l_i * exp(m_i - m_new) + rowsum(P_ij)

        // 5. 输出累加更新
        O_i = O_i * (l_i * exp(m_i - m_new) / l_new) + P_ij · V_j / l_new

        // 6. 状态更新
        m_i = m_new
        l_i = l_new

    // 7. 写回 O_i
```

### 2.3 Tiling 策略分析

在面积约束 ≤ 200 万门下，需要仔细平衡片上 buffer 大小与计算并行度。

**推荐分块参数**：

| 参数 | 推荐值 | 存储需求 |
|---|---|---|
| B_r（Q tile rows） | 4 | Q tile: 4×64×16b = 512 Bytes |
| B_c（KV tile rows） | 16 | K tile: 16×64×16b = 2 KB, V tile: 同 2 KB |
| S_ij tile | 4×16 | 128 Bytes（40-bit 格式 = 320 Bytes） |
| m, l per row | 4 个 | 极少量寄存器 |
| O 累加 buffer | 4×64 | 512 Bytes（40-bit = 1.25 KB） |

**总片上 buffer 估算**：约 6-8 KB（远小于面积约束，留出大量空间给计算逻辑）。

**迭代次数**：
- Q tiles: 256 / 4 = 64
- KV tiles: 256 / 16 = 16
- 总迭代: 64 × 16 = 1024 次 tile 计算

### 2.4 定点 exp 近似方案

exp 函数是 FlashAttention 硬件化最关键的非线性运算。采用**分段线性近似 + 查找表 (LUT)** 混合方案：

**方案选择**：基于 2^x 的移位近似

1. 将 `exp(x)` 转化为 `2^(x / ln2)` = `2^(x * 1.4427)`
2. 分离整数部分（移位实现）和小数部分（LUT 插值）
3. 对 x < NEG_LARGE 直接输出 0（下溢截断）

**精度控制**：
- 使用 256 项 LUT 覆盖 [0, 1) 的小数区间
- 整数部分通过桶形移位器（barrel shifter）实现
- 误差控制在 Q8.8 的 1 LSB 以内

### 2.5 定点倒数近似方案

Online softmax 需要计算 `1/l_new`。采用 **Newton-Raphson 迭代**：

1. 用 LUT 查表获得初始近似值 `x0 ≈ 1/l`
2. 迭代 `x_{n+1} = x_n * (2 - l * x_n)`，2 次迭代可达足够精度
3. 每次迭代仅需乘法和减法，硬件开销可控

---

## 三、硬件架构设计

### 3.1 顶层架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    FlashAttention Accelerator Top               │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │  AXI4-Lite   │    │   Register   │    │   Main FSM /     │  │
│  │  Slave I/F   │◄──►│   File       │◄──►│   Sequencer      │  │
│  └──────────────┘    └──────────────┘    └────────┬─────────┘  │
│                                                    │            │
│         ┌──────────────────────────────────────────┤            │
│         │                                          │            │
│  ┌──────▼──────┐    ┌──────────────┐    ┌─────────▼────────┐  │
│  │  AXI4 Master│    │  DMA Engine  │    │  Tile Controller │  │
│  │  Interface  │◄──►│  (RD + WR)   │◄──►│  (Address Gen)   │  │
│  └─────────────┘    └──────┬───────┘    └────────┬─────────┘  │
│                            │                      │            │
│                     ┌──────▼──────────────────────▼─────┐      │
│                     │         On-Chip Buffer System      │      │
│                     │  ┌────────┐ ┌────────┐ ┌────────┐ │      │
│                     │  │ Q Buf  │ │ K Buf  │ │ V Buf  │ │      │
│                     │  │(B_r×d) │ │(B_c×d) │ │(B_c×d) │ │      │
│                     │  └───┬────┘ └───┬────┘ └───┬────┘ │      │
│                     └─────┼──────────┼──────────┼──────┘      │
│                           │          │          │              │
│                     ┌─────▼──────────▼──────────▼──────┐      │
│                     │       Compute Core               │      │
│                     │  ┌───────────────────────────┐   │      │
│                     │  │  Dot-Product Array (DP)   │   │      │
│                     │  │  B_r × B_c parallel MACs  │   │      │
│                     │  └─────────┬─────────────────┘   │      │
│                     │            │                      │      │
│                     │  ┌─────────▼─────────────────┐   │      │
│                     │  │  Online Softmax Unit       │   │      │
│                     │  │  max / exp / sum / rescale │   │      │
│                     │  └─────────┬─────────────────┘   │      │
│                     │            │                      │      │
│                     │  ┌─────────▼─────────────────┐   │      │
│                     │  │  Output Accumulator (OA)   │   │      │
│                     │  │  P_ij · V_j 累加与缩放      │   │      │
│                     │  └───────────────────────────┘   │      │
│                     └──────────────────────────────────┘      │
│                                                                 │
│  ┌──────────────┐                                              │
│  │  O Write-Back│   ← 最终结果从 OA buffer 通过 DMA 写回       │
│  │  Buffer      │                                              │
│  └──────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 模块层次划分

```
flash_attention_top
├── axi4_lite_slave          // AXI4-Lite 从接口 + 寄存器文件
│   └── register_file        // 控制/状态/配置寄存器
├── axi4_master_if           // AXI4 主接口
├── dma_engine               // DMA 读/写引擎
│   ├── dma_read_channel     // 突发读通道
│   └── dma_write_channel    // 突发写通道
├── tile_controller          // Tiling 地址生成 & 流控
│   └── address_generator    // 基于 tile 索引的地址计算
├── buffer_system            // 片上 SRAM/寄存器堆缓存
│   ├── q_buffer             // Q tile 双缓冲
│   ├── k_buffer             // K tile 双缓冲
│   ├── v_buffer             // V tile 双缓冲
│   └── o_buffer             // O 累加缓冲
├── compute_core             // 核心计算单元
│   ├── dot_product_array    // 点积阵列
│   ├── online_softmax_unit  // 在线 softmax
│   │   ├── row_max_unit     // 行最大值计算
│   │   ├── exp_approx_unit  // 定点 exp 近似 (LUT + 移位)
│   │   ├── row_sum_unit     // 行求和
│   │   └── reciprocal_unit  // 倒数近似 (Newton-Raphson)
│   ├── score_scale_unit     // 分数缩放 (÷√d)
│   └── output_accumulator   // 加权输出累加
├── causal_mask_unit         // Causal mask 生成逻辑
└── cycle_counter            // 执行周期计数器
```

### 3.3 关键模块详细设计

#### 3.3.1 寄存器文件 (Register File)

严格按照赛题规定的寄存器映射表实现：

| Offset | 名称 | 方向 | 功能 |
|---|---|---|---|
| 0x00 | CTRL | R/W | bit0: START, bit1: SOFT_RESET, bit2: IRQ_EN |
| 0x04 | STATUS | R | bit0: BUSY, bit1: DONE, bit2: ERROR |
| 0x08 | CFG | R/W | bit0: CAUSAL_EN |
| 0x14-0x18 | Q_BASE | R/W | Q 矩阵基地址 (64-bit) |
| 0x1C-0x20 | K_BASE | R/W | K 矩阵基地址 (64-bit) |
| 0x24-0x28 | V_BASE | R/W | V 矩阵基地址 (64-bit) |
| 0x2C-0x30 | O_BASE | R/W | O 矩阵基地址 (64-bit) |
| 0x34 | STRIDE_BYTES | R/W | 行 stride，默认 d×2 = 128 |
| 0x38 | NEG_LARGE | R/W | -inf 近似值 (Q8.8) |
| 0x3C | SCALE | R/W | 缩放常数 (1/√d 的 Q8.8 表示) |
| 0x40 | CYCLES | R | 本次执行周期计数 |

#### 3.3.2 DMA 引擎

**读通道设计**：
- 支持 AXI4 突发传输（Burst Length 可配置，推荐 16 beats）
- 数据宽度 128-bit（每拍传输 8 个 Q8.8 数据）
- 支持非对齐地址处理
- 双缓冲机制：DMA 加载下一 tile 的同时计算引擎处理当前 tile

**写通道设计**：
- 支持突发写回 O 矩阵
- 带写缓冲，允许计算与写回流水

**带宽估算（Baseline，单次 attention）**：

| 操作 | 数据量 | 说明 |
|---|---|---|
| 读 Q | 256 × 64 × 2 = 32 KB | 每个 Q tile 读 1 次，共 64 次 × 512 B |
| 读 K | 256 × 64 × 2 × 64 = 2 MB | 每个 Q tile 需遍历所有 K tile；64 × 16 × 2 KB |
| 读 V | 256 × 64 × 2 × 64 = 2 MB | 同 K |
| 写 O | 256 × 64 × 2 = 32 KB | 最终结果写回 |
| **总计** | **约 4.06 MB** | |

**优化策略**：
- Q tile 保持不变时复用，减少 Q 重读
- 若片上存储允许，缓存完整 K/V 可将读带宽降至约 64 KB

#### 3.3.3 点积阵列 (Dot-Product Array)

**架构**：采用脉动阵列（Systolic Array）风格的 MAC 阵列

- 并行度：同时计算 B_r × B_c = 4 × 16 = 64 个点积
- 每个点积需要 d = 64 次 MAC 操作
- 每个 MAC：16b × 16b → 40b 累加

**流水设计**：
- 将 d=64 的点积拆分为多拍完成
- 每拍处理 P 个乘累加（P = 4 或 8，视面积约束）
- 当 P=8 时，单个 tile 的点积计算需 64/8 = 8 拍
- B_r × B_c = 64 个点积可通过空间并行 + 时间复用实现

**资源估算**：
- 若使用 8 个并行 MAC 单元处理一行点积
- 4 行并行 → 32 个 MAC 单元
- 每个 MAC：1 个 16×16 乘法器 + 1 个 40-bit 加法器
- 总计约 32 × (乘法器 + 加法器) ≈ 15-20 万门

#### 3.3.4 Online Softmax 单元

**行最大值单元 (Row Max)**：
- 对 S_ij 的每行 B_c=16 个元素求最大值
- 使用比较树结构，4 级比较完成（log2(16) = 4）
- 与历史 m_i 再做一次比较得到 m_new

**Exp 近似单元**：
- 对 `S_ij[r][c] - m_new` 计算 exp
- 总共 B_r × B_c = 64 个 exp 运算/tile
- 可时间复用 4-8 个 exp 单元
- 每个 exp 单元：LUT (256×16b = 512 Bytes) + 桶形移位器 + 乘法器

**行求和单元 (Row Sum)**：
- 对 P_ij 每行求和，得到 Σ exp(...)
- 使用加法树，4 级加法完成

**缩放单元 (Rescale)**：
- 计算 `exp(m_old - m_new)` 用于历史值缩放
- 计算 `1/l_new` 用于归一化（Newton-Raphson，2 次迭代）

#### 3.3.5 输出累加器 (Output Accumulator)

- 维护 B_r × d = 4 × 64 = 256 个 40-bit 累加值
- 每次 KV-tile 迭代更新：
  - `O_i = O_i * rescale_factor + P_ij · V_j`
- 最后一个 KV-tile 完成后截断为 Q8.8 输出

#### 3.3.6 Causal Mask 单元

- 根据当前 Q-tile 行索引 `row_idx` 和 KV-tile 列索引 `col_idx`
- 当 `col_idx > row_idx` 时将 score 置为 NEG_LARGE
- 纯组合逻辑比较器实现，面积极小

### 3.4 流水线与时序设计

整体采用**三级宏流水线**：

```
时间轴 →
────────────────────────────────────────────────────────
Stage 1 (DMA Load):    [KV tile j]  [KV tile j+1]  [KV tile j+2] ...
Stage 2 (Compute):      idle        [KV tile j]    [KV tile j+1] ...
Stage 3 (O Writeback):  idle         idle          [Q tile完成时写回]
────────────────────────────────────────────────────────
```

- **双缓冲**：K/V buffer 使用 Ping-Pong 双缓冲，DMA 加载与计算并行
- **计算流水**：点积 → softmax → 累加 内部也采用流水线

### 3.5 主状态机 (Main FSM)

```
       ┌────────┐
       │  IDLE  │ ← 复位/完成后回到此状态
       └───┬────┘
    START=1│
       ┌───▼────┐
       │  INIT  │ ← 加载配置、初始化计数器
       └───┬────┘
       ┌───▼────────┐
       │  LOAD_Q     │ ← DMA 加载当前 Q tile
       └───┬────────┘
       ┌───▼────────┐
  ┌───►│  LOAD_KV   │ ← DMA 加载当前 KV tile
  │    └───┬────────┘
  │    ┌───▼────────┐
  │    │  COMPUTE   │ ← 点积 + online softmax + 累加
  │    └───┬────────┘
  │        │ KV tile 未遍历完？
  │    YES │
  │    ┌───▼────────┐
  │    │ NEXT_KV    │ ← 更新 KV tile 索引
  │    └───┬────────┘
  │        │
  └────────┘
           │ 所有 KV tile 完成
       ┌───▼────────┐
       │  WRITE_O   │ ← DMA 写回当前 Q tile 对应的 O 行
       └───┬────────┘
           │ Q tile 未遍历完？ → 回到 LOAD_Q
       ┌───▼────┐
       │  DONE  │ ← 设置 STATUS.DONE, 触发中断
       └───┬────┘
           │
       ┌───▼────┐
       │  IDLE  │
       └────────┘
```

---

## 四、Cycle 预算分析

### 4.1 单 tile 计算周期

以 B_r=4, B_c=16, d=64, 并行 MAC 数 P=8 为例：

| 阶段 | 周期数 | 说明 |
|---|---|---|
| 点积计算 | 64/8 × 16 = 128 | 4 行并行，每行与 16 列依次计算；每个点积 8 拍 |
| Causal mask | 1 | 组合逻辑，流水融合 |
| Row max | 4 | 比较树 |
| Exp 计算 | 16 | 16 个 exp（4 个并行 exp 单元 × 4 拍） |
| Row sum | 4 | 加法树 |
| Rescale | 6 | exp(m_old-m_new) + Newton-Raphson 倒数 |
| O 累加 | 64/8 × 16 = 128 | P_ij · V_j 矩阵乘 |
| **合计** | **~287** | |

流水线重叠后预估约 **200 cycles/tile**。

### 4.2 DMA 传输周期

假设 AXI4 数据宽度 128-bit，突发长度 16：

| 传输 | 数据量 | Beats | 周期（含开销） |
|---|---|---|---|
| 加载 Q tile (4×64×2B) | 512 B | 32 | ~40 |
| 加载 K tile (16×64×2B) | 2048 B | 128 | ~140 |
| 加载 V tile (16×64×2B) | 2048 B | 128 | ~140 |
| 写回 O tile (4×64×2B) | 512 B | 32 | ~40 |

双缓冲下 DMA 与计算重叠，DMA 延迟大部分被隐藏。

### 4.3 总周期估算

```
总周期 = T_r × (Q加载 + T_c × max(计算, DMA_KV) + O写回) + 固定开销
       = 64 × (40 + 16 × max(200, 140) + 40) + 100
       = 64 × (40 + 16 × 200 + 40) + 100
       = 64 × 3280 + 100
       = 210,020 cycles
```

**约 210k cycles**，满足 < 300k cycles 的要求，留有约 30% 的余量。

---

## 五、面积预算分析

### 5.1 各模块面积估算

| 模块 | 估算门数 | 占比 | 说明 |
|---|---|---|---|
| AXI4-Lite Slave + 寄存器 | ~10K | 0.5% | 标准接口逻辑 |
| AXI4 Master + DMA 引擎 | ~50K | 2.5% | 含读写通道、地址生成、FIFO |
| Buffer 系统 (SRAM) | ~400K | 20% | Q/K/V/O 双缓冲，约 16-20 KB |
| 点积阵列 (32 MAC) | ~300K | 15% | 32 个 16×16 乘法器 + 40b 加法器 |
| Online Softmax 单元 | ~200K | 10% | exp LUT + 比较树 + 加法树 + 倒数 |
| 输出累加器 | ~150K | 7.5% | 乘法器 + 累加寄存器 |
| 控制逻辑 (FSM + Tile Ctrl) | ~30K | 1.5% | 状态机 + 地址生成 |
| Causal Mask + 杂项 | ~10K | 0.5% | 比较器 |
| **总计** | **~1.15M** | **57.5%** | 余量充足 |

在 200 万门约束下占用约 57.5%，有充分余量用于优化或 Bonus 扩展。

---

## 六、验证方案（SystemVerilog + UVM）

### 6.1 验证框架选择

采用 **SystemVerilog + UVM (Universal Verification Methodology)** 方案，原因：
- 工业标准验证方法学，评审认可度最高
- 可复用的组件化架构（Agent、Sequence、Scoreboard）
- 强大的约束随机激励生成能力
- 内建功能覆盖率与断言覆盖率机制
- 使用 Synopsys VCS 进行编译和仿真

### 6.2 UVM 验证环境架构

```
fa_tb_top (顶层 testbench module)
│
├── flash_attention_top (DUT)
│
└── fa_test (UVM test)
    └── fa_env (UVM environment)
        │
        ├── axi4_lite_agent (AXI4-Lite 主端 Agent)
        │   ├── axi4_lite_driver        // 驱动寄存器读写
        │   ├── axi4_lite_monitor        // 监控 AXI4-Lite 事务
        │   └── axi4_lite_sequencer      // 序列调度器
        │
        ├── axi4_mem_agent (AXI4 从端 Agent — 模拟外部存储器)
        │   ├── axi4_slave_driver        // 响应 DMA 读写请求
        │   ├── axi4_slave_monitor       // 监控 AXI4 Master 事务
        │   └── memory_model             // 内存模型 (存储 Q/K/V/O)
        │
        ├── fa_scoreboard (记分板)
        │   ├── golden_model             // SV 实现的 FP32 参考模型
        │   ├── result_checker           // 比较 DUT 输出与 golden
        │   └── error_statistics         // 误差统计 (mean/max abs error)
        │
        ├── fa_coverage (功能覆盖率收集器)
        │   ├── cfg_covergroup           // 配置空间覆盖
        │   ├── data_covergroup          // 数据模式覆盖
        │   └── fsm_covergroup           // 状态机转移覆盖
        │
        └── fa_virtual_sequencer         // 虚拟序列器，协调多个 Agent
```

### 6.3 UVM 关键组件详述

#### 6.3.1 AXI4-Lite Agent

实现 AXI4-Lite 主端接口，用于配置 DUT 寄存器并启动计算：

- **Transaction 类 (`axi4_lite_txn`)**：包含地址、数据、读/写类型
- **Driver**：将 transaction 转化为 AXI4-Lite 总线波形（AW/W/B 写通道，AR/R 读通道）
- **Monitor**：采样总线信号，构建 transaction 发送给 scoreboard
- **Sequence 库**：
  - `reg_write_seq`：单寄存器写入
  - `reg_read_seq`：单寄存器读取
  - `fa_config_seq`：完整配置序列（写入所有基地址 + 参数 + 启动）
  - `fa_poll_done_seq`：轮询 STATUS.DONE

#### 6.3.2 AXI4 Memory Agent

模拟外部存储器，响应 DUT 作为 AXI4 Master 发起的读写请求：

- **Memory Model**：使用关联数组实现大地址空间存储，预加载 Q/K/V 数据
- **Slave Driver**：按 AXI4 协议响应突发读写（支持 INCR/WRAP burst）
- **Monitor**：记录所有 DMA 事务，用于带宽统计

#### 6.3.3 Scoreboard

核心验证逻辑：

- 从 AXI4 Memory Agent Monitor 接收 DUT 写回的 O 矩阵数据
- 调用 Golden Model 计算 FP32 参考结果
- 将 DUT 的 Q8.8 输出转换为浮点数后与 golden 对比
- 实时统计 mean_abs_error 和 max_abs_error
- 在 `check_phase` 中判断是否通过误差门限

#### 6.3.4 Golden Reference Model (SystemVerilog)

在 scoreboard 内实现 FP32 精度的 SDPA 参考计算：

```systemverilog
function void compute_golden(
    input  shortint Q[256][64],  // Q8.8 输入
    input  shortint K[256][64],
    input  shortint V[256][64],
    input  bit      causal_en,
    output shortint O[256][64]   // Q8.8 输出
);
    real q_f[256][64], k_f[256][64], v_f[256][64];
    real s_f[256][256], p_f[256][256], o_f[256][64];
    real scale = 1.0 / $sqrt(64.0);
    real row_max, row_sum;

    // Q8.8 → float
    foreach (Q[i,j]) q_f[i][j] = real'(Q[i][j]) / 256.0;
    foreach (K[i,j]) k_f[i][j] = real'(K[i][j]) / 256.0;
    foreach (V[i,j]) v_f[i][j] = real'(V[i][j]) / 256.0;

    // S = Q * K^T * scale, apply causal mask, softmax, O = P * V
    for (int i = 0; i < 256; i++) begin
        row_max = -1e30;
        for (int j = 0; j < 256; j++) begin
            s_f[i][j] = 0;
            for (int k = 0; k < 64; k++)
                s_f[i][j] += q_f[i][k] * k_f[j][k];
            s_f[i][j] *= scale;
            if (causal_en && j > i) s_f[i][j] = -1e9;
            if (s_f[i][j] > row_max) row_max = s_f[i][j];
        end
        row_sum = 0;
        for (int j = 0; j < 256; j++) begin
            p_f[i][j] = $exp(s_f[i][j] - row_max);
            row_sum += p_f[i][j];
        end
        for (int j = 0; j < 256; j++)
            p_f[i][j] /= row_sum;
        for (int j = 0; j < 64; j++) begin
            o_f[i][j] = 0;
            for (int k = 0; k < 256; k++)
                o_f[i][j] += p_f[i][k] * v_f[k][j];
            // float → Q8.8
            O[i][j] = shortint'($rtoi(o_f[i][j] * 256.0));
        end
    end
endfunction
```

### 6.4 UVM Test 与 Sequence 规划

#### 测试基类

```systemverilog
class fa_base_test extends uvm_test;
    fa_env env;

    virtual function void build_phase(uvm_phase phase);
        env = fa_env::type_id::create("env", this);
    endfunction

    virtual task configure_dut(
        bit [63:0] q_base, k_base, v_base, o_base,
        bit causal_en, bit [15:0] scale, neg_large
    );
        // 通过 axi4_lite_agent 写入所有寄存器
    endtask
endclass
```

#### 测试用例清单

| 编号 | UVM Test 类名 | 说明 | 覆盖目标 |
|---|---|---|---|
| TC01 | `fa_zero_test` | Q=K=V=0 | 全零边界 |
| TC02 | `fa_identity_test` | Q=K=I, V=I | softmax 行为验证 |
| TC03 | `fa_random_nocausal_test` | 随机数据, CAUSAL_EN=0 | 基础功能 |
| TC04 | `fa_random_causal_test` | 随机数据, CAUSAL_EN=1 | Causal mask 功能 |
| TC05 | `fa_causal_row0_test` | Causal, 关注第 0 行输出 | 边界：仅看自身 |
| TC06 | `fa_causal_lastrow_test` | Causal, 关注最后一行输出 | 边界：看所有 token |
| TC07 | `fa_extreme_test` | Q8.8 极值 (±127.99) | 溢出/饱和处理 |
| TC08 | `fa_consecutive_test` | 连续执行 2 次 | 状态复位 |
| TC09 | `fa_reg_access_test` | 遍历所有寄存器读写 | 寄存器映射正确性 |
| TC10 | `fa_soft_reset_test` | 运行中触发 SOFT_RESET | 复位恢复 |
| TC11 | `fa_random_stress_test` | 100 组随机约束数据 | 误差统计分布 |
| TC12 | `fa_error_inject_test` | 非法配置/地址 | STATUS.ERROR 行为 |

#### 约束随机激励

```systemverilog
class fa_random_sequence extends uvm_sequence #(axi4_lite_txn);
    rand bit [15:0] q_data[256][64];
    rand bit [15:0] k_data[256][64];
    rand bit [15:0] v_data[256][64];
    rand bit        causal_en;

    constraint data_range_c {
        foreach (q_data[i,j]) q_data[i][j] inside {[16'hF000:16'h0FFF]};
        foreach (k_data[i,j]) k_data[i][j] inside {[16'hF000:16'h0FFF]};
        foreach (v_data[i,j]) v_data[i][j] inside {[16'hF000:16'h0FFF]};
    }

    constraint causal_dist_c {
        causal_en dist {1 := 70, 0 := 30};
    }

    virtual task body();
        // 1. 写入 Q/K/V 到 memory model
        // 2. 配置 DUT 寄存器
        // 3. 启动计算
        // 4. 等待 DONE
        // 5. 读出 O 供 scoreboard 检查
    endtask
endclass
```

### 6.5 功能覆盖率

```systemverilog
covergroup fa_func_cg;
    causal_cp: coverpoint causal_en {
        bins enabled  = {1};
        bins disabled = {0};
    }
    data_pattern_cp: coverpoint data_pattern {
        bins all_zero   = {ZERO};
        bins all_max    = {MAX};
        bins random_pos = {RAND_POS};
        bins random_neg = {RAND_NEG};
        bins mixed      = {MIXED};
    }
    query_row_cp: coverpoint query_row_idx {
        bins first_row = {0};
        bins last_row  = {255};
        bins mid_rows  = {[1:254]};
    }
    cross causal_cp, data_pattern_cp;
endgroup
```

### 6.6 正确性验收标准

- **mean_abs_error** < 赛题规定门限（与 FP32 golden 对比）
- **max_abs_error** < 赛题规定门限
- **功能覆盖率** > 95%（所有 covergroup）
- **代码覆盖率** > 95%（行/分支/条件/状态机/toggle）
- 需在报告中分析误差来源（定点量化误差 + exp 近似误差 + 倒数近似误差）

### 6.7 验证层次

```
Level 0: 单元级验证 (直接 SV testbench，非 UVM)
├── exp_approx_unit_tb.sv     // exp 近似：LUT 精度逐值遍历
├── reciprocal_unit_tb.sv     // 倒数：Newton-Raphson 收敛验证
├── dot_product_tb.sv         // 点积：已知向量对比
└── online_softmax_tb.sv      // softmax 单行数值对比

Level 1: 模块级验证 (轻量 UVM)
├── compute_core_env          // 计算核心端到端（直接喂数据，无 AXI）
├── dma_engine_env            // DMA 突发读写功能
└── axi4_lite_reg_env         // 寄存器读写遍历

Level 2: 系统级验证 (完整 UVM 环境)
├── fa_base_test              // 所有 TC01-TC12
├── fa_regression             // 全回归测试
└── fa_coverage_closure       // 覆盖率收敛补充测试
```

### 6.8 测试用例清单

| 编号 | 测试用例 | 说明 |
|---|---|---|
| TC01 | 全零输入 | Q=K=V=0，验证输出正确 |
| TC02 | 单位矩阵 | Q=K=I, V=I，验证 softmax 行为 |
| TC03 | 随机输入（无 causal） | CAUSAL_EN=0 |
| TC04 | 随机输入（有 causal） | CAUSAL_EN=1 |
| TC05 | Causal 第 0 行 | 仅能看到自身，验证边界 |
| TC06 | Causal 最后一行 | 能看到所有，验证完整性 |
| TC07 | 极值输入 | Q8.8 最大/最小值，验证溢出处理 |
| TC08 | 多次连续执行 | 验证状态复位正确 |
| TC09 | 寄存器读写 | AXI4-Lite 所有寄存器 |
| TC10 | SOFT_RESET | 运行中复位，验证恢复 |
| TC11 | 批量随机 (×100) | 100 组约束随机数据，统计误差分布 |
| TC12 | 错误注入 | 非法配置，验证 ERROR 标志 |

---

## 七、Synopsys EDA 工具使用计划

### 7.1 工具环境

使用 Docker 容器 `synopsys2016:0.0.0`，内含以下工具：

| 工具 | 版本 | 路径 |
|---|---|---|
| VCS | L-2016.06 | `/usr/synopsys/vcs-L-2016.06/` |
| Design Compiler (dc_shell) | L-2016.03-SP1 | `/usr/synopsys/dc-L-2016.03-SP1/` |
| PrimeTime (pt_shell) | M-2016.12-SP1 | `/usr/synopsys/pt-M-2016.12-SP1/` |
| IC Compiler (icc_shell) | L-2016.03-SP1 | `/usr/synopsys/icc-L-2016.03-SP1/` |
| Formality (fm_shell) | K-2015.06-SP4 | `/usr/synopsys/fm-K-2015.06-SP4/` |
| Library Compiler (lc_shell) | M-2016.12 | `/usr/synopsys/lc-M-2016.12/` |
| Verdi | L-2016.06-1 | `/usr/synopsys/verdi-L-2016.06-1/` |

### 7.2 设计流程

```
RTL 设计 (SystemVerilog)
       │
       ▼
功能仿真 + UVM 验证 (VCS)
       │
       ▼
代码/功能覆盖率分析 (VCS + URG)
       │
       ▼
波形调试 (Verdi) [需 GUI 环境]
       │
       ▼
逻辑综合 (Design Compiler / dc_shell)
       │
       ▼
综合后仿真 (VCS + SDF back-annotation)
       │
       ▼
时序分析 + 功耗分析 (PrimeTime / pt_shell)
       │
       ▼
形式验证 (Formality / fm_shell)
       │
       ▼
物理实现 (IC Compiler / icc_shell) [可选]
       │
       ▼
最终报告 (面积/时序/功耗)
```

### 7.3 工具对应关系

| 阶段 | Synopsys 工具 | 命令 | 输出物 |
|---|---|---|---|
| RTL 仿真 | VCS | `vcs -sverilog -ntb_opts uvm` | 仿真波形 (FSDB/VPD)、日志 |
| UVM 验证 | VCS + UVM | `+UVM_TESTNAME=fa_xxx_test` | 测试结果、覆盖率数据库 |
| 覆盖率分析 | VCS URG | `urg -dir simv.vdb` | 覆盖率报告 (HTML) |
| 波形调试 | Verdi | `verdi -ssf wave.fsdb` | 交互式波形查看 |
| 逻辑综合 | Design Compiler | `dc_shell -f run_dc.tcl` | 网表、面积/时序/功耗报告 |
| 综合后仿真 | VCS + SDF | `vcs +sdfverbose` | 综合后时序验证 |
| 静态时序分析 | PrimeTime | `pt_shell -f run_pt.tcl` | 时序报告、功耗报告 |
| 形式验证 | Formality | `fm_shell -f run_fm.tcl` | RTL-网表等价性报告 |
| 物理实现 | IC Compiler | `icc_shell -f run_icc.tcl` | GDS、布局布线报告 |

### 7.4 VCS 编译与仿真命令

```bash
# RTL 编译 + UVM
vcs -full64 -sverilog -ntb_opts uvm-1.2 \
    -timescale=1ns/1ps \
    -f filelist.f \
    +incdir+./rtl/include \
    +incdir+./tb/uvm_env \
    -cm line+cond+fsm+tgl+branch \
    -debug_access+all \
    -l compile.log

# 运行测试
./simv +UVM_TESTNAME=fa_random_causal_test \
       +UVM_VERBOSITY=UVM_MEDIUM \
       -cm line+cond+fsm+tgl+branch \
       +fsdbfile+wave.fsdb \
       -l sim.log

# 覆盖率合并与报告
urg -dir simv.vdb -report urgReport
```

### 7.5 Design Compiler 综合脚本要点

```tcl
# run_dc.tcl 关键内容
set target_library "your_target.db"
set link_library   "* $target_library"

read_sverilog -define SYNTHESIS [glob rtl/*.sv]
current_design flash_attention_top

source constraints/flash_attention.sdc

compile_ultra -no_autoungroup
# 或 compile_ultra -gate_clock 用于时钟门控优化

report_area    -hierarchy > reports/area.rpt
report_timing  -max_paths 10 > reports/timing.rpt
report_power   > reports/power.rpt
report_qor     > reports/qor.rpt

write -format verilog -hierarchy -output netlist/fa_top_netlist.v
write_sdc -nosplit netlist/fa_top.sdc
write_sdf netlist/fa_top.sdf
```

### 7.6 约束文件 (SDC)

```tcl
# flash_attention.sdc
create_clock -name clk -period 2.0 [get_ports clk]   ;# 500 MHz 目标
set_clock_uncertainty 0.1 [get_clocks clk]

set_input_delay  0.5 -clock clk [all_inputs]
set_output_delay 0.5 -clock clk [all_outputs]

set_max_area 0   ;# 让工具尽力优化面积
set_max_fanout 32 [current_design]

# AXI 接口约束
set_input_delay  0.3 -clock clk [get_ports s_axi_*]
set_output_delay 0.3 -clock clk [get_ports m_axi_*]
```

---

## 八、项目开发计划与里程碑

### 阶段一：架构设计与算法验证

- 完成 FlashAttention 算法的 Python 参考模型
- 确定定点数方案，验证 exp/倒数近似精度
- 确定 tiling 参数 (B_r, B_c)，完成 cycle/面积预算
- 完成架构文档与模块接口定义
- **交付物**：Python golden model、架构文档、接口规范

### 阶段二：RTL 核心模块开发

- 实现 compute_core（点积阵列 + online softmax + 输出累加器）
- 实现 exp_approx_unit 和 reciprocal_unit
- 实现 causal_mask_unit
- 使用 VCS 编译并运行单元级 SV testbench 验证各子模块
- **交付物**：核心计算模块 RTL + 单元 TB + VCS 仿真日志

### 阶段三：UVM 验证环境搭建 + 接口集成

- 实现 AXI4-Lite Slave 接口 + 寄存器文件
- 实现 AXI4 Master 接口 + DMA 引擎
- 实现 tile_controller 和主 FSM
- 实现 buffer_system（含双缓冲）
- 搭建完整 UVM 验证环境（Agent / Scoreboard / Coverage）
- 顶层集成与系统级 UVM 测试
- **交付物**：完整 RTL + UVM 验证环境

### 阶段四：UVM 验证与调试

- 使用 VCS + UVM 运行所有测试用例（TC01-TC12）
- 修复功能 bug，调优定点精度
- 使用 VCS URG 分析覆盖率（代码覆盖率 + 功能覆盖率 > 95%）
- 补充约束随机测试驱动覆盖率收敛
- **交付物**：UVM 验证报告、URG 覆盖率报告

### 阶段五：综合与优化

- 使用 Design Compiler (dc_shell) 进行逻辑综合
- 使用 PrimeTime (pt_shell) 进行静态时序分析和功耗分析
- 使用 Formality (fm_shell) 进行 RTL-网表形式验证
- 时序优化（关键路径优化、插入流水寄存器）
- 面积优化（资源复用、存储优化）
- 使用 VCS 进行综合后仿真（SDF back-annotation）
- **交付物**：综合报告（面积、时序、功耗）、网表、SDF

### 阶段六：文档与提交

- 撰写设计报告（架构、实现、验证、性能分析）
- 整理代码与脚本
- 准备提交材料
- **交付物**：完整提交包

---

## 九、Bonus 加分项规划

在 Baseline 完成并通过验证后，基于 Baseline 克隆独立版本开发以下加分项：

### 9.1 优先级排序

| 优先级 | 加分项 | 评估 |
|---|---|---|
| **P0** | BF16/FP16 版本 | 技术挑战中等，需实现浮点 exp/倒数硬件；价值高，直接对比展示能力 |
| **P1** | 多 head 支持 | 实用性强，改动主要在地址生成和外循环控制，侵入性低 |
| **P2** | 更长序列 (s=1024) | 验证 FlashAttention 对长序列的可扩展性，改动集中在参数化和存储管理 |
| **P3** | Padding mask | 工程量小，在现有 causal mask 基础上扩展 |
| **P4** | AXI4-Stream 数据接口 | 增加 IP 级联灵活性 |
| **P5** | DMA/任务队列 | 实用性强但工程量较大 |

### 9.2 推荐组合

**方案 A（稳妥）**：BF16/FP16 + 多 head + Padding mask
**方案 B（进取）**：BF16/FP16 + 多 head + 更长序列 + AXI4-Stream

---

## 十、风险分析与应对

| 风险 | 影响 | 应对措施 |
|---|---|---|
| 定点 exp 近似精度不足 | 输出误差超限 | 增加 LUT 深度；使用分段多项式近似；增大中间位宽 |
| 面积超标 | 不满足 ≤200 万门 | 减少并行度（MAC 数量）；使用时间复用；优化 buffer 大小 |
| 时序不收敛 | 主频低 | 增加流水级数；优化关键路径（乘法器后加寄存器）；使用 DC compile_ultra 增量优化 |
| DMA 带宽瓶颈 | 实际周期数超标 | 增大 AXI 数据宽度；优化突发长度；增加 K/V 片上缓存 |
| Causal mask 边界错误 | 功能 bug | 全面的 corner case 测试；形式验证关键属性 |
| 在线 softmax 数值溢出 | 计算错误 | 使用 40-bit+ 累加；分段缩放策略；溢出检测与饱和逻辑 |

---

## 十一、提交材料清单

按赛题要求，最终提交需包含：

```
submission/
├── rtl/                              // RTL 源代码 (SystemVerilog)
│   ├── flash_attention_top.sv        // 顶层模块
│   ├── axi4_lite_slave.sv
│   ├── axi4_master_if.sv
│   ├── dma_engine.sv
│   ├── tile_controller.sv
│   ├── buffer_system.sv
│   ├── compute_core.sv
│   ├── dot_product_array.sv
│   ├── online_softmax_unit.sv
│   ├── exp_approx_unit.sv
│   ├── reciprocal_unit.sv
│   ├── output_accumulator.sv
│   ├── causal_mask_unit.sv
│   └── include/                      // 参数定义头文件
│       └── fa_params.svh
├── tb/                               // UVM 验证代码
│   ├── tb_top/
│   │   └── fa_tb_top.sv              // 顶层 testbench module
│   ├── uvm_env/
│   │   ├── fa_env.sv                 // UVM environment
│   │   ├── fa_env_pkg.sv             // 环境 package
│   │   ├── fa_scoreboard.sv          // Scoreboard + Golden Model
│   │   ├── fa_coverage.sv            // 功能覆盖率收集器
│   │   └── fa_virtual_sequencer.sv   // 虚拟序列器
│   ├── agents/
│   │   ├── axi4_lite_agent/          // AXI4-Lite Master Agent
│   │   │   ├── axi4_lite_txn.sv
│   │   │   ├── axi4_lite_driver.sv
│   │   │   ├── axi4_lite_monitor.sv
│   │   │   ├── axi4_lite_sequencer.sv
│   │   │   └── axi4_lite_agent.sv
│   │   └── axi4_mem_agent/           // AXI4 Slave Memory Agent
│   │       ├── axi4_slave_driver.sv
│   │       ├── axi4_slave_monitor.sv
│   │       ├── memory_model.sv
│   │       └── axi4_mem_agent.sv
│   ├── sequences/
│   │   ├── fa_base_sequence.sv
│   │   ├── fa_config_seq.sv
│   │   ├── fa_random_seq.sv
│   │   └── fa_stress_seq.sv
│   ├── tests/
│   │   ├── fa_base_test.sv
│   │   ├── fa_zero_test.sv
│   │   ├── fa_random_causal_test.sv
│   │   ├── fa_random_nocausal_test.sv
│   │   ├── fa_extreme_test.sv
│   │   ├── fa_reg_access_test.sv
│   │   ├── fa_consecutive_test.sv
│   │   ├── fa_soft_reset_test.sv
│   │   └── fa_random_stress_test.sv
│   └── unit_tb/                      // 单元级 testbench (非 UVM)
│       ├── exp_approx_unit_tb.sv
│       ├── reciprocal_unit_tb.sv
│       ├── dot_product_tb.sv
│       └── online_softmax_tb.sv
├── constraints/                      // 约束文件
│   └── flash_attention.sdc
├── scripts/                          // Synopsys 工具脚本
│   ├── run_vcs.sh                    // VCS 编译 + 仿真脚本
│   ├── run_regression.sh             // 全回归测试脚本
│   ├── run_dc.tcl                    // Design Compiler 综合脚本
│   ├── run_pt.tcl                    // PrimeTime 时序/功耗脚本
│   ├── run_fm.tcl                    // Formality 形式验证脚本
│   └── run_icc.tcl                   // IC Compiler P&R 脚本（可选）
├── filelist.f                        // RTL + TB 文件列表
├── reports/                          // 工具生成报告
│   ├── vcs_sim/                      // VCS 仿真日志
│   ├── urg_coverage/                 // URG 覆盖率报告
│   ├── dc_synthesis/                 // DC 综合报告 (面积/时序/功耗)
│   ├── pt_timing/                    // PT 时序报告
│   └── fm_verify/                    // Formality 验证报告
├── docs/                             // 设计文档
│   └── design_report.pdf
└── bonus/                            // 加分项独立版本
    ├── rtl/
    ├── tb/
    └── reports/
```

---

## 十二、总结

本计划书针对赛题二 FlashAttention 硬件加速器设计，提出了完整的解决方案：

1. **算法层面**：采用 Online Softmax + Tiling 的 FlashAttention 经典范式，在不存储完整注意力矩阵的前提下完成等价 SDPA 计算
2. **架构层面**：模块化设计，计算核心（点积阵列 + softmax + 累加器）+ DMA 引擎 + AXI 接口，支持双缓冲流水线
3. **性能层面**：预估约 210k cycles 完成单次 attention，满足 < 300k 要求；面积约 115 万门，满足 ≤ 200 万门约束
4. **验证层面**：采用 SystemVerilog + UVM 方法学进行三级验证（单元/模块/系统），包含完整的 Agent、Scoreboard、Coverage 架构，12 项测试用例覆盖功能正确性、精度验收、边界条件、错误注入
5. **工具链**：使用 Synopsys 2016 全套工具链 — VCS（仿真）、Design Compiler（综合）、PrimeTime（时序/功耗分析）、Formality（形式验证）、IC Compiler（物理实现）
