# VIIRS night-time lights

Reproducible workflow using **repository-relative paths only**.

## Prerequisites

- Python 3 with `fiona`, `rasterio`, `geopandas`, `numpy`, `scipy`, `opencv-python`, `matplotlib`
- Shapefiles in `Input/extended/viirs/shapefiles/` (`cut_area.shp`, `point_control.shp`, included in Git)

## 1. Prepare working directory

From repository root:

```bash
python Scripts/extended/viirs/setup_viirs_workdir.py
```

Windows without Python on PATH:

```powershell
powershell -File Scripts/extended/viirs/setup_viirs_workdir.ps1
```

Creates `Output/extended/viirs/` with:

- `shapefiles/` (copy of Input shapefiles)
- `Download/viirs_avg_rad/raw`, `cut`, `background_denoise/denoise`, etc.

## 2. Run notebooks (in order)

**Important:** set the Jupyter working directory to `Output/extended/viirs/` so relative paths in the notebooks resolve correctly.

```bash
cd Output/extended/viirs
jupyter notebook ../../../Scripts/extended/viirs/notebooks/
```

| Notebook | Step |
|----------|------|
| `0)VIIRS_download.ipynb` | Download raw VIIRS tiles → `Download/viirs_avg_rad/raw/` |
| `1)Viirs_denoise_background.ipynb` | Clip to `cut_area.shp`, background denoise |
| `2)Viirs_connected_components.ipynb` | Connected components / area extraction |

Notebooks use `os.getcwd()` + `shapefiles/cut_area.shp` (relative to the work dir above).

## 3. Clip annual rasters (optional)

After annual composites are in `Output/extended/viirs/Download/viirs_avg_rad_new_years/`:

```bash
python Scripts/extended/viirs/python/cut_20km.py
```

Defaults are defined in `Scripts/extended/viirs/viirs_paths.py` (no hardcoded user paths).

Custom folders:

```bash
python Scripts/extended/viirs/python/cut_20km.py \
  --input Output/extended/viirs/Download/viirs_avg_rad_new_years \
  --output Output/extended/viirs/Download/viirs_avg_rad/cortado
```

## Outputs

Store large GeoTIFFs under `Output/extended/viirs/` (gitignored). Annual summaries for the paper are in the Zenodo database (`All_annual_timeseries.xlsx`, VIIRS sheet).
