# MATLAB BER Simulation — 操作指南

## 概述

本仿真使用与 FPGA 完全一致的故障注入模型，对 5 种 ECC 算法进行 BER 性能仿真：
- **2NRM-RRNS**（41 bits, t=2, MLD）
- **3NRM-RRNS**（48 bits, t=3, MLD）
- **C-RRNS-MLD**（61 bits, t=3, MLD）
- **C-RRNS-MRC**（61 bits, 无纠错）
- **RS(12,4)**（48 bits, t=4）

每个算法在 3 种故障模式下测试：Random Single Bit (L=1)、Cluster L=5、Cluster L=8。

---

## 前提条件

- MATLAB R2020a 或更新版本
- **Communications Toolbox**（RS 编解码器需要）
- 建议内存：8 GB 以上（100K 样本 × 101 BER 点）

---

## 步骤一：设置工作目录

在 MATLAB 命令窗口中输入：

```matlab
cd('d:\FPGAproject\FPGA-RRNS-Project-V2\src\matlab')
```

或者通过 MATLAB 界面左上角的路径栏导航到该目录。

---

## 步骤二：运行编解码器验证（必须先做）

在 MATLAB 命令窗口输入：

```matlab
test_codecs
```

**预期输出（正常情况）：**
```
=== Codec Sanity Check ===

[PASS] 2NRM-RRNS: No-error round-trip (1000 trials)
[PASS] 2NRM-RRNS: Single-bit error correction (1000 trials)
[PASS] 3NRM-RRNS: No-error round-trip (1000 trials)
[PASS] 3NRM-RRNS: Single-bit error correction (1000 trials)
[PASS] C-RRNS-MLD: No-error round-trip (1000 trials)
[PASS] C-RRNS-MLD: Single-bit error correction (1000 trials)
[PASS] C-RRNS-MRC: No-error round-trip (1000 trials)
[PASS] RS(12,4): No-error round-trip (1000 trials)
[PASS] RS(12,4): Single-bit error correction (1000 trials)

[OK] All no-error round-trip tests passed. Ready to run run_simulation.m
```

**如果出现 [FAIL]：** 停止，检查对应的编解码器文件。

---

## 步骤三：运行完整仿真

在 MATLAB 命令窗口输入：

```matlab
run_simulation
```

**仿真参数（在 run_simulation.m 中配置）：**
- 每个 BER 点样本数：100,000（与 FPGA 一致）
- BER 点数：101（0.0% ~ 10.0%，步长 0.1%）
- 算法数：5
- 故障模式数：3（L=1, L=5, L=8）
- 总运行次数：5 × 3 = 15 次

**预估运行时间：**

| 算法 | 每次运行时间（估算） |
|------|-------------------|
| 2NRM-RRNS | ~5-10 分钟 |
| C-RRNS-MRC | ~2-3 分钟 |
| RS(12,4) | ~5-10 分钟 |
| 3NRM-RRNS | ~30-60 分钟 |
| C-RRNS-MLD | ~30-60 分钟 |
| **总计** | **~3-5 小时** |

> **提示：** 3NRM 和 C-RRNS-MLD 的 MLD 解码器需要枚举 84 个三元组，速度较慢。
> 可以先只运行 2NRM 和 RS 验证流程，再运行慢速算法。

**进度显示示例：**
```
[Run 1/15] Algo=2NRM-RRNS  BurstLen=1  Mode=Random Single Bit
  Starting BER sweep (101 points × 100000 samples)...
    BER_idx=  0  target=0.000%  actual=0.0000%  SR=1.0000
    BER_idx= 10  target=1.000%  actual=0.9998%  SR=0.9987
    ...
    BER_idx=100  target=10.000%  actual=2.4390%  SR=0.8840
  Done in 312.5 seconds.
  Saved: d:\...\src\matlab\results\test_results_20260326_081234.csv
```

---

## 步骤四：查看结果文件

仿真结果保存在：
```
d:\FPGAproject\FPGA-RRNS-Project-V2\src\matlab\results\
```

每次运行生成一个 CSV 文件，格式与 FPGA 结果完全一致：
```
test_results_20260326_081234.csv   ← 2NRM-RRNS, Random, L=1
test_results_20260326_083456.csv   ← 2NRM-RRNS, Cluster, L=5
...
```

---

## 步骤五：与 FPGA 结果对比

### 方法 A：使用现有的 compare_ber_curves.py

1. 将 MATLAB 结果 CSV 文件复制到 FPGA 结果目录：
   ```
   src\PCpython\result\sum_result\
   ```

2. 在命令行运行：
   ```bash
   cd d:\FPGAproject\FPGA-RRNS-Project-V2\src\PCpython
   python compare_ber_curves.py
   ```

3. 程序会自动识别 MATLAB 和 FPGA 的 CSV 文件（通过 Algorithm 字段），生成对比图。

> **注意：** `compare_ber_curves.py` 会将相同算法名称的最新文件用于绘图。
> 如果 MATLAB 和 FPGA 的文件都在 sum_result 目录，它们会被叠加在同一条曲线上（因为算法名相同）。
> 如果需要区分，可以在 MATLAB CSV 的 Algorithm 字段加后缀，例如将 `2NRM-RRNS` 改为 `2NRM-RRNS (MATLAB)`。

---

## 只运行单个算法（调试用）

如果只想测试某一个算法，在 MATLAB 命令窗口直接调用：

```matlab
% 只测试 2NRM-RRNS，Random Single Bit，1000 样本（快速验证）
cd('d:\FPGAproject\FPGA-RRNS-Project-V2\src\matlab')
results = ber_sweep(0, '2NRM-RRNS', 41, 1, 'Random Single Bit', 1000, 101);
```

---

## 常见问题

**Q: 出现 "Undefined function 'rsenc'"**
A: 需要安装 Communications Toolbox。在 MATLAB 中：Home → Add-Ons → 搜索 "Communications Toolbox"

**Q: 3NRM/C-RRNS-MLD 运行太慢**
A: 这是正常的，MLD 需要枚举 84 个三元组。可以先用 1000 样本验证正确性，再用 100000 样本运行完整仿真。

**Q: 如何只运行部分算法**
A: 编辑 `run_simulation.m`，注释掉不需要的算法行：
```matlab
ALGO_LIST = {
    0, '2NRM-RRNS',   41;
    % 1, '3NRM-RRNS',   48;   % 注释掉不需要的
    ...
};
```

**Q: 如何只运行部分故障模式**
A: 编辑 `run_simulation.m`，注释掉不需要的故障模式：
```matlab
FAULT_MODES = {
    1, 'Random Single Bit';
    % 5, 'Cluster (Burst)';   % 注释掉不需要的
    % 8, 'Cluster (Burst)';
};
```
