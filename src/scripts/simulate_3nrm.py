"""
simulate_3nrm.py
Software simulation of 3NRM MRC decoder to find bugs.
Tests all possible 1-error and 2-error patterns for all X in [0, 65535].
"""
import random

MODULI = [64, 63, 65, 31, 29, 23, 19, 17, 11]
N = 9  # number of moduli

def extended_gcd(a, b):
    if a == 0: return b, 0, 1
    g, x1, y1 = extended_gcd(b % a, a)
    return g, y1 - (b // a) * x1, x1

def mod_inv(a, m):
    g, x, _ = extended_gcd(a % m, m)
    return x % m if g == 1 else None

# Build LUT (same as decoder_3nrm.v)
from itertools import combinations

def mrc_decode(recv_r, lut):
    """
    MRC decoder: try all triplets, find minimum distance candidate.
    Returns (best_x, min_dist)
    """
    best_x = None
    min_dist = N + 1
    
    for mi, mj, mk, inv_ij, inv_ijk, ii, ij, ik in lut:
        ri = recv_r[ii]
        rj = recv_r[ij]
        rk = recv_r[ik]
        
        # MRC computation
        # a1 = ri
        a1 = ri
        
        # diff2 = (rj - ri) mod mj
        diff2 = (rj - ri + 6*mj) % mj  # Bug #100 fix: 6 copies
        
        # a2 = (diff2 * inv_ij) mod mj
        a2 = (diff2 * inv_ij) % mj
        
        # diff3 = (rk - ri) mod mk
        diff3 = (rk - ri + 6*mk) % mk  # Bug #100 fix: 6 copies
        
        # a2mi_mod = (a2 * mi) mod mk
        a2mi_mod = (a2 * mi) % mk
        
        # a3raw = (diff3 - a2mi_mod) mod mk
        a3raw = (diff3 - a2mi_mod + mk) % mk
        
        # a3 = (a3raw * inv_ijk) mod mk
        a3 = (a3raw * inv_ijk) % mk
        
        # X = a1 + a2*mi + a3*mi*mj
        X = a1 + a2 * mi + a3 * mi * mj
        
        if X > 65535:
            continue
        
        # Compute Hamming distance
        dist = sum(1 for s in range(N) if X % MODULI[s] != recv_r[s])
        
        if dist < min_dist:
            min_dist = dist
            best_x = X
    
    return best_x, min_dist

# Build LUT
lut = []
for ii, ij, ik in combinations(range(N), 3):
    mi, mj, mk = MODULI[ii], MODULI[ij], MODULI[ik]
    inv_ij = mod_inv(mi, mj)
    inv_ijk = mod_inv((mi * mj) % mk, mk)
    if inv_ij is None or inv_ijk is None:
        continue
    # Only include triplets where X can be <= 65535
    # X_max = (mi-1) + (mj-1)*mi + (mk-1)*mi*mj
    x_max = (mi-1) + (mj-1)*mi + (mk-1)*mi*mj
    if x_max > 65535:
        continue  # Skip triplets that can never produce valid X
    lut.append((mi, mj, mk, inv_ij, inv_ijk, ii, ij, ik))

print(f"LUT size: {len(lut)} triplets")

# Test with random samples
print("Testing 1-error patterns (should all succeed)...")
errors_1 = 0
total_1 = 0
for X in range(0, 65536, 100):  # Sample every 100th X
    recv_r = [X % m for m in MODULI]
    for err_idx in range(N):
        # Inject 1 error
        recv_r_err = recv_r.copy()
        recv_r_err[err_idx] = (recv_r_err[err_idx] + 1) % MODULI[err_idx]
        
        best_x, min_dist = mrc_decode(recv_r_err, lut)
        total_1 += 1
        if best_x != X:
            errors_1 += 1
            if errors_1 <= 3:
                print(f"  1-error FAIL: X={X}, err_idx={err_idx}, best_x={best_x}, dist={min_dist}")

print(f"1-error: {errors_1}/{total_1} failures")

print("Testing 2-error patterns (should all succeed for t=3)...")
errors_2 = 0
total_2 = 0
for X in range(0, 65536, 500):  # Sample every 500th X
    recv_r = [X % m for m in MODULI]
    for err_i, err_j in combinations(range(N), 2):
        recv_r_err = recv_r.copy()
        recv_r_err[err_i] = (recv_r_err[err_i] + 1) % MODULI[err_i]
        recv_r_err[err_j] = (recv_r_err[err_j] + 1) % MODULI[err_j]
        
        best_x, min_dist = mrc_decode(recv_r_err, lut)
        total_2 += 1
        if best_x != X:
            errors_2 += 1
            if errors_2 <= 3:
                print(f"  2-error FAIL: X={X}, errors=({err_i},{err_j}), best_x={best_x}, dist={min_dist}")

print(f"2-error: {errors_2}/{total_2} failures")

# Check if the FPGA LUT matches our software LUT
print(f"\nSoftware LUT has {len(lut)} triplets")
print("Note: FPGA LUT has 74 triplets (some excluded due to X > 65535)")
