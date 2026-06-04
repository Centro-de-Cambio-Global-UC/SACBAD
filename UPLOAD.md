# Publishing to GitHub

## Pre-upload checklist

Run from `SACBAD_github/`:

```powershell
# 1. Confirm NDVI stacks are NOT staged (~3.6 GB belong on Zenodo only)
git check-ignore -v Input/external/ndvi/NDVI_anual_est_csv/NDVI_UQanual_est.csv
git check-ignore -v Input/external/ndvi/README.txt   # should NOT be ignored

# 2. Confirm merge Excel workbooks stay local (Zenodo tooling)
git check-ignore -v Input/extended/merge_excel/All_annual_timeseries.xlsx

# 3. Dry-run: expect ~104 files, ~6 MB total (no Output/, no NDVI CSVs)
git add -n .

# 4. Optional: clean local Output/ junk before archiving the folder
#    (Output/ is gitignored; only Output/.gitkeep is versioned)
```

After `Rscript run_all.R` on a clean machine, verify:

```bash
Rscript Scripts/tests/verify_outputs.R
```

Update `CITATION.cff` (`repository-code`) and Zenodo DOI placeholders before release.

## What to upload

1. Create a new empty repository on GitHub (e.g. `sacbad-hydroclimatic-supplementary`).
2. Upload **only** this folder (`SACBAD_github/`) — not the parent `analisis_series_climaticas/` workspace.
3. Do **not** include:
   - `shiny_app/`, `backend/`, database credentials
   - `Input/external/ndvi/*.csv` (Zenodo: `Input Data/NDVI/`)
   - `Input/extended/merge_excel/*.xlsx` (Zenodo database staging)
   - Generated `Output/` (except `.gitkeep`)
   - Local logs, `.Rhistory`, `Scripts/renv/library/`

## Git commands

```bash
git init
git add .
git commit -m "SACBAD supplementary pipeline"
git remote add origin https://github.com/YOUR_ORG/YOUR_REPO.git
git push -u origin main
```

Frozen hydroclimate CSVs under `Input/` are versioned (~5 MB). Full paper database and NDVI stacks live on the **data Zenodo deposit** (`docs/ZENODO_DATABASE_README.txt`).
