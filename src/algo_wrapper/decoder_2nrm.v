// =============================================================================
// File: decoder_2nrm.v
// Description: 2NRM Decoder with MLD (Maximum Likelihood Decoding)
//              Part of FPGA Multi-Algorithm Fault-Tolerant Test System
//              Implements Design Doc Section 2.3.3.3
// Version: v2.21 -- STAGE 3a2 FURTHER SPLIT (3a2 + 3a3) — Bug #41
//                   ILA data 6 analysis (iladata6.csv) confirmed:
//                   ch_dist_reg[0] = 5 (not 0) for ALL 57 valid cycles.
//                   ch0_x = 0x0088 = r257 value (CRT x_k0 is correct),
//                   but distance is wrong (should be 0, got 5).
//                   This proves Stage 3a2's cr2→cr3→cr4 chain (~9ns total)
//                   EXCEEDS the 10ns clock budget on actual silicon.
//
//                   ROOT CAUSE (Bug #41): Stage 3a2 computes cr2..cr4 as a
//                   3-level chain from registered cr1_s3a1:
//                     cr2 = f(cr1_s3a1) ~2ns  (from registered cr1)
//                     cr3 = f(cr2)      ~4ns  (cr2 is combinational)
//                     cr4 = f(cr3)      ~6ns  (cr3 is combinational)
//                     dist_k4 = f(cr4)  ~9ns  (cr4 + 3ns comparison)
//                   The actual silicon path (including route delay) exceeds 10ns,
//                   causing dist_k2_s3a..dist_k4_s3a to capture WRONG values.
//                   This corrupts ch_dist_reg[0] (the final channel output).
//
//                   FIX: Split Stage 3a2 into two registered sub-stages:
//                     Stage 3a2 [new]: Register cr2 only (from cr1_s3a1, ~2ns).
//                       Inputs: cr1_s3a1[0..5] (registered)
//                       Outputs: cr2_s3a2[0..5] (registered)
//                       Latency: 1 cycle, logic depth ~2ns
//                     Stage 3a3 [new]: Compute cr3, cr4 from registered cr2,
//                       compute all 5 distances, register them.
//                       Inputs: cr0_s3a1, cr1_s3a1, cr2_s3a2 (all registered)
//                       Chain: cr3=f(cr2_s3a2)~2ns, cr4=f(cr3)~4ns,
//                              dist_k4=f(cr4)~7ns -- within 10ns budget!
//                       Outputs: dist_k0_s3a..dist_k4_s3a, x_k0..k4_s3a
//                   Total Stage 3a latency: 3 cycles (was 2 cycles in v2.19/v2.20).
//                   Total decoder latency increases by 1 cycle (absorbed by DEC_WAIT).
//                   Expected comp_latency_a: 26 -> 27.
//
// Version: v2.20 -- STAGE 3a FULL PARALLEL REGISTRATION (Bug #40, not implemented)
//
// Version: v2.19 -- STAGE 3a CHAIN SPLIT (3a1 + 3a2)
//
// Version: v2.18 -- MLD INPUT REGISTER STAGE (ch_x/ch_dist pipeline register)
//                   iladata5 analysis showed that Bug #37 (Stage 3 split) correctly
//                   added 1 cycle latency (comp_latency_a: 23→24), but the decoder
//                   still outputs wrong values (MLD correct: 0/20, 97% failure rate).
//
//                   ROOT CAUSE: In decoder_channel_2nrm_param Stage 3b, valid/x_out/
//                   distance are all updated in the same always block at the same clock
//                   edge. However, best_x_all/best_dist_all are combinational outputs
//                   of a 4-level MUX tree driven by dist_k0_s3a..dist_k4_s3a and
//                   x_k0_s3a..x_k4_s3a. Due to Vivado register replication (max_fanout
//                   constraints on x_cand_16_s1e, x_cand_16_s2a/s2b), different channel
//                   instances may have their Stage 3b output registers (x_out, distance)
//                   updated at slightly different effective times relative to ch_valid.
//                   When MLD-A reads ch_x[j]/ch_dist[j] at the cycle when ch_valid AND=1,
//                   some channels (especially ch0 which has the correct answer) may still
//                   hold their PREVIOUS trial's distance value (initial value 6), while
//                   other channels (e.g., ch6 with dist=4) have already updated.
//                   This causes MLD-A to incorrectly select ch6 (dist=4) over ch0 (dist=0).
//
//                   FIX: Add a dedicated pipeline register stage in decoder_2nrm top-level
//                   that registers ALL 15 channel outputs (ch_x, ch_dist, ch_valid) before
//                   feeding them to MLD-A. This ensures MLD-A always reads values that have
//                   been stable for a full clock cycle, eliminating any inter-channel
//                   timing skew caused by register replication.
//
//                   Implementation:
//                     ch_x_reg[0..14]    : registered ch_x[0..14]
//                     ch_dist_reg[0..14] : registered ch_dist[0..14]
//                     ch_valid_reg[0..14]: registered ch_valid[0..14]
//                   MLD-A uses ch_x_reg/ch_dist_reg/ch_valid_reg instead of ch_x/ch_dist/ch_valid.
//                   Total decoder latency increases by 1 cycle (absorbed by DEC_WAIT).
//
// Version: v2.17 -- STAGE 3 PIPELINE SPLIT (3a + 3b)
//                   ILA data analysis (iladata4.csv) showed 98% failure rate even
//                   with zero error injection (70/71 non-injected trials FAIL).
//                   Python MLD simulation confirmed all failing cases should decode
//                   correctly (dist=0), but hardware outputs wrong values.
//                   Timing report shows WNS >= 0, so the issue is NOT a classic
//                   setup-time violation caught by static timing analysis.
//
//                   ROOT CAUSE HYPOTHESIS: The Stage 3 combinational logic
//                   (Bug #35 multi-candidate fix) creates a very deep combinational
//                   chain that Vivado's STA may not fully model due to the complex
//                   interaction of 5 candidates × 6 moduli × comparison + 4-level
//                   mux tree. The actual silicon path may have marginal timing that
//                   causes intermittent capture errors not visible in STA.
//
//                   FIX: Split Stage 3 into two registered pipeline sub-stages:
//                     Stage 3a [new]: Register all 5 candidate distances and x values.
//                       Inputs: cand_r_s2[0..5], recv_r_s2[0..5], x_cand_16_s2, valid_s2
//                       Outputs: dist_k0_s3a..dist_k4_s3a, x_k0_s3a..x_k4_s3a,
//                                x_k1_valid_s3a..x_k4_valid_s3a, valid_s3a
//                       Latency: 1 cycle (combinational dist/x computation → register)
//                     Stage 3b [new]: Select minimum distance from registered candidates.
//                       Inputs: dist_k0_s3a..dist_k4_s3a, x_k0_s3a..x_k4_s3a, valid_s3a
//                       Outputs: x_out, distance, valid (final channel outputs)
//                       Latency: 1 cycle (4-level mux tree → register, ~2ns)
//                   Total Stage 3 latency: 2 cycles (was 1 cycle in v2.16).
//                   Total decoder latency increases by 1 cycle (absorbed by DEC_WAIT).
//
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

    // diff_raw = (rj - ri) mod P_M2
    //
    // Bug #101 fix: ri can be up to P_M1-1 (max 256), while P_M2 can be as small
    // as 53. When ri > P_M2, a single addition of P_M2 is insufficient to make
    // the result positive. Example: ri=200, P_M2=53, rj=10:
    //   10 + 53 - 200 = -137 → wraps to 887 in 10-bit unsigned (WRONG!)
    // Fix: add enough multiples of P_M2 to ensure positive result, then take modulo.
    // ri_max = P_M1-1 = 256, P_M2_min = 53, ceil(256/53) = 5 → add 5×P_M2.
    // Since P_M2 is a compile-time constant, % P_M2 is optimized by Vivado.
    //
    // v2.14 BIT-WIDTH NOTE: diff_raw reduced to 9-bit (max = 255+5*256-0 = 1535 < 2^11).
    // Using 11-bit intermediate to avoid overflow before modulo.
    wire [10:0] diff_raw_wide;
    assign diff_raw_wide = {3'b0, rj} + {2'b0, P_M2[8:0]} + {2'b0, P_M2[8:0]} +
                           {2'b0, P_M2[8:0]} + {2'b0, P_M2[8:0]} + {2'b0, P_M2[8:0]} -
                           {3'b0, ri};  // 11-bit: max = 255+5*256-0 = 1535 < 2^11
    wire [8:0] diff_raw;
    assign diff_raw = diff_raw_wide % P_M2;  // constant modulo, optimized by Vivado

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
    // STAGE 1c: LUT-based Multiply (Bug #63 FIX: replaces DSP48E1)
    // Operation: coeff_raw = diff_mod_s1b * P_INV
    //
    // ROOT CAUSE OF BUG #63 (2026-03-21):
    //   ILA data (iladata9.csv) showed ch_x_reg[0] = ri (not the correct x_cand),
    //   and ch_dist_reg[0] = 5 (not 0). This proves coeff_raw_s1c = 0, meaning
    //   the DSP48E1 multiply output was always 0.
    //   The DSP48E1 Stage 1c pipeline (AREG+MREG+PREG = 3 internal stages + 1
    //   fabric input register = 4 total cycles) had a timing alignment issue
    //   that caused diff_mod_s1b to be sampled as 0 by the DSP.
    //
    // FIX: Replace DSP48E1 with a simple LUT-based multiply.
    //   diff_mod_s1b (8-bit, max 255) × P_INV (6-bit, max 56) = 14-bit result
    //   max = 255 × 56 = 14,280 < 2^14 = 16,384 ✓
    //   At 50MHz (20ns period), 8×6-bit LUT multiply takes ~3-4ns → timing safe.
    //   Pipeline latency: 1 cycle (was 4 cycles with DSP).
    //   Total decoder latency decreases by 3 cycles.
    // =========================================================================

    // Stage 1c combinational: coeff_raw = diff_mod_s1b * P_INV (LUT multiply)
    wire [13:0] coeff_raw_1c_comb;
    assign coeff_raw_1c_comb = diff_mod_s1b * P_INV[5:0];  // 8-bit × 6-bit = 14-bit

    // Stage 1c pipeline register (1 cycle, replaces 4-cycle DSP pipeline)
    (* max_fanout = 4 *) reg [13:0] coeff_raw_s1c;
    (* dont_touch = "true" *) reg [8:0]  ri_s1c;
    (* dont_touch = "true" *) reg [8:0]  r0_s1c, r1_s1c, r2_s1c, r3_s1c, r4_s1c, r5_s1c;
    (* dont_touch = "true" *) reg        valid_s1c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coeff_raw_s1c <= 14'd0;
            ri_s1c        <= 9'd0;
            r0_s1c <= 9'd0; r1_s1c <= 9'd0; r2_s1c <= 9'd0;
            r3_s1c <= 9'd0; r4_s1c <= 9'd0; r5_s1c <= 9'd0;
            valid_s1c     <= 1'b0;
        end else begin
            // LUT multiply: 1 cycle latency (was 4 cycles with DSP)
            coeff_raw_s1c <= coeff_raw_1c_comb;  // diff_mod_s1b * P_INV
            ri_s1c        <= ri_s1b;
            r0_s1c <= r0_s1b; r1_s1c <= r1_s1b; r2_s1c <= r2_s1b;
            r3_s1c <= r3_s1b; r4_s1c <= r4_s1b; r5_s1c <= r5_s1b;
            valid_s1c     <= valid_s1b;
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
    // STAGE 1e: LUT-based MAC (Bug #64 FIX: replaces DSP48E1)
    // Operation: x_cand = ri_s1d + P_M1 * coeff_mod_s1d
    //
    // ROOT CAUSE OF BUG #64 (2026-03-21):
    //   ILA data (iladata10.csv) showed ch_x_reg[0] = 0x5D88 = 23944,
    //   which is not the correct x_cand = 57204 for sym_a = 0xDF74.
    //   Stage 1c LUT fix was effective (ch_x_reg[0] is no longer ri),
    //   but Stage 1e DSP48E1 (AREG+BREG+CREG+MREG+PREG = 3 internal stages
    //   + 1 fabric input register = 4 total cycles) has the same timing
    //   alignment issue as Stage 1c: coeff_mod_s1d or ri_s1d may not be
    //   correctly sampled by the DSP, causing x_cand to be wrong.
    //
    // FIX: Replace DSP48E1 with a simple LUT-based MAC.
    //   ri_s1d (9-bit, max 256) + P_M1 (9-bit constant, max 257) * coeff_mod_s1d (8-bit, max 255)
    //   Product: max 257 * 255 = 65535 (16-bit)
    //   Sum: max 256 + 65535 = 65791 (17-bit, clamp to 16-bit = 65535)
    //   At 50MHz (20ns period), 9*8-bit LUT multiply+add takes ~4-5ns → timing safe.
    //   Pipeline latency: 1 cycle (was 4 cycles with DSP).
    //   Total decoder latency decreases by 3 more cycles.
    // =========================================================================

    // Stage 1e combinational: x_cand = ri_s1d + P_M1 * coeff_mod_s1d (LUT MAC)
    // coeff_mod_s1d is 18-bit declared but max value is P_M2-1 <= 255 (8-bit effective)
    wire [16:0] x_cand_raw_1e;
    assign x_cand_raw_1e = {1'b0, ri_s1d} + (P_M1[8:0] * coeff_mod_s1d[7:0]);

    // Stage 1e pipeline register (1 cycle, replaces 4-cycle DSP pipeline)
    // max_fanout=2: x_cand_16_s1e drives Stage 2a1 in all 15 channel instances
    (* max_fanout = 2 *) reg [15:0] x_cand_16_s1e;
    (* dont_touch = "true" *) reg [8:0]  r0_s1e, r1_s1e, r2_s1e, r3_s1e, r4_s1e, r5_s1e;
    (* dont_touch = "true" *) reg        valid_s1e;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_cand_16_s1e <= 16'd0;
            r0_s1e <= 9'd0; r1_s1e <= 9'd0; r2_s1e <= 9'd0;
            r3_s1e <= 9'd0; r4_s1e <= 9'd0; r5_s1e <= 9'd0;
            valid_s1e     <= 1'b0;
        end else begin
            // LUT MAC: 1 cycle latency (was 4 cycles with DSP)
            // Clamp to 16-bit (max x_cand = 65791 > 65535, so clamp needed)
            x_cand_16_s1e <= (x_cand_raw_1e > 17'd65535) ? 16'hFFFF : x_cand_raw_1e[15:0];
            r0_s1e <= r0_s1d; r1_s1e <= r1_s1d; r2_s1e <= r2_s1d;
            r3_s1e <= r3_s1d; r4_s1e <= r4_s1d; r5_s1e <= r5_s1d;
            valid_s1e     <= valid_s1d;
        end
    end

    // =========================================================================
    // STAGE 2a1: Modular Residue Computation — Group 1 Step 1 (v2.29 Bug #58 FIX)
    // Compute step1 values for % 257 and % 256 (NO modulo, just arithmetic).
    //
    // ROOT CAUSE OF BUG #58 (timing15.csv): Stage 2a computes % 257 directly
    // from x_cand_16_s1e. The % 257 operation requires 15 CARRY4 levels
    // (~5.06ns logic delay), exceeding the 5ns half-period threshold.
    // % 256 is trivial (= x[7:0]), but % 257 is the bottleneck.
    //
    // FIX: Apply 2-step decomposition using the identity 256 ≡ -1 (mod 257):
    //   x = x_hi * 256 + x_lo ≡ -x_hi + x_lo (mod 257)
    //   x % 257 = (x_lo - x_hi + 257) % 257
    //   Mathematical verification: 256 ≡ -1 (mod 257) ✓
    //
    //   Stage 2a1 [new]: Compute step1_257 = x_lo - x_hi + 257, REGISTER result.
    //     x_lo = x[7:0] (8-bit), x_hi = x[15:8] (8-bit)
    //     step1_257 = x_lo - x_hi + 257 (range: 1 to 511, 9-bit, always positive)
    //     Logic depth: ~2 CARRY4 (subtraction + addition) = ~1ns
    //   Stage 2a2 [new]: Compute step1_257 % 257 (9-bit input), REGISTER result.
    //     9-bit input % 257 → ~2-3 CARRY4 (~1ns)
    //   % 256 = x[7:0] (trivial, no CARRY4 needed)
    //
    // Total Stage 2 latency: 10 cycles (2a1+2a2+2b1+2b2a+2b2b+2c1a+2c1b+2c2a+2c2b+...),
    // was 8 cycles. DEC_WAIT automatically absorbs the extra cycles.
    // =========================================================================

    // Stage 2a1 combinational: step1_257 = x_lo - x_hi + 257 (NO modulo)
    wire [8:0] step1_257_comb;
    assign step1_257_comb = {1'b0, x_cand_16_s1e[7:0]} - {1'b0, x_cand_16_s1e[15:8]} + 9'd257;

    // Stage 2a1 pipeline registers: register step1_257 + forward all side-channels
    (* dont_touch = "true" *) reg [8:0]  step1_257_reg;      // Registered step1 for % 257
    (* dont_touch = "true" *) reg [7:0]  r256_s2a1;          // % 256 = x[7:0] (trivial)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2a1 [0:5];  // All received residues (forwarded)
    (* max_fanout = 4 *) reg [15:0] x_cand_16_s2a1;          // x_cand_16 forwarded to Stage 2a2
    (* dont_touch = "true" *) reg        valid_s2a1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step1_257_reg <= 9'd0;
            r256_s2a1     <= 8'd0;
            recv_r_s2a1[0] <= 9'd0; recv_r_s2a1[1] <= 9'd0; recv_r_s2a1[2] <= 9'd0;
            recv_r_s2a1[3] <= 9'd0; recv_r_s2a1[4] <= 9'd0; recv_r_s2a1[5] <= 9'd0;
            x_cand_16_s2a1 <= 16'd0;
            valid_s2a1     <= 1'b0;
        end else begin
            valid_s2a1     <= valid_s1e;
            x_cand_16_s2a1 <= x_cand_16_s1e;
            step1_257_reg  <= step1_257_comb;          // Register step1 (~1ns logic)
            r256_s2a1      <= x_cand_16_s1e[7:0];     // % 256 = x[7:0] (trivial)
            recv_r_s2a1[0] <= r0_s1e;
            recv_r_s2a1[1] <= r1_s1e;
            recv_r_s2a1[2] <= r2_s1e;
            recv_r_s2a1[3] <= r3_s1e;
            recv_r_s2a1[4] <= r4_s1e;
            recv_r_s2a1[5] <= r5_s1e;
        end
    end

    // =========================================================================
    // STAGE 2a2: Modular Residue Computation — Group 1 Step 2 (v2.29 Bug #58 FIX)
    // Compute step1_257_reg % 257 (9-bit input, ~2-3 CARRY4, ~1ns).
    // =========================================================================

    // Stage 2a2 combinational: step1_257_reg % 257 (9-bit input → ~2-3 CARRY4)
    wire [8:0] cand_r_257_comb;
    assign cand_r_257_comb = step1_257_reg % 9'd257;

    // Stage 2a2 pipeline registers
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2a [0:1];  // Partial residues (% 257/256)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2a [0:5];  // All received residues (forwarded)
    // Bug #58 FIX: max_fanout=4 on x_cand_16_s2a (forwarded from Stage 2a1)
    (* max_fanout = 4 *) reg [15:0] x_cand_16_s2a;          // x_cand_16 forwarded to Stage 2b1
    (* dont_touch = "true" *) reg        valid_s2a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cand_r_s2a[0] <= 9'd0; cand_r_s2a[1] <= 9'd0;
            recv_r_s2a[0] <= 9'd0; recv_r_s2a[1] <= 9'd0; recv_r_s2a[2] <= 9'd0;
            recv_r_s2a[3] <= 9'd0; recv_r_s2a[4] <= 9'd0; recv_r_s2a[5] <= 9'd0;
            x_cand_16_s2a <= 16'd0;
            valid_s2a     <= 1'b0;
        end else begin
            valid_s2a     <= valid_s2a1;
            x_cand_16_s2a <= x_cand_16_s2a1;
            cand_r_s2a[0] <= cand_r_257_comb;          // % 257 (step1_257_reg % 257, ~1ns)
            cand_r_s2a[1] <= {1'b0, r256_s2a1};        // % 256 = x[7:0] (trivial, forwarded)
            recv_r_s2a[0] <= recv_r_s2a1[0];
            recv_r_s2a[1] <= recv_r_s2a1[1];
            recv_r_s2a[2] <= recv_r_s2a1[2];
            recv_r_s2a[3] <= recv_r_s2a1[3];
            recv_r_s2a[4] <= recv_r_s2a1[4];
            recv_r_s2a[5] <= recv_r_s2a1[5];
        end
    end

    // =========================================================================
    // STAGE 2b1a: Modular Residue Computation — Group 2a Step 1 (v2.29 Bug #58 FIX)
    // Compute step1_61 = x_hi * 12 + x_lo (NO modulo, just multiply+add).
    //
    // ROOT CAUSE OF BUG #58 (timing15.csv): Stage 2b1 computes % 61 directly
    // from x_cand_16_s2a. The % 61 operation requires ~13 CARRY4 levels
    // (~4.51-5.02ns logic delay), approaching/exceeding the 5ns threshold.
    //
    // FIX: Apply 2-step decomposition:
    //   x % 61 = (x_hi * (256 % 61) + x_lo) % 61 = (x_hi * 12 + x_lo) % 61
    //   Mathematical verification: 256 % 61 = 256 - 4*61 = 256 - 244 = 12 ✓
    //
    //   Stage 2b1a [new]: Compute step1 = x_hi * 12 + x_lo, REGISTER result.
    //     x_hi * 12 <= 255 * 12 = 3060 (12-bit), + x_lo <= 3315 (12-bit)
    //     Logic depth: ~3 CARRY4 (multiply) + ~2 CARRY4 (add) = ~5 CARRY4 (~1.5ns)
    //   Stage 2b1b [new]: Compute step1_reg % 61 (12-bit input), REGISTER result.
    //     12-bit input % 61 → ~3-4 CARRY4 (~1.5ns)
    // =========================================================================

    // Stage 2b1a combinational: step1_61 = x_hi * 12 + x_lo (NO modulo)
    wire [11:0] x_mod61_step1_comb;
    assign x_mod61_step1_comb = ({4'd0, x_cand_16_s2a[15:8]} * 12'd12) + {4'd0, x_cand_16_s2a[7:0]};

    // Stage 2b1a pipeline registers
    (* dont_touch = "true" *) reg [11:0] x_mod61_step1_reg;   // Registered step1 for % 61
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2b1a [0:1];  // Partial residues (% 257/256)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2b1a [0:5];  // All received residues (forwarded)
    (* max_fanout = 4 *) reg [15:0] x_cand_16_s2b1a;          // x_cand_16 forwarded to Stage 2b1b
    (* dont_touch = "true" *) reg        valid_s2b1a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_mod61_step1_reg <= 12'd0;
            cand_r_s2b1a[0] <= 9'd0; cand_r_s2b1a[1] <= 9'd0;
            recv_r_s2b1a[0] <= 9'd0; recv_r_s2b1a[1] <= 9'd0; recv_r_s2b1a[2] <= 9'd0;
            recv_r_s2b1a[3] <= 9'd0; recv_r_s2b1a[4] <= 9'd0; recv_r_s2b1a[5] <= 9'd0;
            x_cand_16_s2b1a <= 16'd0;
            valid_s2b1a     <= 1'b0;
        end else begin
            valid_s2b1a        <= valid_s2a;
            x_cand_16_s2b1a    <= x_cand_16_s2a;
            x_mod61_step1_reg  <= x_mod61_step1_comb;  // Register step1 (~1.5ns logic)
            cand_r_s2b1a[0]    <= cand_r_s2a[0];       // % 257 (from Stage 2a2)
            cand_r_s2b1a[1]    <= cand_r_s2a[1];       // % 256 (from Stage 2a2)
            recv_r_s2b1a[0]    <= recv_r_s2a[0];
            recv_r_s2b1a[1]    <= recv_r_s2a[1];
            recv_r_s2b1a[2]    <= recv_r_s2a[2];
            recv_r_s2b1a[3]    <= recv_r_s2a[3];
            recv_r_s2b1a[4]    <= recv_r_s2a[4];
            recv_r_s2b1a[5]    <= recv_r_s2a[5];
        end
    end

    // =========================================================================
    // STAGE 2b1b: Modular Residue Computation — Group 2a Step 2 (v2.29 Bug #58 FIX)
    // Compute x_mod61_step1_reg % 61 (12-bit input, ~3-4 CARRY4, ~1.5ns).
    // =========================================================================

    // Stage 2b1b combinational: step1_reg % 61 (12-bit input → ~3-4 CARRY4)
    wire [8:0] cand_r_61_comb;
    assign cand_r_61_comb = x_mod61_step1_reg % 9'd61;

    // Stage 2b1b pipeline registers (merges % 257/256 from 2b1a with % 61)
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2b1 [0:2];  // Partial residues (% 257/256/61)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2b1 [0:5];  // All received residues (forwarded)
    (* max_fanout = 4 *) reg [15:0] x_cand_16_s2b1;          // x_cand_16 forwarded to Stage 2b2
    (* dont_touch = "true" *) reg        valid_s2b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cand_r_s2b1[0] <= 9'd0; cand_r_s2b1[1] <= 9'd0; cand_r_s2b1[2] <= 9'd0;
            recv_r_s2b1[0] <= 9'd0; recv_r_s2b1[1] <= 9'd0; recv_r_s2b1[2] <= 9'd0;
            recv_r_s2b1[3] <= 9'd0; recv_r_s2b1[4] <= 9'd0; recv_r_s2b1[5] <= 9'd0;
            x_cand_16_s2b1 <= 16'd0;
            valid_s2b1     <= 1'b0;
        end else begin
            valid_s2b1     <= valid_s2b1a;
            x_cand_16_s2b1 <= x_cand_16_s2b1a;
            cand_r_s2b1[0] <= cand_r_s2b1a[0];  // % 257 (from Stage 2b1a)
            cand_r_s2b1[1] <= cand_r_s2b1a[1];  // % 256 (from Stage 2b1a)
            cand_r_s2b1[2] <= cand_r_61_comb;   // % 61  (step1_reg % 61, ~1.5ns)
            recv_r_s2b1[0] <= recv_r_s2b1a[0];
            recv_r_s2b1[1] <= recv_r_s2b1a[1];
            recv_r_s2b1[2] <= recv_r_s2b1a[2];
            recv_r_s2b1[3] <= recv_r_s2b1a[3];
            recv_r_s2b1[4] <= recv_r_s2b1a[4];
            recv_r_s2b1[5] <= recv_r_s2b1a[5];
        end
    end

    // =========================================================================
    // STAGE 2b2a: Modular Residue Computation — Group 2b Step 1 (v2.27 Bug #49 FIX)
    // Compute x_mod59_step1 = x_hi * 20 + x_lo (NO modulo, just multiply+add).
    //
    // ROOT CAUSE OF BUG #49 (timing6.csv): Stage 2b2 computes x_cand_16_s2b1 % 59
    // directly. The % 59 operation requires 13-16 CARRY4 levels (~4.9-5.3ns logic
    // delay), which combined with route delay (~6ns) exceeds the 10ns budget.
    // Additionally, x_cand_16_s2b1 max_fanout=4 still results in fo=5-12 on
    // replicated copies, causing 5.72-6.03ns route delay.
    //
    // FIX: Apply the same 2-step decomposition with register isolation as Bug #48:
    //   x % 59 = (x_hi * (256 % 59) + x_lo) % 59 = (x_hi * 20 + x_lo) % 59
    //   Mathematical verification: 256 % 59 = 256 - 4*59 = 256 - 236 = 20 ✓
    //
    //   Stage 2b2a [new]: Compute step1 = x_hi * 20 + x_lo, REGISTER result.
    //     x_hi * 20 <= 255 * 20 = 5100 (13-bit), + x_lo <= 5355 (13-bit)
    //     Logic depth: ~3 CARRY4 (multiply) + ~2 CARRY4 (add) = ~5 CARRY4 (~1.5ns)
    //   Stage 2b2b [new]: Compute step1_reg % 59 (13-bit input), REGISTER result.
    //     13-bit input % 59 → ~4-5 CARRY4 (~1.5ns)
    //
    // With register isolation, Vivado CANNOT merge the two steps.
    // Each step has ~1.5ns logic depth, total path ~3-4ns — within 10ns budget.
    //
    // Total Stage 2 latency: 7 cycles (2a+2b1+2b2a+2b2b+2c1a+2c1b+2c2), was 6.
    // Total decoder latency increases by 1 more cycle (absorbed by DEC_WAIT).
    // =========================================================================

    // Stage 2b2a combinational: step1 = x_hi * 20 + x_lo (NO modulo)
    wire [12:0] x_mod59_step1_comb;
    assign x_mod59_step1_comb = ({5'd0, x_cand_16_s2b1[15:8]} * 13'd20) + {5'd0, x_cand_16_s2b1[7:0]};

    // Stage 2b2a pipeline registers: register step1 result + forward all side-channels
    (* dont_touch = "true" *) reg [12:0] x_mod59_step1_reg;  // Registered step1 result
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2b2a [0:2]; // Partial residues (% 257/256/61)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2b2a [0:5]; // All received residues (forwarded)
    (* max_fanout = 8 *) reg [15:0] x_cand_16_s2b2a;         // x_cand_16 forwarded to Stage 2b2b
    (* dont_touch = "true" *) reg        valid_s2b2a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_mod59_step1_reg <= 13'd0;
            cand_r_s2b2a[0] <= 9'd0; cand_r_s2b2a[1] <= 9'd0; cand_r_s2b2a[2] <= 9'd0;
            recv_r_s2b2a[0] <= 9'd0; recv_r_s2b2a[1] <= 9'd0; recv_r_s2b2a[2] <= 9'd0;
            recv_r_s2b2a[3] <= 9'd0; recv_r_s2b2a[4] <= 9'd0; recv_r_s2b2a[5] <= 9'd0;
            x_cand_16_s2b2a <= 16'd0;
            valid_s2b2a     <= 1'b0;
        end else begin
            valid_s2b2a        <= valid_s2b1;
            x_cand_16_s2b2a    <= x_cand_16_s2b1;
            x_mod59_step1_reg  <= x_mod59_step1_comb;  // Register step1 (~1.5ns logic)
            cand_r_s2b2a[0]    <= cand_r_s2b1[0];      // % 257 (from Stage 2b1)
            cand_r_s2b2a[1]    <= cand_r_s2b1[1];      // % 256 (from Stage 2b1)
            cand_r_s2b2a[2]    <= cand_r_s2b1[2];      // % 61  (from Stage 2b1)
            recv_r_s2b2a[0]    <= recv_r_s2b1[0];
            recv_r_s2b2a[1]    <= recv_r_s2b1[1];
            recv_r_s2b2a[2]    <= recv_r_s2b1[2];
            recv_r_s2b2a[3]    <= recv_r_s2b1[3];
            recv_r_s2b2a[4]    <= recv_r_s2b1[4];
            recv_r_s2b2a[5]    <= recv_r_s2b1[5];
        end
    end

    // =========================================================================
    // STAGE 2b2b: Modular Residue Computation — Group 2b Step 2 (v2.27 Bug #49 FIX)
    // Compute x_mod59_step1_reg % 59 (13-bit input modulo, ~4-5 CARRY4, ~1.5ns).
    //
    // The register isolation between Stage 2b2a and 2b2b prevents Vivado from
    // merging the two steps back into a single combinational cone.
    // =========================================================================

    // Stage 2b2b combinational: step1_reg % 59 (13-bit input → ~4-5 CARRY4)
    wire [8:0] cand_r_comb_b2b;
    assign cand_r_comb_b2b = x_mod59_step1_reg % 9'd59;

    // Stage 2b2b pipeline registers (merges % 257/256/61 from 2b2a with % 59)
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2b [0:3];  // Partial residues (% 257/256/61/59)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2b [0:5];  // All received residues (forwarded)
    // max_fanout=4: reduce route delay on x_cand_16_s2b for Stage 2c1a
    (* max_fanout = 4 *) reg [15:0] x_cand_16_s2b;          // x_cand_16 forwarded to Stage 2c1a
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
            valid_s2b     <= valid_s2b2a;
            x_cand_16_s2b <= x_cand_16_s2b2a;
            cand_r_s2b[0] <= cand_r_s2b2a[0];   // % 257 (from Stage 2b2a)
            cand_r_s2b[1] <= cand_r_s2b2a[1];   // % 256 (from Stage 2b2a)
            cand_r_s2b[2] <= cand_r_s2b2a[2];   // % 61  (from Stage 2b2a)
            cand_r_s2b[3] <= cand_r_comb_b2b;   // % 59  (step1_reg % 59, ~1.5ns)
            recv_r_s2b[0] <= recv_r_s2b2a[0];
            recv_r_s2b[1] <= recv_r_s2b2a[1];
            recv_r_s2b[2] <= recv_r_s2b2a[2];
            recv_r_s2b[3] <= recv_r_s2b2a[3];
            recv_r_s2b[4] <= recv_r_s2b2a[4];
            recv_r_s2b[5] <= recv_r_s2b2a[5];
        end
    end

    // =========================================================================
    // STAGE 2c1a: Modular Residue Computation — Group 3a Step 1 (v2.26 Bug #48 FIX)
    // Compute x_mod55_step1 = x_hi * 36 + x_lo (NO modulo, just multiply+add).
    //
    // ROOT CAUSE OF BUG #48 (timing5.csv): The v2.25 2-step decomposition of % 55
    // placed both steps (multiply+add AND modulo) in the SAME combinational block.
    // Vivado merged them into a single logic cone, resulting in WORSE timing
    // (logic delay 5.85-6.63ns, 18 levels) than the original direct % 55.
    //
    // FIX: Split the 2-step decomposition into TWO REGISTERED pipeline stages:
    //   Stage 2c1a [new]: Compute step1 = x_hi * 36 + x_lo, REGISTER result.
    //     x = x_hi * 256 + x_lo, 256 % 55 = 36
    //     x_hi * 36 <= 255 * 36 = 9180 (14-bit), + x_lo <= 9435 (14-bit)
    //     Logic depth: ~3 CARRY4 (multiply) + ~2 CARRY4 (add) = ~5 CARRY4 (~1.5ns)
    //   Stage 2c1b [new]: Compute step1_reg % 55, REGISTER result.
    //     14-bit input % 55 → ~4-5 CARRY4 (~1.5ns)
    //
    // With register isolation between the two steps, Vivado CANNOT merge them.
    // Each step has ~5 CARRY4 logic depth (~1.5ns), total path ~3-4ns per stage.
    //
    // Total Stage 2 latency: 6 cycles (2a+2b1+2b2+2c1a+2c1b+2c2), was 5 cycles.
    // Total decoder latency increases by 1 more cycle (absorbed by DEC_WAIT).
    // Mathematical verification: 256 % 55 = 256 - 4*55 = 256 - 220 = 36 ✓
    // =========================================================================

    // Stage 2c1a combinational: step1 = x_hi * 36 + x_lo (NO modulo)
    wire [13:0] x_mod55_step1_comb;
    assign x_mod55_step1_comb = ({6'd0, x_cand_16_s2b[15:8]} * 14'd36) + {6'd0, x_cand_16_s2b[7:0]};

    // Stage 2c1a pipeline registers: register step1 result + forward all side-channels
    // Bug #54 FIX: max_fanout=4 added to x_mod55_step1_reg (timing11.csv shows
    // x_mod55_step1_reg_reg[2] has fo=10, net delay 5.55ns on Stage 2c1b path).
    // Adding max_fanout=4 forces Vivado to replicate, reducing net delay to ~3ns.
    // Bug #56 FIX: REMOVED dont_touch from x_mod55_step1_reg.
    // timing13.csv shows fo=14 unchanged despite max_fanout=4, proving
    // dont_touch conflicts with max_fanout and prevents replication.
    (* max_fanout = 4 *) reg [13:0] x_mod55_step1_reg;  // Registered step1 result
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2c1a [0:3]; // Partial residues (% 257/256/61/59)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2c1a [0:5]; // All received residues (forwarded)
    (* max_fanout = 8 *) reg [15:0] x_cand_16_s2c1a;         // x_cand_16 forwarded to Stage 2c1b
    (* dont_touch = "true" *) reg        valid_s2c1a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_mod55_step1_reg <= 14'd0;
            cand_r_s2c1a[0] <= 9'd0; cand_r_s2c1a[1] <= 9'd0;
            cand_r_s2c1a[2] <= 9'd0; cand_r_s2c1a[3] <= 9'd0;
            recv_r_s2c1a[0] <= 9'd0; recv_r_s2c1a[1] <= 9'd0; recv_r_s2c1a[2] <= 9'd0;
            recv_r_s2c1a[3] <= 9'd0; recv_r_s2c1a[4] <= 9'd0; recv_r_s2c1a[5] <= 9'd0;
            x_cand_16_s2c1a <= 16'd0;
            valid_s2c1a     <= 1'b0;
        end else begin
            valid_s2c1a        <= valid_s2b;
            x_cand_16_s2c1a    <= x_cand_16_s2b;
            x_mod55_step1_reg  <= x_mod55_step1_comb;  // Register step1 (~1.5ns logic)
            cand_r_s2c1a[0]    <= cand_r_s2b[0];       // % 257 (from Stage 2b2)
            cand_r_s2c1a[1]    <= cand_r_s2b[1];       // % 256 (from Stage 2b2)
            cand_r_s2c1a[2]    <= cand_r_s2b[2];       // % 61  (from Stage 2b2)
            cand_r_s2c1a[3]    <= cand_r_s2b[3];       // % 59  (from Stage 2b2)
            recv_r_s2c1a[0]    <= recv_r_s2b[0];
            recv_r_s2c1a[1]    <= recv_r_s2b[1];
            recv_r_s2c1a[2]    <= recv_r_s2b[2];
            recv_r_s2c1a[3]    <= recv_r_s2b[3];
            recv_r_s2c1a[4]    <= recv_r_s2b[4];
            recv_r_s2c1a[5]    <= recv_r_s2b[5];
        end
    end

    // =========================================================================
    // STAGE 2c1b: Modular Residue Computation — Group 3a Step 2 (v2.26 Bug #48 FIX)
    // Compute x_mod55_step1_reg % 55 (14-bit input modulo, ~4-5 CARRY4, ~1.5ns).
    //
    // The register isolation between Stage 2c1a and 2c1b prevents Vivado from
    // merging the two steps back into a single combinational cone.
    // =========================================================================

    // Stage 2c1b combinational: step1_reg % 55 (14-bit input → ~4-5 CARRY4)
    wire [8:0] cand_r_comb_c1b;
    assign cand_r_comb_c1b = x_mod55_step1_reg % 9'd55;

    // Stage 2c1b pipeline registers: register % 55 result + forward all side-channels
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2c1 [0:4];  // Partial residues (% 257/256/61/59/55)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2c1 [0:5];  // All received residues (forwarded)
    // max_fanout=8: allow Vivado to replicate x_cand_16_s2c1 for Stage 2c2
    (* max_fanout = 8 *) reg [15:0] x_cand_16_s2c1;          // x_cand_16 forwarded to Stage 2c2
    (* dont_touch = "true" *) reg        valid_s2c1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cand_r_s2c1[0] <= 9'd0; cand_r_s2c1[1] <= 9'd0; cand_r_s2c1[2] <= 9'd0;
            cand_r_s2c1[3] <= 9'd0; cand_r_s2c1[4] <= 9'd0;
            recv_r_s2c1[0] <= 9'd0; recv_r_s2c1[1] <= 9'd0; recv_r_s2c1[2] <= 9'd0;
            recv_r_s2c1[3] <= 9'd0; recv_r_s2c1[4] <= 9'd0; recv_r_s2c1[5] <= 9'd0;
            x_cand_16_s2c1 <= 16'd0;
            valid_s2c1     <= 1'b0;
        end else begin
            valid_s2c1     <= valid_s2c1a;
            x_cand_16_s2c1 <= x_cand_16_s2c1a;
            cand_r_s2c1[0] <= cand_r_s2c1a[0];  // % 257 (from Stage 2c1a)
            cand_r_s2c1[1] <= cand_r_s2c1a[1];  // % 256 (from Stage 2c1a)
            cand_r_s2c1[2] <= cand_r_s2c1a[2];  // % 61  (from Stage 2c1a)
            cand_r_s2c1[3] <= cand_r_s2c1a[3];  // % 59  (from Stage 2c1a)
            cand_r_s2c1[4] <= cand_r_comb_c1b;  // % 55  (step1_reg % 55, ~1.5ns)
            recv_r_s2c1[0] <= recv_r_s2c1a[0];
            recv_r_s2c1[1] <= recv_r_s2c1a[1];
            recv_r_s2c1[2] <= recv_r_s2c1a[2];
            recv_r_s2c1[3] <= recv_r_s2c1a[3];
            recv_r_s2c1[4] <= recv_r_s2c1a[4];
            recv_r_s2c1[5] <= recv_r_s2c1a[5];
        end
    end

    // =========================================================================
    // STAGE 2c2a: Modular Residue Computation — Group 3b Step 1 (v2.28 Bug #52 FIX)
    // Compute x_mod53_step1 = x_hi * 44 + x_lo (NO modulo, just multiply+add).
    //
    // ROOT CAUSE OF BUG #52 (timing9.csv): Stage 2c2 computes x_cand_16_s2c1 % 53
    // directly. The % 53 operation requires 14 CARRY4 levels (~5.16ns logic delay),
    // exceeding the 5ns half-period threshold.
    //
    // FIX: Apply the same 2-step decomposition with register isolation as Bug #48/49:
    //   x % 53 = (x_hi * (256 % 53) + x_lo) % 53 = (x_hi * 44 + x_lo) % 53
    //   Mathematical verification: 256 % 53 = 256 - 4*53 = 256 - 212 = 44 ✓
    //
    //   Stage 2c2a [new]: Compute step1 = x_hi * 44 + x_lo, REGISTER result.
    //     x_hi * 44 <= 255 * 44 = 11220 (14-bit), + x_lo <= 11475 (14-bit)
    //     Logic depth: ~3 CARRY4 (multiply) + ~2 CARRY4 (add) = ~5 CARRY4 (~1.5ns)
    //   Stage 2c2b [new]: Compute step1_reg % 53 (14-bit input), REGISTER result.
    //     14-bit input % 53 → ~4-5 CARRY4 (~1.5ns)
    //
    // Total Stage 2 latency: 8 cycles (2a+2b1+2b2a+2b2b+2c1a+2c1b+2c2a+2c2b), was 7.
    // Total decoder latency increases by 1 more cycle (absorbed by DEC_WAIT).
    // =========================================================================

    // Stage 2c2a combinational: step1 = x_hi * 44 + x_lo (NO modulo)
    wire [13:0] x_mod53_step1_comb;
    assign x_mod53_step1_comb = ({6'd0, x_cand_16_s2c1[15:8]} * 14'd44) + {6'd0, x_cand_16_s2c1[7:0]};

    // Stage 2c2a pipeline registers: register step1 result + forward all side-channels
    // Bug #55 FIX: max_fanout=2 added to x_mod53_step1_reg (timing12.csv shows
    // x_mod53_step1_reg_reg[8] has fo=15, net delay 5.18ns on Stage 2c2b path).
    // Bug #56 FIX: REMOVED dont_touch from x_mod53_step1_reg.
    // Same issue as coeff_raw_s1c and x_mod55_step1_reg: dont_touch conflicts
    // with max_fanout and prevents Vivado from replicating the register.
    (* max_fanout = 2 *) reg [13:0] x_mod53_step1_reg;  // Registered step1 result
    (* dont_touch = "true" *) reg [8:0]  cand_r_s2c2a [0:4]; // Partial residues (% 257/256/61/59/55)
    (* dont_touch = "true" *) reg [8:0]  recv_r_s2c2a [0:5]; // All received residues (forwarded)
    (* max_fanout = 8 *) reg [15:0] x_cand_16_s2c2a;         // x_cand_16 forwarded to Stage 2c2b
    (* dont_touch = "true" *) reg        valid_s2c2a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_mod53_step1_reg <= 14'd0;
            cand_r_s2c2a[0] <= 9'd0; cand_r_s2c2a[1] <= 9'd0; cand_r_s2c2a[2] <= 9'd0;
            cand_r_s2c2a[3] <= 9'd0; cand_r_s2c2a[4] <= 9'd0;
            recv_r_s2c2a[0] <= 9'd0; recv_r_s2c2a[1] <= 9'd0; recv_r_s2c2a[2] <= 9'd0;
            recv_r_s2c2a[3] <= 9'd0; recv_r_s2c2a[4] <= 9'd0; recv_r_s2c2a[5] <= 9'd0;
            x_cand_16_s2c2a <= 16'd0;
            valid_s2c2a     <= 1'b0;
        end else begin
            valid_s2c2a        <= valid_s2c1;
            x_cand_16_s2c2a    <= x_cand_16_s2c1;
            x_mod53_step1_reg  <= x_mod53_step1_comb;  // Register step1 (~1.5ns logic)
            cand_r_s2c2a[0]    <= cand_r_s2c1[0];      // % 257 (from Stage 2c1b)
            cand_r_s2c2a[1]    <= cand_r_s2c1[1];      // % 256 (from Stage 2c1b)
            cand_r_s2c2a[2]    <= cand_r_s2c1[2];      // % 61  (from Stage 2c1b)
            cand_r_s2c2a[3]    <= cand_r_s2c1[3];      // % 59  (from Stage 2c1b)
            cand_r_s2c2a[4]    <= cand_r_s2c1[4];      // % 55  (from Stage 2c1b)
            recv_r_s2c2a[0]    <= recv_r_s2c1[0];
            recv_r_s2c2a[1]    <= recv_r_s2c1[1];
            recv_r_s2c2a[2]    <= recv_r_s2c1[2];
            recv_r_s2c2a[3]    <= recv_r_s2c1[3];
            recv_r_s2c2a[4]    <= recv_r_s2c1[4];
            recv_r_s2c2a[5]    <= recv_r_s2c1[5];
        end
    end

    // =========================================================================
    // STAGE 2c2b: Modular Residue Computation — Group 3b Step 2 (v2.28 Bug #52 FIX)
    // Compute x_mod53_step1_reg % 53 (14-bit input modulo, ~4-5 CARRY4, ~1.5ns).
    // Merge with cand_r_s2c2a[0..4] into final cand_r_s2[0..5].
    //
    // The register isolation between Stage 2c2a and 2c2b prevents Vivado from
    // merging the two steps back into a single combinational cone.
    // =========================================================================

    // Stage 2c2b combinational: step1_reg % 53 (14-bit input → ~4-5 CARRY4)
    wire [8:0] cand_r_comb_c2b;
    assign cand_r_comb_c2b = x_mod53_step1_reg % 9'd53;

    // Stage 2c2b pipeline registers (final Stage 2 output — merges all 6 residues)
    reg [8:0]  cand_r_s2 [0:5];  // All 6 candidate residues (merged from all stages)
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
            valid_s2     <= valid_s2c2a;
            x_cand_16_s2 <= x_cand_16_s2c2a;
            // Merge all results: 2a+2b1+2b2a+2b2b+2c1a+2c1b+2c2a+2c2b
            cand_r_s2[0] <= cand_r_s2c2a[0];    // % 257 (from Stage 2c2a)
            cand_r_s2[1] <= cand_r_s2c2a[1];    // % 256 (from Stage 2c2a)
            cand_r_s2[2] <= cand_r_s2c2a[2];    // % 61  (from Stage 2c2a)
            cand_r_s2[3] <= cand_r_s2c2a[3];    // % 59  (from Stage 2c2a)
            cand_r_s2[4] <= cand_r_s2c2a[4];    // % 55  (from Stage 2c2a)
            cand_r_s2[5] <= cand_r_comb_c2b;    // % 53  (step1_reg % 53, ~1.5ns)
            recv_r_s2[0] <= recv_r_s2c2a[0];
            recv_r_s2[1] <= recv_r_s2c2a[1];
            recv_r_s2[2] <= recv_r_s2c2a[2];
            recv_r_s2[3] <= recv_r_s2c2a[3];
            recv_r_s2[4] <= recv_r_s2c2a[4];
            recv_r_s2[5] <= recv_r_s2c2a[5];
        end
    end

    // =========================================================================
    // STAGE 3a: Multi-Candidate Distance Computation (Bug #35 Fix, v2.17 Split)
    //
    // ROOT CAUSE OF DECODING FAILURE (v2.16 and earlier):
    //   The original CRT formula x_cand = ri + M_i × coeff_mod only produces
    //   the minimum non-negative solution in [0, M_i×M_j). For large x values
    //   (x > M_i×M_j), the correct solution is x_cand + n×(M_i×M_j) for some
    //   n > 0. Since M_a = M_i×M_j = 65792 only for Channel 0 (pair 0,1),
    //   all other channels may miss the correct candidate for large x values.
    //
    //   Example: x=61302, Channel 5 (M_i=256, M_j=61, PERIOD=15616):
    //     x_cand_k0 = 14454 (distance=4, wrong)
    //     x_cand_k3 = 14454 + 3×15616 = 61302 (distance=1, correct!) ✅
    //
    // v2.17 PIPELINE SPLIT:
    //   Stage 3a: Compute all 5 candidate distances and x values combinationally,
    //             then REGISTER them. This breaks the long combinational chain.
    //   Stage 3b: Select minimum from registered candidates (simple 4-level mux,
    //             ~2ns logic delay). Register final x_out/distance/valid.
    //
    // EFFICIENCY: Use modular arithmetic periodicity to avoid recomputing
    //   full modulo operations for each candidate:
    //   (x + k×PERIOD) % m = (x%m + k×(PERIOD%m)) % m
    //   Since M_i | PERIOD and M_j | PERIOD, those two residues are unchanged.
    //   Only the 4 "other" residues need updating per candidate.
    // =========================================================================

    // Pre-compute PERIOD = P_M1 × P_M2 (compile-time constant)
    localparam [31:0] PERIOD = P_M1 * P_M2;

    // Pre-compute PERIOD % m_j for each modulus (compile-time constants)
    // These are used to update residues for extra candidates without full modulo
    localparam [8:0] PMOD_257 = PERIOD % 9'd257;
    localparam [8:0] PMOD_256 = PERIOD % 9'd256;
    localparam [8:0] PMOD_61  = PERIOD % 9'd61;
    localparam [8:0] PMOD_59  = PERIOD % 9'd59;
    localparam [8:0] PMOD_55  = PERIOD % 9'd55;
    localparam [8:0] PMOD_53  = PERIOD % 9'd53;

    // Helper macro: compute distance for a given set of candidate residues
    // dist = number of mismatches between cand_r and recv_r_s3a1 (all 6 moduli)
    // NOTE: v2.19 uses recv_r_s3a1 (registered in Stage 3a1) instead of recv_r_s2
    `define DIST_CALC(cr0,cr1,cr2,cr3,cr4,cr5) \
        (((cr0) != recv_r_s3a1[0] ? 4'd1 : 4'd0) + \
         ((cr1) != recv_r_s3a1[1] ? 4'd1 : 4'd0) + \
         ((cr2) != recv_r_s3a1[2] ? 4'd1 : 4'd0) + \
         ((cr3) != recv_r_s3a1[3] ? 4'd1 : 4'd0) + \
         ((cr4) != recv_r_s3a1[4] ? 4'd1 : 4'd0) + \
         ((cr5) != recv_r_s3a1[5] ? 4'd1 : 4'd0))

    // =========================================================================
    // STAGE 3a1 (v2.19 NEW): Register cr0..cr4 residues and x values
    //
    // ROOT CAUSE OF BUG #39: The original Stage 3a computed cr1..cr4 as a
    // CHAIN of combinational logic:
    //   cr1 = f(cand_r_s2)       -- ~2ns
    //   cr2 = f(cr1)             -- ~4ns (cr1 + 2ns)
    //   cr3 = f(cr2)             -- ~6ns (cr2 + 2ns)
    //   cr4 = f(cr3)             -- ~8ns (cr3 + 2ns)
    //   dist_k4 = f(cr4, recv_r) -- ~11ns (cr4 + 3ns)
    // This chain EXCEEDS the 10ns clock budget at 100MHz.
    //
    // FIX: Register cr0..cr4 in Stage 3a1. Each cr_k is computed from
    // cr_{k-1} combinationally (~2ns), then registered. This breaks the
    // chain into 4 independent 1-cycle stages, each with ~2ns logic delay.
    //
    // Stage 3a1 also registers:
    //   - cand_r_s2[0..5] as cr0_s3a1 (k=0 candidate residues)
    //   - x values for k=0..4 (x_k0_raw..x_k4_raw, validity flags)
    //   - recv_r_s2[0..5] as recv_r_s3a1 (for distance calculation in 3a2)
    //   - valid_s2 as valid_s3a1
    // =========================================================================

    // Combinational: cr0 = cand_r_s2 (k=0 candidate, no computation needed)
    // Combinational: cr1 = (cand_r_s2 + PMOD) % m  (k=1 candidate residues)
    wire [8:0] cr1_0_comb = (cand_r_s2[0] + PMOD_257 >= 9'd257) ? (cand_r_s2[0] + PMOD_257 - 9'd257) : (cand_r_s2[0] + PMOD_257);
    wire [8:0] cr1_1_comb = (cand_r_s2[1] + PMOD_256 >= 9'd256) ? (cand_r_s2[1] + PMOD_256 - 9'd256) : (cand_r_s2[1] + PMOD_256);
    wire [8:0] cr1_2_comb = (cand_r_s2[2] + PMOD_61  >= 9'd61)  ? (cand_r_s2[2] + PMOD_61  - 9'd61)  : (cand_r_s2[2] + PMOD_61);
    wire [8:0] cr1_3_comb = (cand_r_s2[3] + PMOD_59  >= 9'd59)  ? (cand_r_s2[3] + PMOD_59  - 9'd59)  : (cand_r_s2[3] + PMOD_59);
    wire [8:0] cr1_4_comb = (cand_r_s2[4] + PMOD_55  >= 9'd55)  ? (cand_r_s2[4] + PMOD_55  - 9'd55)  : (cand_r_s2[4] + PMOD_55);
    wire [8:0] cr1_5_comb = (cand_r_s2[5] + PMOD_53  >= 9'd53)  ? (cand_r_s2[5] + PMOD_53  - 9'd53)  : (cand_r_s2[5] + PMOD_53);

    // x values for k=0..22 (combinational, from cand_r_s2 / x_cand_16_s2)
    // Bug #102 fix: extend from k=0..4 to k=0..22 to cover all 16-bit X values
    // for small-modulus pairs (e.g., (55,53) with PERIOD=2915 needs k up to 22).
    // For large-modulus pairs (PERIOD >= 13568), k>4 gives X > 65535, so
    // x_k_valid will be false and Vivado will optimize away those branches.
    wire [31:0] x_k0_raw_comb  = {16'd0, x_cand_16_s2};
    wire [31:0] x_k1_raw_comb  = {16'd0, x_cand_16_s2} + PERIOD;
    wire [31:0] x_k2_raw_comb  = {16'd0, x_cand_16_s2} + (PERIOD * 2);
    wire [31:0] x_k3_raw_comb  = {16'd0, x_cand_16_s2} + (PERIOD * 3);
    wire [31:0] x_k4_raw_comb  = {16'd0, x_cand_16_s2} + (PERIOD * 4);
    wire [31:0] x_k5_raw_comb  = {16'd0, x_cand_16_s2} + (PERIOD * 5);
    wire [31:0] x_k6_raw_comb  = {16'd0, x_cand_16_s2} + (PERIOD * 6);
    wire [31:0] x_k7_raw_comb  = {16'd0, x_cand_16_s2} + (PERIOD * 7);
    wire [31:0] x_k8_raw_comb  = {16'd0, x_cand_16_s2} + (PERIOD * 8);
    wire [31:0] x_k9_raw_comb  = {16'd0, x_cand_16_s2} + (PERIOD * 9);
    wire [31:0] x_k10_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 10);
    wire [31:0] x_k11_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 11);
    wire [31:0] x_k12_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 12);
    wire [31:0] x_k13_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 13);
    wire [31:0] x_k14_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 14);
    wire [31:0] x_k15_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 15);
    wire [31:0] x_k16_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 16);
    wire [31:0] x_k17_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 17);
    wire [31:0] x_k18_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 18);
    wire [31:0] x_k19_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 19);
    wire [31:0] x_k20_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 20);
    wire [31:0] x_k21_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 21);
    wire [31:0] x_k22_raw_comb = {16'd0, x_cand_16_s2} + (PERIOD * 22);
    wire x_k1_valid_comb  = (x_k1_raw_comb  <= 32'd65535);
    wire x_k2_valid_comb  = (x_k2_raw_comb  <= 32'd65535);
    wire x_k3_valid_comb  = (x_k3_raw_comb  <= 32'd65535);
    wire x_k4_valid_comb  = (x_k4_raw_comb  <= 32'd65535);
    wire x_k5_valid_comb  = (x_k5_raw_comb  <= 32'd65535);
    wire x_k6_valid_comb  = (x_k6_raw_comb  <= 32'd65535);
    wire x_k7_valid_comb  = (x_k7_raw_comb  <= 32'd65535);
    wire x_k8_valid_comb  = (x_k8_raw_comb  <= 32'd65535);
    wire x_k9_valid_comb  = (x_k9_raw_comb  <= 32'd65535);
    wire x_k10_valid_comb = (x_k10_raw_comb <= 32'd65535);
    wire x_k11_valid_comb = (x_k11_raw_comb <= 32'd65535);
    wire x_k12_valid_comb = (x_k12_raw_comb <= 32'd65535);
    wire x_k13_valid_comb = (x_k13_raw_comb <= 32'd65535);
    wire x_k14_valid_comb = (x_k14_raw_comb <= 32'd65535);
    wire x_k15_valid_comb = (x_k15_raw_comb <= 32'd65535);
    wire x_k16_valid_comb = (x_k16_raw_comb <= 32'd65535);
    wire x_k17_valid_comb = (x_k17_raw_comb <= 32'd65535);
    wire x_k18_valid_comb = (x_k18_raw_comb <= 32'd65535);
    wire x_k19_valid_comb = (x_k19_raw_comb <= 32'd65535);
    wire x_k20_valid_comb = (x_k20_raw_comb <= 32'd65535);
    wire x_k21_valid_comb = (x_k21_raw_comb <= 32'd65535);
    wire x_k22_valid_comb = (x_k22_raw_comb <= 32'd65535);

    // Stage 3a1 pipeline registers
    // cr0_s3a1: k=0 candidate residues (= cand_r_s2, registered)
    // cr1_s3a1: k=1 candidate residues (= cr1_comb, registered)
    // x_k0_s3a1..x_k22_s3a1: candidate x values (registered)
    // x_k1_valid_s3a1..x_k22_valid_s3a1: validity flags (registered)
    // recv_r_s3a1: received residues (forwarded from recv_r_s2, registered)
    (* dont_touch = "true" *) reg [8:0] cr0_s3a1 [0:5];  // k=0 residues
    (* dont_touch = "true" *) reg [8:0] cr1_s3a1 [0:5];  // k=1 residues
    (* dont_touch = "true" *) reg [15:0] x_k0_s3a1,  x_k1_s3a1,  x_k2_s3a1,  x_k3_s3a1,  x_k4_s3a1;
    (* dont_touch = "true" *) reg [15:0] x_k5_s3a1,  x_k6_s3a1,  x_k7_s3a1,  x_k8_s3a1,  x_k9_s3a1;
    (* dont_touch = "true" *) reg [15:0] x_k10_s3a1, x_k11_s3a1, x_k12_s3a1, x_k13_s3a1, x_k14_s3a1;
    (* dont_touch = "true" *) reg [15:0] x_k15_s3a1, x_k16_s3a1, x_k17_s3a1, x_k18_s3a1, x_k19_s3a1;
    (* dont_touch = "true" *) reg [15:0] x_k20_s3a1, x_k21_s3a1, x_k22_s3a1;
    (* dont_touch = "true" *) reg        x_k1_valid_s3a1,  x_k2_valid_s3a1,  x_k3_valid_s3a1,  x_k4_valid_s3a1;
    (* dont_touch = "true" *) reg        x_k5_valid_s3a1,  x_k6_valid_s3a1,  x_k7_valid_s3a1,  x_k8_valid_s3a1;
    (* dont_touch = "true" *) reg        x_k9_valid_s3a1,  x_k10_valid_s3a1, x_k11_valid_s3a1, x_k12_valid_s3a1;
    (* dont_touch = "true" *) reg        x_k13_valid_s3a1, x_k14_valid_s3a1, x_k15_valid_s3a1, x_k16_valid_s3a1;
    (* dont_touch = "true" *) reg        x_k17_valid_s3a1, x_k18_valid_s3a1, x_k19_valid_s3a1, x_k20_valid_s3a1;
    (* dont_touch = "true" *) reg        x_k21_valid_s3a1, x_k22_valid_s3a1;
    (* dont_touch = "true" *) reg [8:0]  recv_r_s3a1 [0:5];
    (* dont_touch = "true" *) reg        valid_s3a1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cr0_s3a1[0] <= 9'd0; cr0_s3a1[1] <= 9'd0; cr0_s3a1[2] <= 9'd0;
            cr0_s3a1[3] <= 9'd0; cr0_s3a1[4] <= 9'd0; cr0_s3a1[5] <= 9'd0;
            cr1_s3a1[0] <= 9'd0; cr1_s3a1[1] <= 9'd0; cr1_s3a1[2] <= 9'd0;
            cr1_s3a1[3] <= 9'd0; cr1_s3a1[4] <= 9'd0; cr1_s3a1[5] <= 9'd0;
            x_k0_s3a1  <= 16'd0; x_k1_s3a1  <= 16'd0; x_k2_s3a1  <= 16'd0;
            x_k3_s3a1  <= 16'd0; x_k4_s3a1  <= 16'd0; x_k5_s3a1  <= 16'd0;
            x_k6_s3a1  <= 16'd0; x_k7_s3a1  <= 16'd0; x_k8_s3a1  <= 16'd0;
            x_k9_s3a1  <= 16'd0; x_k10_s3a1 <= 16'd0; x_k11_s3a1 <= 16'd0;
            x_k12_s3a1 <= 16'd0; x_k13_s3a1 <= 16'd0; x_k14_s3a1 <= 16'd0;
            x_k15_s3a1 <= 16'd0; x_k16_s3a1 <= 16'd0; x_k17_s3a1 <= 16'd0;
            x_k18_s3a1 <= 16'd0; x_k19_s3a1 <= 16'd0; x_k20_s3a1 <= 16'd0;
            x_k21_s3a1 <= 16'd0; x_k22_s3a1 <= 16'd0;
            x_k1_valid_s3a1  <= 1'b0; x_k2_valid_s3a1  <= 1'b0;
            x_k3_valid_s3a1  <= 1'b0; x_k4_valid_s3a1  <= 1'b0;
            x_k5_valid_s3a1  <= 1'b0; x_k6_valid_s3a1  <= 1'b0;
            x_k7_valid_s3a1  <= 1'b0; x_k8_valid_s3a1  <= 1'b0;
            x_k9_valid_s3a1  <= 1'b0; x_k10_valid_s3a1 <= 1'b0;
            x_k11_valid_s3a1 <= 1'b0; x_k12_valid_s3a1 <= 1'b0;
            x_k13_valid_s3a1 <= 1'b0; x_k14_valid_s3a1 <= 1'b0;
            x_k15_valid_s3a1 <= 1'b0; x_k16_valid_s3a1 <= 1'b0;
            x_k17_valid_s3a1 <= 1'b0; x_k18_valid_s3a1 <= 1'b0;
            x_k19_valid_s3a1 <= 1'b0; x_k20_valid_s3a1 <= 1'b0;
            x_k21_valid_s3a1 <= 1'b0; x_k22_valid_s3a1 <= 1'b0;
            recv_r_s3a1[0] <= 9'd0; recv_r_s3a1[1] <= 9'd0; recv_r_s3a1[2] <= 9'd0;
            recv_r_s3a1[3] <= 9'd0; recv_r_s3a1[4] <= 9'd0; recv_r_s3a1[5] <= 9'd0;
            valid_s3a1 <= 1'b0;
        end else begin
            // Register k=0 candidate residues (= cand_r_s2, no computation)
            cr0_s3a1[0] <= cand_r_s2[0]; cr0_s3a1[1] <= cand_r_s2[1];
            cr0_s3a1[2] <= cand_r_s2[2]; cr0_s3a1[3] <= cand_r_s2[3];
            cr0_s3a1[4] <= cand_r_s2[4]; cr0_s3a1[5] <= cand_r_s2[5];
            // Register k=1 candidate residues (computed from cand_r_s2, ~2ns)
            cr1_s3a1[0] <= cr1_0_comb; cr1_s3a1[1] <= cr1_1_comb;
            cr1_s3a1[2] <= cr1_2_comb; cr1_s3a1[3] <= cr1_3_comb;
            cr1_s3a1[4] <= cr1_4_comb; cr1_s3a1[5] <= cr1_5_comb;
            // Register x values k=0..22 (combinational from x_cand_16_s2)
            x_k0_s3a1  <= x_k0_raw_comb[15:0];
            x_k1_s3a1  <= x_k1_valid_comb  ? x_k1_raw_comb[15:0]  : 16'd0;
            x_k2_s3a1  <= x_k2_valid_comb  ? x_k2_raw_comb[15:0]  : 16'd0;
            x_k3_s3a1  <= x_k3_valid_comb  ? x_k3_raw_comb[15:0]  : 16'd0;
            x_k4_s3a1  <= x_k4_valid_comb  ? x_k4_raw_comb[15:0]  : 16'd0;
            x_k5_s3a1  <= x_k5_valid_comb  ? x_k5_raw_comb[15:0]  : 16'd0;
            x_k6_s3a1  <= x_k6_valid_comb  ? x_k6_raw_comb[15:0]  : 16'd0;
            x_k7_s3a1  <= x_k7_valid_comb  ? x_k7_raw_comb[15:0]  : 16'd0;
            x_k8_s3a1  <= x_k8_valid_comb  ? x_k8_raw_comb[15:0]  : 16'd0;
            x_k9_s3a1  <= x_k9_valid_comb  ? x_k9_raw_comb[15:0]  : 16'd0;
            x_k10_s3a1 <= x_k10_valid_comb ? x_k10_raw_comb[15:0] : 16'd0;
            x_k11_s3a1 <= x_k11_valid_comb ? x_k11_raw_comb[15:0] : 16'd0;
            x_k12_s3a1 <= x_k12_valid_comb ? x_k12_raw_comb[15:0] : 16'd0;
            x_k13_s3a1 <= x_k13_valid_comb ? x_k13_raw_comb[15:0] : 16'd0;
            x_k14_s3a1 <= x_k14_valid_comb ? x_k14_raw_comb[15:0] : 16'd0;
            x_k15_s3a1 <= x_k15_valid_comb ? x_k15_raw_comb[15:0] : 16'd0;
            x_k16_s3a1 <= x_k16_valid_comb ? x_k16_raw_comb[15:0] : 16'd0;
            x_k17_s3a1 <= x_k17_valid_comb ? x_k17_raw_comb[15:0] : 16'd0;
            x_k18_s3a1 <= x_k18_valid_comb ? x_k18_raw_comb[15:0] : 16'd0;
            x_k19_s3a1 <= x_k19_valid_comb ? x_k19_raw_comb[15:0] : 16'd0;
            x_k20_s3a1 <= x_k20_valid_comb ? x_k20_raw_comb[15:0] : 16'd0;
            x_k21_s3a1 <= x_k21_valid_comb ? x_k21_raw_comb[15:0] : 16'd0;
            x_k22_s3a1 <= x_k22_valid_comb ? x_k22_raw_comb[15:0] : 16'd0;
            x_k1_valid_s3a1  <= x_k1_valid_comb;  x_k2_valid_s3a1  <= x_k2_valid_comb;
            x_k3_valid_s3a1  <= x_k3_valid_comb;  x_k4_valid_s3a1  <= x_k4_valid_comb;
            x_k5_valid_s3a1  <= x_k5_valid_comb;  x_k6_valid_s3a1  <= x_k6_valid_comb;
            x_k7_valid_s3a1  <= x_k7_valid_comb;  x_k8_valid_s3a1  <= x_k8_valid_comb;
            x_k9_valid_s3a1  <= x_k9_valid_comb;  x_k10_valid_s3a1 <= x_k10_valid_comb;
            x_k11_valid_s3a1 <= x_k11_valid_comb; x_k12_valid_s3a1 <= x_k12_valid_comb;
            x_k13_valid_s3a1 <= x_k13_valid_comb; x_k14_valid_s3a1 <= x_k14_valid_comb;
            x_k15_valid_s3a1 <= x_k15_valid_comb; x_k16_valid_s3a1 <= x_k16_valid_comb;
            x_k17_valid_s3a1 <= x_k17_valid_comb; x_k18_valid_s3a1 <= x_k18_valid_comb;
            x_k19_valid_s3a1 <= x_k19_valid_comb; x_k20_valid_s3a1 <= x_k20_valid_comb;
            x_k21_valid_s3a1 <= x_k21_valid_comb; x_k22_valid_s3a1 <= x_k22_valid_comb;
            // Forward received residues (for distance calculation in Stage 3a2)
            recv_r_s3a1[0] <= recv_r_s2[0]; recv_r_s3a1[1] <= recv_r_s2[1];
            recv_r_s3a1[2] <= recv_r_s2[2]; recv_r_s3a1[3] <= recv_r_s2[3];
            recv_r_s3a1[4] <= recv_r_s2[4]; recv_r_s3a1[5] <= recv_r_s2[5];
            valid_s3a1 <= valid_s2;
        end
    end

    // =========================================================================
    // STAGE 3a2 (v2.21 BUG #41 FIX): Register cr2 only (from cr1_s3a1, ~2ns).
    //
    // ILA data 6 confirmed: ch_dist_reg[0] = 5 (not 0) for ALL valid cycles.
    // This proves the cr2→cr3→cr4 chain in Stage 3a2 (~9ns total) EXCEEDS
    // the 10ns clock budget on actual silicon (including route delay).
    //
    // FIX: Register cr2 here (1 cycle, ~2ns logic), then compute cr3, cr4,
    // and all distances in Stage 3a3 from registered cr2.
    // Chain in Stage 3a3: cr3=f(cr2_s3a2)~2ns, cr4=f(cr3)~4ns, dist_k4~7ns.
    // Maximum path: ~7ns -- safely within 10ns budget.
    // =========================================================================

    // Combinational: cr2 = f(cr1_s3a1) ~2ns (from registered cr1)
    wire [8:0] cr2_0_comb = (cr1_s3a1[0] + PMOD_257 >= 9'd257) ? (cr1_s3a1[0] + PMOD_257 - 9'd257) : (cr1_s3a1[0] + PMOD_257);
    wire [8:0] cr2_1_comb = (cr1_s3a1[1] + PMOD_256 >= 9'd256) ? (cr1_s3a1[1] + PMOD_256 - 9'd256) : (cr1_s3a1[1] + PMOD_256);
    wire [8:0] cr2_2_comb = (cr1_s3a1[2] + PMOD_61  >= 9'd61)  ? (cr1_s3a1[2] + PMOD_61  - 9'd61)  : (cr1_s3a1[2] + PMOD_61);
    wire [8:0] cr2_3_comb = (cr1_s3a1[3] + PMOD_59  >= 9'd59)  ? (cr1_s3a1[3] + PMOD_59  - 9'd59)  : (cr1_s3a1[3] + PMOD_59);
    wire [8:0] cr2_4_comb = (cr1_s3a1[4] + PMOD_55  >= 9'd55)  ? (cr1_s3a1[4] + PMOD_55  - 9'd55)  : (cr1_s3a1[4] + PMOD_55);
    wire [8:0] cr2_5_comb = (cr1_s3a1[5] + PMOD_53  >= 9'd53)  ? (cr1_s3a1[5] + PMOD_53  - 9'd53)  : (cr1_s3a1[5] + PMOD_53);

    // Stage 3a2 pipeline registers: register cr2 only
    // Also forward cr0_s3a1, cr1_s3a1, x values k=0..22, valid flags, recv_r to Stage 3a3
    (* dont_touch = "true" *) reg [8:0] cr2_s3a2 [0:5];  // k=2 residues (registered)
    // Forward cr0/cr1 from Stage 3a1 (need 1 more cycle alignment)
    (* dont_touch = "true" *) reg [8:0] cr0_s3a2 [0:5];  // k=0 residues (forwarded)
    (* dont_touch = "true" *) reg [8:0] cr1_s3a2 [0:5];  // k=1 residues (forwarded)
    // Bug #102: forward k=0..22 x values and valid flags
    (* dont_touch = "true" *) reg [15:0] x_k0_s3a2,  x_k1_s3a2,  x_k2_s3a2,  x_k3_s3a2,  x_k4_s3a2;
    (* dont_touch = "true" *) reg [15:0] x_k5_s3a2,  x_k6_s3a2,  x_k7_s3a2,  x_k8_s3a2,  x_k9_s3a2;
    (* dont_touch = "true" *) reg [15:0] x_k10_s3a2, x_k11_s3a2, x_k12_s3a2, x_k13_s3a2, x_k14_s3a2;
    (* dont_touch = "true" *) reg [15:0] x_k15_s3a2, x_k16_s3a2, x_k17_s3a2, x_k18_s3a2, x_k19_s3a2;
    (* dont_touch = "true" *) reg [15:0] x_k20_s3a2, x_k21_s3a2, x_k22_s3a2;
    (* dont_touch = "true" *) reg        x_k1_valid_s3a2,  x_k2_valid_s3a2,  x_k3_valid_s3a2,  x_k4_valid_s3a2;
    (* dont_touch = "true" *) reg        x_k5_valid_s3a2,  x_k6_valid_s3a2,  x_k7_valid_s3a2,  x_k8_valid_s3a2;
    (* dont_touch = "true" *) reg        x_k9_valid_s3a2,  x_k10_valid_s3a2, x_k11_valid_s3a2, x_k12_valid_s3a2;
    (* dont_touch = "true" *) reg        x_k13_valid_s3a2, x_k14_valid_s3a2, x_k15_valid_s3a2, x_k16_valid_s3a2;
    (* dont_touch = "true" *) reg        x_k17_valid_s3a2, x_k18_valid_s3a2, x_k19_valid_s3a2, x_k20_valid_s3a2;
    (* dont_touch = "true" *) reg        x_k21_valid_s3a2, x_k22_valid_s3a2;
    (* dont_touch = "true" *) reg [8:0]  recv_r_s3a2 [0:5];
    (* dont_touch = "true" *) reg        valid_s3a2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cr2_s3a2[0] <= 9'd0; cr2_s3a2[1] <= 9'd0; cr2_s3a2[2] <= 9'd0;
            cr2_s3a2[3] <= 9'd0; cr2_s3a2[4] <= 9'd0; cr2_s3a2[5] <= 9'd0;
            cr0_s3a2[0] <= 9'd0; cr0_s3a2[1] <= 9'd0; cr0_s3a2[2] <= 9'd0;
            cr0_s3a2[3] <= 9'd0; cr0_s3a2[4] <= 9'd0; cr0_s3a2[5] <= 9'd0;
            cr1_s3a2[0] <= 9'd0; cr1_s3a2[1] <= 9'd0; cr1_s3a2[2] <= 9'd0;
            cr1_s3a2[3] <= 9'd0; cr1_s3a2[4] <= 9'd0; cr1_s3a2[5] <= 9'd0;
            x_k0_s3a2  <= 16'd0; x_k1_s3a2  <= 16'd0; x_k2_s3a2  <= 16'd0;
            x_k3_s3a2  <= 16'd0; x_k4_s3a2  <= 16'd0; x_k5_s3a2  <= 16'd0;
            x_k6_s3a2  <= 16'd0; x_k7_s3a2  <= 16'd0; x_k8_s3a2  <= 16'd0;
            x_k9_s3a2  <= 16'd0; x_k10_s3a2 <= 16'd0; x_k11_s3a2 <= 16'd0;
            x_k12_s3a2 <= 16'd0; x_k13_s3a2 <= 16'd0; x_k14_s3a2 <= 16'd0;
            x_k15_s3a2 <= 16'd0; x_k16_s3a2 <= 16'd0; x_k17_s3a2 <= 16'd0;
            x_k18_s3a2 <= 16'd0; x_k19_s3a2 <= 16'd0; x_k20_s3a2 <= 16'd0;
            x_k21_s3a2 <= 16'd0; x_k22_s3a2 <= 16'd0;
            x_k1_valid_s3a2  <= 1'b0; x_k2_valid_s3a2  <= 1'b0;
            x_k3_valid_s3a2  <= 1'b0; x_k4_valid_s3a2  <= 1'b0;
            x_k5_valid_s3a2  <= 1'b0; x_k6_valid_s3a2  <= 1'b0;
            x_k7_valid_s3a2  <= 1'b0; x_k8_valid_s3a2  <= 1'b0;
            x_k9_valid_s3a2  <= 1'b0; x_k10_valid_s3a2 <= 1'b0;
            x_k11_valid_s3a2 <= 1'b0; x_k12_valid_s3a2 <= 1'b0;
            x_k13_valid_s3a2 <= 1'b0; x_k14_valid_s3a2 <= 1'b0;
            x_k15_valid_s3a2 <= 1'b0; x_k16_valid_s3a2 <= 1'b0;
            x_k17_valid_s3a2 <= 1'b0; x_k18_valid_s3a2 <= 1'b0;
            x_k19_valid_s3a2 <= 1'b0; x_k20_valid_s3a2 <= 1'b0;
            x_k21_valid_s3a2 <= 1'b0; x_k22_valid_s3a2 <= 1'b0;
            recv_r_s3a2[0] <= 9'd0; recv_r_s3a2[1] <= 9'd0; recv_r_s3a2[2] <= 9'd0;
            recv_r_s3a2[3] <= 9'd0; recv_r_s3a2[4] <= 9'd0; recv_r_s3a2[5] <= 9'd0;
            valid_s3a2 <= 1'b0;
        end else begin
            // Register cr2 (computed from cr1_s3a1, ~2ns logic)
            cr2_s3a2[0] <= cr2_0_comb; cr2_s3a2[1] <= cr2_1_comb;
            cr2_s3a2[2] <= cr2_2_comb; cr2_s3a2[3] <= cr2_3_comb;
            cr2_s3a2[4] <= cr2_4_comb; cr2_s3a2[5] <= cr2_5_comb;
            // Forward cr0, cr1 from Stage 3a1 (alignment)
            cr0_s3a2[0] <= cr0_s3a1[0]; cr0_s3a2[1] <= cr0_s3a1[1];
            cr0_s3a2[2] <= cr0_s3a1[2]; cr0_s3a2[3] <= cr0_s3a1[3];
            cr0_s3a2[4] <= cr0_s3a1[4]; cr0_s3a2[5] <= cr0_s3a1[5];
            cr1_s3a2[0] <= cr1_s3a1[0]; cr1_s3a2[1] <= cr1_s3a1[1];
            cr1_s3a2[2] <= cr1_s3a1[2]; cr1_s3a2[3] <= cr1_s3a1[3];
            cr1_s3a2[4] <= cr1_s3a1[4]; cr1_s3a2[5] <= cr1_s3a1[5];
            // Forward x values k=0..22 and validity flags
            x_k0_s3a2  <= x_k0_s3a1;  x_k1_s3a2  <= x_k1_s3a1;
            x_k2_s3a2  <= x_k2_s3a1;  x_k3_s3a2  <= x_k3_s3a1;  x_k4_s3a2  <= x_k4_s3a1;
            x_k5_s3a2  <= x_k5_s3a1;  x_k6_s3a2  <= x_k6_s3a1;  x_k7_s3a2  <= x_k7_s3a1;
            x_k8_s3a2  <= x_k8_s3a1;  x_k9_s3a2  <= x_k9_s3a1;  x_k10_s3a2 <= x_k10_s3a1;
            x_k11_s3a2 <= x_k11_s3a1; x_k12_s3a2 <= x_k12_s3a1; x_k13_s3a2 <= x_k13_s3a1;
            x_k14_s3a2 <= x_k14_s3a1; x_k15_s3a2 <= x_k15_s3a1; x_k16_s3a2 <= x_k16_s3a1;
            x_k17_s3a2 <= x_k17_s3a1; x_k18_s3a2 <= x_k18_s3a1; x_k19_s3a2 <= x_k19_s3a1;
            x_k20_s3a2 <= x_k20_s3a1; x_k21_s3a2 <= x_k21_s3a1; x_k22_s3a2 <= x_k22_s3a1;
            x_k1_valid_s3a2  <= x_k1_valid_s3a1;  x_k2_valid_s3a2  <= x_k2_valid_s3a1;
            x_k3_valid_s3a2  <= x_k3_valid_s3a1;  x_k4_valid_s3a2  <= x_k4_valid_s3a1;
            x_k5_valid_s3a2  <= x_k5_valid_s3a1;  x_k6_valid_s3a2  <= x_k6_valid_s3a1;
            x_k7_valid_s3a2  <= x_k7_valid_s3a1;  x_k8_valid_s3a2  <= x_k8_valid_s3a1;
            x_k9_valid_s3a2  <= x_k9_valid_s3a1;  x_k10_valid_s3a2 <= x_k10_valid_s3a1;
            x_k11_valid_s3a2 <= x_k11_valid_s3a1; x_k12_valid_s3a2 <= x_k12_valid_s3a1;
            x_k13_valid_s3a2 <= x_k13_valid_s3a1; x_k14_valid_s3a2 <= x_k14_valid_s3a1;
            x_k15_valid_s3a2 <= x_k15_valid_s3a1; x_k16_valid_s3a2 <= x_k16_valid_s3a1;
            x_k17_valid_s3a2 <= x_k17_valid_s3a1; x_k18_valid_s3a2 <= x_k18_valid_s3a1;
            x_k19_valid_s3a2 <= x_k19_valid_s3a1; x_k20_valid_s3a2 <= x_k20_valid_s3a1;
            x_k21_valid_s3a2 <= x_k21_valid_s3a1; x_k22_valid_s3a2 <= x_k22_valid_s3a1;
            // Forward received residues
            recv_r_s3a2[0] <= recv_r_s3a1[0]; recv_r_s3a2[1] <= recv_r_s3a1[1];
            recv_r_s3a2[2] <= recv_r_s3a1[2]; recv_r_s3a2[3] <= recv_r_s3a1[3];
            recv_r_s3a2[4] <= recv_r_s3a1[4]; recv_r_s3a2[5] <= recv_r_s3a1[5];
            valid_s3a2 <= valid_s3a1;
        end
    end

    // =========================================================================
    // STAGE 3a3 (v2.21 BUG #41 FIX): Compute cr3, cr4 from registered cr2,
    //   compute all 5 candidate distances, register them.
    //
    // Inputs: cr0_s3a2, cr1_s3a2, cr2_s3a2 (all registered), recv_r_s3a2
    // Chain: cr3=f(cr2_s3a2)~2ns, cr4=f(cr3)~4ns, dist_k4=f(cr4)~7ns
    // Maximum combinational path: ~7ns -- safely within 10ns budget!
    //
    // NOTE: The DIST_CALC macro uses recv_r_s3a1 but we now use recv_r_s3a2.
    // We redefine the macro locally to use recv_r_s3a2.
    // =========================================================================

    // Redefine DIST_CALC to use recv_r_s3a2 (registered in Stage 3a2)
    `undef DIST_CALC
    `define DIST_CALC(cr0,cr1,cr2,cr3,cr4,cr5) \
        (((cr0) != recv_r_s3a2[0] ? 4'd1 : 4'd0) + \
         ((cr1) != recv_r_s3a2[1] ? 4'd1 : 4'd0) + \
         ((cr2) != recv_r_s3a2[2] ? 4'd1 : 4'd0) + \
         ((cr3) != recv_r_s3a2[3] ? 4'd1 : 4'd0) + \
         ((cr4) != recv_r_s3a2[4] ? 4'd1 : 4'd0) + \
         ((cr5) != recv_r_s3a2[5] ? 4'd1 : 4'd0))

    // Combinational: cr3 = f(cr2_s3a2) ~2ns (from registered cr2)
    wire [8:0] cr3_0 = (cr2_s3a2[0] + PMOD_257 >= 9'd257) ? (cr2_s3a2[0] + PMOD_257 - 9'd257) : (cr2_s3a2[0] + PMOD_257);
    wire [8:0] cr3_1 = (cr2_s3a2[1] + PMOD_256 >= 9'd256) ? (cr2_s3a2[1] + PMOD_256 - 9'd256) : (cr2_s3a2[1] + PMOD_256);
    wire [8:0] cr3_2 = (cr2_s3a2[2] + PMOD_61  >= 9'd61)  ? (cr2_s3a2[2] + PMOD_61  - 9'd61)  : (cr2_s3a2[2] + PMOD_61);
    wire [8:0] cr3_3 = (cr2_s3a2[3] + PMOD_59  >= 9'd59)  ? (cr2_s3a2[3] + PMOD_59  - 9'd59)  : (cr2_s3a2[3] + PMOD_59);
    wire [8:0] cr3_4 = (cr2_s3a2[4] + PMOD_55  >= 9'd55)  ? (cr2_s3a2[4] + PMOD_55  - 9'd55)  : (cr2_s3a2[4] + PMOD_55);
    wire [8:0] cr3_5 = (cr2_s3a2[5] + PMOD_53  >= 9'd53)  ? (cr2_s3a2[5] + PMOD_53  - 9'd53)  : (cr2_s3a2[5] + PMOD_53);

    // Combinational: cr4 = f(cr3) ~4ns (from combinational cr3)
    wire [8:0] cr4_0 = (cr3_0 + PMOD_257 >= 9'd257) ? (cr3_0 + PMOD_257 - 9'd257) : (cr3_0 + PMOD_257);
    wire [8:0] cr4_1 = (cr3_1 + PMOD_256 >= 9'd256) ? (cr3_1 + PMOD_256 - 9'd256) : (cr3_1 + PMOD_256);
    wire [8:0] cr4_2 = (cr3_2 + PMOD_61  >= 9'd61)  ? (cr3_2 + PMOD_61  - 9'd61)  : (cr3_2 + PMOD_61);
    wire [8:0] cr4_3 = (cr3_3 + PMOD_59  >= 9'd59)  ? (cr3_3 + PMOD_59  - 9'd59)  : (cr3_3 + PMOD_59);
    wire [8:0] cr4_4 = (cr3_4 + PMOD_55  >= 9'd55)  ? (cr3_4 + PMOD_55  - 9'd55)  : (cr3_4 + PMOD_55);
    wire [8:0] cr4_5 = (cr3_5 + PMOD_53  >= 9'd53)  ? (cr3_5 + PMOD_53  - 9'd53)  : (cr3_5 + PMOD_53);

    // Combinational: compute all 5 candidate distances
    // dist_k0: from cr0_s3a2 (registered), ~3ns
    // dist_k1: from cr1_s3a2 (registered), ~3ns
    // dist_k2: from cr2_s3a2 (registered), ~3ns
    // dist_k3: from cr3 (2ns chain from cr2_s3a2), ~5ns
    // dist_k4: from cr4 (4ns chain from cr2_s3a2), ~7ns -- within 10ns budget!
    wire [3:0] dist_k0_comb = `DIST_CALC(cr0_s3a2[0], cr0_s3a2[1], cr0_s3a2[2],
                                          cr0_s3a2[3], cr0_s3a2[4], cr0_s3a2[5]);
    wire [3:0] dist_k1_comb = x_k1_valid_s3a2 ?
                              `DIST_CALC(cr1_s3a2[0], cr1_s3a2[1], cr1_s3a2[2],
                                         cr1_s3a2[3], cr1_s3a2[4], cr1_s3a2[5]) : 4'd6;
    wire [3:0] dist_k2_comb = x_k2_valid_s3a2 ?
                              `DIST_CALC(cr2_s3a2[0], cr2_s3a2[1], cr2_s3a2[2],
                                         cr2_s3a2[3], cr2_s3a2[4], cr2_s3a2[5]) : 4'd6;
    wire [3:0] dist_k3_comb = x_k3_valid_s3a2 ?
                              `DIST_CALC(cr3_0, cr3_1, cr3_2, cr3_3, cr3_4, cr3_5) : 4'd6;
    wire [3:0] dist_k4_comb = x_k4_valid_s3a2 ?
                              `DIST_CALC(cr4_0, cr4_1, cr4_2, cr4_3, cr4_4, cr4_5) : 4'd6;

    // --- Stage 3a3 output registers (= old Stage 3a output) ---
    // Register all 5 candidate distances (k=0..4) and x values.
    (* dont_touch = "true" *) reg [3:0]  dist_k0_s3a, dist_k1_s3a, dist_k2_s3a, dist_k3_s3a, dist_k4_s3a;
    (* dont_touch = "true" *) reg [15:0] x_k0_s3a, x_k1_s3a, x_k2_s3a, x_k3_s3a, x_k4_s3a;
    // Bug #102: also forward k=5..22 x values for Stage 3b extended MLD
    (* dont_touch = "true" *) reg [15:0] x_k5_s3a,  x_k6_s3a,  x_k7_s3a,  x_k8_s3a,  x_k9_s3a;
    (* dont_touch = "true" *) reg [15:0] x_k10_s3a, x_k11_s3a, x_k12_s3a, x_k13_s3a, x_k14_s3a;
    (* dont_touch = "true" *) reg [15:0] x_k15_s3a, x_k16_s3a, x_k17_s3a, x_k18_s3a, x_k19_s3a;
    (* dont_touch = "true" *) reg [15:0] x_k20_s3a, x_k21_s3a, x_k22_s3a;
    (* dont_touch = "true" *) reg        valid_s3a;

    // Bug #102: compute k=5..22 residues directly from cr0_s3a2 using compile-time constants
    // cr_k[m] = (cr0[m] + k*PMOD_m) % m  -- no chaining needed, all parallel
    // Helper function: (a + C) % M where C and M are compile-time constants
    // Using conditional subtraction: result = (a + C >= M) ? (a + C - M) : (a + C)
    // Note: C = k*PMOD_m may be >= M, so we use modulo arithmetic
    // For timing safety, each k uses a single addition + conditional subtraction (~2ns)

    // Pre-compute k*PMOD for each k and modulus (compile-time constants)
    // These are used to compute cr_k directly from cr0 without chaining
    `define CR_K(cr0_val, k_pmod, modulus) \
        (({1'b0, cr0_val} + (k_pmod % modulus)) >= modulus) ? \
        ({1'b0, cr0_val} + (k_pmod % modulus) - modulus) : \
        ({1'b0, cr0_val} + (k_pmod % modulus))

    // k=5..22 distances computed from cr0_s3a2 (registered, ~3ns each)
    wire [3:0] dist_k5_comb  = x_k5_valid_s3a2  ? `DIST_CALC(`CR_K(cr0_s3a2[0],5*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],5*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],5*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],5*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],5*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],5*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k6_comb  = x_k6_valid_s3a2  ? `DIST_CALC(`CR_K(cr0_s3a2[0],6*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],6*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],6*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],6*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],6*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],6*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k7_comb  = x_k7_valid_s3a2  ? `DIST_CALC(`CR_K(cr0_s3a2[0],7*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],7*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],7*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],7*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],7*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],7*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k8_comb  = x_k8_valid_s3a2  ? `DIST_CALC(`CR_K(cr0_s3a2[0],8*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],8*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],8*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],8*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],8*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],8*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k9_comb  = x_k9_valid_s3a2  ? `DIST_CALC(`CR_K(cr0_s3a2[0],9*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],9*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],9*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],9*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],9*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],9*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k10_comb = x_k10_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],10*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],10*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],10*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],10*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],10*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],10*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k11_comb = x_k11_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],11*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],11*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],11*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],11*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],11*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],11*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k12_comb = x_k12_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],12*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],12*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],12*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],12*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],12*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],12*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k13_comb = x_k13_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],13*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],13*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],13*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],13*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],13*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],13*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k14_comb = x_k14_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],14*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],14*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],14*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],14*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],14*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],14*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k15_comb = x_k15_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],15*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],15*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],15*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],15*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],15*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],15*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k16_comb = x_k16_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],16*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],16*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],16*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],16*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],16*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],16*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k17_comb = x_k17_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],17*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],17*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],17*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],17*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],17*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],17*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k18_comb = x_k18_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],18*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],18*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],18*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],18*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],18*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],18*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k19_comb = x_k19_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],19*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],19*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],19*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],19*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],19*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],19*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k20_comb = x_k20_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],20*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],20*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],20*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],20*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],20*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],20*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k21_comb = x_k21_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],21*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],21*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],21*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],21*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],21*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],21*PMOD_53,9'd53)) : 4'd6;
    wire [3:0] dist_k22_comb = x_k22_valid_s3a2 ? `DIST_CALC(`CR_K(cr0_s3a2[0],22*PMOD_257,9'd257),`CR_K(cr0_s3a2[1],22*PMOD_256,9'd256),`CR_K(cr0_s3a2[2],22*PMOD_61,9'd61),`CR_K(cr0_s3a2[3],22*PMOD_59,9'd59),`CR_K(cr0_s3a2[4],22*PMOD_55,9'd55),`CR_K(cr0_s3a2[5],22*PMOD_53,9'd53)) : 4'd6;

    // Stage 3a3 output registers: k=0..4 distances + k=5..22 distances + all x values
    (* dont_touch = "true" *) reg [3:0]  dist_k5_s3a,  dist_k6_s3a,  dist_k7_s3a,  dist_k8_s3a,  dist_k9_s3a;
    (* dont_touch = "true" *) reg [3:0]  dist_k10_s3a, dist_k11_s3a, dist_k12_s3a, dist_k13_s3a, dist_k14_s3a;
    (* dont_touch = "true" *) reg [3:0]  dist_k15_s3a, dist_k16_s3a, dist_k17_s3a, dist_k18_s3a, dist_k19_s3a;
    (* dont_touch = "true" *) reg [3:0]  dist_k20_s3a, dist_k21_s3a, dist_k22_s3a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dist_k0_s3a <= 4'd6; dist_k1_s3a <= 4'd6;
            dist_k2_s3a <= 4'd6; dist_k3_s3a <= 4'd6; dist_k4_s3a <= 4'd6;
            dist_k5_s3a  <= 4'd6; dist_k6_s3a  <= 4'd6; dist_k7_s3a  <= 4'd6;
            dist_k8_s3a  <= 4'd6; dist_k9_s3a  <= 4'd6; dist_k10_s3a <= 4'd6;
            dist_k11_s3a <= 4'd6; dist_k12_s3a <= 4'd6; dist_k13_s3a <= 4'd6;
            dist_k14_s3a <= 4'd6; dist_k15_s3a <= 4'd6; dist_k16_s3a <= 4'd6;
            dist_k17_s3a <= 4'd6; dist_k18_s3a <= 4'd6; dist_k19_s3a <= 4'd6;
            dist_k20_s3a <= 4'd6; dist_k21_s3a <= 4'd6; dist_k22_s3a <= 4'd6;
            x_k0_s3a  <= 16'd0; x_k1_s3a  <= 16'd0; x_k2_s3a  <= 16'd0;
            x_k3_s3a  <= 16'd0; x_k4_s3a  <= 16'd0; x_k5_s3a  <= 16'd0;
            x_k6_s3a  <= 16'd0; x_k7_s3a  <= 16'd0; x_k8_s3a  <= 16'd0;
            x_k9_s3a  <= 16'd0; x_k10_s3a <= 16'd0; x_k11_s3a <= 16'd0;
            x_k12_s3a <= 16'd0; x_k13_s3a <= 16'd0; x_k14_s3a <= 16'd0;
            x_k15_s3a <= 16'd0; x_k16_s3a <= 16'd0; x_k17_s3a <= 16'd0;
            x_k18_s3a <= 16'd0; x_k19_s3a <= 16'd0; x_k20_s3a <= 16'd0;
            x_k21_s3a <= 16'd0; x_k22_s3a <= 16'd0;
            valid_s3a   <= 1'b0;
        end else begin
            dist_k0_s3a <= dist_k0_comb;
            dist_k1_s3a <= dist_k1_comb;
            dist_k2_s3a <= dist_k2_comb;
            dist_k3_s3a <= dist_k3_comb;
            dist_k4_s3a <= dist_k4_comb;
            // Bug #102: register k=5..22 distances
            dist_k5_s3a  <= dist_k5_comb;  dist_k6_s3a  <= dist_k6_comb;
            dist_k7_s3a  <= dist_k7_comb;  dist_k8_s3a  <= dist_k8_comb;
            dist_k9_s3a  <= dist_k9_comb;  dist_k10_s3a <= dist_k10_comb;
            dist_k11_s3a <= dist_k11_comb; dist_k12_s3a <= dist_k12_comb;
            dist_k13_s3a <= dist_k13_comb; dist_k14_s3a <= dist_k14_comb;
            dist_k15_s3a <= dist_k15_comb; dist_k16_s3a <= dist_k16_comb;
            dist_k17_s3a <= dist_k17_comb; dist_k18_s3a <= dist_k18_comb;
            dist_k19_s3a <= dist_k19_comb; dist_k20_s3a <= dist_k20_comb;
            dist_k21_s3a <= dist_k21_comb; dist_k22_s3a <= dist_k22_comb;
            x_k0_s3a  <= x_k0_s3a2;  x_k1_s3a  <= x_k1_s3a2;
            x_k2_s3a  <= x_k2_s3a2;  x_k3_s3a  <= x_k3_s3a2;  x_k4_s3a  <= x_k4_s3a2;
            x_k5_s3a  <= x_k5_s3a2;  x_k6_s3a  <= x_k6_s3a2;  x_k7_s3a  <= x_k7_s3a2;
            x_k8_s3a  <= x_k8_s3a2;  x_k9_s3a  <= x_k9_s3a2;  x_k10_s3a <= x_k10_s3a2;
            x_k11_s3a <= x_k11_s3a2; x_k12_s3a <= x_k12_s3a2; x_k13_s3a <= x_k13_s3a2;
            x_k14_s3a <= x_k14_s3a2; x_k15_s3a <= x_k15_s3a2; x_k16_s3a <= x_k16_s3a2;
            x_k17_s3a <= x_k17_s3a2; x_k18_s3a <= x_k18_s3a2; x_k19_s3a <= x_k19_s3a2;
            x_k20_s3a <= x_k20_s3a2; x_k21_s3a <= x_k21_s3a2; x_k22_s3a <= x_k22_s3a2;
            valid_s3a   <= valid_s3a2;
        end
    end

    `undef CR_K

    // =========================================================================
    // STAGE 3b: Minimum Distance Selection (Bug #102 extended to k=0..22)
    //
    // Find minimum distance across all 23 candidates (k=0..22).
    // Uses a balanced binary tree to avoid long combinational chains.
    // Priority: lower k wins on tie.
    // =========================================================================

    // Helper function: select minimum of two (dist, x) pairs
    // Lower k wins on tie (a wins over b when equal)
    `define MIN2(da, xa, db, xb) \
        ((db) < (da)) ? (db) : (da), \
        ((db) < (da)) ? (xb) : (xa)

    // Stage 3b: Combinational minimum selection from all 23 registered candidates
    // Level 1: pair-wise comparisons (12 pairs + 1 leftover)
    wire [3:0]  d01  = (dist_k1_s3a  < dist_k0_s3a)  ? dist_k1_s3a  : dist_k0_s3a;
    wire [15:0] x01  = (dist_k1_s3a  < dist_k0_s3a)  ? x_k1_s3a     : x_k0_s3a;
    wire [3:0]  d23  = (dist_k3_s3a  < dist_k2_s3a)  ? dist_k3_s3a  : dist_k2_s3a;
    wire [15:0] x23  = (dist_k3_s3a  < dist_k2_s3a)  ? x_k3_s3a     : x_k2_s3a;
    wire [3:0]  d45  = (dist_k5_s3a  < dist_k4_s3a)  ? dist_k5_s3a  : dist_k4_s3a;
    wire [15:0] x45  = (dist_k5_s3a  < dist_k4_s3a)  ? x_k5_s3a     : x_k4_s3a;
    wire [3:0]  d67  = (dist_k7_s3a  < dist_k6_s3a)  ? dist_k7_s3a  : dist_k6_s3a;
    wire [15:0] x67  = (dist_k7_s3a  < dist_k6_s3a)  ? x_k7_s3a     : x_k6_s3a;
    wire [3:0]  d89  = (dist_k9_s3a  < dist_k8_s3a)  ? dist_k9_s3a  : dist_k8_s3a;
    wire [15:0] x89  = (dist_k9_s3a  < dist_k8_s3a)  ? x_k9_s3a     : x_k8_s3a;
    wire [3:0]  d1011 = (dist_k11_s3a < dist_k10_s3a) ? dist_k11_s3a : dist_k10_s3a;
    wire [15:0] x1011 = (dist_k11_s3a < dist_k10_s3a) ? x_k11_s3a    : x_k10_s3a;
    wire [3:0]  d1213 = (dist_k13_s3a < dist_k12_s3a) ? dist_k13_s3a : dist_k12_s3a;
    wire [15:0] x1213 = (dist_k13_s3a < dist_k12_s3a) ? x_k13_s3a    : x_k12_s3a;
    wire [3:0]  d1415 = (dist_k15_s3a < dist_k14_s3a) ? dist_k15_s3a : dist_k14_s3a;
    wire [15:0] x1415 = (dist_k15_s3a < dist_k14_s3a) ? x_k15_s3a    : x_k14_s3a;
    wire [3:0]  d1617 = (dist_k17_s3a < dist_k16_s3a) ? dist_k17_s3a : dist_k16_s3a;
    wire [15:0] x1617 = (dist_k17_s3a < dist_k16_s3a) ? x_k17_s3a    : x_k16_s3a;
    wire [3:0]  d1819 = (dist_k19_s3a < dist_k18_s3a) ? dist_k19_s3a : dist_k18_s3a;
    wire [15:0] x1819 = (dist_k19_s3a < dist_k18_s3a) ? x_k19_s3a    : x_k18_s3a;
    wire [3:0]  d2021 = (dist_k21_s3a < dist_k20_s3a) ? dist_k21_s3a : dist_k20_s3a;
    wire [15:0] x2021 = (dist_k21_s3a < dist_k20_s3a) ? x_k21_s3a    : x_k20_s3a;
    // k=22 is leftover
    wire [3:0]  d22   = dist_k22_s3a;
    wire [15:0] x22   = x_k22_s3a;

    // Level 2: 6 pairs from level 1 results
    wire [3:0]  d0123   = (d23   < d01)   ? d23   : d01;
    wire [15:0] x0123   = (d23   < d01)   ? x23   : x01;
    wire [3:0]  d4567   = (d67   < d45)   ? d67   : d45;
    wire [15:0] x4567   = (d67   < d45)   ? x67   : x45;
    wire [3:0]  d891011 = (d1011 < d89)   ? d1011 : d89;
    wire [15:0] x891011 = (d1011 < d89)   ? x1011 : x89;
    wire [3:0]  d12131415 = (d1415 < d1213) ? d1415 : d1213;
    wire [15:0] x12131415 = (d1415 < d1213) ? x1415 : x1213;
    wire [3:0]  d16171819 = (d1819 < d1617) ? d1819 : d1617;
    wire [15:0] x16171819 = (d1819 < d1617) ? x1819 : x1617;
    wire [3:0]  d202122   = (d22   < d2021) ? d22   : d2021;
    wire [15:0] x202122   = (d22   < d2021) ? x22   : x2021;

    // Level 3: 3 pairs
    wire [3:0]  d01234567     = (d4567   < d0123)   ? d4567   : d0123;
    wire [15:0] x01234567     = (d4567   < d0123)   ? x4567   : x0123;
    wire [3:0]  d891011121314 = (d12131415 < d891011) ? d12131415 : d891011;
    wire [15:0] x891011121314 = (d12131415 < d891011) ? x12131415 : x891011;
    wire [3:0]  d1516171819202122 = (d202122 < d16171819) ? d202122 : d16171819;
    wire [15:0] x1516171819202122 = (d202122 < d16171819) ? x202122 : x16171819;

    // Level 4: 2 comparisons
    wire [3:0]  d_low  = (d891011121314 < d01234567) ? d891011121314 : d01234567;
    wire [15:0] x_low  = (d891011121314 < d01234567) ? x891011121314 : x01234567;
    wire [3:0]  best_dist_all = (d1516171819202122 < d_low) ? d1516171819202122 : d_low;
    wire [15:0] best_x_all    = (d1516171819202122 < d_low) ? x1516171819202122 : x_low;

    // --- Stage 3b output registers (final channel outputs) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_out    <= 16'd0;
            distance <= 4'd6;
            valid    <= 1'b0;
        end else begin
            valid <= valid_s3a;
            if (valid_s3a) begin
                x_out    <= best_x_all;
                distance <= best_dist_all;
            end
        end
    end

    `undef DIST_CALC

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

    // Channel 1: pair (0,2) M1=257, M2=61, Inv=47
    // Fix: inv(257,61)=inv(13,61)=47 (13*47=611=10*61+1 ✓)
    // Previous value 48 was wrong: 13*48=624=10*61+14 ≠ 1 (mod 61)
    decoder_channel_2nrm_param #(.P_M1(257), .P_M2(61), .P_INV(47))
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
    // 3. Channel Output Pipeline Register Stage (v2.18 BUG FIX #38)
    // =========================================================================
    // PURPOSE: Register all 15 channel outputs (ch_x, ch_dist, ch_valid) before
    // feeding them to MLD-A. This ensures MLD-A always reads values that have
    // been stable for a full clock cycle, eliminating any inter-channel timing
    // skew caused by Vivado register replication (max_fanout constraints on
    // x_cand_16_s1e, x_cand_16_s2a/s2b).
    //
    // ROOT CAUSE (Bug #38): In Stage 3b, valid/x_out/distance are updated in
    // the same always block. However, best_x_all/best_dist_all are combinational
    // outputs of a 4-level MUX tree. Due to register replication, different
    // channel instances may have their Stage 3b output registers updated at
    // slightly different effective times. When MLD-A reads ch_x[j]/ch_dist[j]
    // at the cycle when ch_valid AND=1, some channels (especially ch0 with the
    // correct answer dist=0) may still hold their PREVIOUS trial's distance
    // value (initial value 6), while other channels (e.g., ch6 with dist=4)
    // have already updated. This causes MLD-A to incorrectly select ch6 over ch0.
    //
    // FIX: Register all channel outputs here. MLD-A uses ch_x_reg/ch_dist_reg/
    // ch_valid_reg instead of ch_x/ch_dist/ch_valid directly.
    // Total decoder latency increases by 1 cycle (absorbed by DEC_WAIT polling).
    //
    // (* dont_touch = "true" *) prevents Vivado from merging these registers
    // back into the channel output path, which would defeat the purpose.
    //
    // ILA DEBUG NOTE (Bug #40):
    // Do NOT add mark_debug attributes here — synthesis fails with them.
    // Instead, use Vivado GUI "Set Up Debug" after synthesis to add probes dynamically.
    // Key signals to probe via GUI (net names after synthesis):
    //   ch_x_reg[0]    (16-bit): ch0 x output, should = sym_a when no injection
    //   ch_dist_reg[0]  (4-bit): ch0 distance, should = 0 when no injection
    //   ch_valid_reg[0] (1-bit): ch0 valid signal
    //   ch_x_reg[6]    (16-bit): ch6 x output (comparison)
    //   ch_dist_reg[6]  (4-bit): ch6 distance (comparison)

    (* dont_touch = "true" *) reg [15:0] ch_x_reg    [0:14];
    (* dont_touch = "true" *) reg [3:0]  ch_dist_reg [0:14];
    (* dont_touch = "true" *) reg        ch_valid_reg[0:14];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ch_x_reg[0]  <= 16'd0; ch_x_reg[1]  <= 16'd0; ch_x_reg[2]  <= 16'd0;
            ch_x_reg[3]  <= 16'd0; ch_x_reg[4]  <= 16'd0; ch_x_reg[5]  <= 16'd0;
            ch_x_reg[6]  <= 16'd0; ch_x_reg[7]  <= 16'd0; ch_x_reg[8]  <= 16'd0;
            ch_x_reg[9]  <= 16'd0; ch_x_reg[10] <= 16'd0; ch_x_reg[11] <= 16'd0;
            ch_x_reg[12] <= 16'd0; ch_x_reg[13] <= 16'd0; ch_x_reg[14] <= 16'd0;
            ch_dist_reg[0]  <= 4'd6; ch_dist_reg[1]  <= 4'd6; ch_dist_reg[2]  <= 4'd6;
            ch_dist_reg[3]  <= 4'd6; ch_dist_reg[4]  <= 4'd6; ch_dist_reg[5]  <= 4'd6;
            ch_dist_reg[6]  <= 4'd6; ch_dist_reg[7]  <= 4'd6; ch_dist_reg[8]  <= 4'd6;
            ch_dist_reg[9]  <= 4'd6; ch_dist_reg[10] <= 4'd6; ch_dist_reg[11] <= 4'd6;
            ch_dist_reg[12] <= 4'd6; ch_dist_reg[13] <= 4'd6; ch_dist_reg[14] <= 4'd6;
            ch_valid_reg[0]  <= 1'b0; ch_valid_reg[1]  <= 1'b0; ch_valid_reg[2]  <= 1'b0;
            ch_valid_reg[3]  <= 1'b0; ch_valid_reg[4]  <= 1'b0; ch_valid_reg[5]  <= 1'b0;
            ch_valid_reg[6]  <= 1'b0; ch_valid_reg[7]  <= 1'b0; ch_valid_reg[8]  <= 1'b0;
            ch_valid_reg[9]  <= 1'b0; ch_valid_reg[10] <= 1'b0; ch_valid_reg[11] <= 1'b0;
            ch_valid_reg[12] <= 1'b0; ch_valid_reg[13] <= 1'b0; ch_valid_reg[14] <= 1'b0;
        end else begin
            // Register all channel outputs simultaneously.
            // All 15 channels use the same start_r and identical pipeline stages,
            // so their valid signals arrive at the same time. Registering here
            // ensures MLD-A reads values that have been stable for a full cycle.
            ch_x_reg[0]  <= ch_x[0];  ch_x_reg[1]  <= ch_x[1];  ch_x_reg[2]  <= ch_x[2];
            ch_x_reg[3]  <= ch_x[3];  ch_x_reg[4]  <= ch_x[4];  ch_x_reg[5]  <= ch_x[5];
            ch_x_reg[6]  <= ch_x[6];  ch_x_reg[7]  <= ch_x[7];  ch_x_reg[8]  <= ch_x[8];
            ch_x_reg[9]  <= ch_x[9];  ch_x_reg[10] <= ch_x[10]; ch_x_reg[11] <= ch_x[11];
            ch_x_reg[12] <= ch_x[12]; ch_x_reg[13] <= ch_x[13]; ch_x_reg[14] <= ch_x[14];
            ch_dist_reg[0]  <= ch_dist[0];  ch_dist_reg[1]  <= ch_dist[1];
            ch_dist_reg[2]  <= ch_dist[2];  ch_dist_reg[3]  <= ch_dist[3];
            ch_dist_reg[4]  <= ch_dist[4];  ch_dist_reg[5]  <= ch_dist[5];
            ch_dist_reg[6]  <= ch_dist[6];  ch_dist_reg[7]  <= ch_dist[7];
            ch_dist_reg[8]  <= ch_dist[8];  ch_dist_reg[9]  <= ch_dist[9];
            ch_dist_reg[10] <= ch_dist[10]; ch_dist_reg[11] <= ch_dist[11];
            ch_dist_reg[12] <= ch_dist[12]; ch_dist_reg[13] <= ch_dist[13];
            ch_dist_reg[14] <= ch_dist[14];
            ch_valid_reg[0]  <= ch_valid[0];  ch_valid_reg[1]  <= ch_valid[1];
            ch_valid_reg[2]  <= ch_valid[2];  ch_valid_reg[3]  <= ch_valid[3];
            ch_valid_reg[4]  <= ch_valid[4];  ch_valid_reg[5]  <= ch_valid[5];
            ch_valid_reg[6]  <= ch_valid[6];  ch_valid_reg[7]  <= ch_valid[7];
            ch_valid_reg[8]  <= ch_valid[8];  ch_valid_reg[9]  <= ch_valid[9];
            ch_valid_reg[10] <= ch_valid[10]; ch_valid_reg[11] <= ch_valid[11];
            ch_valid_reg[12] <= ch_valid[12]; ch_valid_reg[13] <= ch_valid[13];
            ch_valid_reg[14] <= ch_valid[14];
        end
    end

    // =========================================================================
    // 4. MLD Stage A: Two Parallel Partial Minimum Finders (v2.13, updated v2.18)
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
    // v2.18 UPDATE: MLD-A now uses ch_x_reg/ch_dist_reg/ch_valid_reg (registered
    // channel outputs) instead of ch_x/ch_dist/ch_valid directly. This ensures
    // all channel outputs are stable for a full clock cycle before MLD-A reads them.
    //
    // Tie-breaking: lower channel index wins (ch0 < ch1 < ... < ch14).
    // Group A always wins ties against Group B (ch0~ch7 < ch8~ch14).
    //
    // Latency: +1 cycle vs v2.17 (channel output register stage).
    // Total decoder latency: 1(input) + channel_pipeline + 1(ch_reg) + 2(MLD) cycles.
    // auto_scan_engine DEC_WAIT polls dec_valid -> absorbed automatically.

    // --- MLD Stage A: Combinational partial minimums (using registered channel outputs) ---
    reg [3:0]  mid_dist_a_comb, mid_dist_b_comb;
    reg [15:0] mid_x_a_comb,    mid_x_b_comb;
    reg        mid_valid_comb;
    integer    j;

    always @(*) begin
        // Group A: ch0~ch7 (using registered outputs)
        mid_dist_a_comb = 4'd6;
        mid_x_a_comb    = 16'd0;
        for (j = 0; j <= 7; j = j + 1) begin
            if (ch_dist_reg[j] < mid_dist_a_comb) begin
                mid_dist_a_comb = ch_dist_reg[j];
                mid_x_a_comb    = ch_x_reg[j];
            end
        end
        // Group B: ch8~ch14 (using registered outputs)
        mid_dist_b_comb = 4'd6;
        mid_x_b_comb    = 16'd0;
        for (j = 8; j <= 14; j = j + 1) begin
            if (ch_dist_reg[j] < mid_dist_b_comb) begin
                mid_dist_b_comb = ch_dist_reg[j];
                mid_x_b_comb    = ch_x_reg[j];
            end
        end
        // v2.18: Use AND of ALL 15 registered channel valid signals.
        // Since ch_valid_reg[j] is registered from ch_valid[j], all 15 channels
        // will have their valid_reg asserted in the same cycle (they all use the
        // same start_r and identical pipeline stages). The registered valid ensures
        // that ch_x_reg/ch_dist_reg are also stable (registered in the same cycle).
        mid_valid_comb = ch_valid_reg[0]  & ch_valid_reg[1]  & ch_valid_reg[2]  &
                         ch_valid_reg[3]  & ch_valid_reg[4]  & ch_valid_reg[5]  &
                         ch_valid_reg[6]  & ch_valid_reg[7]  & ch_valid_reg[8]  &
                         ch_valid_reg[9]  & ch_valid_reg[10] & ch_valid_reg[11] &
                         ch_valid_reg[12] & ch_valid_reg[13] & ch_valid_reg[14];
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
