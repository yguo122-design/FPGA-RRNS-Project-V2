// =============================================================================
// File: auto_scan_engine.v
// Description: Auto Scan Engine - Single-Test Pipeline Orchestrator
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.5 (Green Block)
// Version: v1.2 (Multi-Bit Injection for Random Single Bit mode)
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
//   burst_len == 1 (Random Single Bit): Multi-bit Bernoulli scan mode.
//     For each bit position 0..(w_valid-1), the LFSR is advanced and compared
//     against threshold_val directly. If lfsr < threshold_val, that bit is
//     flipped. This allows actual BER to reach up to 100% without saturation.
//     ROM stores: threshold_val = BER_target * (2^32 - 1)  (no ×64 factor).
//     P(flip per bit) = threshold_val / (2^32 - 1) = BER_target  ✓
//
//   burst_len > 1 (Cluster Burst): Original single-injection ROM mode.
//     lfsr_val < threshold_val → inject_en = 1 (inject one burst)
//     lfsr_val >= threshold_val → inject_en = 0 (pass through)
//     Cluster mode is completely unchanged.
//
// FSM STATES (per auto_scan_engine.vh):
//   IDLE → CONFIG → GEN_WAIT → ENC_WAIT → INJ_WAIT → DEC_WAIT → COMP_WAIT → DONE
//   INJ_WAIT for burst_len=1: iterates w_valid times (bit-scan sub-loop)
//   INJ_WAIT for burst_len>1: original 2-cycle ROM pipeline wait
//
// PIPELINE LATENCY:
//   encoder_wrapper:     6 cycles (v2.4 single-channel)
//   error_injector_unit: 2 cycles (registered output, 2-cycle pipeline, burst only)
//   bit-scan injection:  w_valid cycles (max 89 for C-RRNS, burst_len=1 only)
//   decoder_wrapper:     ~12 cycles (decoder_2nrm v2.29 pipeline)
//   result_comparator:   1 cycle (registered comparison)
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
    input  wire [2:0]  algo_id,   // 3-bit: 0=2NRM,1=3NRM,2=CRRNS-MLD,3=CRRNS-MRC,4=CRRNS-CRT,5=RS
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
    output reg  [11:0] latency_cycles,  // 12-bit: total trial latency (enc+inj+dec+comp)
    output reg  [11:0] enc_latency,     // 12-bit: encoder latency (enc_start to enc_done)
    output reg  [11:0] dec_latency,     // 12-bit: decoder latency (dec_start to dec_valid_a)
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
    // v1.3 FIX (Bug #93): LFSR now only advances during ENG_STATE_INJ_WAIT.
    // Previously the LFSR was free-running (advancing every clock cycle),
    // which caused the LFSR state at injection time to depend on the decoder
    // latency. Since Parallel (~73 cycles) and Serial (~412 cycles) decoders
    // have different latencies, they sampled different LFSR sequence segments,
    // producing different error clustering patterns and thus different SR curves
    // even though both implement the same MLD algorithm.
    //
    // By freezing the LFSR outside of INJ_WAIT, the injection sequence is
    // independent of decoder latency, ensuring fair comparison between
    // architectures with different pipeline depths.
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

    // LFSR advances ONLY during ENG_STATE_INJ_WAIT (frozen during decode/encode)
    // This ensures injection sequence is independent of decoder latency.
    //
    // FIXED SEED MODE (for Parallel vs Serial equivalence testing):
    //   Set FIXED_SEED_TEST = 1 to use a hardcoded seed (32'hACE12345).
    //   Both Parallel and Serial will use the same LFSR sequence, allowing
    //   direct comparison of SR curves to verify algorithmic equivalence.
    //   Set FIXED_SEED_TEST = 0 (default) to restore random seed behavior.
    localparam FIXED_SEED_TEST = 0;  // 1=fixed seed for testing, 0=random seed (normal)
    localparam [31:0] FIXED_SEED_VAL = 32'hACE12345;

    // LFSR_ADVANCE_TEST: Verification mode for LFSR clustering hypothesis.
    // When set to 1, the LFSR advances 32 EXTRA times after each bit evaluation
    // in the bit-scan loop, breaking the linear correlation between consecutive
    // bit positions. If SR drops to match MATLAB after this change, it confirms
    // that LFSR clustering is the cause of FPGA SR > MATLAB SR.
    // Set back to 0 after verification.
    localparam LFSR_ADVANCE_TEST = 0;  // 1=advance 32 extra times per bit, 0=normal
    localparam [4:0] LFSR_EXTRA_ADVANCES = 5'd31;  // 31 extra = 32 total per bit

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if (FIXED_SEED_TEST)
                inj_lfsr <= FIXED_SEED_VAL;  // Fixed seed for equivalence testing
            else
                inj_lfsr <= 32'hDEADBEEF;   // Default reset value (overwritten by seed_in)
        end else if (FIXED_SEED_TEST && state == `ENG_STATE_CONFIG) begin
            // Per-trial LFSR reset: reload fixed seed at the start of each trial.
            // This ensures Parallel and Serial use IDENTICAL LFSR sequences for
            // each trial, eliminating PRBS sampling differences due to different
            // decode latencies. Used for Parallel vs Serial equivalence testing.
            inj_lfsr <= FIXED_SEED_VAL;
        end else if (state == `ENG_STATE_INJ_WAIT)
            inj_lfsr <= inj_lfsr_next;
        // else: LFSR frozen — holds value during all other states
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

    // BUG FIX #33: 2-bit counter for INJ_WAIT state (burst mode)
    reg [1:0]  inj_wait_cnt;

    // =========================================================================
    // Bit-Scan Multi-Injection Registers (burst_len=1 / Random Single Bit mode)
    // =========================================================================
    // bit_scan_pos: current bit position being evaluated (0 to w_valid-1)
    // bit_scan_cw:  accumulated codeword with flipped bits
    // bit_scan_flips: total bits flipped so far
    //
    // threshold_per_bit: the per-bit flip probability threshold.
    //   ROM stores: threshold_val = BER_target * (2^32 - 1)  (for burst_len=1)
    //   FPGA uses:  if (inj_lfsr < threshold_val) → flip this bit
    //   P(flip) = threshold_val / (2^32 - 1) = BER_target  ✓
    //   No shift needed — gen_rom.py now stores the correct per-bit probability
    //   directly (no ×64 compensation factor for burst_len=1).
    reg [6:0]  bit_scan_pos;    // 7-bit: supports up to 127 bit positions
    reg [63:0] bit_scan_cw;     // Accumulated codeword during bit-scan
    reg [6:0]  bit_scan_flips;  // Flip count accumulator (7-bit: max 89 flips)
    // LFSR_ADVANCE_TEST: extra advance counter (0..31 for 31 extra advances per bit)
    reg [4:0]  lfsr_skip_cnt;   // Counts extra LFSR advances per bit position
    wire [31:0] threshold_per_bit;
    assign threshold_per_bit = threshold_val;  // Direct use: ROM stores BER*(2^32-1)

    // Encoder and decoder latency measurement counters
    reg [11:0] enc_lat_cnt;   // Counts cycles in ENC_WAIT (enc_start to enc_done_d1)
    reg [11:0] dec_lat_cnt;   // Counts cycles in DEC_WAIT (dec_start to dec_valid_a)

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
    wire [`COMP_LATENCY_WIDTH-1:0] comp_latency_a;  // 12-bit: matches COMP_LATENCY_WIDTH
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
            latency_cycles   <= 12'd0;
            enc_latency      <= 12'd0;
            dec_latency      <= 12'd0;
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
            enc_lat_cnt      <= 12'd0;
            dec_lat_cnt      <= 12'd0;
            bit_scan_pos     <= 7'd0;
            bit_scan_cw      <= 64'd0;
            bit_scan_flips   <= 7'd0;
            lfsr_skip_cnt    <= 5'd0;

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
                        enc_lat_cnt     <= 12'd0;           // Reset encoder latency counter
                        enc_start       <= 1'b1;
                        state           <= `ENG_STATE_ENC_WAIT;
                    end
                end

                // =============================================================
                // ENC_WAIT: Wait for encoder to finish
                //   BUG FIX: encoder_wrapper latches codeword_A on enc_done=1 via NBA,
                //   so codeword_A is only valid one cycle AFTER enc_done=1.
                //   enc_done_d1 aligns the latch point with the valid codeword data.
                //   enc_lat_cnt: counts cycles from enc_start to enc_done_d1 (inclusive)
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
                        enc_lat_cnt <= enc_lat_cnt + 12'd1;  // Count encoder cycles

                        if (enc_done_d1) begin
                            enc_out_a_latch <= codeword_a_raw[63:0];
                            // enc_out_b_latch <= codeword_b_raw[63:0];  // SINGLE-CHANNEL: disabled
                            cw_len_latch    <= cw_len_a;
                            enc_done_d1     <= 1'b0;
                            enc_latency     <= enc_lat_cnt;  // Latch encoder latency
                            state           <= `ENG_STATE_INJ_WAIT;
                        end
                    end
                end

                // =============================================================
                // INJ_WAIT: Error injection — two paths based on burst_len:
                //
                // PATH A (burst_len == 1): Bit-scan Bernoulli multi-injection.
                //   Iterates over each bit position 0..(cw_len_latch-1).
                //   Each cycle: advance LFSR, compare against threshold_per_bit.
                //   If lfsr < threshold_per_bit → flip that bit in bit_scan_cw.
                //   After all bits scanned, latch result and proceed to DEC_WAIT.
                //   This allows actual BER to reach up to 10% without saturation.
                //
                // PATH B (burst_len > 1): Original ROM-based single burst injection.
                //   2-cycle pipeline wait (BUG FIX #33), unchanged from v1.1.
                // =============================================================
                `ENG_STATE_INJ_WAIT: begin
                    if (dec_timeout_flag) begin
                        result_pass    <= 1'b0;
                        inj_wait_cnt   <= 2'd0;
                        bit_scan_pos   <= 7'd0;
                        bit_scan_cw    <= 64'd0;
                        bit_scan_flips <= 7'd0;
                        state          <= `ENG_STATE_DONE;

                    end else if (burst_len == 4'd1) begin
                        // ─────────────────────────────────────────────────────
                        // PATH A: Bit-scan Bernoulli injection (burst_len=1)
                        // ─────────────────────────────────────────────────────
                        // Cycle 0 (bit_scan_pos==0): Initialize accumulator only.
                        //   bit_scan_cw  ← enc_out_a_latch (clean codeword)
                        //   bit_scan_pos ← 1 (advance to first evaluation cycle)
                        //
                        // Cycles 1..w_valid (bit_scan_pos==1..w_valid):
                        //   Evaluate bit (bit_scan_pos-1) using current inj_lfsr.
                        //   inj_lfsr advances automatically every clock.
                        //   If lfsr < threshold_per_bit → flip bit (bit_scan_pos-1).
                        //
                        // Cycle w_valid+1 (bit_scan_pos==w_valid+1): Done.
                        //   Latch bit_scan_cw → inj_out_a_latch, proceed to DEC_WAIT.
                        //
                        // Total latency: w_valid + 2 cycles (init + w_valid evals + done)
                        // ─────────────────────────────────────────────────────
                        if (bit_scan_pos == 7'd0) begin
                            // Cycle 0: Initialize accumulator, no bit evaluation yet
                            bit_scan_cw    <= enc_out_a_latch;
                            bit_scan_flips <= 7'd0;
                            lfsr_skip_cnt  <= 5'd0;
                            bit_scan_pos   <= 7'd1;  // Advance to first evaluation

                        end else if (bit_scan_pos <= {1'b0, cw_len_latch}) begin
                            // Cycles 1..w_valid: Evaluate bit (bit_scan_pos-1)
                            // LFSR_ADVANCE_TEST: first cycle evaluates the bit,
                            // then lfsr_skip_cnt counts 31 extra LFSR advances
                            // before moving to the next bit position.
                            if (LFSR_ADVANCE_TEST) begin
                                if (lfsr_skip_cnt == 5'd0) begin
                                    // First cycle: evaluate this bit
                                    if (inj_lfsr < threshold_per_bit) begin
                                        bit_scan_cw    <= bit_scan_cw ^ (64'd1 << (bit_scan_pos - 7'd1));
                                        bit_scan_flips <= bit_scan_flips + 7'd1;
                                    end
                                    lfsr_skip_cnt <= 5'd1;  // Start extra advances
                                end else if (lfsr_skip_cnt < LFSR_EXTRA_ADVANCES) begin
                                    // Extra advance cycles: just let LFSR run
                                    lfsr_skip_cnt <= lfsr_skip_cnt + 5'd1;
                                end else begin
                                    // Done with extra advances: move to next bit
                                    lfsr_skip_cnt <= 5'd0;
                                    bit_scan_pos  <= bit_scan_pos + 7'd1;
                                end
                            end else begin
                                // Normal mode: evaluate and advance immediately
                                if (inj_lfsr < threshold_per_bit) begin
                                    bit_scan_cw    <= bit_scan_cw ^ (64'd1 << (bit_scan_pos - 7'd1));
                                    bit_scan_flips <= bit_scan_flips + 7'd1;
                                end
                                bit_scan_pos <= bit_scan_pos + 7'd1;
                            end

                        end else begin
                            // All bits scanned — latch result and proceed
                            inj_out_a_latch <= bit_scan_cw;
                            was_injected    <= (bit_scan_flips != 7'd0);
                            flip_count_a    <= bit_scan_flips[5:0];  // Saturate at 63
                            bit_scan_pos    <= 7'd0;   // Reset for next trial
                            bit_scan_cw     <= 64'd0;
                            bit_scan_flips  <= 7'd0;
                            dec_lat_cnt     <= 12'd0;
                            dec_start       <= 1'b1;
                            state           <= `ENG_STATE_DEC_WAIT;
                        end

                    end else begin
                        // ─────────────────────────────────────────────────────
                        // PATH B: ROM-based single burst injection (burst_len>1)
                        // Original logic — BUG FIX #33: 2-cycle pipeline wait
                        // ─────────────────────────────────────────────────────
                        if (inj_wait_cnt < 2'd2) begin
                            inj_wait_cnt <= inj_wait_cnt + 2'd1;
                        end else begin
                            // Cycle 2: inj_out_a is now valid
                            inj_out_a_latch <= inj_out_a;
                            inj_wait_cnt    <= 2'd0;

                            was_injected <= inject_en_latch;
                            flip_count_a <= inj_flip_a;

                            dec_lat_cnt <= 12'd0;
                            dec_start   <= 1'b1;
                            state       <= `ENG_STATE_DEC_WAIT;
                        end
                    end
                end

                // =============================================================
                // DEC_WAIT: Wait for Channel A decoder to produce valid output
                //   Single-channel mode: only wait for dec_valid_a
                //   dec_lat_cnt: counts cycles from dec_start to dec_valid_a (inclusive)
                // =============================================================
                `ENG_STATE_DEC_WAIT: begin
                    dec_lat_cnt <= dec_lat_cnt + 12'd1;  // Count decoder cycles
                    if (dec_valid_a) begin
                        // Channel A decoder has produced output → move to COMP_WAIT
                        dec_latency <= dec_lat_cnt;  // Latch decoder latency
                        state       <= `ENG_STATE_COMP_WAIT;
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
