# NDVI data (Zenodo deposit vs GitHub repo)

NDVI pixel CSV stacks (~100 MB) are **not** in the GitHub code repository. They are published on the **SACBAD data Zenodo deposit** (paper data DOI).

## Where the files live on Zenodo

On the data deposit, NDVI stacks are under:

```
Input Data/NDVI/
  NDVI_anual_est_csv/
    NDVI_CQPanual_est.csv
    NDVI_UQanual_est.csv
    ... (one CSV per sub-basin ID: CQP, LL, LP, LQ, ML, MP, MQ, UL, UP, UQ)
  NDVI_prim_est_csv/     (spring — when included in the deposit)
  NDVI_ver_est_csv/      (summer — when included in the deposit)
  base.tif               (optional — enables GeoTIFF export in correlations)
```

Each CSV contains columns `ID`, `cell`, and years **1991–2022** (one row per grid cell).

The summary table **Vegetation NDVI** in `Input Data/All_annual_timeseries.xlsx` is separate: aggregated NDVI by sub-basin and land cover, not the pixel stacks.

## Using NDVI with the GitHub pipeline (`SACBAD_github`)

The R pipeline does **not** read Zenodo paths directly. After downloading this data deposit:

1. Copy the contents of **`Input Data/NDVI/`** from Zenodo into the GitHub repo as:

```
Input/external/ndvi/
  NDVI_anual_est_csv/
  NDVI_prim_est_csv/    (if available on Zenodo)
  NDVI_ver_est_csv/     (if available on Zenodo)
  base.tif              (optional)
```

`Input/external/ndvi/` exists only in the **GitHub repo layout** — it is gitignored and is where `run_all.R` looks for files before running NDVI–SPEI correlations.

2. Check inputs:

```bash
Rscript Scripts/download_ndvi_zenodo.R
```

3. Run:

```bash
Rscript run_all.R
```

There is **no verified automated download URL** in the GitHub repo. Users must obtain files from the **paper data DOI** on Zenodo and copy them as above.

## Optional automated download (maintainers)

If you publish a single zip on your Zenodo record:

```bash
export ZENODO_NDVI_URL="https://zenodo.org/records/YOUR_ID/files/ndvi_sacbad_bundle.zip?download=1"
Rscript Scripts/download_ndvi_zenodo.R
```

The zip should unpack with the same `NDVI_*_est_csv/` folder names under `Input/external/ndvi/`.

## Citation

Cite the SACBAD data Zenodo deposit and the original NDVI product as required by your license.
