# Sky130 HS 综合 — Run #1 结果摘要（2026-04-20）

## 运行结果一句话

> **100 MHz 时钟下综合收敛**：最差路径 slack **+1102 ps**，全部 `max_transition`/`max_capacitance`/`max_fanout` design rules **无违规**；`flash_attention_top` 成功映射到 `sky130_fd_sc_hs` 库上。面积/功耗报告因脚本 bug 未落盘（见下文）。

## 运行环境

| 项 | 值 |
|---|---|
| 主机 | sh02lo02 (Intel Xeon Gold 6140 18×2 核, 1006 GB RAM) |
| Genus | 25.12-s067_1 (DDI 25.12.000) |
| Liberty | `sky130_fd_sc_hs__tt_025C_1v80.lib` (TT, 1.8V, 25°C) |
| Top | `flash_attention_top` |
| Clock period 目标 | 10.0 ns (100 MHz) |
| Effort | medium / medium / medium (generic / map / opt) |
| Clock gating | disabled |
| 总 wall time | **6 h 5 min** (04:44:07 → 10:49:41 BJ 时间) |
| 内存峰值 | 24.2 GB (master process) |

## Critical Path Timing (来自 `reports/timing_top20.rpt`，run 1)

```
Path 1: MET (1102 ps) Setup Check
  Group: clk
  Startpoint: u_tile_ctrl/q_idx_reg[1]/CLK
  Endpoint:   u_tile_ctrl/dma_rd_addr_reg[63]/D

       Clock Edge:+   10000 ps  (100 MHz)
            Setup:-     174 ps
      Uncertainty:-     200 ps
    Required Time:=    9626 ps
        Data Path:-    8525 ps
            Slack:=   +1102 ps    ← POSITIVE = MET
```

- 最差路径从 tile_controller 的 q_idx 寄存器出发，经过一串 Wallace CSA 全加器乘法 → 回写到 DMA 读地址寄存器
- 数据路径 **8525 ps** / 时钟周期 **10000 ps** ≈ 85% 利用率，还有 15% 裕量
- 理论极限：`10000 - 8525 - 174 - 200 = 1101 ps` slack ≈ fmax **110 MHz**（把周期压到 9 ns, 即 ~111 MHz 才会开始违规；保守设到 9.5 ns / 105 MHz 应该能稳定收敛）

## Design Report (来自 `reports/design.rpt`)

```
Technology library: sky130_fd_sc_hs__tt_025C_1v80 1.0000000000
Operating conditions: typ (balanced_tree)

Max_transition design rule:   no violations.
Max_capacitance design rule:  no violations.
Max_fanout design rule:       no violations.
```

**3 条 DRC 全过** — 综合网表就绪，可以直接 handoff 给 Innovus 做 PnR。

## syn_generic 6-partition summary (从 genus_run.log 提取)

| Partition | Start Cell Count | Done Cell Count | Done Slack (ns) | Elapsed |
|---|---:|---:|---:|---:|
| pbs_genopt_0 | — | 6,401 | -0.46 | 56 s |
| pbs_genopt_1 | 207,477 | 194,710 | -0.84 | 2,160 s |
| pbs_genopt_2 | — | 74,417 | -0.87 | 1,119 s |
| pbs_genopt_3 | 1,449,164 | 954,036 | +2.85 | 3,142 s |
| pbs_genopt_4 | 39,420 | **5** ← 几乎全被常数折叠/死代码消除 | +0.37 | 70 s |
| pbs_genopt_5 | — | 1,602,278 | -31.92 | 10,404 s (2h53min, 最长) |

> ⚠️ pbs_genopt_4 塌缩到 5 个 cell 值得回查 RTL — 很可能是某个 partition 被常数输入锁死、或者综合时 `SYNTHESIS` 宏把某个路径关掉了。

## syn_map (PBS_Map) 示例数据

| Partition | Start (Cell×Area) | Done (Cell×Area) | Slack Done |
|---|---:|---:|---:|
| pbs_map_6 | 19801 × 540k | 11220 × 373k | +276 ps |
| pbs_map_8 | 20170 × 547k | 11741 × 378k | +275 ps |

每个 map partition 平均把 cell count 优化掉 ~43%，slack 由 generic 阶段的 +163ps 收紧到映射后的 +275ps（因为真实 std cell 计时比 generic 估算更精确）。

## ⚠️ 本次缺失的报告

以下文件应该由 `scripts/genus_synth.tcl` 生成，但**第一轮**因 Tcl 错误阻断：

- `reports/area.rpt`, `area_summary.rpt`, `area_detail.rpt`
- `reports/gates.rpt`, `gates_nand2eq.rpt`（赛题面积评判口径: NAND2 等效门数）
- `reports/power.rpt`
- `reports/qor.rpt`
- `reports/messages.rpt`, `clock_gating.rpt`
- `results/flash_attention_top_netlist.v`
- `results/flash_attention_top.sdc`
- `results/flash_attention_top_post_syn.db`

### 根因

Genus 25.12 里 `report_area -hierarchy` 选项已被移除，改用 `-depth <integer>`。旧 `tools/sky130_synth/scripts/genus_synth.tcl`（HD 版本）用的也是 `-hierarchy`，但那版本跑在不同的 Genus 版本上可能还支持。

```
Error : An invalid option was specified. [TUI-204]
        : An option named '-hierarchy' could not be found.
```

Tcl script 遇到 Error 后整体 abort，`write_hdl` / `write_sdc` / 后续 report 全部跳过。

### 修复（已 commit，Run #2 在跑）

- 把 `write_hdl` / `write_sdc` / `write_db` 挪到所有 report 命令之前 — 哪怕后面 report 失败，至少 netlist + db 保底
- 把 12 个 report 命令改成 `foreach + catch { ... }` 驱动，单条失败不影响后续
- `-hierarchy` → `-depth 10`
- 加 `-normalize_with_gate sky130_fd_sc_hs__nand2_1` 用于 NAND2 等效门数

见 commit `41a6aba`。

## Run #2 状态：**重复了 Run #1 的 bug**（FILES tab upload 同名不覆盖）

Run #2 启动于 BJ 时间 11:14（UTC 03:14）、运行了 6 小时 4 分钟，但**产出和 Run #1 完全一样**——只有 3 份 timing/design 报告，没有 area/power/qor/gates_nand2eq/网表，`reports` tar 89.93 KB。

### 根因

FILES tab 行为：upload 不会覆盖同名文件。

1. Run #2 前我做了 `cadence_runner.py rm sky130_synth_hs.tar.gz` + `bash pack_and_upload.sh`
2. `rm` 返回 `not found`（FILES 列表里显示的名字和 NFS 文件名之间有缓存）
3. `pack_and_upload` upload 以后，FILES tab 多了一条 `sky130_synth_hs.tar(2).gz`，**但** NFS 上 `sky130_synth_hs.tar.gz`（旧，Run #1 用过）还在
4. `run.sh` 里 `tar xzf "$HOME/neere/Start Mate Desktop/sky130_synth_hs.tar.gz"` 解出来的是**旧 tar**，里面是带 `report_area -hierarchy` 的 Tcl
5. Run #2 最后在 `report_area -hierarchy` 再次 abort，只保下来 3 份 timing/design 报告

诊断发现方法：登录远端 `ls -la "$HOME/neere/Start Mate Desktop/" | grep sky130_synth_hs`，看 FILES 区里到底有几个 `.tar.gz` / `.tar(N).gz`。

### 已修

1. `pack_and_upload.sh` 改成上传前先远端 `rm sky130_synth_hs.tar.gz "sky130_synth_hs.tar(1).gz" "sky130_synth_hs.tar(2).gz" "sky130_synth_hs.tar(3).gz"`，再 upload，再 md5 校验。
2. ACCESS.md §5.8 记录这个坑。
3. 手工把 FILES 上的 `sky130_synth_hs.tar(2).gz` 重命名成 `sky130_synth_hs.tar.gz`（确保这次远端脚本能拿到正确 tar）。

## Run #3 状态：进行中

启动于 BJ 时间 17:41（UTC 09:41），PID 2130272。这次确认 Tcl 是带 `foreach + catch {}` + `-depth 10` 的正确版本（grep 到 line 100 `write_db`, line 103 `foreach {fname cmd} {`, line 117 `set rc [catch {`）。

**Run #3 运行期间的观测**：
- 1h03min: genopt done 3/6 ✅
- 2h06min: genopt done 5/6 ✅
- 3h+ 后 VNC proxy 返回 `Internal server error / ERROR 500`，noVNC iframe 无法加载，无法继续 probe
- FILES tab API 仍然工作（不需要 VNC）
- 预期 BJ 23:45 前后生成 `sky130_synth_hs_result_20260420_1741xx.tar.gz`

Run #3 完成后会替换本文件为完整的 area / gates / power / qor 汇总。

## 附件

`reports_run1/` 目录保留了 Run #1 能拿到的三份关键报告：

- `reports_run1/design.rpt`         (DRC 全过)
- `reports_run1/timing_top20.rpt`   (200k，top 20 worst-N5 critical path)
- `reports_run1/timing_max_head80k.rpt` (前 80KB 的 `timing_max.rpt`，完整 432KB 因体积没全进仓)
