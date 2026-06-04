# SACBAD

Code and data accompanying the paper **"Assessing the Complex Nature of Climate Change Risks in Semi-Arid Coastal Basins"**. This repository contains datasets, analysis workflows, and scripts used to evaluate climate risk propagation, ecohydrological responses, and adaptation dynamics in semi-arid coastal basins of central Chile during the megadrought.

Self-contained reproduction of the hydroclimatic pipeline: frozen inputs, one command, no database and **no Shiny app**.

## Repository layout

```
├── run_all.R          # Single entry point (core pipeline)
├── Input/             # Frozen CSV inputs (versioned)
│   └── extended/      # Optional vectors for extended workflows
├── Output/            # Generated products (not versioned)
│   └── extended/      # Post-pipeline outputs (NDVI maps, VIIRS, etc.)
├── Scripts/           # Core R pipeline, config, renv, tests
│   └── extended/      # Colleague follow-on scripts (R + Python + notebooks)
└── docs/              # Documentation (English)
```

## Citation

See `CITATION.cff` for software citation. Add the paper DOI when available.

## Requirements

- R ≥ 4.2
- Recommended: `renv::restore()` using `Scripts/renv.lock`
- ~5 MB versioned inputs, ~200–500 MB disk for full outputs
- No PostgreSQL or VPN

## Quick start

```bash
git clone https://github.com/Centro-de-Cambio-Global-UC/SACBAD.git
cd SACBAD
Rscript run_all.R
```

Verify key outputs:

```bash
Rscript Scripts/tests/verify_outputs.R
```

Typical runtime: 5–15 min (hydroclimate only); +60–90 min if NDVI correlations run.

## Pipeline

1. Quality control — physical limits, IQR, station thresholds (`Scripts/3_depurado.R`)
2. Gap filling — `missForest` (`Scripts/4_missforest.R`)
3. Aggregation — monthly / annual / historical (`Scripts/5_agregacion.R`)
4. Indices — SPI and SPEI-3/6/12 (`Scripts/6_indicadores_tendencias.R`)
5. CQP — temperature 320048 → proxy 320005 (`Scripts/cqp_temperature.R`)
6. Excel — `Hydroclimatic` sheet (`Scripts/consolidado.R`)

Configuration: `Scripts/config_sacbad.R` (steps 0–2 off, relative paths, 1988–2024).

## Outputs

| File | Description |
|------|-------------|
| `Output/consolidado_export/sacbad_timeseries_anual_1988_2024.xlsx` | Annual tables (Hydroclimatic) |
| `Output/Correlaciones_NDVI/datos_spei_jv.csv` | SPEI-12 by sub-basin and hydro-year |
| `Output/indicadores/sacbad_spei_12_60_1988_2024.csv` | Monthly SPEI-12 by station |
| `Output/series/mensual/sacbad_*_mensual.csv` | Monthly PP and temperature |

## CQP temperature proxy

Sub-basin **CQP** uses precipitation at **320005** (Huaquén) and temperature from **320048** (Longotoma), imputed and assigned as a proxy on 320005 for SPEI (see `Input/metadata/cqp_temp_fuente.csv`).

## Extended analyses (optional)

Follow-on scripts from collaborators (NDVI correlation workbooks, wetlands GEE, VIIRS notebooks) live under `Scripts/extended/`. See `Scripts/extended/README.md` and `docs/EXTENDED_ANALYSES.md`. They are **not** part of `run_all.R`.

## NDVI (optional)

NDVI CSV stacks are **not** in Git. Download them from the **SACBAD Zenodo data deposit** (paper DOI) and copy to `Input/external/ndvi/` (see `Input/external/ndvi/README.txt`).

```bash
Rscript Scripts/download_ndvi_zenodo.R   # check / instructions
Rscript run_all.R
```

See `docs/ZENODO_NDVI.md`.

## Troubleshooting

- Close Excel if `sacbad_timeseries_anual_*.xlsx` is open before re-running.
- `missForest` is slow on long daily panels — expected.
- NDVI step is skipped without `Input/external/ndvi/`.

## License

See `LICENSE`. Third-party hydrometeorological data remain under DGA/DMC terms.
