text = """

---

## Bug #78 -- C-RRNS-CRT Test Reports Algorithm as 2NRM-RRNS

### Problem Description

When testing C-RRNS-CRT (algo_id=4), the CSV result file shows:
    Algorithm,2NRM-RRNS   (should be C-RRNS-CRT)
    Avg_Clk_Per_Trial,14  (2NRM latency, not CRT's ~7 cycles)

### Root Cause

In main_scan_fsm.v, the algo_id was passed as 2-bit constant:

    .algo_id_in   (2'd`CURRENT_ALGO_ID)   // tx_packet_assembler
    .algo_id      (2'd`CURRENT_ALGO_ID)   // rom_threshold_ctrl

When CURRENT_ALGO_ID=4 (C-RRNS-CRT):
    2'd4 = 4'b0100 truncated to 2'b00 = 0 (2NRM!)

This caused:
1. tx_packet_assembler to report algo_id=0 (2NRM) in the CSV
2. rom_threshold_ctrl to use 2NRM's threshold table (wrong injection probability)

Additionally, the sub-module port widths were also 2-bit:
- tx_packet_assembler.v: algo_id_in [1:0] -> needed [2:0]
- rom_threshold_ctrl.vh: THRESH_ALGO_BITS=2 -> needed 3

### Fix

Changed all 2-bit algo_id references to 3-bit:

| File | Change |
|------|--------|
| src/ctrl/main_scan_fsm.v | 2'd`CURRENT_ALGO_ID -> 3'd`CURRENT_ALGO_ID (2 places) |
| src/verify/tx_packet_assembler.v | algo_id_in [1:0] -> [2:0], algo_id_latch [1:0] -> [2:0] |
| src/interfaces/rom_threshold_ctrl.vh | THRESH_ALGO_BITS 2 -> 3 |

### Progress

Resolved (pending re-synthesis verification)

| No | Level | Bug | Root Cause | Fix | Status |
|----|-------|-----|------------|-----|--------|
| 78 | Major | CRT test reports Algorithm=2NRM-RRNS | 2'd`CURRENT_ALGO_ID truncates id=4 to 0 | Change to 3'd`CURRENT_ALGO_ID, expand port widths | Resolved (pending) |
"""

with open(r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\bug_fix_report_2026_03_22.md', 'a', encoding='utf-8') as f:
    f.write(text)
print('Bug #78 appended to report')
