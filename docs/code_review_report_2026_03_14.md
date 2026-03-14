# FPGA-RRNS-Project-V2 静态代码审查报告

**审查日期**: 2026-03-14  
**审查范围**: `top_fault_tolerance_test.v` 及其所有直接/间接子模块  
**审查员**: Cline AI (FPGA Verification Engineer)  
**最终状态**: ✅ 所有严重问题已修复，代码可进入综合/仿真阶段

---

## 一、问题汇总表（最终版）

| 编号 | 级别 | 文件 | 问题描述 | 修复状态 |
|------|------|------|----------|----------|
| 严重-1 | 🔴 严重 | `src/top/top_fault_tolerance_test.v` | `reset_sync` 实例化端口名错误：`.clk`→`.clk_100m`，`.rst_n_o`→`.sys_rst_n` | ✅ 已修复 |
| 严重-3 | 🔴 严重 | `src/interfaces/protocol_parser.v/.vh` | `typedef enum logic` 是 SystemVerilog 语法，在 Verilog-2001 编译模式下报错；宏引用缺少反引号 | ✅ 已修复 |
| 严重-4 | 🔴 严重 | `src/verify/mem_stats_array.v` + `src/ctrl/main_scan_fsm.v` | `mem_stats_array` 写指针无法在两次测试间复位，第二次测试数据写到错误地址 | ✅ 已修复 |
| 严重-5 | 🔴 严重 | `src/ctrl/auto_scan_engine.v` | `comp_start` 与 `sym_a/b_latch` 在同一时钟沿赋值，比较器 FIFO 写入旧数据 | ✅ 已修复 |
| ~~严重-6~~ | ~~🔴 严重~~ | ~~`src/algo_wrapper/decoder_2nrm.v`~~ | ~~实例化 `decoder_2nrm_mld` 端口名不匹配~~ | ✅ **撤销**（经复核，`decoder_2nrm.v` 是完整独立实现，不调用 `decoder_2nrm_mld`） |
| 警告-1 | 🟡 警告 | `src/interfaces/top_fault_tolerance_test.vh` | `UART_BAUD_RATE` 宏值为 115200，实际设计使用 921600 bps | ✅ 已修复 |
| 警告-3 | 🟡 警告 | `src/interfaces/protocol_parser.v` | Payload 字节顺序（`burst_len` 在前，`algo_id` 在后）需与 PC 端 Python 脚本严格对齐 | ⏳ 待确认（RTL 暂不改动） |
| 警告-4 | 🟡 警告 | `src/ctrl/ctrl_register_bank.v` | `test_done_flag` 优先级低于 `cfg_update_pulse`，FSM FINISH→IDLE 时存在 1 周期意外重启风险 | ✅ 已修复 |
| 警告-7 | 🟡 警告 | `src/ctrl/encoder_wrapper.v` | `done` 信号通过 OR 组合多算法输出，未来添加其他算法时需注意时序一致性 | ⏳ 暂保留（当前仅 2NRM 有效，功能正确） |
| ~~警告-8~~ | ~~🟡 警告~~ | ~~`src/ctrl/encoder_wrapper.v`~~ | ~~Channel B 未真正编码~~ | ✅ **撤销**（经复核，`encoder_2nrm.v` v2.0 已是双通道版本，Channel B 正确编码） |

---

## 二、已完成修复详情

### 修复1：`reset_sync` 端口名错误 [严重-1]

**文件**: `src/top/top_fault_tolerance_test.v`

```verilog
// 修复前（错误）：
reset_sync u_rst_sync (
    .clk    (clk_sys),
    .rst_n_i(rst_n),
    .rst_n_o(rst_n_sync)
);

// 修复后（正确）：
reset_sync u_rst_sync (
    .clk_100m (clk_sys),
    .rst_n_i  (rst_n),
    .sys_rst_n(rst_n_sync)
);
```

---

### 修复2：UART 波特率宏值 [警告-1]

**文件**: `src/interfaces/top_fault_tolerance_test.vh`

```verilog
// 修复前：
`define UART_BAUD_RATE    115200

// 修复后：
`define UART_BAUD_RATE    921600     // 921,600 bps (BAUD_DIV=109 @ 100MHz)
```

---

### 修复3：`protocol_parser` SystemVerilog 兼容性 [严重-3]

**文件**: `src/interfaces/protocol_parser.vh` + `src/interfaces/protocol_parser.v`

**`.vh` 修改**：移除 `typedef enum logic [2:0]`，改为 `` `define `` 宏：
```verilog
// 修复后（Verilog-2001 兼容）：
`define ST_IDLE         3'd0
`define ST_WAIT_HDR_2   3'd1
`define ST_READ_CMD     3'd2
`define ST_READ_LEN     3'd3
`define ST_READ_PAYLOAD 3'd4
`define ST_CHECK_SUM    3'd5
`define ST_ERROR        3'd6
`define DEFINE_PARSER_TYPES   // 保留为空宏，向后兼容
```

**`.v` 修改**：
1. `parser_state_t current_state, next_state` → `reg [2:0] current_state, next_state`
2. 所有状态常量加反引号：`ST_IDLE` → `` `ST_IDLE ``
3. 所有协议常量加反引号：`FRAME_HEADER_BYTE1` → `` `FRAME_HEADER_BYTE1 ``

---

### 修复4：`ctrl_register_bank` 优先级 [警告-4]

**文件**: `src/ctrl/ctrl_register_bank.v`

```verilog
// 修复前（cfg_update_pulse 优先，存在重启风险）：
if (cfg_update_pulse && !tx_busy) begin
    ...
    test_active <= 1'b1;
end else if (test_done_flag) begin
    test_active <= 1'b0;
end

// 修复后（test_done_flag 最高优先级）：
if (test_done_flag) begin
    test_active   <= 1'b0;
    config_locked <= 1'b0;
end else if (cfg_update_pulse && !tx_busy) begin
    ...
    test_active <= 1'b1;
end
```

---

### 修复5：`mem_stats_array` 写指针复位 [严重-4]

**文件**: `src/verify/mem_stats_array.v`

新增端口：
```verilog
input wire wr_ptr_rst,
// 同步写指针复位（高电平有效，单周期脉冲）
// 在新测试开始前清零 wr_ptr 和 entry_count，不清除 mem_array 内容
```

新增逻辑（优先级高于 `wr_en`）：
```verilog
if (wr_ptr_rst) begin
    wr_ptr      <= {`STATS_MEM_ADDR_WIDTH{1'b0}};
    entry_count <= 11'd0;
    halted_reg  <= 1'b0;
end else if (actual_wr_en) begin
    ...
end
```

**文件**: `src/ctrl/main_scan_fsm.v`

1. 新增信号声明：`reg mem_wr_ptr_rst;`
2. 实例化连接：`.wr_ptr_rst(mem_wr_ptr_rst)`
3. 复位初始化：`mem_wr_ptr_rst <= 1'b0;`
4. default 默认值：`mem_wr_ptr_rst <= 1'b0;`
5. IDLE 状态 `sys_start` 分支：`mem_wr_ptr_rst <= 1'b1;`（单周期脉冲）

---

### 修复6：`auto_scan_engine` `comp_start` 时序 [严重-5]

**文件**: `src/ctrl/auto_scan_engine.v`

**问题根因**：`comp_start` 在 `GEN_WAIT` 状态与 `sym_a/b_latch` 同周期赋值，非阻塞赋值导致比较器读到旧数据。

**修复方案**：引入 `comp_start_sent` 标志，将 `comp_start` 延迟到 `ENC_WAIT` 状态的第一个周期（此时 `sym_a/b_latch` 已稳定）：

```verilog
// GEN_WAIT 状态（修复后）：
`ENG_STATE_GEN_WAIT: begin
    if (prbs_valid) begin
        sym_a_latch     <= prbs_out[31:16];
        sym_b_latch     <= prbs_out[15:0];
        comp_start_sent <= 1'b0;   // 解除 comp_start 锁定
        enc_start       <= 1'b1;
        state           <= `ENG_STATE_ENC_WAIT;
        // 注意：不在这里发 comp_start，sym_a/b_latch 此时尚未稳定
    end
end

// ENC_WAIT 状态（修复后）：
`ENG_STATE_ENC_WAIT: begin
    // 第一个周期：sym_a/b_latch 已稳定（上周期非阻塞赋值已生效）
    if (!comp_start_sent) begin
        comp_start      <= 1'b1;
        comp_start_sent <= 1'b1;
    end
    if (enc_done) begin
        enc_out_a_latch <= codeword_a_raw[63:0];
        enc_out_b_latch <= codeword_b_raw[63:0];
        state           <= `ENG_STATE_INJ_WAIT;
    end
end
```

---

## 三、撤销问题说明

### 撤销：[严重-6] `decoder_2nrm.v` 端口名不匹配

**经复核**：`src/algo_wrapper/decoder_2nrm.v` 是一个**完整的独立实现**，内部包含自己的 `decoder_channel_2nrm_param` 子模块，实现了完整的 15 通道并行 CRT + MLD 解码逻辑。它**不调用** `src/algo_base/decoder_2nrm_mld.v`。

`src/algo_base/decoder_2nrm_mld.v` 是一个**孤立的参考实现**（接口为 41-bit 打包输入），不在当前编译路径中，不影响功能。

**结论**：无端口不匹配问题，严重-6 撤销。

### 撤销：[警告-8] `encoder_wrapper` Channel B 未真正编码

**经复核**：`src/ctrl/encoder_2nrm.v`（v2.0）已经是**双通道版本**，端口为 `data_in_A`/`data_in_B`/`residues_out_A`/`residues_out_B`，内部同时计算两个通道的 6 个残差。`encoder_wrapper.v` 的实例化端口名与模块定义完全匹配。

**结论**：Channel B 已正确编码，警告-8 撤销。

---

## 四、待处理事项

### ✅ 已确认：Payload 字节顺序 [警告-3 → 已关闭]

经过逐字节对比核查（2026-03-14），FPGA 侧与 PC 侧**完全一致**，警告-3 正式关闭。

**FPGA 侧**（`protocol_parser.v` ST_READ_PAYLOAD 状态）：
```verilog
3'd0: cfg_burst_len  <= rx_byte;   // Payload Byte 0
3'd1: cfg_algo_id    <= rx_byte;   // Payload Byte 1
3'd2: cfg_error_mode <= rx_byte;   // Payload Byte 2
3'd3~6: cfg_sample_count Big-Endian
```

**PC 侧**（`py_controller_main.py` `send_command`）：
```python
payload[0] = burst_len   # Byte 0
payload[1] = algo_id     # Byte 1
payload[2] = error_mode  # Byte 2
payload[3:7] = struct.pack('>I', sample_count)  # Bytes 3..6 Big-Endian
```

| 字段 | FPGA 解析 | PC 发送 | 一致性 |
|------|----------|---------|--------|
| Byte 0 | `cfg_burst_len` | `burst_len` | ✅ |
| Byte 1 | `cfg_algo_id` | `algo_id` | ✅ |
| Byte 2 | `cfg_error_mode` | `error_mode` | ✅ |
| Bytes 3..6 | `cfg_sample_count` Big-Endian | `struct.pack('>I', ...)` | ✅ |

帧头（`0xAA55`）、CmdID（`0x01`）、Payload 长度（`7`）、XOR 校验范围均完全一致。

---

### ⚠️ 新发现：`protocol_parser.v` 端口重复声明 [严重]

**位置**：`src/interfaces/protocol_parser.v`，模块声明处

**问题**：
```verilog
// 当前代码（有 Bug）：
module protocol_parser (
    `PROTOCOL_PARSER_PORTS,           // 宏展开已包含 checksum_error
    output wire checksum_error        // ← 重复声明！综合报错
);
```

`PROTOCOL_PARSER_PORTS` 宏的最后一行已经包含 `output wire checksum_error`，模块声明中又额外加了一行，导致**端口重复声明**，Vivado 综合时会报 `[Synth 8-87] Port 'checksum_error' is already declared` 错误。

**正确写法**（二选一）：

方案 A：从宏中移除 `checksum_error`，保留模块声明中的单独声明：
```verilog
// protocol_parser.vh 中 PROTOCOL_PARSER_PORTS 宏末尾改为：
    output wire [2:0]  state_dbg        // 去掉 checksum_error（无逗号结尾）

// protocol_parser.v 中保留：
module protocol_parser (
    `PROTOCOL_PARSER_PORTS,
    output wire checksum_error
);
```

方案 B：从模块声明中移除单独声明，只保留宏中的声明：
```verilog
// protocol_parser.v 改为：
module protocol_parser (
    `PROTOCOL_PARSER_PORTS
);
// 宏中已包含 checksum_error，无需重复
```

**推荐方案 B**（改动最小，宏定义已完整）。

> **修复状态**：✅ 已修复（2026-03-14，方案 B）。删除了模块声明中重复的 `output wire checksum_error` 行，保留宏中的声明。

### 暂保留：`encoder_wrapper` done 信号 OR 组合 [警告-7]

```verilog
assign done = done_2nrm | done_3nrm | done_crrns | done_rs;
```

当前 `done_3nrm`/`done_crrns`/`done_rs` 均为常量 `1'b0`，功能正确。未来添加其他算法时，需确保各算法的 `done` 信号时序一致（均为 `start` 后 1 个时钟周期）。

---

## 五、审查进度（最终）

- [x] 第一步：顶层架构与端口概览（`top_fault_tolerance_test.v`）
- [x] 第二步：`protocol_parser` + `ctrl_register_bank` 深度检查
- [x] 第三步：`main_scan_fsm` + `auto_scan_engine` 深度检查
- [x] 第四步：`encoder_wrapper` / `decoder_wrapper` / `decoder_2nrm` 链路检查
- [x] 所有严重问题已修复（严重-1/3/4/5）
- [x] 严重-6 和 警告-8 经复核撤销
- [ ] 第五步：端到端控制信号流串联分析（可选，建议在仿真后进行）
- [ ] 确认 [警告-3]：Python 脚本 Payload 字节顺序

---

## 六、已修改文件清单（最终）

| 文件路径 | 修改内容 | 对应问题 |
|----------|----------|----------|
| `src/top/top_fault_tolerance_test.v` | 修复 `reset_sync` 端口名 `.clk`→`.clk_100m`，`.rst_n_o`→`.sys_rst_n` | 严重-1 |
| `src/interfaces/top_fault_tolerance_test.vh` | 修正 `UART_BAUD_RATE` 115200→921600 | 警告-1 |
| `src/interfaces/protocol_parser.vh` | 移除 `typedef enum`，改为 `` `define `` 宏；保留 `DEFINE_PARSER_TYPES` 为空宏 | 严重-3 |
| `src/interfaces/protocol_parser.v` | 状态变量改为 `reg [2:0]`；所有状态/协议常量加反引号 | 严重-3 |
| `src/ctrl/ctrl_register_bank.v` | `test_done_flag` 优先级提升至 if-else 最高位，消除 FSM 意外重启风险 | 警告-4 |
| `src/verify/mem_stats_array.v` | 新增 `wr_ptr_rst` 端口及同步清零逻辑（优先级高于 `wr_en`） | 严重-4 |
| `src/ctrl/main_scan_fsm.v` | 新增 `mem_wr_ptr_rst` 信号；连接 `wr_ptr_rst`；在 `IDLE→INIT_CFG` 时产生单周期脉冲 | 严重-4 |
| `src/ctrl/auto_scan_engine.v` | 新增 `comp_start_sent` 标志；`comp_start` 延迟到 `ENC_WAIT` 第一周期发出 | 严重-5 |

---

## 七、下一步建议

1. **立即执行 Vivado 综合**：验证无编译错误（特别是 `protocol_parser.v` 的宏展开）
2. **运行 `tb_top.v` 仿真**：验证端到端功能，重点观察：
   - `comp_start` 时序（应在 `sym_a/b_latch` 稳定后 1 周期）
   - 第二次测试的 `mem_stats_array` 写入地址（应从 0 开始）
   - FSM `FINISH→IDLE` 时 `test_active` 的清零时序
3. **确认 Python 脚本字节顺序**（警告-3）：检查 `py_controller_main.py` 中帧打包的 Payload 字节顺序

---

---

# 第二轮审查补充：端到端控制信号流分析与系统级修复

**审查日期**: 2026-03-14（续）  
**审查范围**: 端到端控制信号流（第五步）+ 系统级 Bug 修复（P1~P5）  
**最终状态**: ✅ 全部 5 个系统级问题已修复，代码可进入上板测试阶段

---

## 八、第五步：端到端控制信号流分析结论

### 8.1 启动链分析（sys_start → FSM → ROM → Engine）

**分析路径**：
```
PC 发送配置帧
  → protocol_parser (cfg_update_pulse)
  → ctrl_register_bank (test_active ← 1)
  → main_scan_fsm.sys_start (电平)
  → IDLE 状态检测 → INIT_CFG → rom_req
  → rom_threshold_ctrl (thresh_valid)
  → auto_scan_engine.start
```

**发现问题 P1**：`sys_start` 为持续高电平，FSM 在 IDLE 状态直接检测电平，存在 FINISH→IDLE 后意外重启风险（见 P1 修复）。

**其余路径**：ROM 查找（1 周期 BRAM 延迟）、Engine 启动均无问题。

---

### 8.2 注入链分析（PRBS → 比较器 → 注入器 → 解码器）

**分析路径**：
```
prbs_generator (prbs_valid)
  → sym_a/b_latch (GEN_WAIT)
  → encoder_wrapper (enc_done, 1 cycle)
  → enc_out_a/b_latch (ENC_WAIT)
  → error_injector_unit (inj_out_a/b, 1 cycle)
  → inj_out_a/b_latch (INJ_WAIT)
  → decoder_wrapper (dec_valid_a/b, 2 cycles)
  → result_comparator (comp_result_a/b, 1 cycle)
```

**`inj_done` 握手**：`error_injector_unit` 为纯组合/单拍寄存器输出，无 `done` 信号，FSM 在 `INJ_WAIT` 等待 1 周期后直接进入 `DEC_WAIT`，握手严谨。

**发现问题 P4**：`DEC_WAIT` 无超时保护，解码器若永不输出 `dec_valid`，FSM 永久卡死（见 P4 修复）。

---

### 8.3 异常流分析（dec_uncorr 持续高电平）

**原始行为**：`dec_uncorr_a/b` 信号存在但未被使用，FSM 无法区分"ECC 纠正失败"与"系统故障"。

**发现问题 P3**：`dec_uncorr` 未利用，诊断价值丢失（见 P3 修复）。

**死锁风险**：若 `dec_uncorr` 持续高电平但 `dec_valid` 正常输出，FSM 不会卡死（`dec_valid` 驱动状态转移）。真正的死锁风险是 `dec_valid` 永不到来，已由 P4 看门狗解决。

---

### 8.4 种子锁存时序分析

**发现问题 P2**：`cfg_update_pulse` 与 `config_locked` 在同一时钟沿由 `ctrl_register_bank` 的非阻塞赋值产生，`seed_lock_unit` 在 T+0 采样到 `lock_en=0`，种子永远无法锁存（见 P2 修复）。

---

### 8.5 硬件中止路径分析

**发现问题 P5**：`main_scan_fsm.sys_abort` 硬连接为 `1'b0`，无任何硬件中止手段，死锁后只能断电（见 P5 修复）。

---

## 九、第二轮新增问题汇总表

| 编号 | 级别 | 文件 | 问题描述 | 修复状态 |
|------|------|------|----------|----------|
| P1 | 🟡 警告 | `src/ctrl/main_scan_fsm.v` | `sys_start` 电平触发：FINISH→IDLE 后若 `test_active` 未及时清零，FSM 意外重启 | ✅ 已修复 |
| P2 | 🔴 严重 | `src/top/top_fault_tolerance_test.v` | `seed_lock_unit` 时序错位：`cfg_update_pulse` 与 `config_locked` 同拍产生，种子永远无法锁存 | ✅ 已修复 |
| P3 | 🟡 警告 | `src/ctrl/auto_scan_engine.v` + 3个文件 | `dec_uncorr_a/b` 信号未利用，无法区分 BER_FAIL 与 UNCORR_FAIL，诊断价值丢失 | ✅ 已修复 |
| P4 | 🔴 严重 | `src/ctrl/auto_scan_engine.v` | `DEC_WAIT` 状态无超时保护，解码器死锁导致整个 BER 扫描永久卡死 | ✅ 已修复 |
| P5 | 🔴 严重 | `src/top/top_fault_tolerance_test.v` | `sys_abort` 硬连接 `1'b0`，无硬件紧急中止手段，死锁后只能断电 | ✅ 已修复 |

---

## 十、第二轮修复详情

### 修复 P1：sys_start 电平触发竞争风险

**文件**: `src/ctrl/main_scan_fsm.v`

**根本原因**：`sys_start = test_active` 是持续高电平信号，FSM 在 IDLE 状态直接检测电平，依赖 `ctrl_register_bank` 在 FINISH→IDLE 的同一时钟沿通过 NBA 清除 `test_active`，存在综合时序依赖风险。

**修复方案**：新增上升沿检测器，FSM 仅在 `sys_start` 0→1 跳变时启动：

```verilog
// Section 1b in main_scan_fsm.v
reg  sys_start_prev;
wire sys_start_pulse = sys_start && !sys_start_prev;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sys_start_prev <= 1'b0;
    else        sys_start_prev <= sys_start;
end

// IDLE 状态改为：
if (sys_start_pulse) begin  // FIX P1: 边沿触发，非电平
    ...
end
```

**触发行为**：

| 场景 | 行为 |
|------|------|
| PC 发送配置帧 → `test_active` 0→1 | `sys_start_pulse=1`，FSM 启动扫描 ✓ |
| 扫描进行中 `sys_start` 持续 HIGH | 无新上升沿，FSM 不重启 ✓ |
| FINISH→IDLE，`test_active` 仍 HIGH | 无新上升沿（边沿已消耗），不重触发 ✓ |
| 新一轮：PC 再次发送配置帧 | `test_active` 再次 0→1 → 新上升沿 → 正常启动 ✓ |

---

### 修复 P2：seed_lock_unit 时序错位

**文件**: `src/top/top_fault_tolerance_test.v`

**根本原因**：`cfg_update_pulse` 与 `config_locked` 在同一时钟沿由 `ctrl_register_bank` 的非阻塞赋值产生。在 T+0 时钟沿，`seed_lock_unit` 采样到 `lock_en=0`（旧值）、`capture_pulse=1`，条件 `lock_en && capture_pulse` 永远不满足，种子永远无法锁存。

**修复方案**：新增 1 拍延迟寄存器 `cfg_update_pulse_d1`：

```verilog
// Section 6b in top_fault_tolerance_test.v
reg cfg_update_pulse_d1;
always @(posedge clk_sys or negedge rst_n_sync) begin
    if (!rst_n_sync) cfg_update_pulse_d1 <= 1'b0;
    else             cfg_update_pulse_d1 <= cfg_update_pulse;
end

// seed_lock_unit 实例化：
seed_lock_unit u_seed_lock (
    .lock_en      (config_locked),
    .capture_pulse(cfg_update_pulse_d1),  // FIX: 延迟 1 拍对齐 config_locked
    ...
);
```

**时序波形**：
```
T+0: cfg_update_pulse=1, config_locked←1 (NBA，尚未生效)
T+1: cfg_update_pulse_d1=1, config_locked=1 → 条件满足，种子被锁存 ✓
```

---

### 修复 P3：dec_uncorr 信号利用（诊断增强）

**涉及文件**：`auto_scan_engine.v` + `main_scan_fsm.v` + `main_scan_fsm.vh` + `py_controller_main.py`

#### 层 1：`auto_scan_engine.v` — 信号捕获

新增 `output reg [1:0] uncorr_cnt` 端口，在 `COMP_WAIT` 状态捕获：

```verilog
// COMP_WAIT 状态（修复后）：
uncorr_cnt <= {dec_uncorr_b, dec_uncorr_a};
// [1]=Ch_B uncorrectable, [0]=Ch_A uncorrectable
```

#### 层 2：`main_scan_fsm.v` — 打包进结果

更新 64-bit `packed_result` 格式（PACKING v1.1）：

```verilog
// [23:10] Reserved (14 bits，原 16 bits 缩减 2 位)
// [09:08] Uncorr_Cnt = res_uncorr_latch  ← 新增
// [07]    Was_Injected
// [06]    Pass/Fail
```

#### 层 3：`main_scan_fsm.vh` — 接口定义

```verilog
`define RES_BP_UNCORR_CNT     9:8    // 2 bits (NEW - FIX P3)
`define RES_BP_UNCORR_B       9      // 1 bit: Channel B uncorrectable
`define RES_BP_UNCORR_A       8      // 1 bit: Channel A uncorrectable
```

#### 层 4：`py_controller_main.py` — PC 端解析

- 解析格式从旧的 22字节/点 改为正确的 **8字节/点**（`RESULT_ENTRY_SIZE=8`）
- 使用 `struct.unpack('>Q', ...)` 解包 64-bit Big-Endian
- 生成 `Fail_Type` 诊断标签：

```python
if pass_fail == 1:
    fail_type = "PASS"
elif uncorr_cnt == 0:
    fail_type = "BER_FAIL"      # 比较器不匹配，解码器声称可纠正
else:
    fail_type = "UNCORR_FAIL"   # ECC 硬失败，解码器明确标记不可纠正
```

**诊断矩阵**：

| Pass | Uncorr | 含义 |
|------|--------|------|
| 1 | 00 | Clean PASS（ECC 纠正成功或无注入）|
| 0 | 00 | BER_FAIL（比较器不匹配，解码器声称可纠正）|
| 0 | ≠00 | UNCORR_FAIL（ECC 硬失败）|
| 1 | ≠00 | IMPOSSIBLE（调试标志，不应出现）|

---

### 修复 P4：DEC_WAIT 无超时导致系统死锁

**文件**: `src/ctrl/auto_scan_engine.v`

**根本原因**：`ENG_STATE_DEC_WAIT` 状态仅等待 `dec_valid_a && dec_valid_b`，无任何超时退出路径。若解码器永不输出 `valid`，FSM 永久卡死。

**修复方案**：新增独立看门狗计数器（Section 8）：

```verilog
localparam WATCHDOG_CYCLES = 14'd10000; // 100μs @ 100MHz

reg [13:0] watchdog_cnt;
reg        dec_timeout_flag;

// 看门狗计数器（独立 always 块）：
// - IDLE/DONE 状态：计数器清零，标志清零
// - 其他状态：计数器递增
// - 达到阈值：dec_timeout_flag 锁存为 1

// DEC_WAIT 状态（修复后）：
`ENG_STATE_DEC_WAIT: begin
    if (dec_valid_a && dec_valid_b) begin
        state <= `ENG_STATE_COMP_WAIT;
    end else if (dec_timeout_flag) begin
        // 看门狗超时：强制 FAIL，继续扫描
        result_pass <= 1'b0;
        state       <= `ENG_STATE_DONE;
    end
end
```

**保护范围**：覆盖所有等待状态（GEN_WAIT、ENC_WAIT、INJ_WAIT、**DEC_WAIT**、COMP_WAIT）。

**超时参数**：10,000 周期 = 100μs @ 100MHz，远大于正常流水线延迟（~9 周期），不会误触发。

---

### 修复 P5：sys_abort 未连接（硬件紧急中止）

**涉及文件**：`src/top/top_fault_tolerance_test.v` + `src/constrains/top.xdc`

**根本原因**：`main_scan_fsm.sys_abort` 原来硬连接为 `1'b0`，无任何硬件中止手段。

**修复方案（三层设计）**：

1. **新增端口**：`top_fault_tolerance_test.v` 增加 `input wire btn_abort`（Active-High）
2. **防抖滤波**：实例化 `button_debounce #(.COUNT_MAX(1_600_000))`，提供 16ms 滤波
3. **信号连接**：`sys_abort_w = btn_abort_debounced` → 连接到 `main_scan_fsm.sys_abort`

```verilog
// Section 2b in top_fault_tolerance_test.v
localparam ABORT_DEBOUNCE_COUNT = 32'd1600000; // 16ms @ 100MHz

wire btn_abort_debounced;
button_debounce #(.COUNT_MAX(ABORT_DEBOUNCE_COUNT)) u_btn_abort_debounce (
    .clk_100m (clk_sys),
    .sys_rst_n(rst_n_sync),
    .btn_in   (btn_abort),
    .btn_out  (btn_abort_debounced)
);

wire sys_abort_w;
assign sys_abort_w = btn_abort_debounced;

// main_scan_fsm 实例化：
.sys_abort(sys_abort_w),  // FIX P5: 连接到防抖后的 btn_abort
```

**XDC 约束**（`src/constrains/top.xdc`）：

```tcl
## btn_abort → Arty A7 Left Button (B9, Active-High)
## 注意：B9 与 btn[2] 共享引脚，两个顶层模块互斥使用
set_property -dict { PACKAGE_PIN B9 IOSTANDARD LVCMOS33 } [get_ports { btn_abort }]
```

**行为**：按下 Left Button → 16ms 后 `sys_abort=1` → `main_scan_fsm` 立即跳转 IDLE → 松开后系统恢复，等待新配置帧重启测试。

---

## 十一、第二轮已修改文件清单

| 文件路径 | 修改内容 | 对应问题 |
|----------|----------|----------|
| `src/ctrl/main_scan_fsm.v` | 新增 `sys_start_prev` + `sys_start_pulse` 上升沿检测；IDLE 状态改为边沿触发；新增 `res_uncorr_latch` 及锁存逻辑；更新 `packed_result` 格式（v1.1）；连接 `eng_uncorr_cnt` | P1, P3 |
| `src/top/top_fault_tolerance_test.v` | 新增 `btn_abort` 端口；新增 `button_debounce` 实例（16ms 防抖）；新增 `cfg_update_pulse_d1` 延迟寄存器；`sys_abort` 从 `1'b0` 改为 `sys_abort_w` | P2, P5 |
| `src/ctrl/auto_scan_engine.v` | 新增 `uncorr_cnt` 输出端口；复位初始化；`COMP_WAIT` 状态捕获 `{dec_uncorr_b, dec_uncorr_a}`；看门狗超时时报告 `2'b00`；新增 14-bit 看门狗计数器 + `dec_timeout_flag`；所有等待状态添加超时保护 | P3, P4 |
| `src/interfaces/main_scan_fsm.vh` | 更新结果打包格式注释（v1.1）；新增 `` `RES_BP_UNCORR_CNT ``、`` `RES_BP_UNCORR_B ``、`` `RES_BP_UNCORR_A `` 宏定义 | P3 |
| `src/constrains/top.xdc` | 新增 `btn_abort` 约束（B9，LVCMOS33）；添加互斥使用说明注释 | P5 |
| `src/PCpython/py_controller_main.py` | 新增 `RESULT_ENTRY_SIZE=8` 常量及字段注释；`receive_response` 改为 8字节/点解析；提取 `uncorr_b/a`、`fail_type` 字段；`print_results_table` 新增诊断列和汇总统计；`save_to_csv` 更新列头 | P3 |

---

## 十二、上板测试检查清单（最终版）

### 综合前检查
- [ ] Vivado 综合无 Error（检查 `uncorr_cnt` 无 undriven 警告）
- [ ] 时序报告：所有路径 WNS ≥ 0（100MHz 目标）
- [ ] `btn_abort` 约束仅在 `top_fault_tolerance_test` 构建中启用（与 `btn[2]` 互斥）

### 上板功能验证
- [ ] **LED 状态**：上电后 LED[0] 亮（IDLE），发送配置后 LED[1] 亮（RUN_TEST），上传时 LED[2] 亮
- [ ] **中止测试**：按 Left Button(B9) → LED 立即回到 LED[0]（IDLE），无需断电
- [ ] **重启测试**：中止后重新发送配置帧 → 新一轮扫描正常启动（边沿触发验证）
- [ ] **UART 接收**：PC 端收到 91 × 8 = 728 字节数据（加帧头/尾）
- [ ] **字节序验证**：第一个点 `BER_Index=0`，最后一个点 `BER_Index=90`
- [ ] **Fail_Type 分布**：低 BER 点多 PASS，高 BER 点出现 BER_FAIL 或 UNCORR_FAIL
- [ ] **UNCORR_FAIL 合理性**：仅在高注入率（BER_Idx > 70）时出现
- [ ] **IMPOSSIBLE 标志**：CSV 中不应出现任何 `IMPOSSIBLE` 行
- [ ] **看门狗验证**：人为注释掉 `dec_valid` 输出，确认 100μs 后 FSM 继续下一个 BER 点

---

---

# 第三轮审查补充：核心激励链深度审查（seed_lock_unit / rom_threshold_ctrl / error_injector_unit）

**审查日期**: 2026-03-14（续）  
**审查范围**: 核心激励链三个模块的深度代码审查  
**最终状态**: ✅ 全部 3 个问题已修复，核心激励链验证通过

---

## 十三、第三轮问题汇总表

| 编号 | 模块 | 严重度 | 问题描述 | 修复状态 |
|------|------|--------|----------|----------|
| S1 | `seed_lock_unit.v` | 🟡 警告 | `seed_valid_reg` 一旦置 1 永不清零，第二次测试开始前种子状态为"stale valid"，存在旧种子被误用风险 | ✅ 已修复 |
| S2 | `error_injector_unit.v` | 🟡 警告 | `burst_len=0` 时地址字段下溢（`0-1=4'b1111=15`），无硬件防护，可能注入 15 个连续比特错误 | ✅ 已修复 |
| R1 | `rom_threshold_ctrl.v` | ℹ️ 信息 | `addr_valid` 中 `` burst_len != `THRESH_LEN_BITS'b0 `` 语义混淆（宏作位宽前缀），可读性差 | ✅ 已修复 |

---

## 十四、第三轮各模块审查结论

### 14.1 seed_lock_unit.v — 全面通过（含 S1 修复）

| 检查项 | 结论 |
|--------|------|
| P2 Fix 验证 | ✅ 延迟由顶层 `cfg_update_pulse_d1` 实现，模块本身无需修改 |
| CDC 安全 | ✅ 单时钟域（`clk`），无跨时钟域问题 |
| 零值保护 | ✅ `SEED_SAFE_DEFAULT=0xDEADBEEF` 完整实现 |
| 复位行为 | ✅ 异步复位清零，行为确定 |
| **S1 stale seed** | ✅ 已修复：`!lock_en` 时清零 `seed_locked` 和 `seed_valid_reg` |

### 14.2 rom_threshold_ctrl.v — 全面通过（含 R1 修复）

| 检查项 | 结论 |
|--------|------|
| ROM 深度 | ✅ 物理深度 8192 > 逻辑深度 5460，完全覆盖 |
| 地址公式 | ✅ 与 `gen_rom.py` 完全匹配：`(algo_id×1365)+(ber_idx×15)+(burst_len-1)` |
| 数据单调性 | ✅ 由 Python 脚本保证，FPGA 侧只做查表 |
| 地址稳定性 | ✅ FSM 在 `INIT_CFG` 状态保持地址稳定 |
| 越界保护 | ✅ `addr_valid` 检查 + 强制输出 0（不注入） |
| **R1 可读性** | ✅ 已修复：`` `THRESH_LEN_BITS'b0 `` → `4'd0` |

### 14.3 error_injector_unit.v — 全面通过（含 S2 修复）

| 检查项 | 结论 |
|--------|------|
| 注入点正确性 | ✅ 编码后→注入→解码前，符合信道噪声模型 |
| 时序对齐 | ✅ `inject_en` 与 `data_in` 均为寄存器输出，对齐无误 |
| 多比特翻转 | ✅ `$countones(error_pattern)` 可 > 1，高 BER 可触发 `dec_uncorr`（P3 兼容）|
| Channel A/B 独立性 | ✅ 使用 LFSR 不同位段（`[5:0]` vs `[11:6]`），相关性极低 |
| **S2 下溢保护** | ✅ 已修复：新增 `burst_len_safe` 钳位逻辑 |

---

## 十五、第三轮修复详情

### 修复 S1：seed_valid_reg 跨测试轮次残留

**文件**: `src/ctrl/seed_lock_unit.v`

**根本原因**：`seed_valid_reg` 在第一次测试中被置 1 后，永远不会被清零（除非全局复位）。第二次测试开始时，`lock_en` 先变高（FSM 进入 INIT_CFG），而 `capture_pulse_d1` 晚 1 拍到来。在这 1 个时钟周期的窗口内，`seed_valid=1` 但 `seed_locked` 仍是上次测试的旧值。

**修复方案**：在 `else begin` 块中，优先处理 `!lock_en` 分支，清零 `seed_locked` 和 `seed_valid_reg`：

```verilog
// 修复前（seed_valid_reg 永不清零）：
if (lock_en && capture_pulse) begin
    ...
    seed_valid_reg <= 1'b1;
end
// else: hold（包括 lock_en=0 时也 hold）

// 修复后（lock_en=0 时主动清零）：
if (!lock_en) begin
    seed_locked    <= `SEED_WIDTH'h0;
    seed_valid_reg <= 1'b0;          // 任务结束时清除有效标志
end else if (capture_pulse) begin    // lock_en=1 隐含
    ...
    seed_valid_reg <= 1'b1;
end
// else: lock_en=1, capture_pulse=0 → 保持稳定（91点扫描中）
```

**时序影响**：无。`lock_en` 在 FSM FINISH 状态后才清零（所有 91 个 BER 点已完成），此时种子已不再需要。

---

### 修复 S2：burst_len=0 地址下溢

**文件**: `src/ctrl/error_injector_unit.v`

**根本原因**：`burst_len=0` 时，`burst_len - 1` 在 4-bit 无符号运算中下溢为 `4'b1111`（=15），地址字段 `[9:6]` 指向 L=15 的 ROM 分区，可能注入 15 个连续比特错误。

**修复方案**：新增 `burst_len_safe` 钳位线，在减法前将 0 钳位为 1：

```verilog
// 修复前（无保护）：
assign rom_addr = {
    algo_id,
    burst_len - `INJ_BURST_LEN_WIDTH'b1,  // burst_len=0 → 4'b1111 (BUG)
    random_offset
};

// 修复后（带钳位保护）：
wire [`INJ_BURST_LEN_WIDTH-1:0] burst_len_safe;
assign burst_len_safe = (burst_len == {`INJ_BURST_LEN_WIDTH{1'b0}}) ?
                         {{(`INJ_BURST_LEN_WIDTH-1){1'b0}}, 1'b1} : // 0 → 1
                         burst_len;                                   // 1~15 → 不变

assign rom_addr = {
    algo_id,
    burst_len_safe - {{(`INJ_BURST_LEN_WIDTH-1){1'b0}}, 1'b1}, // 安全减法
    random_offset
};
```

**逻辑开销**：单个 4-bit MUX，被综合工具吸收进地址路径，不增加关键路径延迟。

---

### 修复 R1：addr_valid 可读性优化

**文件**: `src/ctrl/rom_threshold_ctrl.v`

```verilog
// 修复前（语义混淆）：
assign addr_valid = (ber_idx < `THRESH_BER_POINTS) && (burst_len != `THRESH_LEN_BITS'b0);
// `THRESH_LEN_BITS 是数值常量 4，用作位宽前缀语法正确但语义不清晰

// 修复后（明确语义）：
assign addr_valid = (ber_idx < `THRESH_BER_POINTS) && (burst_len != 4'd0);
// 4'd0 明确表示：4-bit 宽度的零值，与 burst_len 端口宽度完全匹配
```

---

## 十六、第三轮已修改文件清单

| 文件路径 | 修改内容 | 对应问题 |
|----------|----------|----------|
| `src/ctrl/seed_lock_unit.v` | 新增 `!lock_en` 优先分支，清零 `seed_locked` 和 `seed_valid_reg`；`lock_en && capture_pulse` 改为 `else if (capture_pulse)`（`lock_en=1` 由结构隐含）| S1 |
| `src/ctrl/error_injector_unit.v` | 新增 `burst_len_safe` 钳位线（0→1 保护）；`rom_addr` 赋值改用 `burst_len_safe` | S2 |
| `src/ctrl/rom_threshold_ctrl.v` | `` `THRESH_LEN_BITS'b0 `` → `4'd0`，添加 FIX R1 注释 | R1 |

---

---

# 第四轮审查补充：下游模块架构重构（Spec v1.7 合规性修复）

**审查日期**: 2026-03-14（续）  
**审查范围**: `mem_stats_array` / `tx_packet_assembler` / `main_scan_fsm`（统计聚合部分）  
**触发原因**: 代码审查发现当前实现为"单次事件记录器"，与 Spec v1.7 要求的"BER 统计聚合器"存在架构级不匹配  
**最终状态**: ✅ 全部 4 个严重问题 + 2 个警告已修复，三个模块完成架构重构

---

## 十七、第四轮问题汇总表

| 编号 | 级别 | 文件 | 问题描述 | 修复状态 |
|------|------|------|----------|----------|
| C1 | 🔴 严重 | `mem_stats_array.vh/.v` | 数据宽度 **64-bit** vs 规格要求 **176-bit**（22 Bytes/点）—— 架构级不匹配 | ✅ 已修复 |
| C2 | 🔴 严重 | `tx_packet_assembler.vh/.v` | 帧格式完全不符：Sync=`0xA55A` vs `0xBB66`；每点 8 字节 vs 22 字节；无 Global Info；16-bit 加法校验 vs XOR | ✅ 已修复 |
| C3 | 🔴 严重 | `mem_stats_array.v` | 内存深度 1024 vs 规格 91；地址由内部写指针自增 vs 规格要求 `addr = ber_idx` 直接寻址 | ✅ 已修复 |
| C4 | 🔴 严重 | `mem_stats_array.vh` | 缺少 `Clk_Count(64-bit)`、`Success_Count(32-bit)`、`Fail_Count(32-bit)`、`Actual_Flip_Count(32-bit)` | ✅ 已修复 |
| W1 | 🟡 警告 | `tx_packet_assembler.v` | `PKT_MAX_ENTRIES=8`，每次最多发 64 字节，无法一次发送 91 点数据 | ✅ 已修复 |
| W2 | 🟡 警告 | `main_scan_fsm.v` | 每个 BER 点只运行 1 次试验，缺少 `sample_count` 次循环累计逻辑 | ✅ 已修复 |

---

## 十八、根本原因分析

当前实现的 `mem_stats_array` + `tx_packet_assembler` 是一套**通用调试数据记录器**（记录每次单次试验的 64-bit 结果），而规格要求的是**BER 扫描统计聚合器**（每个 BER 点聚合 N 次采样的统计数据）。

```
【旧实现数据流（错误）】
auto_scan_engine → (每次试验) → mem_stats_array[wr_ptr++]
                                  64-bit: {valid, pass/fail, latency, ...}

【规格要求数据流（正确）】
auto_scan_engine → (N次试验累计) → main_scan_fsm 累加计数器
                                  → mem_stats_array[ber_idx]
                                    176-bit: {ber_idx, success_cnt, fail_cnt, flip_cnt, clk_cnt, reserved}
```

---

## 十九、第四轮修复详情

### 修复 C1+C4：mem_stats_array.vh 数据结构重构

**文件**: `src/interfaces/mem_stats_array.vh`

```verilog
// 修复前（64-bit 单次事件格式）：
`define STATS_DATA_WIDTH  64
`define STATS_MEM_DEPTH   1024
`define STATS_MEM_ADDR_WIDTH  10
// 字段：Valid(1) + Result(1) + Latency(8) + AlgoID(2) + ErrType(4) + Reserved(32) + SeqNum(16)

// 修复后（176-bit BER 统计聚合格式，Spec v1.7 Section 2.1.3.2）：
`define STATS_DATA_WIDTH      176   // 22 Bytes/点
`define STATS_MEM_DEPTH       91    // 91 个 BER 测试点
`define STATS_MEM_ADDR_WIDTH  7     // ceil(log2(91)) = 7 bits

// 新字段布局（Big-Endian 字段顺序）：
// [175:168] BER_Index          (8-bit,  Uint8)
// [167:136] Success_Count      (32-bit, Uint32)
// [135:104] Fail_Count         (32-bit, Uint32)
// [103:72]  Actual_Flip_Count  (32-bit, Uint32)
// [71:8]    Clk_Count          (64-bit, Uint64)  ← 防止 42 秒溢出
// [7:0]     Reserved           (8-bit,  0x00)
```

**BRAM 资源**：91 × 176 bits = 16,016 bits < 18 Kbits（RAMB18E1），适配 1 个 BRAM tile。

---

### 修复 C3：mem_stats_array.v 接口重构

**文件**: `src/verify/mem_stats_array.v`

**移除**：内部 `wr_ptr` 自增逻辑、`entry_count`、`halted_reg`、Circular/Stop-on-Fail/Once 三种模式、`wr_ptr_rst` 端口、`mode` 端口、`full`/`empty`/`count`/`halted` 状态输出。

**新增**：外部 `wr_addr_a[6:0]` 输入端口（由 FSM `ber_cnt` 直接驱动）。

```verilog
// 修复后接口（简洁双端口 RAM）：
module mem_stats_array (
    input  wire        clk,
    input  wire        rst_n,
    // Write Port A（由 Main Scan FSM 控制）
    input  wire        we_a,
    input  wire [6:0]  wr_addr_a,   // = ber_idx (0~90)，外部直接寻址
    input  wire [175:0] din_a,      // 176-bit 统计数据
    // Read Port B（由 TX Packet Assembler 控制）
    input  wire [6:0]  rd_addr_b,
    output reg  [175:0] dout_b      // 同步读，1 周期 BRAM 延迟
);
```

**写端口**：纯同步写，无内部指针，FSM 完全控制地址。  
**读端口**：同步读（1 周期延迟），`tx_packet_assembler` 的 `RD_WAIT` 状态吸收该延迟。  
**复位**：mem 内容不清零（FSM 保证每次测试前覆盖所有 91 个地址）。

---

### 修复 W2：main_scan_fsm.v 多次采样循环 + 统计累加

**文件**: `src/ctrl/main_scan_fsm.v`

**新增端口**：
```verilog
input wire [31:0] sample_count,  // 每个 BER 点的试验次数（来自 ctrl_register_bank）
```

**新增寄存器**：
```verilog
reg [31:0] acc_success;  // 当前 BER 点累计通过次数
reg [31:0] acc_fail;     // 当前 BER 点累计失败次数
reg [31:0] acc_flip;     // 当前 BER 点累计翻转比特数
reg [63:0] acc_clk;      // 当前 BER 点累计时钟周期数（64-bit 防溢出）
reg [31:0] trial_cnt;    // 当前 BER 点已完成试验次数
```

**RUN_TEST 状态修改**（每次 `eng_done` 时累加，达到 `sample_count` 才跳转）：
```verilog
`MAIN_STATE_RUN_TEST: begin
    if (eng_done) begin
        // 累加统计
        if (eng_result_pass) acc_success <= acc_success + 32'd1;
        else                 acc_fail    <= acc_fail + 32'd1;
        acc_flip <= acc_flip + {26'd0, eng_flip_a} + {26'd0, eng_flip_b};
        acc_clk  <= acc_clk  + {56'd0, eng_latency};

        if (trial_cnt + 32'd1 >= sample_count) begin
            trial_cnt <= 32'd0;
            state     <= `MAIN_STATE_SAVE_RES;  // N 次完成 → 保存
        end else begin
            trial_cnt <= trial_cnt + 32'd1;
            eng_start <= 1'b1;  // 立即启动下一次试验
        end
    end
end
```

**SAVE_RES 状态修改**（写 176-bit 统计数据到 BRAM）：
```verilog
`MAIN_STATE_SAVE_RES: begin
    mem_we_a      <= 1'b1;
    mem_wr_addr_a <= ber_cnt;    // 直接寻址，无内部指针
    mem_din_a     <= packed_stats; // 176-bit 聚合数据
    state         <= `MAIN_STATE_NEXT_ITER;
end
```

**176-bit 打包**（`packed_stats` 组合逻辑）：
```verilog
wire [175:0] packed_stats = {
    {1'b0, ber_cnt},  // [175:168] BER_Index (8-bit)
    acc_success,      // [167:136] Success_Count (32-bit)
    acc_fail,         // [135:104] Fail_Count (32-bit)
    acc_flip,         // [103:72]  Actual_Flip_Count (32-bit)
    acc_clk,          // [71:8]    Clk_Count (64-bit)
    8'h00             // [7:0]     Reserved
};
```

**NEXT_ITER 状态修改**（切换 BER 点时清零累加器）：
```verilog
ber_cnt     <= ber_cnt + 1'b1;
trial_cnt   <= 32'd0;
acc_success <= 32'd0;
acc_fail    <= 32'd0;
acc_flip    <= 32'd0;
acc_clk     <= 64'd0;
```

---

### 修复 C2+W1：tx_packet_assembler 完整重构

**文件**: `src/interfaces/tx_packet_assembler.vh` + `src/verify/tx_packet_assembler.v`

#### .vh 常量更新

| 常量 | 旧值 | 新值 | 说明 |
|------|------|------|------|
| `PKT_SYNC_HI/LO` | `0xA5/0x5A` | `0xBB/0x66` | Spec v1.7 规定 |
| `PKT_CMD_STATS` | `0x01` | `0x81` | 响应帧 CmdID |
| `PKT_LENGTH_HI/LO` | 无（1字节） | `0x07/0xD5` (=2005) | 2字节 Big-Endian |
| `PKT_BYTES_PER_POINT` | 8 | **22** | 176-bit/点 |
| `PKT_TOTAL_POINTS` | 8 | **91** | 全量 BER 点 |
| `PKT_GLOBAL_INFO_BYTES` | 无 | 3 | 新增 Global Info |
| `PKT_TOTAL_FRAME_BYTES` | 70 | **2011** | 完整帧长 |

#### .v FSM 重构（10 态状态机）

```
IDLE → SYNC(2B) → CMD(1B) → LEN_HI(1B) → LEN_LO(1B)
     → GINFO(3B) → RD_WAIT(1cy) → SEND_BYTES(22B×91)
     → CHECKSUM(1B) → DONE → IDLE
```

**关键设计点**：

1. **Global Info 发送**（`GINFO` 状态，3字节）：
   - Byte 0: `Total_Points = 91`（0x5B）
   - Byte 1: `Algo_ID`（来自 `algo_id_in` 端口）
   - Byte 2: `Mode_ID`（来自 `mode_id_in` 端口）

2. **BRAM 读取时序**（`RD_WAIT` 状态）：
   - 在前一状态末尾设置 `mem_rd_addr`
   - `RD_WAIT` 状态等待 1 周期（BRAM 同步读延迟）
   - 进入 `SEND_BYTES` 时 `mem_rd_data` 已稳定，锁存到 `entry_latch`

3. **22字节 Big-Endian 序列化**（`SEND_BYTES` 状态）：
   - 使用 `case(byte_cnt)` 完整枚举 22 个字节位置
   - 避免 Verilog 可变部分选择（variable part-select）综合问题
   - `byte_cnt=0` → `entry_latch[175:168]`（BER_Index）
   - `byte_cnt=21` → `entry_latch[7:0]`（Reserved=0x00）

4. **XOR 校验**（`xor_chk` 寄存器）：
   - 每个成功发送的字节（`tx_valid && tx_ready`）立即 XOR 累加
   - 覆盖范围：Sync → 最后一个 Reserved 字节（共 2010 字节）
   - Checksum 字节本身不参与 XOR（符合 Spec 2.1.3.1）

5. **背压处理**：所有字节发送状态均检查 `tx_valid && tx_ready`，`tx_ready=0` 时 FSM 原地等待，`tx_valid` 和 `tx_data` 保持稳定。

---

## 二十、第四轮已修改文件清单

| 文件路径 | 修改内容 | 对应问题 |
|----------|----------|----------|
| `src/interfaces/mem_stats_array.vh` | `STATS_DATA_WIDTH` 64→176；`STATS_MEM_DEPTH` 1024→91；`STATS_MEM_ADDR_WIDTH` 10→7；新增 176-bit 字段位置宏；移除旧字段宏和模式常量 | C1, C4 |
| `src/verify/mem_stats_array.v` | 完全重写：移除内部写指针/模式逻辑；新增外部 `wr_addr_a[6:0]` 端口；简化为标准双端口 BRAM（同步写+同步读）；`(* ram_style = "block" *)` 保留 | C1, C3, C4 |
| `src/ctrl/main_scan_fsm.v` | 新增 `sample_count[31:0]` 输入端口；新增 `acc_success/fail/flip/clk` 累加器（32/32/32/64-bit）；新增 `trial_cnt[31:0]`；`RUN_TEST` 状态改为 N 次循环累加；`SAVE_RES` 改为写 176-bit `packed_stats`；`NEXT_ITER` 清零累加器；更新 `mem_stats_array` 实例化（新接口）；更新 `tx_packet_assembler` 实例化（新接口） | W2, C3 |
| `src/interfaces/tx_packet_assembler.vh` | 完全重写：Sync `0xBB66`；CmdID `0x81`；Length 2字节 `0x07D5`；新增 `PKT_GLOBAL_INFO_BYTES=3`、`PKT_BYTES_PER_POINT=22`、`PKT_TOTAL_POINTS=91`；FSM 状态扩展为 10 态；移除旧的 `PKT_MAX_ENTRIES`、`PKT_FOOTER_SIZE` 等 | C2, W1 |
| `src/verify/tx_packet_assembler.v` | 完全重写：10 态 FSM；新增 `algo_id_in`/`mode_id_in` 端口；移除旧的 `cmd`/`start_addr`/`num_entries` 端口；`mem_rd_addr` 改为 7-bit；`mem_rd_data` 改为 176-bit；22字节 `case(byte_cnt)` 序列化；8-bit XOR 校验；Global Info 3字节发送；2011字节完整帧 | C2, W1 |

---

## 二十一、遗留待处理事项（第四轮后）

> **✅ 全部已在第五轮修复，见第二十二节。**

---

---

# 第五轮修复：遗留问题闭环处理

**修复日期**: 2026-03-14（续）  
**修复范围**: 第四轮遗留的 4 个待处理事项  
**最终状态**: ✅ 全部 4 个遗留问题已修复，系统端到端链路完全闭合

---

## 二十二、第五轮修复详情

### 修复 Issue 1：`mode_id` 信号路由（`main_scan_fsm` → `tx_packet_assembler`）

**涉及文件**：`src/ctrl/main_scan_fsm.v` + `src/top/top_fault_tolerance_test.v`

**问题**：`tx_packet_assembler` 的 `mode_id_in` 端口原来硬编码为 `2'd0`，Global Info 字段中的 Mode_ID 始终为 0，无法反映实际测试模式（Random/Burst）。

**修复方案**：

1. **`main_scan_fsm.v`** — 新增 `mode_id[1:0]` 输入端口：
```verilog
input wire [1:0] mode_id,
// mode_id: Error mode ID (0=Random, 1=Burst) from ctrl_register_bank.reg_error_mode.
// Embedded in Global Info field of the uplink response frame.
```

2. **`main_scan_fsm.v`** — `tx_packet_assembler` 实例化改为：
```verilog
.mode_id_in (mode_id),  // FIX Issue1: from ctrl_register_bank.reg_error_mode
```

3. **`top_fault_tolerance_test.v`** — `main_scan_fsm` 实例化新增连接：
```verilog
.mode_id (reg_error_mode[1:0]),  // FIX Issue1: error mode → Global Info
```

**效果**：PC 端收到的 Global Info Byte 2 现在正确反映 `cfg_error_mode`（0=Random, 1=Burst），与用户配置一致。

---

### 修复 Issue 2：`sample_count` 端口连接

**涉及文件**：`src/top/top_fault_tolerance_test.v`

**问题**：`main_scan_fsm` 新增的 `sample_count[31:0]` 端口未在顶层连接，导致每个 BER 点只运行 1 次试验（`sample_count` 为 X/0）。

**修复方案**：`top_fault_tolerance_test.v` 中 `main_scan_fsm` 实例化新增：
```verilog
.sample_count (reg_sample_count),  // FIX Issue2: N trials per BER point
```

**效果**：`reg_sample_count`（来自 `ctrl_register_bank`，由 PC 端 `cfg_sample_count` 配置）正确传入 FSM，每个 BER 点运行用户指定的 N 次试验后才保存统计数据。

---

### 修复 Issue 3：`py_controller_main.py` 解析逻辑更新（22字节/点）

**文件**：`src/PCpython/py_controller_main.py`

**问题**：`receive_response()` 中仍使用旧的 `RESULT_ENTRY_SIZE=8`（8字节/点，64-bit 格式），与 FPGA 发送的 22字节/点（176-bit 格式）完全不匹配，导致所有字段解析错误。

**修复方案**：

1. **常量更新**：
   - 移除 `RESULT_ENTRY_SIZE = 8`
   - `POINT_DATA_SIZE = 22`（已存在但未使用，现在正式启用）
   - 新增 `EXPECTED_LENGTH_FIELD = 0x07D5`（2005，用于 Length 字段验证）

2. **解析逻辑重写**（`receive_response` 中的 Step 6）：
```python
# 22-byte entry parsing (Big-Endian)
ber_idx     = entry_bytes[0]                           # Byte 0: BER_Index
success_cnt = struct.unpack('>I', entry_bytes[1:5])[0] # Bytes 1..4: Success_Count
fail_cnt    = struct.unpack('>I', entry_bytes[5:9])[0] # Bytes 5..8: Fail_Count
flip_cnt    = struct.unpack('>I', entry_bytes[9:13])[0]# Bytes 9..12: Actual_Flip_Count
clk_cnt     = struct.unpack('>Q', entry_bytes[13:21])[0]# Bytes 13..20: Clk_Count
# entry_bytes[21] = Reserved (0x00), ignored
```

3. **派生统计计算**：
```python
total_trials = success_cnt + fail_cnt
ber_rate     = fail_cnt / total_trials if total_trials > 0 else 0.0
avg_clk      = clk_cnt / total_trials if total_trials > 0 else 0.0
```

4. **`print_results_table` 更新**：显示 `Success_Count`/`Fail_Count`/`BER_Rate`/`Clk_Count`/`Avg_Clk` 统计列，汇总行显示 `Overall_BER`。

5. **`save_to_csv` 更新**：CSV 列头改为 `Point_ID, BER_Index, Success_Count, Fail_Count, Total_Trials, BER_Rate, Flip_Count, Clk_Count, Avg_Clk_Per_Trial`。

---

### 修复 Issue 4：Length 字段值确认（0x07D5 = 2005）

**涉及文件**：`src/interfaces/tx_packet_assembler.vh` + `src/PCpython/py_controller_main.py`

**问题**：Spec v1.7 原文 Length 字段示例值为 `0x077A = 1914`（基于 21字节/点的旧版本），与当前 22字节/点实现不符。

**确认结论**：
- 当前实现：22字节/点 → Length = GlobalInfo(3) + 91×22(2002) = **2005 = 0x07D5** ✓
- `tx_packet_assembler.vh` 中 `PKT_LENGTH_HI/LO = 0x07/0xD5` 已正确
- `py_controller_main.py` 新增 `EXPECTED_LENGTH_FIELD = 0x07D5` 常量，与 FPGA 发送值对齐

**注意**：`receive_response()` 中 `len_field` 读取后暂未做强制校验（仅注释说明），保持宽松解析策略（以固定帧长 2011 字节为准），避免因 Spec 版本差异导致误拒绝。

---

## 二十三、第五轮已修改文件清单

| 文件路径 | 修改内容 | 对应问题 |
|----------|----------|----------|
| `src/ctrl/main_scan_fsm.v` | 新增 `mode_id[1:0]` 输入端口；`tx_packet_assembler` 实例化 `.mode_id_in` 从 `2'd0` 改为 `mode_id` | Issue 1 |
| `src/top/top_fault_tolerance_test.v` | `main_scan_fsm` 实例化新增 `.sample_count(reg_sample_count)` 和 `.mode_id(reg_error_mode[1:0])` | Issue 1, 2 |
| `src/PCpython/py_controller_main.py` | 移除 `RESULT_ENTRY_SIZE=8`；启用 `POINT_DATA_SIZE=22`；新增 `EXPECTED_LENGTH_FIELD=0x07D5`；`receive_response` Step 6 改为 22字节解析；`print_results_table` 和 `save_to_csv` 更新为统计聚合格式 | Issue 3, 4 |

---

---

---

# 第六轮审查：gen_rom.py 与 FPGA ROM 读取逻辑一致性核查

**审查日期**: 2026-03-14（续）  
**审查范围**: `gen_rom.py` ↔ `rom_threshold_ctrl.v` ↔ `error_injector_unit.v` ↔ `auto_scan_engine.v`  
**最终状态**: ✅ 两个 ROM 的地址公式、数据宽度、深度完全一致；发现 1 个注释错误（不影响功能）

---

## 二十五、ROM 一致性核查总表

### 25.1 threshold_table ROM（`rom_threshold_ctrl.v`）

| 核查维度 | gen_rom.py | rom_threshold_ctrl.v | 结论 |
|----------|-----------|---------------------|------|
| **地址公式** | `(algo_id × 91 × 15) + (ber_idx × 15) + (len - 1)` | `(algo_id × 1365) + (ber_idx × 15) + (burst_len - 1)` | ✅ 完全一致 |
| **逻辑深度** | 4 × 91 × 15 = **5460** | `THRESH_ROM_LOGICAL_DEPTH = 5460` | ✅ 一致 |
| **物理深度** | 5460 条目写入 COE | 2^13 = 8192（覆盖 5460） | ✅ 物理 ≥ 逻辑 |
| **地址宽度** | 最大地址 5459，需 13 bit | `THRESH_ROM_ADDR_WIDTH = 13` | ✅ 一致 |
| **数据宽度** | 32-bit（`width=8` hex chars） | `THRESH_ROM_DATA_WIDTH = 32` | ✅ 一致 |
| **COE 格式** | `radix=16, width=8` | `$readmemh(...)` | ✅ 兼容 |
| **BER 点数** | `BER_POINTS = 91`（0~90） | `THRESH_BER_POINTS = 91` | ✅ 一致 |
| **Burst 步数** | `NUM_BURST_STEPS = 15`（L=1~15） | `THRESH_LEN_STEPS = 15` | ✅ 一致 |
| **Algo 数量** | 4（2NRM/3NRM/C-RRNS/RS） | `THRESH_ALGO_COUNT = 4` | ✅ 一致 |
| **越界保护** | 未写入的地址默认为 0 | `addr_valid` 检查 + 强制输出 0 | ✅ 双重保护 |
| **burst_len=0 保护** | 不生成 len=0 的条目 | `burst_len != 4'd0` 检查 | ✅ 一致 |

**地址公式逐步验证**（以 algo_id=2, ber_idx=45, burst_len=7 为例）：

```
Python:  addr = (2 × 91 × 15) + (45 × 15) + (7 - 1)
              = 2730 + 675 + 6 = 3411

Verilog: addr = (2 × 1365) + (45 × 15) + (7 - 1)
              = 2730 + 675 + 6 = 3411  ✓
```

---

### 25.2 error_lut ROM（`error_injector_unit.v`）

| 核查维度 | gen_rom.py | error_injector_unit.v | 结论 |
|----------|-----------|----------------------|------|
| **地址公式** | `(algo_id << 10) \| (len_idx << 6) \| offset` | `{algo_id[1:0], (burst_len-1)[3:0], random_offset[5:0]}` | ✅ 完全等价（位拼接） |
| **物理深度** | `ERROR_ROM_DEPTH = 4096`（2^12） | `INJ_ROM_DEPTH = 4096` | ✅ 一致 |
| **地址宽度** | 12-bit（2+4+6） | `INJ_ROM_ADDR_WIDTH = 12` | ✅ 一致 |
| **数据宽度** | 64-bit（`width=16` hex chars） | `INJ_ROM_DATA_WIDTH = 64` | ✅ 一致 |
| **COE 格式** | `radix=16, width=16` | `$readmemh(...)` | ✅ 兼容 |
| **algo_id 分区大小** | 每个 algo 占 1024 条目（2^10） | bits[11:10] 选分区 | ✅ 一致 |
| **len_idx 分区大小** | 每个 len 占 64 条目（2^6） | bits[9:6] 选 len | ✅ 一致 |
| **offset 范围** | 0~63（6-bit） | `random_offset[5:0]` | ✅ 一致 |
| **L=16 非法处理** | 显式填 0（`illegal_len_idx=15`） | `burst_len_safe` 钳位（0→1），不会访问 len_idx=15 | ✅ 双重保护 |
| **越界 offset 处理** | `offset > w_valid - L` 时填 0 | 无需硬件检查（ROM 预填 0） | ✅ 设计正确 |

**地址公式逐步验证**（以 algo_id=1, burst_len=3, offset=25 为例）：

```
Python:  len_idx = 3 - 1 = 2
         addr = (1 << 10) | (2 << 6) | 25
              = 1024 | 128 | 25 = 1177

Verilog: rom_addr = {2'b01, 4'b0010, 6'b011001}
                  = 12'b01_0010_011001 = 1177  ✓
```

---

## 二十六、发现问题

### 问题 ROM-W1（⚠️ 警告）：`error_injector_unit.v` 注释中 algo_id 映射顺序错误

**位置**：`src/ctrl/error_injector_unit.v`，文件头注释 ADDRESS MAPPING 部分

**错误内容**：
```
// 当前注释（错误）：
//   - bits[11:10]: algo_id    (0=2NRM, 1=3NRM, 2=RS, 3=C-RRNS)
```

**正确内容**（与 `gen_rom.py` ALGORITHMS 字典一致）：
```python
# gen_rom.py 定义：
ALGORITHMS = {
    '2NRM':   {'id': 0},   # algo_id = 0
    '3NRM':   {'id': 1},   # algo_id = 1
    'C-RRNS': {'id': 2},   # algo_id = 2  ← 注释写成了 RS
    'RS':     {'id': 3},   # algo_id = 3  ← 注释写成了 C-RRNS
}
```

**正确注释应为**：
```
//   - bits[11:10]: algo_id    (0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS)
```

**影响评估**：
- **功能无影响**：`error_injector_unit.v` 本身不解码 `algo_id`，只是将其作为地址高位传入 ROM。只要调用方（`auto_scan_engine.v`）传入的 `algo_id` 与 `gen_rom.py` 的 id 定义一致，ROM 查表结果就是正确的。
- **调用方验证**：`auto_scan_engine.v` 的 `algo_id` 来自 `main_scan_fsm` 的 `` `CURRENT_ALGO_ID ``，该宏在编译时固定，与 `gen_rom.py` 的 id 定义一致（均为 0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS）。
- **结论**：纯注释错误，不影响综合/仿真/上板功能。建议修正注释以避免维护混淆。

> **修复状态**：✅ 已修复（2026-03-14）。修改了两处：
> 1. 文件头 ADDRESS MAPPING 注释：`2=RS, 3=C-RRNS` → `2=C-RRNS, 3=RS`，并添加说明注释
> 2. `algo_id` 端口注释：`0=2NRM, 1=3NRM, 2=RS, 3=C-RRNS` → `0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS`

---

### 问题 ROM-I1（ℹ️ 信息）：threshold 计算公式的物理含义说明

**位置**：`gen_rom.py` → `calculate_threshold` 函数

**公式**：
```python
p_trigger = (target_ber * w_valid) / burst_len
threshold  = round(p_trigger * (2**32 - 1))
```

**物理含义**：
- `target_ber`：目标误码率（每比特错误概率），范围 0.01~0.10
- `w_valid`：有效码字比特数（算法相关：2NRM=41, 3NRM=48, C-RRNS=61, RS=48）
- `burst_len`：突发错误长度 L（1~15）
- `p_trigger`：每次试验触发注入的概率 = 期望在 `w_valid` 比特中产生 `target_ber × w_valid` 个错误，每次注入 L 个比特，所以触发概率 = `(target_ber × w_valid) / L`

**FPGA 侧验证**（`auto_scan_engine.v`）：
```verilog
// CONFIG 状态：
inject_en_latch <= (inj_lfsr < threshold_val);
// inj_lfsr 是 32-bit 均匀分布 LFSR
// P(inject) = threshold_val / (2^32 - 1) ≈ p_trigger  ✓
```

**结论**：公式语义正确，FPGA 侧实现与 Python 侧定义完全对应。✅

---

### 问题 ROM-I2（ℹ️ 信息）：error_lut 的 `random_offset` 来源

**gen_rom.py 侧**：offset 范围 0~63（6-bit），超出 `w_valid - L` 的条目填 0（不注入）。

**FPGA 侧**（`auto_scan_engine.v`）：
```verilog
// Channel A: 使用 inj_lfsr[5:0]（低 6 位）
.random_offset(inj_lfsr[5:0]),

// Channel B: 使用 inj_lfsr[11:6]（次低 6 位）
.random_offset(inj_lfsr[11:6]),
```

**一致性验证**：
- LFSR 输出为均匀分布的 32-bit 随机数，取低 12 位分别给 A/B 两个通道
- 两个通道使用不同的 6-bit 段，相关性极低（LFSR 相邻位相关性由多项式决定，实际测试中可接受）
- offset 超出有效范围时，ROM 返回 0（不注入），行为正确

**结论**：`random_offset` 来源合理，与 gen_rom.py 的 offset 范围定义一致。✅

---

## 二十七、ROM 一致性核查总结

| ROM 文件 | 地址公式 | 数据宽度 | 深度 | COE 格式 | algo_id 映射 | 总体结论 |
|----------|---------|---------|------|---------|------------|---------|
| `threshold_table.coe` | ✅ 完全一致 | ✅ 32-bit | ✅ 5460/8192 | ✅ hex/8chars | ✅ 一致 | **✅ 通过** |
| `error_lut.coe` | ✅ 完全一致 | ✅ 64-bit | ✅ 4096 | ✅ hex/16chars | ✅ 注释已修正 | **✅ 通过** |

**核查结论**：两个 ROM 的生成逻辑（`gen_rom.py`）与 FPGA 读取逻辑（`rom_threshold_ctrl.v` / `error_injector_unit.v`）**完全一致**，可以直接使用 `gen_rom.py` 生成的 COE 文件进行综合。

**所有问题已闭环**：`error_injector_unit.v` 中两处 algo_id 映射注释（文件头 ADDRESS MAPPING + `algo_id` 端口注释）均已从 `2=RS, 3=C-RRNS` 修正为 `2=C-RRNS, 3=RS`，与 `gen_rom.py` ALGORITHMS 字典定义完全一致。

---

---

# 第七轮审查：ROM 文件加载完整性核查

**审查日期**: 2026-03-14（续）  
**审查范围**: COE 文件存在性、`$readmemh` 路径、文件内容正确性  
**最终状态**: ✅ 全部 4 个问题已修复，COE 文件已生成并验证

---

## 二十八、ROM 加载问题汇总

| 编号 | 级别 | 问题描述 | 修复状态 |
|------|------|----------|----------|
| ROM-L1 | 🔴 严重 | `src/ROM/` 目录为空，`threshold_table.coe` 和 `error_lut.coe` **均不存在** | ✅ 已修复（运行 gen_rom.py 生成） |
| ROM-L2 | 🔴 严重 | `gen_rom.py` 将 COE 文件输出到**运行时当前目录**，而非项目 `src/ROM/` 目录 | ✅ 已修复（输出路径改为 `src/ROM/`） |
| ROM-L3 | 🔴 严重 | `$readmemh` 使用**裸文件名**（`"threshold_table.coe"`），无路径前缀，仿真/综合时找不到文件 | ✅ 已修复（改为 `"../../../../src/ROM/..."` 相对路径） |
| ROM-L4 | 🟡 警告 | `gen_rom.py` 的 `write_coe_file` 函数存在**缩进 Bug**：`for` 循环体的 `if/else` 写入语句缩进错误，导致只有最后一个条目被写入文件 | ✅ 已修复（恢复正确缩进） |
| ROM-W2 | 🟡 警告 | `error_injector_unit.vh` 中 `ALGO_ID_RS=2'd2, ALGO_ID_CRRNS=2'd3` 与 gen_rom.py 相反 | ✅ 已修复（`ALGO_ID_CRRNS=2'd2, ALGO_ID_RS=2'd3`） |

---

## 二十九、修复详情

### 修复 ROM-L1+L2：gen_rom.py 输出路径修正

**文件**: `src/PCpython/gen_rom.py`

**修复内容**：
1. 新增 `import os`
2. 新增 `SCRIPT_DIR` 和 `ROM_OUTPUT_DIR` 常量，自动计算 `src/ROM/` 绝对路径：
```python
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROM_OUTPUT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "ROM"))
```
3. `write_coe_file` 函数改为写入 `os.path.join(ROM_OUTPUT_DIR, filename)`
4. 新增 `os.makedirs(ROM_OUTPUT_DIR, exist_ok=True)` 确保目录存在

**运行结果**：
```
✓ Saved: d:\FPGAproject\FPGA-RRNS-Project-V2\src\ROM\threshold_table.coe (Depth: 5460)
✓ Saved: d:\FPGAproject\FPGA-RRNS-Project-V2\src\ROM\error_lut.coe (Depth: 4096)
```

---

### 修复 ROM-L3：$readmemh 路径修正

**文件**: `src/interfaces/rom_threshold_ctrl.vh` + `src/interfaces/error_injector_unit.vh`

```verilog
// 修复前（裸文件名，找不到文件）：
`define THRESH_ROM_COE_FILE     "threshold_table.coe"
`define INJ_ROM_COE_FILE        "error_lut.coe"

// 修复后（相对路径，从 Vivado 仿真运行目录向上 4 级到项目根目录）：
`define THRESH_ROM_COE_FILE     "../../../../src/ROM/threshold_table.coe"
`define INJ_ROM_COE_FILE        "../../../../src/ROM/error_lut.coe"
```

**路径说明**：
- Vivado 仿真默认工作目录：`FPGAProjectV2/FPGAProjectV2.sim/sim_1/behav/xsim/`
- 向上 4 级：`../../../../` → `d:\FPGAproject\FPGA-RRNS-Project-V2\`
- 完整路径：`d:\FPGAproject\FPGA-RRNS-Project-V2\src\ROM\threshold_table.coe` ✓

> **注意**：若 Vivado 项目目录结构不同，需相应调整 `../../../../` 的层级数。综合时 `$readmemh` 在 `initial` 块中，Vivado 会在综合时解析路径（相对于 `.xpr` 文件所在目录），可能需要改为绝对路径或在 Vivado 项目设置中添加数据文件路径。

---

### 修复 ROM-L4：write_coe_file 缩进 Bug

**文件**: `src/PCpython/gen_rom.py`

```python
# 修复前（缩进错误，只有最后一个条目被写入）：
for i, val in enumerate(data):
    hex_val = fmt.format(val)
if i == total_items - 1:      # ← 脱离了 for 循环！
    f.write(f"{hex_val};\n")
else:
    f.write(f"{hex_val},\n")

# 修复后（正确缩进）：
for i, val in enumerate(data):
    hex_val = fmt.format(val)
    if i == total_items - 1:  # ← 在 for 循环内
        f.write(f"{hex_val};\n")
    else:
        f.write(f"{hex_val},\n")
```

---

### 修复 ROM-W2：error_injector_unit.vh ALGO_ID 宏顺序

**文件**: `src/interfaces/error_injector_unit.vh`

```verilog
// 修复前（RS 和 C-RRNS 互换）：
`define ALGO_ID_RS      2'd2
`define ALGO_ID_CRRNS   2'd3

// 修复后（与 gen_rom.py 一致）：
`define ALGO_ID_CRRNS   2'd2   // C-RRNS = 2
`define ALGO_ID_RS      2'd3   // RS     = 3
```

---

## 三十、COE 文件内容验证

运行 Python 抽查脚本，验证结果：

| 验证项 | 期望值 | 实际值 | 结论 |
|--------|--------|--------|------|
| `threshold_table.coe` 总行数 | 5460+2=5462 | 5462 | ✅ |
| `threshold_table.coe` 格式头 | `memory_initialization_radix=16;` | ✓ | ✅ |
| `threshold_table.coe` 数据宽度 | 8 hex chars (32-bit) | `68F5C28F` (8 chars) | ✅ |
| `threshold_table.coe` 最后行 | 以 `;` 结尾 | `51EB851E;` | ✅ |
| `threshold_table[0]` 数值 | `0x68F5C28F` = 1760936591 | 1760936591 | ✅ 精确匹配 |
| `error_lut.coe` 总行数 | 4096+2=4098 | 4098 | ✅ |
| `error_lut.coe` 数据宽度 | 16 hex chars (64-bit) | `0000000000000001` (16 chars) | ✅ |
| `error_lut.coe` 最后行 | 以 `;` 结尾 | `0000000000000000;` | ✅ |
| `error_lut[0]` (algo=0,L=1,offset=0) | bit[0]=1（1位突发从位0开始） | `0000000000000001` | ✅ |

**数值验证**（threshold_table[0]）：
```
algo=2NRM(w_valid=41), ber_idx=0(BER=0.01), burst_len=1
p_trigger = (0.01 × 41) / 1 = 0.41
threshold = round(0.41 × (2^32 - 1)) = round(1760936590.65) = 1760936591
hex = 0x68F5C28F  ✓
```

---

## 三十一、第七轮已修改文件清单

| 文件路径 | 修改内容 | 对应问题 |
|----------|----------|----------|
| `src/PCpython/gen_rom.py` | 新增 `import os`；新增 `ROM_OUTPUT_DIR` 自动路径计算；`write_coe_file` 改为写入 `src/ROM/`；修复 `for` 循环缩进 Bug | ROM-L1, L2, L4 |
| `src/interfaces/rom_threshold_ctrl.vh` | `THRESH_ROM_COE_FILE` 从裸文件名改为 `"../../../../src/ROM/threshold_table.coe"` | ROM-L3 |
| `src/interfaces/error_injector_unit.vh` | `INJ_ROM_COE_FILE` 从裸文件名改为 `"../../../../src/ROM/error_lut.coe"`；`ALGO_ID_CRRNS/RS` 宏值修正 | ROM-L3, ROM-W2 |
| `src/ROM/threshold_table.coe` | **新生成**：5460 条目，32-bit，radix=16 | ROM-L1 |
| `src/ROM/error_lut.coe` | **新生成**：4096 条目，64-bit，radix=16 | ROM-L1 |

---

## 三十二、Vivado 综合注意事项

`$readmemh` 在 `initial` 块中用于 BRAM 初始化时，Vivado 的路径解析规则如下：

| 场景 | 路径基准 | 建议 |
|------|---------|------|
| **行为仿真** (xsim) | 仿真运行目录（`sim_1/behav/xsim/`） | `../../../../src/ROM/` ✓ |
| **综合** (synthesis) | `.xpr` 文件所在目录 | 需要 `../src/ROM/` 或绝对路径 |
| **IP 核初始化** | Vivado IP 设置中指定 | 推荐使用 IP 核方式加载 BRAM |

**推荐做法**：在 Vivado 项目设置中将 `src/ROM/` 添加为"Simulation Sources"的数据文件目录，或在综合时使用绝对路径。若使用 Block Memory Generator IP 核，直接在 IP 配置中指定 COE 文件路径更为可靠。

---

## 二十四、系统端到端数据流（最终确认）

```
PC 发送配置帧 (12 Bytes)
  → protocol_parser → ctrl_register_bank
  → main_scan_fsm (sys_start 上升沿触发)
  → 91 × N 次试验 (auto_scan_engine)
  → 91 × 176-bit 统计数据 (mem_stats_array)
  → tx_packet_assembler (2011 Bytes 帧)
  → uart_tx_module → PC

PC 接收 2011 Bytes
  → 验证 Header(0xBB66) + CmdID(0x81) + Length(0x07D5)
  → 验证 XOR Checksum
  → 解析 GlobalInfo (3B): Total_Points=91, Algo_ID, Mode_ID
  → 解析 91 × 22B: BER_Index, Success_Count, Fail_Count,
                    Actual_Flip_Count, Clk_Count, Reserved
  → 计算 BER_Rate, Avg_Clk
  → 打印表格 + 保存 CSV
```

**所有字段端到端对齐验证**：

| 字段 | FPGA 发送位置 | PC 解析位置 | 对齐 |
|------|--------------|------------|------|
| BER_Index | entry[175:168] → Byte 0 | `entry_bytes[0]` | ✅ |
| Success_Count | entry[167:136] → Bytes 1..4 | `struct.unpack('>I', [1:5])` | ✅ |
| Fail_Count | entry[135:104] → Bytes 5..8 | `struct.unpack('>I', [5:9])` | ✅ |
| Actual_Flip_Count | entry[103:72] → Bytes 9..12 | `struct.unpack('>I', [9:13])` | ✅ |
| Clk_Count | entry[71:8] → Bytes 13..20 | `struct.unpack('>Q', [13:21])` | ✅ |
| Reserved | entry[7:0] → Byte 21 | 忽略 | ✅ |
| Mode_ID | Global Info Byte 2 | `global_info['mode_used']` | ✅ |




| 序号 | 问题描述 | 严重程度 | 处理措施 |
|------|---------|---------|---------|
| 1 | `reset_sync` 实例化端口名错误：`.clk` 应为 `.clk_100m`，`.rst_n_o` 应为 `.sys_rst_n`，导致综合报端口未连接错误 | 🔴 严重 | 修正端口名，已修复 |
| 2 | `UART_BAUD_RATE` 宏值为 115200，与实际设计使用的 921600bps 不符，导致波特率分频系数错误 | 🟡 警告 | 将宏值改为 921600，已修复 |
| 3 | `protocol_parser.vh` 使用 `typedef enum logic` SystemVerilog 语法，在 Verilog-2001 模式下编译报错；宏引用缺少反引号 | 🔴 严重 | 改为 `` `define `` 宏定义状态常量，状态变量改为 `reg [2:0]`，已修复 |
| 4 | `ctrl_register_bank` 中 `test_done_flag` 优先级低于 `cfg_update_pulse`，FSM FINISH→IDLE 时存在 1 周期意外重启风险 | 🟡 警告 | 将 `test_done_flag` 提升为 if-else 最高优先级，已修复 |
| 5 | `mem_stats_array` 写指针无法在两次测试间复位，第二次测试数据写到错误地址 | 🔴 严重 | 新增 `wr_ptr_rst` 端口，FSM 在 IDLE→INIT_CFG 时产生单周期复位脉冲，已修复 |
| 6 | `auto_scan_engine` 中 `comp_start` 与 `sym_a/b_latch` 在同一时钟沿赋值，比较器读到旧数据 | 🔴 严重 | 新增 `comp_start_sent` 标志，将 `comp_start` 延迟到 ENC_WAIT 第一周期发出，已修复 |
| 7 | `sys_start` 为持续高电平，FSM 在 FINISH→IDLE 后若 `test_active` 未及时清零会意外重启 | 🟡 警告 | 新增上升沿检测器 `sys_start_pulse`，FSM 改为边沿触发，已修复 |
| 8 | `seed_lock_unit` 时序错位：`cfg_update_pulse` 与 `config_locked` 同拍产生，种子永远无法锁存 | 🔴 严重 | 新增 `cfg_update_pulse_d1` 延迟寄存器，延迟 1 拍对齐 `config_locked`，已修复 |
| 9 | `dec_uncorr_a/b` 信号未利用，无法区分 BER_FAIL 与 UNCORR_FAIL，诊断价值丢失 | 🟡 警告 | 新增 `uncorr_cnt[1:0]` 输出，打包进统计数据，PC 端增加 Fail_Type 诊断标签，已修复 |
| 10 | `auto_scan_engine` DEC_WAIT 状态无超时保护，解码器死锁导致整个 BER 扫描永久卡死 | 🔴 严重 | 新增 14bit 看门狗计数器（10000周期=100μs），超时强制 FAIL 并继续扫描，已修复 |
| 11 | `sys_abort` 硬连接 `1'b0`，无硬件紧急中止手段，死锁后只能断电 | 🔴 严重 | 新增 `btn_abort` 端口（B9 按钮），经 16ms 防抖后连接到 `sys_abort`，已修复 |
| 12 | `seed_lock_unit` 中 `seed_valid_reg` 一旦置 1 永不清零，第二次测试开始前存在旧种子被误用风险 | 🟡 警告 | 新增 `!lock_en` 优先分支，`lock_en=0` 时主动清零 `seed_locked` 和 `seed_valid_reg`，已修复 |
| 13 | `error_injector_unit` 中 `burst_len=0` 时地址字段下溢（`0-1=4'b1111=15`），可能注入 15 个连续比特错误 | 🟡 警告 | 新增 `burst_len_safe` 钳位线（0→1 保护），已修复 |
| 14 | `rom_threshold_ctrl.v` 中 `addr_valid` 条件使用 `` `THRESH_LEN_BITS'b0 `` 语义混淆，可读性差 | ℹ️ 信息 | 改为 `4'd0`，语义明确，已修复 |
| 15 | `mem_stats_array` 数据宽度 64bit，与规格要求的 176bit（22字节/点）架构级不匹配 | 🔴 严重 | 重构为 176bit 格式，包含 BER_Index/Success_Count/Fail_Count/Flip_Count/Clk_Count，已修复 |
| 16 | `tx_packet_assembler` 帧格式完全不符规格：Sync 错误、每点 8 字节、无 Global Info、校验算法错误 | 🔴 严重 | 完整重构：Sync=0xBB66，22字节/点，3字节 Global Info，XOR 校验，10态 FSM，已修复 |
| 17 | `mem_stats_array` 内存深度 1024 vs 规格 91，地址由内部写指针自增而非 `ber_idx` 直接寻址 | 🔴 严重 | 重构为深度 91 的直接寻址 BRAM，外部 `wr_addr_a` 由 FSM `ber_cnt` 驱动，已修复 |
| 18 | `main_scan_fsm` 每个 BER 点只运行 1 次试验，缺少 `sample_count` 次循环累计逻辑 | 🟡 警告 | 新增累加器（acc_success/fail/flip/clk）和 `trial_cnt`，RUN_TEST 状态改为 N 次循环，已修复 |
| 19 | `tx_packet_assembler` 的 `mode_id_in` 端口硬编码为 `2'd0`，Global Info 中 Mode_ID 始终为 0 | 🟡 警告 | 新增 `mode_id[1:0]` 输入端口，顶层连接 `reg_error_mode[1:0]`，已修复 |
| 20 | `main_scan_fsm` 新增的 `sample_count` 端口未在顶层连接，每个 BER 点只运行 1 次试验 | 🔴 严重 | 顶层新增 `.sample_count(reg_sample_count)` 连接，已修复 |
| 21 | `py_controller_main.py` 使用旧的 8 字节/点解析格式，与 FPGA 发送的 22 字节/点完全不匹配 | 🔴 严重 | 更新为 22 字节解析，使用 struct.unpack 正确提取各统计字段，已修复 |
| 22 | `error_injector_unit.v` 注释中 algo_id 映射顺序错误（RS 和 C-RRNS 互换） | ℹ️ 信息 | 修正注释：`2=C-RRNS, 3=RS`，与 gen_rom.py 定义一致，已修复 |
| 23 | `src/ROM/` 目录为空，`threshold_table.coe` 和 `error_lut.coe` 均不存在，综合/仿真无法加载 ROM | 🔴 严重 | 修复 gen_rom.py 输出路径和缩进 Bug，重新生成两个 COE 文件，已修复 |
| 24 | `gen_rom.py` 将 COE 文件输出到运行时当前目录而非项目 `src/ROM/` 目录 | 🔴 严重 | 新增 `ROM_OUTPUT_DIR` 自动路径计算，输出到 `src/ROM/`，已修复 |
| 25 | `$readmemh` 使用裸文件名，无路径前缀，仿真/综合时找不到 ROM 文件 | 🔴 严重 | 改为 `../../../../src/ROM/` 相对路径（适用于 xsim 仿真工作目录），已修复 |
| 26 | `gen_rom.py` 的 `write_coe_file` 函数 for 循环体缩进错误，导致只有最后一个条目被写入文件 | 🔴 严重 | 恢复正确缩进，已修复并重新生成 COE 文件验证 |
| 27 | `error_injector_unit.vh` 中 `ALGO_ID_RS=2'd2, ALGO_ID_CRRNS=2'd3` 与 gen_rom.py 定义相反 | 🟡 警告 | 修正为 `ALGO_ID_CRRNS=2'd2, ALGO_ID_RS=2'd3`，已修复 |
| 28 | `protocol_parser.v` 模块声明中重复声明 `output wire checksum_error`，宏中已包含该端口，综合报 [Synth 8-87] 错误 | 🔴 严重 | 删除模块声明中的重复声明行，保留宏中的声明（方案 B），已修复 |
