"""
Bug #39 Final Analysis - iladata5 deep dive
comp_latency_a = 0x18 = 24 decimal -> this is Bug #37 bitstream (NOT Bug #38)
Bug #38 bitstream would show comp_latency_a = 0x19 = 25 decimal

Key question: Does the hardware dec_out match Python MLD result?
If YES -> the decoder computes correctly but something else is wrong
If NO  -> the decoder itself has a computation error
"""
import csv

moduli = [257, 256, 61, 59, 55, 53]
channels = [
    (257, 256, 1,  0, 1), (257,  61, 48, 0, 2), (257,  59, 45, 0, 3),
    (257,  55, 3,  0, 4), (257,  53, 33, 0, 5), (256,  61, 56, 1, 2),
    (256,  59, 3,  1, 3), (256,  55, 26, 1, 4), (256,  53, 47, 1, 5),
    ( 61,  59, 30, 2, 3), ( 61,  55, 46, 2, 4), ( 61,  53, 20, 2, 5),
    ( 59,  55, 14, 3, 4), ( 59,  53, 9,  3, 5), ( 55,  53, 27, 4, 5),
]

def decode_enc(enc_hex):
    val = int(enc_hex, 16)
    return [(val>>32)&0x1FF, (val>>24)&0xFF, (val>>18)&0x3F,
            (val>>12)&0x3F, (val>>6)&0x3F, val&0x3F]

def hamming(x, recv_r):
    return sum(1 for i,m in enumerate(moduli) if x%m != recv_r[i])

def mld(recv_r):
    best_x, best_d = 0, 7
    for m1,m2,inv,i1,i2 in channels:
        ri,rj = recv_r[i1], recv_r[i2]
        diff = (rj + m2 - ri) % m2
        coeff = (diff * inv) % m2
        x0 = ri + m1*coeff
        for k in range(5):
            xk = x0 + k*m1*m2
            if xk > 65535:
                break
            d = hamming(xk, recv_r)
            if d < best_d:
                best_d, best_x = d, xk
    return best_x, best_d

def mld_per_channel(recv_r):
    """Return per-channel best result"""
    results = []
    for ch_idx, (m1,m2,inv,i1,i2) in enumerate(channels):
        ri,rj = recv_r[i1], recv_r[i2]
        diff = (rj + m2 - ri) % m2
        coeff = (diff * inv) % m2
        x0 = ri + m1*coeff
        best_x, best_d = x0, hamming(x0, recv_r)
        for k in range(1, 5):
            xk = x0 + k*m1*m2
            if xk > 65535:
                break
            d = hamming(xk, recv_r)
            if d < best_d:
                best_d, best_x = d, xk
        results.append((ch_idx, m1, m2, best_x, best_d))
    return results

rows = []
with open('src/scripts/iladata5.csv', 'r', encoding='utf-8', errors='replace') as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

data = [r for r in rows if r.get('Sample in Buffer','') not in ['Radix - UNSIGNED','UNSIGNED','']]
done = [r for r in data if r.get('u_fsm/u_engine/state[2:0]','') == 'iSTATE5']

print("=" * 70)
print("iladata5 ANALYSIS - comp_latency check")
print("=" * 70)
from collections import Counter
lats = Counter(r.get('u_fsm/u_engine/comp_latency_a[7:0]','N/A') for r in done)
print("comp_latency_a distribution:", dict(lats))
print("0x18 = 24 decimal -> Bug #37 bitstream (no ch_reg stage)")
print("0x19 = 25 decimal -> Bug #38 bitstream (with ch_reg stage)")
print()

no_inj_fails = [r for r in done
                if r.get('u_fsm/u_engine/inject_en_latch','')=='0'
                and r.get('u_fsm/u_engine/comp_result_a','')=='0']

print("=" * 70)
print("No-injection failures: hardware dec_out vs Python MLD")
print("=" * 70)
print()

hw_correct = 0
hw_wrong = 0
for r in no_inj_fails[:20]:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    inj_hex = r['u_fsm/u_engine/inj_out_a_latch[40:0]']
    recv_r = decode_enc(inj_hex)
    py_x, py_d = mld(recv_r)
    correct_d = hamming(sym_a, recv_r)
    match = (dec_out == py_x)
    if match:
        hw_correct += 1
    else:
        hw_wrong += 1
    status = "OK" if match else "WRONG"
    print("sym_a=0x%04x dec_out=0x%04x py_mld=0x%04x py_dist=%d correct_dist=%d [%s]" % (
        sym_a, dec_out, py_x, py_d, correct_d, status))
    if not match:
        # Find which channel gives dec_out
        ch_results = mld_per_channel(recv_r)
        for ch_idx, m1, m2, ch_x, ch_d in ch_results:
            if ch_x == dec_out:
                print("  -> hw selected ch%d (M1=%d,M2=%d): x=0x%04x dist=%d" % (
                    ch_idx, m1, m2, ch_x, ch_d))
        # Find which channel gives correct answer
        for ch_idx, m1, m2, ch_x, ch_d in ch_results:
            if ch_x == sym_a:
                print("  -> correct ch%d (M1=%d,M2=%d): x=0x%04x dist=%d" % (
                    ch_idx, m1, m2, ch_x, ch_d))
                break

print()
print("Hardware matches Python MLD: %d/%d" % (hw_correct, hw_correct+hw_wrong))
print("Hardware WRONG vs Python MLD: %d/%d" % (hw_wrong, hw_correct+hw_wrong))
print()

print("=" * 70)
print("CRITICAL ANALYSIS: What does dec_out represent?")
print("=" * 70)
print()
print("If hw_wrong > 0: decoder computes wrong answer (timing/logic bug)")
print("If hw_wrong == 0: decoder computes correct MLD answer but")
print("  the comparator reads the WRONG trial's result (off-by-one)")
print()

# Check if dec_out matches the PREVIOUS trial's sym_a
print("Checking if dec_out == PREVIOUS trial's sym_a (off-by-one hypothesis):")
prev_sym_a = None
stale_count = 0
total_checked = 0
for r in done:
    sym_a = int(r['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    dec_out = int(r['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    if prev_sym_a is not None:
        total_checked += 1
        if dec_out == prev_sym_a:
            stale_count += 1
    prev_sym_a = sym_a

print("dec_out == prev_sym_a: %d/%d (%.1f%%)" % (
    stale_count, total_checked, 100.0*stale_count/total_checked if total_checked else 0))
print()

# Check if dec_out matches the NEXT trial's sym_a
print("Checking if dec_out == NEXT trial's sym_a (one-ahead hypothesis):")
next_count = 0
for i in range(len(done)-1):
    dec_out = int(done[i]['u_fsm/u_engine/dec_out_a[15:0]'], 16)
    next_sym = int(done[i+1]['u_fsm/u_engine/sym_a_latch[15:0]'], 16)
    if dec_out == next_sym:
        next_count += 1
print("dec_out == next_sym_a: %d/%d (%.1f%%)" % (
    next_count, len(done)-1, 100.0*next_count/(len(done)-1) if len(done)>1 else 0))
print()

print("=" * 70)
print("CONCLUSION")
print("=" * 70)
print()
print("iladata5 was captured with Bug #37 bitstream (comp_latency=24, not 25)")
print("Bug #38 fix (ch_reg stage) was NOT yet active when iladata5 was captured")
print()
print("The test_results_20260319_141457.csv shows Avg_Clk_Per_Trial=25")
print("This means comp_latency_a=25 in the Bug #38 bitstream")
print("Bug #38 IS active in the latest test, but still 98% failure")
print()
print("We need NEW ILA data captured with Bug #38 bitstream to diagnose further")
print("The new ILA should show comp_latency_a=0x19=25 (not 0x18=24)")
