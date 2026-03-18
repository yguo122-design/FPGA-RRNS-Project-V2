# UART 通信诊断报告 — 2026-03-18

**项目：** FPGA Multi-Algorithm Fault-Tolerant Test System (2NRM-RRNS)  
**日期：** 2026-03-18  
**问题描述：** 通过 `py_controller_main.py` 发送测试指令到 FPGA 开发板，没有收到任何响应  
**分析范围：** Python 串口脚本 + FPGA UART RX/TX 模块 + 协议解析器 + 顶层连接

---

## 一、串口物理层参数对比（✅ 完全匹配）

| 参数 | Python端 (`py_controller_main.py`) | FPGA端 (`uart_rx_module.v` / `uart_tx_module.v`) | 结论 |
|------|-----------------------------------|--------------------------------------------------|------|
| **波特率** | `921600` bps | `BAUD_DIV=109` → `100MHz/109 = 917,431 bps`，误差 0.45%，在 UART ±3% 容限内 | ✅ 匹配 |
| **数据位** | `serial.EIGHTBITS` (8位) | 8N1 帧格式，8 数据位 | ✅ 匹配 |
| **停止位** | `serial.STOPBITS_ONE` (1位) | 1 个停止位 | ✅ 匹配 |
| **校验位** | `serial.PARITY_NONE` (无校验) | 无奇偶校验 | ✅ 匹配 |
| **帧格式** | 8N1 | 8N1 | ✅ 匹配 |

**物理层串口参数完全匹配，不是问题根源。**

---

## 二、下行帧协议对比（PC → FPGA）（✅ 完全匹配）

### Python 端构造的帧结构（`send_command()`）：

```
字节偏移:  0     1     2     3     4          5         6           7~10              11
内容:    [0xAA][0x55][0x01][0x07][burst_len][algo_id][error_mode][sample_count 4B BE][checksum]
         HDR1  HDR2  CMD   LEN   Payload[0] Payload[1] Payload[2]  Payload[3:6]       XOR校验
```

### FPGA 端 `protocol_parser.v` 期望的帧结构：

```
ST_IDLE       → 等待 0xAA (FRAME_HEADER_BYTE1)
ST_WAIT_HDR_2 → 等待 0x55 (FRAME_HEADER_BYTE2)
ST_READ_CMD   → 等待 0x01 (CMD_ID_CONFIG)
ST_READ_LEN   → 等待 0x07 (PAYLOAD_LEN_CONFIG = 8'd7)
ST_READ_PAYLOAD[0] → cfg_burst_len
ST_READ_PAYLOAD[1] → cfg_algo_id
ST_READ_PAYLOAD[2] → cfg_error_mode
ST_READ_PAYLOAD[3] → sample_count[31:24]
ST_READ_PAYLOAD[4] → sample_count[23:16]
ST_READ_PAYLOAD[5] → sample_count[15:8]
ST_READ_PAYLOAD[6] → sample_count[7:0]
ST_CHECK_SUM  → XOR 校验字节
```

| 字段 | Python端 | FPGA端 | 结论 |
|------|---------|--------|------|
| Header | `0xAA 0x55` | `FRAME_HEADER_BYTE1=0xAA`, `FRAME_HEADER_BYTE2=0x55` | ✅ |
| CmdID | `CMD_REQ_ID=0x01` | `CMD_ID_CONFIG=0x01` | ✅ |
| Length | `len(payload)=7` | `PAYLOAD_LEN_CONFIG=8'd7` | ✅ |
| Payload[0] | `burst_len` | `cfg_burst_len` | ✅ |
| Payload[1] | `algo_id` | `cfg_algo_id` | ✅ |
| Payload[2] | `error_mode` | `cfg_error_mode` | ✅ |
| Payload[3:6] | `sample_count` Big-Endian | `sample_count_buffer[31:0]` Big-Endian | ✅ |
| 总帧长 | `FRAME_LEN_REQ=12` | 1+1+1+1+7+1=12 字节 | ✅ |
| 校验和 | XOR(11字节: HDR+CMD+LEN+Payload) | XOR(11字节: 0xAA~payload[6]) | ✅ |

**下行帧协议完全匹配，不是问题根源。**

---

## 三、上行帧协议对比（FPGA → PC）（✅ 完全匹配）

| 字段 | Python端 | FPGA端 (`tx_packet_assembler.v`) | 结论 |
|------|---------|----------------------------------|------|
| Header | `0xBB 0x66` | `PKT_SYNC_HI=0xBB`, `PKT_SYNC_LO=0x66` | ✅ |
| CmdID | `CMD_RESP_ID=0x81` | `PKT_CMD_STATS=0x81` | ✅ |
| Length | `0x07D5` (2005) | `PKT_LENGTH_HI=0x07`, `PKT_LENGTH_LO=0xD5` | ✅ |
| 总帧长 | `FRAME_LEN_RESP=2011` | `PKT_TOTAL_FRAME_BYTES=2011` | ✅ |
| 数据点数 | `PAYLOAD_DATA_POINTS=91` | `PKT_TOTAL_POINTS=91` | ✅ |
| 每点字节数 | `POINT_DATA_SIZE=22` | `PKT_BYTES_PER_POINT=22` | ✅ |
| 校验和 | XOR(raw_data[0:2010]) | XOR(Byte[0..2009]) | ✅ |

**上行帧协议完全匹配，不是问题根源。**

---

## 四、发现的真实 Bug

### 🔴 Bug #22（Critical）：`py_controller_main.py` 发送命令前未清空串口接收缓冲区

**位置：** `src/PCpython/py_controller_main.py`，`send_command()` 函数

**根本原因：**

`serial.Serial` 对象在打开串口时，操作系统的串口驱动可能已经在接收缓冲区中积累了数据（例如：FPGA 上电时发送的乱码、上次测试残留的数据、或者 USB-UART 桥芯片的初始化字节）。

`send_command()` 在发送下行帧之前，**没有调用 `serial_conn.reset_input_buffer()`** 清空接收缓冲区。

`receive_response()` 使用 `serial_conn.read(FRAME_LEN_RESP)` 一次性读取 2011 字节。如果缓冲区中有残留数据，读取到的前几个字节不是 `0xBB 0x66`，导致帧头验证失败：

```python
# receive_response() 中的帧头验证：
if raw_data[0:2] != HEADER_RESP:   # HEADER_RESP = bytes([0xBB, 0x66])
    print(f"[ERROR] Header mismatch: ...")
    return None
```

**后果：** 即使 FPGA 正确发送了响应帧，Python 端也会因为帧头偏移而报告"Header mismatch"，返回 `None`，表现为"没有收到任何响应"。

**修复方案：** 在 `send_command()` 发送数据之前，调用 `reset_input_buffer()` 清空接收缓冲区：

```python
def send_command(self, algo_id: int, error_mode: int, burst_len: int, sample_count: int) -> bool:
    # ... 构造帧 ...
    
    # 5. Send Data
    print(f"\n[Transmit] Sending test configuration...")
    print(f"   Frame Content (Hex): {full_frame.hex()}")
    try:
        self.serial_conn.reset_input_buffer()  # ← 新增：发送前清空接收缓冲区
        self.serial_conn.write(full_frame)
        self.serial_conn.flush()
        return True
    except Exception as e:
        print(f"[ERROR] Transmission failed: {e}")
        return False
```

---

### 🔴 Bug #23（Critical）：`py_controller_main.py` 的 `receive_response()` 使用固定长度读取，**没有帧头同步机制**，一旦帧头偏移则永久失败

**位置：** `src/PCpython/py_controller_main.py`，`receive_response()` 函数

**根本原因：**

当前实现直接读取固定长度 2011 字节，然后验证第 0~1 字节是否为 `0xBB 0x66`：

```python
raw_data = self.serial_conn.read(FRAME_LEN_RESP)  # 读取 2011 字节

if raw_data[0:2] != HEADER_RESP:
    print(f"[ERROR] Header mismatch: ...")
    return None
```

**问题场景：**

1. **场景 A（最常见）：** 串口缓冲区中有 N 字节残留数据（N > 0）。`read(2011)` 读取到的前 N 字节是残留数据，后续字节才是真正的响应帧。帧头验证失败，直接返回 `None`。

2. **场景 B：** FPGA 响应帧在传输过程中丢失了前几个字节（例如 USB-UART 桥的缓冲区溢出）。帧头验证失败，直接返回 `None`。

3. **场景 C：** 第一次测试成功，但 FPGA 在发送完 2011 字节后，由于某种原因多发了几个字节（例如 UART TX 模块的停止位后有额外脉冲）。这些多余字节留在缓冲区，导致第二次测试的帧头偏移。

**修复方案：** 在 `receive_response()` 中增加**帧头同步搜索**逻辑：先逐字节搜索 `0xBB 0x66` 帧头，找到后再读取剩余 2009 字节：

```python
def receive_response(self) -> Optional[Dict]:
    print(f"[Receive] Waiting for FPGA response (Timeout: {TIMEOUT_SEC}s)...")
    start_time = time.time()
    
    try:
        # Step 1: 搜索帧头 0xBB 0x66（带超时）
        sync_buf = bytearray()
        header_found = False
        
        while time.time() - start_time < TIMEOUT_SEC:
            byte = self.serial_conn.read(1)
            if not byte:
                continue
            sync_buf.append(byte[0])
            
            # 检查最后两字节是否为帧头
            if len(sync_buf) >= 2 and sync_buf[-2] == 0xBB and sync_buf[-1] == 0x66:
                header_found = True
                break
            
            # 防止缓冲区无限增长（超过帧长则说明帧头丢失）
            if len(sync_buf) > FRAME_LEN_RESP:
                print(f"[ERROR] Frame header 0xBB66 not found in {len(sync_buf)} bytes")
                return None
        
        if not header_found:
            print(f"[ERROR] Timeout waiting for frame header 0xBB66")
            return None
        
        # Step 2: 读取剩余 2009 字节（CmdID + Length + GlobalInfo + Data + Checksum）
        remaining = self.serial_conn.read(FRAME_LEN_RESP - 2)
        if len(remaining) < FRAME_LEN_RESP - 2:
            print(f"[ERROR] Incomplete frame: expected {FRAME_LEN_RESP-2} more bytes, got {len(remaining)}")
            return None
        
        # 重组完整帧
        raw_data = bytes([0xBB, 0x66]) + remaining
        
        elapsed = time.time() - start_time
        print(f"[OK] Reception complete, elapsed time: {elapsed:.2f} seconds")
        
        # --- 后续解析逻辑不变 ---
        # 2. Verify CmdID
        if raw_data[2] != CMD_RESP_ID:
            print(f"[ERROR] Command ID mismatch: Expected {CMD_RESP_ID:#04x}, received {raw_data[2]:#04x}")
            return None
        
        # 3. Read Length Field (2 Bytes, Big-Endian)
        len_field = struct.unpack('>H', raw_data[3:5])[0]

        # 4. Verify Checksum (Last 1 Byte)
        received_checksum = raw_data[-1]
        calc_checksum = self._calculate_checksum(raw_data[:-1])
        if received_checksum != calc_checksum:
            print(f"[ERROR] Checksum error: Expected {calc_checksum:#04x}, received {received_checksum:#04x}")
            return None
        
        # 5. Parse Global Info (3 Bytes)
        offset = 5
        global_info = {
            'total_points': raw_data[offset],
            'algo_used':    raw_data[offset+1],
            'mode_used':    raw_data[offset+2]
        }
        offset += 3

        # 6. Parse 91 Data Points (22 Bytes each)
        results = []
        for i in range(PAYLOAD_DATA_POINTS):
            entry_bytes = raw_data[offset : offset + POINT_DATA_SIZE]
            if len(entry_bytes) < POINT_DATA_SIZE:
                print(f"[WARNING] Truncated data at point {i+1}, stopping parse.")
                break

            ber_idx     = entry_bytes[0]
            success_cnt = struct.unpack('>I', entry_bytes[1:5])[0]
            fail_cnt    = struct.unpack('>I', entry_bytes[5:9])[0]
            flip_cnt    = struct.unpack('>I', entry_bytes[9:13])[0]
            clk_cnt     = struct.unpack('>Q', entry_bytes[13:21])[0]

            total_trials = success_cnt + fail_cnt
            ber_rate     = fail_cnt / total_trials if total_trials > 0 else 0.0
            avg_clk      = clk_cnt / total_trials if total_trials > 0 else 0.0

            results.append({
                'Point_ID':      i + 1,
                'BER_Index':     ber_idx,
                'Success_Count': success_cnt,
                'Fail_Count':    fail_cnt,
                'Flip_Count':    flip_cnt,
                'Clk_Count':     clk_cnt,
                'Total_Trials':  total_trials,
                'BER_Rate':      ber_rate,
                'Avg_Clk':       avg_clk,
            })
            offset += POINT_DATA_SIZE

        return {
            'global':    global_info,
            'points':    results,
            'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }

    except Exception as e:
        print(f"[ERROR] Exception during parsing: {e}")
        return None
```

---

### ⚠️ 风险点 #1（Medium）：`uart_interface.vh` 中的注释与实际实现不符

**位置：** `src/interfaces/uart_interface.vh`

**问题：** 注释中仍然写着 `// Note: 16x oversampling logic included.`，但实际上 `uart_rx_module.v` 在 Bug #7 修复（2026-03-16）中已经被完整重写为 **1x 中心采样**方案，16x 过采样逻辑已被完全移除。

**影响：** 不影响功能，但会误导后续开发者。

**修复方案：** 更新 `uart_interface.vh` 中的注释：

```verilog
// Note: 1x center-sampling implementation (v1.1).
//       BAUD_DIV=109 @ 100MHz, HALF_BIT=54 for start-bit alignment.
//       (16x oversampling was removed in v1.1 due to incorrect sample_pulse generation)
```

---

### ⚠️ 风险点 #2（Low）：`py_controller_main.py` 串口号硬编码，缺少自动检测

**位置：** `src/PCpython/py_controller_main.py`，第10行

```python
DEFAULT_PORT = 'COM8'       # Default serial port (Linux: /dev/ttyUSB0)
```

**问题：** 串口号硬编码为 `COM8`。如果实际 USB-UART 桥被分配到其他 COM 口（例如 COM3、COM5），程序会报错：

```
[ERROR] Failed to open serial port COM8: [Errno 2] could not open port COM8: [Error 2]
```

**修复方案：** 增加命令行参数支持，允许用户指定串口号：

```python
import argparse

def main():
    parser = argparse.ArgumentParser(description='FPGA Fault-Tolerant Test System Controller')
    parser.add_argument('--port', type=str, default=DEFAULT_PORT,
                        help=f'Serial port name (default: {DEFAULT_PORT})')
    parser.add_argument('--baudrate', type=int, default=DEFAULT_BAUDRATE,
                        help=f'Baud rate (default: {DEFAULT_BAUDRATE})')
    args = parser.parse_args()
    
    # ... 使用 args.port 和 args.baudrate ...
```

---

## 五、修复优先级总结

| Bug # | 严重程度 | 位置 | 问题描述 | 修复方案 |
|-------|---------|------|---------|---------|
| **#22** | **Critical** | `py_controller_main.py` `send_command()` | 发送命令前未清空串口接收缓冲区，导致响应帧头偏移 | 在 `write()` 前调用 `reset_input_buffer()` |
| **#23** | **Critical** | `py_controller_main.py` `receive_response()` | 固定长度读取无帧头同步，帧头偏移时永久失败 | 改为逐字节搜索 `0xBB66` 帧头后再读取剩余数据 |
| 风险1 | Medium | `uart_interface.vh` | 注释过时（仍写"16x oversampling"） | 更新注释 |
| 风险2 | Low | `py_controller_main.py` | 串口号硬编码 `COM8` | 增加命令行参数 `--port` |

---

## 六、验证步骤

修复后，按以下步骤验证：

1. **确认串口号：** 在设备管理器中查看 Arty A7 的 USB-UART 桥（FTDI FT2232H）对应的 COM 口号，确认与 `DEFAULT_PORT` 一致。

2. **确认 FPGA 已烧录最新 Bitstream：** 确保 Vivado 已生成并下载了包含所有 Bug #1~#21 修复的最新 Bitstream。

3. **运行测试：**
   ```
   python src/PCpython/py_controller_main.py
   ```
   或使用命令行参数指定串口：
   ```
   python src/PCpython/py_controller_main.py --port COM3
   ```

4. **观察 FPGA LED 状态：**
   - 发送命令后：`LED[0]`（cfg_ok）应亮起
   - 测试运行中：`LED[1]`（running）应亮起
   - 数据上传中：`LED[2]`（sending）应亮起
   - 测试完成后：`LED[0]` 重新亮起，其他熄灭

5. **使用 ILA 调试（如果仍无响应）：** 在 Vivado Hardware Manager 中观察 ILA 探针：
   - `rx_valid`：发送命令时应有脉冲（每字节一个脉冲，共12个）
   - `rx_byte`：应依次显示 `AA 55 01 07 ...`
   - `parser_state_dbg`：应从 0 依次变化到 5 再回到 0
   - `cfg_update_pulse`：应有一个单周期脉冲
   - `test_active`：应在 `cfg_update_pulse` 后一拍变为 HIGH
