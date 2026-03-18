## ILA 调试准备完成

`auto_scan_engine.v` 已添加以下 `mark_debug` 属性，重新综合后可在 ILA 中观察：

| 信号 | 位宽 | 用途 |
|------|------|------|
| `state` | 3-bit | FSM 状态（0=IDLE,1=CONFIG,2=GEN_WAIT,3=ENC_WAIT,4=INJ_WAIT,5=DEC_WAIT,6=COMP_WAIT,7=DONE）|
| `inject_en_latch` | 1-bit | 本次 trial 是否注入错误 |
| `sym_a_latch` | 16-bit | 原始符号 A |
| `sym_b_latch` | 16-bit | 原始符号 B |
| `enc_out_a_latch` | 64-bit | 编码后码字 A（有效位 [40:0]）|
| `enc_out_b_latch` | 64-bit | 编码后码字 B（有效位 [40:0]）|
| `inj_out_a_latch` | 64-bit | 注入后码字 A（有效位 [40:0]）|
| `inj_out_b_latch` | 64-bit | 注入后码字 B（有效位 [40:0]）|
| `dec_start` | 1-bit | 解码器启动脉冲 |
| `dec_out_a` | 16-bit | 解码结果 A |
| `dec_out_b` | 16-bit | 解码结果 B |
| `dec_valid_a` | 1-bit | 解码器 A 输出有效 |
| `dec_valid_b` | 1-bit | 解码器 B 输出有效 |
| `dec_uncorr_a/b` | 1-bit | 不可纠正错误标志 |
| `comp_start` | 1-bit | 比较器启动脉冲 |
| `comp_result_a/b` | 1-bit | 比较结果 |
| `comp_latency_a` | 8-bit | 测量延迟（应为 23）|

### ILA 触发建议
- **触发条件**：`dec_valid_a == 1`（捕获解码完成时刻）
- **捕获深度**：1024 samples，触发位置设为 50%
- **关键验证点**：
  1. `dec_valid_a=1` 时，`dec_out_a` 是否等于 `sym_a_latch`？（无注入时应相等）
  2. `inject_en_latch=0` 时，`inj_out_a_latch` 是否等于 `enc_out_a_latch`？（pass-through 验证）
  3. `comp_result_a` 在 `dec_valid_a=1` 后 1 拍是否为 1？

### 操作步骤
1. Vivado → Run Synthesis → Run Implementation → Generate Bitstream
2. Open Hardware Manager → Program Device
3. Set up ILA trigger: `dec_valid_a == 1`
4. Run test with `sample_count=10`（少量 trial 便于观察）
5. 截图波形，重点对比 `sym_a_latch` vs `dec_out_a`