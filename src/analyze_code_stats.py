import os
import re

# Define extensions to count
EXTENSIONS = ['.v', '.vh', '.sv', '.py', '.c', '.coe', '.md']

# Counters
total_files = 0
total_lines = 0
comment_lines = 0
code_lines = 0
blank_lines = 0

# Comment patterns for different languages
COMMENT_PATTERNS = {
    # Verilog
    'verilog': [
        r'^\s*//.*$',
        r'^\s*/\*.*\*/$',
    ],
    # SystemVerilog
    'systemverilog': [
        r'^\s*//.*$',
        r'^\s*/\*.*\*/$',
    ],
    # Python
    'python': [
        r'^\s*#.*$',
    ],
    # C
    'c': [
        r'^\s*//.*$',
        r'^\s*/\*.*\*/$',
    ],
    # COE (Intel FPGA ROM file)
    'coe': [
        r'^\s*#.*$',
    ],
}

def count_lines_in_file(filepath):
    """Count lines in a file and categorize them."""
    global total_lines, comment_lines, code_lines, blank_lines, total_files
    
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    file_total = len(lines)
    file_comment = 0
    file_code = 0
    file_blank = 0
    
    lang = None
    if filepath.endswith('.v') or filepath.endswith('.vh'):
        lang = 'verilog'
    elif filepath.endswith('.sv'):
        lang = 'systemverilog'
    elif filepath.endswith('.py'):
        lang = 'python'
    elif filepath.endswith('.c'):
        lang = 'c'
    elif filepath.endswith('.coe'):
        lang = 'coe'
    
    patterns = COMMENT_PATTERNS.get(lang, [])
    
    for line in lines:
        stripped = line.strip()
        is_blank = len(stripped) == 0
        
        if is_blank:
            file_blank += 1
        else:
            is_comment = False
            for pattern in patterns:
                if re.match(pattern, line, re.MULTILINE):
                    is_comment = True
                    break
            
            if is_comment:
                file_comment += 1
            else:
                file_code += 1
    
    total_files += 1
    total_lines += file_total
    comment_lines += file_comment
    code_lines += file_code
    blank_lines += file_blank
    
    return file_total, file_comment, file_code, file_blank

def analyze_project(root_dir):
    """Analyze the entire project directory."""
    global total_files, total_lines, comment_lines, code_lines, blank_lines
    
    # Reset counters
    total_files = 0
    total_lines = 0
    comment_lines = 0
    code_lines = 0
    blank_lines = 0
    
    for root, dirs, files in os.walk(root_dir):
        # Skip hidden directories
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        for filename in files:
            ext = os.path.splitext(filename)[1].lower()
            if ext in EXTENSIONS:
                filepath = os.path.join(root, filename)
                count_lines_in_file(filepath)

if __name__ == "__main__":
    project_dir = r"d:\FPGAproject\FPGA-RRNS-Project-V2\src"
    
    print("正在分析项目代码统计信息...\n")
    
    analyze_project(project_dir)
    
    print("=" * 60)
    print("项目代码统计报告")
    print("=" * 60)
    print(f"\n文件统计:")
    print(f"  总文件数: {total_files}")
    print(f"  源代码文件数: {total_files} (包含 .v, .vh, .sv, .py, .c, .coe)")
    
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
    
    # Count by language
    print(f"\n语言统计:")
    
    # Count Verilog files
    vl_files = 0
    vl_lines = 0
    for root, dirs, files in os.walk(project_dir):
        for f in files:
            if f.endswith(('.v', '.vh')):
                vl_files += 1
                vl_lines += len(open(os.path.join(root, f), encoding='utf-8', errors='ignore').readlines())
    
    print(f"  Verilog/Verilog-HDL文件: {vl_files} 个, 共 {vl_lines:,} 行")
    
    # Count Python files
    py_files = 0
    py_lines = 0
    for root, dirs, files in os.walk(project_dir):
        for f in files:
            if f.endswith('.py'):
                py_files += 1
                py_lines += len(open(os.path.join(root, f), encoding='utf-8', errors='ignore').readlines())
    
    print(f"  Python文件: {py_files} 个, 共 {py_lines:,} 行")
    
    print("\n" + "=" * 60)