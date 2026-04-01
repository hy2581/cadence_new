# 在线 Softmax 单元 (`online_softmax_unit.sv`)

> FlashAttention 的**核心创新模块**。不存储完整的注意力矩阵，而是逐 KV-tile 在线更新 Softmax 的 running max 和 running sum。

---

## 接口

```pseudocode
输入: 分数矩阵 S[TILE_BR][TILE_BC]
      首个分块标志(first_tile)
      旧最大值 m_old[TILE_BR]
      旧分母和 l_old[TILE_BR]
输出: 新最大值 m_new[TILE_BR]
      新分母和 l_new[TILE_BR]
      概率矩阵 P[TILE_BR][TILE_BC]  // exp 定点结果
      缩放修正 rescale[TILE_BR]
      结果有效
```

---

## 子模块

```pseudocode
单个 exp_approx_unit 实例（3拍延迟）
逐元素时分复用: TILE_BR × TILE_BC = 4×16 = 64 个元素排队通过
```

> **解析**：只用一个 exp 单元处理所有 64 个元素，通过流水线实现高利用率。每拍输入一个，3拍后输出一个。

---

## 状态机

```pseudocode
空闲 → 求行最大值 → 指数_输入 → 指数_等待 → 求和与修正 → 完成
```

---

## 各阶段详解

### 求行最大值

```pseudocode
对每行 r:
  行最大 = max_j S[r][j]    // 找本tile每行的最大值
  若 首个分块:
    m_new[r] = 行最大       // 第一个tile直接用
  否则:
    m_new[r] = max(行最大, m_old[r])  // 与之前的max比较
```

> **解析**：这是 Online Softmax 的第一步——维护 running maximum。跨多个 KV-tile 保持全局最大值。

### 指数输入（流水线填充）

```pseudocode
若 当前输入行 < TILE_BR:
  exp输入有效 = 1
  exp输入值 = S[当前输入行][当前输入列] - m_new[当前输入行]
  推进输入指针到下一元素
  
  // 同时收集 exp 输出（3拍延迟后开始产出）
  若 exp输出有效:
    P[当前输出行][当前输出列] = exp输出值
    推进输出指针
否则:
  全部输入完成，转 指数_等待
```

> **解析**：减去 max 是数值稳定性的关键——`exp(x - max)` 确保所有指数值 ≤ 1，避免溢出。

### 指数等待（流水线排空）

```pseudocode
继续收集剩余的 exp 输出
若 全部输出收集完毕: 转 求和与修正
```

### 求和与修正

```pseudocode
对每行 r:
  行和 = Σ_j P[r][j]    // 对当前tile的exp值求和

  若 首个分块:
    l_new[r] = 行和
    rescale[r] = 0       // 首个tile无需修正旧O
  否则:
    l_new[r] = l_old[r] + 行和   // 累加到全局sum
    rescale[r] = l_old[r]        // 旧的sum用于修正旧O
```

> **解析**：`rescale` 传递给输出累加器，用于将旧 O 按 `l_old/l_new` 比例缩放，补偿 max 变化带来的影响。RTL 中使用了简化版本（直接用 l_old）。

### 完成

```pseudocode
结果有效=1, 完成=1, 忙碌=0, 状态=空闲
```
