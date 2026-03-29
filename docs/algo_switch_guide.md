# Algorithm Build Switching Guide

**Project:** FPGA Multi-Algorithm Fault-Tolerant Test System  
**Target:** Arty A7-100T (xc7a100tcsg324-1)  
**Date:** 2026-03-25  
**Version:** v3.0 (Added ALL_IN_ONE_BUILD mode)

---

## 两种 Build 模式

本系统支持两种编译模式，通过 `src/interfaces/main_scan_fsm.vh` 中的宏控制：

| 模式 | 宏定义 | 说明 | 适用场景 |
|------|--------|------|---------|
| **Mode 1: ALL_IN_ONE_BUILD** | `` `define ALL_IN_ONE_BUILD `` | 7种算法全部实例化，运行时切换 | 演示、快速遍历所有算法 |
| **Mode 2: Single Algorithm** | `` `define BUILD_ALGO_xxx `` | 只实例化一种算法 | 公平资源对比、精确功耗测量 |

---

## Mode 1: ALL_IN_ONE_BUILD（新增）

### 功能说明

一个 bitstream 包含全部 7 种算法的编解码器，FPGA 根据 PC 下发指令中的 `algo_id` 字段在运行时选择对应的编码器和解码器。

### 资源消耗

- LUT 消耗约为 Single Build 的 2~3 倍（约 50% LUT）
- 功耗约为 Single Build 的 2 倍（约 0.4W vs 0.2W）
- **不适合用于公平的资源/功耗对比测试**

### 启用步骤

1. 打开 `src/interfaces/main_scan_fsm.vh`
2. 取消注释 `ALL_IN_ONE_BUILD` 行：

```verilog
`define ALL_IN_ONE_BUILD   // ← 取消注释这行（去掉前面的 //）
```

3. `BUILD_ALGO_xxx` 行**不需要修改**，它们在 ALL_IN_ONE_BUILD 模式下会被完全忽略
4. 在 Vivado 中执行完整 Implementation → Generate Bitstream
5. 下载 bitstream 到板卡

### PC 端使用（Mode A）

```bash
python py_controller_main.py
```

启动后选择 **[A] All-in-One Build**，然后：
- 输入要测试的 burst lengths（如 `1 5 8`，1=random，其他=cluster）
- 输入 sample count
- 程序自动循环：对每个 length，对 algo_id 0~6 依次测试
- 结果保存到 `src/PCpython/result/sum_result/`
- 全部完成后自动调用 `compare_ber_curves.py` 生成对比图

### 工作原理

```
main_scan_fsm.vh
    ├── `define ALL_IN_ONE_BUILD  ← 只需修改这里
    │
    ├── encoder_wrapper.v
    │   └── `ifdef ALL_IN_ONE_BUILD
    │       ├── 实例化 encoder_2nrm (algo_id=0,6)
    │       ├── 实例化 encoder_3nrm (algo_id=1)
    │       ├── 实例化 encoder_crrns (algo_id=2,3,4)
    │       └── 实例化 encoder_rs   (algo_id=5)
    │       运行时 case(algo_sel) 选择输出
    │
    └── decoder_wrapper.v
        └── `ifdef ALL_IN_ONE_BUILD
            ├── 实例化 decoder_2nrm        (algo_id=0)
            ├── 实例化 decoder_3nrm        (algo_id=1)
            ├── 实例化 decoder_crrns_mld   (algo_id=2)
            ├── 实例化 decoder_crrns_mrc   (algo_id=3)
            ├── 实例化 decoder_crrns_crt   (algo_id=4)
            ├── 实例化 decoder_rs          (algo_id=5)
            └── 实例化 decoder_2nrm_serial (algo_id=6)
            运行时 case(algo_id) 选择输出
```

---

## Mode 2: Single Algorithm Build（原有）

### 设计原则

> **每次 Implementation 只包含一个算法的编解码器实例。**
>
> 这样才能做到公平的资源消耗对比（LUT、FF、BRAM、DSP），
> 以及准确的解码延迟（时钟周期数）和纠错成功率对比。

---

## 算法总览

| algo_id | 算法名称 | 编码器文件 | 解码器文件 | 码字长度 | 纠错能力 | 解码延迟 |
|---------|---------|-----------|-----------|---------|---------|---------|
| 0 | 2NRM-RRNS (Parallel) | encoder_2nrm.v | decoder_2nrm.v | 41 bits | t=2 | ~27 cycles |
| 1 | 3NRM-RRNS | encoder_3nrm.v | decoder_3nrm.v | 48 bits | t=3 | ~842 cycles |
| 2 | C-RRNS-MLD | encoder_crrns.v | decoder_crrns_mld.v | 61 bits | t=3 (100%) | ~924 cycles |
| 3 | C-RRNS-MRC | encoder_crrns.v | decoder_crrns_mrc.v | 61 bits | 无纠错 | ~8 cycles |
| 4 | C-RRNS-CRT | encoder_crrns.v | decoder_crrns_crt.v | 61 bits | 无纠错 | ~5 cycles |
| 5 | RS(12,4) | encoder_rs.v | decoder_rs.v | 48 bits | t=4 (100%) | ~60 cycles |
| 6 | 2NRM-RRNS-Serial | encoder_2nrm.v | decoder_2nrm_serial.v | 41 bits | t=2 | ~363 cycles |

> **注：** algo_id=0 (Parallel) 和 algo_id=6 (Serial) 使用相同的编码器，解码算法也完全相同，只是硬件架构不同：Parallel 使用 15 个并行 CRT 通道（低延迟、高资源），Serial 使用顺序 FSM（高延迟、低资源）。

---

## 切换方法：只需修改一个文件！

### 唯一需要修改的文件

```
src/interfaces/main_scan_fsm.vh
```

### 操作步骤

1. 打开 `src/interfaces/main_scan_fsm.vh`
2. 找到以下代码块（约第 20 行）：

```verilog
// -----------------------------------------------------------------
// `define BUILD_ALGO_2NRM        // algo_id=0: 2NRM-RRNS,   41b, t=2,  ~27 cycles
// `define BUILD_ALGO_3NRM        // algo_id=1: 3NRM-RRNS,   48b, t=3,  ~842 cycles
// `define BUILD_ALGO_CRRNS_MLD   // algo_id=2: C-RRNS-MLD,  61b, t=3,  ~924 cycles
// `define BUILD_ALGO_CRRNS_MRC   // algo_id=3: C-RRNS-MRC,  61b, none, ~8 cycles
// `define BUILD_ALGO_CRRNS_CRT   // algo_id=4: C-RRNS-CRT,  61b, none, ~5 cycles
`define BUILD_ALGO_RS              // algo_id=5: RS(12,4),    48b, t=4,  ~60 cycles
// -----------------------------------------------------------------
```

3. **注释掉当前激活的行，取消注释目标算法的行**（确保只有一行没有 `//`）
4. 保存文件
5. 在 Vivado 中执行 **完整 Implementation**（Run Implementation → Generate Bitstream）

---

## 各算法切换示例

### 切换到 2NRM-RRNS (algo_id=0)

```verilog
`define BUILD_ALGO_2NRM        // ← 取消注释这行
// `define BUILD_ALGO_3NRM
// `define BUILD_ALGO_CRRNS_MLD
// `define BUILD_ALGO_CRRNS_MRC
// `define BUILD_ALGO_CRRNS_CRT
// `define BUILD_ALGO_RS        // ← 注释掉这行
```

### 切换到 3NRM-RRNS (algo_id=1)

```verilog
// `define BUILD_ALGO_2NRM
`define BUILD_ALGO_3NRM        // ← 取消注释这行
// `define BUILD_ALGO_CRRNS_MLD
// `define BUILD_ALGO_CRRNS_MRC
// `define BUILD_ALGO_CRRNS_CRT
// `define BUILD_ALGO_RS        // ← 注释掉这行
```

### 切换到 C-RRNS-MLD (algo_id=2)

```verilog
// `define BUILD_ALGO_2NRM
// `define BUILD_ALGO_3NRM
`define BUILD_ALGO_CRRNS_MLD   // ← 取消注释这行
// `define BUILD_ALGO_CRRNS_MRC
// `define BUILD_ALGO_CRRNS_CRT
// `define BUILD_ALGO_RS        // ← 注释掉这行
```

### 切换到 C-RRNS-MRC (algo_id=3)

```verilog
// `define BUILD_ALGO_2NRM
// `define BUILD_ALGO_3NRM
// `define BUILD_ALGO_CRRNS_MLD
`define BUILD_ALGO_CRRNS_MRC   // ← 取消注释这行
// `define BUILD_ALGO_CRRNS_CRT
// `define BUILD_ALGO_RS        // ← 注释掉这行
```

### 切换到 C-RRNS-CRT (algo_id=4)

```verilog
// `define BUILD_ALGO_2NRM
// `define BUILD_ALGO_3NRM
// `define BUILD_ALGO_CRRNS_MLD
// `define BUILD_ALGO_CRRNS_MRC
`define BUILD_ALGO_CRRNS_CRT   // ← 取消注释这行
// `define BUILD_ALGO_RS        // ← 注释掉这行
```

### 切换到 RS(12,4) (algo_id=5)

```verilog
// `define BUILD_ALGO_2NRM
// `define BUILD_ALGO_3NRM
// `define BUILD_ALGO_CRRNS_MLD
// `define BUILD_ALGO_CRRNS_MRC
// `define BUILD_ALGO_CRRNS_CRT
`define BUILD_ALGO_RS              // ← 取消注释这行
// `define BUILD_ALGO_2NRM_SERIAL
```

### 切换到 2NRM-RRNS-Serial (algo_id=6) ← **当前 Build**

```verilog
// `define BUILD_ALGO_2NRM
// `define BUILD_ALGO_3NRM
// `define BUILD_ALGO_CRRNS_MLD
// `define BUILD_ALGO_CRRNS_MRC
// `define BUILD_ALGO_CRRNS_CRT
// `define BUILD_ALGO_RS
`define BUILD_ALGO_2NRM_SERIAL     // ← 当前激活
```

> **说明：** 2NRM-RRNS-Serial 与 2NRM-RRNS (Parallel) 使用相同的编码器 (`encoder_2nrm`)，
> 解码算法完全相同，但解码器采用顺序 FSM 实现（`decoder_2nrm_serial`），
> 延迟约 363 cycles，LUT 消耗约 2~3%（vs Parallel 的 22%）。

---

## 工作原理

编译宏通过以下机制自动控制整个系统：

```
main_scan_fsm.vh
    ├── `define BUILD_ALGO_RS  ← 你只需修改这里
    │
    ├── 自动推导 CURRENT_ALGO_ID = 5
    │
    ├── encoder_wrapper.v (`include "main_scan_fsm.vh")
    │   └── `ifdef BUILD_ALGO_RS → 实例化 encoder_rs
    │       `else → wire-tie 其他编码器
    │
    └── decoder_wrapper.v (`include "main_scan_fsm.vh")
        └── `ifdef BUILD_ALGO_RS → 实例化 decoder_rs
            `else → wire-tie 其他解码器
```

**一处修改，全局生效，不会遗漏任何文件。**

---

## 快速切换检查清单

```
□ 1. 打开 src/interfaces/main_scan_fsm.vh
□ 2. 注释掉当前 `define BUILD_ALGO_xxx
□ 3. 取消注释目标 `define BUILD_ALGO_xxx
□ 4. 确认只有一行 `define BUILD_ALGO_xxx 没有注释
□ 5. 保存文件
□ 6. Vivado: Run Implementation (完整重新综合)
□ 7. Vivado: Generate Bitstream
□ 8. 下载 bitstream 到板卡
□ 9. 运行 py_controller_main.py 测试
□ 10. 记录资源利用率 (Utilization Report)
```

---

## 资源利用率记录表

每次 Implementation 完成后，记录以下数据（来自 Vivado Utilization Report）：

| 算法 | LUT | FF | BRAM | DSP | 解码延迟(cycles) | 纠错成功率@BER=1.5% |
|------|-----|-----|------|-----|-----------------|---------------------|
| 2NRM-RRNS | - | - | - | - | ~27 | - |
| 3NRM-RRNS | - | - | - | - | ~842 | ~93% |
| C-RRNS-MLD | - | - | - | - | ~924 | ~100% |
| C-RRNS-MRC | - | - | - | - | ~8 | ~0% |
| C-RRNS-CRT | - | - | - | - | ~5 | ~0% |
| **RS(12,4)** | **-** | **-** | **-** | **-** | **~115** | **~98.4%** |

> 注：解码延迟 = Avg_Clk_Per_Trial（含系统开销），纠错成功率取 BER_Value_Act ≈ 1.5% 时的数据。

---

## 注意事项

1. **C-RRNS-MRC 和 C-RRNS-CRT 共用编码器**：两者都使用 `encoder_crrns`，只有解码器不同。宏 `BUILD_ALGO_CRRNS_MRC` 和 `BUILD_ALGO_CRRNS_CRT` 都会激活 `encoder_crrns`。

2. **每次切换后必须完整重新综合**：因为编解码器实例化发生了变化（`ifdef 控制），不能只重新 Implementation，必须从 Synthesis 开始。

3. **watchdog 超时设置**：不同算法解码延迟差异很大（5~924 cycles），系统 watchdog 设置为 10,000 cycles，对所有算法都有足够余量。

4. **Avg_Clk_Per_Trial 包含系统开销**：实际解码器延迟 = Avg_Clk_Per_Trial - 系统固定开销（约 55 cycles）。

5. **资源对比时使用 "Slice Logic" 部分**：在 Vivado Utilization Report 中，查看 "Slice Logic" 下的 LUT 和 FF 数量，这才是算法本身的资源消耗（不含 UART、时钟等固定开销）。
