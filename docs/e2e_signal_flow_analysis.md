# FPGA-RRNS 系统端到端信号流分析报告

**文档版本**: v1.0  
**分析日期**: 2026-03-14  
**分析范围**: PC 端 Python 脚本 → UART → FPGA 全链路 → UART → PC 端解析  
**基于代码版本**: 经过第一至第七轮代码审查修复后的最终版本

---

## 一、系统总体架构

`
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PC 端 (py_controller_main.py)                       │
│  用户输入 → send_command() → 12字节配置帧 → serial.write()                  │
│  serial.read(2011字节) → receive_response() → 解析 → CSV/打印               │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │ UART 921600bps
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FPGA (top_fault_tolerance_test.v)                        │
│                                                                             │
│  uart_rx_module → protocol_parser → ctrl_register_bank                     │
│                                           │                                 │
│                                    main_scan_fsm                            │
│                                    (91点BER扫描)                             │
│                                           │                                 │
│                                    auto_scan_engine (×N次/点)               │
│                                    [PRBS→编码→注入→解码→比较]               │
│                                           │                                 │
│                                    mem_stats_array (91×176bit)              │
│                                           │                                 │
│                                    tx_packet_assembler → uart_tx_module     │
└─────────────────────────────────────────────────────────────────────────────┘
`

---

## 二、下行链路：配置帧发送（PC → FPGA）

### 2.1 PC 端帧构造（py_controller_main.py: send_command）

**示例参数**：algo_id=0(2NRM), error_mode=1(Burst), burst_len=3, sample_count=100

`python
payload[0] = burst_len   = 0x03
payload[1] = algo_id     = 0x00
payload[2] = error_mode  = 0x01
payload[3:7] = struct.pack('>I', 100) = [0x00, 0x00, 0x00, 0x64]
`

**完整12字节帧**：

| 字节偏移 | 值 | 含义 |
|---------|-----|------|
| 0 | 0xAA | Header Byte 1 |
| 1 | 0x55 | Header Byte 2 |
| 2 | 0x01 | CMD_ID_CONFIG |
| 3 | 0x07 | Payload Length = 7 |
| 4 | 0x03 | burst_len = 3 |
| 5 | 0x00 | algo_id = 0 (2NRM) |
| 6 | 0x01 | error_mode = 1 (Burst) |
| 7 | 0x00 | sample_count[31:24] |
| 8 | 0x00 | sample_count[23:16] |
| 9 | 0x00 | sample_count[15:8] |
| 10 | 0x64 | sample_count[7:0] = 100 |
| 11 | XOR(0..10) | Checksum |

**Checksum 计算**：0xAA^0x55^0x01^0x07^0x03^0x00^0x01^0x00^0x00^0x00^0x64 = 0xC3

### 2.2 FPGA UART 接收（uart_rx_module）

- 波特率：921600 bps，BAUD_DIV = 109（@ 100MHz）
- 每字节：1起始位 + 8数据位 + 1停止位 = 10位
- 每字节传输时间：10 / 921600 ≈ 10.85 μs
- 12字节帧总传输时间：≈ 130 μs
- 输出：rx_valid（单周期脉冲）+ rx_byte（8bit）

### 2.3 协议解析（protocol_parser.v）

**FSM 状态序列**（每收到一个有效字节推进一步）：

`
IDLE → ST_WAIT_HDR_2 → ST_READ_CMD → ST_READ_LEN → ST_READ_PAYLOAD(×7) → ST_CHECK_SUM
`

**Payload 字节捕获**（ST_READ_PAYLOAD 状态）：

| payload_byte_count | 捕获寄存器 | 示例值 |
|-------------------|-----------|--------|
| 0 | cfg_burst_len | 0x03 |
| 1 | cfg_algo_id | 0x00 |
| 2 | cfg_error_mode | 0x01 |
| 3 | sample_count_buffer[31:24] | 0x00 |
| 4 | sample_count_buffer[23:16] | 0x00 |
| 5 | sample_count_buffer[15:8] | 0x00 |
| 6 | sample_count_buffer[7:0] | 0x64 |

**校验通过后**（ST_CHECK_SUM 状态）：
- cfg_update_pulse ← 1（单周期脉冲）
- cfg_sample_count ← sample_count_buffer = 32'd100

### 2.4 寄存器锁存（ctrl_register_bank.v）

**触发条件**：cfg_update_pulse=1 且 tx_busy=0（UART 空闲）

`erilog
// 优先级：test_done_flag > cfg_update_pulse（已修复警告-4）
if (test_done_flag) begin
    test_active   <= 0;
    config_locked <= 0;
end else if (cfg_update_pulse && !tx_busy) begin
    reg_burst_len    <= cfg_burst_len_in;    // 0x03
    reg_algo_id      <= cfg_algo_id_in;      // 0x00
    reg_error_mode   <= cfg_error_mode_in;   // 0x01
    reg_sample_count <= cfg_sample_count_in; // 32'd100
    test_active      <= 1;
    config_locked    <= 1;
end
`

**时序**（T 为 cfg_update_pulse 到来的时钟沿）：

| 时钟 | 事件 |
|------|------|
| T+0 | cfg_update_pulse=1，NBA 赋值：reg_sample_count←100，test_active←1，config_locked←1 |
| T+1 | reg_sample_count=100，test_active=1，config_locked=1（NBA 生效） |
| T+1 | cfg_update_pulse_d1=1（延迟寄存器生效，用于 seed_lock_unit） |

### 2.5 种子锁存（seed_lock_unit.v）

**修复 P2 后的时序**（使用 cfg_update_pulse_d1）：

`
T+0: cfg_update_pulse=1, config_locked←1(NBA未生效)
T+1: cfg_update_pulse_d1=1, config_locked=1 → 条件满足
     seed_locked ← free_counter（当前值，作为PRBS种子）
     seed_valid  ← 1
`

**free_counter**：32位自由计数器，每周期+1，提供随机熵。

### 2.6 FSM 启动触发（main_scan_fsm.v）

**sys_start 上升沿检测**（修复 P1 后）：

`erilog
sys_start_prev  ← sys_start（每周期更新）
sys_start_pulse = sys_start && !sys_start_prev  // 仅在0→1跳变时为1
`

**触发序列**：

| 时钟 | sys_start | sys_start_prev | sys_start_pulse | FSM 状态 |
|------|-----------|----------------|-----------------|---------|
| T+0 | 0 | 0 | 0 | IDLE |
| T+1 | 1 | 0 | **1** | IDLE→INIT_CFG |
| T+2 | 1 | 1 | 0 | INIT_CFG |

**sample_count 到达 FSM**：

`
py: sample_count=100
→ payload[3:7] = [0x00,0x00,0x00,0x64]
→ protocol_parser: cfg_sample_count = 32'h00000064 = 100
→ ctrl_register_bank: reg_sample_count = 100
→ top_fault_tolerance_test: .sample_count(reg_sample_count)
→ main_scan_fsm: sample_count = 100
→ RUN_TEST 状态: trial_cnt 从 0 累加到 99，共运行 100 次试验
`

**✅ 端到端验证**：Python 设置 sample_count=100，FSM 每个 BER 点精确运行 100 次试验。

---

## 三、FPGA 内部处理链路

### 3.1 BER 扫描主循环（main_scan_fsm.v）

**FSM 状态流**：

`
IDLE
  ↓ sys_start_pulse
INIT_CFG ──→ rom_req=1 ──→ thresh_valid=1
  ↓
RUN_TEST ──→ eng_start=1 ──→ eng_done=1（重复 sample_count 次）
  ↓（trial_cnt+1 >= sample_count）
SAVE_RES ──→ mem_we_a=1，写入 176bit 统计数据到 mem[ber_cnt]
  ↓
NEXT_ITER ──→ ber_cnt++，清零累加器
  ↓（ber_cnt < 91）→ 回到 INIT_CFG
  ↓（ber_cnt == 90）
PREP_UPLOAD ──→ asm_start=1
  ↓
DO_UPLOAD ──→ 等待 asm_done
  ↓
FINISH ──→ done=1，回到 IDLE
`

**ROM 查表**（INIT_CFG 状态）：

`
地址 = (CURRENT_ALGO_ID × 1365) + (ber_cnt × 15) + (burst_len - 1)
     = (0 × 1365) + (0 × 15) + (3 - 1)  [第一个BER点，burst_len=3]
     = 2
threshold_val = threshold_table.coe[2]
              = round((0.01 × 41 / 3) × (2^32-1))
              = round(0.1367 × 4294967295)
              = 587,202,197 = 0x2302F5D5
`

### 3.2 单次试验流水线（auto_scan_engine.v）

**流水线时序**（每次试验约 8 个时钟周期）：

`
周期 1: CONFIG  - 注入决策：inj_lfsr < threshold_val？
周期 2: GEN_WAIT - PRBS 生成，sym_a=prbs[31:16], sym_b=prbs[15:0]
周期 3: ENC_WAIT - 编码器输出（1周期延迟），发出 comp_start
周期 4: INJ_WAIT - 注入器输出（1周期延迟），发出 dec_start
周期 5-6: DEC_WAIT - 解码器输出（2周期延迟）
周期 7: COMP_WAIT - 比较器结果（1周期延迟）
周期 8: DONE    - 输出 done 脉冲
`

**注入决策**（CONFIG 状态）：

`erilog
inject_en_latch <= (inj_lfsr < threshold_val);
// inj_lfsr: 32bit Galois LFSR，自由运行
// P(inject) = threshold_val / (2^32-1) ≈ 0.1367（对应BER=0.01,L=3,2NRM）
`

**双通道并行处理**：

`
Symbol_A = prbs_out[31:16]  →  encoder_A  →  injector_A(offset=lfsr[5:0])   →  decoder_A  →  comparator_A
Symbol_B = prbs_out[15:0]   →  encoder_B  →  injector_B(offset=lfsr[11:6])  →  decoder_B  →  comparator_B
result_pass = comp_result_A && comp_result_B
`

**看门狗保护**（修复 P4）：

`
WATCHDOG_CYCLES = 10000（100μs @ 100MHz）
任何等待状态超时 → result_pass=0，强制跳转 DONE
`

### 3.3 统计累加（main_scan_fsm.v RUN_TEST 状态）

每次 eng_done=1 时：

`erilog
if (eng_result_pass) acc_success += 1;
else                 acc_fail    += 1;
acc_flip += eng_flip_a + eng_flip_b;
acc_clk  += eng_latency;
trial_cnt++;
`

100 次试验完成后，写入 BRAM：

`erilog
mem_din_a = {
    {1'b0, ber_cnt},  // [175:168] BER_Index
    acc_success,      // [167:136] Success_Count (32bit)
    acc_fail,         // [135:104] Fail_Count (32bit)
    acc_flip,         // [103:72]  Actual_Flip_Count (32bit)
    acc_clk,          // [71:8]    Clk_Count (64bit)
    8'h00            // [7:0]     Reserved
};
`

---

## 四、上行链路：数据回传（FPGA → PC）

### 4.1 数据包组装（tx_packet_assembler.v）

**FSM 状态序列**：

`
IDLE → SYNC(2B) → CMD(1B) → LEN_HI(1B) → LEN_LO(1B)
     → GINFO(3B) → RD_WAIT(1cy) → SEND_BYTES(22B×91)
     → CHECKSUM(1B) → DONE
`

**完整 2011 字节帧结构**：

| 字节范围 | 内容 | 值 |
|---------|------|-----|
| 0-1 | Header | 0xBB, 0x66 |
| 2 | CmdID | 0x81 |
| 3-4 | Length (Big-Endian) | 0x07, 0xD5 (=2005) |
| 5 | Global: Total_Points | 0x5B (=91) |
| 6 | Global: Algo_ID | CURRENT_ALGO_ID |
| 7 | Global: Mode_ID | reg_error_mode[1:0] |
| 8~2009 | 91 × 22字节数据 | 见下表 |
| 2010 | XOR Checksum | XOR(0..2009) |

**每个 22 字节数据点（Big-Endian）**：

| 字节 | 字段 | 来源 |
|------|------|------|
| 0 | BER_Index | mem[ber_cnt][175:168] |
| 1-4 | Success_Count | mem[ber_cnt][167:136] |
| 5-8 | Fail_Count | mem[ber_cnt][135:104] |
| 9-12 | Actual_Flip_Count | mem[ber_cnt][103:72] |
| 13-20 | Clk_Count | mem[ber_cnt][71:8] |
| 21 | Reserved | 0x00 |

**BRAM 读取时序**（RD_WAIT 状态）：

`
GINFO 末尾: mem_rd_addr ← 0
RD_WAIT:   等待 1 周期（BRAM 同步读延迟）
SEND_BYTES: mem_rd_data 已稳定，锁存到 entry_latch
            发送 22 字节后，mem_rd_addr ← 1，再次 RD_WAIT
`

**背压处理**：每个字节发送前检查 tx_ready（= ~tx_busy），tx_ready=0 时 FSM 原地等待。

### 4.2 UART 发送（uart_tx_module）

- 波特率：921600 bps
- 2011 字节总传输时间：2011 × 10 / 921600 ≈ 21.8 ms
- tx_busy 信号反馈给 tx_packet_assembler（通过 tx_ready = ~tx_busy）

### 4.3 PC 端接收解析（py_controller_main.py: receive_response）

**接收流程**：

`python
raw_data = serial_conn.read(2011)  # 阻塞读取，超时30秒

# 1. 验证 Header
assert raw_data[0:2] == bytes([0xBB, 0x66])

# 2. 验证 CmdID
assert raw_data[2] == 0x81

# 3. 读取 Length 字段
len_field = struct.unpack('>H', raw_data[3:5])[0]  # 应为 0x07D5 = 2005

# 4. 验证 XOR Checksum
calc_checksum = XOR(raw_data[0:-1])
assert raw_data[-1] == calc_checksum

# 5. 解析 Global Info（偏移 5）
total_points = raw_data[5]   # 91
algo_used    = raw_data[6]   # CURRENT_ALGO_ID
mode_used    = raw_data[7]   # error_mode

# 6. 解析 91 × 22 字节数据（偏移 8 开始）
for i in range(91):
    entry = raw_data[8 + i*22 : 8 + (i+1)*22]
    ber_idx     = entry[0]
    success_cnt = struct.unpack('>I', entry[1:5])[0]
    fail_cnt    = struct.unpack('>I', entry[5:9])[0]
    flip_cnt    = struct.unpack('>I', entry[9:13])[0]
    clk_cnt     = struct.unpack('>Q', entry[13:21])[0]
    # entry[21] = Reserved，忽略
    
    ber_rate = fail_cnt / (success_cnt + fail_cnt)
    avg_clk  = clk_cnt / (success_cnt + fail_cnt)
`

---

## 五、关键信号端到端追踪表

### 5.1 sample_count = 100 的完整追踪

| 层次 | 变量/信号 | 值 | 说明 |
|------|---------|-----|------|
| Python | sample_count | 100 | 用户输入 |
| Python | payload[3:7] | [0x00,0x00,0x00,0x64] | struct.pack('>I', 100) |
| UART 字节流 | Byte 7~10 | 0x00,0x00,0x00,0x64 | Big-Endian 传输 |
| protocol_parser | sample_count_buffer | 32'h00000064 | 逐字节拼接 |
| protocol_parser | cfg_sample_count | 32'd100 | checksum 通过后锁存 |
| ctrl_register_bank | 
eg_sample_count | 32'd100 | cfg_update_pulse 触发 |
| top_fault_tolerance_test | .sample_count(reg_sample_count) | 32'd100 | 端口连接 |
| main_scan_fsm | sample_count | 32'd100 | 输入端口 |
| main_scan_fsm | 	rial_cnt | 0→99 | 每次 eng_done 递增 |
| main_scan_fsm | 状态转移条件 | 	rial_cnt+1 >= 100 | 满足后跳转 SAVE_RES |

### 5.2 algo_id = 0 (2NRM) 的完整追踪

| 层次 | 变量/信号 | 值 | 说明 |
|------|---------|-----|------|
| Python | lgo_id | 0 | 用户选择 2NRM |
| Python | payload[1] | 0x00 | Byte 1 of payload |
| protocol_parser | cfg_algo_id | 8'h00 | 解析结果 |
| ctrl_register_bank | 
eg_algo_id | 8'h00 | 锁存 |
| top_fault_tolerance_test | 未直接连接 | - | algo_id 由编译时宏决定 |
| main_scan_fsm | ` CURRENT_ALGO_ID ` | 0 | 编译时常量 |
| auto_scan_engine | lgo_id | 2'd0 | 传入引擎 |
| encoder_wrapper | lgo_sel | 2'd0 | 选择 2NRM 编码 |
| error_injector_unit | lgo_id | 2'd0 | ROM 地址高位 |
| decoder_wrapper | lgo_id | 2'd0 | 选择 2NRM 解码 |

> **注意**：
eg_algo_id 在当前实现中未直接连接到 FSM（algo_id 由编译时宏 ` CURRENT_ALGO_ID ` 固定）。这是设计决策：每次综合只支持一种算法，通过重新综合切换算法。

### 5.3 BER 结果的完整追踪（以第 0 个 BER 点为例）

| 层次 | 变量/信号 | 值（示例） | 说明 |
|------|---------|-----------|------|
| auto_scan_engine | eng_result_pass | 0/1 | 单次试验结果 |
| main_scan_fsm | cc_success | 85 | 100次中85次通过 |
| main_scan_fsm | cc_fail | 15 | 100次中15次失败 |
| main_scan_fsm | cc_flip | 42 | 累计翻转比特数 |
| main_scan_fsm | cc_clk | 800 | 累计时钟周期 |
| mem_stats_array | mem[0] | 176bit 打包 | BRAM 存储 |
| tx_packet_assembler | entry_latch | 176bit | 读出并锁存 |
| UART 字节流 | Bytes 8~29 | 22字节 Big-Endian | 发送 |
| Python | success_cnt | 85 | struct.unpack('>I') |
| Python | ail_cnt | 15 | struct.unpack('>I') |
| Python | er_rate | 0.15 | 15/100 |
| Python | vg_clk | 8.0 | 800/100 |

---

## 六、控制信号握手分析

### 6.1 启动链握手

`
PC: serial.write(12字节)
  ↓ ~130μs（UART传输）
FPGA: protocol_parser → cfg_update_pulse（1周期脉冲）
  ↓ T+0
FPGA: ctrl_register_bank → test_active=1（NBA，T+1生效）
  ↓ T+1
FPGA: sys_start_pulse=1（上升沿检测，仅1周期）
  ↓ T+2
FPGA: main_scan_fsm → INIT_CFG（开始扫描）
`

**无竞争风险**：上升沿检测确保 FSM 只在 test_active 0→1 时启动，不受持续高电平影响。

### 6.2 注入链握手

`
INIT_CFG: rom_req=1 → thresh_valid=1（1周期BRAM延迟）
  ↓
RUN_TEST: eng_start=1（单周期脉冲）
  ↓
auto_scan_engine: CONFIG→GEN_WAIT→ENC_WAIT→INJ_WAIT→DEC_WAIT→COMP_WAIT→DONE
  ↓ eng_done=1（约8周期后）
RUN_TEST: 累加统计，trial_cnt++
  ↓（重复 sample_count 次）
SAVE_RES: mem_we_a=1，写入 BRAM
`

**inj_done 握手**：error_injector_unit 为纯组合/单拍输出，FSM 在 INJ_WAIT 等待1周期后直接进入 DEC_WAIT，无需显式 done 信号。

### 6.3 上传链握手

`
PREP_UPLOAD: asm_start=1（单周期脉冲）
  ↓
tx_packet_assembler: 读取 BRAM，序列化 2011 字节
  每字节：tx_valid=1 → 等待 tx_ready=1（~tx_busy）→ 发送
  ↓ asm_done=1（约 21.8ms 后）
DO_UPLOAD → FINISH: done=1，test_active←0
`

**背压机制**：tx_ready = ~tx_busy，UART 忙时 tx_packet_assembler 原地等待，不丢字节。

### 6.4 异常处理

| 异常场景 | 保护机制 | 恢复方式 |
|---------|---------|---------|
| 解码器死锁（dec_valid 不来） | 看门狗 10000 周期超时 | 强制 FAIL，继续下一个 BER 点 |
| 配置帧 Checksum 错误 | protocol_parser 丢弃帧，checksum_error=1 | PC 重发配置帧 |
| 测试卡死 | btn_abort（B9 按钮，16ms 防抖） | FSM 立即返回 IDLE |
| 第二次测试种子残留 | seed_lock_unit：lock_en=0 时清零 seed_valid | 自动清零，下次配置重新锁存 |

---

## 七、时序关键路径分析

### 7.1 下行链路时序

| 阶段 | 延迟 | 说明 |
|------|------|------|
| PC 发送 12 字节 | ~130 μs | 921600bps |
| UART RX 接收 | ~130 μs | 与发送同步 |
| protocol_parser 解析 | 12 个 rx_valid 脉冲 | 每字节 1 周期处理 |
| ctrl_register_bank 锁存 | 1 周期 | cfg_update_pulse 触发 |
| seed_lock_unit 锁存 | 2 周期 | cfg_update_pulse_d1 对齐 |
| FSM 启动 | 2 周期 | 上升沿检测 |

### 7.2 单次试验时序

| 阶段 | 延迟（周期） | 说明 |
|------|------------|------|
| CONFIG | 1 | 注入决策 |
| GEN_WAIT | 1 | PRBS 生成 |
| ENC_WAIT | 1 | 编码器（含 comp_start） |
| INJ_WAIT | 1 | 注入器 |
| DEC_WAIT | 2 | 解码器（2NRM 2级流水） |
| COMP_WAIT | 1 | 比较器 |
| DONE | 1 | 输出 done |
| **合计** | **8** | **80ns @ 100MHz** |

### 7.3 完整测试时序（sample_count=100，91个BER点）

| 阶段 | 时间 | 说明 |
|------|------|------|
| 每个 BER 点 | 100 × 80ns + 开销 ≈ 8.1 μs | 100次试验 |
| 91 个 BER 点 | 91 × 8.1 μs ≈ 737 μs | 全部扫描 |
| UART 上传 | ~21.8 ms | 2011字节 @ 921600bps |
| **总计** | **~22.5 ms** | 从启动到 PC 收到数据 |

---

## 八、字节序一致性验证

### 8.1 下行帧（PC→FPGA）

| 字段 | PC 打包 | FPGA 解析 | 一致性 |
|------|---------|---------|--------|
| burst_len | payload[0] | cfg_burst_len（Byte 0） | ✅ |
| algo_id | payload[1] | cfg_algo_id（Byte 1） | ✅ |
| error_mode | payload[2] | cfg_error_mode（Byte 2） | ✅ |
| sample_count | struct.pack('>I') Big-Endian | [31:24][23:16][15:8][7:0] 逐字节 | ✅ |

### 8.2 上行帧（FPGA→PC）

| 字段 | FPGA 发送 | PC 解析 | 一致性 |
|------|---------|---------|--------|
| BER_Index | entry[175:168]→Byte 0 | entry_bytes[0] | ✅ |
| Success_Count | entry[167:136]→Bytes 1..4 Big-Endian | struct.unpack('>I',[1:5]) | ✅ |
| Fail_Count | entry[135:104]→Bytes 5..8 Big-Endian | struct.unpack('>I',[5:9]) | ✅ |
| Actual_Flip_Count | entry[103:72]→Bytes 9..12 Big-Endian | struct.unpack('>I',[9:13]) | ✅ |
| Clk_Count | entry[71:8]→Bytes 13..20 Big-Endian | struct.unpack('>Q',[13:21]) | ✅ |
| Reserved | entry[7:0]→Byte 21 = 0x00 | 忽略 | ✅ |

---

## 九、已知限制与注意事项

1. **algo_id 编译时固定**：
eg_algo_id 未连接到 FSM，算法由 ` CURRENT_ALGO_ID ` 宏在综合时决定。切换算法需重新综合。

2. **ROM 路径依赖**：$readmemh 使用相对路径 ../../../../src/ROM/，仅适用于 Vivado xsim 仿真。综合时需使用绝对路径或 Block Memory Generator IP。

3. **sample_count 溢出**：acc_flip 为 32bit，最大值 = burst_len_max(15) × sample_count_max(2^32-1) > 32bit，极端情况下会溢出。规格定义为 Uint32，当前实现按规格截断。

4. **单算法构建**：每次 Vivado 构建只支持一种算法（2NRM/3NRM/C-RRNS/RS），需要 4 次综合才能测试所有算法。

5. **UART 无流控**：PC 端 serial.read(2011) 依赖超时（30秒），若 FPGA 发送不完整，PC 端会超时报错。建议在 PC 端增加帧头检测逻辑。

---

## 十、总结

系统端到端信号流经过 7 轮代码审查修复后，所有关键路径均已验证：

| 链路 | 状态 | 关键修复 |
|------|------|---------|
| PC→FPGA 配置帧 | ✅ 正确 | 字节序一致，checksum 算法一致 |
| 启动触发机制 | ✅ 健壮 | 上升沿检测（修复 P1） |
| 种子锁存时序 | ✅ 正确 | 1拍延迟对齐（修复 P2） |
| 注入链流水线 | ✅ 正确 | comp_start 延迟（修复严重-5） |
| 解码器死锁保护 | ✅ 完善 | 看门狗 100μs（修复 P4） |
| 统计聚合 | ✅ 正确 | N次循环累加（修复 W2） |
| 数据回传帧格式 | ✅ 正确 | 176bit/22字节/点（修复 C1-C4） |
| PC 端解析 | ✅ 正确 | 22字节解析，Big-Endian 对齐 |
| 硬件中止 | ✅ 完善 | btn_abort 防抖（修复 P5） |
