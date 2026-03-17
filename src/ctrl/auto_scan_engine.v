// =============================================================================
// File: auto_scan_engine.v
// Description: Auto Scan Engine - Single-Test Pipeline Orchestrator
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.5 (Green Block)
// Version: v1.0
//
// ─────────────────────────────────────────────────────────────────────────────
// PIPELINE OVERVIEW:
//   This module orchestrates one complete test trial:
//
//   [PRBS Gen] → [Encoder] → [Error Injector] → [Decoder] → [Comparator]
//
//   For each trial, TWO 16-bit symbols (A and B) are processed in parallel:
//     Symbol_A = prbs_out[31:16]
//     Symbol_B = prbs_out[15:0]
//   Each symbol goes through its own encode→inject→decode→compare pipeline.
//   The engine reports PASS only if BOTH channels pass.
//
// INJECTION DECISION:
//   The engine contains an internal 32-bit LFSR for injection probability.
//   At the start of each trial, the LFSR is compared against threshold_val:
//     lfsr_val < threshold_val → inject_en = 1 (inject error)
//     lfsr_val >= threshold_val → inject_en = 0 (pass through)
//   This implements the BER probability model from Section 2.3.2.4.
//
// FSM STATES (per auto_scan_engine.vh):
//   IDLE → CONFIG → GEN_WAIT → ENC_WAIT → INJ_WAIT → DEC_WAIT → COMP_WAIT → DONE
//
// PIPELINE LATENCY:
//   encoder_wrapper:    1 cycle (registered output on start)
//   error_injector_unit: 1 cycle (registered output)
//   decoder_wrapper:    9 cycles (decoder_2nrm v2.3: 1 input reg + 7-stage channel + 1 MLD reg)
//                       [v2.3 timing fix: was 8 cycles (v2.2), Stage 1d further split into
//                        1d (coeff_mod only) + 1e (x_cand multiply+add only).
//                        Added (* dont_touch="true" *) to all pipeline regs (1a/1b/1c/1d/1e)
//                        to prevent Vivado from merging stages back.
//                        Added set_max_fanout=4 in top.xdc for diff_mod_s1b/coeff_raw_s1c/
//                        coeff_mod_s1d registers to force replication and reduce Net Delay.
//                        Resolves WNS=-8.5ns.]
//   result_comparator:  1 cycle (registered comparison)
//   Total: ~12 cycles per trial
//   NOTE: DEC_WAIT state uses dec_valid polling, so this change is transparent.
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
    // start: Single-cycle pulse to begin one test trial.
    // Ignored if busy=1.

    input  wire [1:0]  algo_id,
    // algo_id: Algorithm selector (0=2NRM, 1=3NRM, 2=C-RRNS, 3=RS).

    input  wire [31:0] threshold_val,
    // threshold_val: 32-bit injection probability threshold from ROM.
    // If internal LFSR < threshold_val → inject error.

    input  wire [3:0]  burst_len,
    // burst_len: Error burst length (1~15) for error injector.

    input  wire [31:0] seed_in,
    // seed_in: Seed for PRBS generator (from seed_lock_unit).

    input  wire        load_seed,
    // load_seed: Pulse to load seed_in into PRBS LFSR.

    // -------------------------------------------------------------------------
    // Status Outputs
    // -------------------------------------------------------------------------
    output wire        busy,
    // busy: HIGH when engine is not in IDLE state.

    output reg         done,
    // done: Single-cycle pulse when trial is complete.

    output reg         result_pass,
    // result_pass: 1=PASS (both channels), 0=FAIL (either channel failed).

    output reg  [7:0]  latency_cycles,
    // latency_cycles: Measured pipeline latency from encoder start to decoder valid.

    output reg         was_injected,
    // was_injected: HIGH if error injection occurred in this trial.

    output reg  [5:0]  flip_count_a,
    // flip_count_a: Number of bits flipped in channel A (0 if no injection).

    output reg  [5:0]  flip_count_b,
    // flip_count_b: Number of bits flipped in channel B (0 if no injection).

    output reg  [1:0]  uncorr_cnt
    // uncorr_cnt: Uncorrectable error indicator for this trial (BUG FIX P3).
    //   Bit[1]: Channel B had uncorrectable error (dec_uncorr_b=1 when dec_valid_b=1)
    //   Bit[0]: Channel A had uncorrectable error (dec_uncorr_a=1 when dec_valid_a=1)
    //   Encoding:
    //     2'b00 = Both channels correctable (or no injection)
    //     2'b01 = Channel A uncorrectable only
    //     2'b10 = Channel B uncorrectable only
    //     2'b11 = Both channels uncorrectable (catastrophic)
    //   This field is non-zero ONLY when the decoder explicitly signals it
    //   cannot recover the original data. Distinguishes "ECC correction failure"
    //   from "system/pipeline error" at the BER analysis stage.
);

    // =========================================================================
    // 1. FSM State Register
    // =========================================================================
    reg [2:0] state;
    assign busy = (state != `ENG_STATE_IDLE);

    // =========================================================================
    // 1b. Watchdog Timeout Counter (BUG FIX P4)
    // =========================================================================
    // PURPOSE: Prevent permanent deadlock when any sub-module (decoder, encoder,
    //          PRBS generator) fails to assert its "done/valid" signal.
    //
    // DESIGN:
    //   - Counter runs freely whenever FSM is NOT in IDLE or DONE state.
    //   - Threshold: WATCHDOG_CYCLES = 10,000 cycles = 100 μs @ 100 MHz.
    //     This is far larger than the normal pipeline latency (~9 cycles),
    //     so no false timeouts will occur under normal operation.
    //   - On timeout: dec_timeout_flag is latched HIGH, FSM is forced to
    //     DONE state with result_pass=0 (FAIL), allowing the sweep to continue.
    //   - dec_timeout_flag is cleared on the next IDLE→CONFIG transition
    //     (i.e., at the start of the next test trial).
    //   - The flag is also exported as an output for ILA/LED debug visibility.
    //
    // STATES PROTECTED: GEN_WAIT, ENC_WAIT, INJ_WAIT, DEC_WAIT, COMP_WAIT
    //   (All non-IDLE, non-DONE states where a sub-module could stall.)

    localparam WATCHDOG_CYCLES = 14'd10000; // 100 μs @ 100 MHz

    reg  [13:0] watchdog_cnt;   // 14-bit counter: max 16383, covers 10000
    reg         dec_timeout_flag; // Latched HIGH on timeout, cleared at next trial start

    // =========================================================================
    // 2. Internal LFSR for Injection Probability Decision
    // =========================================================================
    // 32-bit Galois LFSR, polynomial x^32+x^22+x^2+x+1
    // Advances every clock cycle (free-running for maximum randomness).
    // Compared against threshold_val to decide whether to inject.
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

    // Injection decision: latched at CONFIG state
    reg inject_en_latch; // Whether to inject in this trial

    // =========================================================================
    // 3. PRBS Generator Instance
    // =========================================================================
    // TODO: Replace with full prbs_generator module when integrated
    // For now, uses a simple 32-bit counter as test vector source.
    // Symbol_A = prbs_out[31:16], Symbol_B = prbs_out[15:0]

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

    // Latched PRBS output (stable for downstream pipeline)
    reg [15:0] sym_a_latch; // Symbol A = prbs_out[31:16]
    reg [15:0] sym_b_latch; // Symbol B = prbs_out[15:0]

    // =========================================================================
    // 4. Encoder Wrapper Instance
    // =========================================================================
    reg         enc_start;
    wire [255:0] codeword_a_raw;
    wire [255:0] codeword_b_raw;
    wire [7:0]   cw_len_a;
    wire [7:0]   cw_len_b;
    wire         enc_done;

    encoder_wrapper u_enc (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (enc_start),
        .algo_sel  (algo_id),
        .data_in_A (sym_a_latch),
        .data_in_B (sym_b_latch),
        .codeword_A(codeword_a_raw),
        .codeword_B(codeword_b_raw),
        .cw_len_A  (cw_len_a),
        .cw_len_B  (cw_len_b),
        .done      (enc_done)
    );

    // Latch encoder output (lower 64 bits contain the packed residues)
    reg [63:0] enc_out_a_latch;
    reg [63:0] enc_out_b_latch;
    reg [7:0]  cw_len_latch;

    // =========================================================================
    // 5. Error Injector Unit Instances (Channel A and Channel B)
    // =========================================================================
    // The error_injector_unit uses ROM-based patterns.
    // random_offset: lower 6 bits of inj_lfsr (provides random position).
    // inject_en: controlled by injection decision (LFSR vs threshold).

    wire [63:0] inj_out_a;
    wire [63:0] inj_out_b;
    wire [5:0]  inj_flip_a;
    wire [5:0]  inj_flip_b;

    error_injector_unit u_inj_a (
        .clk          (clk),
        .rst_n        (rst_n),
        .inject_en    (inject_en_latch),
        .algo_id      (algo_id),
        .burst_len    (burst_len),
        .random_offset(inj_lfsr[5:0]),   // Lower 6 bits for channel A offset
        .data_in      (enc_out_a_latch),
        .data_out     (inj_out_a),
        .flip_count   (inj_flip_a)
    );

    error_injector_unit u_inj_b (
        .clk          (clk),
        .rst_n        (rst_n),
        .inject_en    (inject_en_latch),
        .algo_id      (algo_id),
        .burst_len    (burst_len),
        .random_offset(inj_lfsr[11:6]),  // Bits [11:6] for channel B offset (independent)
        .data_in      (enc_out_b_latch),
        .data_out     (inj_out_b),
        .flip_count   (inj_flip_b)
    );

    // =========================================================================
    // 6. Decoder Wrapper Instances (Channel A and Channel B)
    // =========================================================================
    reg         dec_start;
    wire [15:0] dec_out_a;
    wire [15:0] dec_out_b;
    wire        dec_valid_a;
    wire        dec_valid_b;
    wire        dec_uncorr_a;
    wire        dec_uncorr_b;

    // Latched injector output (stable for decoder input)
    reg [63:0] inj_out_a_latch;
    reg [63:0] inj_out_b_latch;

    decoder_wrapper u_dec_a (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (dec_start),
        .algo_id      (algo_id),
        .residues_in  (inj_out_a_latch), // 64-bit direct connection (matches DEC_INPUT_BUS_WIDTH=64)
        .data_out     (dec_out_a),
        .valid        (dec_valid_a),
        .uncorrectable(dec_uncorr_a)
    );

    decoder_wrapper u_dec_b (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (dec_start),
        .algo_id      (algo_id),
        .residues_in  (inj_out_b_latch), // 64-bit direct connection (matches DEC_INPUT_BUS_WIDTH=64)
        .data_out     (dec_out_b),
        .valid        (dec_valid_b),
        .uncorrectable(dec_uncorr_b)
    );

    // =========================================================================
    // 7. Result Comparator Instances (Channel A and Channel B)
    // =========================================================================
    // comp_start_sent: flag to ensure comp_start is only pulsed once per trial,
    // in the first cycle of ENC_WAIT (after sym_a/b_latch have been registered).
    reg         comp_start_sent;
    reg         comp_start;
    wire        comp_result_a;
    wire        comp_result_b;
    wire [7:0]  comp_latency_a;
    wire [7:0]  comp_latency_b;
    wire        comp_ready_a;
    wire        comp_ready_b;

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

    result_comparator u_comp_b (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (comp_start),
        .data_orig      (sym_b_latch),
        .valid_in       (dec_valid_b),
        .data_recov     (dec_out_b),
        .test_result    (comp_result_b),
        .current_latency(comp_latency_b),
        .ready          (comp_ready_b)
    );

    // =========================================================================
    // 8. Watchdog Counter Sequential Logic (BUG FIX P4)
    // =========================================================================
    // Runs independently from the main FSM always block to avoid priority
    // conflicts. The counter is reset whenever the FSM is in IDLE or DONE
    // (safe states). It increments in all other states (CONFIG through COMP_WAIT).
    // When it reaches WATCHDOG_CYCLES, dec_timeout_flag is latched HIGH.
    //
    // The main FSM checks dec_timeout_flag in every waiting state and forces
    // a transition to ENG_STATE_DONE with result_pass=0 on timeout.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            watchdog_cnt     <= 14'd0;
            dec_timeout_flag <= 1'b0;
        end else begin
            if (state == `ENG_STATE_IDLE || state == `ENG_STATE_DONE) begin
                // Safe states: reset counter and clear flag for next trial
                watchdog_cnt     <= 14'd0;
                dec_timeout_flag <= 1'b0;
            end else if (watchdog_cnt < WATCHDOG_CYCLES) begin
                // Active states: increment counter
                watchdog_cnt <= watchdog_cnt + 14'd1;
            end else begin
                // Threshold reached: latch timeout flag
                // Flag stays HIGH until FSM returns to IDLE/DONE
                dec_timeout_flag <= 1'b1;
            end
        end
    end

    // =========================================================================
    // 9. Main FSM
    // =========================================================================
    // Pipeline timing (cycles after state entry):
    //   CONFIG:    1 cycle (latch params, decide injection)
    //   GEN_WAIT:  1 cycle (PRBS generates, prbs_valid=1)
    //   ENC_WAIT:  1 cycle (encoder_wrapper registered output, enc_done=1)
    //   INJ_WAIT:  1 cycle (error_injector_unit registered output)
    //   DEC_WAIT:  2 cycles (decoder_wrapper pipeline, dec_valid=1)
    //   COMP_WAIT: 1 cycle (result_comparator registered output)
    //   DONE:      1 cycle (latch results, pulse done)
    //
    // WATCHDOG INTEGRATION:
    //   Every waiting state (GEN_WAIT, ENC_WAIT, INJ_WAIT, DEC_WAIT, COMP_WAIT)
    //   checks dec_timeout_flag. On timeout, the FSM immediately forces:
    //     result_pass = 0 (FAIL — conservative, safe default)
    //     state       = ENG_STATE_DONE
    //   This allows main_scan_fsm to receive eng_done and continue the sweep,
    //   recording this BER point as a FAIL rather than hanging forever.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= `ENG_STATE_IDLE;
            done             <= 1'b0;
            result_pass      <= 1'b0;
            latency_cycles   <= 8'd0;
            was_injected     <= 1'b0;
            flip_count_a     <= 6'd0;
            flip_count_b     <= 6'd0;
            uncorr_cnt       <= 2'b00;  // FIX P3: initialize uncorr_cnt
            inject_en_latch  <= 1'b0;
            enc_start        <= 1'b0;
            dec_start        <= 1'b0;
            comp_start       <= 1'b0;
            comp_start_sent  <= 1'b0;
            prbs_start_gen   <= 1'b0;
            sym_a_latch      <= 16'd0;
            sym_b_latch      <= 16'd0;
            enc_out_a_latch  <= 64'd0;
            enc_out_b_latch  <= 64'd0;
            cw_len_latch     <= 8'd0;
            inj_out_a_latch  <= 64'd0;
            inj_out_b_latch  <= 64'd0;

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
                //   - Compare inj_lfsr against threshold_val
                //   - Kick off PRBS generation
                // =============================================================
                `ENG_STATE_CONFIG: begin
                    // Injection decision: inject if LFSR < threshold
                    inject_en_latch <= (inj_lfsr < threshold_val);

                    // Start PRBS generation (will be valid next cycle)
                    prbs_start_gen <= 1'b1;

                    state <= `ENG_STATE_GEN_WAIT;
                end

                // =============================================================
                // GEN_WAIT: Wait for PRBS generator to produce valid output
                //   - prbs_valid=1 indicates prbs_out is ready
                //   - Latch Symbol_A and Symbol_B into registers
                //   - Start encoder (encoder reads sym_a/b_latch next cycle)
                //   - NOTE: comp_start is NOT issued here because sym_a/b_latch
                //     are non-blocking assignments — they take effect NEXT cycle.
                //     comp_start is issued in ENC_WAIT (first cycle) instead.
                //   - WATCHDOG: if dec_timeout_flag=1, force FAIL and exit.
                // =============================================================
                `ENG_STATE_GEN_WAIT: begin
                    if (dec_timeout_flag) begin
                        // Watchdog triggered: PRBS generator stalled
                        result_pass <= 1'b0; // Record as FAIL
                        state       <= `ENG_STATE_DONE;
                    end else if (prbs_valid) begin
                        // Latch both symbols from PRBS output (effective next cycle)
                        sym_a_latch     <= prbs_out[31:16]; // Symbol A (upper 16 bits)
                        sym_b_latch     <= prbs_out[15:0];  // Symbol B (lower 16 bits)
                        comp_start_sent <= 1'b0;            // Arm the comp_start flag

                        // Start encoder (reads sym_a/b_latch which will be stable
                        // at the start of ENC_WAIT, one cycle from now)
                        enc_start <= 1'b1;

                        state <= `ENG_STATE_ENC_WAIT;
                    end
                end

                // =============================================================
                // ENC_WAIT: Wait for encoder to finish
                //   - First cycle: sym_a/b_latch are now stable (registered).
                //     Issue comp_start once to write original data into comparator.
                //   - enc_done=1 indicates codeword_A/B are valid
                //   - Latch encoder output (lower 64 bits = packed residues)
                //   - WATCHDOG: if dec_timeout_flag=1, force FAIL and exit.
                // =============================================================
                `ENG_STATE_ENC_WAIT: begin
                    if (dec_timeout_flag) begin
                        // Watchdog triggered: encoder stalled
                        result_pass <= 1'b0;
                        state       <= `ENG_STATE_DONE;
                    end else begin
                        // Issue comp_start in the FIRST cycle of ENC_WAIT only.
                        // At this point sym_a/b_latch are stable (latched in GEN_WAIT).
                        // comp_start_sent prevents re-triggering if enc_done takes >1 cycle.
                        if (!comp_start_sent) begin
                            comp_start      <= 1'b1;
                            comp_start_sent <= 1'b1;
                        end

                        if (enc_done) begin
                            // Latch encoder output (lower 64 bits contain packed residues)
                            enc_out_a_latch <= codeword_a_raw[63:0];
                            enc_out_b_latch <= codeword_b_raw[63:0];
                            cw_len_latch    <= cw_len_a; // Both channels same length

                            // Error injector will process on next cycle (registered)
                            state <= `ENG_STATE_INJ_WAIT;
                        end
                    end
                end

                // =============================================================
                // INJ_WAIT: Wait for error injector to produce output
                //   - error_injector_unit has 1-cycle registered latency
                //   - After 1 cycle, inj_out_a/b are valid
                //   - Latch injector output and start decoder
                //   - WATCHDOG: if dec_timeout_flag=1, force FAIL and exit.
                //     (Extremely unlikely here since injector is purely registered,
                //      but included for completeness.)
                // =============================================================
                `ENG_STATE_INJ_WAIT: begin
                    if (dec_timeout_flag) begin
                        // Watchdog triggered (unexpected)
                        result_pass <= 1'b0;
                        state       <= `ENG_STATE_DONE;
                    end else begin
                        // Injector output is valid this cycle (1-cycle latency from ENC_WAIT)
                        // Latch injector output for decoder input
                        inj_out_a_latch <= inj_out_a;
                        inj_out_b_latch <= inj_out_b;

                        // Record injection metadata
                        was_injected <= inject_en_latch;
                        flip_count_a <= inj_flip_a;
                        flip_count_b <= inj_flip_b;

                        // Start decoder with injected codewords
                        dec_start <= 1'b1;

                        state <= `ENG_STATE_DEC_WAIT;
                    end
                end

                // =============================================================
                // DEC_WAIT: Wait for decoder to produce valid output
                //   - decoder_wrapper (decoder_2nrm) has 2-cycle pipeline
                //   - Wait for dec_valid_a AND dec_valid_b
                //   - Comparator will automatically compare when valid_in=1
                //   - WATCHDOG: PRIMARY protection point.
                //     If dec_valid never arrives (decoder stall/bug), the
                //     watchdog fires after WATCHDOG_CYCLES (10,000 cycles =
                //     100 μs), forces result_pass=0, and exits to DONE.
                //     This prevents the entire BER sweep from hanging.
                // =============================================================
                `ENG_STATE_DEC_WAIT: begin
                    if (dec_valid_a && dec_valid_b) begin
                        // Both decoders have produced output.
                        // result_comparator automatically compares when valid_in=1.
                        // Move to COMP_WAIT to read the comparison result.
                        state <= `ENG_STATE_COMP_WAIT;
                    end else if (dec_timeout_flag) begin
                        // -------------------------------------------------------
                        // WATCHDOG TIMEOUT (BUG FIX P4):
                        //   Decoder did not respond within WATCHDOG_CYCLES.
                        //   Force FAIL result and exit to DONE state.
                        //   The main_scan_fsm will receive eng_done=1 on the
                        //   next cycle and record this BER point as FAIL,
                        //   then continue to the next BER point normally.
                        //   dec_timeout_flag will be cleared when FSM reaches
                        //   IDLE (via DONE → IDLE transition).
                        // -------------------------------------------------------
                        result_pass <= 1'b0; // Timeout = FAIL (conservative)
                        state       <= `ENG_STATE_DONE;
                    end
                end

                // =============================================================
                // COMP_WAIT: Wait for comparator to register its result
                //   - result_comparator registers test_result on valid_in edge
                //   - After dec_valid, comparator result is available next cycle
                //   - WATCHDOG: if dec_timeout_flag=1, force FAIL and exit.
                //     (Unlikely here since we just received dec_valid, but
                //      included for robustness.)
                // =============================================================
                `ENG_STATE_COMP_WAIT: begin
                    if (dec_timeout_flag) begin
                        // Watchdog triggered (unexpected in this state)
                        result_pass <= 1'b0;
                        uncorr_cnt  <= 2'b00; // Timeout: uncorr status unknown, report 0
                        state       <= `ENG_STATE_DONE;
                    end else begin
                        // Comparator result is now stable (registered on dec_valid edge)
                        // Both channels must pass for overall PASS
                        result_pass    <= comp_result_a && comp_result_b;
                        latency_cycles <= comp_latency_a; // Use channel A latency as reference

                        // -------------------------------------------------------
                        // BUG FIX P3: Capture dec_uncorr signals
                        // dec_uncorr_a/b are valid in the same cycle as dec_valid_a/b.
                        // We are now one cycle past DEC_WAIT (where dec_valid was seen),
                        // so we sample dec_uncorr here while the decoder output is still
                        // stable (decoder_wrapper holds outputs until next start pulse).
                        //
                        // uncorr_cnt encoding:
                        //   [1] = Channel B uncorrectable
                        //   [0] = Channel A uncorrectable
                        //
                        // DIAGNOSTIC VALUE:
                        //   result_pass=0, uncorr_cnt=2'b00 → comparator mismatch
                        //     (decoder produced wrong data but claimed correctable)
                        //   result_pass=0, uncorr_cnt≠2'b00 → ECC hard failure
                        //     (decoder explicitly flagged uncorrectable error)
                        //   result_pass=1, uncorr_cnt=2'b00 → clean pass
                        //   result_pass=1, uncorr_cnt≠2'b00 → impossible (decoder
                        //     should not output valid data when uncorrectable)
                        // -------------------------------------------------------
                        uncorr_cnt <= {dec_uncorr_b, dec_uncorr_a};

                        state <= `ENG_STATE_DONE;
                    end
                end

                // =============================================================
                // DONE: Pulse done signal, return to IDLE
                // =============================================================
                `ENG_STATE_DONE: begin
                    done  <= 1'b1; // Single-cycle done pulse
                    state <= `ENG_STATE_IDLE;
                end

                // =============================================================
                // Default: Safety catch-all
                // =============================================================
                default: begin
                    state <= `ENG_STATE_IDLE;
                end

            endcase
        end
    end

endmodule
