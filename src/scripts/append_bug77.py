text = """

---

## Bug #77 -- error_lut ROM Address Mapping: CRT (id=4) Maps to Wrong W_valid Slot

### Problem Description

C-RRNS-CRT (algo_id=4) showed 100% success rate while C-RRNS-MRC (algo_id=3) showed
low success rate, even though both algorithms are mathematically equivalent and should
have the same success rate (low, since neither can correct errors).

### Root Cause

The error_injector_unit uses only algo_id[1:0] (2-bit) for the error_lut ROM address:

    rom_addr = {algo_id[1:0], len_idx[3:0], offset[5:0]}  // 12-bit

This means:
- algo_id=3 (MRC): algo_id[1:0]=2'b11 -> slot 3 (W_valid=61) CORRECT
- algo_id=4 (CRT): algo_id[1:0]=2'b00 -> slot 0 (W_valid=41) WRONG!

For CRT (id=4), errors were only injected in bits 0..40 (W_valid=41 from 2NRM slot).
The C-RRNS codeword layout has non-redundant moduli at bits [60:42], which are
OUTSIDE the 0..40 range. So CRT never received errors in its non-redundant moduli,
resulting in 100% success rate (accidental, not real correction ability).

### Fix

Expanded error_lut ROM address from 12-bit to 13-bit:

    rom_addr = {algo_id[2:0], len_idx[3:0], offset[5:0]}  // 13-bit (was 12-bit)

New ROM depth: 2^13 = 8192 (was 4096).
All 6 algo_ids now have their own correct W_valid slot.

### Modified Files

| File | Change |
|------|--------|
| src/interfaces/error_injector_unit.vh | INJ_ROM_ADDR_WIDTH 12->13, INJ_ROM_DEPTH 4096->8192 |
| src/ctrl/error_injector_unit.sv | Comment updated; addr width auto-adapts via macros |
| src/PCpython/gen_rom.py | Remove id<=3 filter, use all 6 algo slots, depth 8192 |
| src/ROM/error_lut.coe | Regenerated (depth 8192) |

### Expected Result After Fix

Both C-RRNS-MRC and C-RRNS-CRT should show similar (low) success rates,
since both algorithms cannot correct errors in non-redundant moduli.

### Progress

Resolved (pending re-synthesis verification)

| No | Level | Bug | Root Cause | Fix | Status |
|----|-------|-----|------------|-----|--------|
| 77 | Major | CRT 100% success (wrong), MRC low success (correct) | error_lut uses algo_id[1:0], CRT(id=4) maps to 2NRM slot (W_valid=41) | Expand error_lut to 13-bit address (8192 depth) | Resolved (pending) |
"""

with open(r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\bug_fix_report_2026_03_22.md', 'a', encoding='utf-8') as f:
    f.write(text)
print('Bug #77 appended to report')
