"""
analyze_2nrm_coverage.py
Analyze whether k=0..4 candidates are sufficient to cover all 16-bit X values
for each of the 15 channel pairs in the 2NRM-RRNS decoder.
"""

MODULI = [257, 256, 61, 59, 55, 53]
pairs = [(i, j) for i in range(6) for j in range(i+1, 6)]

print("Channel pair analysis (max k needed to cover all 16-bit X):")
print(f"{'Pair':<15} {'PERIOD':>8} {'max_k':>6} {'Coverage':>10}  Status")
print("-" * 65)

insufficient = []
for ii, ij in pairs:
    mi = MODULI[ii]
    mj = MODULI[ij]
    period = mi * mj
    max_k = 65535 // period  # Maximum k such that k*period <= 65535
    # With k=0..4, we cover X in [0, 4*period + period - 1] = [0, 5*period - 1]
    coverage_max = min(5 * period - 1, 65535)
    coverage_pct = (coverage_max + 1) / 65536.0 * 100
    flag = "*** INSUFFICIENT ***" if max_k > 4 else "OK"
    if max_k > 4:
        insufficient.append((mi, mj, period, max_k))
    print(f"({mi},{mj}){'':<8} {period:>8d} {max_k:>6d} {coverage_pct:>9.1f}%  {flag}")

print()
if insufficient:
    print(f"INSUFFICIENT pairs ({len(insufficient)}):")
    for mi, mj, period, max_k in insufficient:
        print(f"  ({mi},{mj}): period={period}, need k=0..{max_k}, but FPGA only has k=0..4")
        print(f"  X values NOT covered: {5*period} to 65535 ({65535 - 5*period + 1} values, "
              f"{(65535 - 5*period + 1)/65536*100:.1f}% of range)")
else:
    print("All pairs have sufficient k=0..4 coverage.")

print()
# Estimate impact on SR
# For a random X in [0, 65535], what fraction of X values are NOT covered by any channel?
# A channel (mi, mj) covers X if X < 5*period
# X is NOT covered by channel (mi,mj) if X >= 5*period
# But MLD uses ALL 15 channels - X is correctly decoded if AT LEAST ONE channel
# with correct residues covers X.
# For t=2 errors, at most 2 residues are wrong. The correct channel is one where
# both residues are error-free. With 6 residues and 2 errors, there are C(4,2)=6
# error-free pairs out of C(6,2)=15 total pairs.
# If the correct X is NOT in the range of any error-free channel, decoding fails.

print("Coverage analysis for X values in [0, 65535]:")
total_uncovered = 0
for X in range(65536):
    covered = False
    for ii, ij in pairs:
        mi = MODULI[ii]
        mj = MODULI[ij]
        period = mi * mj
        if X < 5 * period:
            covered = True
            break
    if not covered:
        total_uncovered += 1

print(f"X values NOT covered by ANY channel (k=0..4): {total_uncovered}")
print(f"Percentage: {total_uncovered/65536*100:.2f}%")
print()
print("Note: These X values cannot be decoded correctly by the FPGA decoder,")
print("even with no errors, because no channel's k=0..4 candidates include them.")
