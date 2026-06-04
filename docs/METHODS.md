# Methods summary

## Period and stations

- Daily series 1988–2024; quality thresholds: precipitation ≥ 70 %, temperature ≥ 60 %.
- Station lists are frozen in `Input/metadata/`.

## Quality control (step 3)

Outliers are set to missing using physical limits, IQR (k = 1.5), and station-level rules for low-mean precipitation sites.

## Gap filling (step 4)

Multivariate imputation with **missForest** (`ntree = 100`, `maxiter = 10`) on daily wide tables.

## Aggregation (step 5)

- Precipitation: monthly sum.
- Temperature: monthly mean of daily t_max and t_min.

## Drought indices (step 6)

- **SPEI** and **SPI** at 3-, 6-, and 12-month scales (`SPEI` package).
- Potential evapotranspiration: Hargreaves.
- Non-finite values capped at ±4.

## SPEI-12 and hydrological year

The hydrological year runs **April–March**. **SPEI-12 in September** is reported for tables and NDVI work because it reflects moisture at the end of the wet season in central Chile. Calendar-year and December variants are also exported in `datos_spei_jv.csv` where applicable.

## CQP temperature

Station **320048** (Longotoma) supplies temperature for SPEI at **320005** (Huaquén), which carries precipitation for sub-basin **CQP**. Flow: QC → missForest → monthly → SPEI → merge into global indicators and `datos_spei_jv.csv`.

## Consolidated Excel

`Scripts/7_consolidado_excel.R` builds annual wide tables; sheet **Hydroclimatic** includes `(CQP)` columns after the CQP step.

## Reproducibility

From a clean clone: `renv::restore()` (optional), then `Rscript run_all.R`. Compare outputs with `Rscript Scripts/tests/verify_outputs.R`.
