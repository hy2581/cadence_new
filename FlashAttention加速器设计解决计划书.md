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
| 主频 | 尽可能高（Cadence Genus 综合报告） |
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

## 六、验证方案

### 6.1 验证框架选择

推荐采用 **Python + cocotb** 方案，原因：
- 开发效率高，Python 生态可直接调用 NumPy 生成 golden 数据
- cocotb 对 AXI 协议有成熟的验证 IP (cocotb-bus)
- 方便进行大量随机测试

备选方案：SystemVerilog + UVM（更贴近工业标准，适合有 UVM 经验的团队）。

### 6.2 验证层次

```
Level 0: 单元级验证
├── exp_approx_unit_tb      // exp 近似精度验证
├── reciprocal_unit_tb      // 倒数精度验证
├── dot_product_tb          // 点积功能验证
└── online_softmax_tb       // softmax 单行验证

Level 1: 模块级验证
├── compute_core_tb         // 完整计算核心（无 DMA）
├── dma_engine_tb           // DMA 读写功能验证
└── axi4_lite_reg_tb        // 寄存器读写验证

Level 2: 系统级验证
├── top_basic_tb            // 端到端基础功能
├── top_causal_tb           // Causal mask 端到端
├── top_random_tb           // 随机输入端到端
└── top_corner_tb           // 边界条件测试
```

### 6.3 Golden Model

使用 Python/NumPy 实现 FP32 精度的参考模型：

```python
def flash_attention_golden(Q, K, V, causal=True):
    """FP32 golden reference"""
    s, d = Q.shape
    scale = 1.0 / math.sqrt(d)
    S = Q @ K.T * scale
    if causal:
        mask = np.triu(np.ones((s, s), dtype=bool), k=1)
        S[mask] = -1e9
    P = softmax(S, axis=-1)
    O = P @ V
    return O
```

### 6.4 正确性验收标准

- **mean_abs_error** < 赛题规定门限（与 FP32 golden 对比）
- **max_abs_error** < 赛题规定门限
- 需在报告中分析误差来源（定点量化误差 + exp 近似误差 + 倒数近似误差）

### 6.5 测试用例清单

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
| TC11 | 批量随机 (×100) | 100 组随机数据，统计误差分布 |

---

## 七、Cadence EDA 工具使用计划

### 7.1 设计流程

```
RTL 设计 (Verilog/SystemVerilog)
       │
       ▼
功能仿真 (Xcelium)
       │
       ▼
代码质量检查 (Jasper/HAL)
       │
       ▼
RTL 功耗预估 (Joules RTL Design Studio)
       │
       ▼
逻辑综合 (Genus)
       │
       ▼
综合后仿真 (Xcelium + SDF)
       │
       ▼
物理实现 (Innovus) [可选，加分]
       │
       ▼
物理综合报告 (面积/时序/功耗)
```

### 7.2 工具对应关系

| 阶段 | Cadence 工具 | 输出物 |
|---|---|---|
| RTL 仿真 | Xcelium | 仿真波形、覆盖率报告 |
| RTL 功耗分析 | Joules RTL Design Studio | 等效逻辑门数、功耗报告 |
| 逻辑综合 | Genus | 网表、时序报告、面积报告 |
| 物理综合 | Genus (Physical Synthesis) | 物理感知网表 |
| 布局布线 | Innovus | GDS、时序收敛报告 |
| 形式验证 | Conformal | RTL-网表等价性 |

### 7.3 约束文件 (SDC)

需要准备的关键约束：
- 时钟定义（目标频率 500MHz+）
- 输入/输出延迟约束
- AXI 接口时序约束
- 面积约束（max area）
- 功耗约束

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
- 单元级 testbench 验证各子模块
- **交付物**：核心计算模块 RTL + 单元 TB

### 阶段三：接口与系统集成

- 实现 AXI4-Lite Slave 接口 + 寄存器文件
- 实现 AXI4 Master 接口 + DMA 引擎
- 实现 tile_controller 和主 FSM
- 实现 buffer_system（含双缓冲）
- 顶层集成与系统级 testbench
- **交付物**：完整 RTL + 系统 TB

### 阶段四：验证与调试

- 完成所有测试用例（TC01-TC11）
- 修复功能 bug，调优精度
- 完成覆盖率分析（行/分支/状态机覆盖率 > 95%）
- **交付物**：验证报告、覆盖率报告

### 阶段五：综合与优化

- 使用 Genus 进行逻辑综合
- 使用 Joules 进行 RTL 功耗/面积分析
- 时序优化（关键路径优化）
- 面积优化（资源复用、存储优化）
- **交付物**：综合报告（面积、时序、功耗）

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
| 时序不收敛 | 主频低 | 增加流水级数；优化关键路径（乘法器后加寄存器）；使用 Genus 增量优化 |
| DMA 带宽瓶颈 | 实际周期数超标 | 增大 AXI 数据宽度；优化突发长度；增加 K/V 片上缓存 |
| Causal mask 边界错误 | 功能 bug | 全面的 corner case 测试；形式验证关键属性 |
| 在线 softmax 数值溢出 | 计算错误 | 使用 40-bit+ 累加；分段缩放策略；溢出检测与饱和逻辑 |

---

## 十一、提交材料清单

按赛题要求，最终提交需包含：

```
submission/
├── rtl/                          // RTL 源代码
│   ├── flash_attention_top.sv    // 顶层模块
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
│   └── include/                  // 参数定义头文件
│       └── fa_params.svh
├── tb/                           // 验证代码
│   ├── cocotb/                   // cocotb 验证环境
│   │   ├── test_basic.py
│   │   ├── test_causal.py
│   │   ├── test_random.py
│   │   ├── test_corner.py
│   │   ├── test_axi_reg.py
│   │   ├── golden_model.py
│   │   └── axi_driver.py
│   └── Makefile
├── constraints/                  // 约束文件
│   └── flash_attention.sdc
├── scripts/                      // Cadence 工具脚本
│   ├── run_sim.tcl               // Xcelium 仿真脚本
│   ├── run_genus.tcl             // Genus 综合脚本
│   ├── run_joules.tcl            // Joules 功耗分析脚本
│   └── run_innovus.tcl           // Innovus P&R 脚本（可选）
├── reports/                      // 工具生成报告
│   ├── sim_report/
│   ├── synthesis_report/
│   └── power_report/
├── docs/                         // 设计文档
│   └── design_report.pdf
└── bonus/                        // 加分项独立版本
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
4. **验证层面**：采用 cocotb 框架进行多层次验证，覆盖功能正确性、精度验收、边界条件
5. **工具链**：充分利用 Cadence Xcelium/Genus/Joules 工具完成仿真、综合和功耗分析
