# Extended analyses (colleague workflows)

Scripts contributed for **follow-on work** after the core SACBAD hydroclimatic pipeline (`run_all.R`). They are **not** invoked by `run_all.R` and may require extra data, Python environments, or Google Earth Engine credentials.

## Modules

| Folder | Language | Purpose |
|--------|----------|---------|
| `ndvi_spei_correlations/` | R | SPEI standardization from Excel; NDVI–SPEI correlations and maps; SPEI vs groundwater, streamflow, VIIRS |
| `wetlands/` | Python / Jupyter | Sentinel/Landsat wetland mapping (Ligua–Petorca coast) |
| `viirs/` | Python / Jupyter | VIIRS night-time lights download, denoising, connected components |

Shared path helper: `extended_paths.R` (working directory `Output/extended/<module>/`).

## NDVI–SPEI (R)

**Prerequisites:** run `run_all.R` first (or copy `sacbad_timeseries_anual_*.xlsx` to `Output/consolidado_export/`).

```bash
cd SACBAD_github
Rscript Scripts/extended/ndvi_spei_correlations/01_Estandarizacion_SPEI.R
```

Script `02_Correlaciones_y_stats.R` expects, under `Output/extended/ndvi_spei_correlations/`:

- `datos_SPEI_2026.csv` (from script 01)
- `ID_subcuencas.csv` (from `Input/metadata/` or copied locally)
- NDVI GeoTIFF stacks (`NDVI_verano/`, etc.) and `subcuencas_nombres/subcuencas_nombres.shp`  
  (often from Zenodo bundle — see `docs/ZENODO_NDVI.md`)

Script `03_SPEI_G_Q_V.R` needs colleague Excel files (`All_annual_timeseries.xlsx`, VIIRS summaries) placed in the same working folder.

**Note:** `Scripts/ndvi/run_correlaciones_ndvi_spei_auto.R` is the automated pipeline used in development; these R scripts are an alternate / complementary workflow.

## Wetlands (Python)

```powershell
powershell -File Scripts/extended/wetlands/setup_wetlands_workdir.ps1
cd Output/extended/wetlands
jupyter notebook ../../../Scripts/extended/wetlands/notebooks/
```

Requires **Google Earth Engine** (`earthengine authenticate`). Optional: `$env:GEE_PROJECT = "your-gee-project-id"`.

Coast geometries are copied from `Input/extended/wetlands/shapes/`.

## VIIRS (Python)

```bash
python Scripts/extended/viirs/setup_viirs_workdir.py
cd Output/extended/viirs
jupyter notebook ../../../Scripts/extended/viirs/notebooks/
```

See `viirs/README.md`. Shapefiles: `Input/extended/viirs/shapefiles/`.

## Outputs

All extended products should go under `Output/extended/` (gitignored). Do not mix with core pipeline folders unless you intentionally overwrite files.

## Provenance

Code adapted from collaborator workflows (Gestiona / PUC). Paths use repository-relative layout under `Input/` and `Output/extended/`.
