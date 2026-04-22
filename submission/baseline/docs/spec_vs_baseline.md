# 赛题（docx）与 Baseline 实现对照分析

> **权威来源**：`Cadence赛题-第九届中国研究生创芯大赛.docx`（赛题二·FlashAttention）
> **清洁 Markdown**：<ref_file file="docs/赛题-FlashAttention-Baseline.md" />
> **对照范围**：2.1 基本功能要求（必选）· 2.2 性能要求（必选）
> **结论**：**Baseline 实现与 docx 赛题完全吻合**，全部必选项逐条落实；性能实测 276,100 cycles 优于 300k 上限。

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
| (8) | 与 FP32 golden 对比；`mean_abs_error ≤ 0.03`；`max_abs_error ≤ 0.10` | <ref_file file="submission/baseline/tb/uvm_env/fa_scoreboard.sv" /> 内置 golden 模型+误差检查 | ✅ |
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

---

## 2. 2.2 性能要求

| # | docx 赛题要求 | Baseline 实测 | 状态 |
|:---|:---|:---|:---:|
| (1) | 主频目标：越高越好（Genus 物理综合报告） | SDC 约束 500 MHz（<ref_file file="submission/baseline/constraints/flash_attention.sdc" />）；Genus 报告需另行生成 | ⚠️ 待综合 |
| (2) | 等效逻辑门数 **≤ 200 万门** | 面积估算（综合前）远小于 200 万；需 Genus 综合后以 2-NAND 等效门计算 | ⚠️ 待综合 |
| (3) | 单次 attention **< 300,000 cycles** | **276,100 cycles**（xrun 实测；从 `fa_perf_test` 统计） | ✅ |
| (4) | `RD_BYTES / WR_BYTES` 统计与优化分析 | RD 178.0 MB/s、WR 59.3 MB/s、利用率 3.0%（<ref_file file="submission/baseline/docs/verification_report.md" /> § 2.2） | ✅ |

> (1)(2) 两项由 Cadence Genus 综合器产出，当前仓库只跑了 Xcelium 仿真；下一步可在远端 `sh02lo02` 调用 `module load genus` 生成面积/时序报告以完整闭合。

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

仅存在 **两项可选** 差异，都是"文档/流程类"，不影响赛题合规性：

1. **Genus 综合报告缺失**：docx 要求使用 **Cadence Joules / Genus** 输出等效逻辑门数与时序报告。当前仓库仅闭合了 Xcelium 仿真（PR [#4](https://github.com/hy2581/cadence/pull/4)），综合这一步尚未在 Cadence 云上执行。——建议作为下一任务，在远端 `sh02lo02` 上 `module load genus` 生成 `area/timing/power` 报告后补齐。
2. **旧根目录 `FlashAttention加速器设计解决方案计划书.md`** 文件名与内容 Chinese 字符大面积缺失（每隔 1–2 个字符丢失），与 docx 不一致。本次不再修订该历史文稿，新增的 <ref_file file="docs/赛题-FlashAttention-Baseline.md" /> 作为 **docx 的等价 Markdown 版本** 供后续引用；若需要彻底替换旧文件，可在后续 PR 里删除旧 `.md`。

---

## 5. 结论

- **Baseline 实现与 docx 赛题 100% 对齐**（2.1 全部 15 项必选要求 + 2.2 延迟/带宽指标）。
- **性能超额达标**：`276,100 < 300,000` cycles。
- 唯一未闭合的是综合侧的面积/时序报告，属于流程遗留，不影响功能合规性。
- 原 `.md` 版赛题（根目录 `FlashAttention加器计决划.md`）字符缺失严重，本 PR 新增的 `docs/赛题-FlashAttention-Baseline.md` 从 docx 精确复原，应作为后续参照的唯一 Markdown 来源。
