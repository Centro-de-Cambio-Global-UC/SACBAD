# Extended analysis inputs

Auxiliary spatial data for **optional** workflows under `Scripts/extended/`. Not required for `run_all.R`.

| Path | Used by |
|------|---------|
| `wetlands/shapes/ligua_petorca_coast/*.geojson` | Wetlands Sentinel / GEE notebooks |
| `viirs/shapefiles/` | VIIRS clipping (`cut_area.shp`, `point_control.shp`, plus `.gpkg`) |
| `ndvi/` | Optional mirror of Zenodo NDVI bundle (same role as `Input/external/ndvi/` at repo root) |

Large rasters (NDVI stacks, VIIRS annual tiles) should stay **outside Git** or on Zenodo; only small metadata and vectors are versioned here.
