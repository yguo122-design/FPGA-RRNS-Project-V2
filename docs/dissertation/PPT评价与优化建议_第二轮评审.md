# 答辩PPT第二轮评审报告

**评审对象**：`Hardware-Acceleration-for-Cluster-Fault-Tolerance-in-Hybrid-CMOSNon-CMOS-Memories (dissertation).pdf`（更新版）  
**第一轮评审日期**：2026年4月14日 13:19  
**第二轮评审日期**：2026年4月14日 14:20  
**评审方式**：基于第一轮建议的逐项核查 + 补充优化建议

---

## 一、第一轮高优先级建议核查清单

请对照以下清单，逐项确认修改是否到位：

### ✅/❌ 改进项1：Slide 12（Quantitative Comparison）数据表格

**第一轮建议**：添加包含Max Burst L / Dec. Cycles / LUT / Power / Storage的完整数据表

**自查要点**：
- [ ] 表格中是否出现 **L=14**（C-RRNS-MLD最大burst长度）
- [ ] 表格中是否出现 **L=13**（RS(12,4)最大burst长度）
- [ ] 表格中是否出现 **24 cycles**（2NRM-P解码延迟）
- [ ] 表格中是否出现 **39.0%**（2NRM-RRNS存储效率）
- [ ] 每列最优值是否用粗体或颜色高亮
- [ ] 表格字体是否≥16pt（投影可读）

**推荐的最终表格格式**：

| Algorithm | Max Burst L | Dec. Cycles | LUT | Power | Storage |
|-----------|------------|-------------|-----|-------|---------|
| **C-RRNS-MLD** | **★14** | 928 | ~6% | 0.232W | 26.2% |
| RS(12,4) | 13 | 127 | ~3% | 0.216W | 33.3% |
| 3NRM-RRNS | 11 | 2048 | ~7% | 0.242W | 33.3% |
| **2NRM-P** | 8 | **★24** | 51% | 0.58W | **★39.0%** |
| 2NRM-S | 7 | 1047 | ~4% | 0.223W | **★39.0%** |

（★ 表示该维度最优值，建议用Sheffield紫色 #440099 高亮）

---

### ✅/❌ 改进项2：Slide 13（Latency）标注43×加速比

**第一轮建议**：明确标注"43× lower latency (24 vs 1047 cycles)"

**自查要点**：
- [ ] 是否出现 **"43×"** 字样
- [ ] 是否出现 **"13×"**（LUT差异）
- [ ] 是否用大字体或高亮框强调

**推荐的文字框内容**：
```
2NRM-RRNS Parallel vs Serial:
• 43× lower latency (24 vs 1047 decoder cycles)
• 13× higher LUT utilisation (51% vs ~4%)
→ Clear resource-latency trade-off quantified on hardware
```

---

### ✅/❌ 改进项3：Slide 16（Conclusions）添加具体数字

**第一轮建议**：在5个结论中添加量化数据

**自查要点**：
- [ ] 结论02是否包含 **"L=14"**（C-RRNS-MLD）
- [ ] 结论03是否包含 **"43×"** 或 **"24 cycles"**
- [ ] 结论04是否包含 **"39.0%"**

**推荐的结论表述**：
```
01 Platform: Reusable FPGA benchmark — 6 algorithms, 2 BRAMs, 100K samples/point
02 Fault Tolerance: C-RRNS-MLD → 0 failures up to L=14 (best in design space)
03 Performance: 2NRM-Parallel → 24 cycles (43× faster than Serial, 13× more LUTs)
04 Storage: 2NRM-RRNS → 39.0% efficiency (best among all correcting codes)
05 Validation: FPGA ≈ MATLAB across all 6 configs → correctness confirmed
```

---

### ✅/❌ 改进项4：样本数量不一致问题

**第一轮建议**：确认并统一Slide 10中"1000000 samples"的表述

**自查要点**：
- [ ] Slide 10的样本数量是否已更正或明确说明
- [ ] 如果保留1,000,000，是否添加注释说明这是特殊验证测试

**说明**：
- 论文标准：100,000 samples/BER point（用于所有正式结果）
- 如果Slide 10使用1,000,000，需要说明："*1,000,000 samples used for this validation run to demonstrate statistical robustness; all other results use 100,000 samples/point"

---

## 二、中优先级建议核查

### ✅/❌ 改进项5：Slide 8（Main Innovation）添加关键参数

**自查要点**：
- [ ] 是否出现 **"2³²-1"** 或 **"4.3×10⁹"**（LFSR周期）
- [ ] 是否出现 **"only 2 BRAMs"**
- [ ] 是否出现 **"101 BER points"** 或 **"0%~10%"**

---

### ✅/❌ 改进项6：Slide 11（Cluster Burst L=12）添加成功率数字

**自查要点**：
- [ ] 是否出现 **"100%"**（C-RRNS-MLD和RS在L=12时的成功率）
- [ ] 是否出现 **"~95%"**（2NRM-P）或 **"~79%"**（2NRM-S）

---

### ✅/❌ 改进项7：Slide 17（Contributions）改为"first/novel"表述

**自查要点**：
- [ ] 是否出现 **"First"** 或 **"Novel"** 等强调词
- [ ] 是否包含 **"43×"** 或 **"13×"** 数字

**推荐表述**：
```
✓ First reusable FPGA evaluation platform for multi-algorithm RRNS benchmarking
✓ Novel probabilistic fault injection engine: 2 BRAMs, 100K samples/point
✓ First hardware quantification of 2NRM-RRNS parallel/serial trade-off: 43× latency, 13× LUT
```

---

### ✅/❌ 改进项8：Slide 6（FPGA Photo）添加组件标注

**自查要点**：
- [ ] 是否在照片上添加了标注箭头
- [ ] 是否标注了"Xilinx Artix-7 xc7a100t"或"Arty A7-100T"

---

## 三、补充优化建议（第二轮新增）

基于对答辩PPT的整体分析，提出以下第二轮新增建议：

### 3.1 Slide 2（Project Overview）：添加核心贡献一句话

在目录页底部添加：
> **Core Contribution**: First hardware-validated multi-algorithm RRNS benchmark on FPGA, with novel probabilistic fault injection engine (2 BRAMs, 100K samples/point)

这让评委在看目录时就能理解研究的独特价值。

---

### 3.2 Slide 3（Background）：强化Research Gap

当前文字描述了三个动机，但"Research Gap"不够突出。建议添加一个高亮框：

```
┌─────────────────────────────────────────────────────┐
│  Research Gap:                                       │
│  No prior work has provided hardware-validated,      │
│  multi-algorithm RRNS benchmarks with quantified     │
│  parallel vs. serial MLD trade-offs on physical FPGA │
└─────────────────────────────────────────────────────┘
```

---

### 3.3 Slide 12（Quantitative Comparison）：视觉层次优化

如果已添加数据表格，建议在表格下方保留三个视觉标签，形成"数据表格 + 结论标签"的双层结构：

```
[数据表格]
         ↓
Most Reliable: C-RRNS-MLD (L=14)
Fastest:       2NRM-Parallel (24 cycles)  
Most Compact:  2NRM-RRNS (39.0%)
```

---

### 3.4 Slide 15（Application Scenarios）：添加推荐理由

当前表格缺少推荐理由列。建议在"Recommended"列后添加简短理由：

| Scenario | Constraint | Recommended | Why |
|----------|-----------|-------------|-----|
| High-reliability | Fault tolerance | C-RRNS MLD or RS | 100% recovery, L=14/13 |
| Storage-constrained | Codeword overhead | 2NRM-RRNS (Parallel) | 39.0% efficiency, 10.96 Mbps |
| Latency-sensitive | Processing speed | RS(12,4) or 2NRM-P | 127/24 cycles, t=4/2 |
| Resource-constrained | LUT utilisation | 2NRM-RRNS (Serial) | ~4% LUT, same BER perf |
| General-purpose | All dimensions | RS(12,4) | Mature ecosystem, balanced |

---

### 3.5 答辩开场白建议

建议在封面页展示时，用以下一句话开场（约30秒）：

> "This dissertation presents the first hardware-validated, multi-algorithm comparison of RRNS and RS error-correcting codes on FPGA, addressing the cluster fault challenge in hybrid CMOS/non-CMOS memories. Our key finding is that C-RRNS-MLD provides the strongest burst-fault tolerance up to L=14, while our novel probabilistic fault injection engine enables statistically rigorous BER testing using only two Block RAMs."

---

## 四、答辩当天时间分配建议

| 幻灯片 | 内容 | 建议时间 | 关键要点 |
|--------|------|---------|---------|
| Slide 1-2 | 封面+目录 | 1分钟 | 一句话介绍研究价值 |
| Slide 3-4 | 背景+目标 | 2分钟 | 强调Research Gap |
| Slide 5-7 | 方法+平台+架构 | 2.5分钟 | 强调两阶段验证 |
| Slide 8-9 | 创新+平台优势 | 2分钟 | 强调"2 BRAMs"创新 |
| Slide 10-14 | 结果（5张） | 4分钟 | 强调43×、L=14 |
| Slide 15-17 | 应用+结论+贡献 | 2.5分钟 | 强调实用价值 |
| **总计** | | **14分钟** | 留1分钟缓冲 |

---

## 五、答辩预期问题与准备（更新版）

### Q1：你的研究与现有RRNS FPGA实现（如Kumar et al. 2022）有何区别？
**准备答案**：现有实现（如[3]）专注于单一算法，未进行系统性多算法对比，也未量化并行vs串行MLD的资源-延迟权衡。本研究首次在物理硬件上同时评估6种算法配置，并提供了首个并行/串行MLD的硬件量化对比（43×延迟差、13×LUT差）。

### Q2：为什么选择L=12作为代表性burst长度？
**准备答案**：L=12足够长以挑战所有算法（包括C-RRNS-MLD），同时在所有算法的有效注入范围内（最短codeword为41 bits的2NRM-RRNS，L=12 < 41）。这使得L=12成为最具区分度的测试点。

### Q3：C-RRNS-MLD的928 cycles解码延迟是否适合实际内存系统？
**准备答案**：928 cycles @ 50 MHz = 18.56 μs，对于高可靠性应用（如航空航天、医疗）是可接受的。对于延迟敏感应用，RS(12,4)的127 cycles（2.54 μs）或2NRM-P的24 cycles（0.48 μs）是更好的选择。这正是Table 4.6应用场景推荐的依据。

### Q4：你的FPGA实现是否可以直接用于实际混合存储器？
**准备答案**：当前实现是评估平台，而非直接可部署的存储控制器。主要限制包括：(1) 仅支持16-bit数据字；(2) 功耗数据来自Vivado估算而非实际测量；(3) 故障模型是概率性的，未来需要与真实混合存储器设备的故障轨迹对比验证。这些限制已在论文Section 4.9中明确说明。

### Q5：如果要将此平台扩展到更宽的数据字（如64-bit），主要挑战是什么？
**准备答案**：主要挑战有三：(1) 2NRM-RRNS并行MLD的15通道架构在更宽数据字下会产生更长的组合路径，时序约束更难满足；(2) 模数集合需要重新设计以覆盖更大的动态范围；(3) ROM表（threshold_table.coe和error_lut.coe）需要重新生成。这是论文Future Work中提到的首要方向。

---

## 六、最终评分预测

基于第一轮建议的改进情况（假设高优先级项均已修改）：

| 评价维度 | 第一轮 | 预测第二轮 | 改进原因 |
|---------|--------|-----------|---------|
| 内容覆盖度 | 17/20 | 18/20 | Slide 12数据表格补全了关键量化数据 |
| 逻辑结构 | 17/20 | 18/20 | 结论页添加数字后叙事更完整 |
| 技术深度 | 16/20 | 18/20 | 43×、L=14等核心数字的呈现大幅提升技术深度 |
| 视觉设计 | 16/20 | 17/20 | 数据表格和高亮框改善了视觉层次 |
| 答辩实用性 | 16/20 | 18/20 | 具体数字使答辩时的论证更有力 |
| **总分** | **82/100** | **89/100** | **+7分** |

> 如果所有高优先级和中优先级建议均已实施，预计综合评分可达 **89-92分**。

---

## 七、答辩前最终自查清单

### 内容层面（必查）
- [ ] Slide 12包含完整数据表格（含L=14、24 cycles、43×、39.0%）
- [ ] Slide 13明确标注"43× lower latency"
- [ ] Slide 16的5个结论包含具体数字
- [ ] Slide 10的样本数量已统一或明确说明

### 视觉层面（建议查）
- [ ] 所有幻灯片字体≥16pt
- [ ] 关键数字（43×、L=14、24 cycles）用粗体或颜色强调
- [ ] Slide 12数据表格清晰可读（行高、字号、对齐）
- [ ] Sheffield紫色（#440099）一致使用

### 逻辑层面（建议查）
- [ ] 从Slide 3到Slide 16形成完整的"问题→方法→结果→结论"叙事线
- [ ] 附录幻灯片（Slide 18-19）准备好应对深入提问
- [ ] 已准备好Q1-Q5的答案

### 技术层面（必查）
- [ ] 样本数量表述一致（100,000 or 1,000,000，需明确）
- [ ] 所有数字与论文Table 4.2、4.3、4.4、4.5一致
- [ ] "no observed decoding failures"的表述准确（非"guaranteed 100%"）

---

*第二轮评审基于第一轮建议的逐项核查框架*  
*如需进一步评审，请提供更新后的PPT截图或文字内容*