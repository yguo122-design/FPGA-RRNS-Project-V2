print("=" * 70)
print(" " * 15 + "FPGA-RRNS项目代码统计总报告")
print("=" * 70)

print("\n【整体项目统计】")
print("-" * 70)

total_files = 110
total_lines = 45030
code_lines = 36295
comment_lines = 5921
blank_lines = 2814

print(f"总文件数: {total_files}")
print(f"总行数: {total_lines:,}")
print(f"代码行数: {code_lines:,}")
print(f"注释行数: {comment_lines:,}")
print(f"空行数: {blank_lines:,}")

if total_lines > 0:
    comment_rate = (comment_lines / total_lines) * 100
    code_rate = (code_lines / total_lines) * 100
    blank_rate = (blank_lines / total_lines) * 100
    
    print(f"\n行数占比:")
    print(f"  代码行占比: {code_rate:.2f}%")
    print(f"  注释行占比: {comment_rate:.2f}%")
    print(f"  空行占比: {blank_rate:.2f}%")

print("\n" + "=" * 70)
print("【各语言详细统计】")
print("=" * 70)

print("\n【Verilog/Verilog-HDL】")
print("-" * 70)
vl_files = 49
vl_lines = 12495
vl_code_lines = 0
vl_comment_lines = 0
vl_blank_lines = 0

# Recalculate Verilog stats
import os
for root, dirs, files in os.walk(r"d:\FPGAproject\FPGA-RRNS-Project-V2\src"):
    if not any(d.startswith('.') for d in dirs):
        for f in files:
            if f.endswith(('.v', '.vh')):
                with open(os.path.join(root, f), encoding='utf-8', errors='ignore') as file:
                    lines = file.readlines()
                    for line in lines:
                        stripped = line.strip()
                        if len(stripped) == 0:
                            vl_blank_lines += 1
                        elif stripped.startswith('%'):
                            vl_comment_lines += 1
                        else:
                            vl_code_lines += 1

print(f"文件数: {vl_files}")
print(f"总行数: {vl_lines:,}")
print(f"代码行数: {vl_code_lines:,}")
print(f"注释行数: {vl_comment_lines:,}")
print(f"空行数: {vl_blank_lines:,}")

if vl_lines > 0:
    comment_rate = (vl_comment_lines / vl_lines) * 100
    code_rate = (vl_code_lines / vl_lines) * 100
    blank_rate = (vl_blank_lines / vl_lines) * 100
    
    print(f"\n行数占比:")
    print(f"  代码行占比: {code_rate:.2f}%")
    print(f"  注释行占比: {comment_rate:.2f}%")
    print(f"  空行占比: {blank_rate:.2f}%")

print("\n【Python】")
print("-" * 70)
py_files = 55
py_lines = 12638
py_code_lines = 0
py_comment_lines = 0
py_blank_lines = 0

# Recalculate Python stats
for root, dirs, files in os.walk(r"d:\FPGAproject\FPGA-RRNS-Project-V2\src"):
    if not any(d.startswith('.') for d in dirs):
        for f in files:
            if f.endswith('.py'):
                with open(os.path.join(root, f), encoding='utf-8', errors='ignore') as file:
                    lines = file.readlines()
                    for line in lines:
                        stripped = line.strip()
                        if len(stripped) == 0:
                            py_blank_lines += 1
                        elif stripped.startswith('#'):
                            py_comment_lines += 1
                        else:
                            py_code_lines += 1

print(f"文件数: {py_files}")
print(f"总行数: {py_lines:,}")
print(f"代码行数: {py_code_lines:,}")
print(f"注释行数: {py_comment_lines:,}")
print(f"空行数: {py_blank_lines:,}")

if py_lines > 0:
    comment_rate = (py_comment_lines / py_lines) * 100
    code_rate = (py_code_lines / py_lines) * 100
    blank_rate = (py_blank_lines / py_lines) * 100
    
    print(f"\n行数占比:")
    print(f"  代码行占比: {code_rate:.2f}%")
    print(f"  注释行占比: {comment_rate:.2f}%")
    print(f"  空行占比: {blank_rate:.2f}%")

print("\n【MATLAB】")
print("-" * 70)
matlab_files = 17
matlab_lines = 1263
matlab_code_lines = 667
matlab_comment_lines = 458
matlab_blank_lines = 138

matlab_code_comment_rate = (matlab_comment_lines / matlab_code_lines) * 100

print(f"文件数: {matlab_files}")
print(f"总行数: {matlab_lines:,}")
print(f"代码行数: {matlab_code_lines:,}")
print(f"注释行数: {matlab_comment_lines:,}")
print(f"空行数: {matlab_blank_lines:,}")

if matlab_lines > 0:
    comment_rate = (matlab_comment_lines / matlab_lines) * 100
    code_rate = (matlab_code_lines / matlab_lines) * 100
    blank_rate = (matlab_blank_lines / matlab_lines) * 100
    
    print(f"\n行数占比:")
    print(f"  代码行占比: {code_rate:.2f}%")
    print(f"  注释行占比: {comment_rate:.2f}%")
    print(f"  空行占比: {blank_rate:.2f}%")

print(f"\n代码注释率: {matlab_code_comment_rate:.2f}%")

print("\n" + "=" * 70)
print("【代码注释率对比】")
print("=" * 70)

print(f"\n  Verilog/Verilog-HDL: {code_rate:.2f}% (基于代码行数)")
print(f"  Python: {code_rate:.2f}% (基于代码行数)")
print(f"  MATLAB: {matlab_code_comment_rate:.2f}% (基于代码行数)")

print("\n" + "=" * 70)
print("【项目评价】")
print("=" * 70)

avg_comment_rate = ((vl_comment_lines + py_comment_lines + matlab_comment_lines) / 
                   (vl_code_lines + py_code_lines + matlab_code_lines)) * 100

print(f"\n平均代码注释率: {avg_comment_rate:.2f}%")
print(f"  - Verilog代码注释率: {comment_rate:.2f}%")
print(f"  - Python代码注释率: {code_rate:.2f}%")
print(f"  - MATLAB代码注释率: {matlab_code_comment_rate:.2f}%")

print("\n项目规模评估:")
print(f"  - 总代码量: {total_lines:,} 行")
print(f"  - 总文件数: {total_files} 个")
print(f"  - 核心语言: Verilog/HDL ({vl_files}个文件), Python ({py_files}个文件), MATLAB ({matlab_files}个文件)")

print("\n代码质量评估:")
if avg_comment_rate >= 15:
    print("  ✓ 代码注释率良好，代码可读性较高")
else:
    print("  ⚠ 代码注释率有待提高")

print("\n" + "=" * 70)
print("报告结束")
print("=" * 70)