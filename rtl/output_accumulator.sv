// ============================================================
// 输出累加器
// 累加 O = 缩放修正 × O旧值 + P · V（FlashAttention核心公式）
// 每个KV分块迭代执行：
//   O_new[行][列] = 缩放修正[行] × O_old[行][列] + Σ_c P[行][c] × V[c][列]
// 最后一个KV分块处理完后：用分母和 l 归一化O
// ============================================================
module 输出累加器 #(
    parameter Q分块行数    = 4,
    parameter KV分块行数   = 16,
    parameter 头维度       = 64,
    parameter 数据位宽     = 16,
    parameter 累加器位宽   = 40,
    parameter 指数输出位宽 = 24,
    parameter 小数位数     = 16,
    parameter 并行列数     = 8      // 每周期并行处理8列V
)(
    input  logic                          时钟,
    input  logic                          复位_低有效,

    // 控制信号
    input  logic                          启动,
    input  logic                          首个分块,      // 第一个KV分块
    input  logic                          末个分块,      // 最后一个KV分块 → 需归一化并输出
    output logic                          完成,
    output logic                          忙碌,

    // 概率矩阵 P（来自Softmax，Q分块行数 × KV分块行数）
    input  logic [指数输出位宽-1:0]       概率矩阵 [Q分块行数-1:0][KV分块行数-1:0],

    // V分块数据：KV分块行数 行 × d 列，每周期流式输入 并行列数 列
    input  logic signed [数据位宽-1:0]    V数据 [KV分块行数-1:0][并行列数-1:0],
    input  logic                          V有效,

    // 缩放修正因子（每行一个，用于修正旧O）
    input  logic [累加器位宽-1:0]         缩放修正 [Q分块行数-1:0],

    // 分母和（每行一个，最终归一化用）
    input  logic [累加器位宽-1:0]         分母和 [Q分块行数-1:0],

    // 输出 O分块：Q分块行数 × 头维度，完成时有效
    output logic signed [数据位宽-1:0]    O输出 [Q分块行数-1:0][头维度-1:0],
    output logic                          O有效
);

    localparam V总步数 = 头维度 / 并行列数;  // 64/8 = 8步

    // O累加器（Q分块行数 × 头维度，使用 累加器位宽 位防溢出）
    logic signed [累加器位宽-1:0] O累加器 [Q分块行数-1:0][头维度-1:0];

    typedef enum logic [2:0] {
        空闲,          // 等待启动
        缩放旧值,      // 将旧O乘以缩放修正因子
        PV乘累加,      // 计算 P·V 并累加
        归一化,        // 最终除以分母和 l
        处理完成       // 输出结果
    } 状态类型;

    状态类型 当前状态;
    logic [$clog2(V总步数):0] V步进;
    logic [$clog2(头维度):0]  列基址;        // 当前处理的起始列号

    always_ff @(posedge 时钟 or negedge 复位_低有效) begin
        if (!复位_低有效) begin
            当前状态 <= 空闲;
            完成     <= 1'b0;
            忙碌     <= 1'b0;
            O有效    <= 1'b0;
            V步进    <= '0;
            列基址   <= '0;
            for (int 行 = 0; 行 < Q分块行数; 行++)
                for (int 列 = 0; 列 < 头维度; 列++)
                    O累加器[行][列] <= '0;
        end else begin
            完成  <= 1'b0;
            O有效 <= 1'b0;

            case (当前状态)
                // ---- 空闲：等待启动 ----
                空闲: begin
                    if (启动) begin
                        当前状态 <= 首个分块 ? PV乘累加 : 缩放旧值;
                        忙碌     <= 1'b1;
                        V步进    <= '0;
                        列基址   <= '0;
                        if (首个分块) begin
                            // 第一个KV分块：清零累加器
                            for (int 行 = 0; 行 < Q分块行数; 行++)
                                for (int 列 = 0; 列 < 头维度; 列++)
                                    O累加器[行][列] <= '0;
                        end
                    end
                end

                // ---- 缩放旧值：O_old = O_old × 缩放修正 / l_new ----
                缩放旧值: begin
                    for (int 行 = 0; 行 < Q分块行数; 行++) begin
                        for (int 列 = 0; 列 < 头维度; 列++) begin
                            if (分母和[行] != '0)
                                O累加器[行][列] <= (O累加器[行][列] * signed'({1'b0, 缩放修正[行]})) >>> 小数位数;
                            else
                                O累加器[行][列] <= '0;
                        end
                    end
                    当前状态 <= PV乘累加;
                    V步进    <= '0;
                    列基址   <= '0;
                end

                // ---- PV乘累加：O += P · V ----
                // 每步处理 并行列数 列，共 V总步数 步
                PV乘累加: begin
                    if (V有效) begin
                        for (int 行 = 0; 行 < Q分块行数; 行++) begin
                            for (int p = 0; p < 并行列数; p++) begin
                                logic signed [累加器位宽-1:0] PV和;
                                PV和 = '0;
                                // 对所有KV行求和：PV和 = Σ_c P[行][c] × V[c][p]
                                for (int c = 0; c < KV分块行数; c++) begin
                                    PV和 = PV和 +
                                        (signed'({1'b0, 概率矩阵[行][c]}) * 累加器位宽'(V数据[c][p])) >>> 小数位数;
                                end
                                O累加器[行][列基址 + p] <= O累加器[行][列基址 + p] + PV和;
                            end
                        end
                        列基址 <= 列基址 + 并行列数;
                        V步进  <= V步进 + 1;
                        if (V步进 == V总步数 - 1)
                            当前状态 <= 末个分块 ? 归一化 : 处理完成;
                    end
                end

                // ---- 归一化：O = O / l（最终输出） ----
                归一化: begin
                    for (int 行 = 0; 行 < Q分块行数; 行++) begin
                        for (int 列 = 0; 列 < 头维度; 列++) begin
                            logic signed [累加器位宽-1:0] 归一化值;
                            if (分母和[行] != '0)
                                归一化值 = (O累加器[行][列] << 小数位数) /
                                           signed'({1'b0, 分母和[行]});
                            else
                                归一化值 = '0;
                            // 截断为 Q8.8 格式输出
                            O输出[行][列] <= 数据位宽'(归一化值 >>> (小数位数 - 8));
                        end
                    end
                    当前状态 <= 处理完成;
                end

                // ---- 处理完成 ----
                处理完成: begin
                    O有效    <= 末个分块;    // 仅在最后一个KV分块时输出有效
                    完成     <= 1'b1;
                    忙碌     <= 1'b0;
                    当前状态 <= 空闲;
                end
            endcase
        end
    end

endmodule
