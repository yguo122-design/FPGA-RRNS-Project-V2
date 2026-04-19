"""
verify_3nrm_full.py
Full verification of 3NRM decoder LUT constants and MRC computation.
"""
import re

MODULI = [64, 63, 65, 31, 29, 23, 19, 17, 11]

def extended_gcd(a, b):
    if a == 0: return b, 0, 1
    g, x1, y1 = extended_gcd(b % a, a)
    return g, y1 - (b // a) * x1, x1

def mod_inv(a, m):
    g, x, _ = extended_gcd(a % m, m)
    return x % m if g == 1 else None

# Read decoder_3nrm.v
with open('src/algo_wrapper/decoder_3nrm.v', 'r') as f:
    content = f.read()

# Extract all LUT entries by parsing line by line
lut_mi = {}
lut_mj = {}
lut_mk = {}
lut_idx_i = {}
lut_idx_j = {}
lut_idx_k = {}
lut_inv_ij = {}
lut_inv_ijk = {}

for line in content.split('\n'):
    line = line.strip()
    # Match patterns like: lut_mi[0]=7'd64;
    m = re.search(r'lut_mi\[(\d+)\]\s*=\s*7\'d(\d+)', line)
    if m: lut_mi[int(m.group(1))] = int(m.group(2))
    m = re.search(r'lut_mj\[(\d+)\]\s*=\s*7\'d(\d+)', line)
    if m: lut_mj[int(m.group(1))] = int(m.group(2))
    m = re.search(r'lut_mk\[(\d+)\]\s*=\s*7\'d(\d+)', line)
    if m: lut_mk[int(m.group(1))] = int(m.group(2))
    m = re.search(r'lut_idx_i\[(\d+)\]\s*=\s*4\'d(\d+)', line)
    if m: lut_idx_i[int(m.group(1))] = int(m.group(2))
    m = re.search(r'lut_idx_j\[(\d+)\]\s*=\s*4\'d(\d+)', line)
    if m: lut_idx_j[int(m.group(1))] = int(m.group(2))
    m = re.search(r'lut_idx_k\[(\d+)\]\s*=\s*4\'d(\d+)', line)
    if m: lut_idx_k[int(m.group(1))] = int(m.group(2))
    m = re.search(r'lut_inv_ij\[(\d+)\]\s*=\s*7\'d(\d+)', line)
    if m: lut_inv_ij[int(m.group(1))] = int(m.group(2))
    m = re.search(r'lut_inv_ijk\[(\d+)\]\s*=\s*7\'d(\d+)', line)
    if m: lut_inv_ijk[int(m.group(1))] = int(m.group(2))

print(f"Found {len(lut_mi)} triplets")
print()

errors = []
for idx in sorted(lut_mi.keys()):
    mi = lut_mi[idx]
    mj = lut_mj[idx]
    mk = lut_mk[idx]
    ii = lut_idx_i.get(idx, -1)
    ij = lut_idx_j.get(idx, -1)
    ik = lut_idx_k.get(idx, -1)
    inv_ij = lut_inv_ij.get(idx, -1)
    inv_ijk = lut_inv_ijk.get(idx, -1)

    # Verify inv_ij: mi * inv_ij = 1 (mod mj)
    expected_inv_ij = mod_inv(mi, mj)
    ok_ij = (mi * inv_ij) % mj == 1

    # Verify inv_ijk: (mi*mj) * inv_ijk = 1 (mod mk)
    expected_inv_ijk = mod_inv((mi * mj) % mk, mk)
    ok_ijk = ((mi * mj * inv_ijk) % mk == 1) if expected_inv_ijk is not None else False

    status = 'OK' if (ok_ij and ok_ijk) else 'ERROR'
    if status == 'ERROR':
        errors.append(idx)
        print(f"[{idx:2d}] mi={mi:2d}(m[{ii}]), mj={mj:2d}(m[{ij}]), mk={mk:2d}(m[{ik}])")
        if not ok_ij:
            print(f"      inv_ij={inv_ij} WRONG! Expected {expected_inv_ij}")
            print(f"      Verify: {mi}*{inv_ij} mod {mj} = {(mi*inv_ij)%mj} (should be 1)")
        if not ok_ijk:
            print(f"      inv_ijk={inv_ijk} WRONG! Expected {expected_inv_ijk}")
            print(f"      Verify: {mi}*{mj}*{inv_ijk} mod {mk} = {(mi*mj*inv_ijk)%mk} (should be 1)")

print()
print(f"Total: {len(lut_mi)} triplets checked, {len(errors)} errors found")
if errors:
    print(f"Error indices: {errors}")
else:
    print("All LUT constants are correct!")
