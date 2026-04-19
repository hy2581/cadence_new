# Sky130 sky130_fd_sc_hs Genus 综合环境

赛题官方钦点用 Sky130A PDK 的 **sky130_fd_sc_hs** (High Speed) 标准单元库做综合
（依据 `/home/share/readMe.txt`：*"please use the sky130_fb_sc_hs library"*，其
中 `fb` 是 typo，正确库名是 `_fd_sc_hs`，详见 `tools/ACCESS.md` §5）。

## 目录结构

```
tools/sky130_synth_hs/
├── README.md                  本文件
├── scripts/
│   ├── genus_synth.tcl        Genus 综合脚本 (HS lib + 100MHz 目标)
│   └── run.sh                 bash 驱动器: PDK 解包 → module load → genus -batch → 打包结果
└── pack_and_upload.sh         本地打包: submission/baseline/rtl → tar → cadence_runner upload
```

注意: 没有 `lib/` 子目录, 因为 lib 文件在远端 `/home/share/sky130A.tar.gz` 里, 解包到
`/tmp/sky130_pdk/sky130A/libs.ref/sky130_fd_sc_hs/lib/` 直接读. 不再需要本地传 lib.

## 一键运行

```bash
# 本地: 打 tar + upload
bash tools/sky130_synth_hs/pack_and_upload.sh

# 远端: 解 tar + 跑综合 (可后台 nohup)
python3 tools/cadence_runner.py exec \
  'cd /tmp && rm -rf sky130_synth_hs && tar xzf "$HOME/neere/Start Mate Desktop/sky130_synth_hs.tar.gz" && cd sky130_synth_hs && nohup bash scripts/run.sh > /tmp/sky130_synth_hs/run_outer.log 2>&1 & echo PID=$!' \
  --after 8000

# 等待结果 (Genus 在 Sky130 HS 上跑 flash_attention_top 大约 30min - 2h)
python3 tools/cadence_runner.py poll sky130_synth_hs_result_ --timeout 7200 --interval 60

# 下载结果
python3 tools/cadence_runner.py list | grep sky130_synth_hs_result_
python3 tools/cadence_runner.py download sky130_synth_hs_result_<TS>.tar.gz ./
```

## 关键约束 (在 `genus_synth.tcl` 内联)

| 项 | 值 | 备注 |
|---|---|---|
| Liberty | `sky130_fd_sc_hs__tt_025C_1v80.lib` | TT/1.8V/25°C, 12.6MB |
| Clock 周期 | 10 ns (100 MHz) | Sky130 HS 上保守起步; 收敛后再迭代收紧 |
| Clock uncertainty | 0.2 ns | |
| 输入/输出 delay | 周期 × 0.20 (=2 ns) | 留 80% 给内部逻辑 |
| max_fanout | 32 | |
| max_transition | 0.5 ns | |
| Effort | medium / medium / medium | generic / map / opt |
| Clock gating | 关闭 | 避免 ICG cell 缺失 |

## 关键报告

| 文件 | 内容 |
|---|---|
| `reports/timing_max.rpt`           | 最差 50 路径 |
| `reports/timing_top20.rpt`         | top-20 worst, 每条 5 个候选 |
| `reports/area.rpt` / `area_summary.rpt` | 面积层次 / 总览 |
| `reports/gates_nand2eq.rpt`        | **NAND2 等效门数** (赛题面积评判口径) |
| `reports/qor.rpt`                  | 综合 QoR (slack/area/cell count) |
| `reports/power.rpt`                | 功耗 |
| `results/flash_attention_top_netlist.v` | 综合后 gate-level netlist |
| `results/flash_attention_top.sdc`  | 写出的 SDC (供 Innovus PnR) |

## 与旧版 (`sky130_synth/`，HD lib) 的区别

| 项 | 旧 (HD) | 新 (HS) |
|---|---|---|
| Lib | `sky130_fd_sc_hd__tt_025C_1v80.lib` (efabless 拉的, 12.8MB, **本地 tar 上传**) | `sky130_fd_sc_hs__tt_025C_1v80.lib` (官方 PDK, **远端解包**) |
| 是否符合赛题 | ❌ HD 不是钦点库, 报告不算数 | ✅ HS 是钦点库 |
| 上传体积 | sky130_synth.tar.gz ≈ 2.14 MB (含 lib) | sky130_synth_hs.tar.gz ≈ < 1 MB (不含 lib) |
| Clock period | 20 ns (50MHz) | 10 ns (100MHz) |
| LEF | 无 | 加载 `sky130_fd_sc_hs.lef` (Genus 物理感知) |
| NAND2-eq 报告 | 无 | 有 (赛题要的) |
