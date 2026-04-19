"""
Fix decoder_2nrm.v:
1. Add missing Stage 1b code
2. Remove orphaned old DSP code blocks
"""

filepath = 'd:/FPGAproject/FPGA-RRNS-Project-V2/src/algo_wrapper/decoder_2nrm.v'
content = open(filepath, encoding='utf-8').read()

# ============================================================
# Step 1: Add Stage 1b between Stage 1a and Stage 1c
# ============================================================
stage1b_code = """
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

"""

insert_marker = "    // =========================================================================\n    // STAGE 1c: LUT-based Multiply"
if insert_marker in content:
    content = content.replace(insert_marker, stage1b_code + insert_marker, 1)
    print("Stage 1b inserted successfully")
else:
    print("ERROR: Could not find Stage 1c marker")

# ============================================================
# Step 2: Remove orphaned old code blocks
# The orphaned code is 3 always blocks that reference ri_s1c_p2, ri_s1c_p3, dsp1c_p_out
# They appear after the new Stage 1c always block ends (after 'end\n    end\n')
# and before Stage 1d
# ============================================================

orphan_start = "    // Stage 3 always block (Cycle N+2): side-channel only, SEPARATE from Stage 4.\n    // BUG FIX #31"
orphan_end = "    // =========================================================================\n    // STAGE 1d: Second Modulo ONLY"

if orphan_start in content and orphan_end in content:
    start_idx = content.index(orphan_start)
    end_idx = content.index(orphan_end)
    removed = content[start_idx:end_idx]
    content = content[:start_idx] + content[end_idx:]
    print(f"Orphaned old code removed ({len(removed)} chars)")
    print("First 200 chars of removed code:")
    print(removed[:200])
else:
    print("ERROR: Could not find orphaned code markers")
    # Debug: find what's around the problematic lines
    lines = content.split('\n')
    for i, line in enumerate(lines):
        if 'ri_s1c_p2' in line or 'ri_s1c_p3' in line or 'dsp1c_p_out[13:0]' in line:
            start = max(0, i-3)
            end = min(len(lines), i+3)
            for j in range(start, end):
                print(f"Line {j+1}: {lines[j]}")
            print("---")

# ============================================================
# Step 3: Verify fix
# ============================================================
problems = []
if 'ri_s1c_p2' in content and 'reg [8:0]  ri_s1c_p2' not in content:
    problems.append('ri_s1c_p2 still referenced but not declared')
if 'ri_s1c_p3' in content and 'reg [8:0]  ri_s1c_p3' not in content:
    problems.append('ri_s1c_p3 still referenced but not declared')
if 'dsp1c_p_out[13:0]' in content:
    problems.append('dsp1c_p_out[13:0] still present')
if 'reg [7:0]  diff_mod_s1b' not in content and '* dont_touch = "true", max_fanout = 4 *) reg [7:0] diff_mod_s1b' not in content:
    problems.append('diff_mod_s1b not declared')
if 'reg [8:0]  ri_s1b' not in content and '* dont_touch = "true" *) reg [8:0]  ri_s1b' not in content:
    problems.append('ri_s1b not declared')

if problems:
    print("\nRemaining problems:")
    for p in problems:
        print(f"  - {p}")
else:
    print("\nAll problems fixed!")

# Save
open(filepath, 'w', encoding='utf-8').write(content)
print(f"\nFile saved ({len(content)} chars)")
