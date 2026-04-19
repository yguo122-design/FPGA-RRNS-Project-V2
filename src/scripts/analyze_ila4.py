"""
ILA Data 4 Analysis Script
Analyzes iladata4.csv to find root cause of 98% failure rate after Bug #36 fix
"""
import csv

rows = []
with open('src/scripts/iladata4.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

# Skip Radix header row
data = [r for r in rows if r['Sample in Buffer'] not in ['Radix - UNSIGNED', 'UNSIGNED']]

# Find all DONE states (iSTATE5)
done_states = [r for r in data if r['u_fsm/u_engine/state[2:0]'] == 'iSTATE5']
print(f'Total DONE states found: {len(done_states)}')

# Analyze comp_result_a and comp_result_b
pass_a = sum(1 for r in done_states if r['u_fsm/u_engine/comp_result_a'] == '1')
pass_b = sum(1 for r in done_states if r['u_fsm/u_engine/comp_result_b'] == '1')
both_pass = sum(1 for r in done_states if r['u_fsm/u_engine/comp_result_a'] == '1' and r['u_fsm/u_engine/comp_result_b'] == '1')
both_fail = sum(1 for r in done_states if r['u_fsm/u_engine/comp_result_a'] == '0' and r['u_fsm/u_engine/comp_result_b'] == '0')

print(f'Pass A: {pass_a}/{len(done_states)} = {pass_a/len(done_states)*100:.1f}%')
print(f'Pass B: {pass_b}/{len(done_states)} = {pass_b/len(done_states)*100:.1f}%')
print(f'Both Pass: {both_pass}/{len(done_states)} = {both_pass/len(done_states)*100:.1f}%')
print(f'Both Fail: {both_fail}/{len(done_states)} = {both_fail/len(done_states)*100:.1f}%')

# Analyze inject_en_latch in DONE states
injected = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '1')
not_injected = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '0')
print(f'\nInjected trials: {injected}, Not injected: {not_injected}')

# For non-injected trials, check pass rate
no_inj_pass = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '0' 
                  and r['u_fsm/u_engine/comp_result_a'] == '1' 
                  and r['u_fsm/u_engine/comp_result_b'] == '1')
no_inj_fail_cases = [r for r in done_states 
                     if r['u_fsm/u_engine/inject_en_latch'] == '0' 
                     and (r['u_fsm/u_engine/comp_result_a'] == '0' or r['u_fsm/u_engine/comp_result_b'] == '0')]
print(f'No injection - Pass: {no_inj_pass}, Fail: {len(no_inj_fail_cases)}')

# For injected trials, check pass rate
inj_pass = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '1' 
               and r['u_fsm/u_engine/comp_result_a'] == '1' 
               and r['u_fsm/u_engine/comp_result_b'] == '1')
inj_fail = sum(1 for r in done_states if r['u_fsm/u_engine/inject_en_latch'] == '1' 
               and (r['u_fsm/u_engine/comp_result_a'] == '0' or r['u_fsm/u_engine/comp_result_b'] == '0'))
print(f'With injection - Pass: {inj_pass}, Fail: {inj_fail}')

print()
print('=== NON-INJECTED TRIALS THAT FAIL (should be 0%) ===')
print(f'Count: {len(no_inj_fail_cases)}')
print()
print('Sample | sym_a_latch | dec_out_a | enc_out_a_latch   | inj_out_a_latch   | comp_a | comp_b')
for r in no_inj_fail_cases[:20]:
    sample = r['Sample in Buffer']
    sym_a = r['u_fsm/u_engine/sym_a_latch[15:0]']
    dec_out = r['u_fsm/u_engine/dec_out_a[15:0]']
    enc_out = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    inj_out = r['u_fsm/u_engine/inj_out_a_latch[40:0]']
    comp_a = r['u_fsm/u_engine/comp_result_a']
    comp_b = r['u_fsm/u_engine/comp_result_b']
    print(f'{sample:6} | {sym_a:11} | {dec_out:9} | {enc_out:17} | {inj_out:17} | {comp_a:6} | {comp_b}')

print()
print('=== KEY OBSERVATION: enc_out_a_latch vs inj_out_a_latch for non-injected fails ===')
mismatch_count = 0
for r in no_inj_fail_cases:
    enc = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    inj = r['u_fsm/u_engine/inj_out_a_latch[40:0]']
    if enc != inj:
        mismatch_count += 1
        sample = r['Sample in Buffer']
        print(f'  Sample {sample}: enc={enc} != inj={inj}')
print(f'Total enc!=inj mismatches in non-injected fails: {mismatch_count}')

print()
print('=== VERIFY ENCODING CORRECTNESS for non-injected fails ===')
moduli = [257, 256, 61, 59, 55, 53]
bits = [9, 8, 6, 6, 6, 6]
offsets = [32, 24, 18, 12, 6, 0]

def decode_enc_out(enc_hex):
    """Decode enc_out_a_latch (41-bit packed residues)"""
    val = int(enc_hex, 16)
    r257 = (val >> 32) & 0x1FF
    r256 = (val >> 24) & 0xFF
    r61  = (val >> 18) & 0x3F
    r59  = (val >> 12) & 0x3F
    r55  = (val >> 6)  & 0x3F
    r53  = (val >> 0)  & 0x3F
    return [r257, r256, r61, r59, r55, r53]

def compute_expected_enc(sym_a):
    """Compute expected encoding for sym_a"""
    return [sym_a % m for m in moduli]

enc_errors = 0
for r in no_inj_fail_cases[:10]:
    sym_a_hex = r['u_fsm/u_engine/sym_a_latch[15:0]']
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    sym_a = int(sym_a_hex, 16)
    actual_residues = decode_enc_out(enc_hex)
    expected_residues = compute_expected_enc(sym_a)
    match = actual_residues == expected_residues
    if not match:
        enc_errors += 1
    print(f'  sym_a=0x{sym_a_hex}({sym_a}): enc_ok={match}')
    if not match:
        print(f'    Expected: {expected_residues}')
        print(f'    Actual:   {actual_residues}')

print()
print('=== VERIFY DECODING: Does dec_out_a match sym_a for non-injected? ===')
for r in no_inj_fail_cases[:15]:
    sym_a_hex = r['u_fsm/u_engine/sym_a_latch[15:0]']
    dec_out_hex = r['u_fsm/u_engine/dec_out_a[15:0]']
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    inj_hex = r['u_fsm/u_engine/inj_out_a_latch[40:0]']
    sym_a = int(sym_a_hex, 16)
    dec_out = int(dec_out_hex, 16)
    comp_a = r['u_fsm/u_engine/comp_result_a']
    comp_b = r['u_fsm/u_engine/comp_result_b']
    
    # Check if enc == inj (no injection)
    enc_eq_inj = (enc_hex == inj_hex)
    
    print(f'  sym_a={sym_a}(0x{sym_a_hex}), dec_out={dec_out}(0x{dec_out_hex}), '
          f'match={sym_a==dec_out}, enc==inj={enc_eq_inj}, comp_a={comp_a}, comp_b={comp_b}')

print()
print('=== CRITICAL: Check if inj_out_a_latch == enc_out_a_latch for ALL non-injected ===')
all_match = True
for r in no_inj_fail_cases:
    enc = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    inj = r['u_fsm/u_engine/inj_out_a_latch[40:0]']
    if enc != inj:
        all_match = False
        break
print(f'All enc==inj for non-injected fails: {all_match}')

print()
print('=== ANALYZE: What does the decoder receive vs what it should? ===')
print('For non-injected fails, decoder input = inj_out_a_latch = enc_out_a_latch')
print('Decoder should output sym_a, but outputs dec_out_a')
print()

# Check if dec_out_a == sym_a for non-injected fails
for r in no_inj_fail_cases[:5]:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    residues = decode_enc_out(enc_hex)
    
    print(f'sym_a={sym_a}, dec_out={dec_out}')
    print(f'  Residues sent to decoder: {residues}')
    print(f'  Expected residues: {compute_expected_enc(sym_a)}')
    
    # Verify CRT reconstruction for channel 0 (pair 257, 256)
    r257, r256 = residues[0], residues[1]
    # x = r257 + 257 * ((r256 - r257) * Inv(257, 256) % 256)
    # Inv(257, 256) = 1 (since 257 % 256 = 1, and 1*1=1 mod 256)
    diff = (r256 + 256 - r257) % 256
    coeff = (diff * 1) % 256  # Inv=1
    x_cand_ch0 = r257 + 257 * coeff
    print(f'  CRT ch0 (257,256): r257={r257}, r256={r256}, diff={diff}, coeff={coeff}, x_cand={x_cand_ch0}')
    print(f'  Expected x={sym_a}, CRT ch0 gives x={x_cand_ch0}, match={x_cand_ch0==sym_a}')
    print()

print()
print('=== LOOK AT PASSING CASES ===')
pass_cases = [r for r in done_states if r['u_fsm/u_engine/comp_result_a'] == '1' and r['u_fsm/u_engine/comp_result_b'] == '1']
print(f'Both-pass cases: {len(pass_cases)}')
for r in pass_cases:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    inj = r['u_fsm/u_engine/inject_en_latch']
    enc_hex = r['u_fsm/u_engine/enc_out_a_latch[40:0]']
    inj_hex = r['u_fsm/u_engine/inj_out_a_latch[40:0]']
    print(f'  Sample {r["Sample in Buffer"]}: sym_a={sym_a}(0x{r["u_fsm/u_engine/sym_a_latch[15:0]"]}), '
          f'dec_out={dec_out}, inject={inj}, enc==inj={enc_hex==inj_hex}')
