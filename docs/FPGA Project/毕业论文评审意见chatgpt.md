我已经通读了你这篇论文的核心内容（方法、理论、实验设计部分），下面我重点从**“逻辑矛盾 / 技术错误 / 表述不一致 / 潜在误导”**四个维度给你做一个“严格评审”。这些是导师或答辩老师最容易抓的问题。

---

# ⚠️ 一、关键逻辑矛盾（重点！）

## ❶ C-RRNS 是否“没有纠错能力”？——前后严重冲突

### 在 3.1 MATLAB部分：

你写：

> C-RRNS (MRC) has no error correction capability  
> “direct reconstruction”

✔ 这是对的（MRC本身不纠错）

---

### 但在全文其他地方：

你又写：

> C-RRNS has t = 3 correction capability

⚠️ 问题：

- **C-RRNS 作为“编码”是有 t=3 能力的**
    
- 但你 MATLAB 用的是 **MRC decoder（无纠错）**
    

👉 你混淆了两个层次：

|层次|是否有纠错|
|---|---|
|C-RRNS 编码理论|✅ 有 (t=3)|
|MRC 解码实现|❌ 没有|

---

### ❗导致的问题：

你在不同地方说：

- C-RRNS 可以纠错（理论）
    
- C-RRNS 不行（MATLAB结果）
    

👉 **读者会以为你在自相矛盾**

---

### ✅ 建议修正（必须改）：

明确写：

> “C-RRNS theoretical capability is t=3, but in MATLAB we use MRC decoding which does not exploit redundancy, therefore no correction is observed.”

---

# ⚠️ 二、最严重技术问题（可能被质疑）

## ❷ “C-RRNS-MLD 在 0–10% BER 100%成功” —— 结论不可信

你写：

> C-RRNS-MLD achieves 100% success across 0–10% BER

---

### ❗问题本质：

这**理论上不成立**（非常关键）

因为：

- t = 3（最多纠正 3 个 residue）
    
- BER = 10%（bit-level）
    

👉 很容易超过 3 residues 错误

---

### ⚠️ 你这里隐含了一个“漏洞”：

你的 fault injection 是：

> bit-level + burst + mapping to residue

👉 但：

- 一个 residue ≠ 一个 bit
    
- 一个 burst 不一定影响多个 residue
    

---

### 🚨 关键问题：

你没有证明：

> “10% BER 不会导致 >3 residues 错误”

---

### 可能真实原因（推测）：

你系统中：

- codeword 61 bits
    
- residue field 较大（6–7 bits）
    

👉 单 bit error **未必破坏整个 residue**

→ 实际 residue error rate 很低

---

### ❗但你没有解释这一点 → 属于**论证缺失**

---

### ✅ 必须补充解释：

你需要加一句类似：

> “Due to residue field granularity, bit errors do not directly translate to residue errors, therefore even at 10% BER the number of corrupted residues rarely exceeds t=3.”

否则：

👉 这个“100%成功”会被认为是**实验或模型错误**

---

# ⚠️ 三、数学/定义层面问题

## ❸ RRNS 规则描述错误（很隐蔽但严重）

你写：

> Rule 2: m1 < m2 < ... < mn

⚠️ 这个不是 RRNS 必须条件

---

### 正确情况：

RRNS只要求：

✔ pairwise coprime  
✔ dynamic range sufficient

❌ **不要求严格递增**

---

### ❗你后面说：

> 3NRM violates Rule 2

👉 这是错误推导

---

### 正确说法：

- “传统构造中常采用递增”
    
- 但不是数学必要条件
    

---

### ✅ 修改建议：

把：

> “Rule 2 must be satisfied”

改成：

> “Rule 2 is commonly used but not strictly required”

---

# ⚠️ 四、实验设计不一致（答辩高危点）

## ❹ MATLAB vs FPGA 对比存在“不可比性”

你自己也提到：

> MATLAB injects into full codeword  
> FPGA injects only valid bits

---

### ❗问题：

这会导致：

- MATLAB BER 实际更高
    
- FPGA BER 实际更低
    

👉 **结果不可直接对比**

---

### 但你后面却写：

> results are consistent

⚠️ 这是逻辑问题

---

### ✅ 正确表达应是：

> “Qualitative trends are consistent, but quantitative differences exist due to different injection models.”

---

# ⚠️ 五、概率模型潜在错误

## ❺ Ptrigger = BER × Wvalid / L

这个公式你用了：

> Ptrigger = BER × Wvalid / L

---

### ❗问题：

当：

- BER 高
    
- L 小
    

👉 Ptrigger 可能 > 1

---

虽然你隐含限制：

> BER ≤ L / Wvalid

但你没有明确说明：

👉 **Ptrigger 被 clamp 到 1**

---

### ✅ 必须补充：

> “Ptrigger is clipped to 1 when exceeding the valid range”

否则属于**概率模型不完整**

---

# ⚠️ 六、硬件参数前后不一致

## ❻ 时钟频率矛盾

### 前文：

> system runs at 100 MHz

### Table 4.1：

> Clock frequency = 50 MHz

---

### ❗问题：

- 到底 latency 是按哪个算？
    
- cycles vs time 是否一致？
    

---

### ✅ 必须统一：

要么：

- 全部用 cycles（推荐）
    
- 或明确说明：
    
    - design @100MHz
        
    - measurement @50MHz
        

---

# ⚠️ 七、复杂度分析问题

## ❼ MLD complexity 表达不严谨

你写：

> evaluates (6 choose 2) × 5 candidates

---

### ❗问题：

这个 “×5” 没有理论推导

👉 会被问：

- 为什么是 5？
    
- 与 modulus 有关吗？
    

---

### ✅ 建议：

加一句：

> “Due to periodicity of CRT solution space (as shown in [ref])”

否则显得像“拍脑袋”

---

# ⚠️ 八、概念混用（术语问题）

## ❽ fault / error / BER 混用

你在文中：

- cluster fault
    
- burst error
    
- BER
    
- residue error
    

👉 有时混用

---

### ❗问题：

这些层级不同：

|层级|含义|
|---|---|
|bit error|BER|
|residue error|RRNS|
|fault|物理层|

---

### ✅ 建议：

加一个统一说明：

> “In this work, BER refers to bit-level error rate, while correction capability is evaluated at residue level.”

---

# ✅ 总体评价（客观）

## 优点（很强）

✔ 架构设计非常完整（这一点很加分）  
✔ FPGA系统工程能力突出  
✔ 实验设计系统性强  
✔ 有创新点（fault injection engine + parallel MLD）

---

## 主要问题（必须改）

### 🔴 严重级（答辩可能被问住）

- C-RRNS纠错能力表述冲突
    
- 100% BER结论缺乏解释
    
- MATLAB vs FPGA 不可比
    

### 🟠 中等级

- RRNS规则错误
    
- 概率模型不完整
    
- 时钟频率不一致
    

### 🟡 轻微问题

- 术语混用
    
- complexity说明不足
    

---

# 🎯 最关键修改优先级（建议你这样改）

1️⃣ 修正 C-RRNS + MRC 描述  
2️⃣ 给“100%成功”一个物理解释  
3️⃣ 明确 FPGA vs MATLAB 差异  
4️⃣ 改 RRNS Rule 2  
5️⃣ 统一 clock frequency

---

如果你愿意，我可以帮你做一件更“杀伤力强”的事：

👉 **模拟答辩老师提问（10个最刁钻问题）+标准回答**

这个对你毕业答辩会非常有用。