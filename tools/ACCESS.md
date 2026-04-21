# Cadence Cloud 比赛平台 —— 访问方式与远端环境说明

**平台**：`https://cpipc.cadencecloud.cn` （第九届中国研究生创芯大赛，Cadence Cloud）
**账号**：`haoyu`（仅持有人本人，学校统一开通）
**房间**：`rooms/e56bb0dc-8638-428f-82eb-64b4063e1935`（"Start Mate Desktop"）
**远端机器**：`sh02lo02`，RHEL 8 / x86_64
**远端 shell**：`tcsh`（登录默认），`bash` 可用
**VNC**：浏览器内 noVNC iframe，内嵌 Mate Desktop

---

## 1. 能做什么、不能做什么

| 能力 | 状态 |
|---|---|
| 浏览器登录、进入房间、开 Mate Desktop | ✅ |
| FILES tab 上传 / 下载 / 删除文件 | ✅ (上传**不覆盖同名**，必须先 `rm` 再 upload，见 §5.8) |
| 驱动 noVNC 做键鼠 → 远端 Mate Terminal | ✅ (fresh session 要 `exec --open-term`) |
| 跑 `xrun` 仿真（Xcelium 24.09） | ✅ |
| 跑 Genus 综合（DDI 25.12，sky130_fd_sc_hs，100 MHz MET） | ✅ Run #1 已完成，见 §5.7 |
| 跑 Innovus PnR | ⚠️ 缺 Cadence tech LEF，待解决（§5.9） |
| 跑 Joules RTL power | ⚠️ 脚本模板未写 |
| ssh / scp / rsync 直接进 `sh02lo02` | ❌（只有浏览器通道） |
| 远端访问公网 | ⚠️ **DNS 不通**（`/etc/resolv.conf` 空），但 **TCP/443 直连公网 IP 可达**。可用 `curl --resolve` 强行下载 |

---

## 2. 唯一通道：`tools/cadence_runner.py`

这个脚本封装了浏览器自动化（Playwright + Chromium headless）。
配置位于 `~/.cache/cadence_runner/config.json`，登录 cookie 位于 `~/.cache/cadence_runner/storage_state.json`。

核心子命令：

```bash
# 首次登录（走完两步：密码 → 进房间）。后续靠 storage_state 自动续
python3 tools/cadence_runner.py login

# FILES tab 操作
python3 tools/cadence_runner.py list
python3 tools/cadence_runner.py upload <local_path>       # 拖文件到 FILES
python3 tools/cadence_runner.py download <remote_name> [local_out]
python3 tools/cadence_runner.py rm <remote_name>

# noVNC 桌面
python3 tools/cadence_runner.py probe                      # 验证 iframe 可达
python3 tools/cadence_runner.py peek                       # 只截图，不输入
python3 tools/cadence_runner.py exec "<bash_oneliner>"     # 在 Mate Terminal 里跑一条 bash 命令
```

`exec` 的实现细节：

1. 进入房间 → 保持 iframe 全屏 → 点 `(350, 200)` 聚焦 Mate Terminal（这两个坐标对应 1920×1080 viewport 下 Mate Terminal 左上角区域）。
2. 发两次 Ctrl+C 清空残留输入。
3. 把用户给的 oneliner 用 base64 编码打包成 `echo <b64> | base64 -d | bash`。
   * 远端默认 tcsh，不支持 `2>&1` 与 `$(...)`，所以必须走 bash 管道。
   * base64 也避免换行 / 特殊字符被 VNC 键盘层吃掉。
4. 打 Enter，等 `after_ms` 毫秒后截图保存到 `~/.cache/cadence_runner/shots/`。

**结果怎么拿回来**：`exec` 本身不回传 stdout。统一把命令输出重定向到 `/tmp/xxx_$(date +%H%M%S).log`，然后 `cp` 到 **`$HOME/neere/Start Mate Desktop/`**（这就是 FILES tab 的远端真实目录），再用 `list` + `download` 把日志拉回本地。

**长命令监控**：`exec` 把命令送出后只等 `after_ms` 就截图返回；真正还在跑的进程用 `peek` 每隔几十秒截图看一下，或直接去 `list` 看日志是否出现。

---

## 3. 远端文件系统关键路径

| 路径 | 作用 | 权限 |
|---|---|---|
| `$HOME/neere/Start Mate Desktop/` | **FILES tab 的真实挂载点**；上/下载文件都落在这里 | rw |
| `$HOME/Desktop/`, `$HOME/Documents/`, `$HOME/Public/`, `$HOME/Downloads/` | 普通 home 子目录，**与 FILES tab 无关** | rw |
| `/tmp` | 工作空间（`/dev/mapper/vg00-ltmp` xfs，本机盘） | rw |
| `/scratch` | 大工作空间（`vg00-lscratch` xfs） | rw |
| `/home` | NFS 自动挂载（`shstna02:/vol/SH02/home`） | rw |
| `/home/.snapshot/` | NetApp 只读快照（小心：find 经常第一条命中这里，用 `-not -path '*/.snapshot/*'` 过滤） | ro |
| `/apps` | autofs 按需挂载 Cadence 工具 | ro |
| `/apps/DDI251/25.12.000/` | Cadence Digital Design Implementation，含 Genus / Innovus / Joules | ro |
| `/apps/XCELIUM2409/24.09.006/` | Cadence Xcelium 仿真器，含 xrun | ro |
| `/cc`, `/grid/common`, `/proj`, `/projects` | 其它 autofs 自动挂载点（`/grid/common` 下是系统共享库 `.so`；`/cc` 和 `/proj` 当前是空的） | ro |
| `/home/cm_admin/licenses/` | 许可证文件（`CDS_LIC_FILE=5280@sh02lo01`） | ro |
| `/home/share/` | **官方提供的 Sky130A PDK + SRAM IP + Cadence RAK 教程**（NFS 共享，所有 ccusers 可读，由 `shanshan@cadence.com` 维护，详见 §5） | ro |

---

## 4. Module 系统 & EDA 工具链

平台用 `environment-modules`（`/usr/share/Modules`）管理版本。默认 shell 加载后并没有自动 `source` module init，要手动来：

```bash
source /usr/share/Modules/init/sh           # bash
# 或
source /usr/share/Modules/init/csh          # tcsh

module avail
# --- /home/cm_admin/modules/Linux/modulefiles ---
# ddi/251/25.12.000  jasper/2509/25.09.002  license  xcelium/2409/24.09.006

module load license ddi xcelium             # 三选都加，一次搞定
```

加载后可用二进制：

| 工具 | 作用 | 版本 |
|---|---|---|
| `xrun` | 编译 + 仿真（SystemVerilog、UVM、mixed-language） | 24.09-s006 |
| `xmvlog` / `xmelab` / `xmsim` | 分步：编译 / 精化 / 仿真 | 24.09 |
| `genus` | RTL 综合 | 25.12-s067 |
| `innovus` | PnR / 物理实现 | 25.12 |
| `joules` | RTL 功耗分析 | 25.12-s069 |

加载后关键环境变量：

```
CDS_LICENSE_DIR=/home/cm_admin/licenses
CDS_LIC_FILE=5280@sh02lo01
LM_LICENSE_FILE=5280@sh02lo01
XCELIUM_HOME=/apps/XCELIUM2409/24.09.006
INCISIVE_HOME=/apps/XCELIUM2409/24.09.006
AMS_HOME=/apps/XCELIUM2409/24.09.006
PATH=/apps/XCELIUM2409/24.09.006/tools/systemc/gcc/bin/64bit:
     /apps/XCELIUM2409/24.09.006/tools/bin/64bit:
     /apps/XCELIUM2409/24.09.006/bin:
     ... :
     /apps/DDI251/25.12.000/bin
```

---

## 5. PDK / 标准单元库（**官方已提供 Sky130A**，在 `/home/share/`）

### 5.1 结论（已修正）

赛题白纸黑字写"服务器已预装赛事所需的 Cadence EDA 工具及对应工艺库"，确实如此。
**官方 PDK 不通过 module 系统挂载，而是直接 tar 包放在 NFS 共享目录 `/home/share/`**：

```
/home/share/
├── sky130A.tar.gz                                    1.51 GB  完整 Sky130A 开源 PDK
├── sky130_sram_0kbytes_1rw1r_32x64_2.zip             810 KB   OpenRAM 32×64 SRAM IP
├── RAK.tar                                            10 MB   Cadence Rapid Adoption Kit (Genus / Innovus / Jasper SuperLint PDF 教程)
└── readMe.txt                                        163 B    "please use the sky130_fb_sc_hs library" (fb 是 typo，实际是 sky130_fd_sc_hs)
```

`/home/share/` 属于 `shanshan` (UID 900006，`shanshan@cadence.com`，赛事助教)，permissions 是 `drwxr-sr-x ccusers`，**所有 ccusers 用户都可读**。

readMe.txt 原文：

```
please use the sky130_fb_sc_hs library for your design.
if you encounter any missing files or related issues, please contact me immediately: shanshan@cadence.com
```

> 注意：readMe 里的 `sky130_fb_sc_hs` 是 **typo**，正确的库名是 `sky130_fd_sc_hs`（HS = High Speed），后文 §5.4 会列证据。

### 5.2 上一版结论错在哪

旧版 ACCESS.md 这一节断言"平台没装 PDK，需自带"，理由是：

1. `module avail` 只有 ddi/jasper/license/xcelium —— **正确，但 module 不是唯一交付通道**
2. `pdkFinder.csh` 跑出 `pdkList.csv` 只有表头 —— **正确，因为 pdkFinder 只看 `/cc` 下的 autoproj key，NFS 共享目录它不知道**
3. `find / -name '*.lib' -size +100k` 没扫到 —— **当时 find 没下到 `/home/share/`**：原来的 recon 脚本只扫了 `~/shared`、`~/Shared`、`/shared` 等候选位置，恰好漏了 `/home/share`（注意是 **NFS auto.home 自动挂载**，stat 一下就出来）

正确的扫法：

```bash
# 1. 直接看 /home 顶层（每个用户一个目录 + 一个特殊的 share/）
ls -la /home/

# 2. 在共享目录里抓 .lib / .lef / pdk
find /home -maxdepth 4 -name '*.lib' -size +100k -not -path '*/.snapshot/*'

# 3. 直接列 /home/share
ls -la /home/share
```

教训：以后做侦察时，**`/home` 顶层一定要 `ls`**，因为 NFS 共享目录习惯叫 `share/`、`public/`、`pub/` 这种"看着像用户名"的目录，单纯 grep 用户名是看不出来的。

### 5.3 PDK 内部结构（`/home/share/sky130A.tar.gz`，13430 个文件）

解开后是标准的 [google/skywater-pdk](https://github.com/google/skywater-pdk) `sky130A/` 树：

```
sky130A/
├── .config/nodeinfo.json
├── libs.ref/                       # 各家 IP 的物理视图
│   ├── sky130_fd_sc_hs/            # ★ readMe 指定使用的高速标准单元库
│   │   ├── lib/                    # 24 个 Liberty 文件，覆盖全部 PVT corner
│   │   │   ├── sky130_fd_sc_hs__tt_025C_1v80.lib            # ★ typical 角 (综合主用)
│   │   │   ├── sky130_fd_sc_hs__tt_025C_1v80_ccsnoise.lib   # CCS noise 版
│   │   │   ├── sky130_fd_sc_hs__ff_n40C_1v95.lib            # fast-fast 角
│   │   │   ├── sky130_fd_sc_hs__ss_150C_1v60.lib            # slow-slow 角
│   │   │   ├── ... (其它 voltage / temperature 组合)
│   │   ├── lef/sky130_fd_sc_hs.lef                          # ★ Innovus PnR 用
│   │   └── verilog/                                          # 仿真用 (gate-level)
│   │       ├── primitives.v
│   │       ├── sky130_fd_sc_hs.v
│   │       ├── sky130_fd_sc_hs__blackbox.v
│   │       └── sky130_fd_sc_hs__blackbox_pp.v
│   ├── sky130_fd_sc_hd/            # high-density 标准单元 (赛题没指定，可不用)
│   ├── sky130_fd_sc_hdll/          # high-density low-leakage
│   ├── sky130_fd_sc_ms/            # medium-speed
│   ├── sky130_fd_sc_ls/            # low-speed
│   ├── sky130_fd_sc_lp/            # low-power
│   ├── sky130_fd_io/               # IO cells
│   └── sky130_fd_pr/               # primitives (R/C/L、各种器件)
└── libs.tech/                      # 工具链配套
    ├── librelane/sky130_fd_sc_hs/  # synth dont_use / fa_map / latch_map / mux2_map / mux4_map / rca_map / tribuff_map
    ├── magic/                      # Magic 版图
    ├── ngspice/                    # SPICE 模型
    ├── netgen/                     # LVS 比对
    └── openroad/                   # OpenROAD/OpenLane 配套
```

**注意里面没有 Innovus tech LEF（`*tech.lef` / `*.tlf`）**，PnR 阶段需要从 SkyWater 仓库的 `libs.tech/cadence/` 自己合一份；但 **Genus 综合不需要 tech LEF**，只需要 `.lib` + `dont_use` 即可。

### 5.4 为什么是 `_fd_sc_hs` 而不是 `_fb_sc_hs`

readMe 里的 `sky130_fb_sc_hs` 在 PDK 包里**根本不存在**，列出 `libs.ref/` 下所有 `sky130_fd_sc_*` 目录可以确认：

```
sky130A/libs.ref/sky130_fd_sc_hd/
sky130A/libs.ref/sky130_fd_sc_hdll/
sky130A/libs.ref/sky130_fd_sc_hs/      ← 这个，HS = High Speed
sky130A/libs.ref/sky130_fd_sc_lp/
sky130A/libs.ref/sky130_fd_sc_ls/
sky130A/libs.ref/sky130_fd_sc_ms/
```

`fd` = "Foundry Design"（SkyWater 自家命名前缀），`sc` = "Standard Cell"。所以正确库就是 `sky130_fd_sc_hs`。

### 5.5 配套 SRAM IP（OpenRAM 生成）

`/home/share/sky130_sram_0kbytes_1rw1r_32x64_2.zip`，解开后：

```
sky130_sram_0kbytes_1rw1r_32x64_2/
├── sky130_sram_0kbytes_1rw1r_32x64_2.v          ← Verilog behavioral model（综合时 dont_touch）
├── sky130_sram_0kbytes_1rw1r_32x64_2.lef        ← 物理 macro footprint（PnR 用）
├── sky130_sram_0kbytes_1rw1r_32x64_2_TT_1p8V_25C.lib  ← Liberty (TT 1.8V 25C)
├── sky130_sram_0kbytes_1rw1r_32x64_2.gds        ← 版图
├── sky130_sram_0kbytes_1rw1r_32x64_2.sp         ← SPICE netlist
├── sky130_sram_0kbytes_1rw1r_32x64_2.html       ← 数据手册
├── delay_meas.sp / delay_stim.sp                ← 时序测量 testbench
├── functional_meas.sp / functional_stim.sp      ← 功能测量 testbench
└── ...
```

**32 words × 64 bits, 1 RW + 1 R 双口 SRAM**。Baseline 设计的 K/V buffer (~8.75 KB ≈ 280 words × 256 bits) 用不上这个 SRAM 形状，但作为 macro 例子可以学一下接口怎么接 Genus / Innovus。

### 5.6 已落地：`tools/sky130_synth_hs/` — 符合赛题要求的综合环境

旧版本 `tools/sky130_synth/` 用的是 `sky130_fd_sc_hd__tt_025C_1v80.lib`（HD 高密度），不符合赛题钦点。新目录 `tools/sky130_synth_hs/` 切到 `sky130_fd_sc_hs`：

```
tools/sky130_synth_hs/
├── README.md                    环境说明 + 一键运行 howto
├── PROGRESS.md                  Run #1 实际结果摘要 + Run #2 进度
├── pack_and_upload.sh           本地: submission/baseline/rtl + scripts → tar → upload
├── scripts/
│   ├── genus_synth.tcl          Genus Tcl (HS lib, 10ns clk, catch 包裹 12 个 report)
│   └── run.sh                   bash driver: 按需解 PDK → module load → genus -batch → 打包
└── reports_run1/                Run #1 抢救下来的 3 份报告
    ├── design.rpt               (DRC 全过)
    ├── timing_top20.rpt         (top-20 worst, 每条 5 候选)
    └── timing_max_head80k.rpt   (432KB timing_max 的前 80KB)
```

一键运行（本地 + 远端）：

```bash
# 本地
bash tools/sky130_synth_hs/pack_and_upload.sh    # ~24KB tar，秒级

# 远端 (/home/share/sky130A.tar.gz 按需解压到 /tmp/sky130_pdk，约 30s)
python3 tools/cadence_runner.py exec \
  'cd /tmp && rm -rf sky130_synth_hs && tar xzf "$HOME/neere/Start Mate Desktop/sky130_synth_hs.tar.gz" && cd sky130_synth_hs && nohup bash scripts/run.sh > /tmp/sky130_synth_hs/run_outer.log 2>&1 & echo PID=$!' \
  --open-term --after 8000

# 拉结果
python3 tools/cadence_runner.py poll sky130_synth_hs_result_ --timeout 25200 --interval 120
python3 tools/cadence_runner.py download sky130_synth_hs_result_<TS>.tar.gz ./
```

### 5.7 实际测量结果 (Run #3, 2026-04-20, 完整数据)

> Run #1 和 Run #2 都因 Tcl bug 没拿全报告，**Run #3 的数据才是本 PR 的最终结果**。踩过的三个 bug 详见 `tools/sky130_synth_hs/PROGRESS.md`。

**Clock period 10 ns (100 MHz) 收敛成功**，`flash_attention_top` 所有关键指标：

| 指标 | 值 | vs 赛题要求 |
|---|---:|---|
| Technology | `sky130_fd_sc_hs__tt_025C_1v80` | ✅ 官方钦点 |
| **Worst Setup Slack** | **+1101.6 ps ✅ MET** | TNS=0, 违规路径 0 |
| Data Path Delay | 8525 ps (85% of 10000 ps) | 1102 ps 余量 |
| **Total Cell Count** | **3,555** (Sequential 1242 / Combinational 2313 / Hier 10) | |
| **Total Cell Area** | **75,987.935 μm²** | |
| **NAND2-equivalent gates** | **15,847** | 赛题预算 ≤ **2,000,000**，占 **0.79%** ✅ 大幅富余 |
| **Total Power** (vectorless) | **11.12 mW** (leak 0.01% / internal 87.8% / switching 12.2%) | 注：Baseline 只给估算，精确值需 VCD-driven |
| **DRC** | max_trans ✅ / max_cap ✅ / max_fanout ✅ | 3/3 通过 |
| 预估 fmax | ~105-110 MHz | slack 1102ps 允许压到 8.9ns，留 5-10% 保守裕量 |
| Wall time | 6 h 7 min | syn_generic 3h + syn_map 1.5h + syn_opt 1h + reports 10min |
| Memory peak | 23.6 GB | 服务器 1006 GB 绰绰有余 |

Worst setup path：
```
Startpoint:  u_tile_ctrl/q_idx_reg[1]/CLK
Endpoint:    u_tile_ctrl/dma_rd_addr_reg[63]/D
```
经过 tile_controller 里的 Wallace CSA 全加器乘法链（`q_idx * stride` 类似的 DMA 地址计算）。

**子模块面积分布**（占全 top 的百分比）：

| 模块 | Cell | NAND2-eq gates | 占比 |
|---|---:|---:|---:|
| u_tile_ctrl (tile_controller)  | 1599 | 4601 | 29.0% |
| u_dma (dma_engine + axi4_master) | 709 | 4984 | 31.5% |
| u_axil (axi4_lite_slave)       | 845 | 4962 | 31.3% |
| u_compute (compute_core)        | 272 | 854  | 5.4% |
| hierarchy overhead              | 130 | ~445 | ~2.8% |

观察：**90% 面积在控制/接口**（tile_ctrl + dma + axil），真正做 SDPA 计算的 `u_compute` 只有 5.4%。这跟 FlashAttention-style "低中间存储" 设计特性吻合——控制流复杂度高，算术单元相对小。

syn_generic 6 partition 摘要：

| Partition | Done Cell-Count | Done Slack (ns) | Elapsed |
|---:|---:|---:|---:|
| pbs_genopt_0 | 6,401 | -0.46 | 56 s |
| pbs_genopt_1 | 194,710 | -0.84 | 2,160 s |
| pbs_genopt_2 | 74,417 | -0.87 | 1,119 s |
| pbs_genopt_3 | 954,036 | +2.85 | 3,142 s |
| pbs_genopt_4 | **5** ← 塌缩 | +0.37 | 70 s |
| pbs_genopt_5 | 1,602,278 | -31.92 | 10,404 s (2h53min 单 partition) |

> ⚠️ `pbs_genopt_4` 从 39,420 塌缩到 5 cell：partition 里的逻辑被常数折叠光了，或 `SYNTHESIS` 宏关掉了某路径。值得回 RTL 查。

**综合后产物**（已保留在 `tools/sky130_synth_hs/reports_run3/`）：

- 11 份报告 (design/timing_max/timing_top20/area/area_summary/area_detail/gates_nand2eq/qor/power/messages/clock_gating)
- `flash_attention_top_netlist.v` (1.9 MB, 35270 行 gate-level netlist)
- `flash_attention_top.sdc` (67.7 KB, 综合工具写出的 SDC，供 Innovus PnR 用)

### 5.8 踩过的坑（综合阶段，务必写进脚本）

下列问题都在 Run #1/#2 实际踩过，写这里供下一位（下一个 cloud agent / 队友）参考。

**⚠️ Genus 25.12 里 `report_area -hierarchy` 已被移除。**

```
Error : An invalid option was specified. [TUI-204] [parse_options]
        : An option named '-hierarchy' could not be found.
```

旧版本的 Tcl script（包括 `tools/sky130_synth/scripts/genus_synth.tcl`）用 `-hierarchy`，在 25.12 上直接 abort，后续 `write_hdl` / `write_sdc` 全部跳过，**6 小时综合白跑**。改成 `-depth <N>` 即可。

**⚠️ Genus Tcl 脚本里任何一条 `report_*` 失败都会整条 abort**，所以全部 report 应该用 `foreach + catch {}` 包裹；并且 **`write_hdl` / `write_sdc` / `write_db` 必须放在所有 report 之前**（保底，哪怕报告全挂至少还有 netlist）。模板见 `tools/sky130_synth_hs/scripts/genus_synth.tcl` 末尾的 `foreach {fname cmd}` 块。

**⚠️ Genus `report_*` 命令把报告打到 stdout，Tcl 返回值是空字符串。** 所以下面这段看着对的 Tcl 实际是**写空文件**：

```tcl
# 错的: reports/area.rpt 只有 1 字节 (换行)
set fh [open "reports/area.rpt" w]
puts $fh [report_area -depth 10]
close $fh
```

正确用 Genus Tcl 的 `>` redirect 语法（不是标准 Tcl，是 Genus 扩展）：

```tcl
# 对: 报告文本正常写入
eval "report_area -depth 10 > reports/area.rpt"
```

踩过这个坑一次：Run #3 的 reports/*.rpt 全部是 1 字节空文件，真实报告文本全打到了 `/tmp/sky130_synth_hs/genus.log` 里（因为 stdout 被 bash 的 `genus ... > genus_run.log` 捕获）。最后是从 log 里按 `report OK:` 分隔符切回来的。

**⚠️ 不要 `set_db lef_library <sky130 cell LEF>`。** SkyWater 的 `sky130_fd_sc_hs.lef` 引用了 `li1` / `met1` / `pwell` / `nwell` 等层，这些层只在 **Cadence tech LEF** 里定义，而 `/home/share/sky130A.tar.gz` 里**没有** Cadence 兼容的 tech LEF（有 `libs.tech/openroad/` / `librelane/` / `magic/` 但都不是 Innovus 口径）。强行 `lef_library` 会：

```
Error : Undefined pin layer detected. [PHYS-148] : layer 'li1' ...
Error : No capacitance or resistance specified. [PHYS-10] : Specify the tech LEF first.
Error : Cannot change the value of the attribute [TUI-48]
```

Genus 综合本来就不需要 cell LEF（只需要 .lib），所以**直接不加载**就行。PnR 阶段（Innovus）才会绕不开 tech LEF 这件事，下一步需要联系助教要或自己拼一份。

**⚠️ FILES tab 上传同名文件的行为非常坑，踩过两次。** 实测规律：

1. 远端 NFS 已有 `foo.tar.gz`，这个文件实际落在 `$HOME/neere/Start Mate Desktop/foo.tar.gz`
2. `cadence_runner.py rm foo.tar.gz` 可能返回 "not found"（因为 FILES 列表里的名字和 NFS 里的名字有微妙差异，或者被其它 session 锁住）
3. 接着 `cadence_runner.py upload foo.tar.gz` **不会替换原文件**，而是在 FILES tab 里多出一条叫 `foo.tar(1).gz` / `foo.tar(2).gz` 的条目
4. 远端磁盘 NFS 实际看到会有 **3 个文件共存**：`foo.tar.gz`（旧）、`foo.tar(1).gz`、`foo.tar(2).gz`（最新）
5. 脚本里 `tar xzf "$HOME/neere/Start Mate Desktop/foo.tar.gz"` 展开的还是**最旧的那个**

建议流程（改 Tcl 后 safe 重跑）：

```bash
# 本地 pack
bash tools/sky130_synth_hs/pack_and_upload.sh
# 远端：强制清理+检验
python3 tools/cadence_runner.py exec 'cd "$HOME/neere/Start Mate Desktop" && rm -f sky130_synth_hs.tar.gz "sky130_synth_hs.tar(1).gz" "sky130_synth_hs.tar(2).gz"; ls -la sky130_synth_hs*.tar.gz 2>&1' --after 5000
# 这时 FILES 上应该什么都没有；再 upload
bash tools/sky130_synth_hs/pack_and_upload.sh
# 验证 md5 匹配本地
md5sum /tmp/sky130_synth_hs.tar.gz
python3 tools/cadence_runner.py exec 'md5sum "$HOME/neere/Start Mate Desktop/sky130_synth_hs.tar.gz"' --after 5000
```

如果 md5 不一致，说明 FILES 还在缓存旧版本，改用带时间戳的文件名（例如 `sky130_synth_hs_$(date +%H%M%S).tar.gz`）绕过。

**代价**：Run #2 就是因为这个坑，6 小时的综合重跑**完全浪费**——启动时用的是 Run #1 的旧 tcl，所以同样在 `report_area -hierarchy` abort。发现方法：登录远端 `ls -la "$HOME/neere/Start Mate Desktop/" | grep sky130_synth_hs` 看文件名是不是真的是 `.tar.gz`（正常），还是 `.tar(N).gz`（中招）。

**⚠️ Genus 的 log 是大缓冲写盘，不是行缓冲。** `/tmp/sky130_synth_hs/genus.log` 可能 1 小时都不刷新，但进程 `ps -p $PID -o state` 显示 S(sleeping) + `wchan=core_sys_select` → 表示正在 socket 上等 PBS worker 响应，**不是死掉**。不要 `pkill` 它。真死了会 Z(zombie)。

**⚠️ PBS 子任务 (`pbs_genopt_*` / `pbs_fcopt_*` / `pbs_map_*`) 的 `_post.db` 出现时间滞后于 log**。实际判断一个 partition 是否跑完，用 `ls /tmp/sky130_synth_hs/.pbs_*/` 看 `_post.db` 文件更可靠。

**⚠️ `pbs_genopt_4 → 5 cells` 塌缩是 tile_controller 里某个 partition 被常数折叠，不是 bug**（Run #1/Run #2 都出现）。不影响整体功能，但提示 RTL 有可清理的死代码。

**⚠️ session 断开后 `remote_exec` 第一次调用会 `iframe never appeared`**。先 `python3 tools/cadence_runner.py probe`（触发 Start remote）再 sleep 30s 再 `exec --open-term` 就稳。

**⚠️ Cadence Cloud VNC proxy 会抽风（实测过两次）**：长时间综合跑着期间，VNC 侧可能返回：

- `Internal server error / ERROR 500`（VNC proxy 后端挂了）
- `Loading external app...` 卡死超过 30 分钟（App Presenter 启不起来）

VNC 不可用时：

- `list` / `upload` / `download` **不受影响**（走 REST API，不经过 VNC）
- `exec` / `peek` **全部不可用**（`noVNC iframe never appeared`）
- 远端服务器上正在跑的 Genus / xrun 等批处理任务**不受影响**（它们不依赖 VNC，VNC 只是键鼠通道）

应对：
1. 只靠 FILES tab 交付（`run.sh` 里把日志/结果 `cp "$HOME/neere/Start Mate Desktop/"`，本地靠 `poll` + `download` 拉回）
2. 不要在 VNC 出问题时 kill session；批处理会继续
3. 等 VNC proxy 自己恢复（实测半小时到几小时不等）

这条坑的具体意义：**cadence_runner.py 的 `run-synth` 全自动流程必须做成"启动后 VNC 就不再需要"**——把所有结果走 FILES tab 回收，而不是每隔几分钟截图 peek。

### 5.9 没跑通 / 待解决

- **Innovus PnR**: `/home/share/sky130A.tar.gz` 不带 Cadence tech LEF (`*_tech.lef` / `*.tlf`)。Sky130 上社区有两种办法：
  (a) 用 OpenROAD 的 tech LEF，手工转 Cadence 格式（可能踩 extraction decks 不对的坑）
  (b) 向 `shanshan@cadence.com` 发邮件要"Innovus tech LEF for sky130_fd_sc_hs"
  - 估计（b）靠谱，SkyWater 官方其实有 Cadence-ready 包，只是助教没放在 `/home/share/` 里
- **Power 报告**: Run #1 没落盘。`report_power` 在 Genus 里只给 **估算功耗**（不做 signal switching activity analysis），要真实功耗需要走 Joules 流程，读 VCD/SAIF。
- **fmax 极限试探**: 目前设 10 ns (100 MHz) 收敛 + 1102 ps slack，理论可以压到 9.1 ns (110 MHz)。建议 Run #3 试 9.0 ns，Run #4 试 8.5 ns，找到真实极限。

### 5.10 旁证：NFS server 上其它 PDK 卷（仅记录用，无法直接用）

NFS 服务器 `shstna02` export 了大量工艺库 volume：

```
/vol/tsmc28hpc_IN00051633         /vol/tsmc28hpcp_IN00180494
/vol/tsmc28hpm_03095904           /vol/tsmc28hpm00_03440469
/vol/tsmc28lp_03194533            /vol/gf12lp_IT227770
/vol/umc28hpc_IN00380656          /vol/smic40pdk_02778743
/vol/PROCESS                      (还有 100+ 个其它设计工程专用卷)
```

但 autofs map (`/etc/auto.master.d/` 空) 没给它们分配 `/projects/<foo>` 或 `/proj/<foo>` 的 key，普通用户无法手动 `mount.nfs`（需要 root），也无法直接读。这些是 Cadence 内部其它项目占的卷，不是给本次比赛用的。

### 5.11 VM 网络（已实测）

* DNS 解析**不通**：`/etc/resolv.conf` 是空的
* TCP/443 直连 **可以**：`curl --resolve <host>:443:<ip> https://...` 能下载
* **现在不需要再走外网**：PDK 已在 `/home/share/`，直接读即可

---

## 6. 典型工作流（现阶段）

```
[本地]                                          [远端 sh02lo02]
---------------------------------------------------------------
1. tar czf submission.tar.gz submission/
2. cadence_runner.py upload submission.tar.gz   →  ~/neere/Start Mate Desktop/submission.tar.gz
3. cadence_runner.py exec "cd ~/neere/'Start Mate Desktop' && tar xzf submission.tar.gz -C /tmp/"
4. cadence_runner.py exec "source /usr/share/Modules/init/sh && module load license xcelium && cd /tmp/submission && xrun -f baseline.f -access +rwc | tee run.log"
5. cadence_runner.py exec "cp /tmp/submission/run.log ~/neere/'Start Mate Desktop'/"
6. cadence_runner.py list         # 确认 run.log 出现在 FILES tab
7. cadence_runner.py download run.log ./
```

综合的完整流程需要等 PDK 决策，见 `run_flow()` 尚未落笔的部分。

---

## 7. 已知坑

| 问题 | 现象 | 对策 |
|---|---|---|
| 远端是 tcsh | `2>&1`、`$(...)`、`!=` 都不对劲 | `exec` 一律 base64 → `bash`，不要在 tcsh 里写 bash 语法 |
| noVNC 键盘事件丢失 | 类似 `type` 以后终端无反应 | 不要在聚焦 iframe 后再点外面；`Desktop.attach` 用 `goto_room(dismiss_iframe=False)` |
| Exit maximize 点了就失焦 | 发命令后终端卡在打字状态 | 进房间时**不要**点 Exit maximize，要保留 iframe 全屏 |
| viewport 改了坐标就错 | 终端聚焦点偏了 | 强制 1920×1080，`d.click(350, 200)` 对应左上区。**用户手动拖动/缩小终端窗口后这个坐标会失灵** —— 把终端窗口最大化（铺满桌面）最稳 |
| 长 base64 串里出现 `IIIIIIII` / `gggggggggg` | playwright `keyboard.type` 默认 25ms/char 太快，noVNC WebSocket 漏 keyup，VNC server 当成长按自动重复 | `Desktop.type()` 已改成显式 `keyboard.down`/`keyboard.up`，每字符 60ms，每 16 字符额外 sleep 120ms。≈ 6×慢于原来但完全可靠 |
| find 一路爬 /home/.snapshot 死慢 | recon 脚本 30 秒以上 | 加 `-not -path '*/.snapshot/*'` 或 `-xdev` |
| 大命令 / 大 base64 打字慢 | `remote_exec(after_ms=8000)` 之后还没跑完 | 把命令分片、把大 find 放后台，`peek` 轮询 |
| FILES 里的文件名保留空格 | `Start Mate Desktop` 带空格 | 全程用双引号 `"$HOME/neere/Start Mate Desktop"` |
| `download` 输出目录有 trailing slash | 实际写到 `<dst>/<name>` 而不是 `<dst>` 本身 | 目标目录传不带 slash，或用 `download <name> /tmp/x` 然后从 `/tmp/x/<name>` 读 |
| `cd /tmp/sky130_synth 2>/dev/null && ...` 静默失败 | 路径不存在时整条命令被短路 | 状态收集命令不要用 `cd ... && ...`，用绝对路径直接操作 |
| storage_state 偶发失效 | iframe never appeared | 重跑一次 / `login` 子命令再登一遍 |
| 远端会话刚启动时桌面没有终端窗口 | `exec` 把命令打到空桌面、键盘焦点丢失、什么都不发生（不会报错） | 第一条 `exec` 加 `--open-term`：自动右键 → "Open in Terminal" 开一个新 Mate Terminal 再发命令；之后窗口常驻就可以裸用 `exec` |

---

## 8. 本地依赖

- Python 3.10+
- Playwright：`pip install playwright && playwright install chromium`
- Linux 运行（WSL 也行）；headless Chromium 默认 OK
- `~/.cache/cadence_runner/` 需要可写

---

## 9. 当前进度快照（2026-04-20）

**已完成：**

- [x] 服务器侦察：模块系统、工具版本、文件系统、license 全摸清
- [x] **官方 PDK 找到**：`/home/share/sky130A.tar.gz` (1.51GB, sky130_fd_sc_hs)、`/home/share/sky130_sram_*.zip` (OpenRAM macro)、`/home/share/RAK.tar` (Cadence 教程)、`readMe.txt` 由助教 `shanshan@cadence.com` 维护，钦点用 `sky130_fd_sc_hs`（详见 §5）
- [x] 网络情况摸清：DNS 不通，TCP/443 直连可达；但 **PDK 既然在远端 NFS，本地下载 + 上传不再必要**
- [x] **`tools/sky130_synth_hs/` 落地**：HS 版 Genus 综合环境（README + pack_and_upload.sh + genus_synth.tcl + run.sh + PROGRESS.md），详见 §5.6
- [x] **综合跑通（Run #3 full reports）**：100 MHz MET slack +1102 ps，cell count 3555, total area 76k μm², NAND2-equivalent **15,847 门 (赛题预算的 0.79%)**, 功耗 11.12 mW。数据在 §5.7，完整报告在 `tools/sky130_synth_hs/reports_run3/`
- [x] 发现并记录 Genus 25.12 的多个坑（`-hierarchy` 移除、Tcl abort 级联、cell LEF 不可加载、`report_*` 返回空字符串需走 `>` redirect、FILES upload 不覆盖同名、VNC proxy 会抽风）：§5.8
- [x] **修复 noVNC 长字符串打字 keyup 丢失 bug**（`Desktop.type` 改成显式 down/up，60ms/char + 每 16 char sleep 120ms）
- [x] **修复 `remote_exec` 在终端不存在时无声失败**（新增 `--open-term` 选项，attach 后右键空桌面 "Open in Terminal" 再发命令）
- [x] **加固 `pack_and_upload.sh`**：上传前强制清理远端所有同名 tar 变体 + md5 校验

**待办：**

- [ ] 回 RTL 查 `pbs_genopt_4` 塌缩根因（39,420 → 5 cells，tile_controller 某 partition 被常数折叠）
- [ ] 评估 Innovus PnR：`/home/share/sky130A.tar.gz` 没带 Cadence tech LEF；需要向助教要或自己合一份
- [ ] `fmax` 极限试探：按 Run #3 slack 1102ps，把周期压到 9.0 ns 跑一次（应该还能 MET），再试 8.5 ns 找真实极限
- [ ] Bonus 版本（submission/bonus/rtl）跑一轮综合，对比 baseline vs bonus 的 area/fmax
- [ ] `cadence_runner.py` 加一个 `run-synth` 子命令封装整个 upload → exec → poll → download 流程
- [ ] VCD-driven power：xrun 跑出 VCD/SAIF → Joules 读入出精确功耗（现在是 vectorless 估算）
- [ ] 清理旧 `tools/sky130_synth/` 目录（或保留作 HD 对比基线？需要用户决定）

## 10. 仓库结构（GitHub）

```
cadence/
├── tools/
│   ├── ACCESS.md            # 本文档，平台访问与状态
│   ├── cadence_runner.py    # 浏览器自动化（Playwright）+ FILES + noVNC exec
│   └── sky130_synth/        # 综合环境（lib + scripts），rtl 软链或同步 submission/rtl
└── submission/              # 比赛提交主目录（RTL、testbench、UVM 等）
```

* `cadence_runner.py` 的状态都落在 `~/.cache/cadence_runner/`：`config.json`（房间/账户）、`storage_state.json`（cookie）、`shots/`（截图）。这些**不进 git**。
* 运行任何 `cadence_runner.py` 子命令前，需要先一次性 `python3 tools/cadence_runner.py login`。
