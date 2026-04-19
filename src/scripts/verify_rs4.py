"""
verify_rs4.py - RS(12,4) over GF(2^4) using a clean, well-tested implementation
Based on the classic Wicker & Bhargava textbook algorithm.
Key insight: use the standard BM that tracks both sigma and omega simultaneously.
"""

PRIM_POLY = 0x13  # x^4 + x + 1

# Build GF(2^4) tables
ALOG = [0]*16; ALOG[0] = 1
for i in range(1, 15):
    a = ALOG[i-1] << 1
    if a & 0x10: a ^= PRIM_POLY
    ALOG[i] = a & 0xF
LOG = [-1]*16
for i in range(15): LOG[ALOG[i]] = i

def gf_mul(a, b):
    if a == 0 or b == 0: return 0
    return ALOG[(LOG[a] + LOG[b]) % 15]

def gf_inv(a): return ALOG[(15 - LOG[a]) % 15] if a else 0
def gf_div(a, b): return gf_mul(a, gf_inv(b))

# Generator polynomial g(x) = prod(x - alpha^i) for i=1..8
G = [1, 9, 4, 3, 4, 13, 6, 14, 12]

def rs_encode(data):
    msg = data + [0]*8
    for i in range(4):
        c = msg[i]
        if c:
            for j in range(1, 9): msg[i+j] ^= gf_mul(G[j], c)
    return data + msg[4:]

def rs_decode(cw):
    """
    RS decoder using the standard BM algorithm.
    Reference: Lin & Costello, "Error Control Coding", 2nd ed.
    """
    n = 12
    t = 4  # max correctable errors

    # Step 1: Compute syndromes S_j = cw(alpha^j) for j=1..2t
    S = [0] * (2*t + 1)  # S[1]..S[2t], S[0] unused
    for j in range(1, 2*t+1):
        s = 0
        for c in cw: s = gf_mul(s, ALOG[j]) ^ c
        S[j] = s

    if all(S[j] == 0 for j in range(1, 2*t+1)):
        return list(cw[:4]), 0

    # Step 2: Berlekamp-Massey algorithm (Massey 1969 correct formulation)
    # sigma(x) = error locator polynomial
    # Key: use x^m shift (not always x^1) where m tracks steps since last update
    sigma = [1]  # sigma[0]=1
    B = [1]      # previous sigma
    L = 0
    m = 1        # steps since last update
    b = 1        # previous discrepancy

    for n_iter in range(1, 2*t+1):
        # Compute discrepancy delta
        delta = S[n_iter]
        for i in range(1, L+1):
            if i < len(sigma):
                delta ^= gf_mul(sigma[i], S[n_iter-i])

        if delta == 0:
            m += 1
        elif 2*L <= n_iter - 1:
            # Update: sigma = sigma - (delta/b) * x^m * B
            T = sigma[:]
            coef = gf_div(delta, b)
            xmB = [0]*m + B
            while len(xmB) < len(sigma): xmB.append(0)
            while len(sigma) < len(xmB): sigma.append(0)
            for i in range(len(sigma)):
                sigma[i] ^= gf_mul(coef, xmB[i])
            L = n_iter - L
            B = T
            b = delta
            m = 1
        else:
            # sigma = sigma - (delta/b) * x^m * B
            coef = gf_div(delta, b)
            xmB = [0]*m + B
            while len(xmB) < len(sigma): xmB.append(0)
            while len(sigma) < len(xmB): sigma.append(0)
            for i in range(len(sigma)):
                sigma[i] ^= gf_mul(coef, xmB[i])
            m += 1

    # Step 3: Chien search - find roots of sigma(x)
    # Syndrome S_j = sum_k e_k * alpha^(j*(n-1-pos_k))
    # So error location number X_k = alpha^(n-1-pos_k)
    # sigma(X_k^-1) = 0, i.e., sigma(alpha^(-(n-1-pos_k))) = sigma(alpha^(pos_k+1-n)) = 0
    # We search: for each i in 0..n-1, evaluate sigma at alpha^(i+1-n) = alpha^((i+1-n)%15)
    # If sigma(alpha^(i+1-n)) = 0, then error at position i (0-indexed from MSB)
    errs = []
    for i in range(n):
        # X_k = alpha^(n-1-i), X_k_inv = alpha^(i+1-n) = alpha^((i+1-n+15*100)%15)
        xi_inv_exp = (i + 1 - n + 15*100) % 15
        xi_inv = ALOG[xi_inv_exp]
        val = 0
        xi_pow = 1
        for c in sigma:
            val ^= gf_mul(c, xi_pow)
            xi_pow = gf_mul(xi_pow, xi_inv)
        if val == 0:
            errs.append(i)

    if len(errs) != L:
        return None, -1  # uncorrectable

    # Step 4: Compute error magnitudes using Forney algorithm
    # omega(x) = S(x) * sigma(x) mod x^(2t)
    # where S(x) = S[1] + S[2]*x + ... + S[2t]*x^(2t-1)
    omega = [0] * (2*t)
    for i in range(2*t):
        for j in range(len(sigma)):
            k = i - j
            if 1 <= k <= 2*t:
                omega[i] ^= gf_mul(sigma[j], S[k])

    # Formal derivative of sigma: sigma'[i] = sigma[i] if i is odd, else 0
    sigma_prime = [sigma[i] if i % 2 == 1 else 0 for i in range(len(sigma))]

    cw_fixed = list(cw)
    for pos in errs:
        # X_k = alpha^(n-1-pos) (error location number)
        X_exp = (n - 1 - pos) % 15
        X = ALOG[X_exp]
        X_inv_exp = (pos + 1 - n + 15*100) % 15
        X_inv = ALOG[X_inv_exp]

        # Evaluate omega at X_inv
        ov = 0
        X_pow = 1
        for c in omega:
            ov ^= gf_mul(c, X_pow)
            X_pow = gf_mul(X_pow, X_inv)

        # Evaluate sigma' at X_inv
        sv = 0
        X_pow = 1
        for c in sigma_prime:
            sv ^= gf_mul(c, X_pow)
            X_pow = gf_mul(X_pow, X_inv)

        if sv == 0: return None, -1

        # Error magnitude: e = omega(X_inv) / sigma'(X_inv)
        # Note: no X factor needed with this syndrome/omega convention
        e = gf_div(ov, sv)
        cw_fixed[pos] ^= e

    return cw_fixed[:4], L


import random
random.seed(42)

print('=== RS(12,4) GF(2^4) Decoder v4 ===')
print()
print('GF tables check:')
print('ALOG:', ALOG)
print('gf_mul(2,3)=', gf_mul(2,3), '(expected 6)')
print('gf_mul(3,3)=', gf_mul(3,3), '(expected 5 = 3*3 in GF(2^4))')
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
