
Task Completed

✅ 修复确认（第二步全部完成）
修复项	文件	状态
typedef enum → reg [2:0] + localparam 宏	protocol_parser.vh	✅
所有状态常量加反引号（ST_IDLE→`ST_IDLE 等）	protocol_parser.v	✅
test_done_flag 优先级提升至 if-else 最高位	ctrl_register_bank.v	✅
第三步：深度检查 main_scan_fsm + auto_scan_engine
3.1 main_scan_fsm 端口匹配检查
顶层实例化（top_fault_tolerance_test.v）：


main_scan_fsm u_fsm (
    .clk        (clk_sys),
    .rst_n      (rst_n_sync),
    .sys_start  (test_active),
    .sys_abort  (1'b0),
    .burst_len  (reg_burst_len[3:0]),   // 4-bit slice of 8-bit reg
    .seed_in    (seed_locked),          // 32-bit
    .load_seed  (cfg_update_pulse),
    .busy       (fsm_busy),
    .done       (fsm_done),
    .status     (fsm_status),
    .ber_cnt_out(fsm_ber_cnt),
    .tx_valid   (fsm_tx_valid),
    .tx_data    (fsm_tx_data),
    .tx_ready   (~tx_busy_w),
    .led_cfg_ok (led_cfg_ok_w),
    .led_running(led_running_w),
    .led_sending(led_sending_w),
    .led_error  (led_error_w)
);
模块实际定义（main_scan_fsm.v）：

顶层连接	模块端口	位宽	状态
.clk(clk_sys)	input wire clk	1-bit	✅
.rst_n(rst_n_sync)	input wire rst_n	1-bit	✅
.sys_start(test_active)	input wire sys_start	1-bit	✅
.sys_abort(1'b0)	input wire sys_abort	1-bit	✅
.burst_len(reg_burst_len[3:0])	input wire [3:0] burst_len	4-bit	✅
.seed_in(seed_locked)	input wire [31:0] seed_in	32-bit	✅
.load_seed(cfg_update_pulse)	input wire load_seed	1-bit	✅
.busy(fsm_busy)	output reg busy	1-bit	✅
.done(fsm_done)	output reg done	1-bit	✅
.status(fsm_status)	output reg [1:0] status	2-bit	✅
.ber_cnt_out(fsm_ber_cnt)	output reg [6:0] ber_cnt_out	7-bit	✅
.tx_valid(fsm_tx_valid)	output wire tx_valid	1-bit	✅
.tx_data(fsm_tx_data)	output wire [7:0] tx_data	8-bit	✅
.tx_ready(~tx_busy_w)	input wire tx_ready	1-bit	✅
.led_cfg_ok(led_cfg_ok_w)	output wire led_cfg_ok	1-bit	✅
.led_running(led_running_w)	output wire led_running	1-bit	✅
.led_sending(led_sending_w)	output wire led_sending	1-bit	✅
.led_error(led_error_w)	output wire led_error	1-bit	✅
✅ 所有端口完全匹配，无位宽冲突。

3.2 main_scan_fsm 内部逻辑检查
🔴 [严重-4] mem_stats_array 写地址端口缺失 — 数据写入位置不可控
main_scan_fsm.v 中实例化 mem_stats_array 时：


mem_stats_array u_mem (
    .wr_en  (mem_wr_en),
    .wr_data(mem_wr_data),
    .mode   (`MODE_CIRCULAR),
    .rd_en  (mem_rd_en_w),
    .rd_addr(mem_rd_addr_w),
    .rd_data(mem_rd_data_w),
    ...
);
mem_stats_array.v 使用内部自增写指针（wr_ptr），没有外部写地址输入。FSM 中声明的 reg [6:0] mem_wr_addr 被赋值但从未连接到任何端口，是死信号。

关键问题：FSM 在 91 个 BER 点中顺序写入，依赖 mem_stats_array 的内部指针从 0 自增到 90。但 mem_stats_array 的深度是 1024（STATS_MEM_DEPTH=1024），而 FSM 只写 91 条。tx_packet_assembler 从地址 0 读 91 条，这在功能上是正确的——只要每次测试前 mem_stats_array 的写指针被复位到 0。

问题：mem_stats_array 的写指针 wr_ptr 只在 rst_n 时复位。如果进行第二次测试（不复位），写指针从 91 继续，第二次的数据写到地址 91~181，但 tx_packet_assembler 仍从地址 0 读，读到的是第一次测试的旧数据！

修复建议：在 mem_stats_array 中增加一个 wr_ptr_reset 输入端口，或在 FSM 的 IDLE→INIT_CFG 跳转时发送一个清零脉冲。

🟡 [警告-5] INIT_CFG 状态中 rom_req 与 thresh_valid 的时序逻辑存在潜在死锁

`MAIN_STATE_INIT_CFG: begin
    rom_req <= 1'b1; // Assert rom_req

    if (thresh_valid) begin
        rom_req   <= 1'b0;
        eng_start <= 1'b1;
        state     <= `MAIN_STATE_RUN_TEST;
    end
end
rom_threshold_ctrl 的行为：

当 req=1 时，下一个时钟周期 valid=1
当 req=0 时，valid=0
时序分析：

周期 N：进入 INIT_CFG，rom_req 被赋值为 1（但寄存器在周期 N+1 才生效）
周期 N+1：rom_req=1 生效，ROM 开始查找
周期 N+2：thresh_valid=1，FSM 检测到，跳转到 RUN_TEST
这是正确的 2 周期延迟，无死锁风险。✅

但注意：在 INIT_CFG 状态，rom_req 每个周期都被赋值为 1（直到 thresh_valid 到来）。由于 ROM 是单周期延迟，thresh_valid 在第二个周期就会到来，所以 rom_req 只会保持 1 个周期高电平，然后被清零。这是正确的。✅

🟡 [警告-6] packed_result 位宽计算验证

wire [63:0] packed_result;
assign packed_result = {
    {1'b0, ber_cnt},          // [63:56] = 8-bit (1+7=8) ✅
    2'd`CURRENT_ALGO_ID,      // [55:54] = 2-bit ✅
    6'b0,                     // [53:48] = 6-bit ✅
    {2'b0, res_flip_a_latch}, // [47:40] = 8-bit (2+6=8) ✅
    {2'b0, res_flip_b_latch}, // [39:32] = 8-bit (2+6=8) ✅
    res_latency_latch,        // [31:24] = 8-bit ✅
    16'b0,                    // [23:08] = 16-bit ✅
    res_injected_latch,       // [07]    = 1-bit ✅
    res_pass_latch,           // [06]    = 1-bit ✅
    6'b0                      // [05:00] = 6-bit ✅
};
// Total: 8+2+6+8+8+8+16+1+1+6 = 64-bit ✅
✅ 位宽计算正确，总计 64 位。

3.3 auto_scan_engine 端口匹配检查
main_scan_fsm.v 中实例化：


auto_scan_engine u_engine (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (eng_start),
    .algo_id       (2'd`CURRENT_ALGO_ID),
    .threshold_val (threshold_val),
    .burst_len     (burst_len),
    .seed_in       (seed_in),
    .load_seed     (load_seed),
    .busy          (eng_busy),
    .done          (eng_done),
    .result_pass   (eng_result_pass),
    .latency_cycles(eng_latency),
    .was_injected  (eng_was_injected),
    .flip_count_a  (eng_flip_a),
    .flip_count_b  (eng_flip_b)
);
模块实际定义（auto_scan_engine.v）：

连接端口	模块端口	位宽	状态
.algo_id(2'd\CURRENT_ALGO_ID)`	input wire [1:0] algo_id	2-bit	✅
.threshold_val(threshold_val)	input wire [31:0] threshold_val	32-bit	✅
.burst_len(burst_len)	input wire [3:0] burst_len	4-bit	✅
.seed_in(seed_in)	input wire [31:0] seed_in	32-bit	✅
.eng_latency	output reg [7:0] latency_cycles	8-bit	✅
.flip_count_a(eng_flip_a)	output reg [5:0] flip_count_a	6-bit	✅
.flip_count_b(eng_flip_b)	output reg [5:0] flip_count_b	6-bit	✅
✅ 所有端口匹配正确。

3.4 auto_scan_engine 内部逻辑检查
🔴 [严重-5] comp_start 时序错误 — 比较器 FIFO 写入时机不正确
在 ENG_STATE_GEN_WAIT 状态：


`ENG_STATE_GEN_WAIT: begin
    if (prbs_valid) begin
        sym_a_latch <= prbs_out[31:16];
        sym_b_latch <= prbs_out[15:0];
        comp_start  <= 1'b1;   // ← 触发比较器 FIFO 写入
        enc_start   <= 1'b1;   // ← 同时启动编码器
        state       <= `ENG_STATE_ENC_WAIT;
    end
end
result_comparator 的 start 信号触发将 data_orig 写入 FIFO。但此时 sym_a_latch 和 sym_b_latch 是在同一个时钟沿被赋值的（非阻塞赋值），它们在下一个时钟周期才生效。

因此，当 comp_start=1 时，data_orig（即 sym_a_latch/sym_b_latch）仍是上一次的旧值，FIFO 写入的是错误数据！

修复建议：将 comp_start 延迟一个周期，在 ENG_STATE_ENC_WAIT 状态的第一个周期发出，此时 sym_a_latch 已经稳定：


// 修复方案：在 ENC_WAIT 状态入口发出 comp_start
`ENG_STATE_GEN_WAIT: begin
    if (prbs_valid) begin
        sym_a_latch <= prbs_out[31:16];
        sym_b_latch <= prbs_out[15:0];
        // 不在这里发 comp_start
        enc_start   <= 1'b1;
        state       <= `ENG_STATE_ENC_WAIT;
    end
end

`ENG_STATE_ENC_WAIT: begin
    comp_start <= 1'b1;  // ← 此时 sym_a/b_latch 已稳定（上周期赋值）
    comp_start <= 1'b0;  // 只需一个周期
    if (enc_done) begin
        ...
    end
end
更简洁的方案：在 ENG_STATE_ENC_WAIT 入口（第一个周期）发出 comp_start，用一个 flag 防止重复：


// 在 ENG_STATE_ENC_WAIT 的第一个周期发出 comp_start
reg comp_start_sent;

`ENG_STATE_ENC_WAIT: begin
    if (!comp_start_sent) begin
        comp_start      <= 1'b1;
        comp_start_sent <= 1'b1;
    end
    if (enc_done) begin
        comp_start_sent <= 1'b0;
        ...
    end
end
🟡 [警告-7] encoder_wrapper 的 done 信号逻辑存在风险
encoder_wrapper.v 中：


assign done = done_2nrm | done_3nrm | done_crrns | done_rs;
当前 done_3nrm、done_crrns、done_rs 均为常量 1'b0，所以 done = done_2nrm，功能正确。

但 encoder_wrapper 的输出寄存器在 start 信号时更新：


always @(posedge clk or negedge rst_n) begin
    ...
    end else if (start) begin
        case (algo_sel)
            ALGO_2NRM: begin
                codeword_A <= {192'd0, out_2nrm_A[63:0]};
                ...
            end
        end
    end
end
而 encoder_2nrm 的 done 也在 start 的同一周期输出（done <= 1'b1 在 if (start) 块中）。因此 encoder_wrapper 的 done 输出和 codeword 输出在同一周期有效，但 codeword 是 encoder_wrapper 的寄存器输出，而 done 来自 encoder_2nrm 的组合路径（通过 assign done = done_2nrm）。

实际上：encoder_2nrm.done 是寄存器输出（在 start 周期的下一个时钟沿输出），encoder_wrapper.codeword 也是寄存器输出（在 start 周期的下一个时钟沿输出）。两者同步，auto_scan_engine 在 ENC_WAIT 状态等待 enc_done=1 时，codeword 已经稳定。✅

第三步总结
问题编号	级别	模块	描述
严重-4	🔴 严重	mem_stats_array / main_scan_fsm	写指针无法复位，第二次测试会写到错误地址，读出旧数据
严重-5	🔴 严重	auto_scan_engine	comp_start 与 sym_latch 同周期赋值，FIFO 写入旧数据
警告-7	🟡 警告	encoder_wrapper	done 信号通过 OR 组合，未来添加其他算法时需注意时序一致性
请确认后，我将继续第四步：深度检查 encoder/decoder 链路（encoder_2nrm, decoder_wrapper, decoder_2nrm）。