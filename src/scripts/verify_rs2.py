"""
verify_rs2.py - RS(12,4) over GF(2^4) with corrected BM decoder
"""

PRIM_POLY = 0x13

def gf_mul(a, b):
    p = 0
    for _ in range(4):
        if b & 1: p ^= a
        a <<= 1
        if a & 0x10: a ^= PRIM_POLY
        b >>= 1
    return p & 0xF

ALOG = [0]*16; ALOG[0] = 1
for i in range(1, 15): ALOG[i] = gf_mul(ALOG[i-1], 2)
LOG = [-1]*16
for i in range(15): LOG[ALOG[i]] = i

def gf_inv(a): return ALOG[(15-LOG[a])%15] if a else 0
def gf_div(a, b): return gf_mul(a, gf_inv(b))

G = [1, 9, 4, 3, 4, 13, 6, 14, 12]

def rs_encode(data):
    msg = data + [0]*8
    for i in range(4):
        c = msg[i]
        if c:
            for j in range(1, 9): msg[i+j] ^= gf_mul(G[j], c)
    return data + msg[4:]

def rs_decode(cw):
    n = 12
    t = 4  # max correctable errors

    # Step 1: Syndromes S[i] = cw(alpha^i) for i=1..2t
    S = [0] * (2*t + 1)
    for i in range(1, 2*t+1):
        s = 0
        for c in cw: s = gf_mul(s, ALOG[i]) ^ c
        S[i] = s

    if all(S[i] == 0 for i in range(1, 2*t+1)):
        return list(cw[:4]), 0

    # Step 2: Berlekamp-Massey to find error locator sigma
    # Standard BM: sigma[0]=1, sigma[i] are coefficients
    sigma = [1] + [0]*(2*t)
    prev  = [1] + [0]*(2*t)
    L = 0
    for r in range(1, 2*t+1):
        # Discrepancy
        delta = S[r]
        for i in range(1, L+1):
            delta ^= gf_mul(sigma[i], S[r-i])
        if delta == 0:
            prev = [0] + prev[:-1]
        elif 2*L < r:
            tmp = sigma[:]
            coef = delta
            for i in range(len(sigma)):
                sigma[i] ^= gf_mul(coef, prev[i])
            L = r - L
            prev = [gf_div(t_val, coef) for t_val in tmp]
            prev = [0] + prev[:-1]
        else:
            coef = delta
            for i in range(len(sigma)):
                sigma[i] ^= gf_mul(coef, prev[i])
            prev = [0] + prev[:-1]

    # Step 3: Chien search - find positions where sigma(alpha^-i) = 0
    errs = []
    for i in range(n):
        # Evaluate sigma at alpha^(-i) = alpha^((15-i)%15)
        val = 0
        for j in range(L+1):
            exp = (j * (15 - i)) % 15
            val ^= gf_mul(sigma[j], ALOG[exp])
        if val == 0:
            errs.append(i)

    if len(errs) != L:
        return None, -1  # uncorrectable

    # Step 4: Forney algorithm
    # Compute omega = S(x) * sigma(x) mod x^(2t)
    omega = [0] * (2*t)
    for i in range(2*t):
        for j in range(min(i+1, L+1)):
            if i-j >= 1 and i-j <= 2*t:
                omega[i] ^= gf_mul(sigma[j], S[i-j+1])

    # Formal derivative of sigma (odd-indexed terms, char=2)
    sigma_d = [0] * (L+1)
    for i in range(1, L+1, 2):
        sigma_d[i] = sigma[i]

    cw_fixed = list(cw)
    for pos in errs:
        if pos >= n: continue
        # xi_inv = alpha^(-pos)
        xi_inv_exp = (15 - pos) % 15
        # Evaluate omega at xi_inv
        ov = 0
        for j in range(2*t):
            exp = (j * xi_inv_exp) % 15
            ov ^= gf_mul(omega[j], ALOG[exp])
        # Evaluate sigma_d at xi_inv
        sv = 0
        for j in range(L+1):
            exp = (j * xi_inv_exp) % 15
            sv ^= gf_mul(sigma_d[j], ALOG[exp])
        if sv == 0:
            return None, -1
        e = gf_div(ov, sv)
        cw_fixed[pos] ^= e

    return cw_fixed[:4], L


import random
random.seed(42)

print('=== RS(12,4) GF(2^4) Decoder v2 Verification ===')
print()
print('No errors:')
for tv in [0, 1, 100, 12345, 65535, 32768]:
    d = [(tv>>12)&0xF, (tv>>8)&0xF, (tv>>4)&0xF, tv&0xF]
    cw = rs_encode(d)
    dec, nerr = rs_decode(cw)
    x = (dec[0]<<12)|(dec[1]<<8)|(dec[2]<<4)|dec[3]
    status = 'PASS' if x == tv else 'FAIL'
    print(f'  x={tv:5d}: decoded={x:5d}, {status}')

print()
print('Error correction (1-4 symbol errors, 200 trials each):')
for ne in [1, 2, 3, 4]:
    ok = 0
    for _ in range(200):
        tv = random.randint(0, 65535)
        d = [(tv>>12)&0xF, (tv>>8)&0xF, (tv>>4)&0xF, tv&0xF]
        cw = list(rs_encode(d))
        for p in random.sample(range(12), ne):
            cw[p] ^= random.randint(1, 15)
        dec, _ = rs_decode(cw)
        if dec and (dec[0]<<12)|(dec[1]<<8)|(dec[2]<<4)|dec[3] == tv:
            ok += 1
    print(f'  {ne} errors: {ok}/200 = {ok/2:.0f}%')

print()
print('Uncorrectable (5 symbol errors):')
fail = 0
for _ in range(200):
    tv = random.randint(0, 65535)
    d = [(tv>>12)&0xF, (tv>>8)&0xF, (tv>>4)&0xF, tv&0xF]
    cw = list(rs_encode(d))
    for p in random.sample(range(12), 5):
        cw[p] ^= random.randint(1, 15)
    dec, _ = rs_decode(cw)
    if dec is None or (dec[0]<<12)|(dec[1]<<8)|(dec[2]<<4)|dec[3] != tv:
        fail += 1
print(f'  5 errors: {fail}/200 failed (expected ~200)')
