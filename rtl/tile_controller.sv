// ============================================================
// 分块控制器
// 管理分块循环：遍历所有Q分块和KV分块
// 生成DMA传输地址，控制计算核心的启停
// ============================================================
module 分块控制器 #(
    parameter 序列长度         = 256,
    parameter 头维度           = 64,
    parameter Q分块行数        = 4,
    parameter KV分块行数       = 16,
    parameter AXI地址位宽      = 64,
    parameter 数据位宽         = 16
)(
    input  logic                          时钟,
    input  logic                          复位_低有效,

    // 启动 / 完成 信号（来自主状态机）
    input  logic                          启动,
    output logic                          全部完成,
    output logic                          忙碌,

    // 配置寄存器输入
    input  logic [AXI地址位宽-1:0]        Q基地址,
    input  logic [AXI地址位宽-1:0]        K基地址,
    input  logic [AXI地址位宽-1:0]        V基地址,
    input  logic [AXI地址位宽-1:0]        O基地址,
    input  logic [31:0]                   行步长,

    // DMA读请求接口
    output logic                          DMA读请求,
    output logic [AXI地址位宽-1:0]        DMA读地址,
    output logic [15:0]                   DMA读长度_字节,
    output logic [1:0]                    DMA读目标,    // 0=Q, 1=K, 2=V
    input  logic                          DMA读完成,

    // DMA写请求接口
    output logic                          DMA写请求,
    output logic [AXI地址位宽-1:0]        DMA写地址,
    output logic [15:0]                   DMA写长度_字节,
    input  logic                          DMA写完成,

    // 计算核心控制接口
    output logic                          计算启动,
    output logic                          首个KV分块,   // 标识当前是否为该Q分块的第一个KV分块
    output logic                          末个KV分块,   // 标识当前是否为该Q分块的最后一个KV分块
    input  logic                          计算完成,

    // 分块索引（用于因果掩码）
    output logic [$clog2(序列长度)-1:0]   Q分块索引,
    output logic [$clog2(序列长度)-1:0]   KV分块索引,

    // 缓冲选择（乒乓双缓冲）
    output logic                          KV缓冲选择,

    // O矩阵回写触发
    output logic                          O回写启动,
    input  logic                          O回写完成
);

    // 局部常量
    localparam Q分块总数     = 序列长度 / Q分块行数;                       // 256/4 = 64
    localparam KV分块总数    = 序列长度 / KV分块行数;                      // 256/16 = 16
    localparam Q分块字节数   = Q分块行数 * 头维度 * (数据位宽 / 8);        // 4×64×2 = 512字节
    localparam KV分块字节数  = KV分块行数 * 头维度 * (数据位宽 / 8);       // 16×64×2 = 2048字节
    localparam O分块字节数   = Q分块行数 * 头维度 * (数据位宽 / 8);        // 4×64×2 = 512字节

    // 状态机定义
    typedef enum logic [3:0] {
        空闲,            // 等待启动信号
        加载Q,           // 发起Q分块的DMA读请求
        等待Q加载,       // 等待Q分块DMA读完成
        加载KV,          // 发起K分块的DMA读请求
        等待KV加载,      // 等待K分块DMA读完成（完成后自动加载V）
        启动计算,        // 等待V加载完成后启动计算
        等待计算完成,    // 等待计算核心完成
        下一个KV,        // 判断是否还有KV分块需要处理
        写回O,           // 发起O分块的DMA写请求
        等待O写回,       // 等待O分块DMA写完成
        下一个Q,         // 判断是否还有Q分块需要处理
        全部处理完成     // 所有分块计算完毕
    } 状态类型;

    状态类型 当前状态;
    logic [$clog2(Q分块总数):0]  Q索引;    // 当前Q分块编号
    logic [$clog2(KV分块总数):0] KV索引;   // 当前KV分块编号

    assign Q分块索引  = $clog2(序列长度)'(Q索引);
    assign KV分块索引 = $clog2(序列长度)'(KV索引);

    always_ff @(posedge 时钟 or negedge 复位_低有效) begin
        if (!复位_低有效) begin
            当前状态       <= 空闲;
            全部完成       <= 1'b0;
            忙碌           <= 1'b0;
            Q索引          <= '0;
            KV索引         <= '0;
            KV缓冲选择     <= 1'b0;
            DMA读请求      <= 1'b0;
            DMA写请求      <= 1'b0;
            计算启动       <= 1'b0;
            首个KV分块     <= 1'b0;
            末个KV分块     <= 1'b0;
            O回写启动      <= 1'b0;
        end else begin
            全部完成       <= 1'b0;
            计算启动       <= 1'b0;
            O回写启动      <= 1'b0;

            case (当前状态)
                // ---- 空闲状态：等待启动 ----
                空闲: begin
                    DMA读请求 <= 1'b0;
                    DMA写请求 <= 1'b0;
                    if (启动) begin
                        当前状态 <= 加载Q;
                        忙碌     <= 1'b1;
                        Q索引    <= '0;
                        KV索引   <= '0;
                    end
                end

                // ---- 加载Q分块：发起DMA读请求 ----
                加载Q: begin
                    DMA读请求      <= 1'b1;
                    // 地址 = Q基地址 + Q索引 × 行步长 × Q分块行数
                    DMA读地址      <= Q基地址 + AXI地址位宽'(Q索引) * AXI地址位宽'(行步长) * Q分块行数;
                    DMA读长度_字节 <= Q分块字节数;
                    DMA读目标      <= 2'd0;   // 目标：Q缓冲
                    当前状态       <= 等待Q加载;
                end

                // ---- 等待Q加载完成 ----
                等待Q加载: begin
                    DMA读请求 <= 1'b0;
                    if (DMA读完成) begin
                        KV索引     <= '0;
                        KV缓冲选择 <= 1'b0;
                        当前状态   <= 加载KV;
                    end
                end

                // ---- 加载K分块：发起DMA读请求 ----
                加载KV: begin
                    DMA读请求      <= 1'b1;
                    // 地址 = K基地址 + KV索引 × 行步长 × KV分块行数
                    DMA读地址      <= K基地址 + AXI地址位宽'(KV索引) * AXI地址位宽'(行步长) * KV分块行数;
                    DMA读长度_字节 <= KV分块字节数;
                    DMA读目标      <= 2'd1;   // 目标：K缓冲
                    当前状态       <= 等待KV加载;
                end

                // ---- 等待K加载完成，然后自动加载V ----
                等待KV加载: begin
                    DMA读请求 <= 1'b0;
                    if (DMA读完成) begin
                        // K加载完毕，立即发起V加载
                        DMA读请求      <= 1'b1;
                        DMA读地址      <= V基地址 + AXI地址位宽'(KV索引) * AXI地址位宽'(行步长) * KV分块行数;
                        DMA读长度_字节 <= KV分块字节数;
                        DMA读目标      <= 2'd2;   // 目标：V缓冲
                        当前状态       <= 启动计算;
                    end
                end

                // ---- 等待V加载完成，然后启动计算 ----
                启动计算: begin
                    DMA读请求 <= 1'b0;
                    if (DMA读完成) begin
                        计算启动   <= 1'b1;
                        首个KV分块 <= (KV索引 == 0);
                        末个KV分块 <= (KV索引 == KV分块总数 - 1);
                        当前状态   <= 等待计算完成;
                    end
                end

                // ---- 等待计算核心完成 ----
                等待计算完成: begin
                    if (计算完成) begin
                        当前状态 <= 下一个KV;
                    end
                end

                // ---- 判断是否还有KV分块 ----
                下一个KV: begin
                    if (KV索引 == KV分块总数 - 1) begin
                        // 所有KV分块处理完毕，写回O
                        当前状态 <= 写回O;
                    end else begin
                        // 还有KV分块，继续加载
                        KV索引     <= KV索引 + 1;
                        KV缓冲选择 <= ~KV缓冲选择;  // 切换乒乓缓冲
                        当前状态   <= 加载KV;
                    end
                end

                // ---- 发起O分块写回的DMA写请求 ----
                写回O: begin
                    DMA写请求      <= 1'b1;
                    // 地址 = O基地址 + Q索引 × 行步长 × Q分块行数
                    DMA写地址      <= O基地址 + AXI地址位宽'(Q索引) * AXI地址位宽'(行步长) * Q分块行数;
                    DMA写长度_字节 <= O分块字节数;
                    O回写启动      <= 1'b1;
                    当前状态       <= 等待O写回;
                end

                // ---- 等待O写回完成 ----
                等待O写回: begin
                    if (DMA写完成) begin
                        DMA写请求 <= 1'b0;
                        当前状态  <= 下一个Q;
                    end
                end

                // ---- 判断是否还有Q分块 ----
                下一个Q: begin
                    if (Q索引 == Q分块总数 - 1) begin
                        // 所有Q分块处理完毕
                        当前状态 <= 全部处理完成;
                    end else begin
                        Q索引    <= Q索引 + 1;
                        当前状态 <= 加载Q;
                    end
                end

                // ---- 全部完成 ----
                全部处理完成: begin
                    全部完成 <= 1'b1;
                    忙碌     <= 1'b0;
                    当前状态 <= 空闲;
                end
            endcase
        end
    end

endmodule
