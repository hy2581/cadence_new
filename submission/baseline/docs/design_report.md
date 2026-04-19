# FlashAttention 高性能硬件加速器 IP — 设计报告

## 1. 设计概述

本设计实现了一个可综合的 FlashAttention-style 注意力算子硬件 IP，完成 Scaled Dot-Product Attention (SDPA) 计算，在不显式存储完整注意力矩阵的前提下完成端到端注意力计算。

### 1.1 设计参数

| 参数 | 值 |
|---|---|
| 序列长度 s | 256 |
| Head 维度 d | 64 |
| 数据格式 | Q8.8 (16-bit 有符号定点) |
| 累加器位宽 | 40-bit |
| Tiling: B_r × B_c | 4 × 16 |
| AXI 数据宽度 | 128-bit |

## 2. 架构设计

### 2.1 顶层架构

```
flash_attention_top
├── axi4_lite_slave        (控制接口 + 寄存器文件)
├── tile_controller        (Tiling 循环控制 + 地址生成)
├── dma_engine             (DMA 读写引擎)
│   └── axi4_master_if     (AXI4 Master 接口)
├── buffer_system          (Q/K/V/O 片上缓存, K/V 双缓冲)
└── compute_core           (计算核心)
    ├── dot_product_array   (点积阵列)
    ├── online_softmax_unit (在线 softmax)
    │   └── exp_approx_unit (定点 exp 近似, 1024-entry LUT)
    ├── output_accumulator  (输出累加器)
    └── causal_mask_unit    (Causal mask 生成)
```

### 2.2 FlashAttention 算法实现

采用 Online Softmax + Tiling 范式：
- 外循环遍历 64 个 Q-tiles (每 4 行)
- 内循环遍历 16 个 KV-tiles (每 16 行)
- 每次迭代：dot_product → causal_mask → online_softmax → output_accumulate
- 维护 running max (m) 和 running sum (l) 实现在线 softmax
- 不存储 256×256 的完整注意力矩阵

### 2.3 Exp 近似

采用 1024-entry 直接 LUT：
- 覆盖范围: x ∈ [-16.0, +4.0]
- 分辨率: 20/1024 ≈ 0.0195
- 3 级流水线: index计算 → LUT读取 → 输出
- 最大相对误差: 1.56%

## 3. 接口设计

### 3.1 AXI4-Lite 寄存器映射

完全按照赛题 TABLE 2 实现：CTRL(0x00), STATUS(0x04), CFG(0x08), Q/K/V/O_BASE(0x14-0x30), STRIDE(0x34), NEG_LARGE(0x38), SCALE(0x3C), CYCLES(0x40)

### 3.2 AXI4 Master DMA

- 突发读: 加载 Q/K/V tiles 从外存到片上 buffer
- 突发写: 将 O tiles 从片上 buffer 写回外存
- 数据宽度: 128-bit (每拍 8 个 Q8.8 值)

## 4. 性能结果

### 4.1 VCS 仿真结果 (端到端)

| 指标 | 结果 | 要求 |
|---|---|---|
| **执行周期** | **276,100 cycles** | < 300,000 |
| **mean_abs_error** | **0.013350** | < 门限 |
| **max_abs_error** | **0.238281** | < 1.0 |

### 4.2 带宽分析

| 操作 | 数据量 | 说明 |
|---|---|---|
| 读 Q | 32 KB | 64 tiles × 512 B/tile |
| 读 K | 2,048 KB | 64×16 tiles × 2048 B/tile |
| 读 V | 2,048 KB | 同 K |
| 写 O | 32 KB | 64 tiles × 512 B/tile |
| **总计** | **4.06 MB** | |

带宽效率 (@ 500MHz, 276k cycles):
- 读带宽: 7,655 MB/s
- 写带宽: 59 MB/s

### 4.3 片上存储

| Buffer | 大小 | 说明 |
|---|---|---|
| Q buffer | 512 B | B_r × d × 2 |
| K buffer ×2 | 2×2 KB | 双缓冲, B_c × d × 2 |
| V buffer ×2 | 2×2 KB | 双缓冲, B_c × d × 2 |
| O accumulator | 1.25 KB | B_r × d × 40-bit |
| **总计** | **~8.75 KB** | 远低于 200万门约束 |

## 5. 验证结果

### 5.1 单元测试 (VCS)

| 模块 | 测试数 | 结果 |
|---|---|---|
| causal_mask_unit | 6 | 6/6 PASS |
| axi4_lite_slave | 14 | 14/14 PASS |
| exp_approx_unit | 10 | 10/10 PASS (max err 1.56%) |
| dot_product_array | 2 | 2/2 PASS |

### 5.2 系统级端到端测试

- 完整 256×64 attention (causal=1)
- 随机 Q/K/V 输入 (Q8.8 范围 ±64)
- Golden model: FP64 精度 SDPA
- DMA 读写全流程: 外存 → 计算 → 外存
- **结果: PASS (276k cycles, mean_err=0.013, max_err=0.24)**

## 6. 工具链

| 工具 | 版本 | 用途 |
|---|---|---|
| VCS | L-2016.06 | RTL 仿真 + 验证 |
| Design Compiler | L-2016.03-SP1 | 逻辑综合 (需适配) |
| SDC | — | 时序约束 (500MHz 目标) |

## 7. 文件清单

```
rtl/                           13 个 SystemVerilog 模块
  include/fa_params.svh        全局参数
  flash_attention_top.sv       顶层
  compute_core.sv              计算核心 FSM
  dot_product_array.sv         点积阵列
  online_softmax_unit.sv       在线 softmax
  exp_approx_unit.sv           exp 近似
  exp_lut_rom.sv               exp LUT ROM
  output_accumulator.sv        输出累加
  causal_mask_unit.sv          causal mask
  buffer_system.sv             片上 buffer
  tile_controller.sv           tiling 控制
  axi4_lite_slave.sv           AXI4-Lite 接口
  axi4_master_if.sv            AXI4 Master 接口
  dma_engine.sv                DMA 引擎
  reciprocal_unit.sv           倒数近似
tb/                            测试验证
  unit_tb/                     单元 + 系统测试
  agents/                      UVM Agent
  uvm_env/                     UVM 环境
  sequences/                   UVM Sequences
  tests/                       UVM Tests
scripts/                       工具脚本
constraints/                   SDC 约束
```
