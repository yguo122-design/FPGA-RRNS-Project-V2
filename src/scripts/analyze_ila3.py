"""
analyze_ila3.py - Analyze ILA data from iladata0327-3.csv
Verify the Serial decoder's output against MATLAB MLD reference.
"""

# ILA captured values at trigger (valid=1, uncorrectable=0)
recv_r = [0x096, 0x02f, 0x004, 0x074, 0x021, 0x011]
moduli = [257, 256, 61, 59, 55, 53]
names = ['r257', 'r256', 'r61', 'r59', 'r55', 'r53']
ila_best_x = 0xDF74  # = 57204
ila_min_dist = 0

print("=== ILA Captured Values ===")
print("Received residues:")
for i, (r, m, n) in enumerate(zip(recv_r, moduli, names)):
    valid = r < m
    status = "VALID" if valid else f"INVALID! {r} >= {m}"
    print(f"  recv_r[{i}] = 0x{r:03x} = {r:3d} ({n}, mod {m}) - {status}")

print(f"\nILA decoder output: best_x = 0x{ila_best_x:04x} = {ila_best_x}, min_dist = {ila_min_dist}")

# MATLAB MLD reference
def extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    g, x1, y1 = extended_gcd(b % a, a)
    return g, y1 - (b // a) * x1, x1

def mod_inv(a, m):
    g, x, _ = extended_gcd(a % m, m)
    return x % m if g == 1 else None

print("\n=== MATLAB MLD Reference ===")
best_X = None
min_dist = 7
pairs = [(i, j) for i in range(6) for j in range(i+1, 6)]

for ii, ij in pairs:
    mi, mj = moduli[ii], moduli[ij]
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
        dist = sum(1 for s in range(6) if X % moduli[s] != recv_r[s])
        if dist < min_dist:
            min_dist = dist
            best_X = X

print(f"MATLAB MLD result: best_X = {best_X} (0x{best_X:04x}), min_dist = {min_dist}")
print(f"\nMatch with ILA: {best_X == ila_best_x and min_dist == ila_min_dist}")

# Verify best_x residues
if best_X is not None:
    print(f"\nVerification of best_X = {best_X}:")
    for i, (m, n) in enumerate(zip(moduli, names)):
        calc = best_X % m
        recv = recv_r[i]
        match = "OK" if calc == recv else f"MISMATCH! calc={calc}, recv={recv}"
        print(f"  {best_X} % {m} = {calc}, recv_r[{i}]={recv} - {match}")
