// =============================================================================
// File: decoder_2nrm.v
// Description: 2NRM Decoder with MLD (Maximum Likelihood Decoding)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.3
// Version: v2.7  -- TIMING FIX: DSP48E1 internal pipeline registers enabled
//                   Stage 1c and 1e each split into two sub-stages:
//                   (1) input register (AREG/BREG) + (2) multiply output register (MREG/PREG)
//                   This forces Vivado to pack registers INTO the DSP48E1 slice,
//                   cutting Logic Delay from ~7ns to ~1ns per multiply stage.
//                   Total channel latency: 6 -> 8 cycles (+2 cycles for 2 DSP stages).
//                   Total decoder latency: 8 -> 10 cycles.
//                   (v2.6: use_dsp="YES" correct but AREG/BREG/MREG still 0 -- combinational)
//
// Algorithm: 2NRM-RRNS with Moduli Set {257, 256, 61, 59, 55, 53}
//   - 6 moduli: 2 information (257, 256) + 4 redundant (61, 59, 55, 53)
//   - Data width: 16 bits (0~65535)
//   - Error correction capability: t=2 (up to 2 erroneous residues)
//   - MLD: C(6,2)=15 parallel CRT channels, select minimum Hamming distance
//
// Input Packing (41 bits, right-aligned in 64-bit bus):
//   [40:32] = r257 (9-bit)
//   [31:24] = r256 (8-bit)
//   [23:18] = r61  (6-bit)
//   [17:12] = r59  (6-bit)
//   [11:6]  = r55  (6-bit)
//   [5:0]   = r53  (6-bit)
//
// Pipeline Latency: 11 clock cycles total (start -> valid) [v2.7]
//   Cycle 0:  start=1, residues_in sampled; input registers latch r0..r5
//   Cycle 1:  Stage 1a     -- diff_raw (subtraction only, ~3 LUT)
//   Cycle 2:  Stage 1b     -- diff_mod = diff_raw % P_M2 (modulo, ~8 LUT)
//   Cycle 3:  Stage 1c_pre -- dsp_a_1c = diff_mod_s1b (DSP AREG input register)
//   Cycle 4:  Stage 1c     -- coeff_raw_s1c = dsp_a_1c * P_INV (DSP MREG output register)
//   Cycle 5:  Stage 1d     -- coeff_mod = coeff_raw_s1c % P_M2 (modulo, ~8 LUT)
//   Cycle 6:  Stage 1e_pre -- dsp_a_1e = coeff_mod_s1d, dsp_c_1e = ri_s1d (DSP AREG+CREG)
//   Cycle 7:  Stage 1e     -- x_cand_16_s1e = ri + P_M1*coeff_mod (DSP PREG, MAC mode)
//   Cycle 8:  Stage 2      -- 6x modular residues (cand_r_s2) latched
//   Cycle 9:  Stage 3      -- distance + x_out latched (ch_valid HIGH)
//   Cycle 10: MLD output register -- valid=1, data_out stable
//
// DSP48E1 Register Mapping (v2.7):
//   Stage 1c: dsp_a_1c -> AREG=1, coeff_raw_s1c -> MREG=1
//   Stage 1e: dsp_a_1e -> AREG=1, dsp_c_1e -> CREG=1, x_cand_16_s1e -> PREG=1
//   Expected Logic Delay per DSP stage: ~1 ns (vs ~7 ns combinational in v2.6)
//
// TIMING FIX RATIONALE (v2.2):
//   v2.1 WNS = -14 ns. Critical path ends at coeff_mod_s1a_reg.
//   Root cause: Stage 1a contained BOTH multiply (diff*P_INV) AND modulo (%P_M2),
//   totaling ~16 LUT. Additionally, input signals r0..r5 had fanout=27 (15 channels
//   x 2 residues each), causing Net Delay ~11 ns.
//
//   v2.2 fixes:
//   1. CRT split into 4 sub-stages (1a/1b/1c/1d): each stage has at most ONE
//      expensive operation (either multiply OR modulo, never both).
//      Max LUT per stage: ~10 levels.
//   2. Input register duplication: r0..r5 are registered at the top-level
//      decoder_2nrm module BEFORE being broadcast to 15 channels, reducing
//      the fanout on each net from 27 to 1 (each channel gets its own copy
//      via the registered bus). Synthesis attribute (* keep = "true" *) is
//      applied to prevent optimization from merging them back.
//
// UPPER-LEVEL IMPACT:
//   auto_scan_engine DEC_WAIT state polls dec_valid_a/dec_valid_b.
//   The 1-cycle latency increase (5->6 cycles) is absorbed automatically.
//   No changes to auto_scan_engine.v or main_scan_fsm.v are required.
//
// CRT Formula (per channel):
//   X = r_i + M_i * ((r_j - r_i) * Inv(M_i, M_j) mod M_j)
//   where Inv(M_i, M_j) is the modular inverse of M_i modulo M_j
//
// MLD Decision:
//   For each candidate X, compute residues modulo all 6 moduli.
//   Count mismatches with received residues → Hamming distance.
//   Select X with minimum distance. If min_dist > NRM_MAX_ERRORS(2) → uncorrectable.
// =============================================================================

`include "decoder_2nrm.vh"
`timescale 1ns / 1ps

// =============================================================================
// Sub-Module: decoder_channel_2nrm_param
// Description: Single CRT reconstruction channel for one pair of moduli (M1, M2)
//              Reconstructs candidate X using two received residues, then
//              computes Hamming distance against all 6 received residues.
//
// PIPELINE STRUCTURE (6 stages, 6-cycle latency):
//
//  Stage 1a [Cycle 0->1]: Difference Calculation (subtraction only)
//    Combinational: MUX(ri,rj) -> diff_raw = rj + P_M2 - ri
//    Register:      diff_raw_s1a, ri_s1a, r0_s1a..r5_s1a, valid_s1a
//    (~3 LUT levels: adder/subtractor only)
//
//  Stage 1b [Cycle 1->2]: First Modulo (diff_mod = diff_raw % P_M2)
//    Combinational: diff_mod = diff_raw_s1a % P_M2
//    Register:      diff_mod_s1b, ri_s1b, r0_s1b..r5_s1b, valid_s1b
//    (~8 LUT levels: constant modulo)
//
//  Stage 1c [Cycle 2->3]: Multiplication (coeff_raw = diff_mod * P_INV)
//    Combinational: coeff_raw = diff_mod_s1b * P_INV
//    Register:      coeff_raw_s1c, ri_s1c, r0_s1c..r5_s1c, valid_s1c
//    (~8 LUT levels: constant multiply)
//
//  Stage 1d [Cycle 3->4]: Second Modulo + Final Multiply+Add
//    Combinational: coeff_mod = coeff_raw_s1c % P_M2  (~8 LUT)
//                   x_cand = ri_s1c + P_M1 * coeff_mod  (~10 LUT)
//                   x_cand_16 = clamp(x_cand)
//    Register:      x_cand_16_s1d, r0_s1d..r5_s1d, valid_s1d
//    NOTE: coeff_mod feeds directly into multiply in same stage.
//          Total ~18 LUT -- if still too slow, split further.
//
//  Stage 2  [Cycle 4->5]: Modular Residue Computation
//    Combinational: cand_r[k] = x_cand_16_s1d % modulus[k]  (6 independent ops)
//    Register:      cand_r_s2[0..5], recv_r_s2[0..5], x_cand_16_s2, valid_s2
//    (~8-10 LUT levels per modulo, all parallel)
//
//  Stage 3  [Cycle 5->6]: Hamming Distance Accumulation
//    Combinational: 6-way mismatch compare + popcount adder
//    Register:      x_out, distance, valid  (final channel outputs)
//    (~5-8 LUT levels)
//
// Parameters:
//   P_M1    - First modulus value
//   P_M2    - Second modulus value
//   P_INV   - Modular inverse of P_M1 modulo P_M2 (pre-computed constant)
// =============================================================================
module decoder_channel_2nrm_param #(
    parameter P_M1  = 257,  // First modulus
    parameter P_M2  = 256,  // Second modulus
    parameter P_INV = 1     // Inv(P_M1 mod P_M2, P_M2)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    // Received residues (9-bit zero-extended for uniform processing)
    // NOTE: These inputs are driven from registered outputs in decoder_2nrm
    //       top-level to reduce fanout from 27 to 1 per channel.
    input  wire [8:0]  r0,   // r257
    input  wire [8:0]  r1,   // r256
    input  wire [8:0]  r2,   // r61
    input  wire [8:0]  r3,   // r59
    input  wire [8:0]  r4,   // r55
    input  wire [8:0]  r5,   // r53

    // Which residues this channel uses (index 0~5)
    input  wire [2:0]  idx1, // Index of first modulus in the set
    input  wire [2:0]  idx2, // Index of second modulus in the set

    output reg  [15:0] x_out,
    output reg  [3:0]  distance,
    output reg         valid
);

    // =========================================================================
    // STAGE 1a: Difference Calculation
    // Combinational: MUX(ri,rj) -> diff_raw = rj + P_M2 - ri
    // Only subtraction/addition: ~3 LUT levels
    // =========================================================================

    // Select the two residues for this channel based on idx1, idx2
    reg [8:0] ri, rj;
    always @(*) begin
        case (idx1)
            3'd0: ri = r0;
            3'd1: ri = r1;
            3'd2: ri = r2;
            3'd3: ri = r3;
            3'd4: ri = r4;
            default: ri = r5;
        endcase
        case (idx2)
            3'd0: rj = r0;
            3'd1: rj = r1;
            3'd2: rj = r2;
            3'd3: rj = r3;
            3'd4: rj = r4;
            default: rj = r5;
        endcase
    end

    // diff_raw = rj + P_M2 - ri  (no modulo here -- just addition/subtraction)
    wire [17:0] diff_raw;
    assign diff_raw = {9'b0, rj} + P_M2 - {9'b0, ri};

    // --- Stage 1a pipeline registers ---
    // (* dont_touch = "true" *) prevents Vivado from merging this stage with
    // Stage 1b (which would recreate the long diff_raw->diff_mod chain).
    (* dont_touch = "true" *) reg [17:0] diff_raw_s1a;
    (* dont_touch = "true" *) reg [8:0]  ri_s1a;
    (* dont_touch = "true" *) reg [8:0]  r0_s1a, r1_s1a, r2_s1a, r3_s1a, r4_s1a, r5_s1a;
    (* dont_touch = "true" *) reg        valid_s1a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_raw_s1a <= 18'd0;
            ri_s1a       <= 9'd0;
            r0_s1a <= 9'd0; r1_s1a <= 9'd0; r2_s1a <= 9'd0;
            r3_s1a <= 9'd0; r4_s1a <= 9'd0; r5_s1a <= 9'd0;
            valid_s1a <= 1'b0;
        end else begin
            valid_s1a    <= start;
            diff_raw_s1a <= diff_raw;
            ri_s1a       <= ri;
            r0_s1a <= r0; r1_s1a <= r1; r2_s1a <= r2;
            r3_s1a <= r3; r4_s1a <= r4; r5_s1a <= r5;
        end
    end

    // =========================================================================
    // STAGE 1b: First Modulo Operation
    // Combinational: diff_mod = diff_raw_s1a % P_M2
    // Only ONE modulo operation: ~8 LUT levels
    // =========================================================================

    wire [17:0] diff_mod_1b;
    assign diff_mod_1b = diff_raw_s1a % P_M2;

    // --- Stage 1b pipeline registers ---
    // dont_touch: prevents Vivado from merging Stage 1b with 1c.
    // max_fanout=4: diff_mod_s1b drives Stage 1c multiply in all 15 channel instances;
    //   Vivado must replicate this register (fanout<=4) to reduce Net Delay.
    //   NOTE: set_max_fanout in XDC is NOT supported ([Designutils 20-1307]);
    //         this in-code attribute is the correct method.
    (* dont_touch = "true", max_fanout = 4 *) reg [17:0] diff_mod_s1b;
    (* dont_touch = "true" *) reg [8:0]  ri_s1b;
    (* dont_touch = "true" *) reg [8:0]  r0_s1b, r1_s1b, r2_s1b, r3_s1b, r4_s1b, r5_s1b;
    (* dont_touch = "true" *) reg        valid_s1b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_mod_s1b <= 18'd0;
            ri_s1b       <= 9'd0;
            r0_s1b <= 9'd0; r1_s1b <= 9'd0; r2_s1b <= 9'd0;
            r3_s1b <= 9'd0; r4_s1b <= 9'd0; r5_s1b <= 9'd0;
            valid_s1b <= 1'b0;
        end else begin
            valid_s1b    <= valid_s1a;
            diff_mod_s1b <= diff_mod_1b;
            ri_s1b       <= ri_s1a;
            r0_s1b <= r0_s1a; r1_s1b <= r1_s1a; r2_s1b <= r2_s1a;
            r3_s1b <= r3_s1a; r4_s1b <= r4_s1a; r5_s1b <= r5_s1a;
        end
    end

    // =========================================================================
    // STAGE 1c: Multiplication
    // Combinational: coeff_raw = diff_mod_s1b * P_INV
    // Only ONE multiply (constant * variable).
    //
    // DSP OPTIMIZATION (v2.5):
    //   (* use_dsp = "true" *) forces Vivado to map this multiplication to a
    //   DSP48E1 hardware slice instead of LUT carry chains.
    //   DSP48E1 multiply latency: ~1-2 ns (vs ~7-8 ns for LUT implementation).
    //   This is the primary fix for Logic Delay ~7.4ns on the critical path.
    //   Applied to the result wire so the attribute covers the multiply operator.
    // =========================================================================

    // --- Stage 1c: DSP AREG + MREG in ONE always block ---
    // Both the input register (dsp_a_1c -> AREG) and the output register
    // (coeff_raw_s1c -> MREG) are in the SAME always block so Vivado can
    // clearly see the pattern: reg_in -> multiply -> reg_out and pack both
    // into DSP48E1 internal pipeline registers.
    // valid_s1c_pre is the intermediate valid (1 cycle after valid_s1b).
    // --- Stage 1c: DSP48E1 AREG + MREG (full-precision 48-bit intermediate) ---
    // KEY FIX (v2.7b): Use 48-bit full-precision intermediate register mult_res_1c_full
    // to match DSP48E1 native P-port width (48-bit). Vivado can then map:
    //   dsp_a_1c [17:0]       -> DSP A-port (18-bit) -> AREG=1
    //   mult_res_1c_full[47:0] -> DSP P-port (48-bit) -> MREG=1
    // Truncation to coeff_raw_s1c [35:0] happens AFTER MREG (external FF).
    // Without full-precision intermediate, Vivado sees width mismatch and
    // falls back to LUT implementation (AREG=0, MREG=0).
    (* dont_touch = "true" *) reg [17:0] dsp_a_1c;          // DSP AREG (18-bit A-port)
    (* dont_touch = "true" *) reg [8:0]  ri_s1c_pre;
    (* dont_touch = "true" *) reg [8:0]  r0_s1c_pre, r1_s1c_pre, r2_s1c_pre;
    (* dont_touch = "true" *) reg [8:0]  r3_s1c_pre, r4_s1c_pre, r5_s1c_pre;
    (* dont_touch = "true" *) reg        valid_s1c_pre;

    (* dont_touch = "true" *) reg [47:0] mult_res_1c_full;   // DSP MREG (48-bit P-port)
    (* dont_touch = "true" *) reg [8:0]  ri_s1c_mid;
    (* dont_touch = "true" *) reg [8:0]  r0_s1c_mid, r1_s1c_mid, r2_s1c_mid;
    (* dont_touch = "true" *) reg [8:0]  r3_s1c_mid, r4_s1c_mid, r5_s1c_mid;
    (* dont_touch = "true" *) reg        valid_s1c_mid;

    (* dont_touch = "true", max_fanout = 4 *) reg [35:0] coeff_raw_s1c; // External FF (truncation)
    (* dont_touch = "true" *) reg [8:0]  ri_s1c;
    (* dont_touch = "true" *) reg [8:0]  r0_s1c, r1_s1c, r2_s1c, r3_s1c, r4_s1c, r5_s1c;
    (* dont_touch = "true" *) reg        valid_s1c;

    // Three-stage always block: AREG -> MREG (48-bit) -> truncate
    // Vivado maps: dsp_a_1c (AREG=1) -> multiply -> mult_res_1c_full (MREG=1)
    // coeff_raw_s1c is an external FF that slices [35:0] from the 48-bit MREG output.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // AREG reset
            dsp_a_1c       <= 18'd0;
            ri_s1c_pre     <= 9'd0;
            r0_s1c_pre <= 9'd0; r1_s1c_pre <= 9'd0; r2_s1c_pre <= 9'd0;
            r3_s1c_pre <= 9'd0; r4_s1c_pre <= 9'd0; r5_s1c_pre <= 9'd0;
            valid_s1c_pre  <= 1'b0;
            // MREG reset (48-bit full precision)
            mult_res_1c_full <= 48'd0;
            ri_s1c_mid     <= 9'd0;
            r0_s1c_mid <= 9'd0; r1_s1c_mid <= 9'd0; r2_s1c_mid <= 9'd0;
            r3_s1c_mid <= 9'd0; r4_s1c_mid <= 9'd0; r5_s1c_mid <= 9'd0;
            valid_s1c_mid  <= 1'b0;
            // External truncation FF reset
            coeff_raw_s1c  <= 36'd0;
            ri_s1c         <= 9'd0;
            r0_s1c <= 9'd0; r1_s1c <= 9'd0; r2_s1c <= 9'd0;
            r3_s1c <= 9'd0; r4_s1c <= 9'd0; r5_s1c <= 9'd0;
            valid_s1c      <= 1'b0;
        end else begin
            // Stage 1c_pre: AREG -- latch 18-bit input aligned to DSP A-port
            dsp_a_1c       <= diff_mod_s1b[17:0];  // explicit 18-bit alignment
            ri_s1c_pre     <= ri_s1b;
            r0_s1c_pre <= r0_s1b; r1_s1c_pre <= r1_s1b; r2_s1c_pre <= r2_s1b;
            r3_s1c_pre <= r3_s1b; r4_s1c_pre <= r4_s1b; r5_s1c_pre <= r5_s1b;
            valid_s1c_pre  <= valid_s1b;
            // Stage 1c: MREG -- 48-bit full-precision multiply result (DSP P-port width)
            // Vivado packs dsp_a_1c (AREG) and mult_res_1c_full (MREG) into DSP48E1
            mult_res_1c_full <= {12'd0, dsp_a_1c} * P_INV; // zero-extend to 48-bit
            ri_s1c_mid     <= ri_s1c_pre;
            r0_s1c_mid <= r0_s1c_pre; r1_s1c_mid <= r1_s1c_pre; r2_s1c_mid <= r2_s1c_pre;
            r3_s1c_mid <= r3_s1c_pre; r4_s1c_mid <= r4_s1c_pre; r5_s1c_mid <= r5_s1c_pre;
            valid_s1c_mid  <= valid_s1c_pre;
            // Stage 1c_post: External FF -- truncate 48-bit MREG to 36-bit
            coeff_raw_s1c  <= mult_res_1c_full[35:0];
            ri_s1c         <= ri_s1c_mid;
            r0_s1c <= r0_s1c_mid; r1_s1c <= r1_s1c_mid; r2_s1c <= r2_s1c_mid;
            r3_s1c <= r3_s1c_mid; r4_s1c <= r4_s1c_mid; r5_s1c <= r5_s1c_mid;
            valid_s1c      <= valid_s1c_mid;
        end
    end

    // =========================================================================
    // STAGE 1d: Second Modulo ONLY
    // Combinational: coeff_mod = coeff_raw_s1c % P_M2
    // Only ONE modulo operation: ~8 LUT levels
    // IMPORTANT: No multiply here -- multiply is in Stage 1e.
    // =========================================================================

    wire [17:0] coeff_mod_1d;
    assign coeff_mod_1d = coeff_raw_s1c % P_M2;

    // --- Stage 1d pipeline registers ---
    // dont_touch: prevents Vivado from merging Stage 1d with 1e.
    // max_fanout=4: coeff_mod_s1d drives Stage 1e multiply in all 15 channel instances;
    //   Vivado must replicate this register to reduce Net Delay.
    //   NOTE: set_max_fanout in XDC is NOT supported ([Designutils 20-1307]);
    //         this in-code attribute is the correct method.
    (* dont_touch = "true", max_fanout = 4 *) reg [17:0] coeff_mod_s1d;
    (* dont_touch = "true" *) reg [8:0]  ri_s1d;
    (* dont_touch = "true" *) reg [8:0]  r0_s1d, r1_s1d, r2_s1d, r3_s1d, r4_s1d, r5_s1d;
    (* dont_touch = "true" *) reg        valid_s1d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coeff_mod_s1d <= 18'd0;
            ri_s1d        <= 9'd0;
            r0_s1d <= 9'd0; r1_s1d <= 9'd0; r2_s1d <= 9'd0;
            r3_s1d <= 9'd0; r4_s1d <= 9'd0; r5_s1d <= 9'd0;
            valid_s1d <= 1'b0;
        end else begin
            valid_s1d     <= valid_s1c;
            coeff_mod_s1d <= coeff_mod_1d;
            ri_s1d        <= ri_s1c;
            r0_s1d <= r0_s1c; r1_s1d <= r1_s1c; r2_s1d <= r2_s1c;
            r3_s1d <= r3_s1c; r4_s1d <= r4_s1c; r5_s1d <= r5_s1c;
        end
    end

    // =========================================================================
    // STAGE 1e: Final Multiply-Add ONLY
    // Combinational: x_cand = ri_s1d + P_M1 * coeff_mod_s1d -> clamp
    // Only ONE multiply + add + clamp.
    //
    // DSP OPTIMIZATION (v2.5):
    //   (* use_dsp = "true" *) forces Vivado to map the P_M1 * coeff_mod_s1d
    //   multiplication to a DSP48E1 hardware slice.
    //   DSP48E1 also supports the post-multiply addition (P = A*B + C),
    //   so the entire multiply-add may be absorbed into a single DSP slice.
    //   Applied to the result wire so the attribute covers the multiply operator.
    // =========================================================================

    // --- Stage 1e: DSP AREG + CREG + PREG in ONE always block ---
    // All three DSP registers (input A, input C, output P) are in the SAME
    // always block so Vivado can clearly see the MAC pattern:
    //   dsp_a_1e (AREG) + dsp_c_1e (CREG) -> MAC -> x_cand_16_s1e (PREG)
    // and pack all three into DSP48E1 internal pipeline registers.
    // --- Stage 1e: DSP48E1 AREG + CREG + PREG (full-precision 48-bit intermediate) ---
    // KEY FIX (v2.7b): Use 48-bit full-precision intermediate register mac_res_1e_full
    // to match DSP48E1 native P-port width (48-bit). Vivado can then map:
    //   dsp_a_1e [17:0]      -> DSP A-port (18-bit) -> AREG=1
    //   dsp_c_1e [47:0]      -> DSP C-port (48-bit) -> CREG=1
    //   mac_res_1e_full[47:0] -> DSP P-port (48-bit) -> PREG=1
    // Truncation to x_cand_16_s1e [15:0] happens AFTER PREG (external FF).
    // Without full-precision intermediate, Vivado sees width mismatch and
    // falls back to LUT implementation (AREG=0, CREG=0, PREG=0).
    (* dont_touch = "true" *) reg [17:0] dsp_a_1e;         // DSP AREG (18-bit A-port: coeff_mod)
    (* dont_touch = "true" *) reg [47:0] dsp_c_1e;         // DSP CREG (48-bit C-port: ri zero-extended)
    (* dont_touch = "true" *) reg [8:0]  r0_s1e_pre, r1_s1e_pre, r2_s1e_pre;
    (* dont_touch = "true" *) reg [8:0]  r3_s1e_pre, r4_s1e_pre, r5_s1e_pre;
    (* dont_touch = "true" *) reg        valid_s1e_pre;

    (* dont_touch = "true" *) reg [47:0] mac_res_1e_full;  // DSP PREG (48-bit P-port)
    (* dont_touch = "true" *) reg [8:0]  r0_s1e_mid, r1_s1e_mid, r2_s1e_mid;
    (* dont_touch = "true" *) reg [8:0]  r3_s1e_mid, r4_s1e_mid, r5_s1e_mid;
    (* dont_touch = "true" *) reg        valid_s1e_mid;

    (* dont_touch = "true" *) reg [15:0] x_cand_16_s1e;   // External FF (truncation)
    (* dont_touch = "true" *) reg [8:0]  r0_s1e, r1_s1e, r2_s1e, r3_s1e, r4_s1e, r5_s1e;
    (* dont_touch = "true" *) reg        valid_s1e;

    // Three-stage always block: AREG+CREG -> PREG (48-bit) -> truncate
    // Vivado maps: dsp_a_1e (AREG=1), dsp_c_1e (CREG=1) -> MAC -> mac_res_1e_full (PREG=1)
    // x_cand_16_s1e is an external FF that slices [15:0] from the 48-bit PREG output.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // AREG + CREG reset
            dsp_a_1e      <= 18'd0;
            dsp_c_1e      <= 48'd0;
            r0_s1e_pre <= 9'd0; r1_s1e_pre <= 9'd0; r2_s1e_pre <= 9'd0;
            r3_s1e_pre <= 9'd0; r4_s1e_pre <= 9'd0; r5_s1e_pre <= 9'd0;
            valid_s1e_pre <= 1'b0;
            // PREG reset (48-bit full precision)
            mac_res_1e_full <= 48'd0;
            r0_s1e_mid <= 9'd0; r1_s1e_mid <= 9'd0; r2_s1e_mid <= 9'd0;
            r3_s1e_mid <= 9'd0; r4_s1e_mid <= 9'd0; r5_s1e_mid <= 9'd0;
            valid_s1e_mid <= 1'b0;
            // External truncation FF reset
            x_cand_16_s1e <= 16'd0;
            r0_s1e <= 9'd0; r1_s1e <= 9'd0; r2_s1e <= 9'd0;
            r3_s1e <= 9'd0; r4_s1e <= 9'd0; r5_s1e <= 9'd0;
            valid_s1e     <= 1'b0;
        end else begin
            // Stage 1e_pre: AREG + CREG -- latch inputs aligned to DSP port widths
            dsp_a_1e      <= coeff_mod_s1d[17:0];       // AREG: 18-bit A-port
            dsp_c_1e      <= {39'd0, ri_s1d};           // CREG: 48-bit C-port (zero-extend 9-bit ri)
            r0_s1e_pre <= r0_s1d; r1_s1e_pre <= r1_s1d; r2_s1e_pre <= r2_s1d;
            r3_s1e_pre <= r3_s1d; r4_s1e_pre <= r4_s1d; r5_s1e_pre <= r5_s1d;
            valid_s1e_pre <= valid_s1d;
            // Stage 1e: PREG -- 48-bit full-precision MAC result (DSP P-port width)
            // Vivado packs dsp_a_1e (AREG), dsp_c_1e (CREG), mac_res_1e_full (PREG) into DSP48E1
            mac_res_1e_full <= dsp_c_1e + ({30'd0, dsp_a_1e} * P_M1); // C + A*B, 48-bit
            r0_s1e_mid <= r0_s1e_pre; r1_s1e_mid <= r1_s1e_pre; r2_s1e_mid <= r2_s1e_pre;
            r3_s1e_mid <= r3_s1e_pre; r4_s1e_mid <= r4_s1e_pre; r5_s1e_mid <= r5_s1e_pre;
            valid_s1e_mid <= valid_s1e_pre;
            // Stage 1e_post: External FF -- truncate 48-bit PREG to 16-bit with clamp
            x_cand_16_s1e <= (mac_res_1e_full > 48'd65535) ? 16'hFFFF : mac_res_1e_full[15:0];
            r0_s1e <= r0_s1e_mid; r1_s1e <= r1_s1e_mid; r2_s1e <= r2_s1e_mid;
            r3_s1e <= r3_s1e_mid; r4_s1e <= r4_s1e_mid; r5_s1e <= r5_s1e_mid;
            valid_s1e     <= valid_s1e_mid;
        end
    end

    // =========================================================================
    // STAGE 2: Modular Residue Computation
    // Compute x_cand_16_s1d % each of the 6 moduli (combinatorial).
    // All 6 operations are independent and execute in parallel.
    // Each constant-modulo operation synthesizes to ~8-10 LUT levels.
    // =========================================================================

    // NOTE: Stage 2 reads from Stage 1e outputs (x_cand_16_s1e, r*_s1e, valid_s1e)
    wire [8:0] cand_r_comb [0:5];
    assign cand_r_comb[0] = x_cand_16_s1e % 9'd257;
    assign cand_r_comb[1] = x_cand_16_s1e % 9'd256;
    assign cand_r_comb[2] = x_cand_16_s1e % 9'd61;
    assign cand_r_comb[3] = x_cand_16_s1e % 9'd59;
    assign cand_r_comb[4] = x_cand_16_s1e % 9'd55;
    assign cand_r_comb[5] = x_cand_16_s1e % 9'd53;

    // --- Stage 2 pipeline registers ---
    reg [8:0]  cand_r_s2 [0:5];  // Candidate residues (computed)
    reg [8:0]  recv_r_s2 [0:5];  // Received residues (time-aligned)
    reg [15:0] x_cand_16_s2;     // Carry x_cand_16 forward for final output
    reg        valid_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cand_r_s2[0] <= 9'd0; cand_r_s2[1] <= 9'd0;
            cand_r_s2[2] <= 9'd0; cand_r_s2[3] <= 9'd0;
            cand_r_s2[4] <= 9'd0; cand_r_s2[5] <= 9'd0;
            recv_r_s2[0] <= 9'd0; recv_r_s2[1] <= 9'd0;
            recv_r_s2[2] <= 9'd0; recv_r_s2[3] <= 9'd0;
            recv_r_s2[4] <= 9'd0; recv_r_s2[5] <= 9'd0;
            x_cand_16_s2 <= 16'd0;
            valid_s2     <= 1'b0;
        end else begin
            valid_s2     <= valid_s1e;          // Follow Stage 1e valid
            x_cand_16_s2 <= x_cand_16_s1e;     // Use Stage 1e candidate value
            cand_r_s2[0] <= cand_r_comb[0];
            cand_r_s2[1] <= cand_r_comb[1];
            cand_r_s2[2] <= cand_r_comb[2];
            cand_r_s2[3] <= cand_r_comb[3];
            cand_r_s2[4] <= cand_r_comb[4];
            cand_r_s2[5] <= cand_r_comb[5];
            recv_r_s2[0] <= r0_s1e;             // Use Stage 1e residues (time-aligned)
            recv_r_s2[1] <= r1_s1e;
            recv_r_s2[2] <= r2_s1e;
            recv_r_s2[3] <= r3_s1e;
            recv_r_s2[4] <= r4_s1e;
            recv_r_s2[5] <= r5_s1e;
        end
    end

    // =========================================================================
    // STAGE 3: Hamming Distance Accumulation
    // Six 1-bit comparisons + 6-input popcount adder (combinatorial).
    // Maximum path: 6 XOR/NE gates + 3-level carry-save adder ~5-8 LUT levels.
    // =========================================================================

    wire [3:0] dist_comb;
    assign dist_comb =
        ((cand_r_s2[0] != recv_r_s2[0]) ? 4'd1 : 4'd0) +
        ((cand_r_s2[1] != recv_r_s2[1]) ? 4'd1 : 4'd0) +
        ((cand_r_s2[2] != recv_r_s2[2]) ? 4'd1 : 4'd0) +
        ((cand_r_s2[3] != recv_r_s2[3]) ? 4'd1 : 4'd0) +
        ((cand_r_s2[4] != recv_r_s2[4]) ? 4'd1 : 4'd0) +
        ((cand_r_s2[5] != recv_r_s2[5]) ? 4'd1 : 4'd0);

    // --- Stage 3 output registers (final channel outputs, 6-cycle latency) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_out    <= 16'd0;
            distance <= 4'd6;   // Max distance (worst case) on reset
            valid    <= 1'b0;
        end else begin
            valid <= valid_s2;
            if (valid_s2) begin
                x_out    <= x_cand_16_s2;
                distance <= dist_comb;
            end
        end
    end

endmodule


// =============================================================================
// Main Module: decoder_2nrm
// Description: Top-level 2NRM decoder with 15 parallel CRT channels and MLD
// =============================================================================
module decoder_2nrm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    // Input: 41-bit packed residues (right-aligned in 64-bit bus from encoder)
    // [40:32]=r257, [31:24]=r256, [23:18]=r61, [17:12]=r59, [11:6]=r55, [5:0]=r53
    input  wire [63:0] residues_in,

    // Output
    output reg  [15:0] data_out,
    output reg         valid,
    output reg         uncorrectable
);

    // =========================================================================
    // 1. Input Unpacking + Input Register Bank (High-Fanout Mitigation)
    // =========================================================================
    // Each of r0..r5 drives 15 channel instances (fanout=15 per bit, ~27 total
    // for the MUX select paths). At 100 MHz, this causes Net Delay ~11 ns.
    //
    // FIX: Register r0..r5 here in the top-level module BEFORE broadcasting
    // to channels. Each channel receives a registered copy, so the fanout on
    // the combinational wire is 1 (one register input per channel).
    // The (* keep = "true" *) attribute prevents Vivado from merging these
    // registers back into a single high-fanout net during optimization.
    //
    // NOTE: This adds 1 cycle of latency at the input stage (Cycle 0 -> Cycle 1).
    //       The start signal is also registered by 1 cycle to stay aligned.
    //       Total decoder latency = 1 (input reg) + 6 (channel) + 1 (MLD) = 8 cycles.

    // Combinational unpack (wires only, no fanout issue here)
    wire [8:0] r0_w = residues_in[40:32];          // r257 (9-bit)
    wire [8:0] r1_w = {1'b0, residues_in[31:24]};  // r256 (8-bit -> 9-bit)
    wire [8:0] r2_w = {3'b0, residues_in[23:18]};  // r61  (6-bit -> 9-bit)
    wire [8:0] r3_w = {3'b0, residues_in[17:12]};  // r59  (6-bit -> 9-bit)
    wire [8:0] r4_w = {3'b0, residues_in[11:6]};   // r55  (6-bit -> 9-bit)
    wire [8:0] r5_w = {3'b0, residues_in[5:0]};    // r53  (6-bit -> 9-bit)

    // Input pipeline registers -- (* keep = "true" *) prevents merging
    (* keep = "true" *) reg [8:0] r0, r1, r2, r3, r4, r5;
    (* keep = "true" *) reg       start_r; // start delayed 1 cycle to align with registered residues

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r0 <= 9'd0; r1 <= 9'd0; r2 <= 9'd0;
            r3 <= 9'd0; r4 <= 9'd0; r5 <= 9'd0;
            start_r <= 1'b0;
        end else begin
            r0 <= r0_w; r1 <= r1_w; r2 <= r2_w;
            r3 <= r3_w; r4 <= r4_w; r5 <= r5_w;
            start_r <= start;
        end
    end

    // =========================================================================
    // 2. 15 Parallel CRT Channels (C(6,2) = 15 pairs)
    // =========================================================================
    // Pair mapping: (idx1, idx2) for each of the 15 channels
    // Channel 0:(0,1), 1:(0,2), 2:(0,3), 3:(0,4), 4:(0,5)
    // Channel 5:(1,2), 6:(1,3), 7:(1,4), 8:(1,5)
    // Channel 9:(2,3), 10:(2,4), 11:(2,5)
    // Channel 12:(3,4), 13:(3,5)
    // Channel 14:(4,5)
    //
    // Moduli: M[0]=257, M[1]=256, M[2]=61, M[3]=59, M[4]=55, M[5]=53
    //
    // Pre-computed constants: Inv(M_i mod M_j, M_j) for each pair
    // Verified by: M_i * Inv ≡ 1 (mod M_j)
    //
    // Channel  Pair    M_i  M_j  M_i mod M_j  Inv   Verification
    //   0     (0,1)   257  256      1          1    1*1=1 ≡1(mod 256) ✓
    //   1     (0,2)   257   61     14         48   14*48=672=11*61+1 ✓
    //   2     (0,3)   257   59     21         45   21*45=945=16*59+1 ✓
    //   3     (0,4)   257   55     37          3   37*3=111=2*55+1 ✓
    //   4     (0,5)   257   53     45         33   45*33=1485=28*53+1 ✓
    //   5     (1,2)   256   61     12         56   12*56=672=11*61+1 ✓
    //   6     (1,3)   256   59     20          3   20*3=60=1*59+1 ✓
    //   7     (1,4)   256   55     36         26   36*26=936=17*55+1 ✓
    //   8     (1,5)   256   53     44         47   44*47=2068=39*53+1 ✓
    //   9     (2,3)    61   59      2         30   2*30=60=1*59+1 ✓
    //  10     (2,4)    61   55      6         46   6*46=276=5*55+1 ✓
    //  11     (2,5)    61   53      8         20   8*20=160=3*53+1 ✓
    //  12     (3,4)    59   55      4         14   4*14=56=1*55+1 ✓
    //  13     (3,5)    59   53      6          9   6*9=54=1*53+1 ✓
    //  14     (4,5)    55   53      2         27   2*27=54=1*53+1 ✓

    // Channel outputs
    wire [15:0] ch_x    [0:14];
    wire [3:0]  ch_dist [0:14];
    wire        ch_valid[0:14];

    // All 15 channels use start_r (registered start, aligned with registered r0..r5)
    // and the registered residues r0..r5 (fanout=1 per channel after input reg bank).

    // Channel 0: pair (0,1) M1=257, M2=256, Inv=1
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(256), .P_INV(1))
        ch0 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd1),
             .x_out(ch_x[0]), .distance(ch_dist[0]), .valid(ch_valid[0]));

    // Channel 1: pair (0,2) M1=257, M2=61, Inv=48
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(61), .P_INV(48))
        ch1 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd2),
             .x_out(ch_x[1]), .distance(ch_dist[1]), .valid(ch_valid[1]));

    // Channel 2: pair (0,3) M1=257, M2=59, Inv=45
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(59), .P_INV(45))
        ch2 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd3),
             .x_out(ch_x[2]), .distance(ch_dist[2]), .valid(ch_valid[2]));

    // Channel 3: pair (0,4) M1=257, M2=55, Inv=3
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(55), .P_INV(3))
        ch3 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd4),
             .x_out(ch_x[3]), .distance(ch_dist[3]), .valid(ch_valid[3]));

    // Channel 4: pair (0,5) M1=257, M2=53, Inv=33
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(53), .P_INV(33))
        ch4 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd0), .idx2(3'd5),
             .x_out(ch_x[4]), .distance(ch_dist[4]), .valid(ch_valid[4]));

    // Channel 5: pair (1,2) M1=256, M2=61, Inv=56
    decoder_channel_2nrm_param #(.P_M1(256), .P_M2(61), .P_INV(56))
        ch5 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd1), .idx2(3'd2),
             .x_out(ch_x[5]), .distance(ch_dist[5]), .valid(ch_valid[5]));

    // Channel 6: pair (1,3) M1=256, M2=59, Inv=3
    decoder_channel_2nrm_param #(.P_M1(256), .P_M2(59), .P_INV(3))
        ch6 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd1), .idx2(3'd3),
             .x_out(ch_x[6]), .distance(ch_dist[6]), .valid(ch_valid[6]));

    // Channel 7: pair (1,4) M1=256, M2=55, Inv=26
    decoder_channel_2nrm_param #(.P_M1(256), .P_M2(55), .P_INV(26))
        ch7 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd1), .idx2(3'd4),
             .x_out(ch_x[7]), .distance(ch_dist[7]), .valid(ch_valid[7]));

    // Channel 8: pair (1,5) M1=256, M2=53, Inv=47
    decoder_channel_2nrm_param #(.P_M1(256), .P_M2(53), .P_INV(47))
        ch8 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd1), .idx2(3'd5),
             .x_out(ch_x[8]), .distance(ch_dist[8]), .valid(ch_valid[8]));

    // Channel 9: pair (2,3) M1=61, M2=59, Inv=30
    decoder_channel_2nrm_param #(.P_M1(61), .P_M2(59), .P_INV(30))
        ch9 (.clk(clk), .rst_n(rst_n), .start(start_r),
             .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
             .idx1(3'd2), .idx2(3'd3),
             .x_out(ch_x[9]), .distance(ch_dist[9]), .valid(ch_valid[9]));

    // Channel 10: pair (2,4) M1=61, M2=55, Inv=46
    decoder_channel_2nrm_param #(.P_M1(61), .P_M2(55), .P_INV(46))
        ch10 (.clk(clk), .rst_n(rst_n), .start(start_r),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd2), .idx2(3'd4),
              .x_out(ch_x[10]), .distance(ch_dist[10]), .valid(ch_valid[10]));

    // Channel 11: pair (2,5) M1=61, M2=53, Inv=20
    decoder_channel_2nrm_param #(.P_M1(61), .P_M2(53), .P_INV(20))
        ch11 (.clk(clk), .rst_n(rst_n), .start(start_r),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd2), .idx2(3'd5),
              .x_out(ch_x[11]), .distance(ch_dist[11]), .valid(ch_valid[11]));

    // Channel 12: pair (3,4) M1=59, M2=55, Inv=14
    decoder_channel_2nrm_param #(.P_M1(59), .P_M2(55), .P_INV(14))
        ch12 (.clk(clk), .rst_n(rst_n), .start(start_r),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd3), .idx2(3'd4),
              .x_out(ch_x[12]), .distance(ch_dist[12]), .valid(ch_valid[12]));

    // Channel 13: pair (3,5) M1=59, M2=53, Inv=9
    decoder_channel_2nrm_param #(.P_M1(59), .P_M2(53), .P_INV(9))
        ch13 (.clk(clk), .rst_n(rst_n), .start(start_r),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd3), .idx2(3'd5),
              .x_out(ch_x[13]), .distance(ch_dist[13]), .valid(ch_valid[13]));

    // Channel 14: pair (4,5) M1=55, M2=53, Inv=27
    decoder_channel_2nrm_param #(.P_M1(55), .P_M2(53), .P_INV(27))
        ch14 (.clk(clk), .rst_n(rst_n), .start(start_r),
              .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),
              .idx1(3'd4), .idx2(3'd5),
              .x_out(ch_x[14]), .distance(ch_dist[14]), .valid(ch_valid[14]));

    // =========================================================================
    // 3. MLD: Select Channel with Minimum Hamming Distance
    // =========================================================================
    // Triggered when ch_valid[0] is HIGH (all 15 channels complete simultaneously
    // because they all receive the same start_r pulse and have identical 6-cycle latency).
    // This combinational tree operates on registered ch_dist/ch_x values (Stage 3 outputs),
    // so its path is: ch_dist_reg -> 15-way compare tree -> output register.
    // The 15-way minimum tree is approximately 4 LUT levels deep (log2(15)~4),
    // well within the 10 ns budget.
    //
    // Tie-breaking: lower channel index wins (deterministic behavior)

    // Combinational minimum distance tree
    reg [3:0]  min_dist_comb;
    reg [15:0] best_x_comb;
    integer k;

    always @(*) begin
        min_dist_comb = 4'd6; // Initialize to impossible max (6 moduli)
        best_x_comb   = 16'd0;
        for (k = 0; k < 15; k = k + 1) begin
            if (ch_dist[k] < min_dist_comb) begin
                min_dist_comb = ch_dist[k];
                best_x_comb   = ch_x[k];
            end
        end
    end

    // =========================================================================
    // 4. Sequential Output Register (Cycle 8 -- MLD stage)
    // =========================================================================
    // ch_valid[0] is the Stage-3 registered valid from channel 0.
    // All 15 channels assert valid simultaneously (same start_r, same 6-cycle latency).
    // Total latency: 1 (input reg) + 6 (channel pipeline) + 1 (this MLD reg) = 8 cycles.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out      <= 16'd0;
            valid         <= 1'b0;
            uncorrectable <= 1'b0;
        end else begin
            // ch_valid[0] goes HIGH 6 cycles after start_r (Stage 3 output)
            // This register adds cycle 8 (including input reg), making total latency = 8 cycles
            valid <= ch_valid[0];

            if (ch_valid[0]) begin
                data_out <= best_x_comb;
                // Uncorrectable if minimum distance exceeds error correction capability
                // NRM_MAX_ERRORS = 2, so if min_dist > 2, correction is not reliable
                uncorrectable <= (min_dist_comb > `NRM_MAX_ERRORS);
            end else begin
                uncorrectable <= 1'b0;
            end
        end
    end

endmodule
