# Sky130 HS 综合 — 中间进度记录（2026-04-20）

> **状态**：syn_generic 阶段全部 6 partition 完成，syn_map / syn_opt 进行中。最终 reports/ 还没生成；本文件记录已经能拿到的中间数据，待综合完成后会被替换为完整的 final report。

## 1. 运行环境

| 项 | 值 |
|---|---|
| 主机 | sh02lo02 (Intel Xeon Gold 6140 18×2 = 36 phys cores, 1006 GB RAM) |
| OS | RHEL 8.4 |
| Genus | DDI 25.12.000 (Genus 25.12-s067_1) |
| License | `5280@sh02lo01` |
| Lib | `/tmp/sky130_pdk/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib` (TT, 1.8V, 25°C) |
| Top | `flash_attention_top` |
| Clock period | 10.0 ns (100 MHz target) |
| Effort | medium / medium / medium (generic / map / opt) |
| Clock gating | disabled |
| Cell LEF | **未加载** (sky130A 不带 Cadence 兼容的 tech LEF, 详见 `tools/ACCESS.md` §5.3) |

## 2. syn_generic — 6 partitions 全部完成

PBS (Partition-Based Synthesis) 自动把 `flash_attention_top` 切成 6 个 partition 并行跑 generic optimization：

| Partition | Cell-Count Start → Done | Cell-Area Start → Done | Slack Done (ns) | TNS Done | Elapsed |
|---|---:|---:|---:|---:|---:|
| pbs_genopt_0 | (initial) → **6,401**       | (initial) → **125,604**     | -460.9   | 460.9     | 56 s     |
| pbs_genopt_4 | 39,420 → **5**              | 562,715 → **158**           | +370.4   | 0.0       | 70 s     |
| pbs_genopt_2 | (initial) → **74,417**      | (initial) → **1,094,848**   | -874.9   | 425,785   | 1,119 s  |
| pbs_genopt_1 | 207,477 → **194,710**       | 6,339,267 → **5,576,018**   | -839.9   | 886,205   | 2,160 s  |
| pbs_genopt_3 | 1,449,164 → **954,036**     | 15,621,737 → **10,933,790** | +2,846.3 | 0.0       | 3,142 s  |
| pbs_genopt_5 | (initial) → **1,602,278**   | (initial) → **18,868,626**  | -31,920  | 321,000,845 | 10,404 s |
| **TOTAL after generic** | **~2,831,847** | **~36,599,044** | (per-part) | (per-part) | ~17,000 s wall (并行) |

**说明**：

- "Cell-Count" 此处是 **generic gates**（与/或/异或等通用代数门），不是真实的 standard cell。`syn_map` 把这些映射到 sky130_fd_sc_hs 库后数量会大幅下降。
- **`pbs_genopt_4` 塌缩到 5 cells** — 这个 partition 几乎全是 dead code 或被上下文常数化的逻辑，跟旧 HD 综合时观察到的现象一致。后续应该回 RTL 排查（可能是 reset 锁死的死代码、或者综合时 `SYNTHESIS` macro 把某条路径关掉了）。
- **`pbs_genopt_5` 是最大且最差的 partition**：1.6M cells, slack -31920 ns。虽然 syn_map/syn_opt 还会大幅优化，但 partition 5 在初始 generic 上就严重违反时序，最终能不能在 100 MHz 收敛要看 syn_opt 后的报告。

## 3. syn_map / syn_opt — 进行中（已观测到的 partition）

`syn_map` + `syn_opt` 阶段被 Genus 改名为 PBS Final Compile Optimization (`pbs_fcopt_*`)。目前已观测到的 8 个 fcopt partition (9, 11, 12, 13, 14, 15, 19, 23)：

| Partition | Cell-Count Start → Done | Cell-Area Start → Done | Slack Done (ns) | Elapsed |
|---|---:|---:|---:|---:|
| pbs_fcopt_9..15  | 103,558 → **60,928** | 1,167,300 → **875,015** | +1,262 | ~330 s |
| pbs_fcopt_19, 23 | 类似  | 类似 | 类似 | ~390 s |

每个 fcopt partition 基本上把 generic gates 优化掉 ~40%，slack 从 +2179 收紧到 +1262 ns（注意这时候已经是真实 std cell timing，不是 generic 估算了，但还在松目标——因为我设的 clock period 是 10ns，在 Sky130 HS 上 100 MHz 比较容易收敛）。

预期 fcopt partition 总数 30+，每个 5-7 min，全部完成预计 +30-60 min。

## 4. 内存峰值

| 阶段 | Peak Memory |
|---|---:|
| pbs_genopt_3 (1.45M cells)        | **11.25 GB** |
| pbs_genopt_5 (1.6M cells)         | (估计 ≥12 GB) |
| pbs_fcopt_9 (smaller partitions)  | **23.6 GB** (这个是因为 Genus master 同时持有多个 partition 的 db) |

峰值 ~24 GB，远低于服务器 1006 GB 上限。完全没问题。

## 5. 总挂钟时间估算

- syn_generic: 已经用了 ~3h (wall, 6 partition 并行但 partition 5 单独 2h53min 卡住)
- syn_map (pbs_fcopt_*): 估计 +30-60 min
- syn_opt (final): 估计 +20-40 min
- 报告生成 + 网表写出: 1-2 min
- **预计 total wall**: 4 - 5 h

> 这一行待综合彻底完成、`reports/qor.rpt` 和 `reports/area.rpt` 拉回本地后会被替换为最终数据。
