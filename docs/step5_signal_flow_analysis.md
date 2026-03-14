# 第五步：端到端控制信号流串联分析报告

**分析日期**: 2026-03-14  
**分析范围**: `top_fault_tolerance_test.v` → `ctrl_register_bank.v` → `main_scan_fsm.v` → `auto_scan_engine.v` → 各子模块  
**目标**: 验证启动链、注入链、异常流的握手正确性，识别死锁/竞争/丢失风险

---

## 总体架构信号流图

```
PC UART TX
    │ (921600 bps, 帧格式: AA 55 CMD LEN Payload[7] Checksum)
    ▼
[uart_rx_module]
    │ rx_valid (单周期脉冲) + rx_byte
    ▼
[protocol_parser]
    │ cfg_update_pulse (单周期脉冲, 校验通过后)
    │ cfg_algo_id / cfg_burst_len / cfg_error_mode / cfg_sample_count
    ▼
[ctrl_register_bank]  ←── test_done_flag (来自 main_scan_fsm.done)
    │ test_active (电平信号, 高=测试进行中)
    │ config_locked
    │ reg_burst_len[3:0]
    ▼
[seed_lock_unit]  ←── free_counter (32位自由计数器)
    │ seed_locked (32位, 整个扫描期间固定)
    │ seed_valid
    ▼
[main_scan_fsm]
    │ eng_start → [auto_scan_engine]
    │ rom_req   → [rom_threshold_ctrl]
    │ mem_wr_en → [mem_stats_array]
    │ asm_start → [tx_packet_assembler]
    │ tx_valid/tx_data → [uart_tx_module] → PC UART RX
    ▼
[auto_scan_engine] 内部流水线:
    [prbs_generator] → [encoder_wrapper] → [error_injector_unit×2]
                    → [decoder_wrapper×2] → [result_comparator×2]
```

---

## 一、启动链分析：`sys_start` → FSM → ROM → Engine

### 1.1 信号传递路径

```
cfg_update_pulse (protocol_parser)
    │
    ▼ (同一时钟沿)
ctrl_register_bank:
    test_active   ← 1'b1  (电平, 持续高)
    config_locked ← 1'b1
    reg_*         ← cfg_*_in  (原子锁存)
    │
    ▼ (下一时钟沿, main_scan_fsm 采样)
main_scan_fsm.sys_start = test_active
    IDLE 状态检测到 sys_start=1 → 进入 INIT_CFG
```

### 1.2 ✅ 正常路径验证

**关键时序**（以时钟沿编号）：

| 时钟沿 | 事件 |
|--------|------|
| T+0 | `cfg_update_pulse=1`，`ctrl_register_bank` 锁存所有参数，`test_active←1` |
| T+1 | `main_scan_fsm` 采样到 `sys_start=1`（即 `test_active`），从 IDLE 跳转 INIT_CFG，同时 `mem_wr_ptr_rst←1`（单周期脉冲） |
| T+2 | INIT_CFG：`rom_req←1`，ROM 开始查找 |
| T+3 | `thresh_valid=1`（ROM 1周期延迟），`eng_start←1`，跳转 RUN_TEST |
| T+4 | `auto_scan_engine` 采样到 `start=1`，进入 CONFIG 状态 |

**结论**：启动链时序正确，无多周期路径问题。

### 1.3 🔴 [严重] 问题1：`test_active` 是电平信号，FSM 会被持续触发

**问题描述**：

`ctrl_register_bank` 输出的 `test_active` 是一个**持续高电平**信号（从 `cfg_update_pulse` 到 `test_done_flag` 之间一直为 1）。

`main_scan_fsm` 的 IDLE 状态逻辑如下：
```verilog
// main_scan_fsm.v, IDLE state:
if (sys_start) begin
    ber_cnt        <= 7'd0;
    busy           <= 1'b1;
    mem_wr_ptr_rst <= 1'b1;
    state          <= `MAIN_STATE_INIT_CFG;
end
```

**正常情况**：FSM 进入 INIT_CFG 后不再处于 IDLE，`sys_start` 虽然持续为高，但 FSM 不在 IDLE 状态，所以不会重复触发。✅

**危险情况**：FSM 完成一轮扫描后，在 FINISH 状态执行：
```verilog
// FINISH state:
done   <= 1'b1;  // 单周期脉冲
busy   <= 1'b0;
status <= `SYS_STATUS_DONE;
state  <= `MAIN_STATE_IDLE;  // 回到 IDLE
```

同一时钟沿，`ctrl_register_bank` 收到 `test_done_flag=1`（即 `fsm_done=1`）：
```verilog
// ctrl_register_bank.v, 最高优先级:
if (test_done_flag) begin
    test_active   <= 1'b0;  // 下一时钟沿才生效！
    config_locked <= 1'b0;
end
```

**竞争窗口**：
- **T+N（FINISH 状态）**：FSM 输出 `done=1`，同时 `state←IDLE`
- **T+N+1（IDLE 状态）**：`ctrl_register_bank` 的 `test_active` 在本周期才变为 0（非阻塞赋值在 T+N 时钟沿生效，T+N+1 时 FSM 采样）

**实际分析**：由于 `ctrl_register_bank` 使用非阻塞赋值，`test_active` 在 T+N 时钟沿的上升沿被清零，在 T+N+1 时 FSM 采样时 `test_active` 已经是 0。

**验证**：
- T+N：FINISH 状态，`done←1`，`state←IDLE`，同时 `ctrl_register_bank` 执行 `test_active←0`（非阻塞，T+N+1 生效）
- T+N+1：FSM 处于 IDLE，采样 `sys_start = test_active = 0` → **不会重新触发** ✅

**结论**：代码注释中已说明 `test_done_flag` 优先级高于 `cfg_update_pulse` 的原因，逻辑正确。**但这是一个极其脆弱的单周期时序依赖**，任何综合工具的时序优化都可能破坏它。

**建议修复**：在 `main_scan_fsm` 的 IDLE 状态，将 `sys_start` 改为边沿检测（上升沿触发），而非电平触发：
```verilog
// 建议：在 main_scan_fsm 内部添加边沿检测
reg sys_start_prev;
wire sys_start_pulse = sys_start && !sys_start_prev;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sys_start_prev <= 1'b0;
    else        sys_start_prev <= sys_start;
end
// IDLE 状态改为: if (sys_start_pulse) begin ...
```

### 1.4 🔴 [严重] 问题2：`seed_lock_unit` 的 `lock_en` 与 `capture_pulse` 时序错位

**问题描述**：

在 `top_fault_tolerance_test.v` 中：
```verilog
seed_lock_unit u_seed_lock (
    .lock_en      (config_locked),    // 来自 ctrl_register_bank
    .capture_pulse(cfg_update_pulse), // 来自 protocol_parser（直接连接！）
    ...
);
```

`seed_lock_unit` 的锁存条件是：
```verilog
if (lock_en && capture_pulse) begin
    seed_locked <= free_cnt_val;
end
```

**时序分析**：
- T+0：`cfg_update_pulse=1`（来自 protocol_parser，直接连接到 `capture_pulse`）
- T+0：`ctrl_register_bank` 执行 `config_locked←1`（非阻塞，T+1 才生效）
- T+0：`seed_lock_unit` 采样 `lock_en = config_locked = 0`（旧值！），`capture_pulse = 1`

**结果**：`lock_en=0 && capture_pulse=1` → **条件不满足，种子不会被锁存！**

`seed_locked` 保持复位后的初始值 `0`，`seed_valid=0`。

**后果**：
- `main_scan_fsm` 将 `seed_locked=0` 传给 `auto_scan_engine`
- `prbs_generator` 收到 `seed_in=0`，但有零值保护（使用 `PRBS_SAFE_DEFAULT`）
- 所有 91 个 BER 点使用相同的默认种子，**测试数据不具备随机性**，但不会崩溃

**严重程度**：功能性错误，不会导致死锁，但会导致测试数据质量下降（所有测试使用固定种子）。

**建议修复**：将 `capture_pulse` 延迟一拍，使其与 `config_locked` 对齐：
```verilog
// 在 top_fault_tolerance_test.v 中添加：
reg cfg_update_pulse_d1;
always @(posedge clk_sys or negedge rst_n_sync) begin
    if (!rst_n_sync) cfg_update_pulse_d1 <= 1'b0;
    else             cfg_update_pulse_d1 <= cfg_update_pulse;
end

seed_lock_unit u_seed_lock (
    .lock_en      (config_locked),
    .capture_pulse(cfg_update_pulse_d1), // 延迟一拍，与 config_locked 对齐
    ...
);
```

### 1.5 ⚠️ [警告] 问题3：ROM 查找在 INIT_CFG 状态的多周期等待

**问题描述**：

`main_scan_fsm` 的 INIT_CFG 状态：
```verilog
`MAIN_STATE_INIT_CFG: begin
    rom_req <= 1'b1; // 持续拉高

    if (thresh_valid) begin
        rom_req   <= 1'b0;
        eng_start <= 1'b1;
        state     <= `MAIN_STATE_RUN_TEST;
    end
end
```

`rom_threshold_ctrl` 的行为：
- 当 `req=1` 时，下一周期 `valid=1`
- 当 `req=0` 时，`valid=0`

**时序分析**：
- T+0（进入 INIT_CFG）：`rom_req←1`（非阻塞，T+1 才生效）
- T+1：`rom_req=1`，ROM 执行查找，`valid←1`（T+2 生效）
- T+2：`thresh_valid=1`，FSM 检测到，`eng_start←1`，跳转 RUN_TEST

**问题**：在 T+0 时，`rom_req` 还是 0（非阻塞赋值），ROM 在 T+0 不会启动查找。实际需要 **2个周期** 才能得到有效的 `thresh_valid`，而不是注释中说的"1-cycle BRAM latency"。

**实际影响**：不会导致错误，只是每个 BER 点多消耗 1 个时钟周期（91 × 1 = 91 个额外周期，可忽略）。

**建议**：更新注释，说明实际是 2 周期延迟（进入状态后第 2 个时钟沿才能得到 `thresh_valid`）。

---

## 二、注入链分析：PRBS → 编码器 → 注入器 → 解码器

### 2.1 完整流水线时序

`auto_scan_engine` 的 FSM 状态机流水线：

```
IDLE → CONFIG → GEN_WAIT → ENC_WAIT → INJ_WAIT → DEC_WAIT → COMP_WAIT → DONE
  1      1         1           1          1          2           1          1   (周期数)
```

**详细时序分析**（以进入 CONFIG 为 T=0）：

| 时钟 | 状态 | 关键动作 |
|------|------|---------|
| T=0 | CONFIG | `inject_en_latch ← (inj_lfsr < threshold_val)`；`prbs_start_gen←1` |
| T=1 | GEN_WAIT | PRBS 输出有效（`prbs_valid=1`）；`sym_a/b_latch←prbs_out`（非阻塞）；`enc_start←1` |
| T=2 | ENC_WAIT | `sym_a/b_latch` 稳定；`comp_start←1`（首周期）；等待 `enc_done` |
| T=3 | ENC_WAIT→INJ_WAIT | `enc_done=1`；`enc_out_a/b_latch←codeword[63:0]`；进入 INJ_WAIT |
| T=4 | INJ_WAIT | 注入器输出有效（1周期延迟）；`inj_out_a/b_latch←inj_out_a/b`；`dec_start←1` |
| T=5 | DEC_WAIT | 解码器流水线第1周期 |
| T=6 | DEC_WAIT | `dec_valid_a/b=1`（2周期延迟）；进入 COMP_WAIT |
| T=7 | COMP_WAIT | 比较器结果稳定；`result_pass←comp_result_a && comp_result_b` |
| T=8 | DONE | `done←1`；返回 IDLE |

**总延迟**：约 9 个时钟周期/次测试（不含 ROM 查找的 2 周期）。

### 2.2 ✅ `inj_done` 握手验证

注入链没有显式的 `inj_done` 信号。注入器 (`error_injector_unit`) 是**纯组合+1级寄存器**的结构：
- 输入：`enc_out_a/b_latch`（在 INJ_WAIT 状态入口已稳定）
- 输出：`inj_out_a/b`（1周期后有效）

FSM 在 INJ_WAIT 状态**无条件等待 1 个周期**，然后锁存 `inj_out_a/b` 并启动解码器。

**验证**：
- INJ_WAIT 进入时，`enc_out_a/b_latch` 已在上一周期（ENC_WAIT→INJ_WAIT 跳转时）被锁存
- 注入器的组合逻辑在 INJ_WAIT 的第一个时钟沿就已经稳定
- INJ_WAIT 状态直接锁存并跳转，**不等待任何 done 信号**

**结论**：握手正确，1周期延迟与注入器的寄存器输出匹配。✅

### 2.3 🔴 [严重] 问题4：`comp_start` 与 `sym_a/b_latch` 的时序对齐问题

**问题描述**：

`result_comparator` 的 `start` 信号用于将 `data_orig`（原始数据）压入 FIFO：
```verilog
// result_comparator.v:
wire fifo_wr_en = start && !fifo_full;
// 写入: fifo_mem[wr_ptr] <= data_orig; (在 start=1 的时钟沿)
```

`comp_start` 在 ENC_WAIT 状态的**第一个周期**发出：
```verilog
// auto_scan_engine.v, ENC_WAIT:
if (!comp_start_sent) begin
    comp_start      <= 1'b1;
    comp_start_sent <= 1'b1;
end
```

此时 `data_orig = sym_a_latch`（或 `sym_b_latch`）。

**时序验证**：
- T=1（GEN_WAIT）：`sym_a_latch ← prbs_out[31:16]`（非阻塞赋值，T=2 才生效）
- T=2（ENC_WAIT 第一周期）：`sym_a_latch` 已稳定（T=1 的非阻塞赋值已生效）；`comp_start←1`

**结论**：`comp_start` 发出时，`sym_a/b_latch` 已经是稳定的新值。✅ 这正是代码注释中说明的"comp_start 在 ENC_WAIT 而非 GEN_WAIT 发出"的原因。

### 2.4 🔴 [严重] 问题5：`dec_uncorr` 信号完全未被处理

**问题描述**：

`decoder_wrapper` 输出 `uncorrectable` 信号，表示解码器无法纠正错误。在 `auto_scan_engine` 中：

```verilog
// auto_scan_engine.v:
wire dec_uncorr_a;
wire dec_uncorr_b;

decoder_wrapper u_dec_a (
    ...
    .uncorrectable(dec_uncorr_a)
);
decoder_wrapper u_dec_b (
    ...
    .uncorrectable(dec_uncorr_b)
);
```

**搜索整个 `auto_scan_engine.v`**：`dec_uncorr_a` 和 `dec_uncorr_b` **从未被使用**！

FSM 在 DEC_WAIT 状态：
```verilog
`ENG_STATE_DEC_WAIT: begin
    if (dec_valid_a && dec_valid_b) begin
        state <= `ENG_STATE_COMP_WAIT;
    end
end
```

**只等待 `dec_valid`，完全忽略 `dec_uncorr`。**

**后果分析**：

当 `dec_uncorr=1` 时，解码器仍然会输出 `valid=1`（表示解码完成），但 `data_out` 是无意义的值。`result_comparator` 会将这个无意义值与原始数据比较，结果为 FAIL。

**这意味着**：
1. `dec_uncorr` 不会导致 FSM 死锁（因为 `dec_valid` 仍然会被拉高）✅
2. 但 `dec_uncorr` 信息丢失，无法区分"解码失败（不可纠正）"和"解码成功但数据错误"两种情况
3. 统计数据中的 `Pass/Fail` 位无法区分这两种失败模式，**降低了测试数据的诊断价值**

**建议修复**：在结果打包中增加 `uncorr` 标志位（利用 `[05:00]` 的保留位）：
```verilog
// 在 auto_scan_engine.v 中添加:
reg res_uncorr_latch;
// 在 DEC_WAIT → COMP_WAIT 跳转时:
res_uncorr_latch <= dec_uncorr_a || dec_uncorr_b;

// 在 main_scan_fsm.v 的 packed_result 中:
// [05] : Uncorrectable (1-bit)
assign packed_result = {
    ...
    res_injected_latch,   // [07]
    res_pass_latch,       // [06]
    res_uncorr_latch,     // [05] ← 新增
    5'b0                  // [04:00]
};
```

---

## 三、异常流分析：`dec_uncorr` 持续高电平 / 超时保护

### 3.1 `dec_uncorr` 持续高电平场景

**场景**：注入了超出纠错能力的错误，`dec_uncorr=1`，`dec_valid=1`（同时拉高）。

**FSM 行为**：
```
DEC_WAIT: dec_valid_a=1 && dec_valid_b=1 → 进入 COMP_WAIT
COMP_WAIT: result_pass = comp_result_a && comp_result_b = 0 (FAIL)
DONE: done=1, 返回 IDLE
```

**结论**：`dec_uncorr` 持续高电平**不会导致 FSM 死锁**。解码器在 2 个周期后仍然输出 `valid=1`，FSM 正常推进。✅

### 3.2 🔴 [严重] 问题6：`dec_valid` 永不拉高时的死锁风险

**场景**：如果 `decoder_2nrm` 由于某种原因（如 RTL bug、综合问题）永远不输出 `dec_valid=1`，FSM 将永远停留在 DEC_WAIT 状态。

**DEC_WAIT 状态代码**：
```verilog
`ENG_STATE_DEC_WAIT: begin
    if (dec_valid_a && dec_valid_b) begin
        state <= `ENG_STATE_COMP_WAIT;
    end
    // 无超时保护！
end
```

**后果**：
- `auto_scan_engine` 永远 `busy=1`，`done` 永远不拉高
- `main_scan_fsm` 永远停留在 RUN_TEST 状态（等待 `eng_done`）
- 整个系统**完全死锁**，无法通过 UART 恢复（除非硬件复位）

**同样的风险存在于**：
- GEN_WAIT：等待 `prbs_valid`（PRBS 生成器如果不输出 valid）
- ENC_WAIT：等待 `enc_done`（编码器如果不输出 done）

**当前唯一的恢复手段**：`main_scan_fsm` 的 `sys_abort` 信号，但在 `top_fault_tolerance_test.v` 中：
```verilog
main_scan_fsm u_fsm (
    ...
    .sys_abort  (1'b0),  // Abort not wired to external pin (future)
    ...
);
```

**`sys_abort` 被硬连接为 0！** 这意味着一旦发生死锁，**只能通过硬件复位（按板上 RST 按钮）恢复**。

**建议修复**：在 `auto_scan_engine` 中添加超时计数器：
```verilog
// 在 auto_scan_engine.v 中添加超时保护:
localparam TIMEOUT_CYCLES = 16'd1000; // 10μs @ 100MHz，足够覆盖所有流水线延迟

reg [15:0] timeout_cnt;
reg        timeout_flag;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        timeout_cnt  <= 16'd0;
        timeout_flag <= 1'b0;
    end else begin
        if (state == `ENG_STATE_IDLE) begin
            timeout_cnt  <= 16'd0;
            timeout_flag <= 1'b0;
        end else if (timeout_cnt < TIMEOUT_CYCLES) begin
            timeout_cnt <= timeout_cnt + 1'b1;
        end else begin
            timeout_flag <= 1'b1; // 超时！
        end
    end
end

// 在各等待状态中添加超时退出:
`ENG_STATE_DEC_WAIT: begin
    if (dec_valid_a && dec_valid_b) begin
        state <= `ENG_STATE_COMP_WAIT;
    end else if (timeout_flag) begin
        result_pass <= 1'b0; // 超时视为 FAIL
        state       <= `ENG_STATE_DONE;
    end
end
```

### 3.3 ⚠️ [警告] 问题7：`sys_abort` 未连接到外部引脚

如上所述，`sys_abort` 被硬连接为 `1'b0`。建议将其连接到 UART 命令（通过 `protocol_parser` 解析中止命令），或至少连接到一个板上按钮。

### 3.4 ✅ `mem_wr_ptr_rst` 复位机制验证

在 `main_scan_fsm` 的 IDLE→INIT_CFG 跳转时：
```verilog
mem_wr_ptr_rst <= 1'b1; // 单周期脉冲
state          <= `MAIN_STATE_INIT_CFG;
```

`mem_stats_array` 收到 `wr_ptr_rst=1` 后，将写指针复位到 0，确保新一轮测试从地址 0 开始写入，不会残留上一轮数据。✅

---

## 四、跨模块握手完整性验证

### 4.1 `main_scan_fsm` ↔ `auto_scan_engine` 握手

```
FSM (INIT_CFG):  eng_start ←1 (单周期脉冲)
Engine (IDLE):   检测到 start=1 → 进入 CONFIG
FSM (RUN_TEST):  等待 eng_done
Engine (DONE):   done ←1 (单周期脉冲)
FSM (RUN_TEST):  检测到 eng_done=1 → 进入 SAVE_RES
```

**验证**：
- `eng_start` 是单周期脉冲（在 INIT_CFG 状态的 `if (thresh_valid)` 分支中赋值，下一周期默认清零）✅
- `eng_done` 是单周期脉冲（DONE 状态赋值，下一周期回 IDLE 后默认清零）✅
- FSM 在 RUN_TEST 状态等待 `eng_done`，不会超时（但存在死锁风险，见问题6）

### 4.2 `main_scan_fsm` ↔ `rom_threshold_ctrl` 握手

```
FSM (INIT_CFG):  rom_req ←1
ROM:             1周期后 valid=1, threshold_val 有效
FSM (INIT_CFG):  检测到 thresh_valid=1 → 清除 rom_req，发出 eng_start
```

**潜在问题**：如果 ROM 文件（`.coe`）未正确生成或加载失败，`thresh_rom` 全为 0，`threshold_val=0`，导致 `inj_lfsr < 0` 永远为假，**注入永远不发生**。这不会导致死锁，但测试数据无效（所有点都是无注入的基准测试）。

### 4.3 `main_scan_fsm` ↔ `mem_stats_array` 握手

```
FSM (SAVE_RES):  mem_wr_en ←1 (单周期), mem_wr_data ← packed_result
MEM:             内部写指针自动递增
FSM (NEXT_ITER): 检查 ber_cnt 是否达到 90
```

**验证**：写操作是单周期的，`mem_stats_array` 使用内部写指针（循环模式），与 `ber_cnt` 同步递增。✅

### 4.4 `main_scan_fsm` ↔ `tx_packet_assembler` 握手

```
FSM (PREP_UPLOAD): asm_start ←1 (单周期脉冲)
ASM:               开始读取 mem_stats_array，组装并发送 UART 数据包
FSM (DO_UPLOAD):   等待 asm_done
ASM:               发送完成后 done ←1
FSM (DO_UPLOAD):   检测到 asm_done=1 → 进入 FINISH
```

**验证**：握手逻辑正确。✅

---

## 五、问题汇总与优先级

| 编号 | 严重程度 | 位置 | 问题描述 | 影响 |
|------|---------|------|---------|------|
| P1 | 🔴 [严重] | `main_scan_fsm` IDLE | `sys_start` 电平触发，存在单周期竞争窗口 | 可能导致测试意外重启 |
| P2 | 🔴 [严重] | `top_fault_tolerance_test.v` | `seed_lock_unit` 的 `lock_en` 与 `capture_pulse` 时序错位 | 种子永远无法锁存，测试随机性丧失 |
| P3 | 🔴 [严重] | `auto_scan_engine` | `dec_uncorr_a/b` 信号完全未使用 | 失败模式无法区分，统计数据诊断价值降低 |
| P4 | 🔴 [严重] | `auto_scan_engine` DEC_WAIT | 无超时保护，`dec_valid` 永不拉高时系统死锁 | 需硬件复位才能恢复 |
| P5 | 🔴 [严重] | `top_fault_tolerance_test.v` | `sys_abort` 硬连接为 0，无软件中止手段 | 死锁后无法通过 UART 恢复 |
| P6 | ⚠️ [警告] | `main_scan_fsm` INIT_CFG | ROM 查找实际需要 2 周期，注释说 1 周期 | 注释误导，无功能影响 |
| P7 | ⚠️ [警告] | `rom_threshold_ctrl` | ROM 文件缺失时 `threshold=0`，注入永不发生 | 测试数据无效但不崩溃 |

---

## 六、修复建议代码（关键问题）

### 修复 P2：`seed_lock_unit` 时序对齐（`top_fault_tolerance_test.v`）

```verilog
// 在 top_fault_tolerance_test.v 的 Section 7 之前添加：
// =========================================================================
// 6b. cfg_update_pulse 延迟一拍（与 config_locked 对齐）
// =========================================================================
reg cfg_update_pulse_d1;
always @(posedge clk_sys or negedge rst_n_sync) begin
    if (!rst_n_sync) cfg_update_pulse_d1 <= 1'b0;
    else             cfg_update_pulse_d1 <= cfg_update_pulse;
end

// Section 7 中修改:
seed_lock_unit u_seed_lock (
    .clk          (clk_sys),
    .rst_n        (rst_n_sync),
    .lock_en      (config_locked),
    .capture_pulse(cfg_update_pulse_d1),  // ← 修改：使用延迟版本
    .free_cnt_val (free_counter),
    .seed_locked  (seed_locked),
    .seed_valid   (seed_valid)
);
```

### 修复 P1：`main_scan_fsm` 边沿检测（`main_scan_fsm.v`）

```verilog
// 在 main_scan_fsm.v 的 Section 8 之前添加：
// =========================================================================
// 8b. sys_start 上升沿检测（防止电平持续触发）
// =========================================================================
reg sys_start_prev;
wire sys_start_pulse;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sys_start_prev <= 1'b0;
    else        sys_start_prev <= sys_start;
end
assign sys_start_pulse = sys_start && !sys_start_prev;

// IDLE 状态改为：
`MAIN_STATE_IDLE: begin
    busy   <= 1'b0;
    status <= `SYS_STATUS_IDLE;
    if (sys_start_pulse) begin  // ← 改为边沿触发
        ber_cnt        <= 7'd0;
        busy           <= 1'b1;
        status         <= `SYS_STATUS_TESTING;
        mem_wr_ptr_rst <= 1'b1;
        state          <= `MAIN_STATE_INIT_CFG;
    end
end
```

---

## 七、结论

**系统整体架构设计合理**，主要信号流路径（启动→扫描→上传）在正常情况下可以正确工作。但存在以下**上板前必须修复**的问题：

1. **P2（种子锁存时序错位）**：必须修复，否则所有测试使用固定种子，测试数据无统计意义。
2. **P4（DEC_WAIT 无超时）**：必须修复，否则任何解码器异常都会导致系统永久死锁。
3. **P5（sys_abort 未连接）**：必须修复，至少连接到一个板上按钮，提供硬件恢复手段。
4. **P1（sys_start 电平触发）**：建议修复，当前代码依赖单周期时序窗口，风险较高。
5. **P3（dec_uncorr 未使用）**：建议修复，提升测试数据的诊断价值。

**下一步**：待确认后，继续执行**第六步：数据回传链路深度检查（FPGA 侧）**。
