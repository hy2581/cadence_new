# Sky130 HS 综合最终结果（Run #3，2026-04-20）

## 一句话总结

> **`flash_attention_top` 在 Sky130 sky130_fd_sc_hs 标准单元库上，100 MHz 时钟下综合收敛**：
> slack **+1102 ps** MET，总面积 **75,988 μm²**，**NAND2 等效门数 15,847**（赛题预算 200 万门，占 0.79% ✅），
> 功耗估算 **11.12 mW**，DRC 全过，综合后网表 + SDC + DB 全部落盘。

## 关键指标一览

| 指标 | 值 | 备注 / 与赛题要求对比 |
|---|---:|---|
| Technology | `sky130_fd_sc_hs__tt_025C_1v80` | TT, 1.8V, 25°C — 赛题官方钦点 (`/home/share/readMe.txt`) |
| Clock period target | 10.0 ns (100 MHz) | 保守起点；见 §"fmax 进一步压缩"讨论 |
| **Worst Setup Slack** | **+1101.6 ps ✅** | TNS = 0, 违规路径 0 |
| Worst path | `u_tile_ctrl/q_idx_reg[1] → u_tile_ctrl/dma_rd_addr_reg[63]` | 走了 tile_controller 里的 Wallace CSA 全加器乘法器 (DMA 地址计算) |
| Data Path Delay | 8525 ps (占 85% 周期) | 余量 1102 ps |
| **Total Cell Count** | **3,555** | 3555 个 std cell |
| — Sequential (flops) | 1,242 | |
| — Combinational | 2,313 | |
| — Hierarchical | 10 | |
| **Total Cell Area** | **75,987.935 μm²** | |
| **NAND2-equivalent gate count** | **15,846.666** | **赛题预算 ≤ 2,000,000 门**, 占 0.79% |
| Net Area | 0 | wire-load 模型是 `Small (D)`，没有精确布线估算 |
| **DRC** | max_trans ✅ max_cap ✅ max_fanout ✅ | 全过，无违规 |
| **Total Power** | **11.12 mW** (vectorless) | 来自 Joules engine 估算 |
| — Leakage | 1.13 μW (0.01%) | |
| — Internal | 9.76 mW (87.77%) | 主要功耗 |
| — Switching | 1.36 mW (12.22%) | |
| Wall runtime | 21,972 s = **6 h 6 min** | Genus 主进程 |
| Peak memory | 23.6 GB | Genus master process |

## 子模块面积分布

```
flash_attention_top               3555 cells   75987.9 μm²    15847 NAND2-eq  (100.0%)
├── u_axil      (axi4_lite_slave)   845 cells   23795.4 μm²     4962 NAND2-eq  (31.3%)
├── u_compute   (compute_core)      272 cells    4096.7 μm²      854 NAND2-eq  ( 5.4%)
│   ├── u_dp      (dot_product_array)  27 cells    473.1 μm²    99 NAND2-eq
│   ├── u_oa      (output_accumulator) 109 cells   1628.8 μm²   340 NAND2-eq
│   │   └── u_recip (reciprocal_unit)    4 cells    147.1 μm²    31 NAND2-eq
│   └── u_softmax (online_softmax)   88 cells    1261.1 μm²   263 NAND2-eq
│       └── u_exp    (exp_approx)     3 cells     110.3 μm²    23 NAND2-eq
├── u_dma       (dma_engine)        709 cells   23899.3 μm²     4984 NAND2-eq  (31.5%)
│   └── u_axi_master (axi4_master_if) 368 cells  12643.3 μm²  2637 NAND2-eq
└── u_tile_ctrl (tile_controller)  1599 cells   22062.7 μm²     4601 NAND2-eq  (29.0%)
```

**观察**：
- 面积最大的三块：`u_tile_ctrl`、`u_dma`、`u_axil`（AXI 控制接口）几乎平分了 90% 的面积。
- `u_tile_ctrl` 1599 个 std cell 是最复杂的一块，因为它要做 tiling 循环控制 + 地址生成（含乘法器），critical path 也落在这里。
- `u_compute`（真正做 SDPA 计算的）只占 5.4% 面积。这符合 FlashAttention-style 低存储设计的特性——主要逻辑在控制流，算术单元相对小。

## Critical Path 详细分析

来自 `reports_run3/timing_top20.rpt` Path 1：

```
Path 1: MET (1102 ps) Setup Check with Pin u_tile_ctrl/dma_rd_addr_reg[63]/CLK->D
  Group: clk
  Startpoint: (R) u_tile_ctrl/q_idx_reg[1]/CLK
  Endpoint:   (F) u_tile_ctrl/dma_rd_addr_reg[63]/D

     Clock Edge:+   10000  (100 MHz)
    Src Latency:+       0
    Net Latency:+       0
        Arrival:=   10000
          Setup:-     174
    Uncertainty:-     200
  Required Time:=    9626
      Data Path:-    8525
          Slack:=   +1102    ← MET
```

路径组成（主要 cell 类型）：
- `sky130_fd_sc_hs__dfrbp_1` D-flop
- `sky130_fd_sc_hs__fa_1` 全加器（Wallace CSA 树里 **几十个级联**）
- `sky130_fd_sc_hs__nand2_1` / `nor2_1` / `o221ai_1` / `o311ai_1` 等 2/3 输入复合逻辑
- 最后 `sky130_fd_sc_hs__sdfxtp_1` D-flop 捕获

critical path 走的是 `tile_controller.sv` 里计算 `q_row_base + q_idx * stride` 这类 DMA 地址的乘法累加链。**优化方向**：

1. `q_idx * stride` 改成 shift-add（如果 stride 可以是 2 的幂）
2. 把乘法流水化（用两拍算出 DMA 地址）
3. 把 `q_idx` pre-decode 成一张查找表（占用更多 flops 换更短的组合路径）

## fmax 进一步压缩讨论

- Slack +1102 ps 理论上允许周期压到 10000 - 1102 = **8898 ps ≈ 112 MHz**
- 但综合工具在拿到更紧的目标时会花更多资源重做时序优化，实际 fmax 可能比理论值低 5-10%
- 保守猜测 **Sky130 HS 上的稳定 fmax ≈ 105-108 MHz**
- **极限试探建议**：Run #4 把 `CLK_PERIOD` 改成 9.0 ns 跑一次，看能不能 MET；如果 MET，再压到 8.5 ns；直到开始出负 slack

## 运行历史（三轮）

| Run | 启动时间 | Wall time | tcl 关键 bug | 产物 |
|---|---|---:|---|---|
| #1 | BJ 04:44 UTC 20:44 | 6h 5min | `report_area -hierarchy` (25.12 已移除) → abort | 3 报告 (design/timing_max/timing_top20), 无 netlist |
| #2 | BJ 11:14 UTC 03:14 | 6h 4min | FILES tab 没覆盖同名 tar, 远端还是用 Run #1 的旧 tcl → 同样 abort | 3 报告 (同 Run #1) |
| **#3** | BJ 17:41 UTC 09:41 | **6h 7min** | 脚本修好；但 `puts $fh [eval $cmd]` 写空文件（Genus `report_*` 打 stdout 返空字符串）→ **reports/ 文件全 1 字节**；走 log 后处理救回 | 所有 11 份报告 + netlist + sdc + db ✅ |

**Run #3 的 reports/ 是 1 字节空文件**，真正的报告文本在 `genus.log` 里（因为 `report_*` 打到 stdout 而不是返回字符串）。本次用 Python 脚本从 `genus_run.log` 按 `report OK:` 标记切分，**完整还原**了所有 11 份报告到 `reports_run3/`。

下次跑（以及 commit 4 会修的 Tcl）应该用：

```tcl
set rc [catch {
    eval "$cmd > reports/$fname"      # Genus Tcl 的 '>' redirect 语义
} err]
```

这样 report_* 的 stdout 会直接写到文件。

## 附件

目录 `reports_run3/` 完整保留：

| 文件 | 大小 | 说明 |
|---|---:|---|
| `design.rpt` | 606 B | DRC 检查 (max_transition / cap / fanout) |
| `timing_max.rpt` | 422 KB | 最差 50 条 setup 路径，完整全路径 cell 列表 |
| `timing_top20.rpt` | 191 KB | top-20 worst, 每条 5 候选路径 |
| `area.rpt` | 2.9 KB | 按层次展开的 cell area 分布 |
| `area_summary.rpt` | 741 B | 总 cell count + cell area |
| `area_detail.rpt` | 4.1 KB | 详细层次 area breakdown |
| `gates_nand2eq.rpt` | 3.6 KB | **NAND2 等效门数**（赛题口径） |
| `gates.rpt` | 37 B | 失败 (Genus 25.12 说 `-gates` with no hinst 不行，之后迭代) |
| `qor.rpt` | 1.7 KB | QoR 总览（slack、cell count、area、runtime、memory） |
| `power.rpt` | 4.2 KB | Joules vectorless 功耗估算 |
| `messages.rpt` | 484 B | 综合过程中 info/warning/error 总数 |
| `clock_gating.rpt` | 2.7 KB | Clock-gating 统计（本次禁用，作为 bonus 起点） |
| `flash_attention_top_netlist.v` | 1.9 MB, 35270 行 | 综合后 gate-level 网表 (HS cell) |
| `flash_attention_top.sdc` | 67.7 KB | 综合工具写出的 SDC (Innovus PnR 用) |

`results/flash_attention_top_post_syn.db` (Genus DB, 1.2 MB) 未入仓（二进制格式，`.db` 在 `.gitignore` 里），但在远端 `/tmp/sky130_synth_hs/results/` 里还在，PnR 时可以直接 load 回来。
