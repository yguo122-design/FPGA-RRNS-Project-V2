"""
ILA Data 7 Analysis - After Bug #41 fix (v2.21, Stage 3a2+3a3 split)
Expected: comp_latency_a = 27, ch_dist_reg[0] = 0 when valid
"""
import csv
import os
from collections import Counter

csv_path = 'src/scripts/iladata7.csv'
if not os.path.exists(csv_path):
    print("ERROR: iladata7.csv not found")
    exit(1)

rows = []
with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

print("Total rows:", len(rows))
cols = list(rows[0].keys())
print("\n=== All Column Names ===")
for c in cols:
    print(" ", repr(c))
print()

# Filter valid data
data = [r for r in rows if r.get('Sample in Buffer', '') not in
        ['Radix - UNSIGNED', 'UNSIGNED', '', 'Sample in Buffer']]
print("Valid data rows:", len(data))

# Find relevant columns
def find_col(cols, pattern):
    matches = [c for c in cols if pattern in c]
    return matches[0] if matches else None

col_ch0_dist  = find_col(cols, 'ch_dist_reg[0]')
col_ch0_x     = find_col(cols, 'ch_x_reg[0]')
col_ch6_x     = find_col(cols, 'ch_x_reg[6]')
col_ch6_dist  = find_col(cols, 'ch_dist_reg[6]')
col_ch0_valid = find_col(cols, 'ch_valid_reg[0]')

print("\n=== Column Mapping ===")
print("ch0_dist: ", col_ch0_dist)
print("ch0_x:    ", col_ch0_x)
print("ch6_x:    ", col_ch6_x)
print("ch6_dist: ", col_ch6_dist)
print("ch0_valid:", col_ch0_valid)

# Find valid cycles
if col_ch0_valid:
    valid_cycles = [r for r in data if r.get(col_ch0_valid, '0') == '1']
    print("\nCycles where ch_valid_reg[0] = 1:", len(valid_cycles))

    if valid_cycles:
        # Analyze ch0_dist
        ch0_dist_vals = []
        for r in valid_cycles:
            try:
                ch0_dist_vals.append(int(r.get(col_ch0_dist, '6'), 16))
            except:
                ch0_dist_vals.append(6)

        dist_counter = Counter(ch0_dist_vals)
        print("\nch_dist_reg[0] distribution when valid:")
        for d, cnt in sorted(dist_counter.items()):
            print("  dist=%d: %d/%d (%.1f%%)" % (d, cnt, len(valid_cycles), 100.0*cnt/len(valid_cycles)))

        ch0_dist_0 = sum(1 for d in ch0_dist_vals if d == 0)
        print("\nch0_dist = 0 (correct): %d/%d (%.1f%%)" % (
            ch0_dist_0, len(valid_cycles), 100.0*ch0_dist_0/len(valid_cycles)))

        print("\n=== KEY DIAGNOSTIC ===")
        if ch0_dist_0 == len(valid_cycles):
            print("GOOD: ch0_dist is ALWAYS 0 - Stage 3a3 distance calculation is CORRECT!")
            print("The problem must be in Stage 3b (min selection) or MLD stage.")
        elif ch0_dist_0 > 0:
            print("PARTIAL: ch0_dist is sometimes 0 (%d/%d)" % (ch0_dist_0, len(valid_cycles)))
            print("Stage 3a3 is partially working but still has timing issues.")
        else:
            print("FAIL: ch0_dist is NEVER 0 - Stage 3a3 still has timing errors!")
            print("The cr3->cr4 chain (~4ns) + dist_k4 (~7ns) may still exceed 10ns.")

        # Show first 10 valid cycles
        print("\n=== First 10 valid cycles ===")
        for r in valid_cycles[:10]:
            try:
                ch0_x = int(r.get(col_ch0_x, '0'), 16)
                ch0_d = int(r.get(col_ch0_dist, '6'), 16)
                ch6_x = int(r.get(col_ch6_x, '0'), 16) if col_ch6_x else 0
                ch6_d = int(r.get(col_ch6_dist, '6'), 16) if col_ch6_dist else 6
                print("  Sample %s: ch0_x=0x%04x dist=%d | ch6_x=0x%04x dist=%d" % (
                    r['Sample in Buffer'], ch0_x, ch0_d, ch6_x, ch6_d))
            except Exception as e:
                print("  Error:", e, dict(r))
    else:
        print("\nWARNING: No valid cycles found!")
        # Show distribution of ch0_dist
        if col_ch0_dist:
            dist_dist = Counter(r.get(col_ch0_dist, 'N/A') for r in data)
            print("ch_dist_reg[0] distribution:", dict(dist_dist))
        # Show non-6 dist samples
        if col_ch0_dist:
            non_6 = [r for r in data if r.get(col_ch0_dist, '6') not in ['6', '06']]
            print("Samples where ch0_dist != 6:", len(non_6))
            for r in non_6[:5]:
                print("  Sample", r['Sample in Buffer'],
                      "ch0_dist=", r.get(col_ch0_dist),
                      "ch0_valid=", r.get(col_ch0_valid, 'N/A'))
else:
    print("\nWARNING: ch_valid_reg[0] column not found!")
    print("Available columns:", [c for c in cols if 'ch' in c.lower()])
