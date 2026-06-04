# Append all sheets from a source .xlsx after the sheets of a base workbook.
# Uses Excel COM (Windows + Excel installed). Preserves charts/formatting.
#
# Usage:
#   powershell -File append_workbook_sheets.ps1 -Base "path\base.xlsx" -Add "path\add.xlsx" [-Output "path\out.xlsx"]

param(
  [Parameter(Mandatory = $true)][string]$Base,
  [Parameter(Mandatory = $true)][string]$Add,
  [string]$Output
)

$Base = (Resolve-Path $Base).Path
$Add = (Resolve-Path $Add).Path
if (-not $Output) {
  $Output = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($Base),
    [System.IO.Path]::GetFileNameWithoutExtension($Base) + "_merged.xlsx"
  )
}

if (Test-Path $Output) { Remove-Item $Output -Force }
Copy-Item $Base $Output

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$missing = [Type]::Missing

try {
  $wbBase = $excel.Workbooks.Open($Output)
  $wbAdd = $excel.Workbooks.Open($Add)

  Write-Host "Base workbook: $Output"
  Write-Host "  Sheets: $($wbBase.Sheets.Count)"
  for ($i = 1; $i -le $wbAdd.Sheets.Count; $i++) {
    $sh = $wbAdd.Sheets.Item($i)
    $last = $wbBase.Sheets.Item($wbBase.Sheets.Count)
    Write-Host "  Append: $($sh.Name) (after $($last.Name))"
    $sh.Copy($missing, $last)
  }

  $wbBase.Save()
  Write-Host "`nDone: $Output ($($wbBase.Sheets.Count) sheets)"
  for ($j = 1; $j -le $wbBase.Sheets.Count; $j++) {
    Write-Host "  $j. $($wbBase.Sheets.Item($j).Name)"
  }

  $wbAdd.Close($false)
  $wbBase.Close($false)
} finally {
  $excel.Quit()
  [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
  [GC]::Collect()
}
