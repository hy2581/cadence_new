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
| FILES tab 上传 / 下载 / 删除文件 | ✅ |
| 驱动 noVNC 做键鼠 → 远端 Mate Terminal | ✅ |
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

### 5.6 综合脚本应该怎么改（建议）

旧版本 `tools/sky130_synth/` 用的是 `sky130_fd_sc_hd__tt_025C_1v80.lib`（HD 高密度），现在应改用赛题指定的 `sky130_fd_sc_hs__tt_025C_1v80.lib`（HS 高速）。流程：

```bash
# 远端解压一次 PDK 到 /tmp 上（1.51GB tar，xz 解大约 20-40 秒）
python3 tools/cadence_runner.py exec '
mkdir -p /tmp/sky130_pdk &&
cd /tmp/sky130_pdk &&
tar xzf /home/share/sky130A.tar.gz &&
ls -la sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib
' --after 60000

# Genus 脚本里把 lib 路径切换为：
#   /tmp/sky130_pdk/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib
# 不再需要本地 tar 上传 lib 文件
```

预期收益：
1. **报告变成"赛事认可的"**：评委按赛题钦点的库评指标，HD 综合数据不算数
2. **省 12.8 MB 上传**：lib 直接走远端 NFS
3. **HS 比 HD 通常时序更优、面积更大**：FlashAttention 这种 dataflow-heavy 设计在 HS 上 fmax 应该更高

### 5.7 旁证：NFS server 上其它 PDK 卷（仅记录用，无法直接用）

NFS 服务器 `shstna02` export 了大量工艺库 volume：

```
/vol/tsmc28hpc_IN00051633         /vol/tsmc28hpcp_IN00180494
/vol/tsmc28hpm_03095904           /vol/tsmc28hpm00_03440469
/vol/tsmc28lp_03194533            /vol/gf12lp_IT227770
/vol/umc28hpc_IN00380656          /vol/smic40pdk_02778743
/vol/PROCESS                      (还有 100+ 个其它设计工程专用卷)
```

但 autofs map (`/etc/auto.master.d/` 空) 没给它们分配 `/projects/<foo>` 或 `/proj/<foo>` 的 key，普通用户无法手动 `mount.nfs`（需要 root），也无法直接读。这些是 Cadence 内部其它项目占的卷，不是给本次比赛用的。

### 5.8 VM 网络（已实测）

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
- [x] 旧版本 Sky130 综合环境已经跑通（用的是 `sky130_fd_sc_hd`，**不符合赛题钦点**，需切到 `_hs`）
- [x] **修复 noVNC 长字符串打字 keyup 丢失 bug**（`Desktop.type` 改成显式 down/up，60ms/char + 每 16 char sleep 120ms）
- [x] **修复 `remote_exec` 在终端不存在时无声失败**（新增 `--open-term` 选项，attach 后右键空桌面 "Open in Terminal" 再发命令）

**进行中：**

- [ ] 把 `tools/sky130_synth/` 切到 `sky130_fd_sc_hs__tt_025C_1v80.lib`，重跑 Genus，对比 HD/HS 数据
- [ ] `tools/sky130_synth/` lib/ 目录可以删掉，改成在 `run.sh` 里 `tar xzf /home/share/sky130A.tar.gz -C /tmp/sky130_pdk` 引用远端 PDK

**待办：**

- [ ] `run.sh` 跑完自动把 `reports/` + `results/` + `genus_run.log` 打成 `sky130_synth_result_<TS>.tar.gz` 落到 FILES，下载分析
- [ ] 解析 timing / area / power / qor 报告
- [ ] 关注 `pbs_genopt_4` 那块 39428 → 5 cells 的塌缩，回头查 RTL 是否有未使用 / 复位锁死的死代码
- [ ] `run_flow()` 全自动化补齐：upload → exec → poll → download → 解析
- [ ] 评估 Innovus PnR 流程是否需要找 `sky130_fd_sc_hs__tech.lef`（PDK tar 里没带 cadence 专用 tech LEF）

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
