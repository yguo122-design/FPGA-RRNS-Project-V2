@echo off
chcp 65001 >nul
echo 正在转换 Markdown 到 LaTeX...
pandoc thesis.md \
  -o thesis_final.tex \
  --template=template.tex \
  --standalone \
  --toc \
  --number-sections \
  --listings
if %errorlevel% equ 0 (
    echo 转换成功！
) else (
    echo 转换失败，请检查 Pandoc 是否安装
)
pause