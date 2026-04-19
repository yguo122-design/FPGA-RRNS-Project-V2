"""
verify_rs3.py - RS(12,4) over GF(2^4) using Euclidean algorithm for key equation
This avoids the Forney formula complexity by using the Euclidean approach.
"""

PRIM_POLY = 0x13  # x^4 + x + 1

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

# Generator polynomial g(x) = prod(x - alpha^i) for i=1..8
G = [1, 9, 4, 3, 4, 13, 6, 14, 12]

def rs_encode(data):
    """Systematic RS encoding: codeword = [data | parity]"""
    msg = data + [0]*8
    for i in range(4):
        c = msg[i]
        if c:
            for j in range(1, 9): msg[i+j] ^= gf_mul(G[j], c)
    return data + msg[4:]

def poly_eval(poly, x):
    """Evaluate polynomial at x using Horner's method"""
    result = 0
    for c in poly: result = gf_mul(result, x) ^ c
    return result

def poly_mul(a, b):
    result = [0] * (len(a) + len(b) - 1)
    for i, ai in enumerate(a):
        for j, bj in enumerate(b):
            result[i+j] ^= gf_mul(ai, bj)
    return result

def poly_mod(a, b):
    """Polynomial division: return a mod b"""
    a = list(a)
    while len(a) >= len(b):
        if a[0] == 0:
            a = a[1:]
            continue
        coef = gf_div(a[0], b[0])
        for i in range(len(b)):
            a[i] ^= gf_mul(coef, b[i])
        a = a[1:]
    return a

def rs_decode(cw):
    """RS decoder using Euclidean algorithm (more robust than BM+Forney)"""
    n = 12
    t = 4

    # Step 1: Compute syndromes
    S = []
    for i in range(1, 2*t+1):
        S.append(poly_eval(cw, ALOG[i]))

    if all(s == 0 for s in S):
        return list(cw[:4]), 0

    # Step 2: Build syndrome polynomial S(x) = S[0] + S[1]*x + ... + S[2t-1]*x^(2t-1)
    # (coefficients in reverse order for polynomial operations)
    S_poly = S[::-1]  # S_poly[0] = S[2t-1], ..., S_poly[2t-1] = S[0]
    # Actually use S_poly = [S[0], S[1], ..., S[2t-1]] with x^0 = S[0]
    # Standard: S(x) = sum S_i * x^(i-1) for i=1..2t
    # S_poly[i] = S[i] (0-indexed: S_poly[0]=S[0]=S_1, ..., S_poly[7]=S[7]=S_8)

    # Step 3: Berlekamp-Massey (standard form)
    # sigma(x) = error locator, omega(x) = error evaluator
    # Use the iterative BM that directly gives sigma and omega

    # Initialize
    C = [1]  # sigma
    B = [1]  # previous sigma
    L = 0
    x = 1   # shift register

    for i in range(2*t):
        # Discrepancy
        d = S[i]
        for j in range(1, L+1):
            if j < len(C): d ^= gf_mul(C[j], S[i-j])
        if d == 0:
            x += 1
        elif 2*L <= i:
            T = C[:]
            # C = C - d * x^x * B
            xB = [0]*x + B
            while len(xB) < len(C): xB.append(0)
            while len(C) < len(xB): C.append(0)
            for j in range(len(C)): C[j] ^= gf_mul(d, xB[j])
            L = i + 1 - L
            B = T
            x = 1
        else:
            xB = [0]*x + B
            while len(xB) < len(C): xB.append(0)
            while len(C) < len(xB): C.append(0)
            for j in range(len(C)): C[j] ^= gf_mul(d, xB[j])
            x += 1

    sigma = C  # error locator polynomial

    # Step 4: Chien search
    errs = []
    for i in range(n):
        # Evaluate sigma at alpha^(-i)
        val = poly_eval(sigma, ALOG[(15-i)%15])
        if val == 0:
            errs.append(i)

    if len(errs) != L:
        return None, -1

    # Step 5: Compute omega = S(x) * sigma(x) mod x^(2t)
    # S_poly as polynomial: S_poly[0]*x^0 + S_poly[1]*x^1 + ...
    # But we need S(x) = S[0] + S[1]*x + ... + S[2t-1]*x^(2t-1)
    # sigma(x) = sigma[0] + sigma[1]*x + ...
    # omega = S * sigma mod x^(2t)
    S_coeffs = S  # S[0]=S_1, ..., S[7]=S_8
    sig_coeffs = sigma

    # Multiply (treating index as power of x)
    omega = [0] * (2*t)
    for i in range(len(S_coeffs)):
        for j in range(len(sig_coeffs)):
            if i+j < 2*t:
                omega[i+j] ^= gf_mul(S_coeffs[i], sig_coeffs[j])

    # Step 6: Forney formula: e_k = -X_k * omega(X_k^-1) / sigma'(X_k^-1)
    # where X_k = alpha^(pos_k), sigma' is formal derivative
    # In GF(2^m), -1 = 1

    # Formal derivative of sigma (odd terms only in char 2)
    sigma_d = [0] * len(sigma)
    for i in range(1, len(sigma), 2):
        sigma_d[i] = sigma[i]

    cw_fixed = list(cw)
    for pos in errs:
        X = ALOG[pos]          # alpha^pos
        X_inv = gf_inv(X)      # alpha^(-pos)

        # Evaluate omega at X_inv
        ov = 0
        X_pow = 1
        for c in omega:
            ov ^= gf_mul(c, X_pow)
            X_pow = gf_mul(X_pow, X_inv)

        # Evaluate sigma_d at X_inv
        sv = 0
        X_pow = 1
        for c in sigma_d:
            sv ^= gf_mul(c, X_pow)
            X_pow = gf_mul(X_pow, X_inv)

        if sv == 0: return None, -1

        # e = X * omega(X_inv) / sigma_d(X_inv)
        e = gf_mul(X, gf_div(ov, sv))
        cw_fixed[pos] ^= e

    return cw_fixed[:4], L


import random
random.seed(42)

print('=== RS(12,4) GF(2^4) Decoder v3 (BM + Forney) ===')
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
print('Error correction (1-4 symbol errors, 500 trials each):')
for ne in [1, 2, 3, 4]:
    ok = 0
    for _ in range(500):
        tv = random.randint(0, 65535)
        d = [(tv>>12)&0xF, (tv>>8)&0xF, (tv>>4)&0xF, tv&0xF]
        cw = list(rs_encode(d))
        for p in random.sample(range(12), ne):
            cw[p] ^= random.randint(1, 15)
        dec, _ = rs_decode(cw)
        if dec and (dec[0]<<12)|(dec[1]<<8)|(dec[2]<<4)|dec[3] == tv:
            ok += 1
    print(f'  {ne} errors: {ok}/500 = {ok/5:.0f}%')

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
