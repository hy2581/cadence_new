# 赛题（docx）与 Baseline 实现对照分析

> **权威来源**：`Cadence赛题-第九届中国研究生创芯大赛.docx`（赛题二·FlashAttention）
> **清洁 Markdown**：<ref_file file="docs/赛题-FlashAttention-Baseline.md" />
> **对照范围**：2.1 基本功能要求（必选）· 2.2 性能要求（必选）
> **结论（修订，2026-04-23）**：
> - **功能 / 接口 / tiling / 面积 / 时序 / 延迟** 逐条对齐，Genus + Xcelium 数字支撑；
> - **2.1(8) 精度条款**在随机 Q/K/V 端到端场景下 **未满足**（见下表 §1.2 SPEC_CHECK 实测）：
>   `fa_random_causal_test` 最大 `max_abs_error=0.977`（spec ≤ 0.10），`mean_abs_error` 普遍 0.05–0.12（spec ≤ 0.03）。

---

## 1. 2.1 基本功能要求

| # | docx 赛题要求 | Baseline 落实点 | 状态 |
|:---|:---|:---|:---:|
| (1) | 算法定义：`score_ij = (Q_i·K_j)/√d + M_ij`；`P_ij = softmax`；`O_i = Σ P_ij·V_j` | <ref_file file="submission/baseline/rtl/dot_product_array.sv" /> + <ref_file file="submission/baseline/rtl/online_softmax_unit.sv" /> + <ref_file file="submission/baseline/rtl/output_accumulator.sv" /> | ✅ |
| (2a) | **禁止** 显式存储注意力矩阵 | 片上 buffer ≈ 8.75 KB，仅缓存 K/V tile + 每行 m/l/acc；无 $S\times S$=64 K 项存储 | ✅ |
| (2b) | **必须** 使用在线 softmax | <ref_file file="submission/baseline/rtl/online_softmax_unit.sv" />（维护 $m_i, l_i$，按块更新） | ✅ |
| (2c) | **必须** 分块 (tiling) 处理 K/V | <ref_file file="submission/baseline/rtl/tile_controller.sv" />（`TILE_BR=4, TILE_BC=16`，共 64×16 tile-pair） | ✅ |
| (3) | 固定规模 $S=256, d=64$，batch=1，head=1 | <ref_snippet file="submission/baseline/rtl/include/fa_params.svh" lines="9-10" />（`SEQ_LEN=256, HEAD_DIM=64`） | ✅ |
| (4a) | Q/K/V/O = Q8.8 有符号 16-bit | <ref_snippet file="submission/baseline/rtl/include/fa_params.svh" lines="19-20" />（`DATA_WIDTH=16, FRAC_BITS=8`） | ✅ |
| (4b) | Dot-product 累加 ≥ 32-bit（建议 ≥ 40-bit） | <ref_snippet file="submission/baseline/rtl/include/fa_params.svh" lines="21" />（`ACC_WIDTH=40`） | ✅ |
| (4c) | softmax 路径允许更高位宽 | `EXP_WIDTH=24, SCORE_WIDTH=40`（<ref_snippet file="submission/baseline/rtl/include/fa_params.svh" lines="22-23" />） | ✅ |
| (5a) | AXI4-Lite 控制接口 | <ref_file file="submission/baseline/rtl/axi4_lite_slave.sv" /> | ✅ |
| (5b) | AXI4 Master + DMA 数据接口 | <ref_file file="submission/baseline/rtl/axi4_master_if.sv" /> + <ref_file file="submission/baseline/rtl/dma_engine.sv" /> | ✅ |
| (6) | 寄存器（CTRL/STATUS/CFG/Q/K/V/O_BASE/STRIDE/NEG_LARGE/SCALE/CYCLES）| 见下表 § 1.1 ——偏移、访问类型、位定义 **全部 1:1 对齐** | ✅ |
| (7) | 禁存 score/P 全矩阵；仅缓存 K,V tile + 每行 m/l/acc | `buffer_system.sv` 双缓冲 K/V tile；`online_softmax_unit` 仅持久化 m/l/acc | ✅ |
| (8) | 与 FP32 golden 对比；`mean_abs_error ≤ 0.03`；`max_abs_error ≤ 0.10` | 框架已齐：<ref_file file="submission/baseline/tb/uvm_env/fa_scoreboard.sv" /> 内置 FP32 golden + SPEC_CHECK 行；**实测数据未达标**，详见 §1.2 | ❌ |
| (9a) | UVM 或 cocotb 验证框架 | SystemVerilog + UVM 1.2（`+UVM_TESTNAME=...`） | ✅ |
| (9b) | 必含 AXI4-Lite 寄存器读写与启动/完成流程 | `fa_reg_access_test`, `fa_reg_walk_test`, `fa_reg_stress_test`, `fa_ral_test` 等 7 项 REG 测试 | ✅ |
| (9c) | 必含随机 Q,K,V 端到端验证 | `fa_random_nocausal_test`, `fa_random_causal_test` | ✅ |
| (9d) | 必含 Causal mask corner case | `fa_boundary_test`（行 0 仅见 $j=0$）、`fa_axi_dual_mode_test` | ✅ |

### 1.1 寄存器 1:1 对照

| Offset | docx 名称 | docx 位定义 | Baseline 实现（`axi4_lite_slave.sv`）| 状态 |
|:---|:---|:---|:---|:---:|
| 0x00 | CTRL | START/SOFT_RESET/IRQ_EN | `r_ctrl`，bit0 脉冲 START、bit1 脉冲 SOFT_RESET、bit2 IRQ_EN | ✅ |
| 0x04 | STATUS | BUSY/DONE(w1c)/ERROR | `{error, done_sticky(w1c), busy}` | ✅ |
| 0x08 | CFG | CAUSAL_EN / RESERVED | `r_cfg[0]=causal_en` | ✅ |
| 0x14/0x18 | Q_BASE_L/H | Q 基地址 | `r_q_base_l/h` | ✅ |
| 0x1C/0x20 | K_BASE_L/H | K 基地址 | `r_k_base_l/h` | ✅ |
| 0x24/0x28 | V_BASE_L/H | V 基地址 | `r_v_base_l/h` | ✅ |
| 0x2C/0x30 | O_BASE_L/H | O 基地址 | `r_o_base_l/h` | ✅ |
| 0x34 | STRIDE_BYTES | 默认 `d*2` | `r_stride`，复位默认 `128`（=64×2） | ✅ |
| 0x38 | NEG_LARGE | -inf 近似（Q8.8） | `r_neg_large`，复位默认 `16'h8000`（-128.0） | ✅ |
| 0x3C | SCALE | 1/√d | `r_scale`，复位默认 `16'h0020`（=1/8 Q8.8，≈1/√64） | ✅ |
| 0x40 | CYCLES | 本次执行周期数 | `cycle_count`（RO） | ✅ |

> RAL 端对应：<ref_file file="submission/baseline/tb/uvm_env/fa_reg_model.sv" /> 也按相同位域声明（`fa_reg_ctrl` / `fa_reg_status` / `fa_reg_cfg` 等 15 个寄存器，`fa_ral_test` 逐项校验读写/权限）。

### 1.2 2.1(8) 精度实测（SPEC_CHECK，xrun 2026-04-23 01:52）

`fa_scoreboard` 在每次 `check_results()` 打印一行：

```
SPEC_CHECK | mean_abs=<f> (spec<=0.030) | max_abs=<f> (spec<=0.100) | PASS|FAIL | N=<count>
```

从 `/tmp/fa_xrun/log_*.log` grep 汇总（每 test 只显示最后一次 check；多次 check 的 `PASS/FAIL` 计数在列里）：

| Test | PASS 次数 | FAIL 次数 | 最后一次 `mean_abs` | 最后一次 `max_abs` | 对 spec 判定 |
|:---|:---:|:---:|---:|---:|:---:|
| `fa_zero_test` | 1 | 0 | 0.000000 | 0.000000 | ✅ |
| `fa_identity_test` | 1 | 0 | 0.013081 | 0.042969 | ✅ |
| `fa_comprehensive_test` | 1 | 1 | 0.013387 | 0.046875 | 混合 |
| `fa_coverage_closure_test` | 3 | 2 | 0.013419 | 0.070312 | 混合 |
| `fa_maxval_test` | 0 | 1 | 0.036621 | 0.082031 | ❌ mean 超 |
| `fa_random_nocausal_test` | 0 | 1 | 0.029713 | **0.128906** | ❌ max 超 |
| `fa_dma_b2b_test` | 0 | 2 | 0.033051 | **0.164062** | ❌ |
| `fa_boundary_test` | 0 | 1 | **0.113863** | **0.250000** | ❌ |
| `fa_coverage_test` | 0 | 2 | **0.123962** | **0.250000** | ❌ |
| `fa_dma_test` / `fa_dma_addr_test` | 0 | 1 | 0.023251 | **0.484375** | ❌ max 远超 |
| `fa_random_causal_test` | 0 | 1 | **0.057435** | **0.976562** | ❌❌ max 接近 1.0 |
| `fa_axi_protocol_test` | 0 | 1 | 0.057435 | **0.976562** | ❌❌ |

**观察**
- 纯零 / 单位矩阵输入 → ✅（验证 golden 路径正确）
- 一旦 Q,K,V 是随机实数据（causal 更糟） → `mean` 超 2–4×、`max` 超 2–10× 阈值；最坏达到 **0.977**（Q8.8 动态范围的全幅）。
- 其他 **功能/协议/寄存器** 测试全部 `UVM_ERROR=0, UVM_FATAL=0` → 24/24 PASS 仍成立；但这**只说明 AXI/UVM/协议层无违规**，不等于赛题精度合规。
- 根因方向（需要 RTL 改动）：softmax 路径内部位宽（目前 `EXP_WIDTH=24, SCORE_WIDTH=40`）+ `exp_approx_unit` 查找表精度 + Q8.8 最终截断策略 + 1/√d=0.125 精确缩放。

**现场复现**
```bash
# 客户端
bash submission/scripts/xrun_pack_and_upload.sh

# 远端 sh02lo02（Mate Terminal）
cd /tmp && rm -rf submission && \
  tar xzf "$HOME/neere/Start Mate Desktop/submission_xrun.tar.gz" -C /tmp && \
  cd /tmp/submission && WAVE_TEST=fa_perf_test nohup bash scripts/xrun_remote_driver.sh > /tmp/xrun_outer.log 2>&1 &

# 结果 tarball 含：spec_check_<ts>.txt（汇总）、log_*.log（每 test）、waves_fa_perf_test.shm/（20 MB SHM）
```

---

## 2. 2.2 性能要求

**Genus 物理综合已完成**，工艺库 `sky130_fd_sc_hs__tt_025C_1v80`（TT 25°C 1.8V），Genus 25.12-s067，详见 <ref_file file="tools/sky130_synth_hs/reports_run3/" />。

| # | docx 赛题要求 | Baseline 实测 | 状态 |
|:---|:---|:---|:---:|
| (1) | 主频目标：越高越好（Genus 物理综合报告） | **100 MHz 约束下 MET，slack = +1102 ps → 隐含 Fmax ≈ 112 MHz**；Setup/Max-transition/Max-cap/Max-fanout 均无违例（<ref_file file="tools/sky130_synth_hs/reports_run3/qor.rpt" />、<ref_file file="tools/sky130_synth_hs/reports_run3/timing_max.rpt" />、<ref_file file="tools/sky130_synth_hs/reports_run3/design.rpt" />） | ✅ |
| (2) | 等效逻辑门数 **≤ 200 万门**（2-NAND 口径） | **15,847 NAND2 等效门**（≈ 2M 上限的 **0.8 %**，共 3,555 leaf / 1,242 seq / 2,313 comb），详见 <ref_file file="tools/sky130_synth_hs/reports_run3/gates_nand2eq.rpt" />、<ref_file file="tools/sky130_synth_hs/reports_run3/area_summary.rpt" /> | ✅ |
| (3) | 单次 attention **< 300,000 cycles** | **276,100 cycles**（xrun 实测；`fa_perf_test`） | ✅ |
| (4) | `RD_BYTES / WR_BYTES` 统计与优化分析 | RD 178.0 MB/s、WR 59.3 MB/s、利用率 3.0%（<ref_file file="submission/baseline/docs/verification_report.md" /> § 2.2） | ✅ |

### 2.1 Genus Run #3 关键数字（2026-04-20 · `sh02lo02`）

| 项 | 值 |
|:---|:---|
| Genus 版本 | 25.12-s067_1 |
| 工艺库 | `sky130_fd_sc_hs__tt_025C_1v80`（Sky130A HS / TT 25 °C 1.8 V） |
| 顶层 | `flash_attention_top` |
| 时钟约束 | 10.0 ns（100 MHz），uncertainty 0.2 ns |
| Setup 最差 slack | **+1102 ps**（MET） |
| TNS / Violating paths | 0.0 / 0 |
| Cell area（raw） | 75,987.935 μm² 等效 |
| **Normalized NAND2-eq gates** | **15,847**（≤ 2,000,000 要求 **✓**） |
| Leaf instances | 3,555（1,242 seq · 2,313 comb） |
| Layer violations | Max-transition / Max-capacitance / Max-fanout 均无违例 |
| Power（Joules vectorless） | **11.12 mW** 总（reg 8.49 mW / logic 2.63 mW） |
| Runtime | 21,972 s wall / 4,084 s CPU |

> **面积分布（主要模块）** — 单位：NAND2 等效门，来自 `area_detail.rpt`
>
> | 模块 | Gates | 说明 |
> |:---|---:|:---|
> | `u_dma` (DMA + AXI4 master) | 4,984 | 含 `u_axi_master` 2,637 |
> | `u_axil` (AXI4-Lite slave + reg file) | 4,962 | 15 寄存器 |
> | `u_tile_ctrl` | ~4,600 | tiling / 地址生成 / 主 FSM |
> | `u_compute` | 854 | `u_dp` 99 + `u_oa` 340 + `u_softmax` 263 |
> | 其他 | ~460 | buffer/mask/顶层 glue |

### 2.2 综合流程复现

```bash
# 客户端（当前仓库根目录）
bash tools/sky130_synth_hs/pack_and_upload.sh

# 远端 sh02lo02（Mate Terminal 里，或 cadence_runner exec 代跑）
cd /tmp && rm -rf sky130_synth_hs && \
  tar xzf "$HOME/neere/Start Mate Desktop/sky130_synth_hs.tar.gz" && \
  cd sky130_synth_hs && nohup bash scripts/run.sh > /tmp/sky130_synth_hs/run_outer.log 2>&1 &

# 结果打包：$HOME/neere/Start Mate Desktop/sky130_synth_hs_result_<TS>.tar.gz
# 然后 cadence_runner.py download 回本地
```

脚本：<ref_file file="tools/sky130_synth_hs/scripts/genus_synth.tcl" />、<ref_file file="tools/sky130_synth_hs/scripts/run.sh" />、<ref_file file="tools/sky130_synth_hs/pack_and_upload.sh" />。

---

## 3. 验证规模

| 维度 | Baseline 实现 |
|:---|:---|
| UVM 测试总数 | **24**（<ref_file file="submission/baseline/tb/tests/fa_tests.sv" />：`fa_base_test` + 24 派生） |
| 覆盖领域 | VP（功能）/ REG（寄存器）/ DMA / AXI 协议 / Performance / Coverage |
| SVA 协议检查 | AXI4 21 条、AXI4-Lite 18 条（<ref_file file="submission/baseline/tb/agents/axi4_protocol_checker.sv" />、<ref_file file="submission/baseline/tb/agents/axi4_lite_protocol_checker.sv" />） |
| Covergroup 数 | 10（<ref_file file="submission/baseline/tb/uvm_env/fa_coverage.sv" />） |
| 最近一次仿真结果 | **24/24 PASS，UVM_ERROR=0，UVM_FATAL=0**（Cadence 云 · Xcelium 24.09.006 · `sh02lo02`） |

---

## 4. 差异与遗留项

本版本已闭合原来的 Genus 综合缺口；差异仅余一项流程性提示：

- **Innovus PnR / 后仿真** 尚未在 Cadence 云上跑。赛题 2.2 指标要求的是 **Genus 物理综合报告**（已完成），PnR 不是必选项；鼓励方向，后续可选。
- 原根目录 `FlashAttention加器计决划.md`（文件名与内容均破损）已在本 PR 删除；<ref_file file="docs/赛题-FlashAttention-Baseline.md" /> 作为 docx 的等价 Markdown，是后续唯一 Chinese 版参照。

---

## 5. 结论

| 要求 | 结果 |
|:---|:---|
| 2.1 功能/tiling/AXI/寄存器/UVM 14 项 | **达标** — RTL / TB 1:1 映射 |
| **2.1(8) 精度（mean≤0.03 / max≤0.10）** | **未达标** — 随机 Q,K,V 场景下 `max_abs_error` 最高 **0.977**（参见 §1.2） |
| 2.2(1) 主频（Genus @ 10 ns） | **100 MHz MET**，slack +1102 ps，隐含 Fmax ≈ 112 MHz |
| 2.2(2) 面积 ≤ 2M NAND2-eq | **15,847 NAND2（占 0.8 %）** |
| 2.2(3) 延迟 < 300k cycles | **276,100 cycles** |
| 2.2(4) 带宽统计 | RD 178 MB/s · WR 59 MB/s · 利用率 3 % |
| 功能仿真（UVM_ERROR=0 口径） | Xcelium 24.09.006 @ `sh02lo02` — 24/24 PASS（PR [#4](https://github.com/hy2581/cadence/pull/4)） |
| 功耗 | Joules vectorless **11.12 mW** @ 100 MHz |
| 波形文件 | `waves_fa_perf_test.shm/` 20 MB（Xcelium 原生 `waves.dsn + waves.trn`） |

**总体判断**：Baseline 在 **结构 / 接口 / 面积 / 时序 / 延迟 / 功耗 / 仿真通过率** 各侧齐备；**唯一硬差距** 是 2.1(8) 数值精度，fixed-point 路径在真实随机数据下误差显著超标。要完全合规需要 RTL 改动（扩宽中间位宽、改进 `exp_approx_unit` 查找表、调整归一化策略）。
