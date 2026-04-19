#!/usr/bin/env python3
import subprocess
import json
import os
import tkinter as tk
from tkinter import messagebox

# 获取当前脚本所在的目录
script_dir = os.path.dirname(os.path.abspath(__file__))

# 构建文件路径
md_file = os.path.join(script_dir, "thesis.md")
template_file = os.path.join(script_dir, "template.tex")
output_file = os.path.join(script_dir, "thesis_final.tex")

# 验证文件是否存在
print("🔍 文件检查：")
print(f"脚本目录: {script_dir}")
print(f"thesis.md 存在: {os.path.exists(md_file)} ({md_file})")
print(f"template.tex 存在: {os.path.exists(template_file)} ({template_file})")

if not os.path.exists(md_file):
    print("❌ 错误: thesis.md 文件不存在！请检查文件名和路径。")
    sys.exit(1)

if not os.path.exists(template_file):
    print("❌ 错误: template.tex 文件不存在！")
    sys.exit(1)

def convert_thesis():
    """执行转换命令"""
    cmd = [
        "pandoc",
        md_file,  # 使用绝对路径
        "-o", output_file,
        "--template", template_file,  # 使用绝对路径
        "--standalone",
        "--toc",
        "--number-sections",
        "--syntax-highlighting=idiomatic",  # 替代已弃用的 --listings
        "--mathjax"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=os.getcwd())
        
        if result.returncode == 0:
            messagebox.showinfo("成功", "✅ 论文转换成功！")
            # 在Obsidian中创建结果笔记
            with open("转换结果.md", "w", encoding="utf-8") as f:
                f.write(f"# 转换结果\n\n命令: `{' '.join(cmd)}`\n\n输出:\n```\n{result.stdout}\n```")
        else:
            messagebox.showerror("错误", f"❌ 转换失败:\n{result.stderr}")
            
    except Exception as e:
        messagebox.showerror("异常", f"执行错误: {str(e)}")

# 创建GUI
root = tk.Tk()
root.title("论文转换工具")
root.geometry("300x150")

label = tk.Label(root, text="论文格式转换工具", font=("Arial", 14))
label.pack(pady=20)

btn = tk.Button(root, text="开始转换", command=convert_thesis, 
                bg="#4CAF50", fg="white", font=("Arial", 12), padx=20, pady=10)
btn.pack()

root.mainloop()