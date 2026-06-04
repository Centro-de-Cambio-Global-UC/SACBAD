# NDVI–SPEI and hydroclimate correlations (R)

| Script | Description |
|--------|-------------|
| `01_Estandarizacion_SPEI.R` | Build standardized SPEI table from Hydroclimatic Excel (+ synthetic MQ from LQ/UQ) |
| `02_Correlaciones_y_stats.R` | Pixel/sub-basin NDVI vs SPEI correlations, rasters, land-cover masks |
| `03_SPEI_G_Q_V.R` | Correlations among SPEI, groundwater depth, streamflow, VIIRS |

Run from repository root or from this folder after `extended_paths.R` is sourced.

**Input from core pipeline:** `Output/consolidado_export/sacbad_timeseries_anual_1988_2024.xlsx`  
**Output:** `Output/extended/ndvi_spei_correlations/datos_SPEI_2026.csv` (and subfolders created by script 02).
