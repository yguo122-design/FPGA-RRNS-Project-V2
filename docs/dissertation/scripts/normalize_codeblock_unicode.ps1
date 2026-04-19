$path = "D:\FPGAproject\FPGA-RRNS-Project-V2\docs\dissertation\thesis.md"
$lines = Get-Content -LiteralPath $path -Encoding UTF8
$inCode = $false

$subs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$map = @(
  @(0x2500,'-'), @(0x2208,'in'), @(0x2190,'<-'), @(0x2192,'->'), @(0x2264,'<='), @(0x2265,'>='),
  @(0x00D7,'*'), @(0x2212,'-'), @(0x2248,'~='), @(0x2261,'=='), @(0x2295,'xor'),
  @(0x2080,'0'), @(0x2081,'1'), @(0x2082,'2'), @(0x2083,'3'), @(0x2084,'4'), @(0x2085,'5'),
  @(0x2086,'6'), @(0x2087,'7'), @(0x2088,'8'), @(0x2089,'9'), @(0x1D62,'i'), @(0x2C7C,'j'), @(0x2096,'k'),
  @(0x2070,'0'), @(0x00B9,'1'), @(0x00B2,'2'), @(0x00B3,'3'), @(0x2074,'4'), @(0x2075,'5'),
  @(0x2076,'6'), @(0x2077,'7'), @(0x2078,'8'), @(0x2079,'9'), @(0x207B,'-'), @(0x2071,'i'), @(0x02B2,'j')
)

foreach ($pair in $map) {
  $subs.Add([char]$pair[0], [string]$pair[1])
}

$changed = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  if ($line.Trim() -eq '```') {
    $inCode = -not $inCode
    continue
  }

  if ($inCode) {
    $newLine = $line
    foreach ($k in $subs.Keys) {
      $newLine = $newLine.Replace($k, $subs[$k])
    }

    if ($newLine -ne $line) {
      $lines[$i] = $newLine
      $changed++
    }
  }
}

if ($changed -gt 0) {
  Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
}

"ChangedCodeLines=$changed"
