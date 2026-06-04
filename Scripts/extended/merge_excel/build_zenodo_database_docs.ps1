# Build README companion + Excel data dictionary for the Zenodo/OneDrive database folder.
# Requires Microsoft Excel on Windows.
#
# Usage:
#   powershell -File build_zenodo_database_docs.ps1 -Root "path\to\Bases de datos nuevas"

param(
  [Parameter(Mandatory = $true)][string]$Root
)

$Root = (Resolve-Path -LiteralPath $Root).Path
$outXlsx = Join-Path $Root "SACBAD_data_dictionary.xlsx"
$outReadme = Join-Path $Root "README.txt"

function Format-Bytes([long]$n) {
  if ($n -ge 1GB) { return "{0:N2} GB" -f ($n / 1GB) }
  if ($n -ge 1MB) { return "{0:N2} MB" -f ($n / 1MB) }
  if ($n -ge 1KB) { return "{0:N1} KB" -f ($n / 1KB) }
  "$n B"
}

function Describe-Column([string]$name) {
  if ($name -match '^(Year|Año|Año_Hidrologico|ano|Years|year|month|year_month|n subbasin)$') {
    return "Calendar or hydrological time index."
  }
  if ($name -match 'precipitation.*hydro year') {
    $id = if ($name -match '\(([^)]+)\)') { $Matches[1].Trim() } else { "" }
    return "Annual total precipitation for hydrological year Apr-Mar (mm), sub-basin $id."
  }
  if ($name -match 'precipitation.*calendar year') {
    $id = if ($name -match '\(([^)]+)\)') { $Matches[1].Trim() } else { "" }
    return "Annual total precipitation for calendar year Jan-Dec (mm), sub-basin $id."
  }
  if ($name -match 'Groundwater depth') {
    $id = if ($name -match '\(([^)]+)\)') { $Matches[1].Trim() } else { "" }
    return "Mean groundwater level (m below terrain), sub-basin $id."
  }
  if ($name -match 'Streamflow') {
    $id = if ($name -match '\(([^)]+)\)') { $Matches[1].Trim() } else { "" }
    return "Mean annual streamflow (m3/s), sub-basin $id."
  }
  if ($name -match '^SPI-12') {
    return "Standardized Precipitation Index, 12-month scale (reporting month in column name)."
  }
  if ($name -match '^SPEI-12') {
    return "Standardized Precipitation Evapotranspiration Index, 12-month scale (reporting month in column name)."
  }
  if ($name -match 'temperature') {
    return "Mean annual maximum or minimum temperature (deg C) for the sub-basin in parentheses."
  }
  if ($name -match '^median$|^mean$') { return "Spatial median/mean of pixel-level correlation across the sub-basin mask." }
  if ($name -match 'Percentage_Significant') { return "Share of valid pixels with statistically significant correlation (p threshold from analysis)." }
  if ($name -match 'Count_Pixels') { return "Pixel counts used in NDVI-SPEI correlation statistics." }
  if ($name -match 'NDVI_season|SPEI_index|source_file') { return "Metadata columns identifying NDVI season, SPEI index, and source workbook." }
  if ($name -match '^\d{4}$') { return "Value for calendar/hydrological year $name." }
  if ($name -match 'VIIRS') { return "Night-time lights: area (ha) with positive radiance for sub-basin in header." }
  if ($name -match 'NDWI') { return "Open-water index: inundated area (ha)." }
  if ($name -match 'inlet') { return "Coastal lagoon inlet state: 1=open, -1=closed, NaN=no data." }
  if ($name -match 'SPEI|SPI|NDVI|Well|rights|Catastros|censos') { return "Manuscript figure series variable; see sheet context." }
  "See file/sheet description."
}

function Describe-Tif([string]$fileName) {
  $base = [IO.Path]::GetFileNameWithoutExtension($fileName)
  if ($base -match '_corr_sign$') {
    return "GeoTIFF mask/raster of significant pixel correlations ($base)."
  }
  if ($base -match '_correlation$') {
    return "GeoTIFF of Pearson correlation coefficients, all pixels ($base)."
  }
  if ($base -match '_pvalue$') {
    return "GeoTIFF of two-tailed p-values for correlation ($base)."
  }
  if ($base -match '_(agriculture|forest|shrubland)$') {
    return "Significant correlations restricted to land-cover class $($Matches[1]) ($base)."
  }
  "GeoTIFF raster ($base)."
}

function Parse-TifMeta([string]$fileName) {
  $base = [IO.Path]::GetFileNameWithoutExtension($fileName)
  $ndvi = $null; $spei = $null; $lc = $null; $kind = $null
  if ($base -match '^(NDVI\w+)_(SPEI\w+)') { $ndvi = $Matches[1]; $spei = $Matches[2] }
  if ($base -match '_(agriculture|forest|shrubland)$') { $lc = $Matches[1] }
  if ($base -match 'corr_sign') { $kind = 'significant_mask' }
  elseif ($base -match 'correlation') { $kind = 'correlation' }
  elseif ($base -match 'pvalue') { $kind = 'pvalue' }
  [pscustomobject]@{ NDVI_season = $ndvi; SPEI_index = $spei; Landcover = $lc; Raster_type = $kind }
}

function Get-FileCategory([string]$rel) {
  if ($rel -like 'Input Data\NDVI*') { return 'Input Data / NDVI' }
  if ($rel -like 'Input Data\Correlations*') { return 'Input Data / Correlations' }
  if ($rel -like 'Input Data\*') { return 'Input Data' }
  if ($rel -like 'Processed Data\Paper figures\*') { return 'Processed Data / Paper figures' }
  if ($rel -like 'Processed Data\Supplementary Material figures\*') { return 'Processed Data / Supplementary Material figures' }
  'Other'
}

function Get-FolderDescription([string]$relDir) {
  switch -Wildcard ($relDir) {
    'Input Data' { 'Raw and derived analytical inputs: master timeseries, NDVI stacks, and correlation rasters/tables.' }
    'Input Data\NDVI' { 'Pixel-level NDVI CSV stacks by sub-basin and season (for correlation analysis).' }
    'Input Data\NDVI\NDVI_anual_est_csv' { 'Annual NDVI: one CSV per sub-basin (ID, cell, 1991-2022).' }
    'Input Data\NDVI\NDVI_prim_est_csv' { 'Spring NDVI stacks (when uploaded).' }
    'Input Data\NDVI\NDVI_ver_est_csv' { 'Summer NDVI stacks (when uploaded).' }
    'Input Data\Correlations' { 'Correlation products (tabular and GeoTIFF).' }
    'Input Data\Correlations\Correlations - SPEI - G - Q - VIIRS' { 'SPEI vs groundwater, streamflow, VIIRS (1990-2023).' }
    'Input Data\Correlations\Correlations_NDVI_SPEI' { 'Pixel-wise NDVI-SPEI correlation GeoTIFF stacks.' }
    'Input Data\Correlations\Correlations_NDVI_SPEI\Correlaciones Significativas' { '9 rasters: significant correlations only.' }
    'Input Data\Correlations\Correlations_NDVI_SPEI\Correlaciones Significativas por LC' { '27 rasters: significant correlations by land cover.' }
    'Input Data\Correlations\Correlations_NDVI_SPEI\Todas Correlaciones y Valor P' { '18 rasters: full correlation and p-value grids.' }
    'Processed Data' { 'Publication-ready tables derived from inputs.' }
    'Processed Data\Paper figures' { 'Excel data behind main-text figures and Table 3.' }
    'Processed Data\Supplementary Material figures' { 'Excel data behind supplementary figures.' }
    default { '' }
  }
}

$subbasins = @{
  UQ = "Upper Quilimari"; LQ = "Lower Quilimari"; CQP = "Coastal Quilimari-Petorca"
  UP = "Upper Petorca"; MP = "Middle Petorca"; LP = "Lower Petorca"
  UL = "Upper Ligua"; ML = "Middle Ligua"; LL = "Lower Ligua"; MQ = "Middle Quilimari (Embalse)"
}

$fileInventory = New-Object System.Collections.Generic.List[object]
$workbooks = New-Object System.Collections.Generic.List[object]
$fields = New-Object System.Collections.Generic.List[object]
$geotiff = New-Object System.Collections.Generic.List[object]

Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
  Where-Object { $_.Name -ne 'desktop.ini' -and $_.Name -notin @('README.txt', 'README.md', 'SACBAD_data_dictionary.xlsx') } |
  ForEach-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\')
    $ext = $_.Extension.ToLower()
    $type = switch ($ext) {
      '.xlsx' { 'Excel workbook' }
      '.csv'  { 'CSV table' }
      '.tif'  { 'GeoTIFF raster' }
      default { 'File' }
    }
    $desc = switch -Wildcard ($rel) {
      '*All_annual_timeseries*.xlsx' { 'Master annual database: hydroclimate, NDVI, water rights, VIIRS, NDWI, lagoon inlet, coastal lagoon, figure S1 hydrograph, raw P/Q/G series.' }
      '*NDVI_*anual_est.csv' { 'Annual NDVI pixel stack for one sub-basin (columns: ID, cell, 1991-2022).' }
      '*NDVI_*prim_est.csv' { 'Spring NDVI pixel stack for one sub-basin.' }
      '*NDVI_*ver_est.csv' { 'Summer NDVI pixel stack for one sub-basin.' }
      '*figS1_data.xlsx' { 'Data behind Supplementary Figure S1.' }
      '*figure4_data.xlsx' { 'Data behind Figure 4: key Petorca annual series and monthly lagoon inlet.' }
      '*figure5_data.xlsx' { 'Data behind Figure 5: extended annual indicators and monthly inlet.' }
      '*figure6_data.xlsx' { 'Data behind Figure 6: NDVI/VIIRS/NDWI vs SPI and agricultural census.' }
      '*Table3_data.xlsx' { 'Table 3: NDVI-SPEI correlation summary statistics by sub-basin and land cover.' }
      '*SPEI_G_Q_v_para_analisis.csv' { 'Long-format SPEI/SPI, groundwater, streamflow, VIIRS by sub-basin ID and hydro year (1990-2023).' }
      '*correlacion_IPE*.xlsx' { 'SPEI (IPE) vs groundwater, streamflow, VIIRS correlation tables and synthesis.' }
      '*corr_sign.tif' { (Describe-Tif $_.Name) }
      '*correlation.tif' { (Describe-Tif $_.Name) }
      '*pvalue.tif' { (Describe-Tif $_.Name) }
      '*_agriculture.tif' { (Describe-Tif $_.Name) }
      '*_forest.tif' { (Describe-Tif $_.Name) }
      '*_shrubland.tif' { (Describe-Tif $_.Name) }
      default { $type }
    }
    $fileInventory.Add([pscustomobject]@{
        category      = (Get-FileCategory $rel)
        relative_path = $rel
        file_name     = $_.Name
        format        = $ext.TrimStart('.')
        size          = (Format-Bytes $_.Length)
        last_modified = $_.LastWriteTime.ToString('yyyy-MM-dd')
        description   = $desc
      })
    if ($ext -eq '.tif') {
      $m = Parse-TifMeta $_.Name
      $geotiff.Add([pscustomobject]@{
          relative_path = $rel
          file_name     = $_.Name
          ndvi_season   = $m.NDVI_season
          spei_index    = $m.SPEI_index
          land_cover    = $m.Landcover
          raster_type   = $m.Raster_type
          crs_note      = 'Projected grid aligned to SACBAD NDVI/SPEI stack (see extended analysis scripts).'
          value_note    = 'Floating-point raster; NoData as defined in source GeoTIFF.'
          description   = (Describe-Tif $_.Name)
        })
    }
  }

$folderStructure = New-Object System.Collections.Generic.List[object]
Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force |
  Where-Object { $_.FullName -ne $Root } |
  ForEach-Object {
    $relDir = $_.FullName.Substring($Root.Length).TrimStart('\')
    $nFiles = (Get-ChildItem -LiteralPath $_.FullName -File -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -ne 'desktop.ini' }).Count
    $folderStructure.Add([pscustomobject]@{
        folder_path  = $relDir
        n_files      = $nFiles
        description  = (Get-FolderDescription $relDir)
      })
  } | Out-Null
$folderStructure = $folderStructure | Sort-Object folder_path

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.xlsx' |
  Where-Object { $_.Name -ne 'SACBAD_data_dictionary.xlsx' } |
  ForEach-Object {
    $relFile = $_.FullName.Substring($Root.Length).TrimStart('\')
    $wb = $excel.Workbooks.Open($_.FullName)
    for ($i = 1; $i -le $wb.Sheets.Count; $i++) {
      $ws = $wb.Sheets.Item($i)
      $ur = $ws.UsedRange
      $rows = if ($ur) { $ur.Rows.Count } else { 0 }
      $cols = if ($ur) { $ur.Columns.Count } else { 0 }
      $sheetDesc = switch ($ws.Name) {
        'Hydroclimatic' { 'Annual hydroclimatic indicators 1990-2023 for nine sub-basins (PP hydro/calendar, G, Q, SPI/SPEI, temperature).' }
        'Vegetation NDVI' { 'NDVI by sub-basin, land-cover class, and season (long format with years as columns).' }
        'Water rights' { 'Accumulated surface and groundwater rights by basin/type.' }
        'VIIRS' { 'Annual VIIRS night-time lights area (ha with positive radiance) per sub-basin.' }
        'NDWI' { 'Annual open-water area from NDWI.' }
        'Coastal lagoon Inlet' { 'Monthly lagoon inlet open/closed status.' }
        'Hydroclimatic coastal lagoon' { 'Coastal lagoon zone precipitation and groundwater.' }
        'figS1_data_Hydrograph' { 'Supplementary Figure S1: station-level hydrograph inputs.' }
        'raw_series_pp_q_g' { 'Wide-format annual precipitation, streamflow, and groundwater used for hydrograph.' }
        'Anual_series' { 'Figure 4 annual series.' }
        'Mensual_inlet' { 'Monthly inlet state for figure panels.' }
        'annual_series' { 'Figure 5 annual multi-variable series.' }
        'NDVI_VIIRS_NDWI' { 'Figure 6 vegetation and lights vs drought index.' }
        'AgriculturalCensus' { 'Agricultural cadastre/census counts.' }
        'Table3_all_combined' { 'Stacked Table 3 statistics for all NDVI×SPEI combinations.' }
        { $_ -like 'stats_*' } { "Table 3 subset: $($ws.Name)." }
        'Descripci' { 'Methodological notes for SPEI-G-Q-VIIRS correlations.' }
        'Sintesis' { 'Summary of correlation results.' }
        default { "Worksheet $($ws.Name)." }
      }
      $workbooks.Add([pscustomobject]@{
          file          = $relFile
          sheet         = $ws.Name
          n_rows        = $rows
          n_columns     = $cols
          description   = $sheetDesc
        })
      if ($cols -gt 0 -and $rows -gt 0) {
        for ($c = 1; $c -le $cols; $c++) {
          $nm = [string]$ws.Cells.Item(1, $c).Text
          if ([string]::IsNullOrWhiteSpace($nm)) { continue }
          $fields.Add([pscustomobject]@{
              file        = $relFile
              sheet       = $ws.Name
              field_name  = $nm
              column_index = $c
              description = (Describe-Column $nm)
            })
        }
      }
    }
    $wb.Close($false)
  }

# CSV fields
$csvPath = Get-ChildItem -LiteralPath $Root -Recurse -Filter 'SPEI_G_Q_v_para_analisis.csv' | Select-Object -First 1
if ($csvPath) {
  $relCsv = $csvPath.FullName.Substring($Root.Length).TrimStart('\')
  $header = (Get-Content -LiteralPath $csvPath.FullName -TotalCount 1 -Encoding UTF8) -split ';'
  $i = 0
  foreach ($h in $header) {
    $i++
    $fields.Add([pscustomobject]@{
        file         = $relCsv
        sheet        = '(CSV)'
        field_name   = $h
        column_index = $i
        description  = switch ($h) {
          'ID' { 'Sub-basin code (UQ, LQ, CQP, UP, MP, LP, UL, ML, LL).' }
          'hydro_year' { 'Hydrological year (Apr-Mar), integer.' }
          'SPEI-12 Hydro avg' { 'SPEI-12 aggregated over hydrological year.' }
          'SPEI-12 September' { 'SPEI-12 with accumulation ending September.' }
          'SPEI-12 December' { 'SPEI-12 with accumulation ending December.' }
          'SPEI12anual_est' { 'Z-scored / standardized SPEI annual estimate used in correlations.' }
          'SPEI12sep_est' { 'Z-scored SPEI September variant.' }
          'SPEI12dic_est' { 'Z-scored SPEI December variant.' }
          'G' { 'Groundwater depth or level (raw units from stations).' }
          'Q' { 'Streamflow (raw units).' }
          'G_est' { 'Standardized groundwater series.' }
          'Q_est' { 'Standardized streamflow series.' }
          'VIIRS' { 'VIIRS radiance/area metric (raw).' }
          'VIIRS_est' { 'Standardized VIIRS series.' }
          default { (Describe-Column $h) }
        }
      })
  }
}

$excel.Quit()
[GC]::Collect()

# Write Excel dictionary
$excel2 = New-Object -ComObject Excel.Application
$excel2.Visible = $false
$excel2.DisplayAlerts = $false
if (Test-Path $outXlsx) { Remove-Item -LiteralPath $outXlsx -Force }
$wbOut = $excel2.Workbooks.Add()
$wbOut.Worksheets.Item(1).Name = 'Index'

function Write-DataSheet($wb, $name, $data) {
  $ws = $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
  $ws.Name = $name
  if ($data.Count -eq 0) { return }
  $headers = $data[0].psobject.Properties.Name
  for ($c = 0; $c -lt $headers.Count; $c++) {
    $ws.Cells.Item(1, $c + 1) = $headers[$c]
    $ws.Cells.Item(1, $c + 1).Font.Bold = $true
  }
  for ($r = 0; $r -lt $data.Count; $r++) {
    for ($c = 0; $c -lt $headers.Count; $c++) {
      $ws.Cells.Item($r + 2, $c + 1) = [string]$data[$r].($headers[$c])
    }
  }
  $ws.UsedRange.Columns.AutoFit() | Out-Null
  $ws.Rows.Item(1).AutoFilter() | Out-Null
}

$indexRows = @(
  [pscustomobject]@{
    topic = 'Package'
    item  = 'SACBAD supplementary database (Zenodo)'
    notes = 'Generated by build_zenodo_database_docs.ps1. See README.txt in the same folder.'
  }
  [pscustomobject]@{
    topic = 'Sheets in this workbook'
    item  = 'Subbasin_codes | Folder_structure | File_inventory | Excel_workbooks | Fields | GeoTIFF_rasters'
    notes = 'Use Filters on row 1 to navigate Fields and File_inventory.'
  }
  [pscustomobject]@{
    topic = 'Folder layout'
    item  = 'Input Data/ | Processed Data/Paper figures/ | Processed Data/Supplementary Material figures/'
    notes = 'See sheet Folder_structure and README.txt.'
  }
  [pscustomobject]@{
    topic = 'Time coverage'
    item  = '1990-2023'
    notes = 'Hydrological year Apr-Mar where noted; calendar year otherwise.'
  }
)
$wsIdx = $wbOut.Worksheets.Item('Index')
$wsIdx.Cells.Item(1, 1) = 'topic'; $wsIdx.Cells.Item(1, 2) = 'item'; $wsIdx.Cells.Item(1, 3) = 'notes'
1..3 | ForEach-Object { $wsIdx.Cells.Item(1, $_).Font.Bold = $true }
for ($r = 0; $r -lt $indexRows.Count; $r++) {
  $wsIdx.Cells.Item($r + 2, 1) = $indexRows[$r].topic
  $wsIdx.Cells.Item($r + 2, 2) = $indexRows[$r].item
  $wsIdx.Cells.Item($r + 2, 3) = $indexRows[$r].notes
}
$wsIdx.UsedRange.Columns.AutoFit() | Out-Null

$sbRows = foreach ($k in ($subbasins.Keys | Sort-Object)) {
  [pscustomobject]@{ id = $k; name = $subbasins[$k] }
}
Write-DataSheet $wbOut 'Subbasin_codes' $sbRows
Write-DataSheet $wbOut 'Folder_structure' @($folderStructure)
Write-DataSheet $wbOut 'File_inventory' $fileInventory
Write-DataSheet $wbOut 'Excel_workbooks' $workbooks
Write-DataSheet $wbOut 'Fields' $fields
Write-DataSheet $wbOut 'GeoTIFF_rasters' $geotiff
$wbOut.SaveAs($outXlsx, 51)
$wbOut.Close($false)
$excel2.Quit()
[GC]::Collect()

Write-Host "Wrote: $outXlsx"
Write-Host "Files inventoried: $($fileInventory.Count)"
Write-Host "Field rows: $($fields.Count)"
Write-Host "GeoTIFF rows: $($geotiff.Count)"

$nData = $fileInventory.Count
$nTif = ($fileInventory | Where-Object { $_.format -eq 'tif' }).Count
$totalBytes = (Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
  Where-Object { $_.Name -notin @('desktop.ini', 'SACBAD_data_dictionary.xlsx') }).Length | Measure-Object -Sum | Select-Object -ExpandProperty Sum

$ipeFile = ($fileInventory | Where-Object { $_.file_name -like 'correlacion_IPE*' } | Select-Object -First 1).file_name
if (-not $ipeFile) { $ipeFile = 'correlacion_IPE_G_Q_Viirs_todos_los_anos_2026.xlsx' }

$readme = @"
================================================================================
SACBAD supplementary database (Zenodo)
================================================================================

This folder contains the published data package supporting the SACBAD
manuscript: annual hydroclimatic and land-surface time series, figure-ready
tables, NDVI pixel stacks, and geospatial correlation products for the
Petorca-Quilimari-Ligua basins (central Chile).

Companion file: SACBAD_data_dictionary.xlsx
  Machine-readable inventory, folder map, sheet list, column definitions, and
  GeoTIFF naming guide. Filter sheets File_inventory and Fields in Excel.

Time coverage: 1990-2023
  Hydrological year Apr-Mar where stated; calendar year otherwise.

Sub-basin IDs (see dictionary sheet Subbasin_codes):

  ID    Basin
  --    -----
  UQ    Upper Quilimari
  LQ    Lower Quilimari
  MQ    Middle Quilimari (to Culimo dam)
  CQP   Coastal Quilimari-Petorca
  UP    Upper Petorca
  MP    Middle Petorca
  LP    Lower Petorca
  UL    Upper Ligua
  ML    Middle Ligua
  LL    Lower Ligua


================================================================================
FOLDER MAP
================================================================================

All paths relative to: Bases de datos nuevas/

Bases de datos nuevas/
  README.txt
  SACBAD_data_dictionary.xlsx
  Input Data/
    All_annual_timeseries.xlsx
    NDVI/
      NDVI_anual_est_csv/          (10 CSV, one per sub-basin)
      NDVI_prim_est_csv/           (when uploaded)
      NDVI_ver_est_csv/            (when uploaded)
    Correlations/
      Correlations - SPEI - G - Q - VIIRS/
        $ipeFile
        SPEI_G_Q_v_para_analisis.csv
      Correlations_NDVI_SPEI/
        Correlaciones Significativas/          (9 GeoTIFF)
        Correlaciones Significativas por LC/   (27 GeoTIFF)
        Todas Correlaciones y Valor P/         (18 GeoTIFF)
  Processed Data/
    Paper figures/
      figure4_data.xlsx
      figure5_data.xlsx
      figure6_data.xlsx
      Table3_data.xlsx
    Supplementary Material figures/
      figS1_data.xlsx

GitHub software repo (separate record): SACBAD_github
  Copy Input Data/NDVI/ from this deposit to Input/external/ndvi/ in that repo.

Total: $nData data files ($(Format-Bytes $totalBytes)), including $nTif GeoTIFF rasters.


================================================================================
INPUT DATA
================================================================================

Path: Input Data/

Raw and derived analytical inputs used to build publication tables and
correlation maps.

--------------------------------------------------------------------------------
Input Data/All_annual_timeseries.xlsx
--------------------------------------------------------------------------------
Master workbook for annual indicators and supplementary series.

  Hydroclimatic                 Year; precipitation (hydro + calendar year);
                                groundwater; streamflow; SPI-12; temperature;
                                SPEI-12 for nine sub-basins (1990-2023).

  Vegetation NDVI               NDVI by sub-basin, land cover, season; years
                                as columns (summary table).

  Water rights                  Accumulated surface/groundwater rights.

  VIIRS                         Night-time lights area (ha) per sub-basin.

  NDWI                          Open-water area (ha).

  Coastal lagoon Inlet          Monthly inlet state (open=1, closed=-1).

  Hydroclimatic coastal lagoon  Lagoon-zone precipitation and groundwater.

  figS1_data_Hydrograph         Supplementary Figure S1 hydrograph inputs.

  raw_series_pp_q_g             Wide annual P, Q, G series for hydrograph.


--------------------------------------------------------------------------------
Input Data/NDVI/
--------------------------------------------------------------------------------
Pixel-level NDVI stacks for correlation analysis (not in the GitHub code repo).

  NDVI_anual_est_csv/
      NDVI_CQPanual_est.csv, NDVI_UQanual_est.csv, ... (10 files)
      Columns: ID, cell, 1991-2022 (one row per grid cell).

  NDVI_prim_est_csv/            Spring season (upload when available)
  NDVI_ver_est_csv/             Summer season (upload when available)
  base.tif                      Optional raster template (upload when available)

Copy to Input/external/ndvi/ in SACBAD_github to re-run NDVI-SPEI correlations.


--------------------------------------------------------------------------------
Input Data/Correlations/
--------------------------------------------------------------------------------

Correlations - SPEI - G - Q - VIIRS/
  $ipeFile
      SPEI (IPE) vs groundwater, streamflow, VIIRS - tables and synthesis.
  SPEI_G_Q_v_para_analisis.csv
      Long-format SPEI/SPI, G, Q, VIIRS by sub-basin and hydro year.

Correlations_NDVI_SPEI/
  Correlaciones Significativas/ (9 files)
      {NDVIseason}_{SPEIindex}_corr_sign.tif - significant pixels only.

  Correlaciones Significativas por LC/ (27 files)
      ..._{agriculture|forest|shrubland}.tif - by land cover.

  Todas Correlaciones y Valor P/ (18 files)
      ..._correlation.tif and ..._pvalue.tif — full grids.

NDVI seasons: anual, prim (spring), ver (summer).
SPEI indices: anual, sep (SPEI-12 ending September), dic (ending December).


================================================================================
PROCESSED DATA
================================================================================

Path: Processed Data/Paper figures/

Publication-ready Excel tables for main-text figures and Table 3.

  figure4_data.xlsx     Figure 4 - Petorca climate/hydrology, wells, rights,
                        monthly lagoon inlet.

  figure5_data.xlsx     Figure 5 - extended annual multi-variable series and
                        monthly inlet.

  figure6_data.xlsx     Figure 6 - NDVI, VIIRS, NDWI vs SPI; agricultural
                        census.

  Table3_data.xlsx      Table 3 - NDVI-SPEI correlation summary stats
                        (combined sheet + 9 NDVI x SPEI subsets).

Path: Processed Data/Supplementary Material figures/

  figS1_data.xlsx       Supplementary Figure S1 data.


================================================================================
GeoTIFF notes
================================================================================

- Open in QGIS, R (terra/raster), or Python (rasterio).
- Filename tokens parsed in SACBAD_data_dictionary.xlsx, sheet GeoTIFF_rasters.


================================================================================
Regenerating documentation
================================================================================

  powershell -File "path\to\build_zenodo_database_docs.ps1" -Root "path\to\Bases de datos nuevas"

Requires Windows and Microsoft Excel.


================================================================================
Related repository
================================================================================

Reproducible R pipeline: SACBAD_github (GitHub / Zenodo software record).


================================================================================
Citation
================================================================================

Cite the SACBAD manuscript and this Zenodo deposit once published. Station
data from DGA and DMC (Chile); see manuscript Data Availability.

Generated: $(Get-Date -Format 'yyyy-MM-dd')
"@

Set-Content -LiteralPath $outReadme -Value $readme -Encoding UTF8
Write-Host "Wrote: $outReadme"
