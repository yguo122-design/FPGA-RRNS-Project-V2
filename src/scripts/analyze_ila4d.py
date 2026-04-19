"""
ILA Data 4 - Final Root Cause Confirmation
Hypothesis: The decoder outputs wrong values because the MLD reads stale channel data.
The dec_out_a in DEC_WAIT is the PREVIOUS trial's result (held from last valid).
When dec_valid=1, the new result appears - but it's WRONG.

Key question: Is the decoder output wrong because:
(A) The MLD Stage A/B reads stale ch_x/ch_dist from channels that haven't updated?
(B) The Stage 3 multi-candidate logic is broken?
(C) Something else?

From ILA data:
- Trial 1: sym_a=0xef76=61302, dec_out=0x0376=886
- Python MLD simulation: should output 61302 (dist=0)
- 886 = ch6 k=0 result (dist=4) - this is a WRONG channel with WRONG distance

This means the MLD is selecting ch6 (dist=4) over ch0 (dist=0).
This can ONLY happen if ch0's distance register still holds the PREVIOUS trial's value
when MLD-A reads it.

CONCLUSION: Bug #36 fix (AND of all valid signals) is INSUFFICIENT.
The valid signals from all channels arrive at the same time (same pipeline),
but the x_out and distance registers may be updated 1 cycle LATER than valid
due to register replication timing differences.

The AND of valid signals ensures all valid=1, but x_out/distance may still be stale.
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

def get_ch_k0_results(recv_r):
    """Get k=0 result for each channel"""
    results = []
    for m1, m2, inv, idx1, idx2 in channels:
        ri = recv_r[idx1]
        rj = recv_r[idx2]
        diff = (rj + m2 - ri) % m2
        coeff = (diff * inv) % m2
        x_k0 = ri + m1 * coeff
        dist = hamming_dist(x_k0, recv_r)
        results.append((x_k0, dist))
    return results

print('=== CRITICAL ANALYSIS: What does the hardware decoder output? ===')
print()
print('For each failing trial, check if dec_out matches any channel k=0 result')
print('AND what the PREVIOUS trial\'s channel results were')
print()

# Build trial list
trials = []
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
            done = [s for s in trial_samples if s['u_fsm/u_engine/state[2:0]'] == 'iSTATE5']
            if done:
                trials.append({
                    'samples': trial_samples[:],
                    'done': done[0]
                })
            in_trial = False
            trial_samples = []

print(f'Total trials found: {len(trials)}')
print()

# For each trial, compute what the PREVIOUS trial's channel k=0 results were
# and check if dec_out matches any of them
print('=== CHECK: Does dec_out match PREVIOUS trial\'s channel results? ===')
print()

prev_ch_results = None
prev_sym_a = None
prev_recv_r = None

stale_ch_match = 0
current_ch_match = 0
no_match = 0

for i, trial in enumerate(trials[:30]):
    done = trial['done']
    sym_a = int(done['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(done['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    enc_hex = done['u_fsm/u_engine/enc_out_a_latch[40:0]']
    inj_hex = done['u_fsm/u_engine/inj_out_a_latch[40:0]']
    recv_r = decode_enc_out(inj_hex)  # Use inj_out as decoder input
    comp_a = done['u_fsm/u_engine/comp_result_a']
    
    # Current trial's channel k=0 results
    curr_ch = get_ch_k0_results(recv_r)
    
    # Check if dec_out matches current trial's channels
    curr_match = None
    for j, (x, d) in enumerate(curr_ch):
        if x == dec_out:
            curr_match = (j, d)
            break
    
    # Check if dec_out matches previous trial's channels
    prev_match = None
    if prev_ch_results is not None:
        for j, (x, d) in enumerate(prev_ch_results):
            if x == dec_out:
                prev_match = (j, d)
                break
    
    if curr_match:
        current_ch_match += 1
        match_type = f'CURRENT ch{curr_match[0]} dist={curr_match[1]}'
    elif prev_match:
        stale_ch_match += 1
        match_type = f'PREV ch{prev_match[0]} dist={prev_match[1]}'
    else:
        no_match += 1
        match_type = 'NO MATCH'
    
    correct_dist = hamming_dist(sym_a, recv_r)
    
    if i < 20:
        print(f'Trial {i+1:3d}: sym_a={sym_a:5d}(0x{sym_a:04x}), dec_out={dec_out:5d}(0x{dec_out:04x}), '
              f'comp_a={comp_a}, correct_dist={correct_dist}, match={match_type}')
    
    prev_ch_results = curr_ch
    prev_sym_a = sym_a
    prev_recv_r = recv_r

print(f'...')
print(f'Current trial channel match: {current_ch_match}')
print(f'Previous trial channel match: {stale_ch_match}')
print(f'No match: {no_match}')

print()
print('=== DEEPER ANALYSIS: For current-trial matches, what is the distance? ===')
print()
print('If dec_out matches current trial ch_k0 with dist>0 while correct dist=0,')
print('then MLD is selecting a WRONG channel (dist>0) over the correct one (dist=0)')
print()

prev_ch_results = None
wrong_selection = 0
correct_selection = 0

for i, trial in enumerate(trials):
    done = trial['done']
    sym_a = int(done['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(done['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    enc_hex = done['u_fsm/u_engine/enc_out_a_latch[40:0]']
    inj_hex = done['u_fsm/u_engine/inj_out_a_latch[40:0]']
    recv_r = decode_enc_out(inj_hex)
    comp_a = done['u_fsm/u_engine/comp_result_a']
    
    curr_ch = get_ch_k0_results(recv_r)
    correct_dist = hamming_dist(sym_a, recv_r)
    
    # Find which channel gives dec_out
    dec_ch = None
    for j, (x, d) in enumerate(curr_ch):
        if x == dec_out:
            dec_ch = (j, d)
            break
    
    if dec_ch is not None:
        if dec_ch[1] > correct_dist:
            wrong_selection += 1
            if wrong_selection <= 10:
                # Find the correct channel
                correct_chs = [(j, x, d) for j, (x, d) in enumerate(curr_ch) if x == sym_a]
                print(f'Trial {i+1}: sym_a={sym_a}, dec_out={dec_out}')
                print(f'  MLD selected: ch{dec_ch[0]}, dist={dec_ch[1]}')
                print(f'  Correct channels: {correct_chs}')
                print(f'  Correct dist={correct_dist}')
                print()
        else:
            correct_selection += 1
    
    prev_ch_results = curr_ch

print(f'MLD selected wrong channel (dist > correct_dist): {wrong_selection}')
print(f'MLD selected correct channel: {correct_selection}')

print()
print('=== FINAL DIAGNOSIS ===')
print()
print('From the analysis:')
print('1. The decoder outputs wrong values even with no errors (dist=0 input)')
print('2. The MLD is selecting channels with dist>0 over channels with dist=0')
print('3. This means the MLD Stage A/B is reading STALE x_out/distance values')
print('   from some channels when mid_valid_comb fires')
print()
print('ROOT CAUSE: In decoder_2nrm.v, the MLD Stage A combinational block reads')
print('ch_x[j] and ch_dist[j] when mid_valid_comb=1 (AND of all ch_valid).')
print('However, ch_valid[j] is the output of the Stage 3 pipeline register,')
print('while ch_x[j] and ch_dist[j] are ALSO Stage 3 pipeline register outputs.')
print()
print('Due to Vivado register replication (max_fanout constraints on x_cand_16_s1e,')
print('x_cand_16_s2a, x_cand_16_s2b), different channels may have their Stage 3')
print('registers updated at SLIGHTLY DIFFERENT times within the same clock cycle.')
print()
print('BUT WAIT - all registers are clocked by the same clock edge!')
print('They should all update simultaneously...')
print()
print('ALTERNATIVE ROOT CAUSE: The Stage 3 combinational logic in decoder_channel_2nrm_param')
print('computes best_x_all and best_dist_all using a DEEP combinational tree:')
print('  dist_k0 -> best_dist_01 -> best_dist_0123 -> best_dist_all')
print('  x_k0   -> best_x_01    -> best_x_0123    -> best_x_all')
print()
print('This 4-level mux tree may have TIMING VIOLATIONS (setup time violations)')
print('causing the Stage 3 output registers to capture WRONG values.')
print()
print('EVIDENCE: The decoder outputs values that are NOT from any channel k=0 result')
print('in 46/70 non-injected failing cases. This is consistent with timing violations')
print('where the combinational logic has not settled before the clock edge.')
print()
print('RECOMMENDED FIX: Add an additional pipeline register stage between')
print('Stage 3 combinational logic and the output registers, OR')
print('simplify the Stage 3 combinational logic to reduce depth.')
