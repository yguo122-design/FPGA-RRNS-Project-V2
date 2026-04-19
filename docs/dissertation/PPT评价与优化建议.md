# 毕业论文答辩PPT评价与优化建议（修订版）

**论文题目**：Hardware Acceleration for Cluster Fault Tolerance in Hybrid CMOS/Non-CMOS Memories  
**评价对象**：`Hardware-Acceleration-for-Cluster-Fault-Tolerance-in-Hybrid-CMOSNon-CMOS-Memories (dissertation).pdf`  
**参考论文**：`thesis_final.pdf` / `thesis_final.tex`  
**PPT实际结构**：共约20页（含首尾），主体内容18页  
**评价日期**：2026年4月14日

---

## 一、PPT实际结构梳理

经核对PPT PDF文本提取内容，实际幻灯片结构如下：

| 序号 | 幻灯片标题 | 类型 |
|------|-----------|------|
| 1 | 封面（标题+作者+导师） | 封面 |
| 2 | Project Overview（6项目录） | 目录 |
| 3 | Background and Research Context | 背景 |
| 4 | Project Goal and Objectives | 目标 |
| 5 | Methodology and Experimental Setup | 方法 |
| 6 | FPGA test platform under working（实物照片） | 平台 |
| 7 | FPGA Platform Architecture | 架构 |
| 8 | Main Innovation: Probabilistic Fault Injection Engine | 创新 |
| 9 | Why the Test Platform Is Strong | 平台优势 |
| 10 | Random Single-Bit Results | 结果1 |
| 11 | Cluster Burst Results at Representative Length L=12 | 结果2 |
| 12 | Quantitative Comparison of Key Results | 汇总 |
| 13 | Latency Comparison | 结果3 |
| 14 | Resource and Storage Comparison | 结果4 |
| 15 | Application scenario recommendations | 应用建议 |
| 16 | Main Conclusions | 结论 |
| 17 | Contributions and Future Work | 贡献 |
| 18 | Appendix A: Fault Injection Algorithm | 附录A |
| 19 | Appendix B: Burst-Length Impact | 附录B |
| 20 | Thanks | 结尾 |

---

## 二、总体评价

### 综合评分：**82 / 100**

| 评价维度 | 得分 | 满分 | 说明 |
|---------|------|------|------|
| 内容覆盖度（与论文对应） | 17 | 20 | 覆盖全面，但部分关键数据缺失 |
| 逻辑结构与叙事流畅性 | 17 | 20 | 结构清晰，叙事线完整 |
| 技术深度与准确性 | 16 | 20 | 技术内容准确，但量化数据呈现不足 |
| 视觉设计与排版 | 16 | 20 | Sheffield风格规范，但部分幻灯片信息密度偏高 |
| 答辩实用性（时间控制/重点突出） | 16 | 20 | 18页主体适合15分钟，但核心结论不够突出 |

**总体印象**：PPT整体结构合理，18页主体内容与15分钟答辩时间匹配良好。覆盖了论文的全部核心章节，技术内容准确，Sheffield大学风格规范。主要不足在于：**关键量化结果（最大可纠正burst长度、延迟数据、43×加速比）在"Quantitative Comparison"幻灯片中仅用文字标签呈现，缺少具体数字**；以及部分幻灯片的视觉层次不够清晰。

---

## 三、逐页详细评价

### Slide 2：Project Overview（目录）

**优点**：
- 6项目录结构清晰，覆盖了从动机到贡献的完整研究路线
- 每项目录附有一句话描述，帮助评委快速定位

**问题**：
- 目录项描述过于简短（如"Two-phase evaluation framework"），未能传达研究的独特性
- 缺少"本研究的核心贡献"一句话总结，让评委在开始就知道"这篇论文做了什么新东西"

**建议**：
在目录页底部添加一行：
> **Core Contribution**: First hardware-validated multi-algorithm RRNS benchmark on FPGA, with novel probabilistic fault injection engine

---

### Slide 3：Background and Research Context

**优点**：
- 清楚指出了三个研究动机：cluster faults、传统ECC局限性、缺乏硬件验证
- "Core Research Question"的提炼非常好，直接点明研究问题

**问题**：
- 文字密度偏高，三段文字在投影时可读性存疑
- 缺少直观图示（如cluster fault的示意图：连续bit错误的物理机制）
- "hardware-validated comparison was still missing"是关键研究缺口，但视觉上没有强调

**建议**：
- 将三段文字改为3个要点（bullet points），每点不超过15词
- 添加一个简单的示意图：正常存储 vs cluster fault（连续bit翻转）
- 用高亮色框标注"Research Gap: No hardware-validated multi-algorithm comparison"

---

### Slide 4：Project Goal and Objectives

**优点**：
- 清楚列出了6种算法配置和4个评估维度
- 结构清晰，信息完整

**问题**：
- 6种算法配置以纯文字列表呈现，视觉上不够直观
- 4个评估维度（Fault Tolerance / Decoding Latency / FPGA Resources / Storage Efficiency）可以用图标或色块强化

**建议**：
将4个评估维度改为4个视觉卡片（icon + 标题 + 一句话说明），例如：
```
🛡️ Fault Tolerance    ⚡ Latency         💾 Resources        📦 Storage
Max burst length      Clock cycles       LUT/FF/DSP/BRAM     Code rate
```

---

### Slide 5：Methodology and Experimental Setup

**优点**：
- 两阶段评估框架（MATLAB + FPGA）清晰
- 测试参数（设备、时钟、注入模式）完整

**问题**：
- "Phase 1: MATLAB Simulation"和"Phase 2: FPGA Implementation"仅用文字描述，缺少流程图
- 缺少说明为什么需要两阶段（MATLAB用于理论基线，FPGA用于硬件验证）

**建议**：
添加一个简单的两阶段流程图：
```
MATLAB Simulation → Theoretical Baseline → Aligned Fault Model
        ↓
FPGA Implementation → Hardware Validation → Cross-Validation
```

---

### Slide 6：FPGA Test Platform Photo

**优点**：
- 实物照片增强了研究的可信度，让评委看到"真实的硬件"
- 这是一个很好的设计选择

**问题**：
- 仅有"FPGA test platform under working"一行文字，缺少关键信息标注
- 没有说明照片中的关键组件（Arty A7-100T开发板、UART连接等）

**建议**：
在照片上添加标注箭头，指出：
- Xilinx Artix-7 xc7a100t (Arty A7-100T)
- UART connection to PC
- 50 MHz clock domain

---

### Slide 7：FPGA Platform Architecture

**优点**：
- "Key Idea"一句话总结了PC-FPGA主从架构，简洁有力
- 包含了系统架构图

**问题**（基于论文内容推断）：
- 架构图中的文字标注在投影时可能偏小
- 缺少对"Single-Algorithm-Build"策略的说明（这是确保资源对比公平性的关键设计决策）

**建议**：
在架构图下方添加一个关键设计原则说明：
> **Single-Algorithm-Build**: Each synthesis run instantiates exactly one codec → ensures fair, interference-free resource comparison

---

### Slide 8：Main Innovation: Probabilistic Fault Injection Engine ⭐

**优点**：
- 4步编号结构清晰（LFSR → Dual Modes → Threshold Control → Precomputed Masks）
- "Why It Matters"的总结很好

**问题**：
- 4个步骤仅有标题和一句话描述，缺少关键参数（如"32-bit LFSR, period = 2³²-1"、"only 2 BRAMs"）
- 这是论文的**核心创新点**，但视觉强调不足——应该是PPT中最醒目的幻灯片之一

**建议**：
将4个步骤改为更具体的描述，并添加关键数字：
```
① 32-bit Galois LFSR    → Period: 2³²-1 ≈ 4.3×10⁹ cycles
② Dual Injection Modes  → Random single-bit + Cluster burst (L=1~15)
③ Threshold Control     → 101 BER points, 0%~10%, step 0.1%
④ Precomputed ROM Masks → Only 2 BRAMs, 100,000 samples/point
```
并在底部用高亮框标注：**"Novel contribution: decouples injection probability from sample count"**

---

### Slide 9：Why the Test Platform Is Strong

**优点**：
- 6个优势点覆盖全面（Fair Comparison / Hardware Validated / Low Overhead / Scalable / Extensible / Cross-Validated）
- 结构清晰

**问题**：
- 6个优势以纯文字列表呈现，视觉上较为单调
- "Support 1~1000000 samples per point configurable"这一行与正文中"100,000 samples per point"的表述不一致，可能引起评委困惑

**⚠️ 重要问题**：
Slide 10（Random Single-Bit Results）中出现"**1000000 samples each BER**"，而论文标准测试使用100,000 samples/BER point。需要明确说明：
- 标准测试：100,000 samples/BER point
- 该特定测试：1,000,000 samples（用于更高统计精度的验证）

如果这是一个特殊测试，需要在幻灯片中明确标注；如果是笔误，需要更正。

**建议**：
- 将6个优势改为图标卡片形式
- 统一样本数量的表述，避免混淆

---

### Slide 10：Random Single-Bit Results

**优点**：
- 3个主要观察点（Model Agreement / Differential Performance / Parallel vs Serial）结构清晰
- 包含了FPGA vs MATLAB对比图

**问题**：
1. **"1000000 samples each BER"**：与论文标准100,000不一致，需要说明
2. 三个观察点的描述较为简短，缺少具体数字支撑
3. "The LFSR Proximity Effect on Parallel/Serial Decoder Assessment"这一观察点非常重要（论文Section 4.2有详细分析），但在PPT中仅一句话带过

**建议**：
- 在图表旁添加关键数字标注：
  - "RS(12,4) maintains highest success rate at elevated BER"
  - "C-RRNS-MRC degrades linearly (no correction)"
- 对LFSR Proximity Effect添加一句解释："Parallel decoder (73 cycles/trial) shows higher apparent success due to LFSR correlation"

---

### Slide 11：Cluster Burst Results at Representative Length L=12

**优点**：
- 选择L=12作为代表性burst长度合理（论文中有充分论证）
- 两个关键发现（Top Performers / Model Dependence）简洁有力

**问题**：
- "C-RRNS-MLD and RS(12,4) show the strongest burst resilience"——缺少具体数字（如"100% success rate at BER=10%"）
- 缺少对为什么C-RRNS-MLD在cluster fault下表现优异的简要解释（宽residue field → 12-bit burst通常只影响2个residue）

**建议**：
在两个关键发现下方添加一行数据支撑：
> C-RRNS-MLD & RS(12,4): **100% decode success** at BER=10%, L=12  
> 2NRM-RRNS: ~95% (Parallel) / ~79% (Serial) — limited by t=2 correction

---

### Slide 12：Quantitative Comparison of Key Results ⭐⭐ 最需要改进

**当前内容**：
```
Most Reliable: C-RRNS-MLD provides the strongest burst-fault tolerance
Fastest: 2NRM-RRNS Parallel decoder achieves the lowest decode latency
Most Compact: 2NRM-RRNS offers the best storage efficiency
```

**严重问题**：
这张幻灯片是整个PPT的**核心汇总页**，但当前仅有文字标签，**完全缺少具体数字**。论文中有完整的Table 4.2和Table 4.5，包含所有关键量化数据，但PPT中没有体现。

**论文中的关键数据（应在此幻灯片中展示）**：

| Algorithm | Max Burst L | Dec. Cycles | LUT | Power | Storage |
|-----------|------------|-------------|-----|-------|---------|
| C-RRNS-MLD | **14** | 928 | ~6% | 0.232W | 26.2% |
| RS(12,4) | 13 | 127 | ~3% | 0.216W | 33.3% |
| 3NRM-RRNS | 11 | 2048 | ~7% | 0.242W | 33.3% |
| 2NRM-P | 8 | **24** | 51% | 0.58W | **39.0%** |
| 2NRM-S | 7 | 1047 | ~4% | 0.223W | **39.0%** |

**建议**：
将此幻灯片改为包含上述数据表格的汇总页，并用颜色高亮每列的最优值。同时保留三个标签（Most Reliable / Fastest / Most Compact）作为视觉引导。

---

### Slide 13：Latency Comparison

**优点**：
- 3个分析要点清晰（2NRM-P最快 / 并行vs串行加速 / resource-latency trade-off）
- 包含延迟对比图

**问题**：
- 缺少关键数字：**"43× lower latency (24 vs 1047 cycles)"** 这是论文Abstract中明确提到的核心贡献之一，但PPT中没有出现这个数字
- "Technical Note"的字体偏小，在投影时可能不可读

**建议**：
在幻灯片中用大字体突出：
> **2NRM-RRNS Parallel: 43× faster than Serial** (24 vs 1047 decoder cycles)  
> At 13× higher LUT utilisation (51% vs 4%)

---

### Slide 14：Resource and Storage Comparison

**优点**：
- 三个关键trade-off（2NRM-Parallel / 2NRM-RRNS / C-RRNS-MLD）结构清晰
- 包含资源利用率对比图

**问题**：
- 缺少具体数字（如"2NRM-Parallel: 51% LUT, 0.58W"）
- 存储效率数据（39.0% vs 26.2%）没有在此幻灯片中体现

**建议**：
在三个trade-off描述中添加具体数字：
```
2NRM-Parallel: 51% LUT, 0.58W → Fastest (24 cycles)
2NRM-RRNS:    ~4% LUT, 0.223W → Best storage (39.0%)
C-RRNS-MLD:   ~6% LUT, 0.232W → Best fault tolerance (L=14)
```

---

### Slide 15：Application Scenario Recommendations

**优点**：
- 5个应用场景覆盖全面（高可靠性 / 存储受限 / 延迟敏感 / 资源受限 / 通用）
- 表格格式清晰

**问题**：
- 表格中"Recommended"列仅列出算法名称，缺少推荐理由
- 论文Table 4.6中有详细的Rationale列，PPT中没有体现

**建议**：
在表格中添加简短的推荐理由（1-2个关键词），例如：
```
High-reliability → C-RRNS MLD or RS → "100% recovery, L=14/13"
Storage-constrained → 2NRM-RRNS (Parallel) → "39.0% efficiency, 10.96 Mbps"
```

---

### Slide 16：Main Conclusions

**优点**：
- 5个结论编号清晰，覆盖了平台验证、容错性、性能、存储效率、验证可靠性
- 结构完整

**问题**：
- 5个结论中缺少**最重要的量化结论**：
  - "C-RRNS-MLD: no observed decoding failures up to L=14"
  - "2NRM-RRNS Parallel: 43× lower latency than Serial"
  - "FPGA-MATLAB: strong agreement confirms implementation correctness"
- 结论05（"Close agreement between FPGA and MATLAB results"）的表述过于简短

**建议**：
将5个结论改为包含具体数字的版本：
```
01 Platform: Delivered reusable FPGA benchmark with novel probabilistic injector (2 BRAMs)
02 Fault Tolerance: C-RRNS-MLD → 0 failures up to L=14; RS → L=13
03 Performance: 2NRM-Parallel → 24 cycles (43× faster than Serial, 13× more LUTs)
04 Storage: 2NRM-RRNS → 39.0% efficiency (best among all correcting codes)
05 Validation: FPGA ≈ MATLAB across all algorithms → confirms correctness
```

---

### Slide 17：Contributions and Future Work

**优点**：
- 3个贡献点清晰（FPGA Platform / Fault Injection Engine / Trade-off Quantification）
- 3个未来工作方向合理

**问题**：
- 贡献点描述过于简短，缺少"first"/"novel"等强调词
- 未来工作"Reduce LFSR correlation with stronger random sources"可以更具体（如"True Random Number Generator (TRNG)"）

**建议**：
将贡献点改为更有力的表述：
```
✓ First reusable FPGA evaluation platform for multi-algorithm RRNS benchmarking
✓ Novel probabilistic fault injection engine: 2 BRAMs, 100K samples/point, arbitrary sample count
✓ First hardware quantification of 2NRM-RRNS parallel/serial trade-off: 43× latency, 13× LUT
```

---

### Slides 18-19：Appendix A & B

**优点**：
- Appendix A的6步注入算法流程清晰，有助于回答"注入引擎如何工作"的问题
- Appendix B的burst-length BER曲线支持了C-RRNS-MLD的最终结论

**问题**：
- Appendix A的"Controlled Evaluation"说明很好，但字体可能偏小
- Appendix B仅有一句话描述，缺少对曲线的简要解读

**建议**：
这两张附录幻灯片设计合理，主要建议是确保字体大小在投影时可读（≥16pt）。

---

## 四、关键数据缺失分析

以下是论文中的核心量化结果，在PPT中**未明确呈现**：

| 关键数据 | 论文来源 | PPT现状 | 重要性 |
|---------|---------|---------|--------|
| C-RRNS-MLD最大burst长度=14 | Table 4.2 | ❌ 未出现 | ⭐⭐⭐ |
| RS(12,4)最大burst长度=13 | Table 4.2 | ❌ 未出现 | ⭐⭐⭐ |
| 2NRM-P解码延迟=24 cycles | Table 4.3 | ❌ 未出现 | ⭐⭐⭐ |
| 并行vs串行：43×延迟差 | Abstract | ❌ 未出现 | ⭐⭐⭐ |
| 并行vs串行：13×LUT差 | Abstract | ❌ 未出现 | ⭐⭐⭐ |
| 2NRM-P功耗=0.58W（其他~0.22W） | Table 4.4 | ❌ 未出现 | ⭐⭐ |
| 2NRM-RRNS存储效率=39.0% | Section 4.7 | ⚠️ 仅文字 | ⭐⭐ |
| C-RRNS-MLD在L=12时100%成功率 | Table 4.5 | ⚠️ 仅文字 | ⭐⭐⭐ |

---

## 五、潜在问题：样本数量不一致

**发现**：
- Slide 9（Why Platform Is Strong）：标注"100,000 samples per point"
- Slide 10（Random Single-Bit Results）：标注"**1000000 samples each BER**"
- 论文标准：100,000 samples per BER point

**分析**：
这可能是：
1. 该特定测试使用了1,000,000 samples（更高统计精度的验证测试）
2. 笔误（多写了一个0）

**建议**：
在答辩前确认此数字，并在幻灯片中明确说明：
- 如果是特殊测试：添加注释"*1,000,000 samples for this validation run; standard: 100,000"
- 如果是笔误：更正为100,000

---

## 六、答辩预期问题与准备

基于论文内容和PPT结构，答辩委员会最可能提出的问题：

### Q1：为什么选择RRNS而不是LDPC或Turbo码？
**准备答案**：LDPC/Turbo码的迭代解码延迟与内存系统的低延迟要求不兼容；RRNS的residue结构天然适合cluster fault（一个burst通常只影响少数residue）。

### Q2：C-RRNS-MLD的"no observed decoding failures"是否意味着100%纠错？
**准备答案**：在100,000 samples/BER point的测试空间内未观察到失败，与理论t=3纠错能力一致；但极端对齐情况（burst恰好跨越3个residue边界）未被穷举覆盖，因此表述为"no observed failures"而非"guaranteed 100%"。

### Q3：为什么时钟频率只有50 MHz而不是100 MHz？
**准备答案**：2NRM-RRNS并行MLD解码器的15个并行CRT通道产生了长组合路径，经过约30轮时序优化仍无法在100 MHz下满足时序约束，因此降至50 MHz。所有6种算法在相同50 MHz下评估，确保对比公平性。

### Q4：LFSR相关性如何影响实验结果？
**准备答案**：LFSR的线性相关性导致并行解码器（73 cycles/trial）的相邻注入模式相关性强于串行解码器（1047 cycles/trial），使并行解码器的测量成功率略高于真实值。跨算法对比使用独立LFSR种子，MATLAB结果作为参考基准，不影响跨算法结论。

### Q5：功耗数据是否来自实际测量？
**准备答案**：功耗数据来自Vivado Power Analyser的后实现估算，精度约±20%。FPGA原型的功耗不能直接与ASIC实现对比，但在相同平台上的相对差异（2NRM-P: 0.58W vs 其他: ~0.22W）是有效的对比依据。

---

## 七、优先级改进清单

### 🔴 高优先级（答辩前必须修改）

1. **Slide 12（Quantitative Comparison）**：添加完整数据表格（Max Burst L / Dec. Cycles / LUT / Power / Storage），这是PPT最重要的改进点
2. **Slide 13（Latency）**：明确标注"**43× lower latency** (24 vs 1047 cycles)"
3. **Slide 16（Conclusions）**：在每个结论中添加具体数字
4. **样本数量不一致**：确认并统一Slide 10中"1000000 samples"的表述

### 🟡 中优先级（建议修改）

5. **Slide 8（Main Innovation）**：在4个步骤中添加关键参数（LFSR period、BRAM数量、BER范围）
6. **Slide 11（Cluster Burst L=12）**：添加具体成功率数字（C-RRNS-MLD: 100%, 2NRM-P: ~95%）
7. **Slide 17（Contributions）**：改为更有力的"first/novel"表述，并添加43×/13×数字
8. **Slide 6（FPGA Photo）**：添加组件标注箭头

### 🟢 低优先级（有时间可改）

9. Slide 3（Background）：添加cluster fault示意图
10. Slide 4（Objectives）：将4个评估维度改为图标卡片
11. Slide 9（Platform Strengths）：改为图标卡片形式
12. Slide 15（Application Scenarios）：添加推荐理由列

---

## 八、总结

**PPT整体评价**：结构合理，18页主体内容与15分钟答辩时间匹配良好，Sheffield大学风格规范，技术内容准确。

**最核心的改进需求**：
1. **Slide 12（Quantitative Comparison）** 是整个PPT最需要改进的幻灯片——当前仅有文字标签，缺少论文中最重要的量化数据（最大burst长度、延迟数字、43×加速比）
2. **Slide 13（Latency）** 需要明确标注43×这一核心贡献数字
3. **样本数量不一致**需要在答辩前确认和统一

按照上述高优先级建议修改后，预计综合评分可从82分提升至**90-93分**。

---

*本评价基于PPT PDF文本提取内容（288行）与论文`thesis_final.tex`（3111行）的逐页对比分析*  
*PPT实际结构：20页总计，18页主体内容（去掉封面和致谢页）*