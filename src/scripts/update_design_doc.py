"""
update_design_doc.py
Update "FPGA project high level design.md" to reflect the BER scan range change:
  Old: 91 points, BER 0.01~0.10, step 0.001
  New: 101 points, BER 0.000~0.100, step 0.001 (added BER=0 baseline)

Key changes:
  - 91 points → 101 points
  - BER range: 0.01~0.10 → 0.000~0.100
  - Frame length: 2011 → 2231 bytes
  - Length field: 2005/0x07D5 → 2225/0x08B1
  - Per-point data total: 91×22=2002 → 101×22=2222 bytes
  - ROM depth: 5460 → 6060
  - BER_Index range: 0~90 → 0~100
  - BER formula: 0.01 + index×0.001 → index×0.001
  - Address formula: Algo×91×15 → Algo×101×15
"""

import re

filepath = 'd:/FPGAproject/FPGA-RRNS-Project-V2/docs/FPGA project high level design.md'
content = open(filepath, encoding='utf-8').read()

replacements = [
    # ── 点数 91 → 101 ──────────────────────────────────────────────────────
    ('91 点循环扫描', '101 点循环扫描'),
    ('91 个测试点', '101 个测试点'),
    ('91 个点全部完成', '101 个点全部完成'),
    ('91 个点全部测试完毕', '101 个点全部测试完毕'),
    ('91 个 BER 点', '101 个 BER 点'),
    ('91 个点的完整数据', '101 个点的完整数据'),
    ('91 个点的数据', '101 个点的数据'),
    ('91 个点详情', '101 个点详情'),
    ('91 个点 的完整统计数据', '101 个点 的完整统计数据'),
    ('全部 91 个点', '全部 101 个点'),
    ('91 个 BER 测试点', '101 个 BER 测试点'),
    ('91 个不同误码率测试点', '101 个不同误码率测试点'),
    ('91 个 BER 点 ($10^{-2}', '101 个 BER 点 ($0 \\sim 10^{-1}'),
    ('91 个 BER 点 ($10^{-2} \\sim 10^{-1}$, step $10^{-3}$)', '101 个 BER 点 ($0 \\sim 10^{-1}$, step $10^{-3}$)'),
    ('91 点扫描周期', '101 点扫描周期'),
    ('91 点 BER 全自动扫描', '101 点 BER 全自动扫描'),
    ('91 点 BER 扫描', '101 点 BER 扫描'),
    ('全量程 BER 扫描（91 个点）', '全量程 BER 扫描（101 个点）'),
    ('91 组统计数据', '101 组统计数据'),
    ('91 点测试', '101 点测试'),
    ('91 个点）', '101 个点）'),
    ('91 个点，', '101 个点，'),
    ('91 个点后', '101 个点后'),
    ('91 个点时', '101 个点时'),
    ('91 个点 的', '101 个点 的'),
    ('91 个点\n', '101 个点\n'),
    ('91 个点。', '101 个点。'),
    ('91 个点，', '101 个点，'),
    ('91 个点 (', '101 个点 ('),
    ('91 个点)', '101 个点)'),
    ('91 个点:', '101 个点:'),
    ('91 个点：', '101 个点：'),
    ('91 个点 ', '101 个点 '),
    ('91 个点\r', '101 个点\r'),
    # 离线计算
    ('离线计算 91点×4算法×15突发长度 的阈值表', '离线计算 101点×4算法×15突发长度 的阈值表'),
    # 总测试次数
    ('总测试次数 = `cfg_sample_count` × 91', '总测试次数 = `cfg_sample_count` × 101'),
    # 重复直到
    ('重复直到 `ber_index` == 91', '重复直到 `ber_index` == 101'),
    # FSM 状态机图
    ('NEXT_BER : BER_Idx < 91', 'NEXT_BER : BER_Idx < 101'),
    ('NEXT_BER --> SEND_REPORT : BER_Idx == 91', 'NEXT_BER --> SEND_REPORT : BER_Idx == 101'),
    # BER_Index 范围
    ('BER_Index`: 0~90', 'BER_Index`: 0~100'),
    ('当前点索引 (0~90)', '当前点索引 (0~100)'),
    ('BER 点索引 (0~90)', 'BER 点索引 (0~100)'),
    ('BER_Index (0~90)', 'BER_Index (0~100)'),
    # ── BER 范围描述 ────────────────────────────────────────────────────────
    ('BER 0.01~0.10', 'BER 0.000~0.100'),
    ('BER 1%~10%', 'BER 0%~10%'),
    ('从1%~10%，步长为0.1%', '从0%~10%，步长为0.1%（含BER=0基线点）'),
    ('$10^{-2} \\sim 10^{-1}$', '$0 \\sim 10^{-1}$'),
    ('$10^{-2} \\sim 10^{-4}$', '$0 \\sim 10^{-1}$'),
    # BER 公式
    ('BER_{target} = 0.01 + (index \\times 0.001)', 'BER_{target} = index \\times 0.001'),
    # ── 帧长 2011 → 2231 ────────────────────────────────────────────────────
    ('固定 **2011 Bytes**', '固定 **2231 Bytes**'),
    ('固定长度阻塞接收 (Read 2011 Bytes )', '固定长度阻塞接收 (Read 2231 Bytes )'),
    ('约 **1.5KB** 的完整响应帧', '约 **2.2KB** 的完整响应帧'),
    ('鉴于上行帧长度为 **2011 Bytes**', '鉴于上行帧长度为 **2231 Bytes**'),
    ('配置波特率 (推荐高速率 **921600**或**115200**，以缩短 2011 Bytes 大数据帧的传输时间)',
     '配置波特率 (推荐高速率 **921600**或**115200**，以缩短 2231 Bytes 大数据帧的传输时间)'),
    ('**帧总长度**：2011 Bytes (当测试 91 个 BER 点时：Total Frame Length = Fixed_Header + Per_Point_Data_Total + Checksum = 8 Bytes + 91 * 22 Bytes + 1 Byte = 2011 Bytes',
     '**帧总长度**：2231 Bytes (当测试 101 个 BER 点时：Total Frame Length = Fixed_Header + Per_Point_Data_Total + Checksum = 8 Bytes + 101 * 22 Bytes + 1 Byte = 2231 Bytes'),
    ('**Total Frame Size**: $2(\\text{Header}) + 1(\\text{CmdID}) + 2(\\text{Length}) + 3(\\text{GlobalInfo}) + 91 \\times 22(\\text{PerPoint}) + 1(\\text{Checksum}) = \\mathbf{2011}$ Bytes',
     '**Total Frame Size**: $2(\\text{Header}) + 1(\\text{CmdID}) + 2(\\text{Length}) + 3(\\text{GlobalInfo}) + 101 \\times 22(\\text{PerPoint}) + 1(\\text{Checksum}) = \\mathbf{2231}$ Bytes'),
    ('帧长由 2011 Bytes 微调至 **2011 Bytes** (91 points × 22 Bytes + Header/Checksum)',
     '帧长由 2011 Bytes 更新至 **2231 Bytes** (101 points × 22 Bytes + Header/Checksum)'),
    ('协议优化**：明确上行链路帧结构，计算并确认精简版帧长为 2011 Bytes（91 点测试）',
     '协议优化**：明确上行链路帧结构，计算并确认精简版帧长为 2231 Bytes（101 点测试）'),
    ('robust 2011-byte frame transmission', 'robust 2231-byte frame transmission'),
    ('output reg         done,          // Pulse when 2011 bytes sent',
     'output reg         done,          // Pulse when 2231 bytes sent'),
    # ── Length 字段 2005/0x07D5 → 2225/0x08B1 ──────────────────────────────
    ('**Length**: 2 Bytes (**2005** = `0x07D5`，即 Payload 长度 = GlobalInfo(3) + PerPointData(91×22=2002) = 2005 Bytes，**不含** Checksum)',
     '**Length**: 2 Bytes (**2225** = `0x08B1`，即 Payload 长度 = GlobalInfo(3) + PerPointData(101×22=2222) = 2225 Bytes，**不含** Checksum)'),
    ('**Length 字段值**：固定为 **2005** (`0x077A`)',
     '**Length 字段值**：固定为 **2225** (`0x08B1`)'),
    ('**Length 字段值**：固定为 **2005** (`0x07D5`)',
     '**Length 字段值**：固定为 **2225** (`0x08B1`)'),
    ('Length 字段值为 **2005 (0x07D5)**，每点 **22 Bytes**，总帧长公式为 `2+1+2+3+(91×22)+1 = 2011 Bytes`',
     'Length 字段值为 **2225 (0x08B1)**，每点 **22 Bytes**，总帧长公式为 `2+1+2+3+(101×22)+1 = 2231 Bytes`'),
    # ── Per-point data total ─────────────────────────────────────────────────
    ('Per-Point Data**: $91 \\times 22 = 2002$ Bytes', 'Per-Point Data**: $101 \\times 22 = 2222$ Bytes'),
    ('Per-Point Data: $91 \\times 22 = 2002$ Bytes', 'Per-Point Data: $101 \\times 22 = 2222$ Bytes'),
    ('PerPointData(91×22=2002)', 'PerPointData(101×22=2222)'),
    ('91×22=2002', '101×22=2222'),
    ('91 * 22 Bytes', '101 * 22 Bytes'),
    ('91 × 22 Bytes', '101 × 22 Bytes'),
    ('91×22', '101×22'),
    ('$91 \\times 22$', '$101 \\times 22$'),
    ('2002 Bytes 的专用 Block RAM', '2222 Bytes 的专用 Block RAM'),
    ('规划 **2002 Bytes**', '规划 **2222 Bytes**'),
    ('Constraint: Must be mapped to Block RAM (size = 91 * 22 = 2002 Bytes)',
     'Constraint: Must be mapped to Block RAM (size = 101 * 22 = 2222 Bytes)'),
    # ── ROM 深度 5460 → 6060 ─────────────────────────────────────────────────
    ('**表深度 (Depth)**: $4 \\times 91 \\times 15 = 5460$ 个条目', '**表深度 (Depth)**: $4 \\times 101 \\times 15 = 6060$ 个条目'),
    ('$\\text{Addr} = (\\text{Algo} \\times 91 \\times 15) + (\\text{BER\\_Index} \\times 15) + (\\text{Burst\\_Len} - 1)$',
     '$\\text{Addr} = (\\text{Algo} \\times 101 \\times 15) + (\\text{BER\\_Index} \\times 15) + (\\text{Burst\\_Len} - 1)$'),
    # ── 总存储需求 ────────────────────────────────────────────────────────────
    ('**总存储需求**：$91 \\times 21 \\text{ Bytes} = 1911 \\text{ Bytes}$', '**总存储需求**：$101 \\times 22 \\text{ Bytes} = 2222 \\text{ Bytes}$'),
    # ── 上行帧描述 ────────────────────────────────────────────────────────────
    ('包含 91 个 BER 点 的完整统计数据', '包含 101 个 BER 点 的完整统计数据'),
    # ── 旧方案描述 ────────────────────────────────────────────────────────────
    ('FPGA 独立跑完全部 91 个 BER 点 ($10^{-2} \\sim 10^{-4}$)',
     'FPGA 独立跑完全部 101 个 BER 点 ($0 \\sim 10^{-1}$)'),
    # ── 修改历史记录 ──────────────────────────────────────────────────────────
    ('修改了 BER 扫描范围（如从 1%~10% 改为 0.1%~10%）',
     '修改了 BER 扫描范围（如从 0%~10% 改为其他范围）'),
]

count = 0
for old, new in replacements:
    if old in content:
        content = content.replace(old, new)
        count += 1
        print(f'[OK] Replaced: {old[:60]}...' if len(old) > 60 else f'[OK] Replaced: {old}')
    else:
        # Try without extra spaces
        pass

# Also handle numeric-only patterns with regex
import re

# 91 个点 (standalone number)
patterns = [
    (r'\b91\b 个点', '101 个点'),
    (r'91 点', '101 点'),
    (r'BER_Idx < 91\b', 'BER_Idx < 101'),
    (r'BER_Idx == 91\b', 'BER_Idx == 101'),
    (r'ber_index.*== 91\b', lambda m: m.group(0).replace('91', '101')),
]

for pattern, replacement in patterns:
    if callable(replacement):
        new_content = re.sub(pattern, replacement, content)
    else:
        new_content = re.sub(pattern, replacement, content)
    if new_content != content:
        count += 1
        content = new_content

open(filepath, 'w', encoding='utf-8').write(content)
print(f'\nTotal replacements: {count}')
print('File saved.')

# Verify remaining 91 occurrences (should only be in comments/history)
remaining = [(i+1, line.strip()) for i, line in enumerate(content.split('\n'))
             if '91' in line and not line.strip().startswith('#') and not line.strip().startswith('//')]
print(f'\nRemaining lines with "91" ({len(remaining)} total):')
for lineno, line in remaining[:20]:
    print(f'  Line {lineno}: {line[:100]}')
