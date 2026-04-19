"""
verify_3nrm_lut.py
Verify all 84 triplet LUT constants in decoder_3nrm.v

For each triplet (Mi, Mj, Mk):
  inv_ij  = inv(Mi mod Mj, Mj)   -- modular inverse of Mi in Mj
  inv_ijk = inv(Mi*Mj mod Mk, Mk) -- modular inverse of Mi*Mj in Mk

MRC formula:
  a1 = ri
  diff2 = (rj - ri) mod Mj
  a2 = diff2 * inv_ij mod Mj
  diff3 = (rk - ri) mod Mk
  a3_raw = (diff3 - a2*Mi mod Mk) mod Mk
  a3 = a3_raw * inv_ijk mod Mk
  X = a1 + a2*Mi + a3*Mi*Mj
"""

def mod_inv(a, m):
    """Extended Euclidean algorithm to find modular inverse of a mod m."""
    if m == 1:
        return 0
    g, x, _ = extended_gcd(a % m, m)
    if g != 1:
        return None  # No inverse exists
    return x % m

def extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    g, x, y = extended_gcd(b % a, a)
    return g, y - (b // a) * x, x

# Moduli set
MODS = [64, 63, 65, 31, 29, 23, 19, 17, 11]

# LUT from decoder_3nrm.v (extracted)
# Format: (mi, mj, mk, inv_ij, inv_ijk, idx_i, idx_j, idx_k)
LUT = [
    (64,63,65,  1, 33, 0,1,2),
    (64,63,31,  1, 16, 0,1,3),
    (64,63,29,  1,  1, 0,1,4),
    (64,63,23,  1, 10, 0,1,5),
    (64,63,19,  1,  5, 0,1,6),
    (64,63,17,  1,  6, 0,1,7),
    (64,63,11,  1,  2, 0,1,8),
    (64,65,31, 64, 26, 0,2,3),
    (64,65,29, 64,  9, 0,2,4),
    (64,65,23, 64, 15, 0,2,5),
    (64,65,19, 64, 18, 0,2,6),
    (64,65,17, 64, 10, 0,2,7),
    (64,65,11, 64,  6, 0,2,8),
    (64,31,29, 16, 17, 0,3,4),
    (64,31,23, 16,  4, 0,3,5),
    (64,31,19, 16, 12, 0,3,6),
    (64,31,17, 16, 10, 0,3,7),
    (64,31,11, 16,  3, 0,3,8),
    (64,29,23,  5, 13, 0,4,5),
    (64,29,19,  5,  3, 0,4,6),
    (64,29,17,  5,  6, 0,4,7),
    (64,29,11,  5,  7, 0,4,8),
    (64,23,19,  9, 17, 0,5,6),
    (64,23,17,  9, 12, 0,5,7),
    (64,23,11,  9,  5, 0,5,8),
    (64,19,17, 11,  2, 0,6,7),
    (64,19,11, 11,  2, 0,6,8),
    (64,17,11,  4, 10, 0,7,8),
    (63,65,31, 32, 21, 1,2,3),
    (63,65,29, 32,  5, 1,2,4),
    (63,65,23, 32,  1, 1,2,5),
    (63,65,19, 32,  2, 1,2,6),
    (63,65,17, 32,  8, 1,2,7),
    (63,65,11, 32,  4, 1,2,8),
    (63,31,29,  1,  3, 1,3,4),
    (63,31,23,  1, 11, 1,3,5),
    (63,31,19,  1, 14, 1,3,6),
    (63,31,17,  1,  8, 1,3,7),
    (63,31,11,  1,  2, 1,3,8),
    (63,29,23,  6,  7, 1,4,5),
    (63,29,19,  6, 13, 1,4,6),
    (63,29,17,  6, 15, 1,4,7),
    (63,29,11,  6,  1, 1,4,8),
    (63,23,19, 19,  4, 1,5,6),
    (63,23,17, 19, 13, 1,5,7),
    (63,23,11, 19,  7, 1,5,8),
    (63,19,17, 16,  5, 1,6,7),
    (63,19,11, 16,  5, 1,6,8),
    (63,17,11, 10,  3, 1,7,8),
    (65,31,29, 21, 27, 2,3,4),
    (65,31,23, 21,  5, 2,3,5),
    (65,31,19, 21,  1, 2,3,6),
    (65,31,17, 21,  2, 2,3,7),
    (65,31,11, 21,  6, 2,3,8),
    (65,29,23, 25, 22, 2,4,5),
    (65,29,19, 25,  5, 2,4,6),
    (65,29,17, 25,  8, 2,4,7),
    (65,29,11, 25,  3, 2,4,8),
    (65,23,19, 17,  3, 2,5,6),
    (65,23,17, 17, 16, 2,5,7),
    (65,23,11, 17, 10, 2,5,8),
    (65,19,17, 12, 14, 2,6,7),
    (65,19,11, 12,  4, 2,6,8),
    (65,17,11, 11,  9, 2,7,8),
    (31,29,23, 15, 12, 3,4,5),
    (31,29,19, 15, 16, 3,4,6),
    (31,29,17, 15,  8, 3,4,7),
    (31,29,11, 15,  7, 3,4,8),
    (31,23,19,  3,  2, 3,5,6),
    (31,23,17,  3, 16, 3,5,7),
    (31,23,11,  3,  5, 3,5,8),
    (31,19,17,  8, 14, 3,6,7),
    (31,19,11,  8,  2, 3,6,8),
    (31,17,11, 11, 10, 3,7,8),
    (29,23,19,  4, 10, 4,5,6),
    (29,23,17,  4, 13, 4,5,7),
    (29,23,11,  4,  8, 4,5,8),
    (29,19,17,  2,  5, 4,6,7),
    (29,19,11,  2,  1, 4,6,8),
    (29,17,11, 10,  5, 4,7,8),
    (23,19,17,  5, 10, 5,6,7),
    (23,19,11,  5,  7, 5,6,8),
    (23,17,11,  3,  2, 5,7,8),
    (19,17,11,  9,  3, 6,7,8),
]

errors = []
warnings = []

print("Verifying all 84 triplet LUT constants in decoder_3nrm.v...")
print("=" * 70)

for idx, (mi, mj, mk, inv_ij_lut, inv_ijk_lut, ii, ij, ik) in enumerate(LUT):
    # Verify moduli match MODS indices
    assert MODS[ii] == mi, f"Triplet {idx}: MODS[{ii}]={MODS[ii]} != mi={mi}"
    assert MODS[ij] == mj, f"Triplet {idx}: MODS[{ij}]={MODS[ij]} != mj={mj}"
    assert MODS[ik] == mk, f"Triplet {idx}: MODS[{ik}]={MODS[ik]} != mk={mk}"

    # Compute expected inv_ij = inv(Mi mod Mj, Mj)
    mi_mod_mj = mi % mj
    inv_ij_expected = mod_inv(mi_mod_mj, mj)

    # Compute expected inv_ijk = inv(Mi*Mj mod Mk, Mk)
    mimj_mod_mk = (mi * mj) % mk
    inv_ijk_expected = mod_inv(mimj_mod_mk, mk)

    # Check inv_ij
    if inv_ij_expected is None:
        errors.append(f"Triplet {idx:2d} ({mi},{mj},{mk}): inv_ij has no inverse! mi%mj={mi_mod_mj}")
    elif inv_ij_lut != inv_ij_expected:
        errors.append(f"Triplet {idx:2d} ({mi},{mj},{mk}): inv_ij WRONG! LUT={inv_ij_lut}, expected={inv_ij_expected} (mi%mj={mi_mod_mj})")
    
    # Check inv_ijk
    if inv_ijk_expected is None:
        errors.append(f"Triplet {idx:2d} ({mi},{mj},{mk}): inv_ijk has no inverse! mi*mj%mk={mimj_mod_mk}")
    elif inv_ijk_lut != inv_ijk_expected:
        errors.append(f"Triplet {idx:2d} ({mi},{mj},{mk}): inv_ijk WRONG! LUT={inv_ijk_lut}, expected={inv_ijk_expected} (mi*mj%mk={mimj_mod_mk})")

    # Also verify MRC correctness with a test value
    # Test: encode X=12345, decode, check we get 12345 back
    X_test = 12345
    ri = X_test % mi
    rj = X_test % mj
    rk = X_test % mk

    # MRC decode
    a1 = ri
    diff2 = (rj - ri) % mj
    a2 = (diff2 * inv_ij_lut) % mj
    diff3 = (rk - ri) % mk
    a2mi_mod_mk = (a2 * mi) % mk
    a3raw = (diff3 - a2mi_mod_mk) % mk
    a3 = (a3raw * inv_ijk_lut) % mk
    X_decoded = a1 + a2 * mi + a3 * mi * mj

    if X_decoded != X_test:
        errors.append(f"Triplet {idx:2d} ({mi},{mj},{mk}): MRC decode WRONG! X_test={X_test}, X_decoded={X_decoded}")

print(f"Checked {len(LUT)} triplets.")
print()

if errors:
    print(f"ERRORS FOUND ({len(errors)}):")
    for e in errors:
        print(f"  ❌ {e}")
else:
    print("✅ All 84 triplet LUT constants are CORRECT!")
    print("   inv_ij and inv_ijk values verified mathematically.")
    print("   MRC decode verified with X=12345 for all triplets.")

print()
print("=" * 70)

# Additional: test MRC with multiple X values to find any edge cases
print("\nTesting MRC decode with multiple X values (0, 1000, 12345, 50000, 65535)...")
test_values = [0, 1, 1000, 12345, 50000, 65535]
mrc_errors = []

for X_test in test_values:
    for idx, (mi, mj, mk, inv_ij_lut, inv_ijk_lut, ii, ij, ik) in enumerate(LUT):
        ri = X_test % mi
        rj = X_test % mj
        rk = X_test % mk

        a1 = ri
        diff2 = (rj - ri) % mj
        a2 = (diff2 * inv_ij_lut) % mj
        diff3 = (rk - ri) % mk
        a2mi_mod_mk = (a2 * mi) % mk
        a3raw = (diff3 - a2mi_mod_mk) % mk
        a3 = (a3raw * inv_ijk_lut) % mk
        X_decoded = a1 + a2 * mi + a3 * mi * mj

        if X_decoded != X_test:
            mrc_errors.append(f"X={X_test}, Triplet {idx} ({mi},{mj},{mk}): decoded={X_decoded}")

if mrc_errors:
    print(f"MRC ERRORS ({len(mrc_errors)}):")
    for e in mrc_errors:
        print(f"  ❌ {e}")
else:
    print("✅ All MRC decode tests passed for all X values and all triplets!")
