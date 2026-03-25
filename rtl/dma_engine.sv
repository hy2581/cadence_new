// ============================================================
// DMA引擎
// 桥接分块控制器的读写请求与AXI4主机事务
// 读数据路由：将AXI读回的数据分发到Q/K/V缓冲
// 写数据路由：将O缓冲数据通过AXI写回外部存储器
// ============================================================
module DMA引擎 #(
    parameter AXI地址位宽   = 64,
    parameter AXI数据位宽   = 128,
    parameter AXI_ID位宽    = 4,
    parameter Q分块行数     = 4,
    parameter KV分块行数    = 16,
    parameter 头维度        = 64,
    parameter 数据位宽      = 16
)(
    input  logic                    时钟,
    input  logic                    复位_低有效,

    // --- AXI4 主机端口（直连外部AXI4接口） ---
    // 写地址通道
    output logic [AXI_ID位宽-1:0]      主机_写地址ID,
    output logic [AXI地址位宽-1:0]     主机_写地址,
    output logic [7:0]                 主机_写突发长度,
    output logic [2:0]                 主机_写突发大小,
    output logic [1:0]                 主机_写突发类型,
    output logic                       主机_写地址有效,
    input  logic                       主机_写地址就绪,
    // 写数据通道
    output logic [AXI数据位宽-1:0]     主机_写数据,
    output logic [AXI数据位宽/8-1:0]   主机_写选通,
    output logic                       主机_写最后一拍,
    output logic                       主机_写数据有效,
    input  logic                       主机_写数据就绪,
    // 写响应通道
    input  logic [AXI_ID位宽-1:0]      主机_写响应ID,
    input  logic [1:0]                 主机_写响应,
    input  logic                       主机_写响应有效,
    output logic                       主机_写响应就绪,
    // 读地址通道
    output logic [AXI_ID位宽-1:0]      主机_读地址ID,
    output logic [AXI地址位宽-1:0]     主机_读地址,
    output logic [7:0]                 主机_读突发长度,
    output logic [2:0]                 主机_读突发大小,
    output logic [1:0]                 主机_读突发类型,
    output logic                       主机_读地址有效,
    input  logic                       主机_读地址就绪,
    // 读数据通道
    input  logic [AXI_ID位宽-1:0]      主机_读数据ID,
    input  logic [AXI数据位宽-1:0]     主机_读数据,
    input  logic [1:0]                 主机_读响应,
    input  logic                       主机_读最后一拍,
    input  logic                       主机_读数据有效,
    output logic                       主机_读数据就绪,

    // --- 分块控制器接口 ---
    // 读请求
    input  logic                       DMA读请求,
    input  logic [AXI地址位宽-1:0]     DMA读地址,
    input  logic [15:0]                DMA读长度_字节,
    input  logic [1:0]                 DMA读目标,     // 0=Q缓冲, 1=K缓冲, 2=V缓冲
    output logic                       DMA读完成,
    // 写请求
    input  logic                       DMA写请求,
    input  logic [AXI地址位宽-1:0]     DMA写地址,
    input  logic [15:0]                DMA写长度_字节,
    output logic                       DMA写完成,

    // --- 缓冲写接口（Q/K/V写入） ---
    output logic                       缓冲_Q写使能,
    output logic [$clog2(Q分块行数*头维度)-1:0] 缓冲_Q写地址,
    output logic [AXI数据位宽-1:0]     缓冲_Q写数据,

    output logic                       缓冲_K写使能,
    output logic [$clog2(KV分块行数*头维度)-1:0] 缓冲_K写地址,
    output logic [AXI数据位宽-1:0]     缓冲_K写数据,

    output logic                       缓冲_V写使能,
    output logic [$clog2(KV分块行数*头维度)-1:0] 缓冲_V写地址,
    output logic [AXI数据位宽-1:0]     缓冲_V写数据,

    // --- O缓冲读接口（回写时读取） ---
    output logic                       缓冲_O读使能,
    output logic [$clog2(Q分块行数)-1:0] 缓冲_O读行号,
    output logic [$clog2(头维度/(AXI数据位宽/数据位宽))-1:0] 缓冲_O读列组,
    input  logic [AXI数据位宽-1:0]     缓冲_O读数据,

    // 缓冲选择（乒乓）
    input  logic                       KV缓冲选择
);

    localparam 每拍元素数 = AXI数据位宽 / 数据位宽;   // 128/16 = 8个元素

    // ========== AXI主机实例的内部信号 ==========
    logic        AXI读请求;
    logic [AXI地址位宽-1:0] AXI读地址;
    logic [15:0] AXI读长度;
    logic        AXI读完成;
    logic [AXI数据位宽-1:0] AXI读出数据;
    logic        AXI读出数据有效;

    logic        AXI写请求;
    logic [AXI地址位宽-1:0] AXI写地址;
    logic [15:0] AXI写长度;
    logic        AXI写完成;
    logic [AXI数据位宽-1:0] AXI写入数据;
    logic        AXI写入数据有效;
    logic        AXI写入数据就绪;

    // 例化AXI4主机接口
    AXI4主机接口 #(
        .地址位宽(AXI地址位宽), .数据位宽(AXI数据位宽), .ID位宽(AXI_ID位宽)
    ) 实例_AXI主机 (
        .时钟(时钟), .复位_低有效(复位_低有效),
        .主机_写地址ID(主机_写地址ID), .主机_写地址(主机_写地址), .主机_写突发长度(主机_写突发长度),
        .主机_写突发大小(主机_写突发大小), .主机_写突发类型(主机_写突发类型),
        .主机_写地址有效(主机_写地址有效), .主机_写地址就绪(主机_写地址就绪),
        .主机_写数据(主机_写数据), .主机_写选通(主机_写选通),
        .主机_写最后一拍(主机_写最后一拍), .主机_写数据有效(主机_写数据有效), .主机_写数据就绪(主机_写数据就绪),
        .主机_写响应ID(主机_写响应ID), .主机_写响应(主机_写响应),
        .主机_写响应有效(主机_写响应有效), .主机_写响应就绪(主机_写响应就绪),
        .主机_读地址ID(主机_读地址ID), .主机_读地址(主机_读地址), .主机_读突发长度(主机_读突发长度),
        .主机_读突发大小(主机_读突发大小), .主机_读突发类型(主机_读突发类型),
        .主机_读地址有效(主机_读地址有效), .主机_读地址就绪(主机_读地址就绪),
        .主机_读数据ID(主机_读数据ID), .主机_读数据(主机_读数据), .主机_读响应(主机_读响应),
        .主机_读最后一拍(主机_读最后一拍), .主机_读数据有效(主机_读数据有效), .主机_读数据就绪(主机_读数据就绪),
        .读请求(AXI读请求), .读地址(AXI读地址), .读长度_字节(AXI读长度),
        .读完成(AXI读完成), .读出数据(AXI读出数据), .读出数据有效(AXI读出数据有效),
        .写请求(AXI写请求), .写地址(AXI写地址), .写长度_字节(AXI写长度),
        .写完成(AXI写完成), .写入数据(AXI写入数据),
        .写入数据有效(AXI写入数据有效), .写入数据就绪(AXI写入数据就绪)
    );

    // ===== 读数据路由逻辑 =====
    // 根据读目标（Q/K/V），将AXI读回的数据写入对应缓冲
    logic [1:0]  读目标_锁存;     // 锁存的读目标
    logic [15:0] 读节拍计数;      // 已接收的节拍数

    always_ff @(posedge 时钟 or negedge 复位_低有效) begin
        if (!复位_低有效) begin
            AXI读请求    <= 1'b0;
            读目标_锁存  <= '0;
            读节拍计数   <= '0;
            DMA读完成    <= 1'b0;
            缓冲_Q写使能 <= 1'b0;
            缓冲_K写使能 <= 1'b0;
            缓冲_V写使能 <= 1'b0;
        end else begin
            DMA读完成    <= 1'b0;
            缓冲_Q写使能 <= 1'b0;
            缓冲_K写使能 <= 1'b0;
            缓冲_V写使能 <= 1'b0;

            // 捕获DMA读请求，发起AXI读事务
            if (DMA读请求 && !AXI读请求) begin
                AXI读请求   <= 1'b1;
                AXI读地址   <= DMA读地址;
                AXI读长度   <= DMA读长度_字节;
                读目标_锁存 <= DMA读目标;
                读节拍计数  <= '0;
            end
            if (AXI读完成) begin
                AXI读请求 <= 1'b0;
            end

            // 收到AXI读数据后，根据目标分发到对应缓冲
            if (AXI读出数据有效) begin
                case (读目标_锁存)
                    2'd0: begin  // 目标：Q缓冲
                        缓冲_Q写使能 <= 1'b1;
                        缓冲_Q写地址 <= 读节拍计数[$clog2(Q分块行数*头维度)-1:0];
                        缓冲_Q写数据 <= AXI读出数据;
                    end
                    2'd1: begin  // 目标：K缓冲
                        缓冲_K写使能 <= 1'b1;
                        缓冲_K写地址 <= 读节拍计数[$clog2(KV分块行数*头维度)-1:0];
                        缓冲_K写数据 <= AXI读出数据;
                    end
                    2'd2: begin  // 目标：V缓冲
                        缓冲_V写使能 <= 1'b1;
                        缓冲_V写地址 <= 读节拍计数[$clog2(KV分块行数*头维度)-1:0];
                        缓冲_V写数据 <= AXI读出数据;
                    end
                    default: ;
                endcase
                读节拍计数 <= 读节拍计数 + 1;
            end

            if (AXI读完成)
                DMA读完成 <= 1'b1;
        end
    end

    // ===== 写数据路由逻辑（O缓冲 → AXI写通道） =====
    localparam O每拍列数   = AXI数据位宽 / 数据位宽;       // 每拍传8个元素
    localparam O每行节拍数 = 头维度 / O每拍列数;            // 64/8 = 8拍/行
    localparam O总节拍数   = Q分块行数 * O每行节拍数;       // 4×8 = 32拍

    logic [15:0] 写节拍计数;
    logic        写活动;

    typedef enum logic [1:0] {
        写_空闲,       // 等待写请求
        写_发地址,     // 等待AXI写地址被接受
        写_发送数据,   // 从O缓冲读数据并发送
        写_结束        // 等待AXI写完成
    } 写状态类型;
    写状态类型 写状态;

    always_ff @(posedge 时钟 or negedge 复位_低有效) begin
        if (!复位_低有效) begin
            写状态          <= 写_空闲;
            AXI写请求       <= 1'b0;
            DMA写完成       <= 1'b0;
            写节拍计数      <= '0;
            写活动          <= 1'b0;
            AXI写入数据有效 <= 1'b0;
            AXI写入数据     <= '0;
            缓冲_O读使能    <= 1'b0;
        end else begin
            DMA写完成       <= 1'b0;
            缓冲_O读使能    <= 1'b0;
            AXI写入数据有效 <= 1'b0;

            case (写状态)
                // ---- 空闲：等待DMA写请求 ----
                写_空闲: begin
                    if (DMA写请求) begin
                        AXI写请求  <= 1'b1;
                        AXI写地址  <= DMA写地址;
                        AXI写长度  <= DMA写长度_字节;
                        写节拍计数 <= '0;
                        写状态     <= 写_发地址;
                    end
                end

                // ---- 发地址：预读第一个O缓冲数据 ----
                写_发地址: begin
                    缓冲_O读使能 <= 1'b1;
                    缓冲_O读行号 <= '0;
                    缓冲_O读列组 <= '0;
                    if (AXI写入数据就绪)
                        写状态 <= 写_发送数据;
                end

                // ---- 发送数据：从O缓冲逐拍读出并发送 ----
                写_发送数据: begin
                    if (AXI写入数据就绪) begin
                        AXI写入数据     <= 缓冲_O读数据;
                        AXI写入数据有效 <= 1'b1;
                        写节拍计数      <= 写节拍计数 + 1;

                        // 预读下一拍数据
                        if (写节拍计数 + 1 < O总节拍数) begin
                            缓冲_O读使能 <= 1'b1;
                            缓冲_O读行号 <= (写节拍计数 + 1) / O每行节拍数;
                            缓冲_O读列组 <= (写节拍计数 + 1) % O每行节拍数;
                        end

                        // 发送完最后一拍
                        if (写节拍计数 == O总节拍数 - 1)
                            写状态 <= 写_结束;
                    end else begin
                        AXI写入数据有效 <= 1'b0;
                    end
                end

                // ---- 结束：等待AXI写完成 ----
                写_结束: begin
                    AXI写入数据有效 <= 1'b0;
                    if (AXI写完成) begin
                        DMA写完成 <= 1'b1;
                        AXI写请求 <= 1'b0;
                        写状态    <= 写_空闲;
                    end
                end
            endcase
        end
    end

endmodule
