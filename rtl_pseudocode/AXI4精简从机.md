# AXI4-Lite 从机 + 寄存器 (`axi4_lite_slave.sv`)

> 该模块是控制面入口：软件通过 AXI4-Lite 写寄存器完成参数配置、启动计算、读取状态与性能计数。
> 
> 对照 RTL：`rtl/axi4_lite_slave.sv`

---

## 1. 模块定位（结合顶层）

在顶层 `flash_attention_top.sv` 中，本模块负责两件事：

1. 把 AXI4-Lite 总线请求映射到寄存器文件。
2. 把寄存器内容导出为数据通路控制信号：
   - `寄存器_启动`（启动脉冲）
   - `寄存器_软复位`（软复位脉冲）
   - `寄存器_因果掩码使能`
   - `寄存器_Q/K/V/O基地址`、`寄存器_行步长`、`寄存器_负大值`、`寄存器_缩放因子`

并接收状态输入：`状态_忙碌`、`状态_完成`、`状态_错误`、`周期计数`。

---

## 2. AXI4-Lite 握手策略（源码真实行为）

### 写通道

```pseudocode
复位后:
  awready = 1
  wready  = 1
  bresp   = OKAY

当 awvalid & awready & wvalid & wready 同拍为1时:
  执行寄存器写入
  bvalid = 1

当 bvalid & bready:
  bvalid 清0
```

要点：

1. 本实现要求写地址和写数据同拍有效才会写入。
2. `从机_写选通(wstrb)`当前未参与字节掩码，行为等价于整字写。
3. `bresp`固定 `2'b00`（OKAY），未实现错误返回。

### 读通道

```pseudocode
复位后:
  arready = 1
  rresp   = OKAY

当 arvalid & arready:
  根据 araddr 选择寄存器值
  rvalid = 1

当 rvalid & rready:
  rvalid 清0
```

要点：

1. 读地址命中后立即给出数据并拉高 `rvalid`。
2. `rresp`固定 `2'b00`（OKAY）。

---

## 3. 寄存器地址映射（0x00~0x40）

> 地址位宽为 8 bit，寄存器空间 256B。有效地址集中在 `0x00~0x40`。

| 地址 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| `0x00` | `CTRL` | RW | `0` | bit0=START(写1触发脉冲)；bit1=SOFT_RESET(写1触发脉冲)；bit2=IRQ_EN（电平配置） |
| `0x04` | `STATUS` | R / W1C | `0` | 读回 `{29'd0, error, done_sticky, busy}`；写 bit1=1 清 `done_sticky` |
| `0x08` | `CFG` | RW | `0` | bit0=因果掩码使能 |
| `0x14` | `Q_BASE_LO` | RW | `0` | Q基地址低32位 |
| `0x18` | `Q_BASE_HI` | RW | `0` | Q基地址高32位 |
| `0x1C` | `K_BASE_LO` | RW | `0` | K基地址低32位 |
| `0x20` | `K_BASE_HI` | RW | `0` | K基地址高32位 |
| `0x24` | `V_BASE_LO` | RW | `0` | V基地址低32位 |
| `0x28` | `V_BASE_HI` | RW | `0` | V基地址高32位 |
| `0x2C` | `O_BASE_LO` | RW | `0` | O基地址低32位 |
| `0x30` | `O_BASE_HI` | RW | `0` | O基地址高32位 |
| `0x34` | `STRIDE` | RW | `128` | 行步长（字节） |
| `0x38` | `NEG_LARGE` | RW | `0xFFFF8000` | 默认 -128.0（定点）；输出只取低16位 |
| `0x3C` | `SCALE` | RW | `0x00000020` | 默认 1/8（Q8.8可表示为0x20）；输出只取低16位 |
| `0x40` | `CYCLES` | RO | `0` | 周期计数输入透传 |

无效地址读返回：`0xDEADBEEF`。

---

## 4. 脉冲信号与粘滞位

### 4.1 启动/软复位/完成清除都是脉冲

RTL 每拍默认会清零：

```pseudocode
寄存器_启动   <= 0
寄存器_软复位 <= 0
完成清除      <= 0
```

只有命中写地址且对应位写1时才拉高一拍。

### 4.2 完成粘滞位 `done_sticky`

```pseudocode
if (状态_完成) done_sticky = 1
if (写 STATUS 且 wdata[1]==1) done_sticky = 0
```

意义：避免软件轮询间隔过大错过 `状态_完成` 瞬时脉冲。

---

## 5. 输出信号组合关系

```pseudocode
寄存器_中断使能     = CTRL[2]
寄存器_因果掩码使能 = CFG[0]

寄存器_Q基地址 = {Q_BASE_HI, Q_BASE_LO}
寄存器_K基地址 = {K_BASE_HI, K_BASE_LO}
寄存器_V基地址 = {V_BASE_HI, V_BASE_LO}
寄存器_O基地址 = {O_BASE_HI, O_BASE_LO}

寄存器_负大值   = NEG_LARGE[15:0]
寄存器_缩放因子 = SCALE[15:0]

中断 = 寄存器_中断使能 & done_sticky
```

---

## 6. 典型软件访问流程（建议）

```pseudocode
1) 写 CFG/STRIDE/NEG_LARGE/SCALE
2) 写 Q/K/V/O 基地址（低32再高32）
3) 写 CTRL[2] 配置是否使能中断
4) 写 CTRL[0]=1 触发 START 脉冲
5) 轮询 STATUS 或等待中断:
     STATUS[0]=busy
     STATUS[1]=done_sticky
     STATUS[2]=error
6) 读 CYCLES 获取性能计数
7) 写 STATUS[1]=1 清 done_sticky（W1C）
```

---

## 7. 实现边界与注意事项

1. 这是简化型 AXI4-Lite 从机，不支持错误响应编码区分（始终 OKAY）。
2. 写入要求 `AW` 与 `W` 同拍握手，主机驱动应满足该时序习惯。
3. 未实现按 `WSTRB` 的字节写屏蔽；软件应按 32bit 全字写寄存器。
4. `CTRL` 中 bit0/bit1 写1是“触发动作”，不是长电平使能。
