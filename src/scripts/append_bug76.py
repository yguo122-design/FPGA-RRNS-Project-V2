text = """

---

## Bug #76 -- Timing WNS=-0.338ns (timing23.xlsx)

### Problem Description
Implementation still failed timing at 50MHz. WNS = -0.338ns.
Failing paths: mrc_a2_reg[3]/C -> mrc_a3raw_reg[x]/D, High Fanout=68, Net Delay=8.46ns.

### Root Cause
The dont_touch+max_fanout=2 approach (Bug #75) only moved the problem from bit[2] to bit[3].
The fundamental issue is structural: the combinational path
    mrc_a2 -> (mrc_a2 * mrc_mi) -> mod_by_idx_7bit -> s3b_a3raw -> mrc_a3raw
spans too many logic levels for a single 20ns clock cycle.
No amount of register replication can fix a path that is inherently too long.

### Fix: Pipeline Register (v1.5)
Added a new FSM state ST_MRC_S3B (state=13) to register the intermediate product:

    ST_MRC_S3:  mrc_a2 <= s2_a2;                    (register a2)
    ST_MRC_S3B: mrc_a2mi_prod <= mrc_a2 * mrc_mi;   (register product, ~5ns path)
    ST_MRC_S4:  mrc_a3raw <= s3b_a3raw;              (mod+subtract using registered product, ~5ns)

This breaks the long path into two shorter paths:
- Path 1: mrc_a2 -> multiply -> mrc_a2mi_prod (~5ns, well within 20ns)
- Path 2: mrc_a2mi_prod -> mod_by_idx_7bit -> subtract -> mrc_a3raw (~5ns)

New latency: 84 triplets x 11 cycles/triplet = 924 cycles (was 842, +82 cycles, still << 10000 watchdog)

### Modified Files
- src/algo_wrapper/decoder_crrns_mld.v (v1.5, direct edit)
  - Added ST_MRC_S3B = 4'd13 state
  - Added mrc_a2mi_prod register
  - Added s3b_a2mi_mod and s3b_a3raw combinational signals
  - Updated FSM: ST_MRC_S3 -> ST_MRC_S3B -> ST_MRC_S4

### Expected Timing Improvement
- Path 1 (mrc_a2 -> mrc_a2mi_prod): ~5ns (7x7 multiply only)
- Path 2 (mrc_a2mi_prod -> mrc_a3raw): ~5ns (mod + subtract)
- WNS: -0.338ns -> expected > +10ns

### Progress
Resolved (pending re-synthesis verification)

| No | Level | Bug | Root Cause | Fix | Status |
|----|-------|-----|------------|-----|--------|
| 76 | Major | Timing WNS=-0.338ns (timing23) | mrc_a2->multiply->mod->subtract path too long for 1 cycle | Add ST_MRC_S3B pipeline register for a2*mi product | Resolved (pending) |
"""

with open(r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\bug_fix_report_2026_03_22.md', 'a', encoding='utf-8') as f:
    f.write(text)
print('Bug #76 appended to report')
