"""
analyze_ila4_serial.py - Analyze iladata0327-4.csv
Look for uncorrectable=1 cases and verify against MATLAB MLD.

CSV column order (from header):
  cand_k, best_x, state, recv_r[0], recv_r[2], recv_r[4], recv_r[1], recv_r[3], recv_r[5],
  pair_idx, min_dist, uncorrectable, valid
"""
import csv

MODULI = [257, 256, 61, 59, 55, 53]

def extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    g, x1, y1 = extended_gcd(b % a, a)
    return g, y1 - (b // a) * x1, x1

def mod_inv(a, m):
    g, x, _ = extended_gcd(a % m, m)
    return x % m if g == 1 else None

def matlab_mld(recv_r):
    """Run MATLAB-equivalent MLD on recv_r[0..5]"""
    best_X = None
    min_dist = 7
    pairs = [(i, j) for i in range(6) for j in range(i+1, 6)]
    for ii, ij in pairs:
        mi, mj = MODULI[ii], MODULI[ij]
        ri, rj = recv_r[ii], recv_r[ij]
        inv = mod_inv(mi, mj)
        if inv is None:
            continue
        PERIOD = mi * mj
        diff = (rj - ri + mj) % mj
        coeff = (diff * inv) % mj
        X_base = ri + mi * coeff
        for k in range(23):
            X = X_base + k * PERIOD
            if X > 65535:
                break
            dist = sum(1 for s in range(6) if X % MODULI[s] != recv_r[s])
            if dist < min_dist:
                min_dist = dist
                best_X = X
    return best_X, min_dist

# Read CSV
with open('D:/FPGAproject/FPGA-RRNS-Project-V2/result/iladata0327-4.csv', 'r') as f:
    reader = csv.reader(f)
    rows = list(reader)

print(f"Total rows: {len(rows)}")
print(f"Header: {rows[0]}")
print()

# Find trigger and valid/uncorrectable events
trigger_rows = []
valid_rows = []
uncorr_rows = []
state_changes = []
prev_state = None

for i, row in enumerate(rows[2:], 2):
    if len(row) < 16:
        continue
    if row[2] == '1':
        trigger_rows.append(i)
    if row[15] == '1':
        valid_rows.append(i)
    if row[14] == '1':
        uncorr_rows.append(i)
    if row[5] != prev_state:
        state_changes.append((i, row[5]))
        prev_state = row[5]

print(f"Trigger points: {trigger_rows[:5]}")
print(f"Rows with valid=1: {valid_rows[:10]}")
print(f"Rows with uncorrectable=1: {uncorr_rows[:10]}")
print(f"Total state changes: {len(state_changes)}")
print()

# Analyze each valid=1 event
print("=== Analysis of valid=1 events ===")
for row_idx in valid_rows[:5]:  # Analyze first 5
    row = rows[row_idx]
    # Parse values (CSV column order: cand_k, best_x, state, r[0], r[2], r[4], r[1], r[3], r[5], pair_idx, min_dist, uncorr, valid)
    cand_k = int(row[3], 16)
    best_x = int(row[4], 16)
    state = int(row[5], 16)
    # recv_r in CSV order: [0],[2],[4],[1],[3],[5]
    recv_csv = [int(row[6], 16), int(row[7], 16), int(row[8], 16),
                int(row[9], 16), int(row[10], 16), int(row[11], 16)]
    # Reorder to [0,1,2,3,4,5]
    recv_r = [recv_csv[0], recv_csv[3], recv_csv[1], recv_csv[4], recv_csv[2], recv_csv[5]]
    pair_idx = int(row[12], 16)
    min_dist = int(row[13], 16)
    uncorr = int(row[14])
    valid = int(row[15])

    print(f"\nRow {row_idx} (sample {row[0]}): valid={valid}, uncorr={uncorr}")
    print(f"  ILA: best_x=0x{best_x:04x}={best_x}, min_dist={min_dist}, pair_idx={pair_idx}")
    print(f"  recv_r = {[hex(r) for r in recv_r]}")

    # Validate recv_r
    all_valid = all(r < m for r, m in zip(recv_r, MODULI))
    if not all_valid:
        for i, (r, m) in enumerate(zip(recv_r, MODULI)):
            if r >= m:
                print(f"  WARNING: recv_r[{i}]={r} >= mod {m}!")

    # Run MATLAB MLD
    matlab_x, matlab_dist = matlab_mld(recv_r)
    match = (best_x == matlab_x and min_dist == matlab_dist)
    print(f"  MATLAB: best_X=0x{matlab_x:04x}={matlab_x}, min_dist={matlab_dist}")
    print(f"  Match: {match}")

    if not match:
        print(f"  *** MISMATCH! Serial decoder gave wrong result! ***")
        # Verify ILA best_x
        ila_actual_dist = sum(1 for s in range(6) if best_x % MODULI[s] != recv_r[s])
        print(f"  Actual distance of ILA best_x: {ila_actual_dist}")

# Summary
print(f"\n=== Summary ===")
print(f"Total valid=1 events: {len(valid_rows)}")
print(f"Total uncorrectable=1 events: {len(uncorr_rows)}")
if uncorr_rows:
    print(f"First uncorrectable at row: {uncorr_rows[0]}")
    row = rows[uncorr_rows[0]]
    recv_csv = [int(row[6], 16), int(row[7], 16), int(row[8], 16),
                int(row[9], 16), int(row[10], 16), int(row[11], 16)]
    recv_r = [recv_csv[0], recv_csv[3], recv_csv[1], recv_csv[4], recv_csv[2], recv_csv[5]]
    best_x = int(row[4], 16)
    min_dist = int(row[13], 16)
    matlab_x, matlab_dist = matlab_mld(recv_r)
    print(f"  ILA: best_x=0x{best_x:04x}, min_dist={min_dist}")
    print(f"  MATLAB: best_X=0x{matlab_x:04x}, min_dist={matlab_dist}")
    print(f"  recv_r = {[hex(r) for r in recv_r]}")
    if matlab_dist <= 2:
        print(f"  *** BUG: MATLAB can decode (dist={matlab_dist}) but Serial declared uncorrectable! ***")
