"""
update_hld.py
Updates docs/FPGA project high level design.md to reflect the C-RRNS algorithm
expansion from single C-RRNS to three variants: C-RRNS-MLD, C-RRNS-MRC, C-RRNS-CRT.
Also extends algo_id from 2-bit to 3-bit throughout the document.
"""

doc_path = r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\FPGA project high level design.md'

with open(doc_path, 'r', encoding='utf-8') as f:
    content = f.read()

changes = 0

# Update 1: Algo_Type user input description
old = '`Algo_Type`: 算法选择 (0: 2NRM-RRNS, 1:3NRM-RRNS,  2: C-RRNS, 3: RS)。'
new = '`Algo_Type`: 算法选择 (0: 2NRM-RRNS, 1: 3NRM-RRNS, 2: C-RRNS-MLD, 3: C-RRNS-MRC, 4: C-RRNS-CRT, 5: RS)。'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 1: Algo_Type description')
else:
    print(f'[SKIP] Update 1: not found')

# Update 2: cfg_algo_ID in downlink frame table
old = '| **5**       | `cfg_algo_ID`      | 1 Byte   | Uint8  | 算法 ID (0:2NRM, 1:3NRM, 2:C-RRNS, 3:RS)                           |'
new = '| **5**       | `cfg_algo_ID`      | 1 Byte   | Uint8  | 算法 ID (0:2NRM, 1:3NRM, 2:C-RRNS-MLD, 3:C-RRNS-MRC, 4:C-RRNS-CRT, 5:RS) |'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 2: cfg_algo_ID table')
else:
    print(f'[SKIP] Update 2: not found')

# Update 3: auto_scan_engine algo_id interface
old = '| `input` | `algo_id` | 2 | Constant | **算法选择ID**。虽为输入，但在单算法编译策略下由顶层固定传入 (`CURRENT_ALGO_ID`)。`0`: 2NRM, `1`: 3NRM, `2`: C-RRNS, `3`: RS |'
new = '| `input` | `algo_id` | 3 | Constant | **算法选择ID（3-bit）**。由顶层固定传入 (`CURRENT_ALGO_ID`)。`0`: 2NRM, `1`: 3NRM, `2`: C-RRNS-MLD, `3`: C-RRNS-MRC, `4`: C-RRNS-CRT, `5`: RS |'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 3: auto_scan_engine algo_id')
else:
    print(f'[SKIP] Update 3: not found')

# Update 4: decoder_wrapper algo_sel
old = '    input  wire [1:0]  algo_sel,      // 0:RS, 1:C-RRNS, 2:3NRM, 3:2NRM'
new = '    input  wire [2:0]  algo_sel,      // 0:2NRM, 1:3NRM, 2:C-RRNS-MLD, 3:C-RRNS-MRC, 4:C-RRNS-CRT, 5:RS'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 4: decoder_wrapper algo_sel')
else:
    print(f'[SKIP] Update 4: not found')

# Update 5: error_injector_unit algo_id
old = '    input wire [1:0] algo_id,      // 算法选择: 0=RS, 1=C-RRNS, 2=3NRM, 3=2NRM'
new = '    input wire [2:0] algo_id,      // 算法选择: 0=2NRM, 1=3NRM, 2=C-RRNS-MLD, 3=C-RRNS-MRC, 4=C-RRNS-CRT, 5=RS'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 5: error_injector_unit algo_id')
else:
    print(f'[SKIP] Update 5: not found')

# Update 6: ROM threshold table depth
old = '*   **表深度 (Depth)**: $4 \\times 101 \\times 15 = 6060$ 个条目。'
new = '*   **表深度 (Depth)**: $6 \\times 101 \\times 15 = 9090$ 个条目（6种算法：2NRM/3NRM/C-RRNS-MLD/C-RRNS-MRC/C-RRNS-CRT/RS）。'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 6: ROM depth 6060->9090')
else:
    print(f'[SKIP] Update 6: not found')

# Update 7: ALGORITHMS dict in gen_rom.py example
old = """ALGORITHMS = {
    'RS': {'w_valid': 48, 'id': 3},
    'C-RRNS': {'w_valid': 61, 'id': 2},
    '3NRM': {'w_valid': 48, 'id': 1},
    '2NRM': {'w_valid': 41, 'id': 0} # 假设 2NRM 也是 41，请根据实际情况调整
}"""
new = """ALGORITHMS = {
    '2NRM':        {'w_valid': 41, 'id': 0},
    '3NRM':        {'w_valid': 48, 'id': 1},
    'C-RRNS-MLD':  {'w_valid': 61, 'id': 2},  # C-RRNS with MLD decoding
    'C-RRNS-MRC':  {'w_valid': 61, 'id': 3},  # C-RRNS with MRC decoding
    'C-RRNS-CRT':  {'w_valid': 61, 'id': 4},  # C-RRNS with CRT decoding
    'RS':          {'w_valid': 48, 'id': 5},
}"""
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 7: ALGORITHMS dict')
else:
    print(f'[SKIP] Update 7: not found')

# Update 8: W_valid table - C-RRNS row
old = '| C-RRNS | 61 | 6+6+7 + 7×7 = 61 |'
new = '| C-RRNS-MLD | 61 | 6+6+7+7+7+7+7+7+7 = 61（MLD解码，842周期）|\n| C-RRNS-MRC | 61 | 同上（MRC解码，~10周期）|\n| C-RRNS-CRT | 61 | 同上（CRT解码，~5周期）|'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 8: W_valid table C-RRNS row')
else:
    print(f'[SKIP] Update 8: not found')

# Update 9: rom_threshold_ctrl i_algo_id
old = '    input  wire [1:0]  i_algo_id,     // 0~3: RS, C-RRNS, 3NRM, 2NRM'
new = '    input  wire [2:0]  i_algo_id,     // 0~5: 2NRM, 3NRM, C-RRNS-MLD, C-RRNS-MRC, C-RRNS-CRT, RS'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 9: rom_threshold_ctrl i_algo_id')
else:
    print(f'[SKIP] Update 9: not found')

# Update 10: algo_id bit width in address mapping
old = '\t*   **高位 [11:10]**：`algo_id` (2-bit)，区分 4 种编码算法。'
new = '\t*   **高位 [11:10]**：`algo_id[1:0]` (2-bit 用于 error_lut ROM 地址)，区分 4 种基础算法。注意：algo_id 实际为 3-bit（支持 6 种算法），threshold_table 使用完整 algo_id（深度 9090=6×101×15）。'
if old in content:
    content = content.replace(old, new)
    changes += 1
    print(f'[OK] Update 10: algo_id bit width in address mapping')
else:
    print(f'[SKIP] Update 10: not found')

# Add version record at the end
version_record = """

---

## 📝 版本修订记录 - v1.9 (2026-03-22)

**主要变更：C-RRNS 算法扩展为三种解码变体，algo_id 从 2-bit 扩展到 3-bit**

本次更新将原来的单一 C-RRNS 算法（algo_id=2）扩展为三种解码方案：

| 变更项 | 旧值 | 新值 |
|--------|------|------|
| algo_id 位宽 | 2-bit（支持 4 种算法） | 3-bit（支持 8 种算法） |
| C-RRNS 算法 | C-RRNS (id=2) | C-RRNS-MLD (id=2), C-RRNS-MRC (id=3), C-RRNS-CRT (id=4) |
| RS 算法 ID | RS (id=3) | RS (id=5) |
| threshold_table 深度 | 4×101×15=6060 | 6×101×15=9090 |
| error_lut 深度 | 4096（不变） | 4096（不变，使用 algo_id[1:0]） |

**新的 algo_id 映射（3-bit）：**
- 0: 2NRM-RRNS
- 1: 3NRM-RRNS
- 2: C-RRNS-MLD（Maximum Likelihood Decoding，842周期，已验证）
- 3: C-RRNS-MRC（Mixed Radix Conversion，~10周期，待实现）
- 4: C-RRNS-CRT（Chinese Remainder Theorem，~5周期，待实现）
- 5: RS（预留）

**编码器说明：** C-RRNS 三种变体共用同一个编码器 `encoder_crrns.v`（61-bit 码字），仅解码器不同。

**修改文件：** decoder_wrapper.vh, decoder_wrapper.v, encoder_wrapper.v, auto_scan_engine.v,
main_scan_fsm.v, error_injector_unit.vh, main_scan_fsm.vh, gen_rom.py, py_controller_main.py,
decoder_crrns_mld.v（新建，从 decoder_crrns.v 重命名）

**状态：** v1.9 Ready for Implementation (C-RRNS-MLD 已验证，MRC/CRT 待实现)
"""

content = content + version_record
changes += 1
print(f'[OK] Added version record v1.9')

with open(doc_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'\nTotal changes applied: {changes}')
print(f'Document updated: {doc_path}')
