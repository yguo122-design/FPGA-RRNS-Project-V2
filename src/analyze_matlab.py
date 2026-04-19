import os
import re

# Count MATLAB files and analyze comments
matlab_dir = r"d:\FPGAproject\FPGA-RRNS-Project-V2\src\matlab"

total_lines = 0
comment_lines = 0
code_lines = 0
blank_lines = 0
total_files = 0

print("正在分析MATLAB代码统计信息...\n")

for filename in os.listdir(matlab_dir):
    if filename.endswith('.m'):
        filepath = os.path.join(matlab_dir, filename)
        
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        
        file_total = len(lines)
        file_comment = 0
        file_code = 0
        file_blank = 0
        
        for line in lines:
            stripped = line.strip()
            is_blank = len(stripped) == 0
            
            if is_blank:
                file_blank += 1
            else:
                # MATLAB comments start with %
                if stripped.startswith('%'):
                    file_comment += 1
                else:
                    file_code += 1
        
        total_files += 1
        total_lines += file_total
        comment_lines += file_comment
        code_lines += file_code
        blank_lines += file_blank

print("=" * 60)
print("MATLAB代码统计报告")
print("=" * 60)
print(f"\n文件统计:")
print(f"  MATLAB文件数: {total_files}")

print(f"\n行数统计:")
print(f"  总行数: {total_lines:,}")
print(f"  代码行数: {code_lines:,}")
print(f"  注释行数: {comment_lines:,}")
print(f"  空行数: {blank_lines:,}")

if total_lines > 0:
    comment_rate = (comment_lines / total_lines) * 100
    code_rate = (code_lines / total_lines) * 100
    blank_rate = (blank_lines / total_lines) * 100
    
    print(f"\n行数占比:")
    print(f"  代码行占比: {code_rate:.2f}%")
    print(f"  注释行占比: {comment_rate:.2f}%")
    print(f"  空行占比: {blank_rate:.2f}%")
    
    if code_lines > 0:
        code_comment_rate = (comment_lines / code_lines) * 100
        print(f"\n代码注释率: {code_comment_rate:.2f}%")

print("\n" + "=" * 60)