#!/usr/bin/env Rscript
# NDVI CSV stacks are NOT in Git (~100 MB).
#
# There is no verified public download URL wired into this repository.
# Before optional NDVI correlations in run_all.R, obtain the stacks from the
# SACBAD **data deposit on Zenodo** (DOI in the paper and CITATION.cff), then
# place them under Input/external/ndvi/ in this GitHub repo (copy from Zenodo
# folder Input Data/NDVI/ on the data deposit):
#
#   Input/external/ndvi/NDVI_anual_est_csv/*.csv
#   Input/external/ndvi/NDVI_prim_est_csv/*.csv
#   Input/external/ndvi/NDVI_ver_est_csv/*.csv
#   Input/external/ndvi/base.tif          (optional, for GeoTIFF export)
#
# After files are in place, re-run: Rscript run_all.R
#
# Optional: if you host a zip on your own Zenodo record, set ZENODO_NDVI_URL
# to the direct file URL and re-run this script to download automatically.

repo_root <- normalizePath(getwd(), winslash = "/")
if (!dir.exists(file.path(repo_root, "Input"))) {
  stop("Run from the SACBAD_github repository root.")
}

dest_dir <- file.path(repo_root, "Input", "external", "ndvi")
dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

ndvi_ready <- function() {
  any(vapply(
    c("anual", "prim", "ver"),
    function(season) {
      d <- file.path(dest_dir, sprintf("NDVI_%s_est_csv", season))
      dir.exists(d) && length(list.files(d, pattern = "\\.csv$", recursive = TRUE)) > 0L
    },
    logical(1)
  ))
}

if (ndvi_ready()) {
  message("NDVI stacks found under Input/external/ndvi/")
  message("You can run: Rscript run_all.R")
  quit(save = "no", status = 0)
}

url <- Sys.getenv("ZENODO_NDVI_URL", unset = "")
if (nzchar(url) && !grepl("ZENODO_RECORD_ID|XXXXXXX|RECORD_ID", url)) {
  dest_zip <- file.path(repo_root, "Input", "external", "ndvi_sacbad_bundle.zip")
  message("Downloading: ", url)
  download.file(url, dest_zip, mode = "wb", quiet = FALSE)
  message("Extracting to: ", dest_dir)
  utils::unzip(dest_zip, exdir = dest_dir)
  if (ndvi_ready()) quit(save = "no", status = 0)
  warning("Download finished but NDVI_*_est_csv folders not detected. Check zip layout.")
}

cat(
  "\n=== NDVI input files not found ===\n\n",
  "1. Open the SACBAD data record on Zenodo (DOI in the paper / CITATION.cff).\n",
  "2. Download folder Input Data/NDVI/ (NDVI_anual_est_csv, NDVI_prim_est_csv,\n",
  "   NDVI_ver_est_csv, and optional base.tif).\n",
  "3. Copy those folders/files into:\n\n",
  "     ", dest_dir, "/\n\n",
  "4. Re-run: Rscript run_all.R\n\n",
  "Optional automated download: publish a zip on Zenodo and set ZENODO_NDVI_URL\n",
  "to the direct file URL, then run this script again.\n\n",
  "See docs/ZENODO_NDVI.md\n",
  sep = ""
)
quit(save = "no", status = 1)
