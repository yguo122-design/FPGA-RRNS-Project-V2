// =============================================================================
// File: auto_scan_engine.v
// Description: Auto Scan Engine - Single-Test Pipeline Orchestrator
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.5 (Green Block)
// Version: v1.1 (Single-Channel Mode: Channel B fully disabled)
//
// ─────────────────────────────────────────────────────────────────────────────
// PIPELINE OVERVIEW (Single-Channel Mode):
//   This module orchestrates one complete test trial using Channel A only:
//
//   [PRBS Gen] → [Encoder] → [Error Injector A] → [Decoder A] → [Comparator A]
//
//   Symbol_A = prbs_out[15:0]  (lower 16 bits, single-channel mode)
//   Channel B instances are retained in code but fully commented out.
//   result_pass is determined solely by comp_result_a.
//
// SINGLE-CHANNEL CHANGES (v1.1):
//   1. sym_a_latch = prbs_out[15:0]  (was prbs_out[31:16])
//   2. sym_b_latch = 16'd0           (constant, not used)
//   3. u_inj_b, u_dec_b, u_comp_b instances commented out
//   4. result_pass = comp_result_a   (was comp_result_a && comp_result_b)
//   5. flip_count_b = 6'd0           (constant)
//   6. DEC_WAIT: wait for dec_valid_a only (was dec_valid_a && dec_valid_b)
//   7. uncorr_cnt = {1'b0, dec_uncorr_a} (was {dec_uncorr_b, dec_uncorr_a})
//
// INJECTION DECISION:
//   The engine contains an internal 32-bit LFSR for injection probability.
//   At the start of each trial, the LFSR is compared against threshold_val:
//     lfsr_val < threshold_val → inject_en = 1 (inject error)
//     lfsr_val >= threshold_val → inject_en = 0 (pass through)
//
// FSM STATES (per auto_scan_engine.vh):
//   IDLE → CONFIG → GEN_WAIT → ENC_WAIT → INJ_WAIT → DEC_WAIT → COMP_WAIT → DONE
//
// PIPELINE LATENCY:
//   encoder_wrapper:     6 cycles (v2.4 single-channel)
//   error_injector_unit: 2 cycles (registered output, 2-cycle pipeline)
//   decoder_wrapper:     ~12 cycles (decoder_2nrm v2.29 pipeline)
//   result_comparator:   1 cycle (registered comparison)
//   Total: ~39 cycles per trial (matches observed Clk_Count/trial = 39)
// =============================================================================

`include "auto_scan_engine.vh"
`include "prbs_generator.vh"
`include "error_injector_unit.vh"
`include "result_comparator.vh"
`timescale 1ns / 1ps

module auto_scan_engine (
    // -------------------------------------------------------------------------
    // Global Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Control Interface (From Main Scan FSM)
    // -------------------------------------------------------------------------
    input  wire        start,
    input  wire [1:0]  algo_id,
    input  wire [31:0] threshold_val,
    input  wire [3:0]  burst_len,
    input  wire [31:0] seed_in,
    input  wire        load_seed,

    // -------------------------------------------------------------------------
    // Status Outputs
    // -------------------------------------------------------------------------
    output wire        busy,
    output reg         done,
    output reg         result_pass,
    output reg  [7:0]  latency_cycles,
    output reg         was_injected,
    output reg  [5:0]  flip_count_a,
    output reg  [5:0]  flip_count_b,   // Always 6'd0 in single-channel mode
    output reg  [1:0]  uncorr_cnt
);

    // =========================================================================
    // 1. FSM State Register
    // =========================================================================
    reg [2:0] state;
    assign busy = (state != `ENG_STATE_IDLE);

    // =========================================================================
    // 1b. Watchdog Timeout Counter
    // =========================================================================
    localparam WATCHDOG_CYCLES = 14'd10000; // 100 μs @ 100 MHz (200 μs @ 50 MHz)

    reg  [13:0] watchdog_cnt;
    reg         dec_timeout_flag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            watchdog_cnt     <= 14'd0;
            dec_timeout_flag <= 1'b0;
        end else begin
            if (state == `ENG_STATE_IDLE || state == `ENG_STATE_DONE) begin
                watchdog_cnt     <= 14'd0;
                dec_timeout_flag <= 1'b0;
            end else if (watchdog_cnt < WATCHDOG_CYCLES) begin
                watchdog_cnt <= watchdog_cnt + 14'd1;
            end else begin
                dec_timeout_flag <= 1'b1;
            end
        end
    end

    // =========================================================================
    // 2. Internal LFSR for Injection Probability Decision
    // =========================================================================
    reg  [31:0] inj_lfsr;
    wire [31:0] inj_lfsr_next;
    wire        inj_fb;

    assign inj_fb = inj_lfsr[0];
    assign inj_lfsr_next = {
        inj_fb,
        inj_lfsr[31:23],
        inj_lfsr[22] ^ inj_fb,
        inj_lfsr[21:3],
        inj_lfsr[2]  ^ inj_fb,
        inj_lfsr[1]  ^ inj_fb
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) inj_lfsr <= 32'hDEADBEEF;
        else        inj_lfsr <= inj_lfsr_next;
    end

    reg inject_en_latch;

    // =========================================================================
    // 3. PRBS Generator Instance
    // =========================================================================
    wire [31:0] prbs_out;
    wire        prbs_valid;
    reg         prbs_start_gen;

    prbs_generator u_prbs (
        .clk       (clk),
        .rst_n     (rst_n),
        .load_seed (load_seed),
        .seed_in   (seed_in),
        .start_gen (prbs_start_gen),
        .prbs_out  (prbs_out),
        .prbs_valid(prbs_valid)
    );

    // Symbol A: lower 16 bits (single-channel mode)
    (* max_fanout = 8 *) reg [15:0] sym_a_latch;
    // Symbol B: not used in single-channel mode (kept for encoder_wrapper interface)
    (* max_fanout = 4 *) reg [15:0] sym_b_latch;  // Always 16'd0

    // =========================================================================
    // 4. Encoder Wrapper Instance
    // =========================================================================
    reg         enc_start;
    wire [255:0] codeword_a_raw;
    wire [255:0] codeword_b_raw;  // Not used (codeword_B = 256'd0 from encoder_wrapper)
    wire [7:0]   cw_len_a;
    wire [7:0]   cw_len_b;        // Not used
    wire         enc_done;

    encoder_wrapper u_enc (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (enc_start),
        .algo_sel  (algo_id),
        .data_in_A (sym_a_latch),
        .data_in_B (sym_b_latch),   // Always 16'd0 (single-channel)
        .codeword_A(codeword_a_raw),
        .codeword_B(codeword_b_raw),
        .cw_len_A  (cw_len_a),
        .cw_len_B  (cw_len_b),
        .done      (enc_done)
    );

    reg [63:0] enc_out_a_latch;
    // reg [63:0] enc_out_b_latch;  // SINGLE-CHANNEL: disabled
    reg [7:0]  cw_len_latch;
    reg        enc_done_d1;

    // BUG FIX #33: 2-bit counter for INJ_WAIT state
    reg [1:0]  inj_wait_cnt;

    // =========================================================================
    // 5. Error Injector Unit - Channel A only
    // =========================================================================
    wire [63:0] inj_out_a;
    wire [5:0]  inj_flip_a;
    // wire [63:0] inj_out_b;   // SINGLE-CHANNEL: disabled
    // wire [5:0]  inj_flip_b;  // SINGLE-CHANNEL: disabled

    error_injector_unit u_inj_a (
        .clk          (clk),
        .rst_n        (rst_n),
        .inject_en    (inject_en_latch),
        .algo_id      (algo_id),
        .burst_len    (burst_len),
        .random_offset(inj_lfsr[5:0]),
        .data_in      (enc_out_a_latch),
        .data_out     (inj_out_a),
        .flip_count   (inj_flip_a)
    );

    // Channel B injector - SINGLE-CHANNEL: disabled
    // error_injector_unit u_inj_b (
    //     .clk          (clk),
    //     .rst_n        (rst_n),
    //     .inject_en    (inject_en_latch),
    //     .algo_id      (algo_id),
    //     .burst_len    (burst_len),
    //     .random_offset(inj_lfsr[11:6]),
    //     .data_in      (enc_out_b_latch),
    //     .data_out     (inj_out_b),
    //     .flip_count   (inj_flip_b)
    // );

    // =========================================================================
    // 6. Decoder Wrapper - Channel A only
    // =========================================================================
    reg         dec_start;
    wire [15:0] dec_out_a;
    wire        dec_valid_a;
    wire        dec_uncorr_a;
    // wire [15:0] dec_out_b;    // SINGLE-CHANNEL: disabled
    // wire        dec_valid_b;  // SINGLE-CHANNEL: disabled
    // wire        dec_uncorr_b; // SINGLE-CHANNEL: disabled

    reg [63:0] inj_out_a_latch;
    // reg [63:0] inj_out_b_latch;  // SINGLE-CHANNEL: disabled

    decoder_wrapper u_dec_a (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (dec_start),
        .algo_id      (algo_id),
        .residues_in  (inj_out_a_latch),
        .data_out     (dec_out_a),
        .valid        (dec_valid_a),
        .uncorrectable(dec_uncorr_a)
    );

    // Channel B decoder - SINGLE-CHANNEL: disabled
    // decoder_wrapper u_dec_b (
    //     .clk          (clk),
    //     .rst_n        (rst_n),
    //     .start        (dec_start),
    //     .algo_id      (algo_id),
    //     .residues_in  (inj_out_b_latch),
    //     .data_out     (dec_out_b),
    //     .valid        (dec_valid_b),
    //     .uncorrectable(dec_uncorr_b)
    // );

    // =========================================================================
    // 7. Result Comparator - Channel A only
    // =========================================================================
    reg         comp_start_sent;
    reg         comp_start;
    wire        comp_result_a;
    wire [7:0]  comp_latency_a;
    wire        comp_ready_a;
    // wire        comp_result_b;    // SINGLE-CHANNEL: disabled
    // wire [7:0]  comp_latency_b;   // SINGLE-CHANNEL: disabled
    // wire        comp_ready_b;     // SINGLE-CHANNEL: disabled

    result_comparator u_comp_a (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (comp_start),
        .data_orig      (sym_a_latch),
        .valid_in       (dec_valid_a),
        .data_recov     (dec_out_a),
        .test_result    (comp_result_a),
        .current_latency(comp_latency_a),
        .ready          (comp_ready_a)
    );

    // Channel B comparator - SINGLE-CHANNEL: disabled
    // result_comparator u_comp_b (
    //     .clk            (clk),
    //     .rst_n          (rst_n),
    //     .start          (comp_start),
    //     .data_orig      (sym_b_latch),
    //     .valid_in       (dec_valid_b),
    //     .data_recov     (dec_out_b),
    //     .test_result    (comp_result_b),
    //     .current_latency(comp_latency_b),
    //     .ready          (comp_ready_b)
    // );

    // =========================================================================
    // 8. Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= `ENG_STATE_IDLE;
            done             <= 1'b0;
            result_pass      <= 1'b0;
            latency_cycles   <= 8'd0;
            was_injected     <= 1'b0;
            flip_count_a     <= 6'd0;
            flip_count_b     <= 6'd0;   // Always 0 in single-channel mode
            uncorr_cnt       <= 2'b00;
            inject_en_latch  <= 1'b0;
            enc_start        <= 1'b0;
            dec_start        <= 1'b0;
            comp_start       <= 1'b0;
            comp_start_sent  <= 1'b0;
            prbs_start_gen   <= 1'b0;
            sym_a_latch      <= 16'd0;
            sym_b_latch      <= 16'd0;
            enc_out_a_latch  <= 64'd0;
            // enc_out_b_latch  <= 64'd0;  // SINGLE-CHANNEL: disabled
            cw_len_latch     <= 8'd0;
            enc_done_d1      <= 1'b0;
            inj_wait_cnt     <= 2'd0;
            inj_out_a_latch  <= 64'd0;
            // inj_out_b_latch  <= 64'd0;  // SINGLE-CHANNEL: disabled

        end else begin
            // Default: deassert single-cycle control signals
            done           <= 1'b0;
            enc_start      <= 1'b0;
            dec_start      <= 1'b0;
            comp_start     <= 1'b0;
            prbs_start_gen <= 1'b0;

            case (state)

                // =============================================================
                // IDLE: Wait for start pulse
                // =============================================================
                `ENG_STATE_IDLE: begin
                    if (start) begin
                        state <= `ENG_STATE_CONFIG;
                    end
                end

                // =============================================================
                // CONFIG: Latch parameters, make injection decision
                // =============================================================
                `ENG_STATE_CONFIG: begin
                    inject_en_latch <= (inj_lfsr < threshold_val);
                    prbs_start_gen  <= 1'b1;
                    state           <= `ENG_STATE_GEN_WAIT;
                end

                // =============================================================
                // GEN_WAIT: Wait for PRBS generator to produce valid output
                //   Single-channel mode: sym_a_latch = prbs_out[15:0] (lower 16 bits)
                //   sym_b_latch = 16'd0 (not used)
                // =============================================================
                `ENG_STATE_GEN_WAIT: begin
                    if (dec_timeout_flag) begin
                        result_pass <= 1'b0;
                        state       <= `ENG_STATE_DONE;
                    end else if (prbs_valid) begin
                        // Single-channel mode: only use lower 16 bits for Symbol A
                        sym_a_latch     <= prbs_out[15:0];  // Symbol A = lower 16 bits
                        sym_b_latch     <= 16'd0;           // Symbol B = unused (single-channel)
                        comp_start_sent <= 1'b0;
                        enc_start       <= 1'b1;
                        state           <= `ENG_STATE_ENC_WAIT;
                    end
                end

                // =============================================================
                // ENC_WAIT: Wait for encoder to finish
                //   BUG FIX: encoder_wrapper latches codeword_A on enc_done=1 via NBA,
                //   so codeword_A is only valid one cycle AFTER enc_done=1.
                //   enc_done_d1 aligns the latch point with the valid codeword data.
                // =============================================================
                `ENG_STATE_ENC_WAIT: begin
                    if (dec_timeout_flag) begin
                        result_pass <= 1'b0;
                        enc_done_d1 <= 1'b0;
                        state       <= `ENG_STATE_DONE;
                    end else begin
                        if (!comp_start_sent) begin
                            comp_start      <= 1'b1;
                            comp_start_sent <= 1'b1;
                        end

                        enc_done_d1 <= enc_done;

                        if (enc_done_d1) begin
                            enc_out_a_latch <= codeword_a_raw[63:0];
                            // enc_out_b_latch <= codeword_b_raw[63:0];  // SINGLE-CHANNEL: disabled
                            cw_len_latch    <= cw_len_a;
                            enc_done_d1     <= 1'b0;
                            state           <= `ENG_STATE_INJ_WAIT;
                        end
                    end
                end

                // =============================================================
                // INJ_WAIT: Wait for error injector to produce output
                //   BUG FIX #33: 2-cycle pipeline latency, use 3-cycle counter
                // =============================================================
                `ENG_STATE_INJ_WAIT: begin
                    if (dec_timeout_flag) begin
                        result_pass  <= 1'b0;
                        inj_wait_cnt <= 2'd0;
                        state        <= `ENG_STATE_DONE;
                    end else if (inj_wait_cnt < 2'd2) begin
                        inj_wait_cnt <= inj_wait_cnt + 2'd1;
                    end else begin
                        // Cycle 2: inj_out_a is now valid
                        inj_out_a_latch <= inj_out_a;
                        // inj_out_b_latch <= inj_out_b;  // SINGLE-CHANNEL: disabled
                        inj_wait_cnt    <= 2'd0;

                        // Record injection metadata (Channel A only)
                        // flip_count_b is not assigned here in single-channel mode.
                        // It is held at its reset value (6'd0) by the reset block above.
                        was_injected <= inject_en_latch;
                        flip_count_a <= inj_flip_a;
                        // flip_count_b <= inj_flip_b;  // SINGLE-CHANNEL: Channel B disabled

                        dec_start <= 1'b1;
                        state     <= `ENG_STATE_DEC_WAIT;
                    end
                end

                // =============================================================
                // DEC_WAIT: Wait for Channel A decoder to produce valid output
                //   Single-channel mode: only wait for dec_valid_a
                //   (was: dec_valid_a && dec_valid_b)
                // =============================================================
                `ENG_STATE_DEC_WAIT: begin
                    if (dec_valid_a) begin
                        // Channel A decoder has produced output → move to COMP_WAIT
                        state <= `ENG_STATE_COMP_WAIT;
                    end else if (dec_timeout_flag) begin
                        result_pass <= 1'b0;
                        state       <= `ENG_STATE_DONE;
                    end
                end

                // =============================================================
                // COMP_WAIT: Wait for comparator to register its result
                //   Single-channel mode: result_pass = comp_result_a only
                //   uncorr_cnt = {1'b0, dec_uncorr_a} (Channel B always 0)
                // =============================================================
                `ENG_STATE_COMP_WAIT: begin
                    if (dec_timeout_flag) begin
                        result_pass <= 1'b0;
                        uncorr_cnt  <= 2'b00;
                        state       <= `ENG_STATE_DONE;
                    end else begin
                        // Single-channel mode: only Channel A result determines PASS/FAIL
                        result_pass    <= comp_result_a;
                        latency_cycles <= comp_latency_a;

                        // uncorr_cnt[0] = Channel A uncorrectable
                        // uncorr_cnt[1] = Channel B uncorrectable (always 0 in single-channel)
                        uncorr_cnt <= {1'b0, dec_uncorr_a};  // SINGLE-CHANNEL: B always 0

                        state <= `ENG_STATE_DONE;
                    end
                end

                // =============================================================
                // DONE: Pulse done signal, return to IDLE
                // =============================================================
                `ENG_STATE_DONE: begin
                    done  <= 1'b1;
                    state <= `ENG_STATE_IDLE;
                end

                default: begin
                    state <= `ENG_STATE_IDLE;
                end

            endcase
        end
    end

endmodule
