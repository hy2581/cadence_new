// ============================================================
// 缓冲系统
// 片上SRAM缓冲，存储Q、K、V分块数据和O累加结果
// K/V缓冲支持乒乓双缓冲（一个缓冲被DMA写入，另一个被计算核心读取）
// ============================================================
module 缓冲系统 #(
    parameter Q分块行数    = 4,
    parameter KV分块行数   = 16,
    parameter 头维度       = 64,
    parameter 数据位宽     = 16,
    parameter 并行乘累加数 = 8,
    parameter AXI数据位宽  = 128
)(
    input  logic                          时钟,
    input  logic                          复位_低有效,

    // --- DMA写接口（从外部存储器加载分块数据） ---
    // Q缓冲写入
    input  logic                          Q写使能,
    input  logic [$clog2(Q分块行数*头维度)-1:0] Q写地址,
    input  logic [AXI数据位宽-1:0]        Q写数据,
    // K缓冲写入
    input  logic                          K写使能,
    input  logic [$clog2(KV分块行数*头维度)-1:0] K写地址,
    input  logic [AXI数据位宽-1:0]        K写数据,
    input  logic                          K缓冲选择,    // 0或1，选择写入哪个乒乓缓冲
    // V缓冲写入
    input  logic                          V写使能,
    input  logic [$clog2(KV分块行数*头维度)-1:0] V写地址,
    input  logic [AXI数据位宽-1:0]        V写数据,
    input  logic                          V缓冲选择,

    // --- 计算核心读接口 ---
    // Q读取：每周期读出 Q分块行数 × 并行乘累加数 个元素
    input  logic                          Q读使能,
    input  logic [$clog2(头维度/并行乘累加数)-1:0] Q读步进,  // 第几步（0~7）
    output logic signed [数据位宽-1:0]    Q读数据 [Q分块行数-1:0][并行乘累加数-1:0],
    // K读取：每周期读出 KV分块行数 × 并行乘累加数 个元素
    input  logic                          K读使能,
    input  logic [$clog2(头维度/并行乘累加数)-1:0] K读步进,
    input  logic                          K读缓冲选择,   // 选择读取哪个乒乓缓冲
    output logic signed [数据位宽-1:0]    K读数据 [KV分块行数-1:0][并行乘累加数-1:0],
    // V读取
    input  logic                          V读使能,
    input  logic [$clog2(头维度/并行乘累加数)-1:0] V读步进,
    input  logic                          V读缓冲选择,
    output logic signed [数据位宽-1:0]    V读数据 [KV分块行数-1:0][并行乘累加数-1:0],

    // --- O缓冲写入接口（从计算核心写入结果） ---
    input  logic                          O写使能,
    input  logic signed [数据位宽-1:0]    O写数据 [Q分块行数-1:0][头维度-1:0],

    // --- O缓冲读取接口（DMA回写时读取） ---
    input  logic                          O读使能,
    input  logic [$clog2(Q分块行数)-1:0]  O读行号,
    output logic [AXI数据位宽-1:0]        O读数据,
    input  logic [$clog2(头维度/(AXI数据位宽/数据位宽))-1:0] O读列组
);

    localparam Q深度       = Q分块行数 * 头维度;         // 4×64 = 256个元素
    localparam KV深度      = KV分块行数 * 头维度;        // 16×64 = 1024个元素
    localparam 每拍元素数  = AXI数据位宽 / 数据位宽;     // 128/16 = 8

    // ===== Q缓冲（单缓冲） =====
    logic signed [数据位宽-1:0] Q存储器 [Q深度-1:0];

    // 写入：DMA每次写入一拍（8个元素）
    always_ff @(posedge 时钟) begin
        if (Q写使能) begin
            for (int i = 0; i < 每拍元素数; i++)
                Q存储器[Q写地址 * 每拍元素数 + i] <=
                    数据位宽'(Q写数据[i*数据位宽 +: 数据位宽]);
        end
    end

    // 读取：每步读出所有行的 并行乘累加数 个元素
    // Q读数据[行][并行索引] = Q存储器[行 × 头维度 + 步进 × 并行乘累加数 + 并行索引]
    always_comb begin
        for (int 行 = 0; 行 < Q分块行数; 行++)
            for (int 并行 = 0; 并行 < 并行乘累加数; 并行++)
                Q读数据[行][并行] = Q存储器[行 * 头维度 + Q读步进 * 并行乘累加数 + 并行];
    end

    // ===== K缓冲（乒乓双缓冲） =====
    logic signed [数据位宽-1:0] K存储器 [1:0][KV深度-1:0];

    always_ff @(posedge 时钟) begin
        if (K写使能) begin
            for (int i = 0; i < 每拍元素数; i++)
                K存储器[K缓冲选择][K写地址 * 每拍元素数 + i] <=
                    数据位宽'(K写数据[i*数据位宽 +: 数据位宽]);
        end
    end

    always_comb begin
        for (int 行 = 0; 行 < KV分块行数; 行++)
            for (int 并行 = 0; 并行 < 并行乘累加数; 并行++)
                K读数据[行][并行] = K存储器[K读缓冲选择][行 * 头维度 + K读步进 * 并行乘累加数 + 并行];
    end

    // ===== V缓冲（乒乓双缓冲） =====
    logic signed [数据位宽-1:0] V存储器 [1:0][KV深度-1:0];

    always_ff @(posedge 时钟) begin
        if (V写使能) begin
            for (int i = 0; i < 每拍元素数; i++)
                V存储器[V缓冲选择][V写地址 * 每拍元素数 + i] <=
                    数据位宽'(V写数据[i*数据位宽 +: 数据位宽]);
        end
    end

    always_comb begin
        for (int 行 = 0; 行 < KV分块行数; 行++)
            for (int 并行 = 0; 并行 < 并行乘累加数; 并行++)
                V读数据[行][并行] = V存储器[V读缓冲选择][行 * 头维度 + V读步进 * 并行乘累加数 + 并行];
    end

    // ===== O缓冲（输出结果存储） =====
    logic signed [数据位宽-1:0] O存储器 [Q分块行数-1:0][头维度-1:0];

    // 写入：计算核心一次性写入整个O分块
    always_ff @(posedge 时钟) begin
        if (O写使能) begin
            for (int 行 = 0; 行 < Q分块行数; 行++)
                for (int 列 = 0; 列 < 头维度; 列++)
                    O存储器[行][列] <= O写数据[行][列];
        end
    end

    // 读取：DMA回写时每次读出一组（8个元素）
    always_comb begin
        for (int i = 0; i < 每拍元素数; i++)
            O读数据[i*数据位宽 +: 数据位宽] =
                O存储器[O读行号][O读列组 * 每拍元素数 + i];
    end

endmodule
