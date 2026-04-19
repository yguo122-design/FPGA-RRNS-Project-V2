"""
Fix decoder_2nrm.v Stage 1e:
Replace DSP48E1 MAC with LUT-based multiply+add.

Root cause: Stage 1e DSP48E1 (AREG+BREG+CREG+MREG+PREG = 3 internal stages
+ 1 fabric input register = 4 total cycles) has the same timing alignment
issue as Stage 1c. The coeff_mod_s1d and ri_s1d signals may not be correctly
sampled by the DSP, causing x_cand to be wrong.

Fix: Replace with 1-cycle LUT MAC:
  x_cand = ri_s1d + P_M1 * coeff_mod_s1d
  ri_s1d: 9-bit (max 256)
  P_M1: 9-bit constant (max 257)
  coeff_mod_s1d: 8-bit (max 255, since coeff_mod = coeff_raw % P_M2 <= P_M2-1 <= 255)
  Product: 9*8 = 17-bit (max 257*255 = 65535)
  Sum: max 256 + 65535 = 65791 (17-bit, clamp to 16-bit)
"""

filepath = 'd:/FPGAproject/FPGA-RRNS-Project-V2/src/algo_wrapper/decoder_2nrm.v'
content = open(filepath, encoding='utf-8').read()

# ============================================================
# Find the Stage 1e section and replace it
# ============================================================

# The old Stage 1e starts with the comment block and ends before Stage 2a1
old_stage1e_start = "    // =========================================================================\n    // STAGE 1e: Manual DSP48E1 Instantiation (v2.11)"
old_stage1e_end = "    // =========================================================================\n    // STAGE 2a1: Modular Residue Computation"

if old_stage1e_start not in content:
    print("ERROR: Could not find Stage 1e start marker")
    exit(1)

if old_stage1e_end not in content:
    print("ERROR: Could not find Stage 2a1 marker")
    exit(1)

start_idx = content.index(old_stage1e_start)
end_idx = content.index(old_stage1e_end)

old_stage1e = content[start_idx:end_idx]
print(f"Found Stage 1e section ({len(old_stage1e)} chars)")
print(f"First 100 chars: {old_stage1e[:100]}")

# New Stage 1e: LUT-based MAC
new_stage1e = """    // =========================================================================
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

"""

# Replace old Stage 1e with new
content = content[:start_idx] + new_stage1e + content[end_idx:]
print(f"Stage 1e replaced successfully")

# ============================================================
# Verify
# ============================================================
problems = []
if 'u_dsp_1e' in content:
    problems.append('u_dsp_1e still present (DSP instance not removed)')
if 'dsp1e_p_out' in content:
    problems.append('dsp1e_p_out still present')
if 'dsp1e_a_in' in content:
    problems.append('dsp1e_a_in still present')
if 'x_cand_raw_1e' not in content:
    problems.append('x_cand_raw_1e not found (LUT MAC not added)')
if 'x_cand_16_s1e <= (x_cand_raw_1e' not in content:
    problems.append('x_cand_16_s1e assignment not found')

if problems:
    print("\nProblems found:")
    for p in problems:
        print(f"  - {p}")
else:
    print("\nAll checks passed!")

# Save
open(filepath, 'w', encoding='utf-8').write(content)
print(f"\nFile saved ({len(content)} chars)")
