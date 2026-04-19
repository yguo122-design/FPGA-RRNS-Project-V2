"""
ILA Data 4 - Final Root Cause Analysis
Key hypothesis: The hardware decoder is outputting the PREVIOUS trial's result
(stale data from the previous dec_valid cycle)
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
    cand_r = [x % m for m in moduli]
    return sum(1 for i in range(6) if cand_r[i] != recv_r[i])

def full_mld_decode(recv_r):
    """Full MLD decode: simulate all 15 channels with k=0..4"""
    channels = [
        (257, 256, 1,  0, 1),
        (257,  61, 48, 0, 2),
        (257,  59, 45, 0, 3),
        (257,  55, 3,  0, 4),
        (257,  53, 33, 0, 5),
        (256,  61, 56, 1, 2),
        (256,  59, 3,  1, 3),
        (256,  55, 26, 1, 4),
        (256,  53, 47, 1, 5),
        ( 61,  59, 30, 2, 3),
        ( 61,  55, 46, 2, 4),
        ( 61,  53, 20, 2, 5),
        ( 59,  55, 14, 3, 4),
        ( 59,  53, 9,  3, 5),
        ( 55,  53, 27, 4, 5),
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

print('=== HYPOTHESIS: Hardware outputs PREVIOUS trial result (stale dec_out) ===')
print()
print('If dec_out_a in trial N = sym_a of trial N-1, then result_comparator')
print('is comparing current sym_a against PREVIOUS trial\'s dec_out.')
print()

# Check if dec_out_a in trial N matches sym_a of trial N-1
print('Trial N | sym_a(N) | dec_out(N) | sym_a(N-1) | dec_out==prev_sym?')
prev_sym_a = None
stale_count = 0
total_count = 0
for r in done_states:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    
    if prev_sym_a is not None:
        total_count += 1
        is_stale = (dec_out == prev_sym_a)
        if is_stale:
            stale_count += 1
        if total_count <= 20:
            print(f'{r["Sample in Buffer"]:7} | {sym_a:8d} | {dec_out:10d} | {prev_sym_a:10d} | {is_stale}')
    
    prev_sym_a = sym_a

print(f'...')
print(f'Stale (dec_out == prev sym_a): {stale_count}/{total_count} = {stale_count/total_count*100:.1f}%')

print()
print('=== ALTERNATIVE HYPOTHESIS: dec_out is from CURRENT trial but wrong channel ===')
print()

# Check if dec_out matches the correct MLD result
correct_mld_count = 0
wrong_mld_count = 0
for r in done_states:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    recv_r = decode_enc_out(enc_hex)
    
    expected_x, expected_dist = full_mld_decode(recv_r)
    if dec_out == expected_x:
        correct_mld_count += 1
    else:
        wrong_mld_count += 1

print(f'dec_out matches correct MLD result: {correct_mld_count}/{len(done_states)}')
print(f'dec_out does NOT match correct MLD: {wrong_mld_count}/{len(done_states)}')

print()
print('=== CRITICAL: Check comp_latency_a value ===')
print('comp_latency_a = 0x17 = 23 cycles in ALL samples')
print('This is the latency from comp_start to dec_valid')
print()

# Check comp_latency_a values
latencies = set(r['u_fsm/u_engine/comp_latency_a[7:0]'] for r in done_states)
print(f'Unique comp_latency_a values in DONE states: {latencies}')

print()
print('=== CRITICAL: Verify result_comparator timing ===')
print()
print('result_comparator.v: comp_start triggers lat_counting=1')
print('When dec_valid=1: test_result = (data_orig == data_recov)')
print()
print('KEY QUESTION: Is dec_valid_a arriving BEFORE or AFTER comp_start?')
print('If dec_valid arrives BEFORE comp_start, the comparator misses it!')
print()

# Look at the sequence of signals around each trial
# Find ENC_WAIT states (iSTATE1) where comp_start is issued
enc_wait_states = [r for r in data if r['u_fsm/u_engine/state[2:0]'] == 'iSTATE1']
dec_wait_states = [r for r in data if r['u_fsm/u_engine/state[2:0]'] == 'iSTATE3']

print(f'ENC_WAIT (iSTATE1) samples: {len(enc_wait_states)}')
print(f'DEC_WAIT (iSTATE3) samples: {len(dec_wait_states)}')

print()
print('=== LOOK AT FULL TRIAL SEQUENCE for first few trials ===')
print()

# Get all samples for first 3 trials
trial_samples = []
in_trial = False
trial_count = 0
for r in data:
    state = r['u_fsm/u_engine/state[2:0]']
    if state == 'iSTATE' and not in_trial:
        # Start of idle before a trial
        pass
    elif state == 'iSTATE0':  # CONFIG
        in_trial = True
        trial_samples = [r]
    elif in_trial:
        trial_samples.append(r)
        if state == 'iSTATE6':  # DONE/UPLOAD
            trial_count += 1
            if trial_count <= 3:
                print(f'--- Trial {trial_count} ---')
                for s in trial_samples:
                    st = s['u_fsm/u_engine/state[2:0]']
                    sym_a = s['u_fsm/u_engine/sym_a_latch[15:0]']
                    dec_out = s['u_fsm/u_engine/dec_out_a[15:0]']
                    dec_valid = s['u_fsm/u_engine/dec_valid_a']
                    comp_a = s['u_fsm/u_engine/comp_result_a']
                    comp_b = s['u_fsm/u_engine/comp_result_b']
                    dec_start = s['u_fsm/u_engine/dec_start']
                    lat = s['u_fsm/u_engine/comp_latency_a[7:0]']
                    inj = s['u_fsm/u_engine/inject_en_latch']
                    enc_out = s['u_fsm/u_engine/enc_out_a_latch[40:0]']
                    inj_out = s['u_fsm/u_engine/inj_out_a_latch[40:0]']
                    print(f'  Sample {s["Sample in Buffer"]:4}: state={st:8}, sym_a={sym_a}, dec_out={dec_out}, '
                          f'dec_valid={dec_valid}, dec_start={dec_start}, comp_a={comp_a}, comp_b={comp_b}, '
                          f'lat={lat}, inj={inj}')
                print()
            in_trial = False
            trial_samples = []

print()
print('=== ANALYZE: What is dec_out_a in DEC_WAIT state? ===')
print('dec_out_a should be STABLE from previous trial until new dec_valid arrives')
print()

# For each trial, find the DEC_WAIT samples and check dec_out_a
trial_samples = []
in_trial = False
trial_count = 0
for r in data:
    state = r['u_fsm/u_engine/state[2:0]']
    if state == 'iSTATE0':
        in_trial = True
        trial_samples = [r]
    elif in_trial:
        trial_samples.append(r)
        if state == 'iSTATE6':
            trial_count += 1
            if trial_count <= 5:
                # Find the DEC_WAIT samples
                dec_wait = [s for s in trial_samples if s['u_fsm/u_engine/state[2:0]'] == 'iSTATE3']
                done = [s for s in trial_samples if s['u_fsm/u_engine/state[2:0]'] == 'iSTATE5']
                if dec_wait and done:
                    first_dec = dec_wait[0]
                    last_dec = dec_wait[-1]
                    done_s = done[0]
                    sym_a = first_dec['u_fsm/u_engine/sym_a_latch[15:0]']
                    dec_out_first = first_dec['u_fsm/u_engine/dec_out_a[15:0]']
                    dec_out_last = last_dec['u_fsm/u_engine/dec_out_a[15:0]']
                    dec_out_done = done_s['u_fsm/u_engine/dec_out_a[15:0]']
                    dec_valid_last = last_dec['u_fsm/u_engine/dec_valid_a']
                    comp_a = done_s['u_fsm/u_engine/comp_result_a']
                    inj = done_s['u_fsm/u_engine/inject_en_latch']
                    print(f'Trial {trial_count}: sym_a={sym_a}, inj={inj}')
                    print(f'  DEC_WAIT first: dec_out={dec_out_first}')
                    print(f'  DEC_WAIT last:  dec_out={dec_out_last}, dec_valid={dec_valid_last}')
                    print(f'  DONE:           dec_out={dec_out_done}, comp_a={comp_a}')
                    print(f'  dec_out stable? {dec_out_first == dec_out_last == dec_out_done}')
                    print()
            in_trial = False
            trial_samples = []

print()
print('=== FINAL DIAGNOSIS: Check if dec_out_a in DONE state == dec_out_a in DEC_WAIT ===')
print()
print('If dec_out_a changes between DEC_WAIT and DONE, there is a timing issue')
print('in result_comparator or the decoder output is not stable')
print()

# Check the comp_latency_a value - it should be 0 if dec_valid arrives before comp_start
print('=== comp_latency_a analysis ===')
print('comp_latency_a = 0x17 = 23 means dec_valid arrived 23 cycles AFTER comp_start')
print('This is CORRECT behavior - decoder takes ~23 cycles')
print()
print('BUT: If comp_latency_a is always 23 (0x17), it means the comparator')
print('is ALWAYS measuring 23 cycles, even when it should be 0 (no injection case)')
print()
print('Wait - comp_latency_a = 23 is the DECODER LATENCY, not related to injection')
print('The comparator measures time from comp_start to dec_valid')
print()

# Check if comp_latency_a is always 0x17
all_lat = [r['u_fsm/u_engine/comp_latency_a[7:0]'] for r in done_states]
from collections import Counter
lat_counts = Counter(all_lat)
print(f'comp_latency_a distribution in DONE states: {dict(lat_counts)}')
print()
print('If comp_latency_a is always 0x17=23, the decoder latency is consistent')
print('The problem must be in the COMPARISON LOGIC, not the timing')
print()

print('=== FINAL CHECK: Is comp_result_a correct given dec_out_a and sym_a_latch? ===')
print()
wrong_comp = 0
correct_comp = 0
for r in done_states:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    comp_a = int(r['u_fsm/u_engine/comp_result_a'])
    
    expected_comp = 1 if sym_a == dec_out else 0
    if expected_comp != comp_a:
        wrong_comp += 1
        if wrong_comp <= 5:
            print(f'  WRONG COMP: sym_a={sym_a}, dec_out={dec_out}, comp_a={comp_a}, expected={expected_comp}')
    else:
        correct_comp += 1

print(f'Correct comparisons: {correct_comp}/{len(done_states)}')
print(f'Wrong comparisons:   {wrong_comp}/{len(done_states)}')
print()
print('If wrong_comp=0: comparator is correct, problem is in decoder output')
print('If wrong_comp>0: comparator has a bug')
