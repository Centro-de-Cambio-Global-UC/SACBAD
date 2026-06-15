================================================================================
SACBAD supplementary database (Zenodo)
================================================================================

This folder contains the published data package supporting the SACBAD
manuscript: annual hydroclimatic and land-surface time series, figure-ready
tables, NDVI pixel stacks, and geospatial correlation products for the
Petorca-Quilimari-Ligua basins (central Chile).

Companion file: SACBAD_data_dictionary.xlsx
  Machine-readable inventory, folder map, sheet list, column definitions, and
  GeoTIFF naming guide. Filter sheets File_inventory and Fields in Excel.

Time coverage: 1990-2023
  Hydrological year Apr-Mar where stated; calendar year otherwise.

Sub-basin IDs (see dictionary sheet Subbasin_codes):

  ID    Basin
  --    -----
  UQ    Upper Quilimari
  LQ    Lower Quilimari
  MQ    Middle Quilimari (to Culimo dam)
  CQP   Coastal Quilimari-Petorca
  UP    Upper Petorca
  MP    Middle Petorca
  LP    Lower Petorca
  UL    Upper Ligua
  ML    Middle Ligua
  LL    Lower Ligua


================================================================================
FOLDER MAP
================================================================================

All paths relative to the root of this Zenodo deposit.

Bases de datos nuevas/
  README.txt
  SACBAD_data_dictionary.xlsx
  Input Data/
    All_annual_timeseries.xlsx
    NDVI/
      NDVI_anual_est_csv/          (10 CSV, one per sub-basin)
      NDVI_prim_est_csv/           (when uploaded)
      NDVI_ver_est_csv/            (when uploaded)
    Correlations/
      Correlations - SPEI - G - Q - VIIRS/
        correlacion_IPE_G_Q_Viirs_todos_los_años_2026.xlsx
        SPEI_G_Q_v_para_analisis.csv
      Correlations_NDVI_SPEI/
        Correlaciones Significativas/          (9 GeoTIFF)
        Correlaciones Significativas por LC/   (27 GeoTIFF)
        Todas Correlaciones y Valor P/         (18 GeoTIFF)
  Processed Data/
    Paper figures/
      figure4_data.xlsx
      figure5_data.xlsx
      figure6_data.xlsx
      Table3_data.xlsx
    Supplementary Material figures/
      figS1_data.xlsx

GitHub software repo (separate Zenodo/GitHub record): SACBAD_github
  Users who re-run NDVI correlations copy Input Data/NDVI/ from this deposit
  into Input/external/ndvi/ in that repository (see docs/ZENODO_NDVI.md there).


================================================================================
INPUT DATA
================================================================================

Path: Input Data/

Raw and derived analytical inputs used to build publication tables and
correlation maps.

--------------------------------------------------------------------------------
Input Data/All_annual_timeseries.xlsx
--------------------------------------------------------------------------------
Master workbook for annual indicators and supplementary series.

  Hydroclimatic                 Year; precipitation (hydro + calendar year);
                                groundwater; streamflow; SPI-12; temperature;
                                SPEI-12 for nine sub-basins (1990-2023).

  Vegetation NDVI               NDVI by sub-basin, land cover, season; years
                                as columns (summary table).

  Water rights                  Accumulated surface/groundwater rights.

  VIIRS                         Night-time lights area (ha) per sub-basin.

  NDWI                          Open-water area (ha).

  Coastal lagoon Inlet          Monthly inlet state (open=1, closed=-1).

  Hydroclimatic coastal lagoon  Lagoon-zone precipitation and groundwater.

  figS1_data_Hydrograph         Supplementary Figure S1 hydrograph inputs.

  raw_series_pp_q_g             Wide annual P, Q, G series for hydrograph.


--------------------------------------------------------------------------------
Input Data/NDVI/
--------------------------------------------------------------------------------
Pixel-level NDVI stacks for correlation analysis (not in the GitHub code repo).

  NDVI_anual_est_csv/
      NDVI_CQPanual_est.csv, NDVI_UQanual_est.csv, ... (10 files, sub-basin IDs)
      Columns: ID, cell, 1991-2022 (one row per grid cell).

  NDVI_prim_est_csv/            Spring season (upload when available)
  NDVI_ver_est_csv/             Summer season (upload when available)
  base.tif                      Optional raster template (upload when available)

These folders are the authoritative location on this Zenodo deposit.
The GitHub pipeline expects the same folder names under Input/external/ndvi/
after manual copy (see SACBAD_github/docs/ZENODO_NDVI.md).


--------------------------------------------------------------------------------
Input Data/Correlations/
--------------------------------------------------------------------------------

Correlations - SPEI - G - Q - VIIRS/
  correlacion_IPE_G_Q_Viirs_todos_los_años_2026.xlsx
      SPEI (IPE) vs groundwater, streamflow, VIIRS - tables and synthesis.
  SPEI_G_Q_v_para_analisis.csv
      Long-format SPEI/SPI, G, Q, VIIRS by sub-basin and hydro year.

Correlations_NDVI_SPEI/
  Correlaciones Significativas/ (9 files)
      {NDVIseason}_{SPEIindex}_corr_sign.tif - significant pixels only.

  Correlaciones Significativas por LC/ (27 files)
      ..._{agriculture|forest|shrubland}.tif - by land cover.

  Todas Correlaciones y Valor P/ (18 files)
      ..._correlation.tif and ..._pvalue.tif - full grids.

NDVI seasons: anual, prim (spring), ver (summer).
SPEI indices: anual, sep (SPEI-12 ending September), dic (ending December).


================================================================================
PROCESSED DATA
================================================================================

Path: Processed Data/Paper figures/

Publication-ready Excel tables for main-text figures and Table 3.

  figure4_data.xlsx     Figure 4 - Petorca climate/hydrology, wells, rights,
                        monthly lagoon inlet.

  figure5_data.xlsx     Figure 5 - extended annual multi-variable series and
                        monthly inlet.

  figure6_data.xlsx     Figure 6 - NDVI, VIIRS, NDWI vs SPI; agricultural
                        census.

  Table3_data.xlsx      Table 3 - NDVI-SPEI correlation summary stats
                        (combined sheet + 9 NDVI x SPEI subsets).

Path: Processed Data/Supplementary Material figures/

  figS1_data.xlsx       Supplementary Figure S1 data.


================================================================================
GeoTIFF notes
================================================================================

- Open in QGIS, R (terra/raster), or Python (rasterio).
- Filename tokens parsed in SACBAD_data_dictionary.xlsx, sheet GeoTIFF_rasters.


================================================================================
Regenerating documentation
================================================================================

  powershell -File "path\to\SACBAD_github\Scripts\extended\merge_excel\build_zenodo_database_docs.ps1" -Root "path\to\this folder"

Requires Windows and Microsoft Excel.


================================================================================
Related repository
================================================================================

Reproducible R pipeline: SACBAD_github (https://github.com/Centro-de-Cambio-Global-UC/SACBAD).
Hydroclimate CSVs are frozen in that repo; NDVI stacks and this full database
live on this data deposit.

Project master archive (OneDrive): uc365_SACBAD Anillo 220055 - Database
includes an additive catalog at 00_Database_Registry/ (relational CSV index,
geospatial inventory, MANIFEST checksums). Zenodo mirrors analytical products
for public citation; field monitoring data remains in the uc365 archive.


================================================================================
Citation
================================================================================

Cite the SACBAD manuscript and this Zenodo deposit once published. Station
data from DGA and DMC (Chile); see manuscript Data Availability.

Generated: 2026-06-04
