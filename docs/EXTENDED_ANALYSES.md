# Extended analyses (beyond the core pipeline)

The manuscript supplementary pipeline (`run_all.R`) ends with consolidated hydroclimatic Excel, SPEI indicators, and optional NDVI–SPEI tables. Collaborators added further scripts for:

1. **NDVI–SPEI correlations and land-cover stratification** (R, `Scripts/extended/ndvi_spei_correlations/`)
2. **Coastal wetland mapping** from Sentinel/Landsat (Python + GEE, `Scripts/extended/wetlands/`)
3. **VIIRS night-time lights** processing (Jupyter + Python, `Scripts/extended/viirs/`)

These are documented in `Scripts/extended/README.md`. They use:

- **Inputs:** core `Output/` products plus `Input/extended/` vectors and externally downloaded rasters
- **Outputs:** `Output/extended/` only

There is no single orchestrator; run each module when the relevant data are available.

## Relationship to `Scripts/ndvi/`

- `Scripts/ndvi/run_correlaciones_ndvi_spei_auto.R` — batch runner integrated with `run_all.R` when `Input/external/ndvi/` exists.
- `Scripts/extended/ndvi_spei_correlations/02_*.R` — related science, manual layout, expects GeoTIFF stacks in the extended working directory.

Both can coexist; prefer one workflow per publication figure to avoid duplicated results.
