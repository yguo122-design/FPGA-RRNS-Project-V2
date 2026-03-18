// =============================================================================
// File: prbs_generator.v
// Description: PRBS Generator - 32-bit Galois LFSR producing dual 16-bit test symbols
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Corresponds to Section 2.3.2 of Top-Level Design Document
// Version: v1.0
//
// ─────────────────────────────────────────────────────────────────────────────
// OUTPUT STRUCTURE (CRITICAL DESIGN INTENT):
//   Each clock cycle when start_gen=1, this module outputs ONE 32-bit word
//   that encodes TWO independent 16-bit test symbols:
//
//     prbs_out[31:16]  =  Symbol_A  (first  16-bit test data, range 0~65535)
//     prbs_out[15:0]   =  Symbol_B  (second 16-bit test data, range 0~65535)
//
//   Downstream pipeline interaction:
//     1. ENCODER:    Symbol_A and Symbol_B are fed into the Encoder separately.
//                    Each produces an independent codeword.
//     2. INJECTOR:   Each codeword passes through the error injector independently.
//     3. DECODER:    Decoder recovers two 16-bit values: Recovered_A, Recovered_B.
//     4. COMPARATOR: Two comparisons are performed per output word:
//                      - Recovered_A == Symbol_A ?  → Pass/Fail for trial 1
//                      - Recovered_B == Symbol_B ?  → Pass/Fail for trial 2
//     5. STATISTICS: Each 32-bit prbs_out word represents ONE trial in the
//                    main_scan_fsm statistics model. Although two 16-bit symbols
//                    (A and B) are processed in parallel, auto_scan_engine merges
//                    their results via (comp_result_a && comp_result_b) into a
//                    single result_pass signal. main_scan_fsm increments
//                    trial_cnt by 1 per eng_done pulse, which is semantically
//                    correct: one trial = one joint A+B pass/fail decision.
//                    NOTE: The previous comment "Total_Trials should increment
//                    by 2" was incorrect and has been removed (comment-only fix,
//                    no functional change to this module).
// ─────────────────────────────────────────────────────────────────────────────
//
// LFSR Specification:
//   - Type: 32-bit Galois LFSR (maximal-length: 2^32 - 1 states)
//   - Polynomial: x^32 + x^22 + x^2 + x^1 + 1
//   - Taps (0-indexed): [31, 21, 1, 0]
//   - Feedback bit: lfsr_q[0] (LSB, right-shift Galois structure)
//
// Galois LFSR Right-Shift Operation:
//   feedback_bit = lfsr_q[0]
//   lfsr_next[31]  = feedback_bit          (tap 31: shift-in at MSB)
//   lfsr_next[30:22] = lfsr_q[31:23]       (plain shift, 9 bits)
//   lfsr_next[21]  = lfsr_q[22] ^ feedback (tap 21: XOR with feedback)
//   lfsr_next[20:2] = lfsr_q[21:3]         (plain shift, 19 bits)
//   lfsr_next[1]   = lfsr_q[2]  ^ feedback (tap 1: XOR with feedback)
//   lfsr_next[0]   = lfsr_q[1]  ^ feedback (tap 0: XOR with feedback)
//
// Seed Loading:
//   - load_seed pulse loads seed_in into the LFSR (takes priority over start_gen)
//   - Zero-value protection: if seed_in == 0, PRBS_SAFE_SEED is used instead
//
// Generation Control:
//   - start_gen=1: LFSR advances each clock, prbs_out updated, prbs_valid=1
//   - start_gen=0: LFSR frozen, prbs_valid=0
// =============================================================================

`include "prbs_generator.vh"

module prbs_generator (
    `PRBS_GENERATOR_PORTS
);

    // =========================================================================
    // Internal LFSR Register
    // =========================================================================
    reg [`PRBS_LFSR_WIDTH-1:0] lfsr_q;

    // =========================================================================
    // Galois LFSR Next-State Combinational Logic
    // =========================================================================
    // Right-shift Galois LFSR with taps at [31, 21, 1, 0]:
    //   - feedback_bit = lfsr_q[0] (outgoing LSB)
    //   - Shift right: each bit moves to the next lower position
    //   - MSB (bit 31) receives feedback_bit (handles tap 31)
    //   - Intermediate taps [21] and [1] are XORed with feedback_bit
    //   - Bit [0] is the XOR of lfsr_q[1] and feedback_bit (handles tap 0)

    wire feedback_bit;
    wire [`PRBS_LFSR_WIDTH-1:0] lfsr_next;

    assign feedback_bit = lfsr_q[0];

    // Bit-width verification:
    //   bit[31]    : 1 bit  (feedback, tap 31)
    //   bits[30:22]: 9 bits (lfsr_q[31:23], plain shift)
    //   bit[21]    : 1 bit  (lfsr_q[22] ^ feedback, tap 21)
    //   bits[20:2] : 19 bits (lfsr_q[21:3], plain shift)
    //   bit[1]     : 1 bit  (lfsr_q[2] ^ feedback, tap 1)
    //   bit[0]     : 1 bit  (lfsr_q[1] ^ feedback, tap 0)
    //   Total      : 1+9+1+19+1+1 = 32 bits ✓
    assign lfsr_next = {
        feedback_bit,                   // bit[31]: tap 31 (shift-in)
        lfsr_q[31:23],                  // bits[30:22]: plain shift (9 bits)
        lfsr_q[22] ^ feedback_bit,      // bit[21]: tap 21
        lfsr_q[21:3],                   // bits[20:2]: plain shift (19 bits)
        lfsr_q[2]  ^ feedback_bit,      // bit[1]: tap 1
        lfsr_q[1]  ^ feedback_bit       // bit[0]: tap 0
    };

    // =========================================================================
    // Sequential Logic: Seed Loading, LFSR Advance, Output Generation
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // -----------------------------------------------------------------
            // Asynchronous Reset:
            //   Initialize LFSR to safe non-zero seed to prevent lock-up.
            //   Clear outputs.
            // -----------------------------------------------------------------
            lfsr_q     <= `PRBS_SAFE_SEED;
            prbs_out   <= `PRBS_OUT_WIDTH'h0;
            prbs_valid <= 1'b0;

        end else begin

            // Default: deassert prbs_valid (will be re-asserted below if needed)
            prbs_valid <= 1'b0;

            if (load_seed) begin
                // -------------------------------------------------------------
                // Seed Load (highest priority, overrides start_gen):
                //   Load the provided seed into the LFSR.
                //   Zero-value protection: if seed_in is 0, substitute the
                //   safe default seed to prevent LFSR lock-up.
                // -------------------------------------------------------------
                if (seed_in != `PRBS_LFSR_WIDTH'h0) begin
                    lfsr_q <= seed_in;
                end else begin
                    lfsr_q <= `PRBS_SAFE_SEED;
                end
                // Do not update prbs_out or prbs_valid on seed load

            end else if (start_gen) begin
                // -------------------------------------------------------------
                // Normal Generation Mode:
                //   Advance the LFSR by one step and capture the new state
                //   as the output word.
                //
                //   OUTPUT MAPPING (32-bit = 2 × 16-bit test symbols):
                //     prbs_out[31:16] = Symbol_A = lfsr_next[31:16]
                //     prbs_out[15:0]  = Symbol_B = lfsr_next[15:0]
                //
                //   Both symbols are derived from consecutive LFSR bits,
                //   ensuring they are statistically independent pseudo-random
                //   values within the maximal-length sequence.
                //
                //   NOTE: Each assertion of prbs_valid represents ONE test
                //   trial in the statistics model. auto_scan_engine merges
                //   Symbol_A and Symbol_B results into a single result_pass
                //   (comp_result_a && comp_result_b). main_scan_fsm increments
                //   trial_cnt by 1 per eng_done, which is correct.
                // -------------------------------------------------------------
                lfsr_q     <= lfsr_next;
                prbs_out   <= lfsr_next;   // [31:16]=Symbol_A, [15:0]=Symbol_B
                prbs_valid <= 1'b1;        // Signal: 2 new test symbols ready

            end
            // else (start_gen=0, load_seed=0): LFSR frozen, outputs hold values

        end
    end

endmodule
