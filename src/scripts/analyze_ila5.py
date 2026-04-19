"""
ILA Data 5 Analysis - After Bug #37 Stage 3 Split Fix
Compare with iladata4 to see if the fix helped
"""
import csv

rows = []
with open('src/scripts/iladata5.csv', 'r') as f:
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
    cand_r = [x % m for m in moduli]
    return sum(1 for i in range(6) if cand_r[i] != recv_r[i])

def full_mld_decode(recv_r):
    channels = [
        (257, 256, 1,  0, 1), (257,  61, 48, 0, 2), (257,  59, 45, 0, 3),
        (257,  55, 3,  0, 4), (257,  53, 33, 0, 5), (256,  61, 56, 1, 2),
        (256,  59, 3,  1, 3), (256,  55, 26, 1, 4), (256,  53, 47, 1, 5),
        ( 61,  59, 30, 2, 3), ( 61,  55, 46, 2, 4), ( 61,  53, 20, 2, 5),
        ( 59,  55, 14, 3, 4), ( 59,  53, 9,  3, 5), ( 55,  53, 27, 4, 5),
    ]
    best_x = 0
    best_dist = 7
    for m1, m2, inv, idx1, idx2 in channels:
        ri = recv_r[idx1]
        rj = recv_r[idx2]
        diff = (rj + m2 - ri) % m2
        coeff = (diff * inv) % m2
        x_k0 = ri + m1 * coeff
        for k in range(5):
            x_k = x_k0 + k * m1 * m2
            if x_k > 65535:
                break
            d = hamming_dist(x_k, recv_r)
            if d < best_dist:
                best_dist = d
                best_x = x_k
    return best_x, best_dist

print('=== iladata5 Basic Statistics ===')
print(f'Total DONE states: {len(done_states)}')

pass_a = sum(1 for r in done_states if r['u_fsm/u_engine/comp_result_a'] == '1')
pass_b = sum(1 for r in done_states if r['u_fsm/u_engine/comp_result_b'] == '1')
both_pass = sum(1 for r in done_states if r['u_fsm/u_engine/comp_result_a'] == '1' and r['u_fsm/u_engine/comp_result_b'] == '1')
both_fail = sum(1 for r in done_states if r['u_fsm/u_engine/comp_result_a'] == '0' and r['u_fsm/u_engine/comp_result_b'] == '0')

print(f'Pass A: {pass_a}/{len(done_states)} = {pass_a/len(done_states)*100:.1f}%')
print(f'Pass B: {pass_b}/{len(done_states)} = {pass_b/len(done_states)*100:.1f}%')
print(f'Both Pass: {both_pass}/{len(done_states)} = {both_pass/len(done_states)*100:.1f}%')
print(f'Both Fail: {both_fail}/{len(done_states)} = {both_fail/len(done_states)*100:.1f}%')

injected = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '1')
not_injected = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '0')
print(f'\nInjected: {injected}, Not injected: {not_injected}')

no_inj_pass = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '0'
                  and r['u_fsm/u_engine/comp_result_a'] == '1'
                  and r['u_fsm/u_engine/comp_result_b'] == '1')
no_inj_fail = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '0'
                  and (r['u_fsm/u_engine/comp_result_a'] == '0' or r['u_fsm/u_engine/comp_result_b'] == '0'))
print(f'No injection - Pass: {no_inj_pass}, Fail: {no_inj_fail}')

inj_pass = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '1'
               and r['u_fsm/u_engine/comp_result_a'] == '1'
               and r['u_fsm/u_engine/comp_result_b'] == '1')
inj_fail = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '1'
               and (r['u_fsm/u_engine/comp_result_a'] == '0' or r['u_fsm/u_engine/comp_result_b'] == '0'))
print(f'With injection - Pass: {inj_pass}, Fail: {inj_fail}')

# Check comp_latency_a
from collections import Counter
lats = Counter(r['u_fsm/u_engine/comp_latency_a[7:0]'] for r in done_states)
print(f'\ncomp_latency_a distribution: {dict(lats)}')
print('(0x18=24 means Stage 3 split is working, +1 cycle vs iladata4 0x17=23)')

print()
print('=== CRITICAL: Check enc_out vs inj_out for non-injected trials ===')
no_inj_fail_cases = [r for r in done_states
                     if r['u_fsm/u_engine/inject_en_latch'] == '0'
                     and (r['u_fsm/u_engine/comp_result_a'] == '0' or r['u_fsm/u_engine/comp_result_b'] == '0')]
print(f'Non-injected fail cases: {len(no_inj_fail_cases)}')

enc_eq_inj_count = sum(1 for r in no_inj_fail_cases
                       if r['u_fsm/u_engine/enc_out_a_latch[40:0]'] == r['u_fsm/u_engine/inj_out_a_latch[40:0]'])
print(f'enc==inj (no injection confirmed): {enc_eq_inj_count}/{len(no_inj_fail_cases)}')

print()
print('=== VERIFY ENCODING for non-injected fails ===')
enc_errors = 0
for r in no_inj_fail_cases[:10]:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    actual = decode_enc_out(enc_hex)
    expected = [sym_a % m for m in moduli]
    if actual != expected:
        enc_errors += 1
        print(f'  ENC ERROR: sym_a={sym_a}, expected={expected}, actual={actual}')
print(f'Encoding errors: {enc_errors}/{min(10, len(no_inj_fail_cases))}')

print()
print('=== MLD SIMULATION for non-injected fails ===')
correct_mld = 0
wrong_mld = 0
for r in no_inj_fail_cases[:20]:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    inj_hex = r['u_fsm/u_engine/inj_out_a_latch[40:0]']
    recv_r = decode_enc_out(inj_hex)
    expected_x, expected_dist = full_mld_decode(recv_r)
    correct_dist = hamming_dist(sym_a, recv_r)
    
    if dec_out == expected_x:
        correct_mld += 1
    else:
        wrong_mld += 1
    
    print(f'  sym_a={sym_a}(0x{sym_a:04x}), dec_out={dec_out}(0x{dec_out:04x}), '
          f'expected_mld={expected_x}(dist={expected_dist}), correct_dist={correct_dist}, '
          f'match={dec_out==expected_x}')

print(f'\nMLD correct: {correct_mld}, wrong: {wrong_mld}')

print()
print('=== COMPARE WITH ILADATA4: Same PRBS sequence? ===')
print('First few sym_a values in iladata5:')
for r in done_states[:10]:
    print(f'  sym_a={r["u_fsm/u_engine/sym_a_latch[15:0]"]}, dec_out={r["u_fsm/u_engine/dec_out_a[15:0]"]}, '
          f'comp_a={r["u_fsm/u_engine/comp_result_a"]}, inj={r["u_fsm/u_engine/inject_en_latch"]}')

print()
print('=== CRITICAL: Check if dec_out is SAME as iladata4 for same sym_a ===')
print('iladata4 Trial 1: sym_a=ef76, dec_out=0376')
print('iladata5 Trial 1: sym_a=ef76, dec_out=?')
trial1 = [r for r in done_states if r['u_fsm/u_engine/sym_a_latch[15:0]'] == 'ef76']
if trial1:
    print(f'  dec_out={trial1[0]["u_fsm/u_engine/dec_out_a[15:0]"]}')
    print(f'  inject_en={trial1[0]["u_fsm/u_engine/inject_en_latch"]}')
    print(f'  enc_out={trial1[0]["u_fsm/u_engine/enc_out_a_latch[40:0]"]}')
    print(f'  inj_out={trial1[0]["u_fsm/u_engine/inj_out_a_latch[40:0]"]}')

print()
print('=== HYPOTHESIS: The decoder is outputting the PREVIOUS trial result ===')
print('Check if dec_out in trial N == sym_a of trial N-1')
prev_sym_a = None
stale_count = 0
total_count = 0
for r in done_states:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    if prev_sym_a is not None:
        total_count += 1
        if dec_out == prev_sym_a:
            stale_count += 1
    prev_sym_a = sym_a
print(f'Stale (dec_out == prev sym_a): {stale_count}/{total_count}')

print()
print('=== LOOK AT FIRST TRIAL IN DETAIL ===')
# Find first complete trial
trial_samples = []
in_trial = False
for r in data:
    state = r['u_fsm/u_engine/state[2:0]']
    if state == 'iSTATE0':
        in_trial = True
        trial_samples = [r]
    elif in_trial:
        trial_samples.append(r)
        if state == 'iSTATE6':
            print('--- First Trial ---')
            for s in trial_samples:
                st = s['u_fsm/u_engine/state[2:0]']
                sym_a = s['u_fsm/u_engine/sym_a_latch[15:0]']
                dec_out = s['u_fsm/u_engine/dec_out_a[15:0]']
                dec_valid = s['u_fsm/u_engine/dec_valid_a']
                comp_a = s['u_fsm/u_engine/comp_result_a']
                dec_start = s['u_fsm/u_engine/dec_start']
                inj = s['u_fsm/u_engine/inject_en_latch']
                enc_out = s['u_fsm/u_engine/enc_out_a_latch[40:0]']
                inj_out = s['u_fsm/u_engine/inj_out_a_latch[40:0]']
                lat = s['u_fsm/u_engine/comp_latency_a[7:0]']
                print(f'  Sample {s["Sample in Buffer"]:4}: {st:8}, sym_a={sym_a}, dec_out={dec_out}, '
                      f'dec_valid={dec_valid}, dec_start={dec_start}, comp_a={comp_a}, '
                      f'inj={inj}, lat={lat}')
                if dec_valid == '1':
                    print(f'    *** dec_valid=1: dec_out={dec_out}, enc_out={enc_out}, inj_out={inj_out}')
            break
