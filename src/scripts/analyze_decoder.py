"""
Decoder analysis script for Bug #36 investigation
Analyzes why the 2NRM decoder fails for sym_a=61302 after Bug #35 fix
"""
import math

# ============================================================
# Setup: sym_a=61302, injected bit35 error in r257 field
# ============================================================
sym_a = 61302
moduli = [257, 256, 61, 59, 55, 53]
recv_r_orig = [sym_a % m for m in moduli]

# Decode packed residues from ILA data
enc = 0x08876e81822
inj = 0x08076e81822
r257_inj = (inj >> 32) & 0x1FF
r256_inj = (inj >> 24) & 0xFF
r61_inj  = (inj >> 18) & 0x3F
r59_inj  = (inj >> 12) & 0x3F
r55_inj  = (inj >> 6)  & 0x3F
r53_inj  = (inj >> 0)  & 0x3F

recv_r_inj = [r257_inj, r256_inj, r61_inj, r59_inj, r55_inj, r53_inj]
print("sym_a =", sym_a)
print("Original residues:", recv_r_orig)
print("Injected residues:", recv_r_inj)
print("Changed: index 0 (r257):", recv_r_orig[0], "->", recv_r_inj[0])
print()

# Channel definitions: (ch_id, M1, M2, INV, idx1, idx2)
channels = [
    (0,  257, 256, 1,  0, 1),
    (1,  257, 61,  48, 0, 2),
    (2,  257, 59,  45, 0, 3),
    (3,  257, 55,  3,  0, 4),
    (4,  257, 53,  33, 0, 5),
    (5,  256, 61,  56, 1, 2),
    (6,  256, 59,  3,  1, 3),
    (7,  256, 55,  26, 1, 4),
    (8,  256, 53,  47, 1, 5),
    (9,  61,  59,  30, 2, 3),
    (10, 61,  55,  46, 2, 4),
    (11, 61,  53,  20, 2, 5),
    (12, 59,  55,  14, 3, 4),
    (13, 59,  53,  9,  3, 5),
    (14, 55,  53,  27, 4, 5),
]

# ============================================================
# Analysis 1: K_MAX needed for each channel
# ============================================================
print("Channel Analysis: PERIOD and K_MAX needed to cover [0, 65535]")
print("="*70)
print("Bug #35 fix uses k=0,1,2,3,4 (K_MAX=5)")
print()
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    k_max = math.ceil(65535 / period)
    covered = "YES" if k_max <= 5 else "NO (need k=0..%d)" % (k_max-1)
    print("Ch%2d: M1=%3d, M2=%3d, PERIOD=%6d, K_MAX=%3d -> %s" % (
        ch, m1, m2, period, k_max, covered))

print()

# ============================================================
# Analysis 2: All 15 channels for sym_a=61302
# ============================================================
print("All 15 channels analysis for sym_a=%d:" % sym_a)
print("="*80)

global_best_dist = 6
global_best_x = 0

for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_inj[idx1]
    rj = recv_r_inj[idx2]
    
    # CRT reconstruction
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    
    # Compute dist_k0
    cand_r_k0 = [x_cand_k0 % m for m in moduli]
    dist_k0 = sum(1 for i in range(6) if cand_r_k0[i] != recv_r_inj[i])
    
    # Find best candidate among k=0..4
    best_dist = 6
    best_x = x_cand_k0
    
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_inj[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
    
    correct = "YES" if best_x == sym_a else "NO"
    if best_dist < global_best_dist:
        global_best_dist = best_dist
        global_best_x = best_x
    
    print("Ch%2d: x_k0=%6d(dist=%d), best_x=%6d(dist=%d) -> correct=%s" % (
        ch, x_cand_k0, dist_k0, best_x, best_dist, correct))

print()
print("Global MLD result: x=%d, dist=%d" % (global_best_x, global_best_dist))
print("Correct answer: x=%d" % sym_a)
print("MLD correct?", global_best_x == sym_a)
print()

# ============================================================
# Analysis 3: Channels 9-14 detailed (small PERIOD)
# ============================================================
print("Detailed analysis for channels 9-14 (small PERIOD, need more k):")
print("="*80)
for ch, m1, m2, inv, idx1, idx2 in channels[9:]:
    period = m1 * m2
    ri = recv_r_inj[idx1]
    rj = recv_r_inj[idx2]
    
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    
    print("Channel %d (M1=%d, M2=%d, PERIOD=%d):" % (ch, m1, m2, period))
    print("  ri=%d, rj=%d, x_cand_k0=%d" % (ri, rj, x_cand_k0))
    
    # Find the k that gives x=sym_a
    k_correct = None
    for k in range(30):
        x_k = x_cand_k0 + k * period
        if x_k == sym_a:
            k_correct = k
            break
        if x_k > 65535:
            break
    
    if k_correct is not None:
        print("  Correct answer at k=%d: x=%d" % (k_correct, x_cand_k0 + k_correct * period))
        if k_correct <= 4:
            print("  -> COVERED by Bug #35 fix (k<=4)")
        else:
            print("  -> NOT COVERED by Bug #35 fix (k=%d > 4)!" % k_correct)
    else:
        print("  Correct answer NOT reachable from this channel!")
    
    # Show best k=0..4 result
    best_dist = 6
    best_x = x_cand_k0
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_inj[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
    print("  Best with k=0..4: x=%d, dist=%d" % (best_x, best_dist))
    
    # Show what happens with full k range
    best_dist_full = 6
    best_x_full = x_cand_k0
    for k in range(30):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_inj[i])
        if dist < best_dist_full:
            best_dist_full = dist
            best_x_full = x_k
    print("  Best with full k range: x=%d, dist=%d" % (best_x_full, best_dist_full))
    print()

# ============================================================
# Analysis 4: What is the correct fix?
# ============================================================
print("="*80)
print("CORRECT FIX ANALYSIS:")
print("="*80)
print()
print("For channels 9-14 (small PERIOD), K_MAX can be up to 23.")
print("Bug #35 only covers k=0..4, which is INSUFFICIENT for these channels.")
print()
print("The correct fix requires K_MAX = ceil(65535 / PERIOD) for each channel:")
print()

for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    k_max_needed = math.ceil(65535 / period)
    print("  Ch%2d: PERIOD=%6d, K_MAX_NEEDED=%3d" % (ch, period, k_max_needed))

print()
print("Maximum K_MAX across all channels:", max(math.ceil(65535 / (m1*m2)) for _, m1, m2, _, _, _ in channels))
print()

# ============================================================
# Analysis 5: Verify with full k range
# ============================================================
print("Verification with full k range (K_MAX=23 for all channels):")
print("="*80)

global_best_dist_full = 6
global_best_x_full = 0

for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_inj[idx1]
    rj = recv_r_inj[idx2]
    
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    
    k_max = math.ceil(65535 / period)
    best_dist = 6
    best_x = x_cand_k0
    
    for k in range(k_max + 1):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_inj[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
    
    if best_dist < global_best_dist_full:
        global_best_dist_full = best_dist
        global_best_x_full = best_x

print("Global MLD result with full k range: x=%d, dist=%d" % (global_best_x_full, global_best_dist_full))
print("Correct answer: x=%d" % sym_a)
print("MLD correct with full k range?", global_best_x_full == sym_a)
print()

# ============================================================
# Analysis 6: Statistical analysis - what fraction of sym_a values fail?
# ============================================================
print("="*80)
print("Statistical analysis: failure rate for random sym_a with 1-bit error")
print("="*80)

import random
random.seed(42)

total = 1000
fail_k5 = 0
fail_full = 0

for _ in range(total):
    x = random.randint(0, 65535)
    orig_r = [x % m for m in moduli]
    
    # Inject 1 random bit error in the packed 41-bit codeword
    bit_pos = random.randint(0, 40)
    inj_r = orig_r.copy()
    
    # Determine which residue field is affected
    if bit_pos >= 32:  # r257 field [40:32]
        field_bit = bit_pos - 32
        inj_r[0] = (orig_r[0] ^ (1 << field_bit)) % 257
    elif bit_pos >= 24:  # r256 field [31:24]
        field_bit = bit_pos - 24
        inj_r[1] = (orig_r[1] ^ (1 << field_bit)) % 256
    elif bit_pos >= 18:  # r61 field [23:18]
        field_bit = bit_pos - 18
        inj_r[2] = (orig_r[2] ^ (1 << field_bit)) % 61
    elif bit_pos >= 12:  # r59 field [17:12]
        field_bit = bit_pos - 12
        inj_r[3] = (orig_r[3] ^ (1 << field_bit)) % 59
    elif bit_pos >= 6:   # r55 field [11:6]
        field_bit = bit_pos - 6
        inj_r[4] = (orig_r[4] ^ (1 << field_bit)) % 55
    else:                # r53 field [5:0]
        field_bit = bit_pos
        inj_r[5] = (orig_r[5] ^ (1 << field_bit)) % 53
    
    # MLD with k=0..4
    best_dist_k5 = 6
    best_x_k5 = 0
    
    # MLD with full k range
    best_dist_full = 6
    best_x_full = 0
    
    for ch, m1, m2, inv, idx1, idx2 in channels:
        period = m1 * m2
        ri = inj_r[idx1]
        rj = inj_r[idx2]
        
        diff = (rj + m2 - ri) % m2
        coeff = (diff * inv) % m2
        x_cand_k0 = ri + m1 * coeff
        
        # k=0..4
        for k in range(5):
            x_k = x_cand_k0 + k * period
            if x_k > 65535:
                break
            cand_r = [x_k % m for m in moduli]
            dist = sum(1 for i in range(6) if cand_r[i] != inj_r[i])
            if dist < best_dist_k5:
                best_dist_k5 = dist
                best_x_k5 = x_k
        
        # Full k range
        k_max = math.ceil(65535 / period)
        for k in range(k_max + 1):
            x_k = x_cand_k0 + k * period
            if x_k > 65535:
                break
            cand_r = [x_k % m for m in moduli]
            dist = sum(1 for i in range(6) if cand_r[i] != inj_r[i])
            if dist < best_dist_full:
                best_dist_full = dist
                best_x_full = x_k
    
    if best_x_k5 != x:
        fail_k5 += 1
    if best_x_full != x:
        fail_full += 1

print("With k=0..4 (Bug #35 fix): %d/%d failed = %.1f%%" % (fail_k5, total, 100.0*fail_k5/total))
print("With full k range:          %d/%d failed = %.1f%%" % (fail_full, total, 100.0*fail_full/total))
print()
print("CONCLUSION:")
print("Bug #35 fix (k=0..4) is INSUFFICIENT for channels 9-14 (small PERIOD).")
print("Need to extend k range to K_MAX=ceil(65535/PERIOD) per channel.")
print("For channels 9-14, K_MAX can be up to 23.")
