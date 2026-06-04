#!/usr/bin/env Rscript
# SACBAD supplementary repository — single entry point
#
# From repository root:
#   Rscript run_all.R

source("Scripts/setup.R")
asc_setup()
Sys.setenv(ASC_REPO_ROOT = asc_repo_root())

Sys.setenv(ASC_CONFIG = "Scripts/config_sacbad.R")
Sys.setenv(ASC_USE_DB = "false")
asc_source_config()

source("Scripts/seed_inputs.R")
seed_all_inputs()

message("\n>>> Main pipeline (steps 3-7, no database)\n")
source("Scripts/MAIN.R")

message("\n>>> CQP: temperature proxy + SPEI\n")
source("Scripts/cqp_temperature.R")

message("\n>>> Excel consolidation\n")
source("Scripts/consolidado.R")

ndvi_dir <- file.path(asc_repo_root(), "Input", "external", "ndvi")
if (dir.exists(ndvi_dir) &&
    length(list.files(ndvi_dir, pattern = "\\.csv$", recursive = TRUE)) > 0L) {
  source("Scripts/ndvi_correlations.R")
} else {
  message("\nNDVI: skipped. Download stacks from the paper Zenodo DOI into Input/external/ndvi/")
  message("  See docs/ZENODO_NDVI.md and run: Rscript Scripts/download_ndvi_zenodo.R")
}

message("\n=== run_all.R finished ===")
message("Key outputs:")
message("  - Output/consolidado_export/sacbad_timeseries_anual_*_*.xlsx")
message("  - Output/Correlaciones_NDVI/datos_spei_jv.csv")
message("  - Output/indicadores/sacbad_spei_12_*_*.csv")
