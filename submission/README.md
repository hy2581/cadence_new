# FlashAttention 高性能硬件加速器 IP — 提交包

## 项目简介

本项目实现了一个**可综合的 FlashAttention-style 注意力算子硬件加速器 IP**，完成 Scaled Dot-Product Attention (SDPA) 计算。采用 Online Softmax + Tiling 范式，在不存储完整 256×256 注意力矩阵的前提下完成端到端注意力计算。

### 核心设计参数

| 参数 | 值 |
|------|-----|
| 序列长度 s | 256 |
| Head 维度 d | 64 |
| 数据格式 | Q8.8 (16-bit 有符号定点) |
| 累加器位宽 | 40-bit |
| Tiling: B_r × B_c | 4 × 16 |
| AXI 数据宽度 | 128-bit |
| 片上存储 | ~8.75 KB |

## 目录结构

```
submission/
├── README.md                          本文件 — 项目总说明
├── file_guide.md                      全部文件详细介绍
├── docker_run_all.sh                  Baseline Docker 一键运行脚本
├── docker_run_all_bonus.sh            Bonus Docker 一键运行脚本
├── vcs_fopen_fix.c                    VCS 新内核兼容性修复 (LD_PRELOAD)
├── vc_hdrs.h                          VCS DPI 头文件
│
├── baseline/                          ====== Baseline 版本（必选项）======
│   ├── rtl/                           14 个 RTL 模块 + 参数头文件
│   │   ├── include/
│   │   │   ├── fa_params.svh          全局参数定义
│   │   │   └── exp_lut.hex            exp LUT 初始化数据 (1024 entries)
│   │   ├── flash_attention_top.sv     顶层模块
│   │   ├── tile_controller.sv         Tiling 循环控制 + 地址生成
│   │   ├── compute_core.sv            计算核心 FSM
│   │   ├── dot_product_array.sv       点积阵列
│   │   ├── online_softmax_unit.sv     在线 softmax
│   │   ├── exp_approx_unit.sv         exp 近似 (LUT)
│   │   ├── exp_lut_rom.sv             exp LUT ROM (可综合)
│   │   ├── reciprocal_unit.sv         倒数近似 (Newton-Raphson)
│   │   ├── output_accumulator.sv      输出累加 + 归一化
│   │   ├── causal_mask_unit.sv        Causal mask 生成
│   │   ├── buffer_system.sv           片上缓存 (K/V 双缓冲)
│   │   ├── dma_engine.sv              DMA 读写引擎
│   │   ├── axi4_lite_slave.sv         AXI4-Lite 控制接口 + 寄存器文件
│   │   └── axi4_master_if.sv          AXI4 Master 数据接口
│   │
│   ├── tb/                            完整验证环境
│   │   ├── unit_tb/                   直接测试
│   │   │   ├── system_tb.sv           系统端到端测试平台
│   │   │   └── axi4_slave_mem.sv      AXI4 从端内存模型
│   │   ├── agents/                    UVM Agents + SVA 协议检查器
│   │   │   ├── axi4_lite_agent/       AXI4-Lite Master Agent (VIP)
│   │   │   │   ├── axi4_lite_txn.sv        事务对象
│   │   │   │   ├── axi4_lite_driver.sv     驱动器
│   │   │   │   ├── axi4_lite_monitor.sv    监控器
│   │   │   │   ├── axi4_lite_sequencer.sv  序列器
│   │   │   │   ├── axi4_lite_agent.sv      Agent 顶层
│   │   │   │   └── axi4_lite_if.sv         接口定义
│   │   │   ├── axi4_mem_agent/        AXI4 Memory Agent (VIP + Monitor)
│   │   │   │   ├── axi4_mem_agent.sv       Agent + Slave Responder
│   │   │   │   └── axi4_mem_if.sv          接口定义
│   │   │   ├── axi4_protocol_checker.sv      AXI4 SVA 协议检查器 (21 条断言)
│   │   │   └── axi4_lite_protocol_checker.sv AXI4-Lite SVA 协议检查器 (18 条断言)
│   │   ├── uvm_env/                   UVM 环境
│   │   │   ├── fa_env_pkg.sv          环境包 (统一 include)
│   │   │   ├── fa_env.sv              顶层 env (Agent + Scoreboard + Coverage)
│   │   │   ├── fa_scoreboard.sv       记分板 (Golden Model 对比)
│   │   │   ├── fa_coverage.sv         覆盖率收集 (10 个 covergroup)
│   │   │   └── fa_reg_model.sv        UVM RAL 寄存器模型 (15 个寄存器)
│   │   ├── sequences/                 UVM Sequences
│   │   │   └── fa_sequences.sv        8 个序列定义
│   │   ├── tests/                     UVM Tests
│   │   │   └── fa_tests.sv            24 个测试用例
│   │   └── tb_top/                    UVM TB 顶层
│   │       └── fa_tb_top.sv           TB 顶层 (协议检查器始终启用)
│   │
│   ├── constraints/                   SDC 约束
│   │   └── flash_attention.sdc        时序约束 (500MHz 目标)
│   │
│   └── docs/                          设计文档
│       ├── design_report.md           设计报告
│       └── verification_report.md     验证报告 (含完整仿真结果)
│
├── bonus/                             ====== Bonus 版本（9 项加分功能）======
│   ├── filelist_bonus.f               VCS 文件列表
│   ├── rtl/                           11 个增强 RTL 模块
│   │   ├── include/
│   │   │   └── fa_params_bonus.svh    Bonus 参数 (多头/可变序列/多格式)
│   │   ├── flash_attention_bonus_top.sv  Bonus 顶层 (集成全部 9 项功能)
│   │   ├── tile_controller_bonus.sv      增强 Tiling 控制器 (多头/可变序列)
│   │   ├── compute_core_bonus.sv         增强计算核心 (多格式支持)
│   │   ├── axi4_lite_slave_bonus.sv      增强寄存器文件 (22 个寄存器)
│   │   ├── bf16_exp_unit.sv              BF16 格式 exp 计算
│   │   ├── bf16_reciprocal_unit.sv       BF16 格式倒数计算
│   │   ├── int8_quantizer.sv             INT8 块量化器
│   │   ├── mask_unit.sv                  通用 Mask 单元 (Causal + Padding)
│   │   ├── dropout_unit.sv               Dropout 单元 (LFSR 伪随机)
│   │   ├── task_queue.sv                 DMA Task Queue (4 深度)
│   │   └── axi4_stream_if.sv            AXI4-Stream 接口
│   │
│   ├── tb/                            Bonus 验证环境
│   │   ├── bonus_system_tb.sv         Bonus 系统测试 (19 项测试)
│   │   ├── tb_top/
│   │   │   └── fa_bonus_tb_top.sv     Bonus UVM TB 顶层
│   │   ├── uvm_env/
│   │   │   ├── fa_bonus_env_pkg.sv    Bonus 环境包
│   │   │   ├── fa_bonus_env.sv        Bonus UVM 环境
│   │   │   ├── fa_bonus_scoreboard.sv Bonus 记分板
│   │   │   └── fa_bonus_coverage.sv   Bonus 覆盖率
│   │   ├── sequences/
│   │   │   └── fa_bonus_sequences.sv  Bonus UVM 序列
│   │   └── tests/
│   │       └── fa_bonus_tests.sv      Bonus 24 个 UVM 测试
│   │
│   └── constraints/
│       └── flash_attention.sdc        Bonus SDC 约束
│
└── scripts/                           ====== 运行脚本 ======
    ├── run_baseline.sh                Baseline 直接仿真
    ├── run_uvm_all.sh                 完整 UVM 验证套件 (24 测试 + 覆盖率合并)
    ├── run_bonus.sh                   Bonus 直接 TB (19 测试)
    ├── run_bonus_uvm.sh               Bonus UVM 测试
    ├── run_synthesis.sh               DC 逻辑综合 (TSMC 12nm)
    └── run_postsim.sh                 后综合门级仿真
```

## 环境要求

| 工具 | 版本 | 用途 |
|------|------|------|
| **VCS** | Synopsys VCS L-2016.06+ | RTL 仿真 + UVM 验证 |
| **UVM** | VCS 内置 UVM-1.2 | 验证方法学 |
| **DC** | Design Compiler L-2016.03-SP1 | 逻辑综合 (可选) |
| **OS** | Linux (Ubuntu 18.04/20.04/22.04) | 运行环境 |

## 快速复现

### 1. 配置环境

```bash
export VCS_HOME=/usr/synopsys/vcs-mx/O-2018.09-SP2
export PATH=$VCS_HOME/bin:$PATH
```

### 2. 运行 Baseline 仿真

```bash
cd submission
bash scripts/run_baseline.sh
```

**预期结果**:
```
Cycles:         276100    PASS (< 300k)
mean_abs_error: 0.013350  PASS
max_abs_error:  0.238281  PASS
>>> ALL TESTS PASSED <<<
```

### 3. 运行完整 UVM 验证套件（24 项测试）

```bash
bash scripts/run_uvm_all.sh
```

也可运行单个测试：

```bash
bash scripts/run_uvm_all.sh fa_axi_protocol_test
```

### 4. 运行 Bonus 测试

```bash
bash scripts/run_bonus.sh              # 直接 TB (19 项)
bash scripts/run_bonus_uvm.sh fa_bonus_causal_test  # UVM 单项
```

### 5. Docker 一键运行

```bash
# Baseline 完整验证
docker exec -it synopsys_vcs bash
cd /work/cadence/submission
bash docker_run_all.sh

# Bonus 完整验证
bash docker_run_all_bonus.sh
```

### 6. 逻辑综合（可选）

```bash
bash scripts/run_synthesis.sh       # DC 综合 (TSMC 12nm)
bash scripts/run_postsim.sh         # 后综合门级仿真
```

## 架构概览

```
flash_attention_top
├── axi4_lite_slave          控制接口 + 15 个寄存器
├── tile_controller          Tiling 循环控制 + 地址生成
├── dma_engine               DMA 读写引擎
│   └── axi4_master_if       AXI4 Master 接口
├── buffer_system            Q/K/V/O 片上缓存 (K/V 双缓冲)
└── compute_core             计算核心
    ├── dot_product_array     点积阵列 (8 路并行 MAC)
    ├── online_softmax_unit   在线 softmax
    │   └── exp_approx_unit   定点 exp 近似 (1024-entry LUT)
    ├── reciprocal_unit       倒数近似 (Newton-Raphson, 4 级流水)
    ├── output_accumulator    输出累加 + 归一化
    └── causal_mask_unit      Causal mask 生成
```

## 验证方案 — 7 大验证领域 (24 项 Baseline + 24 项 Bonus)

### 1. 验证点 (VP01-VP06) — 6 项

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_zero_test` | VP01 | 全零输入，softmax 退化处理 |
| `fa_random_nocausal_test` | VP02 | 随机输入 (无 causal)，标准 SDPA |
| `fa_random_causal_test` | VP03 | 随机输入 (causal)，在线 softmax |
| `fa_identity_test` | VP04 | 恒等矩阵 Q，边界数值 |
| `fa_boundary_test` | VP05 | 边界值混合，极值测试 |
| `fa_maxval_test` | VP06 | 最大值矩阵，溢出保护 |

### 2. 寄存器验证 (REG01-REG07) — 7 项

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_reg_reset_test` | REG01 | 复位值检查 |
| `fa_reg_access_test` | REG02 | 读写一致性 |
| `fa_reg_stress_test` | REG03 | 50 轮背靠背压力 |
| `fa_ral_test` | REG04 | UVM RAL 前门读写 + mirror/predict |
| `fa_reg_walk_test` | REG05 | Walking-1/Walking-0 逐位测试 |
| `fa_reg_unmapped_test` | REG06 | 未映射地址访问 |
| `fa_reg_soft_reset_test` | REG07 | 软复位功能 |

### 3. DMA 验证 (DMA01-DMA03) — 3 项

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_dma_test` | DMA01 | 端到端数据完整性 + Golden Model |
| `fa_dma_b2b_test` | DMA02 | 背靠背连续传输 |
| `fa_dma_addr_test` | DMA03 | 不同地址区间 DMA |

### 4. AXI 协议验证 (AXI01-AXI03) — 3 项

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_axi_protocol_test` | AXI01 | 端到端 + 39 条 SVA 断言 |
| `fa_axi_dual_mode_test` | AXI02 | Causal + Non-causal 双模式 |
| `fa_axi_regonly_test` | AXI03 | 320 次 AXI4-Lite 事务压力 |

### 5. 性能测试 (PERF01-PERF02) — 2 项

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_perf_test` | PERF01 | 基准性能 (cycle, BW, 利用率, 吞吐量) |
| `fa_perf_compare_test` | PERF02 | Causal vs Non-Causal 性能对比 |

### 6. 覆盖率 (COV01-COV02 + COMP) — 3 项

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_coverage_test` | COV01 | 覆盖率驱动随机测试 |
| `fa_coverage_closure_test` | COV02 | 交叉覆盖闭合 (全模式 × 全数据) |
| `fa_comprehensive_test` | COMP | 全流程综合验证 |

## AXI VIP 组件

| 组件 | 描述 |
|------|------|
| **AXI4-Lite Agent** | 完整 UVM Agent: Driver + Monitor + Sequencer |
| **AXI4 Memory Agent** | 完整 VIP: Slave Responder + Monitor + Analysis Ports |
| **AXI4 Protocol Checker** | 21 条 SVA 断言: 握手稳定性、参数有效性、X/Z 检查 |
| **AXI4-Lite Protocol Checker** | 18 条 SVA 断言: 地址对齐、握手规则、X/Z 检查 |

## 覆盖率收集 (10 个 Covergroup)

| Covergroup | 描述 |
|------------|------|
| `fa_config_cg` | 配置模式 × 数据模式交叉 |
| `fa_reg_cg` | 寄存器地址 × 读/写交叉 |
| `fa_reg_val_cg` | 寄存器特征值覆盖 |
| `fa_dma_cg` | DMA 方向 × 大小交叉 |
| `fa_axi_burst_cg` | AXI4 突发: 方向×长度×大小 |
| `fa_perf_cg` | 性能区间覆盖 |
| `fa_perf_detail_cg` | 带宽/利用率详细区间 |
| `fa_vp_cg` | 15 个验证点完成度跟踪 |
| `axi4_txn_cg` | AXI4 突发类型/长度/响应 |
| `axil_txn_cg` | AXI4-Lite 读写地址/STRB/响应 |

## 性能指标

| 指标 | Baseline | Bonus |
|------|----------|-------|
| 执行周期 | **276,100** (< 300k) | **276,165** (< 600k) |
| mean_abs_error | 0.013350 | 0.013350 |
| max_abs_error | 0.238281 | 0.238281 |
| 片上存储 | ~8.75 KB | ~8.75 KB |
| 总带宽 | 4.06 MB | 4.06 MB × heads |
| 读带宽 | 178.0 MB/s | 178.0 MB/s |
| 写带宽 | 59.3 MB/s | 59.3 MB/s |

## 验证结果总览

| 版本 | 测试总数 | 通过 | 失败 | 执行周期 |
|------|---------|------|------|---------|
| **Baseline** | 24 | **24** | 0 | 276,100 |
| **Bonus** | 24 | **24** | 0 | 276,165 |
| **合计** | **48** | **48** | **0** | — |

## Bonus 加分项 (9 项全部实现)

| 编号 | 功能 | 实现模块 |
|------|------|---------|
| 1 | BF16/FP16 数据格式 | `bf16_exp_unit.sv`, `bf16_reciprocal_unit.sv` |
| 2 | Multi-Head 注意力 | `tile_controller_bonus.sv` (NUM_HEADS 循环) |
| 3 | 可变序列长度 | `tile_controller_bonus.sv` (运行时 SEQ_LEN, 最大 1024) |
| 4 | Padding Mask | `mask_unit.sv` + PAD_LEN 寄存器 |
| 5 | 其他定点格式 | `compute_core_bonus.sv` (Q6.10, Q4.12) |
| 6 | Dropout (训练模式) | `dropout_unit.sv` (LFSR 伪随机) |
| 7 | INT8 量化 | `int8_quantizer.sv` (块量化) |
| 8 | AXI4-Stream 接口 | `axi4_stream_if.sv` |
| 9 | DMA / Task Queue | `task_queue.sv` (4 深度) |

## VCS 新内核兼容性修复

在 Docker 容器或新内核 Linux 上运行 VCS 时，可能遇到 `/proc/self/stat` 读取崩溃。本项目提供 LD_PRELOAD 修复：

```bash
gcc -shared -fPIC -o /tmp/vcs_fopen_fix.so submission/vcs_fopen_fix.c -ldl
export LD_PRELOAD=/tmp/vcs_fopen_fix.so
export VCS_INTERNAL_NO_PROC_STAT=1
```

## UVM DPI Unicode 修复（如需要）

```bash
python3 -c "
path = '\$VCS_HOME/etc/uvm-1.2/dpi/uvm_hdl_vcs.c'
with open(path, 'rb') as f:
    data = f.read()
data = data.replace(b'\xe2\x80\x9c', b'\x22')
data = data.replace(b'\xe2\x80\x9d', b'\x22')
data = data.replace(b'\xe2\x80\x99', b'\x27')
with open(path, 'wb') as f:
    f.write(data)
print('Fixed')
"
```
