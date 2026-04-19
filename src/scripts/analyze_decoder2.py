"""
Decoder analysis script - Part 2
Investigates why dec_out_a=128 instead of 61302 in ILA data
Focus: Is the issue in the hardware implementation timing or algorithm?
"""
import math

moduli = [257, 256, 61, 59, 55, 53]

channels = [
    (0,  257, 256, 1,  0, 1),
    (1,  257, 61,  48, 0, 2),
    (2,  257, 59,  45, 0, 3),
    (3,  257, 55,  3,  0, 4),
    (4,  257, 53,  33, 0, 5),
    (5,  256, 61,  56, 1, 2),
    (6,  256, 59,  3,  1, 3),
    (7,  256, 55,  26, 1, 4),
    (8,  256, 53,  47, 1, 5),
    (9,  61,  59,  30, 2, 3),
    (10, 61,  55,  46, 2, 4),
    (11, 61,  53,  20, 2, 5),
    (12, 59,  55,  14, 3, 4),
    (13, 59,  53,  9,  3, 5),
    (14, 55,  53,  27, 4, 5),
]

# ============================================================
# ILA data shows dec_out_a=0x0080=128 for sym_a=61302
# But our analysis shows the correct answer should be 61302
# 
# Hypothesis: The ILA captures dec_out_a BEFORE the decoder
# has finished computing (timing issue), OR the decoder is
# using the WRONG inj_out_a_latch value.
# ============================================================

print("="*80)
print("INVESTIGATION: Why does dec_out_a=128 instead of 61302?")
print("="*80)
print()

# From ILA data (iladata2.csv, Sample 29):
# sym_a_latch = 0xef76 = 61302
# enc_out_a_latch = 0x08876e81822
# inj_out_a_latch = 0x08076e81822
# dec_out_a = 0x0080 = 128
# dec_valid_a = 1 (at Sample 29)
# comp_result_a = 0 (FAIL)

print("ILA data (Sample 29):")
print("  sym_a_latch = 0xef76 = 61302")
print("  enc_out_a_latch = 0x08876e81822")
print("  inj_out_a_latch = 0x08076e81822")
print("  dec_out_a = 0x0080 = 128")
print("  dec_valid_a = 1")
print()

# The decoder output is 128. Let's check what input would produce 128.
# If the decoder received the CORRECT (non-injected) residues, what would it output?
print("Hypothesis 1: Decoder received CORRECT (non-injected) residues")
sym_a = 61302
recv_r_correct = [sym_a % m for m in moduli]
print("  Correct residues:", recv_r_correct)

# Run MLD with correct residues
best_dist = 6
best_x = 0
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_correct[idx1]
    rj = recv_r_correct[idx2]
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_correct[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
print("  MLD result: x=%d, dist=%d" % (best_x, best_dist))
print("  -> Would produce x=61302 (correct), NOT 128")
print()

print("Hypothesis 2: Decoder received INJECTED residues (as expected)")
recv_r_inj = [128, 118, 58, 1, 32, 34]
print("  Injected residues:", recv_r_inj)

best_dist = 6
best_x = 0
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_inj[idx1]
    rj = recv_r_inj[idx2]
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_inj[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
print("  MLD result: x=%d, dist=%d" % (best_x, best_dist))
print("  -> Would produce x=61302 (correct), NOT 128")
print()

print("Hypothesis 3: Decoder received WRONG residues (timing issue)")
print("  What residues would produce dec_out_a=128?")
print()

# If dec_out_a=128, what residues could have caused this?
# 128 = 128 % 257, 128 % 256, 128 % 61 = 6, 128 % 59 = 10, 128 % 55 = 18, 128 % 53 = 22
x_wrong = 128
wrong_r = [x_wrong % m for m in moduli]
print("  If x=128, its residues would be:", wrong_r)
print()

# Check: what if the decoder received the PREVIOUS trial's residues?
# From ILA data, the previous trial had sym_a=0x284b=10315 (from iladata.csv)
# But in iladata2.csv, the first trial starts at Sample 4 with sym_a=0xef76
# The previous state shows enc_out_a_latch=0 (initial state)
print("  What if decoder received ZERO residues (initial state)?")
recv_r_zero = [0, 0, 0, 0, 0, 0]
best_dist = 6
best_x = 0
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_zero[idx1]
    rj = recv_r_zero[idx2]
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_zero[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
print("  MLD result with zero residues: x=%d, dist=%d" % (best_x, best_dist))
print()

# ============================================================
# Key insight: The ILA shows dec_out_a=128 = r257_inj!
# This is the MINIMUM NON-NEGATIVE SOLUTION from Channel 0
# when using the injected residues.
# 
# Channel 0 (M1=257, M2=256, INV=1):
#   ri = r257_inj = 128
#   rj = r256_inj = 118
#   diff = (118 + 256 - 128) % 256 = 246
#   coeff = 246 * 1 % 256 = 246
#   x_cand_k0 = 128 + 257 * 246 = 63350
#
# But dec_out_a=128, not 63350!
# This means the decoder is outputting ri (the raw r257 value)
# instead of the CRT-reconstructed x_cand!
# ============================================================

print("="*80)
print("KEY INSIGHT: dec_out_a=128 = r257_inj!")
print("="*80)
print()
print("The decoder output 128, which equals r257_inj (the injected r257 value).")
print("This is NOT the CRT-reconstructed value (which would be 63350 for Channel 0).")
print()
print("This suggests the decoder is outputting the RAW RESIDUE VALUE")
print("instead of the CRT-reconstructed candidate!")
print()

# Check: what if the decoder is using the WRONG channel?
# Channel 0 with k=0: x_cand = 128 + 257*246 = 63350 (not 128)
# 
# But wait - what if the decoder is outputting x_cand_k0 from a channel
# where x_cand_k0 = 128?
print("Which channel produces x_cand_k0=128?")
recv_r_inj = [128, 118, 58, 1, 32, 34]
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_inj[idx1]
    rj = recv_r_inj[idx2]
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    if x_cand_k0 == 128:
        print("  Channel %d (M1=%d, M2=%d): x_cand_k0=%d" % (ch, m1, m2, x_cand_k0))

print()

# ============================================================
# Let's check: what if the decoder is using the PREVIOUS trial's
# inj_out_a_latch value?
# From iladata2.csv, Sample 0: inj_out_a_latch = 0x00000000000 (all zeros)
# The first trial (Sample 4-29) uses sym_a=0xef76=61302
# But the decoder starts at Sample 10 (dec_start=1)
# The decoder output appears at Sample 29 (dec_valid_a=1)
# 
# Wait - let me re-read the ILA data more carefully.
# In iladata2.csv:
# - Sample 0: state=iSTATE, inj_out_a_latch=0x00000000000
# - Sample 2: state=iSTATE1 (ENC_WAIT), inject_en_latch=1
# - Sample 4: state=iSTATE2 (INJ_WAIT), sym_a=0xef76
# - Sample 7: state=iSTATE3 (DEC_WAIT), enc_out_a_latch=0x08876e81822
# - Sample 10: state=iSTATE4 (COMP_WAIT), dec_start=1, inj_out_a_latch=0x08076e81822
# - Sample 29: state=iSTATE4, dec_valid_a=1, dec_out_a=0x0080=128
# 
# The decoder receives inj_out_a_latch=0x08076e81822 at Sample 10
# and outputs dec_out_a=128 at Sample 29 (19 cycles later)
# 
# But the decoder pipeline is 9 cycles (1 input + 6 channel + 2 MLD)
# So the output at Sample 29 corresponds to input at Sample 20
# 
# At Sample 20, inj_out_a_latch is still 0x08076e81822 (unchanged)
# So the decoder SHOULD output 61302, not 128!
# ============================================================

print("="*80)
print("TIMING ANALYSIS:")
print("="*80)
print()
print("From ILA data (iladata2.csv):")
print("  Sample 10: dec_start=1, inj_out_a_latch=0x08076e81822")
print("  Sample 29: dec_valid_a=1, dec_out_a=0x0080=128")
print("  Latency: 29-10 = 19 cycles")
print()
print("Expected decoder latency: 9 cycles (1 input + 6 channel + 2 MLD)")
print("Actual latency from ILA: 19 cycles")
print()
print("WAIT - let me re-check the decoder latency from the source code...")
print()
print("From decoder_2nrm.v comments:")
print("  1 cycle: input register")
print("  Stage 1a: 1 cycle")
print("  Stage 1b: 1 cycle")
print("  Stage 1c_pre: 1 cycle (fabric input register)")
print("  Stage 1c DSP: 3 cycles (AREG+MREG+PREG)")
print("  Stage 1d: 1 cycle")
print("  Stage 1e_pre: 1 cycle (fabric input register)")
print("  Stage 1e DSP: 3 cycles (AREG+MREG+PREG)")
print("  Stage 2a: 1 cycle")
print("  Stage 2b: 1 cycle")
print("  Stage 2c: 1 cycle")
print("  Stage 3: 1 cycle")
print("  MLD-A: 1 cycle")
print("  MLD-B: 1 cycle")
print()
print("Total: 1+1+1+1+3+1+1+3+1+1+1+1+1+1 = 18 cycles!")
print()
print("So the decoder latency is 18 cycles, not 9!")
print("Sample 10 + 18 = Sample 28 -> output at Sample 28 or 29")
print("This matches the ILA data (dec_valid_a=1 at Sample 29)!")
print()
print("But the output is 128, not 61302...")
print()

# ============================================================
# Let me check: what was the input to the decoder 18 cycles before Sample 29?
# That would be Sample 29-18 = Sample 11
# At Sample 11, inj_out_a_latch = 0x08076e81822 (same as Sample 10)
# So the decoder SHOULD output 61302!
# ============================================================

print("="*80)
print("CRITICAL QUESTION: What input did the decoder receive?")
print("="*80)
print()
print("The decoder output at Sample 29 corresponds to input at Sample 29-18=11")
print("At Sample 11, inj_out_a_latch = 0x08076e81822")
print()
print("With this input, the correct MLD output should be 61302.")
print("But the actual output is 128.")
print()
print("This strongly suggests a BUG IN THE HARDWARE IMPLEMENTATION!")
print()

# ============================================================
# Let me check: what if the decoder is using the WRONG inj_out_a_latch?
# From iladata2.csv Sample 0: inj_out_a_latch = 0x00000000000
# What if the decoder received the INITIAL (zero) value?
# ============================================================

print("What if decoder received ZERO input (initial state)?")
recv_r_zero = [0, 0, 0, 0, 0, 0]
best_dist = 6
best_x = 0
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_zero[idx1]
    rj = recv_r_zero[idx2]
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_zero[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
print("  MLD result: x=%d, dist=%d" % (best_x, best_dist))
print()

# ============================================================
# Let me check: what if the decoder received the PREVIOUS trial's
# inj_out_a_latch? From iladata2.csv, the previous trial (before
# the first one) had inj_out_a_latch=0x00000000000.
# But the SECOND trial (Sample 37-62) has sym_a=0x77bb=30651
# and inj_out_a_latch=0x044bb75c411.
# At Sample 62, dec_valid_a=1, dec_out_a=0xaef2=44786
# 
# Let me check: what does the decoder output for the SECOND trial?
# ============================================================

print("="*80)
print("SECOND TRIAL ANALYSIS (sym_a=0x77bb=30651):")
print("="*80)
print()
sym_a2 = 0x77bb  # 30651
enc2 = 0x044bb75e411
inj2 = 0x044bb75c411
r257_2 = (inj2 >> 32) & 0x1FF
r256_2 = (inj2 >> 24) & 0xFF
r61_2  = (inj2 >> 18) & 0x3F
r59_2  = (inj2 >> 12) & 0x3F
r55_2  = (inj2 >> 6)  & 0x3F
r53_2  = (inj2 >> 0)  & 0x3F

recv_r_2 = [r257_2, r256_2, r61_2, r59_2, r55_2, r53_2]
print("sym_a2 =", sym_a2)
print("Injected residues:", recv_r_2)
print("Original residues:", [sym_a2 % m for m in moduli])
diff2 = enc2 ^ inj2
print("Injected bit:", diff2.bit_length()-1)
print()

# MLD with k=0..4
best_dist = 6
best_x = 0
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_2[idx1]
    rj = recv_r_2[idx2]
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_2[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
print("MLD result (k=0..4): x=%d, dist=%d" % (best_x, best_dist))
print("ILA shows dec_out_a=0xaef2=%d" % 0xaef2)
print("Correct answer: x=%d" % sym_a2)
print()

# ============================================================
# IMPORTANT OBSERVATION:
# ILA shows dec_out_a=0xaef2=44786 for sym_a=30651
# But MLD should output 30651!
# 
# Let me check: what if the decoder is outputting the result
# for the PREVIOUS trial's input?
# 
# Trial 1: sym_a=61302, inj=0x08076e81822 -> should output 61302
# Trial 2: sym_a=30651, inj=0x044bb75c411 -> should output 30651
# 
# But ILA shows:
# Trial 1: dec_out_a=128 (WRONG)
# Trial 2: dec_out_a=44786 (WRONG)
# 
# What if the decoder is outputting the result for the INITIAL state
# (zero input) for Trial 1, and the result for Trial 1's input for Trial 2?
# ============================================================

print("="*80)
print("HYPOTHESIS: Decoder is outputting result for PREVIOUS trial's input")
print("="*80)
print()

# What does MLD output for ZERO input?
recv_r_zero = [0, 0, 0, 0, 0, 0]
best_dist = 6
best_x = 0
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_zero[idx1]
    rj = recv_r_zero[idx2]
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_zero[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
print("MLD result for ZERO input: x=%d, dist=%d" % (best_x, best_dist))
print("ILA Trial 1 shows dec_out_a=128 -> NOT zero input result")
print()

# What does MLD output for Trial 1's input (inj=0x08076e81822)?
recv_r_1 = [128, 118, 58, 1, 32, 34]
best_dist = 6
best_x = 0
for ch, m1, m2, inv, idx1, idx2 in channels:
    period = m1 * m2
    ri = recv_r_1[idx1]
    rj = recv_r_1[idx2]
    diff = (rj + m2 - ri) % m2
    coeff = (diff * inv) % m2
    x_cand_k0 = ri + m1 * coeff
    for k in range(5):
        x_k = x_cand_k0 + k * period
        if x_k > 65535:
            break
        cand_r = [x_k % m for m in moduli]
        dist = sum(1 for i in range(6) if cand_r[i] != recv_r_1[i])
        if dist < best_dist:
            best_dist = dist
            best_x = x_k
print("MLD result for Trial 1 input (inj=0x08076e81822): x=%d, dist=%d" % (best_x, best_dist))
print("ILA Trial 2 shows dec_out_a=0xaef2=%d" % 0xaef2)
print()

# Hmm, Trial 1 MLD gives 61302, not 44786
# Let me check what input gives 44786

print("What input gives dec_out_a=44786?")
target = 44786
target_r = [target % m for m in moduli]
print("  If x=44786, residues would be:", target_r)
print()

# Check if 44786 could come from Trial 1's input with some timing offset
# Let me check all possible inputs from the ILA data

print("="*80)
print("CHECKING ALL TRIAL INPUTS FROM ILA DATA:")
print("="*80)
print()

# From iladata2.csv, the trials and their outputs:
trials = [
    # (trial_num, sym_a, inj_hex, dec_out_a_hex)
    (1, 0xef76, 0x08076e81822, 0x0080),   # Sample 29
    (2, 0x77bb, 0x044bb75c411, 0xaef2),   # Sample 62
    (3, 0x3bdd, 0x0a2dd3ac8c8, 0x7819),   # Sample 95
    (4, 0x9dce, 0x031ce42a70d, 0x3b6c),   # Sample 128
    (5, 0xcec7, 0x0fac5c0c669, 0x9e97),   # Sample 161
]

for trial_num, sym_a_t, inj_t, dec_out_t in trials:
    r257_t = (inj_t >> 32) & 0x1FF
    r256_t = (inj_t >> 24) & 0xFF
    r61_t  = (inj_t >> 18) & 0x3F
    r59_t  = (inj_t >> 12) & 0x3F
    r55_t  = (inj_t >> 6)  & 0x3F
    r53_t  = (inj_t >> 0)  & 0x3F
    recv_r_t = [r257_t, r256_t, r61_t, r59_t, r55_t, r53_t]
    
    best_dist = 6
    best_x = 0
    for ch, m1, m2, inv, idx1, idx2 in channels:
        period = m1 * m2
        ri = recv_r_t[idx1]
        rj = recv_r_t[idx2]
        diff = (rj + m2 - ri) % m2
        coeff = (diff * inv) % m2
        x_cand_k0 = ri + m1 * coeff
        for k in range(5):
            x_k = x_cand_k0 + k * period
            if x_k > 65535:
                break
            cand_r = [x_k % m for m in moduli]
            dist = sum(1 for i in range(6) if cand_r[i] != recv_r_t[i])
            if dist < best_dist:
                best_dist = dist
                best_x = x_k
    
    correct = "CORRECT" if best_x == sym_a_t else "WRONG"
    ila_correct = "CORRECT" if dec_out_t == sym_a_t else "WRONG"
    print("Trial %d: sym_a=0x%04x=%5d, inj=0x%011x" % (trial_num, sym_a_t, sym_a_t, inj_t))
    print("  Expected MLD output: %d (%s)" % (best_x, correct))
    print("  ILA dec_out_a: 0x%04x=%d (%s)" % (dec_out_t, dec_out_t, ila_correct))
    
    # Check if ILA output matches PREVIOUS trial's expected output
    if trial_num > 1:
        prev_trial = trials[trial_num-2]
        prev_sym_a = prev_trial[1]
        prev_inj = prev_trial[2]
        r257_p = (prev_inj >> 32) & 0x1FF
        r256_p = (prev_inj >> 24) & 0xFF
        r61_p  = (prev_inj >> 18) & 0x3F
        r59_p  = (prev_inj >> 12) & 0x3F
        r55_p  = (prev_inj >> 6)  & 0x3F
        r53_p  = (prev_inj >> 0)  & 0x3F
        recv_r_p = [r257_p, r256_p, r61_p, r59_p, r55_p, r53_p]
        
        best_dist_p = 6
        best_x_p = 0
        for ch, m1, m2, inv, idx1, idx2 in channels:
            period = m1 * m2
            ri = recv_r_p[idx1]
            rj = recv_r_p[idx2]
            diff = (rj + m2 - ri) % m2
            coeff = (diff * inv) % m2
            x_cand_k0 = ri + m1 * coeff
            for k in range(5):
                x_k = x_cand_k0 + k * period
                if x_k > 65535:
                    break
                cand_r = [x_k % m for m in moduli]
                dist = sum(1 for i in range(6) if cand_r[i] != recv_r_p[i])
                if dist < best_dist_p:
                    best_dist_p = dist
                    best_x_p = x_k
        
        if dec_out_t == best_x_p:
            print("  *** ILA output MATCHES previous trial's expected output! ***")
            print("  Previous trial expected: %d" % best_x_p)
    print()

print("="*80)
print("CONCLUSION:")
print("="*80)
print()
print("If ILA dec_out_a matches the PREVIOUS trial's expected MLD output,")
print("this confirms a PIPELINE TIMING BUG: the decoder is outputting")
print("the result for the PREVIOUS trial's input, not the current one.")
print()
print("This would be caused by the decoder receiving the input 1 cycle")
print("LATER than expected, causing the output to be delayed by 1 trial.")
