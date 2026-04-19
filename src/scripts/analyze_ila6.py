"""
ILA Data 6 Analysis - After Bug #39 fix (v2.19/v2.20, comp_latency=26)
New ILA probes added via Vivado GUI:
  - ch_dist_reg[0]: ch0 distance (should = 0 when no injection)
  - ch_x_reg[0]:   ch0 x output (should = sym_a when no injection)
  - ch_x_reg[6]:   ch6 x output (comparison)
  - ch_dist_reg[6]: ch6 distance (comparison)
  - ch_valid_reg[0]: ch0 valid signal (trigger)
"""
import csv
import os
from collections import Counter

csv_path = 'src/scripts/iladata6.csv'
rows = []
with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

# Get column names (they have suffixes like _282, _441 etc.)
cols = list(rows[0].keys())
# Find the relevant columns by partial match
def find_col(cols, pattern):
    for c in cols:
        if pattern in c:
            return c
    return None

col_ch0_dist  = find_col(cols, 'ch_dist_reg[0]')
col_ch0_x     = find_col(cols, 'ch_x_reg[0]')
col_ch6_x     = find_col(cols, 'ch_x_reg[6]')
col_ch6_dist  = find_col(cols, 'ch_dist_reg[6]')
col_ch0_valid = find_col(cols, 'ch_valid_reg[0]')

print("=== Column Mapping ===")
print("ch0_dist:", col_ch0_dist)
print("ch0_x:   ", col_ch0_x)
print("ch6_x:   ", col_ch6_x)
print("ch6_dist:", col_ch6_dist)
print("ch0_valid:", col_ch0_valid)
print()

# Filter valid data rows
data = [r for r in rows if r.get('Sample in Buffer', '') not in
        ['Radix - UNSIGNED', 'UNSIGNED', '', 'Sample in Buffer']]

print("Total valid samples:", len(data))
print()

# Find all cycles where ch0_valid = 1
valid_cycles = [r for r in data if r.get(col_ch0_valid, '0') == '1']
print("Cycles where ch_valid_reg[0] = 1:", len(valid_cycles))
print()

if not valid_cycles:
    print("WARNING: No valid cycles found! ch_valid_reg[0] never went HIGH.")
    print("This means either:")
    print("  1. The trigger was wrong (should trigger on ch_valid_reg[0]=1)")
    print("  2. The decoder never produced valid output during capture")
    print()
    # Show distribution of ch0_valid
    valid_dist = Counter(r.get(col_ch0_valid, 'N/A') for r in data)
    print("ch_valid_reg[0] distribution:", dict(valid_dist))
    print()
    # Show distribution of ch0_dist
    dist_dist = Counter(r.get(col_ch0_dist, 'N/A') for r in data)
    print("ch_dist_reg[0] distribution:", dict(dist_dist))
    print()
    # Show some samples around the trigger point
    trigger_samples = [r for r in data if r.get('TRIGGER', '0') == '1']
    print("Trigger samples:", len(trigger_samples))
    if trigger_samples:
        print("First trigger sample:", dict(trigger_samples[0]))
    print()
    # Show samples where ch0_dist changes from 6
    non_6_dist = [r for r in data if r.get(col_ch0_dist, '6') != '6']
    print("Samples where ch0_dist != 6:", len(non_6_dist))
    if non_6_dist[:5]:
        for r in non_6_dist[:5]:
            print("  Sample", r['Sample in Buffer'],
                  "ch0_dist=", r.get(col_ch0_dist),
                  "ch0_x=", r.get(col_ch0_x),
                  "ch6_dist=", r.get(col_ch6_dist),
                  "ch6_x=", r.get(col_ch6_x),
                  "ch0_valid=", r.get(col_ch0_valid))
else:
    print("=== Analysis of valid cycles (ch_valid_reg[0] = 1) ===")
    print()

    # Analyze ch0_dist values when valid
    ch0_dist_vals = [int(r.get(col_ch0_dist, '6'), 16) for r in valid_cycles]
    ch0_dist_counter = Counter(ch0_dist_vals)
    print("ch_dist_reg[0] distribution when valid:")
    for dist, count in sorted(ch0_dist_counter.items()):
        pct = 100.0 * count / len(valid_cycles)
        print("  dist=%d: %d/%d (%.1f%%)" % (dist, count, len(valid_cycles), pct))
    print()

    # Analyze ch6_dist values when valid
    ch6_dist_vals = [int(r.get(col_ch6_dist, '6'), 16) for r in valid_cycles]
    ch6_dist_counter = Counter(ch6_dist_vals)
    print("ch_dist_reg[6] distribution when valid:")
    for dist, count in sorted(ch6_dist_counter.items()):
        pct = 100.0 * count / len(valid_cycles)
        print("  dist=%d: %d/%d (%.1f%%)" % (dist, count, len(valid_cycles), pct))
    print()

    # Key question: Is ch0_dist = 0 when valid?
    ch0_dist_0 = sum(1 for d in ch0_dist_vals if d == 0)
    ch0_dist_nonzero = sum(1 for d in ch0_dist_vals if d != 0)
    print("=== KEY DIAGNOSTIC ===")
    print("ch0_dist = 0 (correct): %d/%d (%.1f%%)" % (
        ch0_dist_0, len(valid_cycles), 100.0*ch0_dist_0/len(valid_cycles)))
    print("ch0_dist != 0 (wrong):  %d/%d (%.1f%%)" % (
        ch0_dist_nonzero, len(valid_cycles), 100.0*ch0_dist_nonzero/len(valid_cycles)))
    print()

    if ch0_dist_0 == len(valid_cycles):
        print("RESULT: ch0_dist is ALWAYS 0 when valid!")
        print("This means Stage 3a2 distance calculation is CORRECT.")
        print("The problem must be in MLD selection or later stages.")
        print()
        print("Checking if ch6_dist < ch0_dist (wrong selection):")
        wrong_sel = sum(1 for i, r in enumerate(valid_cycles)
                       if ch6_dist_vals[i] < ch0_dist_vals[i])
        print("  ch6_dist < ch0_dist: %d/%d" % (wrong_sel, len(valid_cycles)))
        print()
        print("Checking ch0_x vs ch6_x:")
        for r in valid_cycles[:10]:
            ch0_x = int(r.get(col_ch0_x, '0'), 16)
            ch6_x = int(r.get(col_ch6_x, '0'), 16)
            ch0_d = int(r.get(col_ch0_dist, '6'), 16)
            ch6_d = int(r.get(col_ch6_dist, '6'), 16)
            print("  Sample %s: ch0_x=0x%04x(dist=%d), ch6_x=0x%04x(dist=%d)" % (
                r['Sample in Buffer'], ch0_x, ch0_d, ch6_x, ch6_d))

    elif ch0_dist_nonzero > 0:
        print("RESULT: ch0_dist is SOMETIMES non-zero when valid!")
        print("This means Stage 3a2 distance calculation has ERRORS.")
        print("The cr2->cr3->cr4 chain is still causing timing violations.")
        print()
        print("Examples of wrong ch0_dist:")
        wrong_cases = [(r, d) for r, d in zip(valid_cycles, ch0_dist_vals) if d != 0]
        for r, d in wrong_cases[:10]:
            ch0_x = int(r.get(col_ch0_x, '0'), 16)
            ch6_x = int(r.get(col_ch6_x, '0'), 16)
            ch6_d = int(r.get(col_ch6_dist, '6'), 16)
            print("  Sample %s: ch0_dist=%d, ch0_x=0x%04x, ch6_dist=%d, ch6_x=0x%04x" % (
                r['Sample in Buffer'], d, ch0_x, ch6_d, ch6_x))

    print()
    print("=== CONCLUSION ===")
    if ch0_dist_0 == len(valid_cycles):
        print("Stage 3a2 is computing CORRECT distances (ch0_dist always = 0).")
        print("The 98% failure rate is caused by something AFTER Stage 3a2.")
        print("Possible causes:")
        print("  1. Stage 3b (min selection) is selecting wrong candidate")
        print("  2. ch_reg stage is introducing timing skew")
        print("  3. MLD-A for-loop is selecting wrong channel")
        print()
        print("NEXT STEP: Need to probe dist_k0_s3a..dist_k4_s3a inside ch0")
        print("to see if Stage 3b is selecting the correct minimum.")
    else:
        print("Stage 3a2 has TIMING ERRORS (ch0_dist != 0 sometimes).")
        print("The cr2->cr3->cr4 chain (~9ns) is still exceeding 10ns budget.")
        print("NEXT STEP: Need to further split Stage 3a2 into 3a2+3a3.")
        print("  Stage 3a2: register cr2 (from cr1_s3a1, ~2ns)")
        print("  Stage 3a3: compute cr3, cr4 from registered cr2, compute distances")
