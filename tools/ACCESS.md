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

## 5. PDK / 标准单元库（**平台没装**，需自带）

### 5.1 结论

平台 **没有安装任何 PDK / 标准单元库**。已经用官方流程做了决定性验证：

1. `module avail pdk` 空
2. 官方 `pdkFinder.csh`（`/apps/cc/utils/pdkFinder.csh`）跑出来的 `pdkList.csv` **只有表头**
3. `module avail` 总共只显示：`ddi/251/25.12.000  jasper/2509/25.09.002  license  xcelium/2409/24.09.006`

### 5.2 扫描覆盖范围

以下都翻过、都没有标准单元 / LEF / Liberty：

| 路径 | 是什么 |
|---|---|
| `/apps/*` | 只有 `DDI251`、`XCELIUM2409`、`cc`，无 PDK |
| `/apps/cc/*` | 管理脚本 & 桌面元素 |
| `/cc`, `/proj`, `/projects` | autofs indirect map，key 不存在 |
| `/grid/common` | 系统共享库 `.so`（graphviz、motif、gcc runtime 等），不是 EDA 库 |
| `/home/cm_admin/*` | license、modulefiles、web 后台 |
| `/opt` | 系统工具，无关 |
| `$HOME/Documents`, `$HOME/Public`, `$HOME/Downloads` | 空 |
| `/apps/DDI251/25.12.000/share/synth/lib/` | 只有 Tcl/Tk/verilog 代码（Genus 自带脚本库），**不是**标准单元 |

### 5.3 有意思的旁证

NFS 服务器 `shstna02` 确实 export 了大量工艺库 volume（`showmount -e shstna02 | grep -iE 'tsmc|gf|umc|smic|pdk'`）：

```
/vol/tsmc28hpc_IN00051633         /vol/tsmc28hpcp_IN00180494
/vol/tsmc28hpm_03095904           /vol/tsmc28hpm00_03440469
/vol/tsmc28lp_03194533            /vol/gf12lp_IT227770
/vol/umc28hpc_IN00380656          /vol/smic40pdk_02778743
/vol/PROCESS                      (还有 100+ 个其它设计工程专用卷)
```

**但是**：本机 autofs map 没有给它们分配 `/projects/<foo>` 或 `/proj/<foo>` 的 key，普通用户**无法手动 `mount.nfs`**（需要 root）。`autoproj list` 也失败（`/home/cm_admin/autoproj` 都不存在）。

### 5.4 路线选择

| 方案 | 可行性 | 代价 |
|---|---|---|
| 联系管理员要求挂载 PDK 模块 | 最标准 | 得打 ticket，不可控 |
| 自带自己有版权的 PDK（TSMC / SMIC edu 等） | 可行 | 要确认版权合规 |
| 用开源 PDK（Sky130、NanGate45、FreePDK45、ASAP7） | 可行 | 需从本地下载好后整包上传（VM 未验证能不能上公网） |
| 跳过综合，只做 xrun 仿真 | 现在就能跑 | 拿不到面积/时序/功耗报告 |
| Genus `generic` lib 空跑 elab | 现在就能跑 | 只能验证 RTL 语法/层次，无真实指标 |

### 5.5 VM 网络（已实测）

* DNS 解析**不通**：`/etc/resolv.conf` 是空的，`curl https://github.com` 直接 `Could not resolve host`。
* TCP/443 直连 **可以**：`curl --resolve raw.githubusercontent.com:443:185.199.108.133 https://raw.githubusercontent.com/...` 能下载到内容。
* 实际选择：**先本地下载 → 打 tar → FILES 上传** 仍是最稳的路子，避免每次都猜 GitHub Pages CDN IP。

### 5.6 已落地：Sky130 综合环境

仓库的 `tools/` 目录里已经准备好了一个 Sky130 综合包结构（`sky130_synth/`），包括：

```
sky130_synth/
├── lib/
│   └── sky130_fd_sc_hd__tt_025C_1v80.lib   # 12.8 MB，从 efabless/skywater-pdk-libs-sky130_fd_sc_hd 拉的 typical 角
├── rtl/                                     # 从 submission/rtl 同步过来
├── scripts/
│   ├── genus_synth.tcl                      # Genus 综合脚本（read_hdl → elaborate → syn_generic → syn_map → syn_opt → reports）
│   └── run.sh                               # bash 驱动器：source modules → genus -batch → tar 结果到 FILES
```

打包上传执行：

```bash
tar czf sky130_synth.tar.gz sky130_synth/
python3 tools/cadence_runner.py upload sky130_synth.tar.gz
python3 tools/cadence_runner.py exec 'cd /tmp && tar xzf "$HOME/neere/Start Mate Desktop/sky130_synth.tar.gz"'
python3 tools/cadence_runner.py exec 'cd /tmp/sky130_synth && nohup bash scripts/run.sh > /tmp/sky130_synth/genus_run.log 2>&1 &'
```

实测：`flash_attention_top` 在 Sky130 上 generic 后膨胀到 **3,751,602 cells**，分 6 个 PBS partition 并行优化（最大单个 197 万 cells），`syn_generic` 阶段需要 30min - 2h，整轮 + map + opt 容易超过 2 小时。内存峰值 ~15 GB。

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

---

## 8. 本地依赖

- Python 3.10+
- Playwright：`pip install playwright && playwright install chromium`
- Linux 运行（WSL 也行）；headless Chromium 默认 OK
- `~/.cache/cadence_runner/` 需要可写

---

## 9. 当前进度快照（2026-04-20 凌晨）

**已完成：**

- [x] 服务器侦察：模块系统、工具版本、文件系统、license 全摸清，无 PDK 这件事拿到决定性证据
- [x] 网络情况摸清：DNS 不通，TCP/443 直连可达，结论是走"本地下载 + FILES 上传"
- [x] Sky130 typical 角 liberty (`sky130_fd_sc_hd__tt_025C_1v80.lib`, 12.8MB) 拉到本地
- [x] Genus Tcl 脚本 + bash 驱动写好，整包 tar 上传到 FILES
- [x] 远端解压、`module load license ddi`、`nohup genus -batch -no_gui -files scripts/genus_synth.tcl` 已经在跑（PID 1800373，6 partition × 8 super-thread workers，phys mem 15GB peak）
- [x] **修复 noVNC 长字符串打字 keyup 丢失 bug**（`Desktop.type` 改成显式 down/up，60ms/char + 每 16 char sleep 120ms）

**进行中：**

- [ ] 等 `syn_generic` / `syn_map` / `syn_opt` 完成（按 syn_generic 已用 7+ 分钟、最大 partition 1.98M cells 估算总时长 1-3h）

**待办：**

- [ ] `run.sh` 跑完会自动把 `reports/` + `results/` + `genus_run.log` 打成 `sky130_synth_result_<TS>.tar.gz` 落到 FILES，下载下来分析
- [ ] 解析 timing / area / power / qor 报告
- [ ] 关注 `pbs_genopt_4` 那块 39428 → 5 cells 的塌缩，回头查 RTL 是否有未使用 / 复位锁死的死代码
- [ ] `run_flow()` 全自动化补齐：upload → exec → poll → download → 解析

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
