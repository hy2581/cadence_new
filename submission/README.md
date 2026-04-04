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
│   │   ├── agents/               UVM Agents + Protocol Checkers
│   │   │   ├── axi4_lite_agent/  AXI4-Lite Master Agent (VIP)
│   │   │   ├── axi4_mem_agent/   AXI4 Memory Agent (VIP + Monitor)
│   │   │   ├── axi4_protocol_checker.sv   AXI4 SVA 协议检查器
│   │   │   └── axi4_lite_protocol_checker.sv  AXI4-Lite SVA 协议检查器
│   │   ├── uvm_env/              UVM 环境 (env + scoreboard + coverage + RAL)
│   │   ├── sequences/            UVM Sequences (8 个)
│   │   ├── tests/                UVM Tests (24 个)
│   │   └── tb_top/               UVM TB 顶层 (协议检查器始终启用)
│   ├── constraints/              SDC 约束
│   └── docs/                     设计报告
│
├── bonus/                        Bonus 版本（加分项 × 9）
│   ├── rtl/                      增强 RTL
│   ├── tb/                       Bonus 验证
│   └── constraints/              SDC 约束
│
├── scripts/                      运行脚本
│   ├── run_baseline.sh           Baseline 仿真
│   ├── run_bonus.sh              Bonus 直接 TB（19 测试）
│   ├── run_bonus_uvm.sh          Bonus UVM 测试
│   └── run_uvm_all.sh            完整 UVM 验证套件（24 测试）
│
└── README.md                     本文件
```

## 环境要求

- **VCS**: Synopsys VCS (L-2016.06 或更高版本)
- **UVM**: VCS 内置 UVM-1.2
- **OS**: Linux (Ubuntu 20.04/22.04)

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
bash scripts/run_bonus.sh
bash scripts/run_bonus_uvm.sh fa_bonus_causal_test
```

## 验证方案 — 7 大验证领域

### 1. 验证点 (Verification Points) — 6 项测试

| 测试名 | 编号 | 描述 | 覆盖要点 |
|--------|------|------|----------|
| `fa_zero_test` | VP01 | 全零输入 | 零值处理、softmax 退化 |
| `fa_random_nocausal_test` | VP02 | 随机输入 (无 causal) | 标准 SDPA 路径 |
| `fa_random_causal_test` | VP03 | 随机输入 (causal) | Causal mask、在线 softmax |
| `fa_identity_test` | VP04 | 恒等矩阵 Q | 边界数值行为 |
| `fa_boundary_test` | VP05 | 边界值混合 | 最大/最小/正/负边界 |
| `fa_maxval_test` | VP06 | 最大值矩阵 | 溢出保护、饱和处理 |

### 2. AXI VIP — 完整 AXI 验证 IP 组件

| 组件 | 描述 |
|------|------|
| **AXI4-Lite Agent** | 完整 UVM Agent: Driver + Monitor + Sequencer |
| **AXI4 Memory Agent** | 完整 VIP: Slave Responder + Monitor + Analysis Ports |
| **AXI4 Burst Transaction** | `axi4_burst_txn`: 记录突发传输的地址/长度/数据/延迟 |
| **AXI4 Master Monitor** | `axi4_mem_monitor`: 监控所有 DMA 读写突发,提供 analysis port |
| **AXI4 Protocol Checker** | SVA 断言: valid/ready 握手、信号稳定性、X 检查 |
| **AXI4-Lite Protocol Checker** | SVA 断言: 对齐、握手、数据稳定性 |

Monitor 捕获指标:
- 总读/写突发次数、字节数、拍数
- 单次突发延迟 (start_time → end_time)
- 连接至覆盖率收集器自动采样

### 3. 寄存器模型验证 — 7 项测试

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_reg_reset_test` | REG01 | 复位值检查 (CTRL/STATUS/CFG/STRIDE/CYCLES) |
| `fa_reg_access_test` | REG02 | 所有可写寄存器读写一致性 |
| `fa_reg_stress_test` | REG03 | 50 轮全寄存器背靠背压力测试 |
| `fa_ral_test` | REG04 | UVM RAL 前门读写、mirror/predict 验证 |
| `fa_reg_walk_test` | REG05 | Walking-1/Walking-0 位测试 (检查每一位) |
| `fa_reg_unmapped_test` | REG06 | 未映射地址访问测试 |
| `fa_reg_soft_reset_test` | REG07 | 软复位功能测试 |

RAL 模型组件:
- `fa_reg_block`: 包含 15 个寄存器定义 (CTRL~CYCLES)
- `fa_reg_adapter`: AXI4-Lite → UVM reg bus 适配器
- `uvm_reg_predictor`: 自动预测器 (非 auto_predict 模式)

### 4. DMA 验证 — 3 项测试

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_dma_test` | DMA01 | 端到端数据完整性 (预加载验证 + 输出非零检查) |
| `fa_dma_b2b_test` | DMA02 | 背靠背连续传输 (两次计算, 验证第二次结果不同) |
| `fa_dma_addr_test` | DMA03 | 不同地址区间 DMA (验证地址配置灵活性) |

### 5. AXI 协议 — 3 项测试

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_axi_protocol_test` | AXI01 | 完整端到端 + SVA 断言监控 |
| `fa_axi_dual_mode_test` | AXI02 | Causal + Non-causal 双模式 AXI 协议合规 |
| `fa_axi_regonly_test` | AXI03 | 纯寄存器 AXI4-Lite 协议压力 (320 次事务) |

SVA 断言覆盖:
- AXI4: AWVALID/WVALID/ARVALID 握手稳定性 (12 条)
- AXI4: AWSIZE/AWBURST/ARSIZE 有效性 (4 条)
- AXI4: X/Z 未知值检查 (5 条)
- AXI4-Lite: 地址对齐、数据稳定性 (13 条)
- AXI4-Lite: X/Z 检查 (5 条)

### 6. 功能性能 — 2 项测试

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_perf_test` | PERF01 | 基准性能 (cycle count, BW, 利用率, 吞吐量) |
| `fa_perf_compare_test` | PERF02 | Causal vs Non-Causal 性能对比 |

报告指标:
- 执行周期 (vs 300k 目标)
- 读/写带宽 (MB/s)
- 总线利用率 (%)
- 元素吞吐量 (elements/cycle)

### 7. 覆盖率 — 2 项测试 + 全局收集

| 测试名 | 编号 | 描述 |
|--------|------|------|
| `fa_coverage_test` | COV01 | 覆盖率驱动随机测试 (200 次寄存器 + 多模式) |
| `fa_coverage_closure_test` | COV02 | 交叉覆盖闭合 (所有模式 × 所有数据模式) |
| `fa_comprehensive_test` | COMP | 全流程综合验证 |

覆盖率收集:
| Covergroup | 描述 |
|------------|------|
| `fa_config_cg` | 配置模式 × 数据模式交叉覆盖 |
| `fa_reg_cg` | 寄存器地址 × 读/写交叉覆盖 |
| `fa_reg_val_cg` | 寄存器特征值覆盖 (CTRL/CFG/STRIDE/SCALE) |
| `fa_dma_cg` | DMA 方向 × 大小交叉覆盖 |
| `fa_axi_burst_cg` | AXI4 突发: 方向×长度, 方向×大小 交叉 |
| `fa_perf_cg` | 性能区间覆盖 |
| `fa_perf_detail_cg` | 带宽/利用率详细覆盖 |
| `fa_vp_cg` | 15 个验证点完成度跟踪 |
| `axi4_txn_cg` (checker) | AXI4 突发类型/长度/响应覆盖 |
| `axil_txn_cg` (checker) | AXI4-Lite 读写地址/STRB/响应覆盖 |

覆盖率合并:
```bash
# run_uvm_all.sh 自动合并所有测试覆盖率
# 输出: /tmp/fa_uvm/coverage_report/dashboard.html
```

## 性能指标

| 指标 | Baseline | Bonus (2 heads) |
|------|----------|-----------------|
| 执行周期 | 276,100 | 552,323 |
| mean_abs_error | 0.013350 | 0.013350 |
| max_abs_error | 0.238281 | 0.238281 |
| 片上存储 | ~8.75 KB | ~8.75 KB |
| 总带宽 | 4.06 MB | 4.06 MB × heads |

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
