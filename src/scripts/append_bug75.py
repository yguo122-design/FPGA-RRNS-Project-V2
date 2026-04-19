text = """

---

## Bug #75 -- Timing WNS=-0.614ns (timing22.xlsx)

### Problem Description
Implementation still failed timing at 50MHz. WNS = -0.614ns (worse than timing21!).
Failing paths: mrc_a2_reg[2]/C -> mrc_a3raw_reg[x]_rep/D, High Fanout=80, Net Delay=9.26ns.

### Root Cause
Although max_fanout=4 was applied to mrc_a2 in Bug #74, Vivado continued to replicate
the destination register mrc_a3raw (visible as _rep, _rep__0, _rep__1, _rep__2 suffixes)
rather than the source mrc_a2. The source mrc_a2_reg[2] still had fanout=80.

The max_fanout attribute alone is insufficient when Vivado prefers to replicate the
destination. The dont_touch attribute is needed to prevent Vivado from merging mrc_a2
with other logic, forcing it to replicate the source register instead.

### Fix
Applied dont_touch + max_fanout=2 on mrc_a2 in decoder_crrns_mld.v:

    (* dont_touch = "true", max_fanout = 2 *) reg [6:0] mrc_a2;

- dont_touch prevents Vivado from merging mrc_a2 with other logic
- max_fanout=2 forces ~40 copies (80/2), reducing per-copy fanout to 2
- Expected Net Delay: 9.26ns -> ~1-2ns
- Expected WNS: -0.614ns -> expected > +8ns

### Modified Files
- src/algo_wrapper/decoder_crrns_mld.v (v1.4, direct edit)

### Progress
Resolved (pending re-synthesis verification)

| No | Level | Bug | Root Cause | Fix | Status |
|----|-------|-----|------------|-----|--------|
| 75 | Major | Timing WNS=-0.614ns (timing22) | mrc_a2_reg[2] fanout=80, max_fanout=4 insufficient | dont_touch+max_fanout=2 on mrc_a2 | Resolved (pending) |
"""

with open(r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\bug_fix_report_2026_03_22.md', 'a', encoding='utf-8') as f:
    f.write(text)
print('Bug #75 appended to report')
