// ============================================================
// FlashAttention 加速器 — 全局参数定义
// ============================================================

// --- 基本固定维度 ---
parameter 序列长度       = 256;
parameter 头维度         = 64;

// --- 分块参数 ---
parameter Q分块行数      = 4;      // 每个Q分块包含的行数
parameter KV分块行数     = 16;     // 每个K/V分块包含的行数
parameter Q分块总数      = 序列长度 / Q分块行数;    // 256/4 = 64
parameter KV分块总数     = 序列长度 / KV分块行数;   // 256/16 = 16

// --- 数据位宽 ---
parameter 数据位宽       = 16;     // Q8.8 定点数格式
parameter 小数位数       = 8;      // Q8.8 的小数部分位数
parameter 累加器位宽     = 40;     // 点积累加器位宽（防溢出）
parameter 指数输出位宽   = 24;     // exp输出位宽（更宽以保持精度）
parameter 分数中间位宽   = 40;     // score/softmax中间值位宽

// --- AXI总线参数 ---
parameter AXI地址位宽    = 64;
parameter AXI数据位宽    = 128;    // 每次传输128位 = 8个Q8.8值
parameter AXI_ID位宽     = 4;
parameter AXI写选通位宽  = AXI数据位宽 / 8;

parameter AXIL地址位宽   = 8;      // AXI4-Lite 地址位宽
parameter AXIL数据位宽   = 32;     // AXI4-Lite 数据位宽

// --- AXI突发参数 ---
parameter AXI突发长度    = 16;     // 每次突发传输的节拍数

// --- 寄存器地址映射 ---
parameter 寄存器_控制         = 8'h00;   // 控制寄存器
parameter 寄存器_状态         = 8'h04;   // 状态寄存器
parameter 寄存器_配置         = 8'h08;   // 配置寄存器
parameter 寄存器_Q基地址低    = 8'h14;   // Q矩阵基地址低32位
parameter 寄存器_Q基地址高    = 8'h18;   // Q矩阵基地址高32位
parameter 寄存器_K基地址低    = 8'h1C;   // K矩阵基地址低32位
parameter 寄存器_K基地址高    = 8'h20;   // K矩阵基地址高32位
parameter 寄存器_V基地址低    = 8'h24;   // V矩阵基地址低32位
parameter 寄存器_V基地址高    = 8'h28;   // V矩阵基地址高32位
parameter 寄存器_O基地址低    = 8'h2C;   // O(输出)矩阵基地址低32位
parameter 寄存器_O基地址高    = 8'h30;   // O(输出)矩阵基地址高32位
parameter 寄存器_行步长       = 8'h34;   // 矩阵行步长（字节）
parameter 寄存器_负大值       = 8'h38;   // 掩码填充用的负大数
parameter 寄存器_缩放因子     = 8'h3C;   // 注意力分数缩放因子 1/√d
parameter 寄存器_周期计数     = 8'h40;   // 运行周期计数器

// --- 控制寄存器各位定义 ---
parameter 控制位_启动       = 0;    // 写1启动计算
parameter 控制位_软复位     = 1;    // 写1软复位
parameter 控制位_中断使能   = 2;    // 写1使能中断

// --- 状态寄存器各位定义 ---
parameter 状态位_忙碌       = 0;    // 正在计算中
parameter 状态位_完成       = 1;    // 计算完成
parameter 状态位_错误       = 2;    // 发生错误

// --- 配置寄存器各位定义 ---
parameter 配置位_因果掩码使能 = 0;  // 使能因果（下三角）掩码

// --- 默认值 ---
parameter 默认行步长       = 头维度 * 2;            // d × sizeof(Q8.8) = 64×2 = 128字节
parameter 默认负大值       = 16'h8000;              // -128.0（Q8.8格式）
parameter 默认缩放因子     = 16'h0020;              // 1/8 ≈ 1/√64（Q8.8格式）

// --- 并行度 ---
parameter 并行乘累加数     = 8;     // 每个点积单元每周期执行8个乘累加

// --- 指数查找表 ---
parameter 指数查找表深度   = 256;
parameter 指数查找表位宽   = 16;
