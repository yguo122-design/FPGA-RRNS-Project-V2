"""
gen_missing_triplets.py
Generate the 10 missing triplet LUT entries for decoder_3nrm.v Bug #103 fix.
"""
MODULI = [64, 63, 65, 31, 29, 23, 19, 17, 11]

def extended_gcd(a, b):
    if a == 0: return b, 0, 1
    g, x1, y1 = extended_gcd(b % a, a)
    return g, y1 - (b // a) * x1, x1

def mod_inv(a, m):
    g, x, _ = extended_gcd(a % m, m)
    return x % m if g == 1 else None

# The 10 missing triplets (index pairs)
missing = [(0,1,2),(0,1,3),(0,1,4),(0,1,5),(0,1,6),(0,1,7),(0,1,8),(0,2,3),(0,2,4),(0,2,5)]

print("// Bug #103 fix: 10 missing triplets (indices 74..83)")
print("// These triplets involve large moduli (64,63,65) and were incorrectly excluded.")
print("// X_max may exceed 65535 for some residue combinations, but the runtime check")
print("// 'mrc_x <= 18'd65535' filters invalid X values. These triplets are needed")
print("// when errors hit residues 0 (mod 64) and 1 (mod 63) simultaneously.")
print()

for n, (ii, ij, ik) in enumerate(missing):
    mi, mj, mk = MODULI[ii], MODULI[ij], MODULI[ik]
    inv_ij = mod_inv(mi, mj)
    inv_ijk = mod_inv((mi * mj) % mk, mk)
    idx = 74 + n
    
    # Verify
    ok_ij = (mi * inv_ij) % mj == 1
    ok_ijk = (mi * mj * inv_ijk) % mk == 1
    
    print(f"        lut_mi[{idx}]=7'd{mi}; lut_mj[{idx}]=7'd{mj}; lut_mk[{idx}]=7'd{mk};")
    print(f"        lut_inv_ij[{idx}]=7'd{inv_ij}; lut_inv_ijk[{idx}]=7'd{inv_ijk};")
    print(f"        lut_idx_i[{idx}]=4'd{ii}; lut_idx_j[{idx}]=4'd{ij}; lut_idx_k[{idx}]=4'd{ik};")
    print(f"        // m[{ii}]={mi}, m[{ij}]={mj}, m[{ik}]={mk}: inv_ij ok={ok_ij}, inv_ijk ok={ok_ijk}")
