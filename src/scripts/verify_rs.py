"""
verify_rs.py - Verify RS(12,4) over GF(2^4) encoder and decoder
Primitive polynomial: x^4 + x + 1 = 0x13
Generator polynomial roots: alpha^1 to alpha^8 (t=4 error correction)
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

def gf_inv(a): return ALOG[(15 - LOG[a]) % 15] if a else 0
def gf_div(a, b): return gf_mul(a, gf_inv(b))
def gf_pow(a, n): return ALOG[(LOG[a] * n) % 15] if a else 0

G = [1, 9, 4, 3, 4, 13, 6, 14, 12]  # generator polynomial coefficients

def rs_encode(data):
    msg = data + [0]*8
    for i in range(4):
        c = msg[i]
        if c:
            for j in range(1, 9): msg[i+j] ^= gf_mul(G[j], c)
    return data + msg[4:]

def rs_decode(cw):
    # Step 1: Compute syndromes S1..S8
    S = [0]*9
    for i in range(1, 9):
        s = 0
        for c in cw: s = gf_mul(s, ALOG[i]) ^ c
        S[i] = s
    if all(s == 0 for s in S[1:]):
        return cw[:4], 0  # no errors

    # Step 2: Berlekamp-Massey
    C = [1] + [0]*8
    B = [1] + [0]*8
    L, m, b = 0, 1, 1
    for n in range(1, 9):
        d = S[n]
        for i in range(1, L+1): d ^= gf_mul(C[i], S[n-i])
        if d == 0:
            m += 1
        elif 2*L <= n-1:
            T = C[:]
            coef = gf_div(d, b)
            for i in range(m, 9): C[i] ^= gf_mul(coef, B[i-m])
            L, B, b, m = n-L, T, d, 1
        else:
            coef = gf_div(d, b)
            for i in range(m, 9): C[i] ^= gf_mul(coef, B[i-m])
            m += 1

    # Step 3: Chien search for error locations
    # Evaluate C(alpha^-i) for i=0..14. Root at i means error at position i from MSB.
    # C(x) = 1 + c1*x + c2*x^2 + ...
    # C(alpha^-i) = 1 + c1*alpha^(-i) + c2*alpha^(-2i) + ...
    err_locs = []
    for i in range(15):
        val = 0
        for j in range(L+1):
            # alpha^(-i*j) = ALOG[(15 - i*j%15) % 15]
            exp = (15 - (i * j) % 15) % 15
            val ^= gf_mul(C[j], ALOG[exp])
        if val == 0:
            err_locs.append(i)  # error at position i in codeword

    if len(err_locs) != L:
        return None, -1  # uncorrectable

    # Step 4: Forney algorithm for error magnitudes
    cw_fixed = list(cw)
    # Compute error evaluator polynomial omega = S(x)*C(x) mod x^(2t)
    omega = [0]*9
    for i in range(9):
        for j in range(i+1):
            s_val = S[j+1] if j < 8 else 0
            omega[i] ^= gf_mul(s_val, C[i-j])
    # Formal derivative of C (odd-indexed terms only, since char=2)
    cprime = [0]*9
    for i in range(1, L+1, 2): cprime[i-1] = C[i]  # odd terms

    for pos in err_locs:
        if pos >= 12: continue  # position outside codeword
        # xi = alpha^(-pos) = alpha^(15-pos) for pos>0, alpha^0=1 for pos=0
        xi_inv_exp = (15 - pos) % 15
        xi_inv = ALOG[xi_inv_exp]
        xi = gf_inv(xi_inv)
        # Evaluate omega at xi_inv
        omega_val = 0
        xi_pow = 1
        for i in range(9):
            omega_val ^= gf_mul(omega[i], xi_pow)
            xi_pow = gf_mul(xi_pow, xi_inv)
        # Evaluate cprime at xi_inv
        cprime_val = 0
        xi_pow = 1
        for i in range(9):
            cprime_val ^= gf_mul(cprime[i], xi_pow)
            xi_pow = gf_mul(xi_pow, xi_inv)
        if cprime_val == 0: return None, -1
        # Error magnitude: e = -xi * omega(xi_inv) / cprime(xi_inv)
        # In GF(2^m), -1 = 1, so e = xi * omega / cprime
        e = gf_mul(xi, gf_div(omega_val, cprime_val))
        cw_fixed[pos] ^= e

    return cw_fixed[:4], L

import random
random.seed(42)

print('=== RS(12,4) GF(2^4) Verification ===')
print()
print('GF(2^4) tables:')
print('ALOG:', ALOG)
print('LOG:', LOG)
print()
print('Generator polynomial g:', G)
print()

print('=== Encode/Decode Test (no errors) ===')
for tv in [0, 1, 100, 12345, 65535, 32768]:
    d = [(tv>>12)&0xF, (tv>>8)&0xF, (tv>>4)&0xF, tv&0xF]
    cw = rs_encode(d)
    dec, nerr = rs_decode(cw)
    x = (dec[0]<<12)|(dec[1]<<8)|(dec[2]<<4)|dec[3]
    status = 'PASS' if x == tv else 'FAIL'
    print(f'  x={tv:5d}: decoded={x:5d}, errors={nerr}, {status}')

print()
print('=== Error Correction Test (1-4 symbol errors) ===')
for nerr_inject in [1, 2, 3, 4]:
    pass_cnt = 0
    for _ in range(100):
        tv = random.randint(0, 65535)
        d = [(tv>>12)&0xF, (tv>>8)&0xF, (tv>>4)&0xF, tv&0xF]
        cw = list(rs_encode(d))
        for pos in random.sample(range(12), nerr_inject):
            cw[pos] ^= random.randint(1, 15)
        dec, nerr = rs_decode(cw)
        if dec and (dec[0]<<12)|(dec[1]<<8)|(dec[2]<<4)|dec[3] == tv:
            pass_cnt += 1
    print(f'  {nerr_inject} symbol errors: {pass_cnt}/100 = {pass_cnt}%')

print()
print('=== Uncorrectable Test (5 symbol errors) ===')
fail_cnt = 0
for _ in range(100):
    tv = random.randint(0, 65535)
    d = [(tv>>12)&0xF, (tv>>8)&0xF, (tv>>4)&0xF, tv&0xF]
    cw = list(rs_encode(d))
    for pos in random.sample(range(12), 5):
        cw[pos] ^= random.randint(1, 15)
    dec, nerr = rs_decode(cw)
    if dec is None or (dec[0]<<12)|(dec[1]<<8)|(dec[2]<<4)|dec[3] != tv:
        fail_cnt += 1
print(f'  5 symbol errors: {fail_cnt}/100 failed (expected ~100)')
print()
print('=== Verification Complete ===')
