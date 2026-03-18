# Vivado ILA 调试操作指南 — UART 通信故障排查

**项目：** FPGA Multi-Algorithm Fault-Tolerant Test System  
**日期：** 2026-03-18  
**目的：** 通过板载 ILA（Integrated Logic Analyzer）逐层定位 UART 通信无响应的根本原因  
**前提：** Bitstream 已包含 ILA 核（`top.xdc` 中已配置 `create_debug_core u_ila_0`）

---

## 一、ILA 探针清单（当前已配置）

当前 Bitstream 中共有 **8 个 ILA 探针**，分布在 3 个信号层：

| Probe | 信号名 | 位宽 | 所在层 | 含义 |
|-------|--------|------|--------|------|
| probe0 | `parser_state_dbg[2:0]` | 3-bit | Layer 2 | 协议解析器 FSM 状态（0=IDLE, 1=HDR2, 2=CMD, 3=LEN, 4=PAYLOAD, 5=CHKSUM） |
| probe1 | `rx_byte[7:0]` | 8-bit | Layer 1 | UART RX 接收到的字节值 |
| probe2 | `cfg_update_pulse` | 1-bit | Layer 2 | 有效配置帧接收完成脉冲（高电平=解析成功） |
| probe3 | `checksum_error` | 1-bit | Layer 2 | 校验和错误标志（高电平=校验失败） |
| probe4 | `config_locked` | 1-bit | Layer 3 | 配置已锁定（高电平=测试参数已锁存） |
| probe5 | `rx_error` | 1-bit | Layer 1 | UART 帧错误（高电平=停止位不为1，波特率不匹配） |
| probe6 | `rx_valid` | 1-bit | Layer 1 | UART 字节接收完成脉冲（每收到1字节高1个时钟周期） |
| probe7 | `test_active` | 1-bit | Layer 3 | 测试激活标志（高电平=FSM 已启动扫描） |

**ILA 时钟：** `clk_sys_IBUF_BUFG`（100 MHz）  
**采样深度：** 1024 个时钟周期

---

## 二、Vivado Hardware Manager 连接步骤

### 步骤 1：打开 Hardware Manager

```
Vivado 主界面 → 菜单栏 → Flow → Open Hardware Manager
```
或点击左侧 **Flow Navigator** 底部的 **Open Hardware Manager**。

### 步骤 2：连接开发板

1. 点击 Hardware Manager 顶部蓝色横幅中的 **"Open target"**
2. 选择 **"Auto Connect"**
3. 等待连接成功，左侧 Hardware 面板出现：
   ```
   localhost (Local server)
   └── xilinx_tcf/Digilent/...
       └── xc7a100t_0
           ├── XADC (System Monitor)
           └── u_ila_0 (ILA)
   ```

### 步骤 3：下载 Bitstream（如未下载）

1. 右键点击 `xc7a100t_0` → **"Program Device..."**
2. 选择 `.bit` 文件路径（通常在 `FPGAProjectV2/FPGAProjectV2.runs/impl_1/top_fault_tolerance_test.bit`）
3. 点击 **"Program"**，等待下载完成（约10秒）

### 步骤 4：打开 ILA 波形窗口

1. 在 Hardware 面板中双击 **`u_ila_0`**
2. 波形窗口（Waveform）自动打开，显示所有 8 个探针

---

## 三、触发器配置（针对 UART 调试）

### 方案 A：触发在 UART 开始接收（推荐首次调试）

**目标：** 捕获 PC 发送命令后 FPGA 的完整接收过程

在 ILA 的 **Trigger Setup** 窗口中配置：

| 设置项 | 值 |
|--------|-----|
| Trigger mode | `BASIC` |
| Trigger condition | `rx_valid == 1` |
| Trigger position | `1`（触发点在采样窗口左侧第1格，留出1023格观察后续） |

**操作步骤：**
1. 在 Trigger Setup 窗口，点击 **"+"** 添加触发条件
2. 选择 `probe6`（`rx_valid`）
3. 设置 Value = `1`，Radix = `Binary`
4. 点击 **"Run Trigger"**（绿色三角按钮）
5. 在 Python 端运行脚本发送命令
6. ILA 触发后自动停止，波形窗口显示捕获数据

---

### 方案 B：触发在校验和错误（排查协议问题）

**目标：** 确认是否存在校验和不匹配

| 设置项 | 值 |
|--------|-----|
| Trigger condition | `checksum_error == 1` |
| Trigger position | `512`（触发点居中，可观察前后各512个周期） |

---

### 方案 C：触发在配置更新脉冲（确认解析成功）

**目标：** 确认协议解析器是否成功解析了完整帧

| 设置项 | 值 |
|--------|-----|
| Trigger condition | `cfg_update_pulse == 1` |
| Trigger position | `1` |

---

## 四、逐层诊断流程

按以下顺序逐层排查，每层根据观察结果决定是否继续下一层。

---

### 🔍 Layer 1 诊断：物理 UART 接收层

**使用探针：** `rx_valid`（probe6）、`rx_byte`（probe1）、`rx_error`（probe5）

**触发配置：** 方案 A（`rx_valid == 1`）

**发送命令后，观察波形：**

#### ✅ 正常现象（Layer 1 工作正常）：
```
时间轴 →
rx_valid:  ___|‾|___|‾|___|‾|___|‾|___|‾|___|‾|___|‾|___|‾|___|‾|___|‾|___|‾|___|‾|___
           (每个脉冲对应接收到1个字节，共12个脉冲)
rx_byte:   [AA][55][01][07][BL][AI][EM][S3][S2][S1][S0][CS]
           (依次显示12字节的值，与Python发送的帧一致)
rx_error:  _______________________________________________（始终为0）
```

其中：
- `BL` = burst_len（你输入的值）
- `AI` = algo_id（你输入的值）
- `EM` = error_mode（你输入的值）
- `S3~S0` = sample_count 的4字节 Big-Endian
- `CS` = XOR校验字节

#### ❌ 异常现象及原因：

| 现象 | 原因 | 解决方案 |
|------|------|---------|
| `rx_valid` **始终为0**，无任何脉冲 | FPGA 完全没有收到数据 | 检查：①串口号是否正确（设备管理器确认）②USB线是否连接③FTDI驱动是否安装 |
| `rx_valid` 有脉冲，但 `rx_byte` 值全部错误（不是 `0xAA`开头） | 波特率不匹配 | 检查 FPGA 时钟是否真的是100MHz（测量 `clk_sys` 频率） |
| `rx_error` **出现高电平** | 停止位采样失败，帧格式错误 | 波特率偏差过大，或信号质量问题（检查USB线） |
| `rx_valid` 只有 **少于12个脉冲** | 数据传输中断 | Python端 `write()` 是否完整发送了12字节（检查 `flush()` 是否生效） |
| `rx_byte` 序列正确但 **顺序错误** | 不可能（UART是串行协议） | 不适用 |

**关键验证：** 在波形中右键 `rx_byte` → **"Radix" → "Hexadecimal"**，确认12字节序列为：
```
AA 55 01 07 [BL] [AI] [EM] [S3] [S2] [S1] [S0] [CS]
```

---

### 🔍 Layer 2 诊断：协议解析层

**前提：** Layer 1 已确认 `rx_valid` 有12个脉冲且 `rx_byte` 序列正确

**使用探针：** `parser_state_dbg`（probe0）、`cfg_update_pulse`（probe2）、`checksum_error`（probe3）

**触发配置：** 方案 A（`rx_valid == 1`）

**观察 `parser_state_dbg` 的状态转换序列：**

#### ✅ 正常现象（Layer 2 工作正常）：
```
时间轴 →（每个 rx_valid 脉冲对应一次状态转换）
parser_state_dbg: [0][0→1][1→2][2→3][3→4][4][4][4][4][4][4→5][5→0]
                   ↑  ↑AA  ↑55  ↑01  ↑07  ↑BL ↑AI ↑EM ↑S3 ↑S6  ↑CS  ↑回IDLE
                  IDLE HDR2 CMD  LEN  PLD  ...              CHKSUM

cfg_update_pulse: _____________________________________|‾|___
                  (在最后一个字节CS被接收后，出现1个时钟周期的高电平)

checksum_error:   _______________________________________________（始终为0）
```

状态值对应关系：
- `3'd0` = ST_IDLE
- `3'd1` = ST_WAIT_HDR_2
- `3'd2` = ST_READ_CMD
- `3'd3` = ST_READ_LEN
- `3'd4` = ST_READ_PAYLOAD
- `3'd5` = ST_CHECK_SUM

#### ❌ 异常现象及原因：

| 现象 | 原因 | 解决方案 |
|------|------|---------|
| `parser_state_dbg` **始终为0**，从不变化 | Layer 1 问题（rx_valid 没有到达 parser） | 先解决 Layer 1 问题 |
| 状态从 0 跳到 1，然后**立即回到 0** | 收到 `0xAA` 后，下一字节不是 `0x55` | 检查 Python 发送的 `HEADER_REQ = bytes([0xAA, 0x55])` |
| 状态到达 2 后**立即回到 0** | CmdID 不是 `0x01` | 检查 Python 的 `CMD_REQ_ID = 0x01` |
| 状态到达 3 后**立即回到 0** | Length 字节不是 `0x07` | 检查 Python 的 `length_byte = len(payload) = 7` |
| 状态到达 5（CHKSUM）后，`checksum_error = 1` | 校验和不匹配 | 用 Python 打印 `full_frame.hex()` 手动验证校验和 |
| 状态序列正确，但 `cfg_update_pulse` **始终为0** | 校验和比较失败（但 `checksum_error` 也为0？） | 不可能，检查 ILA 采样深度是否足够 |

**关键操作：** 在波形中将 `parser_state_dbg` 的 Radix 设为 **"Unsigned Decimal"**，可以直接看到 0~5 的状态值。

---

### 🔍 Layer 3 诊断：控制流层

**前提：** Layer 2 已确认 `cfg_update_pulse` 出现了高电平脉冲

**使用探针：** `config_locked`（probe4）、`test_active`（probe7）

**触发配置：** 方案 C（`cfg_update_pulse == 1`）

**观察波形：**

#### ✅ 正常现象（Layer 3 工作正常）：
```
时间轴 →
cfg_update_pulse: __|‾|______________
                    ↑T0

config_locked:    _____|‾‾‾‾‾‾‾‾‾‾‾‾
                       ↑T1（T0后1拍，NBA延迟）

test_active:      _____|‾‾‾‾‾‾‾‾‾‾‾‾
                       ↑T1（与config_locked同拍）
```

`test_active` 变为高电平后，`main_scan_fsm` 会检测到 `sys_start` 的上升沿，开始91点BER扫描。此时 `LED[1]`（running）应该亮起。

#### ❌ 异常现象及原因：

| 现象 | 原因 | 解决方案 |
|------|------|---------|
| `cfg_update_pulse=1` 后，`config_locked` **始终为0** | `ctrl_register_bank` 的 `tx_busy` 保护触发（UART TX 正在发送时拒绝新配置） | 等待 UART TX 空闲后再发送命令（正常情况下首次发送不会触发此问题） |
| `config_locked=1` 但 `test_active` **始终为0** | `ctrl_register_bank` 内部逻辑错误 | 检查 `ctrl_register_bank.v` 的 `test_done_flag` 是否异常高电平 |
| `test_active=1` 但 FPGA **LED[1] 不亮** | `main_scan_fsm` 的边沿检测逻辑问题 | 检查 `sys_start_pulse` 是否产生（需要额外探针） |

---

## 五、快速诊断决策树

```
发送命令后 FPGA 无响应
│
├─ ILA 触发了吗？（rx_valid 有脉冲）
│   │
│   ├─ 否 → 物理连接问题
│   │        ① 确认串口号（设备管理器）
│   │        ② 确认 USB 线连接
│   │        ③ 确认 FTDI 驱动安装
│   │        ④ 用串口助手（如 PuTTY）发送 0xAA 测试
│   │
│   └─ 是 → rx_byte 序列正确吗？（AA 55 01 07 ...）
│            │
│            ├─ 否，rx_error=1 → 波特率不匹配
│            │   检查 FPGA 时钟是否真的是 100MHz
│            │
│            ├─ 否，字节值错误 → 波特率偏差
│            │   BAUD_DIV 计算：100MHz/921600 = 108.5 → 109（已正确）
│            │
│            └─ 是 → parser_state_dbg 到达 5 了吗？
│                     │
│                     ├─ 否，卡在某个状态 → 帧格式不匹配
│                     │   对照状态值找到卡住的字节
│                     │
│                     ├─ 是，checksum_error=1 → 校验和错误
│                     │   打印 Python 发送的帧十六进制，手动验证
│                     │
│                     └─ 是，cfg_update_pulse=1 → 解析成功！
│                              │
│                              └─ test_active=1 了吗？
│                                  │
│                                  ├─ 是 → FSM 已启动，等待测试完成
│                                  │       观察 LED[1] 是否亮起
│                                  │       测试完成后 LED[2] 亮起（UART TX 发送中）
│                                  │
│                                  └─ 否 → ctrl_register_bank 问题
│                                          检查 tx_busy 是否异常
```

---

## 六、Vivado Tcl Console 快速命令

连接开发板后，可在 Vivado **Tcl Console** 中使用以下命令快速操作：

```tcl
# 连接开发板
open_hw_manager
connect_hw_server
open_hw_target

# 下载 Bitstream（修改路径为实际路径）
set_property PROGRAM.FILE {D:/FPGAproject/FPGA-RRNS-Project-V2/FPGAProjectV2/FPGAProjectV2.runs/impl_1/top_fault_tolerance_test.bit} [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]

# 设置 ILA 触发条件：rx_valid == 1
set_property CONTROL.TRIGGER_CONDITION AND [get_hw_ilas u_ila_0]
set_property TRIGGER_COMPARE_VALUE eq1'b1 [get_hw_probes u_ila_0/probe6]

# 设置触发位置（触发点在第1个采样，后面1023个采样观察后续）
set_property CONTROL.TRIGGER_POSITION 1 [get_hw_ilas u_ila_0]

# 运行触发（等待触发条件满足）
run_hw_ila [get_hw_ilas u_ila_0]

# 等待触发完成（此时在 Python 端发送命令）
wait_on_hw_ila [get_hw_ilas u_ila_0]

# 上传波形数据到 Vivado
upload_hw_ila_data [get_hw_ilas u_ila_0]

# 在波形窗口显示
display_hw_ila_data [get_hw_ila_data upload_hw_ila_data_1]
```

---

## 七、关键波形截图要点

调试时请截图保存以下关键时刻的波形，便于后续分析：

1. **截图1：** 触发后的完整波形（显示所有8个探针，时间轴覆盖全部12字节接收过程）
2. **截图2：** 放大 `rx_valid` 第一个脉冲附近（确认 `rx_byte = 0xAA`）
3. **截图3：** 放大 `parser_state_dbg` 的状态转换序列
4. **截图4：** 放大 `cfg_update_pulse` 脉冲附近（确认 `config_locked` 和 `test_active` 的响应时序）

---

## 八、如果 ILA 无法触发（采样深度不足）

当前 ILA 采样深度为 **1024 个时钟周期**（在 `top.xdc` 中设置：`set_property C_DATA_DEPTH 1024`）。

接收12字节的时间 = 12 × 10 bits × (1/921600) × 100MHz ≈ 12 × 10 × 108.5 ≈ **13,020 个时钟周期**。

**1024 个采样深度不足以覆盖完整的12字节接收过程！**

### 解决方案：增大 ILA 采样深度

在 `top.xdc` 中修改：
```tcl
# 修改前：
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]

# 修改后（16384 个采样，覆盖约 163ms，足够捕获完整帧）：
set_property C_DATA_DEPTH 16384 [get_debug_cores u_ila_0]
```

修改后需要重新运行 **Implementation** 和 **Generate Bitstream**，然后重新下载。

> **注意：** 增大采样深度会消耗更多 BRAM 资源。16384 深度 × 14-bit（8个探针总位宽）= 229,376 bits ≈ 7 个 BRAM36，Arty A7-100 有 135 个 BRAM36，资源充足。

---

## 九、补充：用串口助手验证物理层（无需 ILA）

在使用 ILA 之前，可以先用 **串口助手**（如 PuTTY、MobaXterm、或 Windows 自带的 HyperTerminal）快速验证物理层：

1. 打开串口助手，设置：波特率 921600，8N1，无流控
2. 以十六进制模式发送：`AA 55 01 07 01 00 00 00 00 03 E8 XX`（XX为校验和）
3. 观察是否收到 `BB 66 81 07 D5 ...` 开头的响应

如果串口助手能收到响应，说明 FPGA 端完全正常，问题在 Python 脚本端。  
如果串口助手也收不到响应，说明问题在 FPGA 端，需要用 ILA 进一步排查。
