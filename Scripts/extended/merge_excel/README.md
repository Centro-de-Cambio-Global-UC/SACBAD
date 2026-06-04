# Excel consolidation (Hydroclimatic)

Merges colleague **All_annual_timeseries** with **sacbad_timeseries** Hydroclimatic updates.

**Note:** Excel workbooks are **not** versioned in Git (`Input/extended/merge_excel/*.xlsx` is gitignored). Pass absolute paths to the scripts, or use the Zenodo staging folder on OneDrive.

## What it does

1. **Verification** (report CSV next to output):
   - Compares precipitation in All_annual (`Annual precipitation (mm)`) vs sacbad (`Annual precipitation hydro/calendar (mm)`).
   - Compares **SPI-12 September / December** (same column names in both files).
2. **Merge** (Hydroclimatic sheet only):
   - Renames All_annual PP to **`Annual precipitation hydro year (mm) (ID)`**.
   - Adds sacbad **`Annual precipitation calendar year (mm) (ID)`** (9 sub-basins).
   - Adds mean max/min temperature, **SPEI-12 September**, **SPEI-12 December**.
   - Rows limited to **Year ≤ 2023** (no 2024).
3. **Workbook**: **Hydroclimatic** is the **first** sheet; other sheets copied from All_annual (also truncated to 2023 where they have Year).

## Usage

From repository root:

```bash
Rscript Scripts/extended/merge_excel/consolidate_hydroclimatic.R \
  "path/All_annual timeseries (1).xlsx" \
  "path/sacbad_timeseries_anual_1990_2024 (2).xlsx" \
  "path/All_annual_timeseries_consolidated.xlsx"
```

If precipitation verification fails but you still want the merge (e.g. known definition mismatch):

```bash
... --force
```

## Append sheets (pp / streamflow / groundwater)

Copies **all sheets** from a second workbook **after** the last sheet of the base file (charts and layout preserved). Requires Excel on Windows:

```powershell
powershell -File Scripts/extended/merge_excel/append_workbook_sheets.ps1 `
  -Base "Downloads/All_annual_timeseries_v2.xlsx" `
  -Add "Downloads/pp_streamflow_groundwater.xlsx" `
  -Output "Downloads/All_annual_timeseries_v2_merged.xlsx"
```

## Zenodo database documentation

After uploading the OneDrive/Zenodo folder, generate `README.txt` and `SACBAD_data_dictionary.xlsx`:

```powershell
powershell -File Scripts/extended/merge_excel/build_zenodo_database_docs.ps1 `
  -Root "path\to\Bases de datos nuevas"
```

## Note on .xlsx format

`.xlsx` files are standard Excel workbooks (Office Open XML). They are not “manually zipped” archives for editing; Excel opens them directly. Internally they use ZIP compression (magic bytes `PK`), which is normal.
