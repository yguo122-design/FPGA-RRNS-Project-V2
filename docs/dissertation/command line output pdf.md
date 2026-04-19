pandoc "thesis.md" -o "thesis.pdf" --toc --toc-depth=3  --pdf-engine=xelatex -V geometry:margin=1in

# 修复字符后使用此命令
pandoc "thesis_fixed.md" -o "thesis_final.pdf" `
  --from markdown+tex_math_dollars `
  --toc `
  --toc-depth=3 `
  --number-sections `
  --pdf-engine=xelatex `
  -V geometry:margin=1.2in 
  -V documentclass=report `
  -V fontsize=12pt `
  -V mainfont="Times New Roman" `
  -V 'header-includes:\usepackage{amsmath,amssymb}\usepackage{bm}' `
  --resource-path=.:./images `
  --syntax-highlighting=pygments `
  --metadata lang="en" 

pandoc thesis.md -o thesis.pdf --toc --toc-depth=3  --pdf-engine=xelatex -V geometry:margin=1.2in -V documentclass=report -V fontsize=12pt -V mainfont="Times New Roman" --resource-path=.:./figure --syntax-highlighting=pygments