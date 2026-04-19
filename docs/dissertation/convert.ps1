# convert.ps1
$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    $OutputEncoding = [System.Text.UTF8Encoding]::new()
    Write-Host "Converting Markdown to PDF..." -ForegroundColor Cyan

    # Times New Roman for body text; FandolSong for CJK; Noto Sans Mono for code blocks.
    $headerIncludes = @'
\usepackage{amsmath,amssymb}
\usepackage{bm}
\usepackage{fontspec}
\usepackage{xeCJK}
\usepackage{array}
\usepackage{makecell}
\usepackage[table]{xcolor}
\setlength{\arrayrulewidth}{0.4pt}
\definecolor{TableRuleOuter}{gray}{0.55}
\definecolor{TableRuleLight}{gray}{0.80}
\newcommand{\TableTopRule}{\noalign{\arrayrulecolor{TableRuleOuter}\global\arrayrulewidth=0.8pt}\hline\noalign{\global\arrayrulewidth=0.4pt\arrayrulecolor{TableRuleLight}}}
\newcommand{\TableHeaderRule}{\noalign{\arrayrulecolor{TableRuleOuter}\global\arrayrulewidth=0.65pt}\hline\noalign{\global\arrayrulewidth=0.4pt\arrayrulecolor{TableRuleLight}}}
\newcommand{\TableInnerRule}{\noalign{\arrayrulecolor{TableRuleLight}\global\arrayrulewidth=0.4pt}\hline\noalign{\arrayrulecolor{TableRuleLight}}}
\newcommand{\TableBottomRule}{\noalign{\arrayrulecolor{TableRuleOuter}\global\arrayrulewidth=0.8pt}\hline\noalign{\global\arrayrulewidth=0.4pt\arrayrulecolor{TableRuleOuter}}}
\setmainfont{Times New Roman}
\setCJKmainfont{FandolSong}
\setmonofont{Noto Sans Mono}[Scale=0.85]
'@
    $headerFile = Join-Path $PSScriptRoot "header_fonts.tex"
    [IO.File]::WriteAllText($headerFile, $headerIncludes, [Text.Encoding]::UTF8)

    $pandocLog = Join-Path $PSScriptRoot "pandoc_build.log"
    $texFile = Join-Path $PSScriptRoot "thesis_final.tex"
    $pdfFile = Join-Path $PSScriptRoot "thesis_final.pdf"
    $xelatexLog = Join-Path $PSScriptRoot "xelatex_build.log"

    if (Test-Path $pdfFile) {
        Remove-Item $pdfFile -Force
    }

    pandoc "thesis_v2.md" -o $texFile `
        --from markdown-implicit_figures+tex_math_dollars+raw_tex `
        -V geometry:margin=1.2in `
        -V documentclass=report `
        -V fontsize=12pt `
        -H $headerFile `
        '--resource-path=.;./figure;../high level design' `
        --syntax-highlighting=pygments `
        --metadata lang="en" 2> $pandocLog

    if ($LASTEXITCODE -ne 0 -and -not (Test-Path $texFile)) {
        throw "pandoc exited with code $LASTEXITCODE"
    }

    # Keep TOC generation fully managed by LaTeX to preserve correct ordering and page numbers.
    $tex = [IO.File]::ReadAllText($texFile, [Text.Encoding]::UTF8)
    
    # Post-process tables: thin inner grid lines, thick outer frame.
    $tex = $tex -replace '\\toprule\\noalign\{\}', '\TableTopRule'
    $tex = $tex -replace '\\midrule\\noalign\{\}', '\TableInnerRule'
    $tex = $tex -replace '\\bottomrule\\noalign\{\}', '\TableBottomRule'

    $rx = [regex]::new('\\begin\{longtable\}\[\]\{@\{\}(.*?)@\{\}\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $tex = $rx.Replace($tex, {
        param($m)
        $spec = $m.Groups[1].Value.Trim()

        if ($spec -match '^[lcr]+$') {
            $chars = $spec.ToCharArray() | ForEach-Object { $_.ToString() }
            $spec = ($chars -join '|')
        }
        else {
            # Insert separators only between full column specs (e.g. ...} <next column>),
            # never inside command names like \arraybackslash.
            $spec = [regex]::Replace(
                $spec,
                '}\s*(\r?\n\s*)?(?=>)',
                { param($m)
                    $gap = ''
                    if ($m.Groups[1].Success) {
                        $gap = $m.Groups[1].Value
                    }
                    return "}!{\color{TableRuleLight}\vrule width 0.4pt}$gap"
                }
            )
        }

        return "\arrayrulecolor{TableRuleLight}\begin{longtable}[]{!{\color{black}\vrule width 1pt}$spec!{\color{black}\vrule width 1pt}}"
    })

    $lines = $tex -split "`r?`n"
    $outLines = New-Object System.Collections.Generic.List[string]
    $inLongTable = $false

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match '\\begin\{longtable\}') {
            $inLongTable = $true
        }

        $outLines.Add($line)

        if (-not $inLongTable) {
            continue
        }

        if ($line.TrimEnd() -match '\\\\$') {
            $nextIndex = $i + 1
            while ($nextIndex -lt $lines.Length -and [string]::IsNullOrWhiteSpace($lines[$nextIndex])) {
                $nextIndex++
            }

            if ($nextIndex -lt $lines.Length) {
                $nextLine = $lines[$nextIndex].Trim()
                $shouldInsertInnerRule = @(
                    '\TableInnerRule',
                    '\TableBottomRule',
                    '\endhead',
                    '\endfirsthead',
                    '\endfoot',
                    '\endlastfoot',
                    '\end{longtable}'
                ) -notcontains $nextLine

                if ($shouldInsertInnerRule) {
                    $outLines.Add('\TableInnerRule')
                }
            }
        }

        if ($line -match '^\\end\{longtable\}') {
            $inLongTable = $false
        }
    }

    $tex = ($outLines -join [Environment]::NewLine)
    $tex = [regex]::Replace($tex, '\\TableInnerRule\s*\\endhead', { param($m) "\TableHeaderRule`r`n\endhead" })
    $tex = [regex]::Replace($tex, '\\TableInnerRule\s*\\endfirsthead', { param($m) "\TableHeaderRule`r`n\endfirsthead" })
    $tex = [regex]::Replace(
        $tex,
        '(\\textbf\{Table 4\.1\} Summary of test conditions\.\s*\r?\n\s*\{\\def\\LTcaptype\{none\} % do not increment counter\s*\r?\n)\\arrayrulecolor\{TableRuleLight\}\\begin\{longtable\}\[\]\{.*?\}\s*\r?\n\\TableTopRule',
        {
            param($m)
            $prefix = $m.Groups[1].Value
            $tableStart = '\arrayrulecolor{TableRuleLight}\begin{longtable}[]{!{\color{TableRuleOuter}\vrule width 0.8pt}>{\raggedright\arraybackslash}p{(\linewidth - 2\tabcolsep) * \real{0.1604}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 2\tabcolsep) * \real{0.8396}}!{\color{TableRuleOuter}\vrule width 0.8pt}}'
            return "$prefix$tableStart`r`n\TableTopRule"
        },
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $tex = [regex]::Replace(
        $tex,
        '(\\textbf\{Table 4\.6\} Application scenario recommendations based on the.*?\r?\n.*?\{\\def\\LTcaptype\{none\} % do not increment counter\s*\r?\n)\\arrayrulecolor\{TableRuleLight\}\\begin\{longtable\}\[\]\{.*?\}\s*\r?\n\\TableTopRule',
        {
            param($m)
            $prefix = $m.Groups[1].Value
            $tableStart = '\arrayrulecolor{TableRuleLight}\begin{longtable}[]{!{\color{TableRuleOuter}\vrule width 0.8pt}>{\raggedright\arraybackslash}p{(\linewidth - 6\tabcolsep) * \real{0.2511}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 6\tabcolsep) * \real{0.1614}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 6\tabcolsep) * \real{0.1794}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 6\tabcolsep) * \real{0.4081}}!{\color{TableRuleOuter}\vrule width 0.8pt}}'
            return "$prefix$tableStart`r`n\TableTopRule"
        },
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $tex = [regex]::Replace(
        $tex,
        '(\\textbf\{Table 4\.5\} Consolidated performance comparison of all evaluated.*?\r?\n.*?\{\\def\\LTcaptype\{none\} % do not increment counter\s*\r?\n)\\arrayrulecolor\{TableRuleLight\}\\begin\{longtable\}\[\]\{.*?\}\s*\r?\n\\TableTopRule',
        {
            param($m)
            $prefix = $m.Groups[1].Value
            $tableStart = '\arrayrulecolor{TableRuleLight}\begin{longtable}[]{!{\color{TableRuleOuter}\vrule width 0.8pt}>{\raggedright\arraybackslash}p{(\linewidth - 14\tabcolsep) * \real{0.1290}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 14\tabcolsep) * \real{0.2323}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 14\tabcolsep) * \real{0.1297}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 14\tabcolsep) * \real{0.1348}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 14\tabcolsep) * \real{0.0968}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 14\tabcolsep) * \real{0.0581}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 14\tabcolsep) * \real{0.1161}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 14\tabcolsep) * \real{0.1032}}!{\color{TableRuleOuter}\vrule width 0.8pt}}'
            return "$prefix$tableStart`r`n\TableTopRule"
        },
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $tex = [regex]::Replace(
        $tex,
        '(Appendix A: Algorithm Overview and.*?\r?\n.*?The following table.*?\{\\def\\LTcaptype\{none\} % do not increment counter\s*\r?\n)\\arrayrulecolor\{TableRuleLight\}\\begin\{longtable\}\[\]\{.*?\}\s*\r?\n\\TableTopRule',
        {
            param($m)
            $prefix = $m.Groups[1].Value
            $tableStart = '\arrayrulecolor{TableRuleLight}\begin{longtable}[]{!{\color{TableRuleOuter}\vrule width 0.8pt}>{\raggedright\arraybackslash}p{(\linewidth - 12\tabcolsep) * \real{0.1200}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 12\tabcolsep) * \real{0.2018}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 12\tabcolsep) * \real{0.1126}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 12\tabcolsep) * \real{0.0861}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 12\tabcolsep) * \real{0.1126}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 12\tabcolsep) * \real{0.1651}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 12\tabcolsep) * \real{0.2018}}!{\color{TableRuleOuter}\vrule width 0.8pt}}'
            return "$prefix$tableStart`r`n\TableTopRule"
        },
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $tex = [regex]::Replace(
        $tex,
        '(\\textbf\{Table 3\.1\}.*?Summary of implemented algorithm configurations\.\s*\r?\n.*?\{\\def\\LTcaptype\{none\} % do not increment counter\s*\r?\n)\\arrayrulecolor\{TableRuleLight\}\\begin\{longtable\}\[\]\{.*?\}\s*\r?\n\\TableTopRule',
        {
            param($m)
            $prefix = $m.Groups[1].Value
            $tableStart = '\arrayrulecolor{TableRuleLight}\begin{longtable}[]{!{\color{TableRuleOuter}\vrule width 0.8pt}>{\raggedright\arraybackslash}p{(\linewidth - 8\tabcolsep) * \real{0.1000}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 8\tabcolsep) * \real{0.1815}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 8\tabcolsep) * \real{0.3930}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 8\tabcolsep) * \real{0.1385}}!{\color{TableRuleLight}\vrule width 0.4pt}>{\raggedright\arraybackslash}p{(\linewidth - 8\tabcolsep) * \real{0.1870}}!{\color{TableRuleOuter}\vrule width 0.8pt}}'
            return "$prefix$tableStart`r`n\TableTopRule"
        },
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $tex = $tex -replace '!\{\\color\{black\}\\vrule width 1pt\}', '!{\color{TableRuleOuter}\vrule width 0.8pt}'
    [IO.File]::WriteAllText($texFile, $tex, [Text.Encoding]::UTF8)

    & xelatex -interaction=nonstopmode -file-line-error $texFile *> $xelatexLog
    & xelatex -interaction=nonstopmode -file-line-error $texFile *> $xelatexLog

    if (-not (Test-Path $pdfFile)) {
        throw "XeLaTeX failed to generate thesis_final.pdf"
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Conversion completed with warnings. See xelatex_build.log." -ForegroundColor Yellow
    }
    
    Write-Host "Conversion succeeded." -ForegroundColor Green
    
    # 自动打开生成的PDF
    if (Test-Path $pdfFile) {
        Start-Process $pdfFile
    }
}
catch {
    Write-Host "Conversion failed: $_" -ForegroundColor Red
    exit 1
}