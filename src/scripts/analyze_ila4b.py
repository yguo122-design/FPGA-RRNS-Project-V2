"""
ILA Data 4 - Deep Analysis of Decoder Failure Pattern
Key finding: CRT ch0 gives CORRECT x, but decoder outputs WRONG value
This means the MLD is selecting the WRONG channel's output
"""
import csv

rows = []
with open('src/scripts/iladata4.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

data = [r for r in rows if r['Sample in Buffer'] not in ['Radix - UNSIGNED', 'UNSIGNED']]
done_states = [r for r in data if r['u_fsm/u_engine/state[2:0]'] == 'iSTATE5']

moduli = [257, 256, 61, 59, 55, 53]

def decode_enc_out(enc_hex):
    val = int(enc_hex, 16)
    r257 = (val >> 32) & 0x1FF
    r256 = (val >> 24) & 0xFF
    r61  = (val >> 18) & 0x3F
    r59  = (val >> 12) & 0x3F
    r55  = (val >> 6)  & 0x3F
    r53  = (val >> 0)  & 0x3F
    return [r257, r256, r61, r59, r55, r53]

def hamming_dist(x, recv_r):
    """Compute Hamming distance between x's residues and received residues"""
    cand_r = [x % m for m in moduli]
    return sum(1 for i in range(6) if cand_r[i] != recv_r[i])

def crt_channel(m1, m2, inv, ri, rj, recv_r):
    """Compute CRT candidate for a channel pair and find best k"""
    PERIOD = m1 * m2
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_k0 = ri + m1 * coeff
    
    best_x = x_k0
    best_dist = hamming_dist(x_k0, recv_r)
    
    # Try k=1..4
    for k in range(1, 5):
        x_k = x_k0 + k * PERIOD
        if x_k > 65535:
            break
        d = hamming_dist(x_k, recv_r)
        if d < best_dist:
            best_dist = d
            best_x = x_k
    
    return best_x, best_dist

# Channel definitions: (M1, M2, INV, idx1, idx2)
channels = [
    (257, 256, 1,  0, 1),  # ch0
    (257,  61, 48, 0, 2),  # ch1
    (257,  59, 45, 0, 3),  # ch2
    (257,  55, 3,  0, 4),  # ch3
    (257,  53, 33, 0, 5),  # ch4
    (256,  61, 56, 1, 2),  # ch5
    (256,  59, 3,  1, 3),  # ch6
    (256,  55, 26, 1, 4),  # ch7
    (256,  53, 47, 1, 5),  # ch8
    ( 61,  59, 30, 2, 3),  # ch9
    ( 61,  55, 46, 2, 4),  # ch10
    ( 61,  53, 20, 2, 5),  # ch11
    ( 59,  55, 14, 3, 4),  # ch12
    ( 59,  53, 9,  3, 5),  # ch13
    ( 55,  53, 27, 4, 5),  # ch14
]

print('=== FULL MLD SIMULATION for non-injected failing cases ===')
print()

no_inj_fail_cases = [r for r in done_states 
                     if r['u_fsm/u_engine/inject_en_latch'] == '0' 
                     and (r['u_fsm/u_engine/comp_result_a'] == '0' or r['u_fsm/u_engine/comp_result_b'] == '0')]

wrong_mld_count = 0
correct_mld_count = 0

for r in no_inj_fail_cases[:20]:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    recv_r = decode_enc_out(enc_hex)
    
    print(f'sym_a={sym_a}(0x{sym_a:04x}), dec_out={dec_out}(0x{dec_out:04x}), recv_r={recv_r}')
    
    # Simulate all 15 channels
    ch_results = []
    for i, (m1, m2, inv, idx1, idx2) in enumerate(channels):
        ri = recv_r[idx1]
        rj = recv_r[idx2]
        best_x, best_dist = crt_channel(m1, m2, inv, ri, rj, recv_r)
        ch_results.append((i, best_x, best_dist))
    
    # Find global minimum (MLD)
    min_dist = min(d for _, _, d in ch_results)
    best_channels = [(i, x, d) for i, x, d in ch_results if d == min_dist]
    
    # What does the correct answer look like?
    correct_dist = hamming_dist(sym_a, recv_r)
    
    print(f'  Correct x={sym_a}, dist={correct_dist}')
    print(f'  MLD selects: min_dist={min_dist}, candidates={[(i, x) for i,x,d in best_channels]}')
    
    # Show all channel results
    print(f'  All channels:')
    for i, x, d in ch_results:
        marker = ' <-- CORRECT' if x == sym_a else ''
        marker2 = ' <-- MLD WINNER' if d == min_dist else ''
        print(f'    ch{i:2d}: x={x:5d}(0x{x:04x}), dist={d}{marker}{marker2}')
    
    if dec_out == sym_a:
        correct_mld_count += 1
        print(f'  RESULT: CORRECT (but comp says fail?)')
    else:
        wrong_mld_count += 1
        # Find which channel gives dec_out
        dec_channels = [(i, x, d) for i, x, d in ch_results if x == dec_out]
        print(f'  RESULT: WRONG - decoder output {dec_out}, channels giving this: {dec_channels}')
    print()

print(f'Summary: correct_mld={correct_mld_count}, wrong_mld={wrong_mld_count}')

print()
print('=== PATTERN ANALYSIS: What is dec_out relative to sym_a? ===')
print()
for r in no_inj_fail_cases[:30]:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    recv_r = decode_enc_out(enc_hex)
    
    # Check: is dec_out == sym_a % (257*256) ?
    # Or is dec_out the CRT result from some specific channel?
    
    # Check if dec_out is the result of ch0 with k=0 (no multi-candidate)
    r257, r256 = recv_r[0], recv_r[1]
    diff = (r256 + 256 - r257) % 256
    coeff = (diff * 1) % 256
    x_ch0_k0 = r257 + 257 * coeff
    
    # Check if dec_out matches any channel's k=0 result
    for i, (m1, m2, inv, idx1, idx2) in enumerate(channels):
        ri = recv_r[idx1]
        rj = recv_r[idx2]
        diff_ch = (rj + m2 - ri) % m2
        coeff_ch = (diff_ch * inv) % m2
        x_k0 = ri + m1 * coeff_ch
        if x_k0 == dec_out:
            dist_k0 = hamming_dist(x_k0, recv_r)
            dist_correct = hamming_dist(sym_a, recv_r)
            print(f'sym_a={sym_a:5d}(0x{sym_a:04x}), dec_out={dec_out:5d}(0x{dec_out:04x}): '
                  f'matches ch{i} k=0, dist_k0={dist_k0}, dist_correct={dist_correct}')
            break
    else:
        print(f'sym_a={sym_a:5d}(0x{sym_a:04x}), dec_out={dec_out:5d}(0x{dec_out:04x}): '
              f'no channel k=0 match')

print()
print('=== CRITICAL CHECK: Is dec_out always the k=0 result of some channel? ===')
print('If yes, the multi-candidate (k=1..4) logic in Bug #35 fix is NOT working in hardware')
print()

k0_match_count = 0
no_match_count = 0
for r in no_inj_fail_cases:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    recv_r = decode_enc_out(enc_hex)
    
    found_k0 = False
    for i, (m1, m2, inv, idx1, idx2) in enumerate(channels):
        ri = recv_r[idx1]
        rj = recv_r[idx2]
        diff_ch = (rj + m2 - ri) % m2
        coeff_ch = (diff_ch * inv) % m2
        x_k0 = ri + m1 * coeff_ch
        if x_k0 == dec_out:
            found_k0 = True
            break
    
    if found_k0:
        k0_match_count += 1
    else:
        no_match_count += 1

print(f'dec_out matches some channel k=0: {k0_match_count}/{len(no_inj_fail_cases)}')
print(f'dec_out does NOT match any k=0:   {no_match_count}/{len(no_inj_fail_cases)}')

print()
print('=== HYPOTHESIS: Bug #35 multi-candidate fix not synthesized correctly ===')
print('If dec_out always = k=0 result, then PERIOD computation or k>0 candidates are broken')
print()

# Check the PERIOD values for each channel
print('Channel PERIOD values (M1 * M2):')
for i, (m1, m2, inv, idx1, idx2) in enumerate(channels):
    period = m1 * m2
    print(f'  ch{i:2d}: M1={m1:3d}, M2={m2:3d}, PERIOD={period:6d}')

print()
print('=== CHECK: For sym_a=61302, what k is needed for each channel? ===')
sym_a_test = 61302
recv_r_test = [sym_a_test % m for m in moduli]
print(f'sym_a={sym_a_test}, recv_r={recv_r_test}')
for i, (m1, m2, inv, idx1, idx2) in enumerate(channels):
    ri = recv_r_test[idx1]
    rj = recv_r_test[idx2]
    diff_ch = (rj + m2 - ri) % m2
    coeff_ch = (diff_ch * inv) % m2
    x_k0 = ri + m1 * coeff_ch
    period = m1 * m2
    if period > 0:
        k_needed = (sym_a_test - x_k0) // period if sym_a_test >= x_k0 else -1
        x_check = x_k0 + k_needed * period if k_needed >= 0 else -1
    else:
        k_needed = 0
        x_check = x_k0
    dist_k0 = hamming_dist(x_k0, recv_r_test)
    dist_correct = hamming_dist(sym_a_test, recv_r_test)
    print(f'  ch{i:2d}: x_k0={x_k0:5d}, k_needed={k_needed}, period={period:6d}, '
          f'dist_k0={dist_k0}, dist_correct={dist_correct}')
