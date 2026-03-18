# Bug Fix Report — 2026-03-18

**项目：** FPGA Multi-Algorithm Fault-Tolerant Test System (2NRM-RRNS)  
**日期：** 2026-03-18  
**工具：** Vivado 2023.x，目标器件：xc7a100tcsg324-1 (Arty A7-100)  
**修复人：** Cline (AI-assisted)  
**延续自：** `docs/bug_fix_report_2026_03_17.md`（Bug #11 ~ #21）

---

## 修复汇总表

| No  | Level        | Bug 描述                                                                                                              | 根本原因                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | 修复方案                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | 进度          |
| --- | ------------ | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| 22  | **Critical** | **`py_controller_main.py` `send_command()` 发送命令前未清空串口接收缓冲区，导致响应帧头偏移，表现为"没有收到任何响应"**                                 | OS 串口驱动缓冲区在 `serial.Serial` 打开时可能已积累残留数据（FPGA 上电乱码、上次测试残留字节、USB-UART 桥初始化字节）。`send_command()` 在调用 `write()` 前**没有调用 `reset_input_buffer()`**。`receive_response()` 使用 `read(2011)` 一次性读取，读到的前几字节是残留数据而非 `0xBB 0x66`，导致帧头验证失败直接返回 `None`。                                                                                                                                                                                                                                                              | 在 `serial_conn.write(full_frame)` 前新增一行：`self.serial_conn.reset_input_buffer()`，发送命令前清空 OS 接收缓冲区，确保 `receive_response()` 始终从干净缓冲区开始读取，帧头对齐到响应帧第一字节 `0xBB`。**文件：** `src/PCpython/py_controller_main.py`，`send_command()` 函数                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | ✅ 已修复       |
| 23  | **Critical** | **`py_controller_main.py` `receive_response()` 使用固定长度读取，无帧头同步机制，帧头偏移时永久失败**                                         | 原实现调用 `serial_conn.read(2011)` 后直接验证 `raw_data[0:2] == 0xBB66`，假设第 0~1 字节一定是帧头。只要缓冲区有任何残留数据（哪怕 1 字节），帧头就会偏移，导致验证失败返回 `None`。即使 FPGA 正确发送了完整的 2011 字节响应帧，Python 端也会因帧头偏移而丢弃，表现为"没有收到任何响应"。                                                                                                                                                                                                                                                                                                            | 将固定长度读取改为**逐字节搜索 `0xBB66` 帧头**的三步流程：**Step 1** — 逐字节读取并检查最后两字节是否为 `0xBB 0x66`（带超时和字节数上限保护）；**Step 2** — 找到帧头后，一次性读取剩余 2009 字节；**Step 3** — 重组完整 2011 字节帧后继续原有解析逻辑。同时增加 Length 字段值校验警告（非致命）。**文件：** `src/PCpython/py_controller_main.py`，`receive_response()` 函数（完整重写）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | ✅ 已修复       |
| 24  | **Medium**   | **`uart_interface.vh` 注释过时：仍写"16x oversampling logic included"，与实际 v1.1 实现不符**                                      | `uart_rx_module.v` 在 Bug #7 修复（2026-03-16）中已完整重写为 1x 中心采样方案，16x 过采样逻辑已被完全移除。但 `uart_interface.vh` 中的接口注释未同步更新，仍写 `// Note: 16x oversampling logic included.`，会误导后续开发者。                                                                                                                                                                                                                                                                                                                               | 更新 `uart_interface.vh` 中 `uart_rx_module` 的注释，准确描述 v1.1 的 1x 中心采样实现：BAUD_DIV=109、HALF_BIT=54、两级同步器，并说明 16x 过采样被移除的原因。**文件：** `src/interfaces/uart_interface.vh`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | ✅ 已修复       |
| 25  | **Low**      | **`py_controller_main.py` 串口号硬编码 `COM8`，缺少命令行参数支持，用户无法在不修改源码的情况下指定串口**                                              | `DEFAULT_PORT = 'COM8'` 硬编码，若实际 USB-UART 桥分配到其他 COM 口（如 COM3、COM5），程序报错退出。同时 `open()` 失败时没有列出可用串口，用户无法快速定位正确的 COM 口。                                                                                                                                                                                                                                                                                                                                                                                 | 新增 `argparse` 命令行参数支持：`--port`（默认 `COM8`）和 `--baudrate`（默认 `921600`）。`open()` 失败时自动调用 `serial.tools.list_ports.comports()` 列出所有可用串口。用法：`python py_controller_main.py --port COM3`。**文件：** `src/PCpython/py_controller_main.py`，`main()` 函数和 `open()` 函数                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | ✅ 已修复       |
| 26  | **Critical** | **FPGA 单板无响应：SW0（复位开关）处于 OFF 位置，系统持续处于复位状态，UART RX 模块被复位，`rx_valid` 永远为 0，ILA 永远不触发**                               | `rst_n` 信号映射到 Arty A7 的 SW0（引脚 A8），是**低电平有效复位**。SW0 拨到 OFF（靠近板边缘）→ `rst_n = 0` → 系统持续复位 → UART RX 模块被复位 → `rx_valid` 永远为 0 → ILA 永远不触发。这正好解释了"FPGA 单板一侧没有任何动静"的现象。                                                                                                                                                                                                                                                                                                                                   | 将 Arty A7 板上 SW0（最靠近 USB 接口的拨码开关）拨到 **ON 位置**（向板子中心方向，即 HIGH = 3.3V），释放复位，系统正常运行。**注意：** 这是硬件操作，无需修改代码。SW0 拨到 ON 后，所有 LED 应熄灭（等待配置帧），ILA 触发后应能看到 `rx_valid` 脉冲。                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | ✅ 已解决（硬件操作） |
| 27  | **Critical** | **`encoder_wrapper.v` 在 `start=1` 时锁存 `encoder_2nrm` 的旧输出（NBA 延迟），导致编码结果错误，全部测试 FAIL（Success=0，Fail=sample_count）** | **根本原因：NBA（非阻塞赋值）时序竞争。**<br>`encoder_2nrm` 使用 NBA 在 `start=1` 时更新 `residues_out_A/B`：<br>`always @(posedge clk) if (start) residues_out_A <= packed_a;`<br>在时钟沿 T（`start=1`）：`residues_out_A` 的 NBA 在 T+1 才生效，T 时刻仍是旧值（上一次编码结果，或复位初始值 `64'd0`）。<br>原 `encoder_wrapper` 也在 `start=1` 时锁存 `out_2nrm_A`（即 `residues_out_A`），因此锁存的是旧值。<br>**后果：** 每次试验的编码结果都是上一次的编码，与当前 PRBS 符号不匹配，比较器永远 FAIL。第一次试验时旧值为复位初始值 `64'd0`，解码 0 得到 `x=0`，而 PRBS 符号是随机值，必然 FAIL。从第二次试验开始，使用的是第一次的编码结果，与第二次的 PRBS 符号不匹配，依然 FAIL。 | **双文件联合修复：**<br><br>**Fix 1（`encoder_wrapper.v` v1.1→v1.2）：** 将输出锁存触发条件从 `start=1` 改为 `done=1`。在 `done=1` 时（T+1），`encoder_2nrm.residues_out_A` 的 NBA 已生效，`out_2nrm_A`（wire）已是正确新值，锁存正确。同时新增 `algo_sel_latch` 寄存器在 `start=1` 时锁存算法选择，确保 `done=1` 时算法选择稳定。<br><br>**Fix 2（`auto_scan_engine.v`）：** `encoder_wrapper` 在 `done=1` 时通过 NBA 更新 `codeword_A`，该值在 T+2 才生效。`auto_scan_engine` 的 `ENC_WAIT` 状态原本在 `enc_done=1`（T+1）时立即锁存 `codeword_a_raw`，仍会读到旧值。修复：新增 `enc_done_d1` 寄存器，将 `enc_done` 延迟一拍，在 `enc_done_d1=1`（T+2）时再锁存 `codeword_a_raw`，此时 `encoder_wrapper.codeword_A` 已是新值。<br><br>**完整时序：**<br>T+0: `enc_start=1`，`encoder_2nrm` 开始编码（组合逻辑 `packed_a` 立即更新）<br>T+1: `enc_done=1`，`residues_out_A`=新值（NBA生效），`encoder_wrapper` NBA: `codeword_A`←新值<br>T+2: `enc_done_d1=1`，`codeword_A`=新值 ✅，`auto_scan_engine` 锁存正确编码结果<br><br>**文件：** `src/ctrl/encoder_wrapper.v`（v1.1→v1.2），`src/ctrl/auto_scan_engine.v`（新增 `enc_done_d1` 寄存器，修改 `ENC_WAIT` 状态） | ✅ 已修复       |

---

## 详细分析

### Bug #22 & #23 — Python 串口通信问题

#### 问题背景

用户通过 `py_controller_main.py` 发送测试指令到 FPGA 开发板，没有收到任何响应。

#### 串口物理层参数对比（均匹配，不是问题根源）

| 参数 | Python端 | FPGA端 | 结论 |
|------|---------|--------|------|
| 波特率 | 921600 bps | 100MHz/109 = 917,431 bps，误差0.45% | ✅ 匹配 |
| 数据位 | 8位 | 8位 | ✅ 匹配 |
| 停止位 | 1位 | 1位 | ✅ 匹配 |
| 校验位 | 无 | 无 | ✅ 匹配 |

#### 下行帧协议对比（均匹配，不是问题根源）

| 字段 | Python端 | FPGA端 | 结论 |
|------|---------|--------|------|
| Header | `0xAA 0x55` | `FRAME_HEADER_BYTE1=0xAA`, `FRAME_HEADER_BYTE2=0x55` | ✅ |
| CmdID | `CMD_REQ_ID=0x01` | `CMD_ID_CONFIG=0x01` | ✅ |
| Length | `len(payload)=7` | `PAYLOAD_LEN_CONFIG=8'd7` | ✅ |
| Payload顺序 | `[burst_len][algo_id][error_mode][sample_count 4B BE]` | `[cfg_burst_len][cfg_algo_id][cfg_error_mode][sample_count]` | ✅ |
| 总帧长 | `FRAME_LEN_REQ=12` | 12字节 | ✅ |
| 校验和 | XOR(11字节) | XOR(11字节) | ✅ |

#### Bug #22 根本原因

`serial.Serial` 打开时，OS 串口驱动缓冲区可能已积累残留数据。`send_command()` 在 `write()` 前没有调用 `reset_input_buffer()`，导致 `receive_response()` 读到残留数据而非响应帧头。

#### Bug #23 根本原因

`receive_response()` 假设 `read(2011)` 的第 0~1 字节一定是 `0xBB 0x66`，任何缓冲区偏移都会导致帧头验证失败，永久返回 `None`。

---

### Bug #26 — SW0 复位开关问题

#### 问题现象

ILA 触发条件 `rx_valid==1` 从未触发，FPGA 单板完全没有任何动静。

#### 根本原因

```
top.xdc:
  rst_n → SW0 (引脚 A8)，Active Low（低电平有效复位）

Arty A7 硬件：
  SW0 拨到 OFF（靠近板边缘）→ 输出 LOW (0V)  → rst_n = 0 → 系统持续复位 ❌
  SW0 拨到 ON （靠近板中心）→ 输出 HIGH (3.3V) → rst_n = 1 → 系统正常运行 ✅
```

当 `rst_n=0` 时，`uart_rx_module` 被复位，`rx_valid` 永远为 0，ILA 永远不触发，所有 LED 熄灭，表现为"FPGA 单板一侧没有任何动静"。

---

### Bug #27 — encoder_wrapper.v NBA 时序竞争

#### 问题现象

通信建立后，收到 FPGA 响应，但所有 91 个 BER 点的 `Success_Count=0`，`Fail_Count=sample_count`，全部失败。

#### 精确时序分析

```
encoder_2nrm.v 的输出寄存器（NBA）：
  always @(posedge clk) begin
      if (start) begin
          residues_out_A <= packed_a;  // NBA：T+1 才生效
          done           <= 1'b1;      // NBA：T+1 才生效
      end
  end

encoder_wrapper.v 原始代码（错误）：
  always @(posedge clk) begin
      else if (start) begin            // 在 start=1（T时刻）触发
          codeword_A <= {192'd0, out_2nrm_A[63:0]};  // out_2nrm_A = residues_out_A = 旧值！
      end
  end
```

**时序对比：**

| 时刻 | encoder_2nrm.residues_out_A | encoder_wrapper.codeword_A（原始） | encoder_wrapper.codeword_A（修复后） |
|------|----------------------------|-----------------------------------|--------------------------------------|
| T（start=1） | 旧值（NBA未生效） | 锁存旧值 ❌ | 不触发（等待done） |
| T+1（done=1） | 新值（NBA生效）✅ | 已锁存旧值，无法更改 | 锁存新值 ✅（NBA，T+2生效） |
| T+2 | 新值 | 旧值（错误） | 新值 ✅ |

**auto_scan_engine.v 的额外延迟：**

`encoder_wrapper` 在 `done=1`（T+1）时通过 NBA 更新 `codeword_A`，该值在 T+2 才生效。`auto_scan_engine` 的 `ENC_WAIT` 状态在 `enc_done=1`（T+1）时立即锁存 `codeword_a_raw`，仍会读到旧值。因此需要额外延迟一拍（`enc_done_d1`）。

#### 修复代码对比

**encoder_wrapper.v：**
```verilog
// 修复前（错误）：
always @(posedge clk or negedge rst_n) begin
    ...
    end else if (start) begin          // ← 在 start=1 时触发，此时 out_2nrm_A 是旧值
        case (algo_sel)
            ALGO_2NRM: codeword_A <= {192'd0, out_2nrm_A[63:0]};  // 锁存旧值 ❌
        endcase
    end
end

// 修复后（正确）：
reg [1:0] algo_sel_latch;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) algo_sel_latch <= 2'd0;
    else if (start) algo_sel_latch <= algo_sel;  // 在 start=1 时锁存算法选择
end

always @(posedge clk or negedge rst_n) begin
    ...
    end else if (done) begin           // ← 在 done=1 时触发，此时 out_2nrm_A 是新值 ✅
        case (algo_sel_latch)          // 使用锁存的算法选择（稳定）
            ALGO_2NRM: codeword_A <= {192'd0, out_2nrm_A[63:0]};  // 锁存新值 ✅
        endcase
    end
end
```

**auto_scan_engine.v（ENC_WAIT 状态）：**
```verilog
// 修复前（错误）：
if (enc_done) begin
    enc_out_a_latch <= codeword_a_raw[63:0];  // enc_done=1 时 codeword_A 仍是旧值 ❌
    state <= `ENG_STATE_INJ_WAIT;
end

// 修复后（正确）：
enc_done_d1 <= enc_done;  // 延迟一拍

if (enc_done_d1) begin    // enc_done_d1=1 时 codeword_A 已是新值 ✅
    enc_out_a_latch <= codeword_a_raw[63:0];
    enc_out_b_latch <= codeword_b_raw[63:0];
    enc_done_d1     <= 1'b0;
    state <= `ENG_STATE_INJ_WAIT;
end
```

---

## 修复文件清单

| 文件路径 | 修改类型 | 关联 Bug # |
|----------|----------|------------|
| `src/PCpython/py_controller_main.py` | 在 `send_command()` 的 `write()` 前新增 `reset_input_buffer()` 调用 | #22 |
| `src/PCpython/py_controller_main.py` | 将 `receive_response()` 改为逐字节搜索 `0xBB66` 帧头的三步流程；新增 Length 字段校验警告 | #23 |
| `src/interfaces/uart_interface.vh` | 更新 `uart_rx_module` 注释，从"16x oversampling"改为准确描述 v1.1 的 1x 中心采样实现 | #24 |
| `src/PCpython/py_controller_main.py` | 新增 `argparse` 命令行参数 `--port` 和 `--baudrate`；`open()` 失败时自动列出可用串口 | #25 |
| 无（硬件操作） | 将 Arty A7 SW0 拨到 ON 位置，释放 `rst_n` 低电平复位 | #26 |
| `src/ctrl/encoder_wrapper.v` | 将输出锁存触发条件从 `start=1` 改为 `done=1`；新增 `algo_sel_latch` 寄存器（v1.1→v1.2） | #27 |
| `src/ctrl/auto_scan_engine.v` | 新增 `enc_done_d1` 寄存器声明及复位初始化；修改 `ENC_WAIT` 状态，在 `enc_done_d1=1` 时再锁存 `codeword_a/b_raw` | #27 |
| `src/verify/tx_packet_assembler.v` | 新增 `rd_wait_done` 寄存器；将 `RD_WAIT` 状态从 1 拍扩展为 2 拍，第 2 拍才锁存 `entry_latch` | #28 |
| `src/ctrl/auto_scan_engine.v` | **Bug #29（不完整修复，已被 #33 取代）：** 新增 `inj_wait_done` 寄存器，等待 2 拍后锁存 `inj_out_a/b_latch`（实际仍只等 1 拍，见 Bug #33） | #29 |
| `src/algo_wrapper/decoder_2nrm.v` | **Bug #30（Stage 1c）：** 新增第4级 side-channel 流水线寄存器 `ri/r0..r5/valid_s1c_p3`，使 `valid_s1c` 与 `coeff_raw_s1c`（DSP PREG 输出，Cycle N+3）时间对齐。**Bug #30（Stage 1e）：** 同样新增第4级 side-channel 流水线寄存器 `r0..r5/valid_s1e_p3`，使 `valid_s1e` 与 `x_cand_16_s1e`（DSP PREG 输出，Cycle N+3）时间对齐。两处修复均适用于所有 15 个通道（共享 `decoder_channel_2nrm_param` 模块）。 | #30 |
| `src/algo_wrapper/decoder_2nrm.v` | **Bug #31（Stage 1c）：** 将 Stage 3(p3) 和 Stage 4(coeff_raw_s1c) 从同一 always 块分离为两个独立 always 块，防止 Vivado 将 NBA 链优化为单周期路径（导致 `valid_s1c` 提前到达，`dec_valid_a` 在 `comp_start` 之前到来，`lat_counting=0` 时 `valid_in=1`，`current_latency=0`，`Clk_sum=0`）。**Bug #31（Stage 1e）：** 同样将 Stage 2(p2)、Stage 3(p3)、Stage 4(x_cand_16_s1e) 各自分离为独立 always 块。 | #31 |
| `src/algo_wrapper/decoder_2nrm.v` | **Bug #32（Stage 1c）：** Bug #31 修复时将 Stage 3(p3) 和 Stage 4 移到独立 always 块，但**意外删除了原 always 块中 Stage 2(p2) 的赋值语句**（`ri_s1c_p2 <= ri_s1c_pre` 等），导致 `ri_s1c_p2`/`valid_s1c_p2` 永远为 0，整个 Stage 1c 流水线断路，`dec_valid_a` 永远不来，Watchdog 超时，全部 FAIL，`Clk_sum=0`。修复：为 Stage 2(p2) 新增独立 always 块，恢复 `ri_s1c_p2 <= ri_s1c_pre` 等赋值。 | #32 |
| `src/ctrl/auto_scan_engine.v` | **Bug #33（Bug #29 不完整修复的根本修复）：** 将 `INJ_WAIT` 状态的 1-bit `inj_wait_done` 替换为 2-bit `inj_wait_cnt` 计数器，等待 3 个周期（cnt: 0→1→2→锁存）后再锁存 `inj_out_a/b_latch`。同时修正 `prbs_generator.v` 中"每次 `prbs_valid` 应加 2"的错误注释（注释修正，无功能变更）。 | #33 |

---

## 后续建议

1. **重新综合并烧录 Bitstream**（Bug #27 修改了 RTL，必须重新综合）：
   ```
   Vivado → Run Synthesis → Run Implementation → Generate Bitstream → Program Device
   ```

2. **验证 Bug #27 修复效果**：使用相同参数（algo=0, error_mode=0, burst_len=1, sample_count=10000）重新测试，预期结果：
   - BER 较低的点（BER_Index 0~30）：`Success_Count` 应接近 `sample_count`，`Fail_Count` 应接近 0
   - BER 较高的点（BER_Index 60~90）：`Fail_Count` 应明显增加，`BER_Rate` 应接近理论值

3. **检查 ENC_WAIT 状态的 Watchdog 计数**：修复后 `ENC_WAIT` 状态多等一拍（`enc_done_d1`），总延迟从约 2 拍增加到约 3 拍，仍远低于 Watchdog 阈值（10,000 拍），不会触发超时。

4. **如果结果仍然全部 FAIL**，使用 ILA 观察以下信号（需要在 `auto_scan_engine.v` 中添加 `mark_debug` 属性）：
   - `enc_out_a_latch[40:0]`：应与 `sym_a_latch` 的 2NRM 编码结果一致
   - `inj_out_a_latch[40:0]`：注入后的码字（无注入时应与 `enc_out_a_latch` 相同）
   - `dec_out_a[15:0]`：解码结果（无注入时应与 `sym_a_latch` 相同）

## Bug #28 修复完成：tx_packet_assembler.v BRAM 读延迟对齐错误

**根本原因（精确时序分析）：**

`mem_stats_array` 使用同步读（1拍延迟）。`mem_rd_addr` 在 T 时刻通过 NBA 设置，T+1 时刻地址才稳定到 BRAM 输入，T+2 时刻 `mem_rd_data` 才输出正确数据。

原 `RD_WAIT` 状态只等 1 拍就锁存，导致每个点读取的是上一个点的数据：
- Point_ID=1 → BRAM 复位值（全0）→ BER_Index=0 ❌
- Point_ID=2 → addr=0 的数据 → BER_Index=0 ❌（这就是"前两行都为0"的原因）
- Point_ID=3 → addr=1 的数据 → BER_Index=1（偏移1）❌

**修复方案：** 在 `tx_packet_assembler.v` 中新增 `rd_wait_done` 1-bit 标志，将 `RD_WAIT` 状态扩展为 2 拍：第1拍等待 BRAM 读取，第2拍锁存有效数据。

**修改文件：** `src/verify/tx_packet_assembler.v`（新增 `rd_wait_done` 寄存器，修改 `RD_WAIT` 状态逻辑）

**Bug #28 已记录在 `docs/bug_fix_report_2026_03_18.md` 的修复文件清单中。**

**下一步：** 重新综合并烧录 Bitstream（Bug #27 和 #28 均修改了 RTL），然后重新测试，预期 BER_Index 应从 0 连续递增到 90，且 BER 较低的点 Success_Count 接近 sample_count。

---

## Bug #33 修复完成：auto_scan_engine.v INJ_WAIT 等待拍数不足（Bug #29 不完整修复）

### 问题现象

测试数据显示 100% FAIL（`Success=0, Fail=10000`），`Avg_Clk=22`（解码器正常工作），`Flip_Sum` 有值（注入器在工作），但比较结果全部失败。

### 根本原因：error_injector_unit 实际延迟为 2 拍，INJ_WAIT 只等了 1 拍

`error_injector_unit.sv` 的完整流水线延迟分析：

```
Cycle N+0 (进入 INJ_WAIT，enc_out_a_latch 稳定):
  inject_en_d1 <= inject_en_latch  (NBA，N+1 生效)
  data_in_d1   <= enc_out_a_latch  (NBA，N+1 生效)
  BRAM ena = inject_en_latch → BRAM 开始读取（1拍延迟）

Cycle N+1:
  inject_en_d1 = inject_en_latch  (NBA 已生效)
  data_in_d1   = enc_out_a_latch  (NBA 已生效)
  bram_dout 有效（BRAM 1拍延迟已完成）
  data_out <= data_in_d1 ^ bram_dout  (NBA，N+2 生效)

Cycle N+2:
  data_out = enc_out_a_latch XOR bram_dout  ✅ 有效
```

**Bug #29 的修复使用 1-bit `inj_wait_done` 标志：**

```
Cycle N+0 (inj_wait_done=0): inj_wait_done <= 1'b1  (NBA，N+1 生效)
Cycle N+1 (inj_wait_done=1): 立即锁存 inj_out_a_latch <= inj_out_a
                              ← 此时 data_out 仍是旧值！N+2 才有效！❌
```

**后果：** `inj_out_a_latch` 锁存的是上一次 trial 的 `data_out`（或复位初始值 `64'd0`）。解码器收到错误码字，解码结果与原始符号不匹配，`comp_result_a && comp_result_b` 永远为 0，100% FAIL。

### 精确时序对比

| 周期 | `data_out`（注入器输出） | Bug #29（`inj_wait_done`） | Bug #33（`inj_wait_cnt`） |
|------|------------------------|--------------------------|--------------------------|
| N+0  | 旧值（上次 trial）       | `inj_wait_done=0`，等待    | `cnt=0`，等待              |
| N+1  | 旧值（NBA 未生效）        | `inj_wait_done=1`，**锁存旧值** ❌ | `cnt=1`，等待              |
| N+2  | **新值** ✅              | 已锁存旧值，无法更改         | `cnt=2`，**锁存新值** ✅    |

### 修复代码对比

```verilog
// 修复前（Bug #29，错误）：
reg inj_wait_done;  // 1-bit 标志

// 复位：inj_wait_done <= 1'b0;

`ENG_STATE_INJ_WAIT: begin
    ...
    end else if (!inj_wait_done) begin
        inj_wait_done <= 1'b1;          // 第1拍：等待
    end else begin
        inj_out_a_latch <= inj_out_a;   // 第2拍：锁存（data_out 还没有效！❌）
        inj_wait_done   <= 1'b0;
        dec_start <= 1'b1;
        state <= `ENG_STATE_DEC_WAIT;
    end
end

// 修复后（Bug #33，正确）：
reg [1:0] inj_wait_cnt;  // 2-bit 计数器

// 复位：inj_wait_cnt <= 2'd0;

`ENG_STATE_INJ_WAIT: begin
    ...
    end else if (inj_wait_cnt < 2'd2) begin
        inj_wait_cnt <= inj_wait_cnt + 2'd1;  // 第1、2拍：等待（cnt: 0→1→2）
    end else begin
        inj_out_a_latch <= inj_out_a;   // 第3拍（cnt=2）：锁存（data_out 已有效 ✅）
        inj_wait_cnt    <= 2'd0;
        dec_start <= 1'b1;
        state <= `ENG_STATE_DEC_WAIT;
    end
end
```

### 附：问题一（Trial 计数口径）分析结论

外部分析指出"`prbs_generator.v` 注释写明每次 `prbs_valid` 应加 2，但 `main_scan_fsm` 每次 `eng_done` 只加 1"。

**结论：这不是 Bug，是注释错误。**

`auto_scan_engine` 每次 `eng_done` 将 A/B 两路结果通过 `comp_result_a && comp_result_b` 合并成一个 `result_pass` 上报，`main_scan_fsm` 每次 `eng_done` 加 1 是语义自洽的（每次 trial = A/B 联合测试一次）。`prbs_generator.v` 注释说"应加 2"是注释错误，已在本次修复中同步更正（无功能变更）。

### 修复文件

| 文件路径 | 修改类型 |
|----------|----------|
| `src/ctrl/auto_scan_engine.v` | 将 `inj_wait_done`（1-bit）替换为 `inj_wait_cnt`（2-bit）；更新复位初始化、`INJ_WAIT` 状态逻辑（watchdog 分支和主逻辑）；更新 `INJ_WAIT` 状态注释，说明 Bug #29 不完整修复的原因 |
| `src/ctrl/prbs_generator.v` | 修正"每次 `prbs_valid` 应加 2"的错误注释，改为准确描述当前实现（注释修正，无功能变更） |

### 后续验证

修复后 `INJ_WAIT` 状态多等 1 拍（共 3 拍），总 trial 延迟从约 24 拍增加到约 25 拍，`Avg_Clk` 预期从 22 变为 23。仍远低于 Watchdog 阈值（10,000 拍），不会触发超时。

**预期修复效果：**
- BER_Index 0（无注入或极低注入概率）：`Success_Count ≈ sample_count`，`Fail_Count ≈ 0`
- BER_Index 90（高注入概率）：`Fail_Count` 明显增加，`BER_Rate` 接近理论值
- `Avg_Clk ≈ 23`（比修复前多 1 拍）
