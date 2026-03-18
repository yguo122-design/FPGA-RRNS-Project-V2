// =============================================================================
// File: decoder_2nrm.v
// Description: 2NRM Decoder with MLD (Maximum Likelihood Decoding)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.3
// Version: v2.16 -- STAGE 2 THREE-WAY PIPELINE SPLIT (2+2+2)
//                   v2.15 timing report showed Slack = -1.688ns on the path:
//                     ch13/x_cand_16_s2a_reg[1]/C -> ch13/cand_r_s2_reg[4][4]/D
//                   Logic Delay = 5.846ns (CARRY4=8), Route Delay = 5.700ns
//                   x_cand_16_s2a[1] had fo=40 (dont_touch prevented replication)
//
//                   ROOT CAUSE: v2.15 split Stage 2 into 3+3 (two sub-stages), but
//                   each sub-stage still computes 3 modulo operations on a 16-bit
//                   input. Each modulo generates ~8 CARRY4 stages (~5.8ns logic
//                   delay), still exceeding the 10ns budget. The 3+3 split was
//                   insufficient because the per-modulo CARRY4 count did not change.
//                   Additionally, x_cand_16_s2a had dont_touch="true" preventing
//                   register replication (fo=40, route delay 0.979ns).
//
//                   FIX: Split Stage 2 into THREE pipeline sub-stages (2+2+2):
//                     Stage 2a [new]: Compute % 257, % 256 (2 moduli)
//                       -> cand_r_s2a[0..1], forward x_cand_16_s2a, recv_r_s2a
//                     Stage 2b [new]: Compute % 61, % 59 (2 moduli)
//                       -> cand_r_s2b[2..3], forward x_cand_16_s2b, recv_r_s2b
//                     Stage 2c [new]: Compute % 55, % 53 (2 moduli)
//                       -> cand_r_s2[4..5], merge all into final cand_r_s2[0..5]
//                   Each sub-stage has at most 2 modulo operations -> ~4-5 CARRY4
//                   per critical path -> logic delay ~2.5ns per stage.
//                   All intermediate x_cand_16 registers use max_fanout=8 (not
//                   dont_touch) to allow Vivado to replicate and reduce route delay.
//                   Total Stage 2 latency: 3 cycles (was 2 cycles in v2.15).
//                   Total decoder latency increases by 1 more cycle (absorbed by
//                   DEC_WAIT). This fix applies uniformly to all 15 channels since
//                   they share the same decoder_channel_2nrm_param module.
//
// Version: v2.15 -- STAGE 2 PIPELINE SPLIT + x_cand_16_s1e FANOUT FIX
//                   v2.14 timing report showed Slack = -1.357ns on the path:
//                     ch9/x_cand_16_s1e_reg[3]/C -> ch9/cand_r_s2_reg[4][2]/D
//                   Logic Delay = 5.584ns (CARRY4=10), Route Delay = 5.803ns
//                   x_cand_16_s1e[3] had fo=70 (dont_touch prevented replication)
//
//                   ROOT CAUSE 1 (primary): Stage 2 computes 6 constant-modulo
//                   operations (% 257, % 256, % 61, % 59, % 55, % 53) on a 16-bit
//                   input in a single clock cycle. Each modulo generates ~10 CARRY4
//                   stages (~5.6ns logic delay), exceeding the 10ns budget.
//
//                   ROOT CAUSE 2 (secondary): x_cand_16_s1e had dont_touch="true"
//                   which prevented Vivado from replicating the register to reduce
//                   fanout. With fo=70, the first net alone consumed 1.155ns route
//                   delay.
//
//                   FIX 1: Remove dont_touch from x_cand_16_s1e, replace with
//                   max_fanout=8. Vivado will replicate the register (~9 copies for
//                   fo=70), reducing per-copy fanout to ~8 and route delay to ~0.3ns.
//
//                   FIX 2: Split Stage 2 into two pipeline sub-stages:
//                     Stage 2a [new]: Compute cand_r_comb[0..2] (% 257, % 256, % 61)
//                       and register into cand_r_s2a[0..2]. Also register x_cand_16
//                       and recv_r for Stage 2b alignment.
//                     Stage 2b [new]: Compute cand_r_comb[3..5] (% 59, % 55, % 53)
//                       and register into cand_r_s2[3..5]. Merge with cand_r_s2a
//                       into final cand_r_s2[0..5].
//                   Each sub-stage has at most 3 modulo operations -> ~3-4 CARRY4
//                   per critical path -> logic delay ~2ns per stage.
//                   Total Stage 2 latency: 2 cycles (was 1 cycle in v2.14).
//                   Total decoder latency increases by 1 cycle (absorbed by DEC_WAIT).
//
// Version: v2.14 -- STAGE 1a/1b BIT-WIDTH FIX: Reduce diff_raw_s1a (18->9 bit) and
//                   diff_mod_s1b (18->8 bit) to eliminate redundant CARRY4 stages.
//
//                   v2.13 timing report showed Slack = -0.845ns on the path:
//                     ch11/diff_raw_s1a_reg[3]/C -> ch11/diff_mod_s1b_reg[3]/D
//                   Logic Delay = 5.004ns (CARRY4=6), Route Delay = 5.705ns
//
//                   ROOT CAUSE: diff_raw_s1a was declared as 18-bit, but the
//                   mathematical upper bound is only 511 (9-bit):
//                     diff_raw = rj + P_M2 - ri
//                     rj  <= P_M2-1 <= 255  (8-bit)
//                     P_M2 <= 256           (9-bit)
//                     ri  >= 0
//                     diff_raw_max = 255 + 256 - 0 = 511 < 2^9 = 512
//                   Bits [17:9] of diff_raw_s1a are always 0 (9 redundant bits).
//                   Vivado synthesized a full 18-bit constant-modulo circuit for
//                   Stage 1b (diff_raw_s1a % P_M2), generating 6 CARRY4 stages.
//
//                   Similarly, diff_mod_s1b = diff_raw % P_M2 <= P_M2-1 <= 255,
//                   so 8-bit is sufficient (was 18-bit, 10 redundant bits).
//
//                   FIX:
//                     diff_raw wire:    [17:0] -> [8:0]  (9-bit, max 511)
//                     diff_raw_s1a reg: [17:0] -> [8:0]  (9-bit)
//                     diff_mod_1b wire: [17:0] -> [7:0]  (8-bit, max P_M2-1=255)
//                     diff_mod_s1b reg: [17:0] -> [7:0]  (8-bit)
//                   Stage 1b modulo circuit now operates on 9-bit input ->
//                   ~1-2 CARRY4 stages (~1.5ns logic delay).
//                   Expected Slack improvement: -0.845ns -> >= 0ns.
//
//                   NOTE: diff_mod_s1b feeds into DSP A-port (25-bit) via zero-extension.
//                   The zero-extension in dsp1c_a_in changes from {7'd0, diff_mod_s1b[17:0]}
//                   to {17'd0, diff_mod_s1b[7:0]} (same 25-bit result, different padding).
//
// Version: v2.13 -- MLD PIPELINE FIX: Split 15-way minimum distance tree into two
//                   registered pipeline stages to eliminate 10.313ns route delay.
//
//                   v2.12 timing report showed Slack = -2.737ns on the path:
//                     ch0/distance_reg[2]/C -> data_out_reg[3]/D
//                   Route Delay = 10.313ns (81% of total), Logic Levels = 15
//
//                   ROOT CAUSE: The MLD for-loop:
//                     for (k = 0; k < 15; k++) if (ch_dist[k] < min_dist_comb) ...
//                   Verilog for-loop sequential semantics force Vivado to synthesize
//                   a 15-level serial priority chain (ch0->ch1->...->ch14), NOT a
//                   balanced log2(15)~4-level tree as the comment claimed. Each level
//                   crosses different SLICEs, accumulating 10.313ns route delay.
//
//                   FIX: Split MLD into two registered pipeline stages (v2.13):
//                     Stage MLD-A [new]: Two parallel for-loops over ch0~ch7 and
//                       ch8~ch14, each finding a partial minimum. Results stored in
//                       registered mid_dist_a/mid_x_a and mid_dist_b/mid_x_b.
//                       Each loop is at most 8 levels -> route delay ~4-5ns.
//                     Stage MLD-B [new]: Final comparison of mid_a vs mid_b,
//                       output data_out/valid/uncorrectable.
//                   Total MLD latency: 2 cycles (was 1 cycle in v2.12).
//                   Total decoder latency increases by 1 cycle (absorbed by DEC_WAIT).
//
// Version: v2.12 -- CRITICAL PATH FIX: coeff_raw_s1c bit-width reduction (36-bit -> 14-bit)
//                   v2.11 timing report showed Slack = -3.803ns on the path:
//                     coeff_raw_s1c_reg[4]/C -> coeff_mod_s1d_reg[3]/D
//                   Logic Delay = 7.149ns (24 logic levels: CARRY4=12, LUT=12)
//
//                   ROOT CAUSE: coeff_raw_s1c was declared as 36-bit (truncated from
//                   48-bit DSP P output). Stage 1d computes coeff_raw_s1c % P_M2, and
//                   Vivado synthesized a full 36-bit constant-modulo circuit, generating
//                   12 CARRY4 stages (~7ns logic delay). Additionally, coeff_raw_s1c[4]
//                   had fanout=44 (vs max_fanout=16), causing 0.842ns route delay on
//                   the first net alone.
//
//                   MATHEMATICAL PROOF that 14-bit is sufficient:
//                     diff_mod_s1b range: 0 ~ (P_M2 - 1), P_M2_max = 256 -> max = 255 (8-bit)
//                     P_INV range: max value across all 15 channels = 56 (6-bit)
//                     coeff_raw = diff_mod * P_INV <= 255 * 56 = 14,280 < 2^14 = 16,384
//                     Therefore: coeff_raw_s1c[13:0] is sufficient; bits [35:14] are always 0.
//
//                   FIX: Change coeff_raw_s1c from reg[35:0] to reg[13:0], and truncate
//                   DSP output at dsp1c_p_out[13:0] instead of dsp1c_p_out[35:0].
//                   Stage 1d modulo circuit now operates on 14-bit input -> ~3-4 CARRY4
//                   stages (~2ns logic delay). Expected Slack improvement: +5.8ns -> >= 0ns.
//
//                   Stage 1c DSP48E1 configuration (unchanged from v2.11):
//                     OPMODE = 7'b0000101  (P = A * B)
//                     ALUMODE = 4'b0000    (addition)
//                     A_INPUT = "DIRECT", B_INPUT = "DIRECT"
//                     AREG=1, BREG=1, MREG=1, PREG=1  (4-stage pipeline)
//                     Pipeline: A/B -> AREG/BREG -> MULT -> MREG -> PREG -> P
//
//                   Stage 1e DSP48E1 configuration (unchanged from v2.11):
//                     OPMODE = 7'b0110101  (P = C + A * B, MAC mode)
//                     ALUMODE = 4'b0000    (addition)
//                     A_INPUT = "DIRECT", B_INPUT = "DIRECT"
//                     AREG=1, BREG=1, CREG=1, MREG=1, PREG=1  (5-stage pipeline)
//                     Pipeline: A/B/C -> AREG/BREG/CREG -> MULT+ADD -> MREG -> PREG -> P
//
//                   LATENCY IMPACT: None. Pipeline stage count unchanged from v2.11.
//                   auto_scan_engine DEC_WAIT polls dec_valid, unaffected.
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
    //
    // v2.14 BIT-WIDTH FIX: diff_raw reduced from 18-bit to 9-bit.
    // Mathematical proof:
    //   rj  <= P_M2 - 1 <= 255  (8-bit)
    //   P_M2 <= 256              (9-bit)
    //   ri  >= 0
    //   diff_raw_max = 255 + 256 - 0 = 511 < 2^9 = 512
    //   => bits [17:9] are always 0; only [8:0] carry valid data.
    // With 9-bit input, Stage 1b modulo circuit uses ~1-2 CARRY4 vs 6 CARRY4 before.
    wire [8:0] diff_raw;
    assign diff_raw = rj + P_M2[8:0] - ri;  // 9-bit: max = 255+256-0 = 511 < 512

    // --- Stage 1a pipeline registers ---
    // (* dont_touch = "true" *) prevents Vivado from merging this stage with
    // Stage 1b (which would recreate the long diff_raw->diff_mod chain).
    (* dont_touch = "true" *) reg [8:0]  diff_raw_s1a;  // v2.14: was [17:0]
    (* dont_touch = "true" *) reg [8:0]  ri_s1a;
    (* dont_touch = "true" *) reg [8:0]  r0_s1a, r1_s1a, r2_s1a, r3_s1a, r4_s1a, r5_s1a;
    (* dont_touch = "true" *) reg        valid_s1a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_raw_s1a <= 9'd0;
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

    // v2.14 BIT-WIDTH FIX: diff_mod_1b reduced from 18-bit to 8-bit.
    // diff_mod = diff_raw_s1a % P_M2 <= P_M2 - 1 <= 255 < 2^8 = 256
    // 8-bit is sufficient; was 18-bit (10 redundant bits).
    wire [7:0] diff_mod_1b;
    assign diff_mod_1b = diff_raw_s1a % P_M2;  // 8-bit: max = P_M2-1 <= 255

    // --- Stage 1b pipeline registers ---
    // dont_touch: prevents Vivado from merging Stage 1b with 1c.
    // max_fanout=4: diff_mod_s1b drives Stage 1c DSP A-port in all 15 channel instances;
    //   Vivado must replicate this register (fanout<=4) to reduce Net Delay.
    //   NOTE: set_max_fanout in XDC is NOT supported ([Designutils 20-1307]);
    //         this in-code attribute is the correct method.
    // v2.14: reduced from [17:0] to [7:0] (8-bit, max P_M2-1 = 255)
    (* dont_touch = "true", max_fanout = 4 *) reg [7:0] diff_mod_s1b;
    (* dont_touch = "true" *) reg [8:0]  ri_s1b;
    (* dont_touch = "true" *) reg [8:0]  r0_s1b, r1_s1b, r2_s1b, r3_s1b, r4_s1b, r5_s1b;
    (* dont_touch = "true" *) reg        valid_s1b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_mod_s1b <= 8'd0;
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
    // STAGE 1c: Manual DSP48E1 Instantiation (v2.11)
    // Operation: coeff_raw = diff_mod_s1b * P_INV
    //
    // All inference-based approaches (v2.6~v2.10b) failed to pack AREG/MREG/PREG.
    // Solution: Manually instantiate DSP48E1 with explicit pipeline configuration.
    //
    // DSP48E1 Pipeline (4 stages, 3 clock cycles from input to P output):
    //   Cycle N:   A/B inputs sampled by fabric registers (pre-DSP)
    //   Cycle N+1: AREG/BREG latch A/B inside DSP
    //   Cycle N+2: MREG latches A*B product inside DSP
    //   Cycle N+3: PREG latches final result inside DSP -> P output
    //
    // OPMODE = 7'b0000101: P = A * B (multiply only, no accumulate)
    // ALUMODE = 4'b0000:   Z + W + X + Y + CIN (standard addition)
    // =========================================================================

    // --- Stage 1c: Fabric input registers (feed into DSP A/B ports) ---
    // These are fabric FFs that drive the DSP A and B input ports.
    // The DSP's internal AREG/BREG will then latch these on the next cycle.
    (* dont_touch = "true" *) reg [24:0] dsp1c_a_in;  // 25-bit A-port input (zero-extended)
    (* dont_touch = "true" *) reg [17:0] dsp1c_b_in;  // 18-bit B-port input (P_INV)
    (* dont_touch = "true" *) reg [8:0]  ri_s1c_pre;
    (* dont_touch = "true" *) reg [8:0]  r0_s1c_pre, r1_s1c_pre, r2_s1c_pre;
    (* dont_touch = "true" *) reg [8:0]  r3_s1c_pre, r4_s1c_pre, r5_s1c_pre;
    (* dont_touch = "true" *) reg        valid_s1c_pre;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dsp1c_a_in    <= 25'd0;
            dsp1c_b_in    <= 18'd0;
            ri_s1c_pre    <= 9'd0;
            r0_s1c_pre <= 9'd0; r1_s1c_pre <= 9'd0; r2_s1c_pre <= 9'd0;
            r3_s1c_pre <= 9'd0; r4_s1c_pre <= 9'd0; r5_s1c_pre <= 9'd0;
            valid_s1c_pre <= 1'b0;
        end else begin
            // Zero-extend 8-bit diff_mod_s1b to 25-bit DSP A-port
            // v2.14: diff_mod_s1b is now [7:0] (8-bit), zero-extend with 17 bits
            dsp1c_a_in    <= {17'd0, diff_mod_s1b[7:0]};
            // P_INV loaded into 18-bit DSP B-port
            dsp1c_b_in    <= P_INV[17:0];
            ri_s1c_pre    <= ri_s1b;
            r0_s1c_pre <= r0_s1b; r1_s1c_pre <= r1_s1b; r2_s1c_pre <= r2_s1b;
            r3_s1c_pre <= r3_s1b; r4_s1c_pre <= r4_s1b; r5_s1c_pre <= r5_s1b;
            valid_s1c_pre <= valid_s1b;
        end
    end

    // --- Stage 1c: DSP48E1 output wire ---
    wire [47:0] dsp1c_p_out;  // 48-bit P output from DSP48E1

    // --- Stage 1c: Manual DSP48E1 instantiation ---
    // AREG=1, BREG=1: latch A/B inputs inside DSP (1 cycle)
    // MREG=1: latch multiplier output inside DSP (1 cycle)
    // PREG=1: latch final result inside DSP (1 cycle)
    // Total DSP internal pipeline: 3 cycles (AREG -> MREG -> PREG)
    DSP48E1 #(
        // Feature control
        .USE_MULT    ("MULTIPLY"),  // Use multiplier
        .USE_SIMD    ("ONE48"),     // Single 48-bit operation
        .USE_DPORT   ("FALSE"),     // No D-port pre-adder
        // Pipeline register configuration (KEY: all enabled)
        .AREG        (1),           // 1 pipeline register on A input -> AREG
        .BREG        (1),           // 1 pipeline register on B input -> BREG
        .CREG        (0),           // No C register (not used in multiply)
        .DREG        (1),           // D register (tied off)
        .MREG        (1),           // 1 pipeline register on multiplier output -> MREG
        .PREG        (1),           // 1 pipeline register on P output -> PREG
        .ADREG       (1),           // A+D pre-adder register
        .ACASCREG    (1),           // Cascade register matches AREG
        .BCASCREG    (1),           // Cascade register matches BREG
        // Data width
        .A_INPUT     ("DIRECT"),    // A input from fabric (not cascade)
        .B_INPUT     ("DIRECT"),    // B input from fabric (not cascade)
        // Initialization
        .AUTORESET_PATDET("NO_RESET"),
        .MASK        (48'h3fffffffffff),
        .PATTERN     (48'h000000000000),
        .SEL_MASK    ("MASK"),
        .SEL_PATTERN ("PATTERN"),
        .USE_PATTERN_DETECT("NO_PATDET")
    ) u_dsp_1c (
        .CLK         (clk),
        // Control signals
        .OPMODE      (7'b0000101),  // P = A * B
        .ALUMODE     (4'b0000),     // Z + W + X + Y (standard add)
        .CARRYINSEL  (3'b000),
        // Clock enables (all enabled) — standard DSP48E1 CE ports
        // CEAD: CE for A+D pre-adder register (ADREG). USE_DPORT=FALSE so ADREG is
        //       bypassed and CEAD has no functional effect, but must be connected to
        //       avoid [Synth 8-7071] unconnected port warning.
        .CEA1        (1'b1), .CEA2        (1'b1),
        .CEB1        (1'b1), .CEB2        (1'b1),
        .CEC         (1'b1), .CED         (1'b1),
        .CEM         (1'b1), .CEP         (1'b1),
        .CECTRL      (1'b1), .CEINMODE    (1'b1),
        .CEAD        (1'b1),         // CE for ADREG (USE_DPORT=FALSE, no functional effect)
        // Synchronous resets (active high, tied low — we use async rst_n externally)
        .RSTA        (1'b0), .RSTB        (1'b0),
        .RSTC        (1'b0), .RSTD        (1'b0),
        .RSTM        (1'b0), .RSTP        (1'b0),
        .RSTALLCARRYIN(1'b0), .RSTALUMODE (1'b0),
        .RSTCTRL     (1'b0), .RSTINMODE   (1'b0),
        // Data inputs
        .A           (dsp1c_a_in),  // 25-bit A input (zero-extended diff_mod)
        .B           (dsp1c_b_in),  // 18-bit B input (P_INV)
        .C           (48'd0),       // C not used
        .D           (25'd0),       // D not used (USE_DPORT=FALSE)
        .CARRYIN     (1'b0),
        .INMODE      (5'b00000),    // Standard mode: A2->A, B2->B
        // Cascade inputs (not used)
        .ACIN        (30'd0), .BCIN        (18'd0),
        .PCIN        (48'd0), .CARRYCASCIN (1'b0),
        .MULTSIGNIN  (1'b0),
        // Outputs
        .P           (dsp1c_p_out), // 48-bit result: diff_mod * P_INV
        // Unused outputs
        .ACOUT       (), .BCOUT       (),
        .PCOUT       (), .CARRYCASCOUT(),
        .MULTSIGNOUT (), .OVERFLOW    (),
        .UNDERFLOW   (), .PATTERNDETECT(),
        .PATTERNBDETECT(), .CARRYOUT  ()
    );

    // --- Stage 1c: Output pipeline registers (after DSP PREG) ---
    // The DSP PREG output (dsp1c_p_out) is already registered inside the DSP.
    // We add fabric FFs here to:
    //   1. Truncate 48-bit result to 36-bit (coeff_raw_s1c)
    //   2. Propagate side-channel signals (ri, r0..r5, valid) with matching latency
    //
    // DSP pipeline adds 3 cycles (AREG+MREG+PREG), so side-channel signals
    // need 3 additional pipeline stages to stay aligned.
    // We already have 1 stage (dsp1c_a_in block above), so we need 2 more here.

    // Side-channel pipeline stage 2 (aligns with DSP MREG output)
    (* dont_touch = "true" *) reg [8:0]  ri_s1c_p2;
    (* dont_touch = "true" *) reg [8:0]  r0_s1c_p2, r1_s1c_p2, r2_s1c_p2;
    (* dont_touch = "true" *) reg [8:0]  r3_s1c_p2, r4_s1c_p2, r5_s1c_p2;
    (* dont_touch = "true" *) reg        valid_s1c_p2;

    // Side-channel pipeline stage 3 (aligns with DSP MREG output, Cycle N+2)
    // NOTE: This stage propagates side-channel signals only.
    //       coeff_raw_s1c is NOT latched here — it comes from DSP PREG (Cycle N+3).
    (* dont_touch = "true" *) reg [8:0]  ri_s1c_p3;
    (* dont_touch = "true" *) reg [8:0]  r0_s1c_p3, r1_s1c_p3, r2_s1c_p3;
    (* dont_touch = "true" *) reg [8:0]  r3_s1c_p3, r4_s1c_p3, r5_s1c_p3;
    (* dont_touch = "true" *) reg        valid_s1c_p3;

    // Side-channel pipeline stage 4 + DSP output truncation (aligns with DSP PREG output)
    //
    // BUG FIX #30: DSP48E1 with AREG=1, MREG=1, PREG=1 has 3 internal pipeline
    // stages PLUS 1 fabric input register = 4 total cycles from diff_mod_s1b to
    // dsp1c_p_out:
    //   Cycle N:   dsp1c_a_in <= diff_mod_s1b  (fabric input register)
    //   Cycle N+1: DSP AREG latches A/B
    //   Cycle N+2: DSP MREG latches A*B
    //   Cycle N+3: DSP PREG latches result → dsp1c_p_out valid
    //
    // The original code had only 3 side-channel pipeline stages (p2, p3 in the
    // same always block as coeff_raw_s1c), making valid_s1c arrive 1 cycle EARLY
    // relative to coeff_raw_s1c. Stage 1d then computed coeff_raw_s1c % P_M2
    // using the PREVIOUS cycle's coeff_raw_s1c value, producing wrong results.
    //
    // FIX: Add a 4th side-channel pipeline stage (p3) so that valid_s1c is
    // registered in the SAME always block as coeff_raw_s1c (both at Cycle N+3).
    // This ensures valid_s1c and coeff_raw_s1c are always time-aligned.
    //
    // v2.12 BIT-WIDTH FIX: coeff_raw_s1c reduced from 36-bit to 14-bit.
    //   diff_mod(<=255) * P_INV(<=56) = 14,280 < 2^14 → bits [47:14] always 0.
    (* dont_touch = "true", max_fanout = 16 *) reg [13:0] coeff_raw_s1c;
    (* dont_touch = "true" *) reg [8:0]  ri_s1c;
    (* dont_touch = "true" *) reg [8:0]  r0_s1c, r1_s1c, r2_s1c, r3_s1c, r4_s1c, r5_s1c;
    (* dont_touch = "true" *) reg        valid_s1c;

    // Stage 2 always block (Cycle N+1): side-channel propagation from pre to p2.
    // BUG FIX #32: When Bug #31 separated Stage 3(p3) and Stage 4 into independent
    // always blocks, the Stage 2(p2) update logic was accidentally removed from the
    // original always block. This left ri_s1c_p2/valid_s1c_p2 with no driver,
    // permanently stuck at 0, breaking the entire Stage 1c pipeline and causing
    // dec_valid_a to never arrive (Watchdog timeout → all FAIL, Clk_sum=0).
    // FIX: Add a dedicated always block for Stage 2(p2) update.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ri_s1c_p2  <= 9'd0;
            r0_s1c_p2 <= 9'd0; r1_s1c_p2 <= 9'd0; r2_s1c_p2 <= 9'd0;
            r3_s1c_p2 <= 9'd0; r4_s1c_p2 <= 9'd0; r5_s1c_p2 <= 9'd0;
            valid_s1c_p2 <= 1'b0;
        end else begin
            // Stage 2: propagate side-channel (Cycle N+1, aligns with DSP MREG)
            ri_s1c_p2  <= ri_s1c_pre;
            r0_s1c_p2 <= r0_s1c_pre; r1_s1c_p2 <= r1_s1c_pre; r2_s1c_p2 <= r2_s1c_pre;
            r3_s1c_p2 <= r3_s1c_pre; r4_s1c_p2 <= r4_s1c_pre; r5_s1c_p2 <= r5_s1c_pre;
            valid_s1c_p2 <= valid_s1c_pre;
        end
    end

    // Stage 3 always block (Cycle N+2): side-channel only, SEPARATE from Stage 4.
    // BUG FIX #31: Separating Stage 3 and Stage 4 into independent always blocks
    // prevents Vivado from merging them into combinational logic.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ri_s1c_p3  <= 9'd0;
            r0_s1c_p3 <= 9'd0; r1_s1c_p3 <= 9'd0; r2_s1c_p3 <= 9'd0;
            r3_s1c_p3 <= 9'd0; r4_s1c_p3 <= 9'd0; r5_s1c_p3 <= 9'd0;
            valid_s1c_p3 <= 1'b0;
        end else begin
            // Stage 3: propagate side-channel (Cycle N+2, aligns with DSP MREG)
            ri_s1c_p3  <= ri_s1c_p2;
            r0_s1c_p3 <= r0_s1c_p2; r1_s1c_p3 <= r1_s1c_p2; r2_s1c_p3 <= r2_s1c_p2;
            r3_s1c_p3 <= r3_s1c_p2; r4_s1c_p3 <= r4_s1c_p2; r5_s1c_p3 <= r5_s1c_p2;
            valid_s1c_p3 <= valid_s1c_p2;
        end
    end

    // Stage 4 always block (Cycle N+3): DSP PREG output + side-channel.
    // SEPARATE from Stage 3 to ensure Vivado treats them as distinct clock cycles.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coeff_raw_s1c <= 14'd0;
            ri_s1c        <= 9'd0;
            r0_s1c <= 9'd0; r1_s1c <= 9'd0; r2_s1c <= 9'd0;
            r3_s1c <= 9'd0; r4_s1c <= 9'd0; r5_s1c <= 9'd0;
            valid_s1c     <= 1'b0;
        end else begin
            // Stage 4: truncate DSP PREG output to 14-bit (Cycle N+3)
            // dsp1c_p_out is valid at Cycle N+3 (3 DSP pipeline stages after fabric reg).
            // Side-channel signals are now at p3 (also Cycle N+3) → time-aligned ✅
            coeff_raw_s1c <= dsp1c_p_out[13:0];  // Truncate 48-bit to 14-bit (lossless)
            ri_s1c        <= ri_s1c_p3;
            r0_s1c <= r0_s1c_p3; r1_s1c <= r1_s1c_p3; r2_s1c <= r2_s1c_p3;
            r3_s1c <= r3_s1c_p3; r4_s1c <= r4_s1c_p3; r5_s1c <= r5_s1c_p3;
            valid_s1c     <= valid_s1c_p3;
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
    // STAGE 1e: Manual DSP48E1 Instantiation (v2.11)
    // Operation: x_cand = ri_s1d + P_M1 * coeff_mod_s1d  (MAC: P = C + A*B)
    //
    // DSP48E1 Pipeline (5 stages, 3 clock cycles from input to P output):
    //   Cycle N:   A/B/C inputs sampled by fabric registers (pre-DSP)
    //   Cycle N+1: AREG/BREG/CREG latch A/B/C inside DSP
    //   Cycle N+2: MREG latches A*B product inside DSP
    //   Cycle N+3: PREG latches C + A*B result inside DSP -> P output
    //
    // OPMODE = 7'b0110101: P = C + A * B (MAC mode)
    //   Bits [6:4] = 011 -> Z mux selects C register
    //   Bits [3:2] = 01  -> W mux selects M (multiplier output)
    //   Bits [1:0] = 01  -> X mux selects M (multiplier output)
    //   Actually: OPMODE[6:4]=011 (Z=C), OPMODE[3:2]=01 (W=M), OPMODE[1:0]=01 (X=M)
    //   P = Z + W + X + Y = C + M + 0 + 0 = C + A*B
    // ALUMODE = 4'b0000: Z + W + X + Y (standard addition)
    // =========================================================================

    // --- Stage 1e: Fabric input registers (feed into DSP A/B/C ports) ---
    (* dont_touch = "true" *) reg [24:0] dsp1e_a_in;  // 25-bit A-port (coeff_mod, zero-extended)
    (* dont_touch = "true" *) reg [17:0] dsp1e_b_in;  // 18-bit B-port (P_M1)
    (* dont_touch = "true" *) reg [47:0] dsp1e_c_in;  // 48-bit C-port (ri, zero-extended)
    (* dont_touch = "true" *) reg [8:0]  r0_s1e_pre, r1_s1e_pre, r2_s1e_pre;
    (* dont_touch = "true" *) reg [8:0]  r3_s1e_pre, r4_s1e_pre, r5_s1e_pre;
    (* dont_touch = "true" *) reg        valid_s1e_pre;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dsp1e_a_in    <= 25'd0;
            dsp1e_b_in    <= 18'd0;
            dsp1e_c_in    <= 48'd0;
            r0_s1e_pre <= 9'd0; r1_s1e_pre <= 9'd0; r2_s1e_pre <= 9'd0;
            r3_s1e_pre <= 9'd0; r4_s1e_pre <= 9'd0; r5_s1e_pre <= 9'd0;
            valid_s1e_pre <= 1'b0;
        end else begin
            // Zero-extend 18-bit coeff_mod_s1d to 25-bit DSP A-port
            dsp1e_a_in    <= {7'd0, coeff_mod_s1d[17:0]};
            // P_M1 loaded into 18-bit DSP B-port
            dsp1e_b_in    <= P_M1[17:0];
            // Zero-extend 9-bit ri_s1d to 48-bit DSP C-port
            dsp1e_c_in    <= {39'd0, ri_s1d};
            r0_s1e_pre <= r0_s1d; r1_s1e_pre <= r1_s1d; r2_s1e_pre <= r2_s1d;
            r3_s1e_pre <= r3_s1d; r4_s1e_pre <= r4_s1d; r5_s1e_pre <= r5_s1d;
            valid_s1e_pre <= valid_s1d;
        end
    end

    // --- Stage 1e: DSP48E1 output wire ---
    wire [47:0] dsp1e_p_out;  // 48-bit P output from DSP48E1 (ri + P_M1 * coeff_mod)

    // --- Stage 1e: Manual DSP48E1 instantiation (MAC mode) ---
    // AREG=1, BREG=1, CREG=1: latch A/B/C inputs inside DSP (1 cycle)
    // MREG=1: latch multiplier output inside DSP (1 cycle)
    // PREG=1: latch final result (C + A*B) inside DSP (1 cycle)
    // Total DSP internal pipeline: 3 cycles (AREG/CREG -> MREG -> PREG)
    DSP48E1 #(
        // Feature control
        .USE_MULT    ("MULTIPLY"),  // Use multiplier
        .USE_SIMD    ("ONE48"),     // Single 48-bit operation
        .USE_DPORT   ("FALSE"),     // No D-port pre-adder
        // Pipeline register configuration (KEY: all enabled)
        .AREG        (1),           // 1 pipeline register on A input -> AREG
        .BREG        (1),           // 1 pipeline register on B input -> BREG
        .CREG        (1),           // 1 pipeline register on C input -> CREG
        .DREG        (1),           // D register (tied off)
        .MREG        (1),           // 1 pipeline register on multiplier output -> MREG
        .PREG        (1),           // 1 pipeline register on P output -> PREG
        .ADREG       (1),           // A+D pre-adder register
        .ACASCREG    (1),           // Cascade register matches AREG
        .BCASCREG    (1),           // Cascade register matches BREG
        // Data width
        .A_INPUT     ("DIRECT"),    // A input from fabric (not cascade)
        .B_INPUT     ("DIRECT"),    // B input from fabric (not cascade)
        // Initialization
        .AUTORESET_PATDET("NO_RESET"),
        .MASK        (48'h3fffffffffff),
        .PATTERN     (48'h000000000000),
        .SEL_MASK    ("MASK"),
        .SEL_PATTERN ("PATTERN"),
        .USE_PATTERN_DETECT("NO_PATDET")
    ) u_dsp_1e (
        .CLK         (clk),
        // Control signals
        // OPMODE[6:4]=011: Z mux = C register
        // OPMODE[3:2]=01:  W mux = M (multiplier output)
        // OPMODE[1:0]=01:  X mux = M (multiplier output)
        // Result: P = C + A*B (MAC operation)
        .OPMODE      (7'b0110101),  // P = C + A * B
        .ALUMODE     (4'b0000),     // Z + W + X + Y (standard add)
        .CARRYINSEL  (3'b000),
        // Clock enables (all enabled) — standard DSP48E1 CE ports
        // CEAD: CE for A+D pre-adder register (ADREG). USE_DPORT=FALSE so ADREG is
        //       bypassed and CEAD has no functional effect, but must be connected to
        //       avoid [Synth 8-7071] unconnected port warning.
        .CEA1        (1'b1), .CEA2        (1'b1),
        .CEB1        (1'b1), .CEB2        (1'b1),
        .CEC         (1'b1), .CED         (1'b1),
        .CEM         (1'b1), .CEP         (1'b1),
        .CECTRL      (1'b1), .CEINMODE    (1'b1),
        .CEAD        (1'b1),         // CE for ADREG (USE_DPORT=FALSE, no functional effect)
        // Synchronous resets (active high, tied low)
        .RSTA        (1'b0), .RSTB        (1'b0),
        .RSTC        (1'b0), .RSTD        (1'b0),
        .RSTM        (1'b0), .RSTP        (1'b0),
        .RSTALLCARRYIN(1'b0), .RSTALUMODE (1'b0),
        .RSTCTRL     (1'b0), .RSTINMODE   (1'b0),
        // Data inputs
        .A           (dsp1e_a_in),  // 25-bit A input (zero-extended coeff_mod)
        .B           (dsp1e_b_in),  // 18-bit B input (P_M1)
        .C           (dsp1e_c_in),  // 48-bit C input (zero-extended ri)
        .D           (25'd0),       // D not used (USE_DPORT=FALSE)
        .CARRYIN     (1'b0),
        .INMODE      (5'b00000),    // Standard mode: A2->A, B2->B
        // Cascade inputs (not used)
        .ACIN        (30'd0), .BCIN        (18'd0),
        .PCIN        (48'd0), .CARRYCASCIN (1'b0),
        .MULTSIGNIN  (1'b0),
        // Outputs
        .P           (dsp1e_p_out), // 48-bit result: ri + P_M1 * coeff_mod
        // Unused outputs
        .ACOUT       (), .BCOUT       (),
        .PCOUT       (), .CARRYCASCOUT(),
        .MULTSIGNOUT (), .OVERFLOW    (),
        .UNDERFLOW   (), .PATTERNDETECT(),
        .PATTERNBDETECT(), .CARRYOUT  ()
    );

    // --- Stage 1e: Output pipeline registers (after DSP PREG) ---
    // DSP pipeline adds 3 cycles (AREG/CREG + MREG + PREG).
    // Side-channel signals need 3 additional pipeline stages to stay aligned.
    // We already have 1 stage (dsp1e_a_in block above), so we need 2 more here.

    // Side-channel pipeline stage 2 (aligns with DSP MREG output)
    (* dont_touch = "true" *) reg [8:0]  r0_s1e_p2, r1_s1e_p2, r2_s1e_p2;
    (* dont_touch = "true" *) reg [8:0]  r3_s1e_p2, r4_s1e_p2, r5_s1e_p2;
    (* dont_touch = "true" *) reg        valid_s1e_p2;

    // Side-channel pipeline stage 3 (aligns with DSP MREG output, Cycle N+2)
    // NOTE: This stage propagates side-channel signals only.
    //       x_cand_16_s1e is NOT latched here — it comes from DSP PREG (Cycle N+3).
    (* dont_touch = "true" *) reg [8:0]  r0_s1e_p3, r1_s1e_p3, r2_s1e_p3;
    (* dont_touch = "true" *) reg [8:0]  r3_s1e_p3, r4_s1e_p3, r5_s1e_p3;
    (* dont_touch = "true" *) reg        valid_s1e_p3;

    // Side-channel pipeline stage 4 + DSP output clamp (aligns with DSP PREG output)
    //
    // BUG FIX #30 (Stage 1e): Same issue as Stage 1c.
    // DSP48E1 with AREG=1, BREG=1, CREG=1, MREG=1, PREG=1 has 3 internal pipeline
    // stages PLUS 1 fabric input register = 4 total cycles from coeff_mod_s1d to
    // dsp1e_p_out:
    //   Cycle N:   dsp1e_a_in <= coeff_mod_s1d  (fabric input register)
    //   Cycle N+1: DSP AREG/BREG/CREG latches A/B/C
    //   Cycle N+2: DSP MREG latches A*B
    //   Cycle N+3: DSP PREG latches C + A*B → dsp1e_p_out valid
    //
    // The original code had only 3 side-channel pipeline stages (p2, p3 in the
    // same always block as x_cand_16_s1e), making valid_s1e arrive 1 cycle EARLY
    // relative to x_cand_16_s1e. Stage 2a then computed x_cand_16_s1e % 257/256
    // using the PREVIOUS cycle's x_cand_16_s1e value, producing wrong results.
    //
    // FIX: Add a 4th side-channel pipeline stage (p3) so that valid_s1e is
    // registered in the SAME always block as x_cand_16_s1e (both at Cycle N+3).
    //
    // v2.15 FANOUT FIX: x_cand_16_s1e uses max_fanout=8 (not dont_touch) to allow
    // Vivado to replicate the register and reduce route delay.
    (* max_fanout = 8 *) reg [15:0] x_cand_16_s1e;
    (* dont_touch = "true" *) reg [8:0]  r0_s1e, r1_s1e, r2_s1e, r3_s1e, r4_s1e, r5_s1e;
    (* dont_touch = "true" *) reg        valid_s1e;

    // Stage 1e: Stage 2 always block (Cycle N+1)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r0_s1e_p2 <= 9'd0; r1_s1e_p2 <= 9'd0; r2_s1e_p2 <= 9'd0;
            r3_s1e_p2 <= 9'd0; r4_s1e_p2 <= 9'd0; r5_s1e_p2 <= 9'd0;
            valid_s1e_p2 <= 1'b0;
        end else begin
            // Stage 2: propagate side-channel (Cycle N+1, aligns with DSP MREG)
            r0_s1e_p2 <= r0_s1e_pre; r1_s1e_p2 <= r1_s1e_pre; r2_s1e_p2 <= r2_s1e_pre;
            r3_s1e_p2 <= r3_s1e_pre; r4_s1e_p2 <= r4_s1e_pre; r5_s1e_p2 <= r5_s1e_pre;
            valid_s1e_p2 <= valid_s1e_pre;
        end
    end

    // Stage 1e: Stage 3 always block (Cycle N+2): side-channel only, SEPARATE from Stage 4.
    // BUG FIX #31 (Stage 1e): Same fix as Stage 1c — separate always blocks prevent
    // Vivado from merging the NBA chain into a single-cycle path.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r0_s1e_p3 <= 9'd0; r1_s1e_p3 <= 9'd0; r2_s1e_p3 <= 9'd0;
            r3_s1e_p3 <= 9'd0; r4_s1e_p3 <= 9'd0; r5_s1e_p3 <= 9'd0;
            valid_s1e_p3 <= 1'b0;
        end else begin
            // Stage 3: propagate side-channel (Cycle N+2, aligns with DSP MREG)
            r0_s1e_p3 <= r0_s1e_p2; r1_s1e_p3 <= r1_s1e_p2; r2_s1e_p3 <= r2_s1e_p2;
            r3_s1e_p3 <= r3_s1e_p2; r4_s1e_p3 <= r4_s1e_p2; r5_s1e_p3 <= r5_s1e_p2;
            valid_s1e_p3 <= valid_s1e_p2;
        end
    end

    // Stage 1e: Stage 4 always block (Cycle N+3): DSP PREG output + side-channel.
    // SEPARATE from Stage 3 to ensure Vivado treats them as distinct clock cycles.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_cand_16_s1e <= 16'd0;
            r0_s1e <= 9'd0; r1_s1e <= 9'd0; r2_s1e <= 9'd0;
            r3_s1e <= 9'd0; r4_s1e <= 9'd0; r5_s1e <= 9'd0;
            valid_s1e     <= 1'b0;
        end else begin
            // Stage 4: clamp DSP PREG output to 16-bit (Cycle N+3)
            // dsp1e_p_out is valid at Cycle N+3 (3 DSP pipeline stages after fabric reg).
            // Side-channel signals are now at p3 (also Cycle N+3) → time-aligned ✅
            x_cand_16_s1e <= (dsp1e_p_out > 48'd65535) ? 16'hFFFF : dsp1e_p_out[15:0];
            r0_s1e <= r0_s1e_p3; r1_s1e <= r1_s1e_p3; r2_s1e <= r2_s1e_p3;
            r3_s1e <= r3_s1e_p3; r4_s1e <= r4_s1e_p3; r5_s1e <= r5_s1e_p3;
            valid_s1e     <= valid_s1e_p3;
        end
    end

    // =========================================================================
    // STAGE 2a: Modular Residue Computation — Group 1 (v2.16)
    // Compute x_cand_16_s1e % {257, 256} (2 moduli, parallel).
    //
    // v2.16 THREE-WAY SPLIT: Stage 2 is now split into 3 sub-stages (2+2+2).
    // v2.15 used 3+3 but each sub-stage still had ~8 CARRY4 per modulo (~5.8ns).
    // With 2 moduli per sub-stage, the critical path is ~4-5 CARRY4 (~2.5ns).
    //
    // Stage 2a: % 257, % 256 -> cand_r_s2a[0..1]
    //   Forward x_cand_16_s2a (max_fanout=8) and recv_r_s2a for downstream stages.
    // =========================================================================

    // Stage 2a combinational: first 2 modulo operations
    wire [8:0] cand_r_comb_a [0:1];
    assign cand_r_comb_a[0] = x_cand_16_s1e % 9'd257;
    assign cand_r_comb_a[1] = x_cand_16_s1e % 9'd256;

    // Stage 2a pipeline registers
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2a [0:1];  // Partial residues (% 257/256)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2a [0:5];  // All received residues (forwarded)
    // v2.16: max_fanout=8 allows Vivado to replicate x_cand_16_s2a to reduce route delay
    (* max_fanout = 8 *) reg [15:0] x_cand_16_s2a;          // x_cand_16 forwarded to Stage 2b
    (* dont_touch = "true" *) reg        valid_s2a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cand_r_s2a[0] <= 9'd0; cand_r_s2a[1] <= 9'd0;
            recv_r_s2a[0] <= 9'd0; recv_r_s2a[1] <= 9'd0; recv_r_s2a[2] <= 9'd0;
            recv_r_s2a[3] <= 9'd0; recv_r_s2a[4] <= 9'd0; recv_r_s2a[5] <= 9'd0;
            x_cand_16_s2a <= 16'd0;
            valid_s2a     <= 1'b0;
        end else begin
            valid_s2a     <= valid_s1e;
            x_cand_16_s2a <= x_cand_16_s1e;
            cand_r_s2a[0] <= cand_r_comb_a[0];
            cand_r_s2a[1] <= cand_r_comb_a[1];
            recv_r_s2a[0] <= r0_s1e;
            recv_r_s2a[1] <= r1_s1e;
            recv_r_s2a[2] <= r2_s1e;
            recv_r_s2a[3] <= r3_s1e;
            recv_r_s2a[4] <= r4_s1e;
            recv_r_s2a[5] <= r5_s1e;
        end
    end

    // =========================================================================
    // STAGE 2b: Modular Residue Computation — Group 2 (v2.16)
    // Compute x_cand_16_s2a % {61, 59} (2 moduli, parallel).
    //
    // Stage 2b: % 61, % 59 -> cand_r_s2b[2..3]
    //   Forward x_cand_16_s2b (max_fanout=8) and cand_r_s2a/recv_r_s2b for Stage 2c.
    // =========================================================================

    // Stage 2b combinational: second 2 modulo operations
    wire [8:0] cand_r_comb_b [2:3];
    assign cand_r_comb_b[2] = x_cand_16_s2a % 9'd61;
    assign cand_r_comb_b[3] = x_cand_16_s2a % 9'd59;

    // Stage 2b pipeline registers
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2b [0:3];  // Partial residues (% 257/256/61/59)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2b [0:5];  // All received residues (forwarded)
    // v2.16: max_fanout=8 allows Vivado to replicate x_cand_16_s2b to reduce route delay
    (* max_fanout = 8 *) reg [15:0] x_cand_16_s2b;          // x_cand_16 forwarded to Stage 2c
    (* dont_touch = "true" *) reg        valid_s2b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cand_r_s2b[0] <= 9'd0; cand_r_s2b[1] <= 9'd0;
            cand_r_s2b[2] <= 9'd0; cand_r_s2b[3] <= 9'd0;
            recv_r_s2b[0] <= 9'd0; recv_r_s2b[1] <= 9'd0; recv_r_s2b[2] <= 9'd0;
            recv_r_s2b[3] <= 9'd0; recv_r_s2b[4] <= 9'd0; recv_r_s2b[5] <= 9'd0;
            x_cand_16_s2b <= 16'd0;
            valid_s2b     <= 1'b0;
        end else begin
            valid_s2b     <= valid_s2a;
            x_cand_16_s2b <= x_cand_16_s2a;
            cand_r_s2b[0] <= cand_r_s2a[0];       // % 257 (from Stage 2a)
            cand_r_s2b[1] <= cand_r_s2a[1];       // % 256 (from Stage 2a)
            cand_r_s2b[2] <= cand_r_comb_b[2];    // % 61  (computed this cycle)
            cand_r_s2b[3] <= cand_r_comb_b[3];    // % 59  (computed this cycle)
            recv_r_s2b[0] <= recv_r_s2a[0];
            recv_r_s2b[1] <= recv_r_s2a[1];
            recv_r_s2b[2] <= recv_r_s2a[2];
            recv_r_s2b[3] <= recv_r_s2a[3];
            recv_r_s2b[4] <= recv_r_s2a[4];
            recv_r_s2b[5] <= recv_r_s2a[5];
        end
    end

    // =========================================================================
    // STAGE 2c: Modular Residue Computation — Group 3 (v2.16)
    // Compute x_cand_16_s2b % {55, 53} (2 moduli, parallel).
    // Merge with cand_r_s2b[0..3] into final cand_r_s2[0..5].
    //
    // Total Stage 2 latency: 3 cycles (Stage 2a + 2b + 2c).
    // Total decoder latency increases by 1 more cycle (absorbed by DEC_WAIT).
    // This fix applies uniformly to all 15 channels (shared module).
    // =========================================================================

    // Stage 2c combinational: third 2 modulo operations
    wire [8:0] cand_r_comb_c [4:5];
    assign cand_r_comb_c[4] = x_cand_16_s2b % 9'd55;
    assign cand_r_comb_c[5] = x_cand_16_s2b % 9'd53;

    // Stage 2c pipeline registers (final Stage 2 output)
    reg [8:0]  cand_r_s2 [0:5];  // All 6 candidate residues (merged from 2a + 2b + 2c)
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
            valid_s2     <= valid_s2b;
            x_cand_16_s2 <= x_cand_16_s2b;
            // Merge all results: Stage 2a (% 257/256) + Stage 2b (% 61/59) + Stage 2c (% 55/53)
            cand_r_s2[0] <= cand_r_s2b[0];       // % 257 (from Stage 2b, originally 2a)
            cand_r_s2[1] <= cand_r_s2b[1];       // % 256 (from Stage 2b, originally 2a)
            cand_r_s2[2] <= cand_r_s2b[2];       // % 61  (from Stage 2b)
            cand_r_s2[3] <= cand_r_s2b[3];       // % 59  (from Stage 2b)
            cand_r_s2[4] <= cand_r_comb_c[4];    // % 55  (computed this cycle)
            cand_r_s2[5] <= cand_r_comb_c[5];    // % 53  (computed this cycle)
            recv_r_s2[0] <= recv_r_s2b[0];
            recv_r_s2[1] <= recv_r_s2b[1];
            recv_r_s2[2] <= recv_r_s2b[2];
            recv_r_s2[3] <= recv_r_s2b[3];
            recv_r_s2[4] <= recv_r_s2b[4];
            recv_r_s2[5] <= recv_r_s2b[5];
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
    // 3. MLD Stage A: Two Parallel Partial Minimum Finders (v2.13)
    // =========================================================================
    // v2.12 used a single for-loop over all 15 channels. Verilog for-loop
    // sequential semantics forced Vivado to synthesize a 15-level serial
    // priority chain (ch0->ch1->...->ch14), causing 10.313ns route delay.
    //
    // v2.13 FIX: Split into two independent for-loops:
    //   Group A: ch0~ch7  (8 channels) -> partial minimum mid_dist_a / mid_x_a
    //   Group B: ch8~ch14 (7 channels) -> partial minimum mid_dist_b / mid_x_b
    // Each loop is at most 8 levels deep -> route delay ~4-5ns per group.
    // Results are registered (mid_*_reg) to break the combinational path.
    //
    // Tie-breaking: lower channel index wins (ch0 < ch1 < ... < ch14).
    // Group A always wins ties against Group B (ch0~ch7 < ch8~ch14).
    //
    // Latency: +1 cycle vs v2.12 (MLD now takes 2 cycles instead of 1).
    // Total decoder latency: 1(input) + 6(channel) + 2(MLD) = 9 cycles.
    // auto_scan_engine DEC_WAIT polls dec_valid -> absorbed automatically.

    // --- MLD Stage A: Combinational partial minimums ---
    reg [3:0]  mid_dist_a_comb, mid_dist_b_comb;
    reg [15:0] mid_x_a_comb,    mid_x_b_comb;
    reg        mid_valid_comb;
    integer    j;

    always @(*) begin
        // Group A: ch0~ch7
        mid_dist_a_comb = 4'd6;
        mid_x_a_comb    = 16'd0;
        for (j = 0; j <= 7; j = j + 1) begin
            if (ch_dist[j] < mid_dist_a_comb) begin
                mid_dist_a_comb = ch_dist[j];
                mid_x_a_comb    = ch_x[j];
            end
        end
        // Group B: ch8~ch14
        mid_dist_b_comb = 4'd6;
        mid_x_b_comb    = 16'd0;
        for (j = 8; j <= 14; j = j + 1) begin
            if (ch_dist[j] < mid_dist_b_comb) begin
                mid_dist_b_comb = ch_dist[j];
                mid_x_b_comb    = ch_x[j];
            end
        end
        mid_valid_comb = ch_valid[0];
    end

    // --- MLD Stage A: Pipeline registers (break combinational path) ---
    (* dont_touch = "true" *) reg [3:0]  mid_dist_a_reg, mid_dist_b_reg;
    (* dont_touch = "true" *) reg [15:0] mid_x_a_reg,    mid_x_b_reg;
    (* dont_touch = "true" *) reg        mid_valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mid_dist_a_reg <= 4'd6;
            mid_dist_b_reg <= 4'd6;
            mid_x_a_reg    <= 16'd0;
            mid_x_b_reg    <= 16'd0;
            mid_valid_reg  <= 1'b0;
        end else begin
            mid_dist_a_reg <= mid_dist_a_comb;
            mid_dist_b_reg <= mid_dist_b_comb;
            mid_x_a_reg    <= mid_x_a_comb;
            mid_x_b_reg    <= mid_x_b_comb;
            mid_valid_reg  <= mid_valid_comb;
        end
    end

    // =========================================================================
    // 4. MLD Stage B + Output Register (v2.13)
    // =========================================================================
    // Final comparison: mid_a vs mid_b -> select global minimum.
    // Group A wins ties (lower channel index priority).
    // Combinational path: mid_dist_a_reg -> 1 compare -> data_out_reg (~2 LUT).
    //
    // Total latency: 1(input) + 6(channel) + 1(MLD-A) + 1(MLD-B/output) = 9 cycles.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out      <= 16'd0;
            valid         <= 1'b0;
            uncorrectable <= 1'b0;
        end else begin
            valid <= mid_valid_reg;

            if (mid_valid_reg) begin
                // Group A wins on tie (ch0~ch7 have lower index priority)
                if (mid_dist_a_reg <= mid_dist_b_reg) begin
                    data_out      <= mid_x_a_reg;
                    uncorrectable <= (mid_dist_a_reg > `NRM_MAX_ERRORS);
                end else begin
                    data_out      <= mid_x_b_reg;
                    uncorrectable <= (mid_dist_b_reg > `NRM_MAX_ERRORS);
                end
            end else begin
                uncorrectable <= 1'b0;
            end
        end
    end

endmodule
