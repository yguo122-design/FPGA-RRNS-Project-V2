"""
analyze_ila3b.py - Re-analyze ILA data with correct column mapping.

The CSV header shows recv_r columns in this order:
  recv_r[0], recv_r[2], recv_r[4], recv_r[1], recv_r[3], recv_r[5]

From iladata0327-3.csv trigger row (sample 1024):
  cand_k=15, best_x=df74, state=0
  recv_r[0]=096, recv_r[2]=02f, recv_r[4]=004
  recv_r[1]=074, recv_r[3]=021, recv_r[5]=011
  pair_idx=e, min_dist=0, uncorr=0, valid=1

Correct reordering to [0,1,2,3,4,5]:
  recv_r[0]=0x096=150 (r257)
  recv_r[1]=0x074=116 (r256)  <- 116 < 256, VALID
  recv_r[2]=0x02f=47  (r61)
  recv_r[3]=0x021=33  (r59)
  recv_r[4]=0x004=4   (r55)
  recv_r[5]=0x011=17  (r53)
"""

# Corrected recv_r mapping (reordered from CSV column order)
recv_r = [0x096, 0x074, 0x02f, 0x021, 0x004, 0x011]
moduli = [257, 256, 61, 59, 55, 53]
names = ['r257', 'r256', 'r61', 'r59', 'r55', 'r53']
ila_best_x = 0xDF74  # = 57204
ila_min_dist = 0

print("=== Corrected ILA Values ===")
print("Received residues (reordered):")
for i, (r, m, n) in enumerate(zip(recv_r, moduli, names)):
    valid = r < m
    status = "VALID" if valid else "INVALID! %d >= %d" % (r, m)
    print("  recv_r[%d] = 0x%03x = %3d (%s, mod %d) - %s" % (i, r, r, n, m, status))

print("\nILA decoder output: best_x = 0x%04x = %d, min_dist = %d" % (ila_best_x, ila_best_x, ila_min_dist))

# Verify ILA best_x against recv_r
print("\nVerification of ILA best_x = %d:" % ila_best_x)
ila_dist = 0
for i, (m, n) in enumerate(zip(moduli, names)):
    calc = ila_best_x % m
    recv = recv_r[i]
    match = calc == recv
    if not match:
        ila_dist += 1
    status = "OK" if match else "MISMATCH! calc=%d, recv=%d" % (calc, recv)
    print("  %d %% %d = %d, recv_r[%d]=%d - %s" % (ila_best_x, m, calc, i, recv, status))
print("Actual distance for ILA best_x: %d" % ila_dist)

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

print("MATLAB MLD result: best_X = %d (0x%04x), min_dist = %d" % (best_X, best_X, min_dist))
print("\nMatch with ILA: %s" % (best_X == ila_best_x and min_dist == ila_min_dist))

if best_X is not None and best_X != ila_best_x:
    print("\nVerification of MATLAB best_X = %d:" % best_X)
    for i, (m, n) in enumerate(zip(moduli, names)):
        calc = best_X % m
        recv = recv_r[i]
        match = "OK" if calc == recv else "MISMATCH! calc=%d, recv=%d" % (calc, recv)
        print("  %d %% %d = %d, recv_r[%d]=%d - %s" % (best_X, m, calc, i, recv, match))
