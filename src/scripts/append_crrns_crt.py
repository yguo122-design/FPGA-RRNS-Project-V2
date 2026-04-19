text = """

---

## C-RRNS-CRT 算法实现（2026-03-22 下午）

### 变更说明

实现了 C-RRNS 的第三种解码方案：Chinese Remainder Theorem (CRT)，对应 algo_id=4。

### 算法原理

CRT 使用 3 个非冗余模数 {64, 63, 65} 并行重建原始数据。

CRT 公式：X = (r0*c0 + r1*c1 + r2*c2) mod M

其中 M = 64*63*65 = 262080，预计算常数：
- c0 = 257985  (M0 * Inv(M0, 64) mod M，其中 M0=4095, Inv=63)
- c1 = 133120  (M1 * Inv(M1, 63) mod M，其中 M1=4160, Inv=32)
- c2 = 133056  (M2 * Inv(M2, 65) mod M，其中 M2=4032, Inv=33)

### 新建文件

- src/algo_wrapper/decoder_crrns_crt.v (v1.0, ~170行)
  - 5级流水线FSM，5周期延迟（比MRC的8周期更快）
  - 并行计算三个乘积 t0=r0*c0, t1=r1*c1, t2=r2*c2
  - 仅使用非冗余模数 {64, 63, 65}，冗余模数完全忽略
  - 无纠错能力：非冗余模数出错则解码失败

### 修改文件

- src/algo_wrapper/decoder_wrapper.v — 实例化 decoder_crrns_crt（替换占位符）
- src/interfaces/main_scan_fsm.vh — CURRENT_ALGO_ID 改为 4

### 三种 C-RRNS 解码方案完整对比

| 特性 | C-RRNS-MLD (id=2) | C-RRNS-MRC (id=3) | C-RRNS-CRT (id=4) |
|------|-------------------|-------------------|-------------------|
| 解码延迟 | 924 周期 | 8 周期 | 5 周期 |
| 纠错能力 | t=3（100%） | 无纠错 | 无纠错 |
| 计算方式 | 枚举84组合 | 串行MRC | 并行CRT |
| FPGA 资源 | ~1500 LUT | ~50 LUT | ~80 LUT |
| 冗余模数 | 全部参与 | 完全忽略 | 完全忽略 |

### 算法验证（Python 仿真）

- 无错误：100% PASS
- 非冗余模数出错：100% FAIL（预期行为，CRT 无纠错能力）
- 冗余模数出错：100% PASS（冗余模数不参与解码）

### 状态

已实现，待综合验证（pending re-synthesis）
"""

with open(r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\bug_fix_report_2026_03_22.md', 'a', encoding='utf-8') as f:
    f.write(text)
print('C-RRNS-CRT implementation appended to report')
