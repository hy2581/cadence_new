# FlashAttention 高性能硬件加速器 IP — 提交包

## 目录结构

```
submission/
├── baseline/                     Baseline 版本（必选项）
│   ├── rtl/                      15 个 RTL 模块
│   │   ├── include/fa_params.svh 全局参数
│   │   ├── flash_attention_top.sv
│   │   ├── tile_controller.sv
│   │   ├── compute_core.sv
│   │   ├── dot_product_array.sv
│   │   ├── online_softmax_unit.sv
│   │   ├── exp_approx_unit.sv
│   │   ├── exp_lut_rom.sv
│   │   ├── reciprocal_unit.sv
│   │   ├── output_accumulator.sv
│   │   ├── causal_mask_unit.sv
│   │   ├── buffer_system.sv
│   │   ├── dma_engine.sv
│   │   ├── axi4_lite_slave.sv
│   │   └── axi4_master_if.sv
│   ├── tb/                       验证环境
│   │   ├── unit_tb/              直接测试
│   │   ├── agents/               UVM Agents
│   │   ├── uvm_env/              UVM 环境
│   │   ├── sequences/            UVM Sequences
│   │   ├── tests/                UVM Tests
│   │   └── tb_top/               UVM TB 顶层
│   ├── constraints/              SDC 约束
│   └── docs/                     设计报告
│
├── bonus/                        Bonus 版本（加分项 × 9）
│   ├── rtl/                      增强 RTL
│   │   ├── include/fa_params_bonus.svh
│   │   ├── flash_attention_bonus_top.sv  增强顶层
│   │   ├── tile_controller_bonus.sv      多头+可变序列+任务队列
│   │   ├── compute_core_bonus.sv         多格式+Padding+Dropout
│   │   ├── axi4_lite_slave_bonus.sv      扩展寄存器
│   │   ├── mask_unit.sv                  联合 Causal+Padding Mask
│   │   ├── dropout_unit.sv               LFSR Dropout
│   │   ├── task_queue.sv                 FIFO 任务队列
│   │   ├── axi4_stream_if.sv            AXI4-Stream 接口
│   │   ├── bf16_exp_unit.sv             BF16 Exp 近似
│   │   ├── bf16_reciprocal_unit.sv      BF16 倒数
│   │   └── int8_quantizer.sv            INT8 块量化
│   ├── tb/                       Bonus 验证
│   │   ├── bonus_system_tb.sv    直接 TB（19 项测试）
│   │   ├── uvm_env/              UVM 环境
│   │   ├── sequences/            UVM Sequences
│   │   ├── tests/                UVM Tests（6 个）
│   │   └── tb_top/               UVM TB 顶层
│   └── constraints/              SDC 约束
│
├── scripts/                      运行脚本
│   ├── run_baseline.sh           Baseline 仿真
│   ├── run_bonus.sh              Bonus 直接 TB（19 测试）
│   └── run_bonus_uvm.sh          Bonus UVM 测试
│
└── README.md                     本文件
```

## 环境要求

- **VCS**: Synopsys VCS (O-2018.09-SP2 或更高版本)
- **UVM**: VCS 内置 UVM-1.2
- **OS**: Linux (Ubuntu 20.04/22.04)

## 快速复现

### 1. 配置环境

```bash
# 设置 Synopsys VCS 环境变量
export VCS_HOME=/usr/synopsys/vcs-mx/O-2018.09-SP2
export PATH=$VCS_HOME/bin:$PATH
# 或 source 你的环境脚本
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

### 3. 运行 Bonus 直接 TB（19 项测试）

```bash
bash scripts/run_bonus.sh
```

**预期结果**:
```
BONUS TEST SUMMARY
Total tests:  19
PASS:         19
FAIL:         0
>>> ALL BONUS TESTS PASSED <<<
```

### 4. 运行 Bonus UVM 测试

```bash
# 运行单个 UVM 测试
bash scripts/run_bonus_uvm.sh fa_bonus_causal_test
bash scripts/run_bonus_uvm.sh fa_bonus_padding_test
bash scripts/run_bonus_uvm.sh fa_bonus_dropout_test
bash scripts/run_bonus_uvm.sh fa_bonus_bf16_test
bash scripts/run_bonus_uvm.sh fa_bonus_combined_test
```

**注意**: UVM DPI 编译可能需要先修复 Unicode 字符问题（见下方）。

### UVM DPI Unicode 修复（如需要）

某些 VCS 安装中 `uvm_hdl_vcs.c` 包含 Unicode 引号字符，需要修复：

```bash
python3 -c "
path = '$VCS_HOME/etc/uvm-1.2/dpi/uvm_hdl_vcs.c'
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

## 测试清单

### Baseline 测试

| 测试 | 内容 | 结果 |
|------|------|------|
| 端到端 Causal Attention | s=256, d=64, causal=1 | PASS (276k cycles) |

### Bonus 直接 TB 测试（19 项）

| # | 测试 | Bonus 项 | 结果 |
|---|------|---------|------|
| 1 | Baseline Causal | 基准 | PASS |
| 2 | Padding Mask | Bonus 4 | PASS |
| 3-4 | Multi-Head (H0+H1) | Bonus 2 | PASS |
| 5 | Dropout | Bonus 6 | PASS |
| 6-9 | Format Registers | Bonus 1/5/7 | PASS |
| 10 | Variable Seq Length | Bonus 3 | PASS |
| 11 | AXI4-Stream Register | Bonus 8 | PASS |
| 12 | AXI4-Stream Data | Bonus 8 | PASS |
| 13 | Task Queue Register | Bonus 9 | PASS |
| 14 | Task Queue E2E | Bonus 9 | PASS |
| 15 | Q6.10 Compute | Bonus 5 | PASS |
| 16 | BF16 Compute | Bonus 1 | PASS |
| 17 | INT8 Compute | Bonus 7 | PASS |
| 18 | Combined Features | 全部 | PASS |

### Bonus UVM 测试（5 项）

| 测试名 | 内容 | 结果 |
|--------|------|------|
| fa_bonus_causal_test | Causal attention | PASS |
| fa_bonus_padding_test | Padding mask | PASS |
| fa_bonus_dropout_test | Dropout mode | PASS |
| fa_bonus_bf16_test | BF16 format | PASS |
| fa_bonus_combined_test | 2 heads + causal + padding | PASS |

## 性能指标

| 指标 | Baseline | Bonus (2 heads) |
|------|----------|-----------------|
| 执行周期 | 276,100 | 552,323 |
| mean_abs_error | 0.013350 | 0.013350 |
| max_abs_error | 0.238281 | 0.238281 |
| 片上存储 | ~8.75 KB | ~8.75 KB |
| 总带宽 | 4.06 MB | 4.06 MB × heads |
