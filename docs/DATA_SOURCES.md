# Data sources and attribution

## Hydrometeorological stations

- **DGA** — Dirección General de Aguas (Chile).
- **DMC** — Dirección Meteorológica de Chile.

Daily extracts in `Input/series_brutas/` are frozen CSV snapshots. The institutional PostgreSQL warehouse used during development is **not** part of this repository.

## Sub-basin metadata

`Input/metadata/ID_subcuencas.csv` — sub-basin identifiers for SPEI/NDVI joins.

## Known limitations

- Sub-basin **MQ** may lack precipitation in consolidated timeseries when no in-basin station meets the quality threshold.
- NDVI products are distributed separately via Zenodo (`docs/ZENODO_NDVI.md`).

## Credentials

Do not commit `.env` or database password files. `run_all.R` does not require database access.
