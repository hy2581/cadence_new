# FlashAttention 硬件加速器 — RTL 伪代码详解

> 本文档是 FlashAttention 硬件加速器全部 15 个 RTL 模块的中文伪代码注释版。每个模块包含功能说明、接口定义、状态机逻辑和设计要点。

---

## 模块架构总览

```
flash_attention_top (顶层互连)
├── axi4_lite_slave       ← 主机通过 AXI4-Lite 配置寄存器
├── tile_controller       ← 控制 Q/KV 分块循环和 DMA 调度
├── dma_engine            ← DMA 读写引擎
│   └── axi4_master_if    ← AXI4 主机总线接口
├── buffer_system         ← Q/K/V/O 片上缓存（K/V 双缓冲）
└── compute_core          ← 计算核心
    ├── dot_product_array  ← 点积阵列：S = Q · K^T × scale
    ├── causal_mask_unit   ← 因果掩码：j > i 的位置填 -inf
    ├── online_softmax_unit ← 在线 Softmax（不存储完整注意力矩阵）
    │   └── exp_approx_unit ← 定点 exp 近似（1024 项 LUT）
    │       └── exp_lut_rom  ← exp 查找表 ROM
    ├── output_accumulator  ← 输出累加器：O += P · V，最后归一化
    └── reciprocal_unit     ← 倒数近似（Newton-Raphson）
```

---

## 1. 闪光注意力顶层 (`flash_attention_top.sv`)

### 功能
**顶层互连模块**，不包含算法逻辑。将 5 个主要子模块（AXI4-Lite 从机、分块控制器、DMA 引擎、缓冲系统、计算核心）连接起来。

### 数据流

```
主机 ──AXI4-Lite──→ [寄存器组] ──配置──→ 分块控制器
                                         ↓
片外内存 ←──AXI4 Master──← [DMA引擎] ←──地址/控制
                              ↓ 数据
                          [缓冲系统] ←→ [计算核心]
                              ↓ O结果
片外内存 ←──AXI4 Master──← [DMA引擎] ←──O回写
```

### 关键信号
- **reg_start**: 寄存器写 CTRL[0]=1 时产生单周期脉冲，启动整个计算流程
- **tc_all_done**: 分块控制器完成所有 Q-tile × KV-tile 迭代后拉高
- **cycle_cnt**: 从 START 到 DONE 的周期计数器

### 设计要点
> 顶层只做信号互连和简单组合赋值。所有算法逻辑在计算核心及其子模块中完成。

---

## 2. AXI4-Lite 从机 (`axi4_lite_slave.sv`)

### 功能
实现 AXI4-Lite 从机接口 + 控制/状态寄存器组。主机通过该接口配置基地址、启动计算、读取状态。

### 寄存器映射

| 偏移 | 名称 | 读/写 | 说明 |
|------|------|-------|------|
| 0x00 | CTRL | R/W | bit0=START(脉冲), bit1=SOFT_RESET, bit2=IRQ_EN |
| 0x04 | STATUS | R | bit0=BUSY, bit1=DONE(粘滞), bit2=ERROR |
| 0x08 | CFG | R/W | bit0=CAUSAL_EN |
| 0x14-0x30 | 基地址 | R/W | Q/K/V/O 的 64 位基地址（分高低 32 位） |
| 0x34 | STRIDE | R/W | 行步长（字节），默认 d×2 |
| 0x38 | NEG_LARGE | R/W | 负大值（Q8.8 格式的 -inf 近似） |
| 0x3C | SCALE | R/W | 缩放因子（1/√d 的 Q8.8 表示） |
| 0x40 | CYCLES | R | 本次执行的周期数 |

### 关键机制
- **START 脉冲**: 写 CTRL[0]=1 时，`reg_start` 产生**单周期脉冲**（非电平），防止重复启动
- **DONE 粘滞位**: `status_done` 输入为高时锁存 `r_done_sticky=1`，直到软件写 STATUS[1]=1 清除
- **中断**: IRQ = CTRL[2] AND r_done_sticky

---

## 3. 分块控制器 (`tile_controller.sv`)

### 功能
管理 FlashAttention 的**双层 tiling 循环**：外层遍历 Q-tiles，内层遍历 KV-tiles。为每个 tile 生成 DMA 地址并控制计算核心。

### 状态机流程

```
空闲 → 加载Q → 等Q → 加载K → 等K → 加载V → 等V → 计算 → 等计算 
→ 下一KV(循环) → 写回O → 等O → 下一Q(循环) → 全部完成 → 空闲
```

### 地址计算
```
Q 地址 = Q_BASE + q_idx × stride × TILE_BR
K 地址 = K_BASE + kv_idx × stride × TILE_BC
V 地址 = V_BASE + kv_idx × stride × TILE_BC
O 地址 = O_BASE + q_idx × stride × TILE_BR
```

### 关键信号
- **compute_first_kv**: 当 `kv_idx == 0` 时为真，告诉 Softmax 初始化 m/l
- **compute_last_kv**: 当 `kv_idx == NUM_KV_TILES-1` 时为真，告诉累加器做最终归一化
- **kv_buf_sel**: 乒乓缓冲选择，每完成一个 KV-tile 翻转一次

---

## 4. DMA 引擎 (`dma_engine.sv`)

### 功能
桥接分块控制器的读/写请求与 AXI4 主机接口。读路径将外存数据按目标（Q/K/V）写入对应缓冲；写路径从 O 缓冲读出写回外存。

### 读路径
```
DMA读请求 → AXI4读请求 → 收到数据 → 按目标(0=Q,1=K,2=V)写入缓冲
```
- 锁存读目标，按 AXI 突发逐拍写入对应缓冲的地址

### 写路径（O 回写）
```
DMA写请求 → 发AXI写地址 → 预读O缓冲 → 逐拍发送写数据 → 等写响应
```
- O 缓冲按 `(行, 列组)` 二维索引读出，打包成 AXI 数据宽度

---

## 5. AXI4 主机接口 (`axi4_master_if.sv`)

### 功能
将 DMA 的简单请求（地址 + 字节长度）转换为标准 AXI4 INCR 突发事务。

### 读通道状态机
```
空闲 → 发地址(AR) → 接收数据(R) → 完成
```
- 计算突发节拍数 = ceil(字节长度 / 每拍字节数)
- 逐拍接收 R 通道数据直到 RLAST

### 写通道状态机
```
空闲 → 发地址(AW) → 发送数据(W) → 等响应(B) → 完成
```
- 最后一拍设置 WLAST
- 等待 B 通道响应确认

---

## 6. 缓冲系统 (`buffer_system.sv`)

### 功能
片上 SRAM 存储，为 DMA 和计算核心提供数据缓冲。

### 存储布局

| 缓冲 | 大小 | 说明 |
|------|------|------|
| Q | TILE_BR × d | 单缓冲，DMA 写 / 计算核心读 |
| K × 2 | TILE_BC × d × 2 | **乒乓双缓冲**，一侧 DMA 写 / 另一侧计算读 |
| V × 2 | TILE_BC × d × 2 | 同 K |
| O | TILE_BR × d | 计算核心写 / DMA 读 |

### 设计要点
> **乒乓缓冲**是 FlashAttention 硬件实现的关键优化——DMA 加载下一个 KV-tile 的同时，计算核心处理当前 KV-tile，实现数据传输与计算的重叠。

---

## 7. 计算核心 (`compute_core.sv`)

### 功能
编排一个 (Q-tile, KV-tile) 对的完整计算流水线：
```
点积 → 掩码 → 在线Softmax → 累加
```

### 状态机
```
空闲 → 点积计算 → 掩码处理 → Softmax → 累加 → 完成
```

### 跨 KV-tile 持久状态
- `m_old[r]`: 每行的 running max（初始为负无穷）
- `l_old[r]`: 每行的 running sum（初始为 0）
- 每完成一个 KV-tile 的 Softmax 后更新

### 掩码处理
```
绝对行 = Q分块索引 × TILE_BR + 行
绝对列 = KV分块索引 × TILE_BC + 列
若 causal_en 且 绝对列 > 绝对行:
    masked_score = NEG_LARGE  // 禁止看到未来 token
```

---

## 8. 点积阵列 (`dot_product_array.sv`)

### 功能
计算 `S = Q · K^T × scale`，得到 TILE_BR × TILE_BC 的分数矩阵。

### 计算方式
- 数据分 `HEAD_DIM / PAR_MACS` 步流入
- 每步每行并行处理 `PAR_MACS` 个乘累加
- 最后统一乘缩放因子并右移对齐

```
对每步 step:
  对每行 r, 每列 c:
    acc[r][c] += Σ(Q[r][step*PAR+p] × K[c][step*PAR+p])  // p=0..PAR-1
最后: score[r][c] = (acc[r][c] × scale) >>> 8
```

---

## 9. 因果掩码单元 (`causal_mask_unit.sv`)

### 功能
纯组合逻辑，判断每个 (行, 列) 位置是否应被掩码（因果注意力要求 token 只能看到自己及之前的 token）。

```
若 causal_en 且 (KV分块索引×TILE_BC + 列) > (Q分块索引×TILE_BR + 行):
    mask = true  // 该位置填 NEG_LARGE
```

---

## 10. 在线 Softmax 单元 (`online_softmax_unit.sv`)

### 功能
FlashAttention 的**核心创新**——不存储完整的 S 矩阵，而是逐 KV-tile 在线更新 Softmax 的 max 和 sum。

### 算法步骤

```
1. 求行最大值: m_new[r] = max(m_old[r], max_j(S[r][j]))
2. 计算 exp:   P[r][j] = exp(S[r][j] - m_new[r])     ← 3级流水线
3. 求行和:     l_new[r] = l_old[r] + Σ_j P[r][j]
4. 缩放修正:   rescale[r] = l_old[r]                   ← 用于累加器修正旧 O
```

### Exp 流水线时分复用
- 单个 exp_approx_unit 实例
- 逐元素输入，3 拍延迟后收集输出
- 输入侧和输出侧用独立行/列指针追踪

---

## 11. 指数近似单元 (`exp_approx_unit.sv`)

### 功能
3 级流水线定点 exp(x) 近似，使用 1024 项 LUT。

### 流水线

| 级 | 操作 |
|----|------|
| 1 | 将输入 x 映射到 LUT 索引（x 范围 [-16, +4]），处理上/下限截断 |
| 2 | ROM 查表读取 |
| 3 | 输出选择：下限截断→0，上限截断→最大值，其它→查表值 |

### 索引计算
```
index = (x + 16) / (20/1024)  ≈  (x + 16) × 51.2
RTL 近似: index = (x_plus_16) / 5
```

---

## 12. 指数查找表 ROM (`exp_lut_rom.sv`)

### 功能
1024 项只读查找表，存储 exp(x) 的定点值。

- **仿真模式**: 用 `$readmemh` 从 hex 文件加载，或用 initial 块数学计算
- **综合模式**: 用分段常数/线性近似替代大 ROM（减少面积）

```
对 i=0..1023:
  x = -16.0 + i × (20.0/1024)
  LUT[i] = min(饱和上限, round(exp(x) × 2^FRAC_OUT))
```

---

## 13. 倒数近似单元 (`reciprocal_unit.sv`)

### 功能
4 级流水线计算 1/x（Newton-Raphson 方法）。

### 流水线

| 级 | 操作 |
|----|------|
| 1 | 归一化：找前导零数，将 x 左移到 [0.5, 1.0) |
| 2 | LUT 初始猜测：256 项表查 1/x_normalized |
| 3 | Newton 迭代 1：x1 = x0 × (2 - d × x0) |
| 4 | Newton 迭代 2：x2 = x1 × (2 - d × x1) |

> 两次 Newton 迭代后精度约 16 位有效位。

---

## 14. 输出累加器 (`output_accumulator.sv`)

### 功能
跨 KV-tile 累加 O = P · V，最后归一化输出。

### 状态机

| 状态 | 操作 |
|------|------|
| **缩放旧值** | O_acc[r][j] = O_acc[r][j] × rescale[r] / 2^FRAC（非首个 tile） |
| **PV 乘累加** | O_acc[r][j] += Σ_c P[r][c] × V[c][j]（逐步并行） |
| **归一化** | O_out[r][j] = O_acc[r][j] / l_new[r]（仅最后一个 KV-tile） |

### 关键：O 有效信号
> `o_valid` **只在最后一个 KV-tile 处理完成后才拉高**，因为在此之前 O 的值还需要被后续 KV-tile 修正。

---

## 15. 参数头文件 (`fa_params.svh`)

### 核心参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| SEQ_LEN | 256 | 序列长度 |
| HEAD_DIM | 64 | 注意力头维度 |
| TILE_BR | 4 | Q 分块行数 |
| TILE_BC | 16 | KV 分块行数 |
| DATA_WIDTH | 16 | Q8.8 定点位宽 |
| ACC_WIDTH | 40 | 累加器位宽 |
| PAR_MACS | 8 | 每周期并行乘累加数 |
| AXI_DATA_WIDTH | 128 | AXI 数据总线宽度 |

---

## 算法流程总结

```
输入: Q[256×64], K[256×64], V[256×64] (Q8.8 定点)
输出: O[256×64] (Q8.8 定点)

for q_tile in 0..63:            // 64 个 Q-tile，每个 4 行
    DMA 加载 Q[q_tile*4 : (q_tile+1)*4]
    初始化 m = -inf, l = 0, O_acc = 0
    
    for kv_tile in 0..15:       // 16 个 KV-tile，每个 16 行
        DMA 加载 K[kv_tile*16 : (kv_tile+1)*16]  → 乒乓缓冲
        DMA 加载 V[kv_tile*16 : (kv_tile+1)*16]  → 乒乓缓冲
        
        // 计算核心流水线
        S = Q_tile · K_tile^T × scale           // 点积阵列
        S = apply_causal_mask(S)                 // 因果掩码
        P, m_new, l_new = online_softmax(S, m, l) // 在线 Softmax
        O_acc = rescale(O_acc, l, l_new) + P · V  // 输出累加
        m = m_new; l = l_new
    
    O = normalize(O_acc, l)     // 最终归一化
    DMA 写回 O[q_tile*4 : (q_tile+1)*4]
```

**总周期数**: ~276,000 cycles @ 500MHz ≈ 0.55ms（< 300k cycles 要求）
