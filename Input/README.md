# Frozen inputs (SACBAD)

Versioned data to reproduce the pipeline **without** a database connection.

## Layout

| Path | Description |
|------|-------------|
| `metadata/estaciones_sacbad_pp70.csv` | Precipitation stations (≥ 70 % completeness) |
| `metadata/sacbad_pp_70_1988_2024.csv` | Station list used in the pipeline |
| `metadata/sacbad_temp_60_1988_2024.csv` | Temperature stations (≥ 60 %) |
| `metadata/cqp_temp_fuente.csv` | CQP metadata: temp 320048 → proxy 320005 |
| `metadata/ID_subcuencas.csv` | Sub-basin IDs (NDVI correlations) |
| `series_brutas/` | Daily raw PP, t_max, t_min (1988–2024) |
| `cqp/` | Daily t_max/t_min for station **320048** (Longotoma) |
| `datos_spei_jv_baseline.csv` | SPEI by sub-basin (all rows except CQP; CQP is recomputed) |
| `external/ndvi/` | Optional NDVI stacks — manual download from paper Zenodo DOI (`docs/ZENODO_NDVI.md`) |

## Raw series columns

- `fecha`, `year`, `month`, `day`
- One column per national station code (daily values; `NA` = missing)

## Period

1988-01-01 — 2024-12-31 (warm-up for SPEI-12; annual tables from 1990).

## CQP temperature

Precipitation for sub-basin **CQP** uses station **320005** (Huaquén). Temperature for SPEI uses **320048** (Longotoma), processed in `Scripts/cqp_temperature.R` and copied as a proxy into column 320005.

## Sources

Hydrometeorological data: Chilean DGA and DMC. No credentials or SQL dumps are included in this repository.
