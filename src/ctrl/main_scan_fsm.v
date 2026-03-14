// =============================================================================
// File: main_scan_fsm.v
// Description: Main Scan FSM - Top-Level BER Sweep Controller
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.1.3.2 & 2.3.3.5
// Version: v1.0
//
// ─────────────────────────────────────────────────────────────────────────────
// STRATEGY: "Single Algorithm per Build, Full BER Sweep, Unified Upload"
//
//   1. ALGORITHM SELECTION: Fixed at compile time via `CURRENT_ALGO_ID.
//      The encoder/decoder hardware is selected by `ifdef in sub-modules.
//      This FSM passes `CURRENT_ALGO_ID as a constant to auto_scan_engine.
//
//   2. BER SWEEP: Iterates ber_cnt from 0 to 90 (91 points total).
//      For each BER point:
//        a. Load threshold from ROM (indexed by ber_cnt + CURRENT_ALGO_ID + burst_len)
//        b. Run one test trial via auto_scan_engine
//        c. Save result to mem_stats_array at address ber_cnt
//        d. Increment ber_cnt
//
//   3. UNIFIED UPLOAD: After all 91 points complete, tx_packet_assembler
//      reads all 91 entries from address 0 and sends them via UART.
//      The host PC receives one complete dataset per test run.
//
// FSM STATE FLOW:
//   IDLE → INIT_CFG → RUN_TEST → SAVE_RES → NEXT_ITER
//                                              ↓ (ber_cnt < 91)
//                                           INIT_CFG (loop back)
//                                              ↓ (ber_cnt == 91)
//                                           PREP_UPLOAD → DO_UPLOAD → FINISH → IDLE
//
// RESULT PACKING FORMAT (64-bit per entry, per main_scan_fsm.vh):
//   [63:56] : BER_Idx        (8-bit, value = ber_cnt, 0~90)
//   [55:54] : Algo_ID        (2-bit, constant = `CURRENT_ALGO_ID)
//   [53:48] : Reserved       (6-bit, 0)
//   [47:40] : Flip_Count_A   (8-bit, from auto_scan_engine)
//   [39:32] : Flip_Count_B   (8-bit, from auto_scan_engine)
//   [31:24] : Latency_Cycles (8-bit, from auto_scan_engine)
//   [23:08] : Reserved       (16-bit, 0)
//   [07]    : Was_Injected   (1-bit, from auto_scan_engine)
//   [06]    : Pass/Fail      (1-bit, 1=Pass, from auto_scan_engine)
//   [05:00] : Reserved       (6-bit, 0)
// =============================================================================

`include "main_scan_fsm.vh"
`include "auto_scan_engine.vh"
`include "rom_threshold_ctrl.vh"
`include "mem_stats_array.vh"
`include "tx_packet_assembler.vh"
`timescale 1ns / 1ps

module main_scan_fsm (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Control Interface (From UART Command Parser)
    // -------------------------------------------------------------------------
    input  wire        sys_start,
    // sys_start: Single-cycle pulse to begin the full BER sweep.
    // Ignored if busy=1.

    input  wire        sys_abort,
    // sys_abort: Asynchronous abort. Returns FSM to IDLE immediately.
    // Clears all counters and sub-module states.

    input  wire [31:0] sample_count,
    // sample_count: Number of trials per BER point (from ctrl_register_bank).
    // Range: 1 ~ 4,294,967,295. Held stable during the entire sweep.

    input  wire [1:0]  mode_id,
    // mode_id: Error mode ID (0=Random, 1=Burst) from ctrl_register_bank.reg_error_mode.
    // Embedded in Global Info field of the uplink response frame.
    // Held stable during the entire sweep.

    input  wire [3:0]  burst_len,
    // burst_len: Error burst length (1~15) for error injector.
    // Held stable during the entire sweep.

    input  wire [31:0] seed_in,
    // seed_in: PRBS seed from seed_lock_unit.

    input  wire        load_seed,
    // load_seed: Pulse to load seed into PRBS generator.

    // -------------------------------------------------------------------------
    // Status Outputs
    // -------------------------------------------------------------------------
    output reg         busy,
    // busy: HIGH when FSM is not in IDLE or FINISH state.

    output reg         done,
    // done: Single-cycle pulse when entire sweep + upload is complete.

    output reg  [1:0]  status,
    // status: Current system status (SYS_STATUS_* codes).

    output reg  [6:0]  ber_cnt_out,
    // ber_cnt_out: Current BER index being tested (0~90). For debug/display.

    // -------------------------------------------------------------------------
    // UART TX Output (Passed through from tx_packet_assembler)
    // -------------------------------------------------------------------------
    output wire        tx_valid,
    output wire [7:0]  tx_data,
    input  wire        tx_ready,

    // -------------------------------------------------------------------------
    // LED Debug Outputs (Directly driven by FSM state, for board-level debug)
    // -------------------------------------------------------------------------
    output wire        led_cfg_ok,
    // led_cfg_ok: HIGH when FSM is in IDLE state (config OK, waiting for start).

    output wire        led_running,
    // led_running: HIGH when FSM is in RUN_TEST state (test in progress).

    output wire        led_sending,
    // led_sending: HIGH when FSM is in DO_UPLOAD state (UART reporting).

    output wire        led_error
    // led_error: HIGH when FSM is in an unexpected/error state.
);

    // =========================================================================
    // 1. FSM State Register
    // =========================================================================
    reg [3:0] state;

    // =========================================================================
    // 1b. sys_start Rising-Edge Detector (BUG FIX P1)
    // =========================================================================
    // PROBLEM: sys_start is a sustained HIGH level signal (driven by
    //   ctrl_register_bank.test_active, which stays HIGH for the entire
    //   91-point sweep duration). If the FSM ever returns to IDLE while
    //   sys_start is still HIGH (e.g., after FINISH state), it would
    //   immediately re-trigger a new sweep without user intent.
    //
    //   The current code relies on a fragile single-cycle window:
    //     T+N:   FINISH state → done=1, state←IDLE
    //     T+N:   ctrl_register_bank → test_active←0 (NBA, takes effect T+N+1)
    //     T+N+1: IDLE state samples sys_start=0 → no re-trigger ✓
    //   This works only because NBA semantics guarantee test_active is 0
    //   at T+N+1. Any synthesis reordering could break this.
    //
    // FIX: Detect the RISING EDGE of sys_start inside main_scan_fsm.
    //   The FSM only starts a new sweep on the 0→1 transition of sys_start,
    //   not on a sustained HIGH level. This makes the trigger robust against:
    //   1. Synthesis timing variations
    //   2. sys_start staying HIGH after FINISH (no re-trigger)
    //   3. sys_start being HIGH at power-on reset release (no spurious start)
    //
    // BEHAVIOR AFTER FIX:
    //   - sys_start goes LOW→HIGH: FSM starts sweep (if in IDLE)
    //   - sys_start stays HIGH during sweep: no effect (FSM not in IDLE)
    //   - sys_start stays HIGH after sweep completes (FINISH→IDLE): no re-trigger
    //     because the rising edge already occurred; no new edge is detected
    //   - To start a new sweep: sys_start must go LOW then HIGH again
    //     (ctrl_register_bank handles this: test_done_flag clears test_active,
    //      then a new cfg_update_pulse sets it again)
    //
    // NOTE: sys_start_prev is registered with async reset to ensure it
    //   initializes to 0, so the first rising edge after reset is detected.

    reg  sys_start_prev;
    wire sys_start_pulse; // Single-cycle pulse on rising edge of sys_start

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sys_start_prev <= 1'b0;
        else        sys_start_prev <= sys_start;
    end

    // Rising edge: sys_start goes 0→1
    assign sys_start_pulse = sys_start && !sys_start_prev;

    // =========================================================================
    // 1b. LED Debug Assignments (Combinational, directly from state register)
    // =========================================================================
    // LED mapping per top_fault_tolerance_test.vh:
    //   led_cfg_ok  → IDLE state (config OK, waiting for start command)
    //   led_running → RUN_TEST state (BER sweep test in progress)
    //   led_sending → DO_UPLOAD state (UART packet transmission in progress)
    //   led_error   → default/unexpected state (watchdog / synthesis error)
    assign led_cfg_ok  = (state == `MAIN_STATE_IDLE);
    assign led_running = (state == `MAIN_STATE_RUN_TEST);
    assign led_sending = (state == `MAIN_STATE_DO_UPLOAD);
    // Error: any state not in the normal sequence (catch-all for unexpected states)
    assign led_error   = (state > `MAIN_STATE_FINISH);

    // =========================================================================
    // 2. BER Sweep Counter
    // =========================================================================
    reg [6:0] ber_cnt; // 0 ~ 90 (7-bit, max 127)

    always @(*) ber_cnt_out = ber_cnt;

    // =========================================================================
    // 3. ROM Threshold Controller Instance
    // =========================================================================
    // Provides 32-bit injection threshold for current (algo_id, ber_idx, burst_len)
    reg         rom_req;
    wire [31:0] threshold_val;
    wire        thresh_valid;

    rom_threshold_ctrl u_rom (
        .clk          (clk),
        .rst_n        (rst_n),
        .req          (rom_req),
        .algo_id      (2'd`CURRENT_ALGO_ID),
        .ber_idx      (ber_cnt),
        .burst_len    (burst_len),
        .threshold_val(threshold_val),
        .valid        (thresh_valid)
    );

    // =========================================================================
    // 4. Auto Scan Engine Instance
    // =========================================================================
    reg         eng_start;
    wire        eng_busy;
    wire        eng_done;
    wire        eng_result_pass;
    wire [7:0]  eng_latency;
    wire        eng_was_injected;
    wire [5:0]  eng_flip_a;
    wire [5:0]  eng_flip_b;
    wire [1:0]  eng_uncorr_cnt; // FIX P3: uncorrectable error indicator

    auto_scan_engine u_engine (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (eng_start),
        // Algorithm ID is a compile-time constant for this build
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
        .flip_count_b  (eng_flip_b),
        .uncorr_cnt    (eng_uncorr_cnt)  // FIX P3: connect uncorr_cnt output
    );

    // Latch engine results for use in SAVE_RES state
    reg        res_pass_latch;
    reg [7:0]  res_latency_latch;
    reg        res_injected_latch;
    reg [5:0]  res_flip_a_latch;
    reg [5:0]  res_flip_b_latch;
    reg [1:0]  res_uncorr_latch; // FIX P3: latch uncorr_cnt for packing

    // =========================================================================
    // 5. Accumulator Registers (REFACTOR v2.0 — BER Statistical Aggregator)
    // =========================================================================
    // These registers accumulate statistics across all N trials of a single
    // BER point. They are cleared at the start of each new BER point (NEXT_ITER)
    // and written to mem_stats_array once per BER point (SAVE_RES).
    //
    // Width rationale:
    //   acc_success / acc_fail: 32-bit (Uint32). Max value = cfg_sample_count
    //     (up to 4,294,967,295). 32-bit is sufficient per spec.
    //   acc_flip: 32-bit (Uint32). Max flips per trial = 15 (burst_len max).
    //     Max total = 15 × 4,294,967,295 > 32-bit. However, spec defines
    //     Actual_Flip_Count as Uint32, so we saturate at 32-bit max.
    //   acc_clk: 64-bit (Uint64). Per spec requirement. Prevents overflow
    //     for long tests (32-bit overflows at ~42 seconds @ 100MHz).

    reg [31:0] acc_success;   // Cumulative pass count for current BER point
    reg [31:0] acc_fail;      // Cumulative fail count for current BER point
    reg [31:0] acc_flip;      // Cumulative flip count for current BER point
    reg [63:0] acc_clk;       // Cumulative clock cycles for current BER point
    reg [31:0] trial_cnt;     // Counts trials within current BER point (0 ~ sample_count-1)

    // =========================================================================
    // 5b. Memory Statistics Array Instance (REFACTOR v2.0)
    // =========================================================================
    // v2.0: 176-bit direct-addressed RAM (91 entries).
    // Write address = ber_cnt (driven by FSM, not internal pointer).
    // Read port driven by tx_packet_assembler.

    reg                          mem_we_a;
    reg  [`STATS_MEM_ADDR_WIDTH-1:0] mem_wr_addr_a;
    reg  [`STATS_DATA_WIDTH-1:0] mem_din_a;

    wire [`STATS_MEM_ADDR_WIDTH-1:0] mem_rd_addr_w;
    wire [`STATS_DATA_WIDTH-1:0]     mem_dout_b_w;

    mem_stats_array u_mem (
        .clk       (clk),
        .rst_n     (rst_n),
        // Write port A: FSM controls address and data
        .we_a      (mem_we_a),
        .wr_addr_a (mem_wr_addr_a),
        .din_a     (mem_din_a),
        // Read port B: tx_packet_assembler controls
        .rd_addr_b (mem_rd_addr_w),
        .dout_b    (mem_dout_b_w)
    );

    // =========================================================================
    // 6. TX Packet Assembler Instance (REFACTOR v2.0)
    // =========================================================================
    // v2.0: assembler reads 176-bit entries from mem_stats_array.
    // mem_stats_array read port is synchronous (1-cycle latency).
    // The assembler's READ_WAIT sub-state handles this latency internally.

    reg         asm_start;
    wire        asm_busy;
    wire        asm_done;
    wire [`STATS_MEM_ADDR_WIDTH-1:0] asm_mem_rd_addr_w;

    // Connect assembler's read address to mem_stats_array port B
    assign mem_rd_addr_w = asm_mem_rd_addr_w;

    tx_packet_assembler u_asm (
        .clk          (clk),
        .rst_n        (rst_n),
        // Control
        .start        (asm_start),
        .algo_id_in   (2'd`CURRENT_ALGO_ID),
        .mode_id_in   (mode_id),            // FIX Issue1: from ctrl_register_bank.reg_error_mode
        // Memory read interface (176-bit)
        .mem_rd_addr  (asm_mem_rd_addr_w),
        .mem_rd_data  (mem_dout_b_w),       // 176-bit from mem_stats_array port B
        // TX output
        .tx_valid     (tx_valid),
        .tx_data      (tx_data),
        .tx_ready     (tx_ready),
        // Status
        .busy         (asm_busy),
        .done         (asm_done)
    );

    // =========================================================================
    // 7. 176-bit Statistics Packing (REFACTOR v2.0)
    // =========================================================================
    // Packs accumulated statistics into 176-bit format per Spec v1.7 Sec 2.1.3.2.
    //
    // FORMAT (Big-Endian field order, MSB first):
    //   [175:168] BER_Index         = ber_cnt (8-bit, zero-extended from 7-bit)
    //   [167:136] Success_Count     = acc_success (32-bit Uint32)
    //   [135:104] Fail_Count        = acc_fail    (32-bit Uint32)
    //   [103:72]  Actual_Flip_Count = acc_flip    (32-bit Uint32)
    //   [71:8]    Clk_Count         = acc_clk     (64-bit Uint64)
    //   [7:0]     Reserved          = 8'h00
    //
    // This wire is used in SAVE_RES state to write to mem_stats_array.

    wire [`STATS_DATA_WIDTH-1:0] packed_stats;
    assign packed_stats = {
        {1'b0, ber_cnt},   // [175:168] BER_Index (8-bit, ber_cnt is 7-bit)
        acc_success,       // [167:136] Success_Count (32-bit)
        acc_fail,          // [135:104] Fail_Count (32-bit)
        acc_flip,          // [103:72]  Actual_Flip_Count (32-bit)
        acc_clk,           // [71:8]    Clk_Count (64-bit)
        8'h00              // [7:0]     Reserved
    };

    // =========================================================================
    // 8. Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= `MAIN_STATE_IDLE;
            busy               <= 1'b0;
            done               <= 1'b0;
            status             <= `SYS_STATUS_IDLE;
            ber_cnt            <= 7'd0;
            eng_start          <= 1'b0;
            rom_req            <= 1'b0;
            // v2.0 mem signals
            mem_we_a           <= 1'b0;
            mem_wr_addr_a      <= {`STATS_MEM_ADDR_WIDTH{1'b0}};
            mem_din_a          <= {`STATS_DATA_WIDTH{1'b0}};
            asm_start          <= 1'b0;
            res_pass_latch     <= 1'b0;
            res_latency_latch  <= 8'd0;
            res_injected_latch <= 1'b0;
            res_flip_a_latch   <= 6'd0;
            res_flip_b_latch   <= 6'd0;
            res_uncorr_latch   <= 2'b00;
            // v2.0 accumulators + trial counter
            acc_success        <= 32'd0;
            acc_fail           <= 32'd0;
            acc_flip           <= 32'd0;
            acc_clk            <= 64'd0;
            trial_cnt          <= 32'd0;

        end else begin
            // Default: deassert single-cycle signals
            done      <= 1'b0;
            eng_start <= 1'b0;
            rom_req   <= 1'b0;
            mem_we_a  <= 1'b0;
            asm_start <= 1'b0;

            // ─────────────────────────────────────────────────────────────────
            // ABORT: Highest priority — return to IDLE from any state
            // ─────────────────────────────────────────────────────────────────
            if (sys_abort) begin
                state   <= `MAIN_STATE_IDLE;
                busy    <= 1'b0;
                status  <= `SYS_STATUS_IDLE;
                ber_cnt <= 7'd0;

            end else begin

                case (state)

                    // =========================================================
                    // IDLE: Wait for sys_start rising edge (BUG FIX P1)
                    //
                    // TRIGGER: sys_start_pulse (rising edge of sys_start)
                    //   NOT the raw sys_start level signal.
                    //
                    // WHY EDGE DETECTION:
                    //   sys_start = test_active from ctrl_register_bank, which
                    //   is a sustained HIGH level for the entire sweep duration.
                    //   Using raw level would cause the FSM to re-trigger
                    //   immediately after FINISH→IDLE if test_active is still
                    //   HIGH (race condition with ctrl_register_bank clearing it).
                    //
                    //   With edge detection:
                    //   - First cfg_update_pulse: test_active 0→1 → sys_start_pulse=1
                    //     → FSM starts sweep ✓
                    //   - During sweep: sys_start stays HIGH, no new edge → no re-trigger ✓
                    //   - After sweep (FINISH→IDLE): test_active already cleared by
                    //     ctrl_register_bank (test_done_flag), so sys_start=0 at IDLE
                    //     → no re-trigger ✓
                    //   - New sweep: user sends new cfg_update_pulse → test_active 0→1
                    //     → new rising edge → sys_start_pulse=1 → FSM starts again ✓
                    // =========================================================
                    `MAIN_STATE_IDLE: begin
                        busy   <= 1'b0;
                        status <= `SYS_STATUS_IDLE;

                        if (sys_start_pulse) begin  // FIX P1: edge-triggered, not level
                            ber_cnt     <= 7'd0;
                            trial_cnt   <= 32'd0;
                            busy        <= 1'b1;
                            status      <= `SYS_STATUS_TESTING;
                            // v2.0: clear accumulators at sweep start
                            acc_success <= 32'd0;
                            acc_fail    <= 32'd0;
                            acc_flip    <= 32'd0;
                            acc_clk     <= 64'd0;
                            state       <= `MAIN_STATE_INIT_CFG;
                        end
                    end

                    // =========================================================
                    // INIT_CFG: Request threshold from ROM for current BER point
                    //   - Assert rom_req for one cycle
                    //   - Wait for thresh_valid (ROM has 1-cycle BRAM latency)
                    // =========================================================
                    `MAIN_STATE_INIT_CFG: begin
                        rom_req <= 1'b1; // Request ROM lookup

                        if (thresh_valid) begin
                            // Threshold is ready → start the test engine
                            rom_req   <= 1'b0;
                            eng_start <= 1'b1;
                            state     <= `MAIN_STATE_RUN_TEST;
                        end
                    end

                    // =========================================================
                    // RUN_TEST: Wait for auto_scan_engine to complete one trial
                    //   - eng_start was pulsed in INIT_CFG
                    //   - Wait for eng_done
                    //   - Latch results
                    // =========================================================
                    `MAIN_STATE_RUN_TEST: begin
                        if (eng_done) begin
                            // Latch engine outputs (kept for debug/LED use)
                            res_pass_latch     <= eng_result_pass;
                            res_latency_latch  <= eng_latency;
                            res_injected_latch <= eng_was_injected;
                            res_flip_a_latch   <= eng_flip_a;
                            res_flip_b_latch   <= eng_flip_b;
                            res_uncorr_latch   <= eng_uncorr_cnt;

                            // v2.0: Accumulate statistics for this BER point
                            if (eng_result_pass)
                                acc_success <= acc_success + 32'd1;
                            else
                                acc_fail    <= acc_fail + 32'd1;

                            acc_flip <= acc_flip + {26'd0, eng_flip_a} + {26'd0, eng_flip_b};
                            acc_clk  <= acc_clk + {56'd0, eng_latency};

                            // v2.0: Check if we've completed all N trials for this point
                            if (trial_cnt + 32'd1 >= sample_count) begin
                                // All N trials done → save accumulated stats
                                trial_cnt <= 32'd0;
                                state     <= `MAIN_STATE_SAVE_RES;
                            end else begin
                                // More trials needed → run another trial
                                trial_cnt <= trial_cnt + 32'd1;
                                eng_start <= 1'b1; // Immediately start next trial
                                // Stay in RUN_TEST state
                            end
                        end
                    end

                    // =========================================================
                    // SAVE_RES: Write 176-bit accumulated stats to mem_stats_array
                    //   - Write address = ber_cnt (direct, 0~90)
                    //   - packed_stats is combinationally assembled from accumulators
                    //   - Assert mem_we_a for one cycle
                    // =========================================================
                    `MAIN_STATE_SAVE_RES: begin
                        mem_we_a      <= 1'b1;
                        mem_wr_addr_a <= ber_cnt;
                        mem_din_a     <= packed_stats; // 176-bit from accumulators

                        state <= `MAIN_STATE_NEXT_ITER;
                    end

                    // =========================================================
                    // NEXT_ITER: Increment BER counter, check loop termination
                    //   - If ber_cnt + 1 >= NUM_BER_POINTS (91) → all done
                    //   - Otherwise → loop back to INIT_CFG
                    // =========================================================
                    `MAIN_STATE_NEXT_ITER: begin
                        if (ber_cnt >= (`NUM_BER_POINTS - 1)) begin
                            // All 91 BER points tested → prepare upload
                            state <= `MAIN_STATE_PREP_UPLOAD;
                        end else begin
                            // More BER points to test → increment, clear accumulators
                            ber_cnt     <= ber_cnt + 1'b1;
                            trial_cnt   <= 32'd0;
                            acc_success <= 32'd0;
                            acc_fail    <= 32'd0;
                            acc_flip    <= 32'd0;
                            acc_clk     <= 64'd0;
                            state       <= `MAIN_STATE_INIT_CFG;
                        end
                    end

                    // =========================================================
                    // PREP_UPLOAD: All 91 tests complete, prepare for upload
                    //   - Update status to UPLOADING
                    //   - tx_packet_assembler will read from addr 0, 91 entries
                    //   - Start the assembler
                    // =========================================================
                    `MAIN_STATE_PREP_UPLOAD: begin
                        status    <= `SYS_STATUS_UPLOADING;
                        asm_start <= 1'b1; // Trigger packet assembler
                        state     <= `MAIN_STATE_DO_UPLOAD;
                    end

                    // =========================================================
                    // DO_UPLOAD: Wait for tx_packet_assembler to finish
                    //   - asm_start was pulsed in PREP_UPLOAD
                    //   - tx_packet_assembler reads 91 entries from addr 0
                    //     and sends them via UART (auto-packetized)
                    //   - Wait for asm_done
                    // =========================================================
                    `MAIN_STATE_DO_UPLOAD: begin
                        if (asm_done) begin
                            state <= `MAIN_STATE_FINISH;
                        end
                        // else: hold status = UPLOADING, wait for assembler
                    end

                    // =========================================================
                    // FINISH: Assert done pulse, update status, return to IDLE
                    // =========================================================
                    `MAIN_STATE_FINISH: begin
                        done   <= 1'b1; // Single-cycle done pulse
                        busy   <= 1'b0;
                        status <= `SYS_STATUS_DONE;
                        state  <= `MAIN_STATE_IDLE;
                    end

                    // =========================================================
                    // Default: Safety catch-all
                    // =========================================================
                    default: begin
                        state  <= `MAIN_STATE_IDLE;
                        busy   <= 1'b0;
                        status <= `SYS_STATUS_IDLE;
                    end

                endcase
            end
        end
    end

endmodule
