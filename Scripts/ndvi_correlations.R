# NDVI–SPEI correlations (optional; requires Input/external/ndvi/)

repo_root <- Sys.getenv("ASC_REPO_ROOT", unset = getwd())
dir_ndvi_data <- file.path(repo_root, "Input/external/ndvi")
dir_ndvi_out  <- file.path(repo_root, dir_output_proyecto, "Correlaciones_NDVI")
dir_scripts   <- file.path(repo_root, "Scripts")

if (!dir.exists(dir_ndvi_data)) {
  message("NDVI: skipped (", dir_ndvi_data, " not found).")
  message("  Place NDVI stacks under Input/external/ndvi/ — see docs/ZENODO_NDVI.md")
  invisible(FALSE)
} else {
  message("\n=== NDVI correlations (optional) ===\n")
  dir.create(dir_ndvi_out, recursive = TRUE, showWarnings = FALSE)

  ndvi_dirs <- list.dirs(dir_ndvi_data, recursive = FALSE, full.names = TRUE)
  for (d in ndvi_dirs) {
    dest <- file.path(dir_ndvi_out, basename(d))
    if (!dir.exists(dest)) {
      dir.create(dest, recursive = TRUE, showWarnings = FALSE)
      file.copy(list.files(d, full.names = TRUE), dest, recursive = TRUE)
      message("  copied: ", basename(d))
    }
  }

  runner <- file.path(dir_scripts, "ndvi", "run_correlaciones_ndvi_spei_auto.R")
  if (!file.exists(runner)) {
    runner <- file.path(dir_ndvi_out, "run_correlaciones_ndvi_spei_auto.R")
  }
  if (!file.exists(runner)) {
    warning("NDVI runner script not found in Scripts/ndvi/ or Output/Correlaciones_NDVI/")
    invisible(FALSE)
  } else {
    file.copy(runner, file.path(dir_ndvi_out, basename(runner)), overwrite = TRUE)
    ow <- getwd()
    on.exit(setwd(ow), add = TRUE)
    setwd(dir_ndvi_out)
    status <- system2("Rscript", args = basename(runner), wait = TRUE)
    if (status != 0) stop("NDVI correlations failed with exit code ", status)
    message("  NDVI correlations finished.")
    invisible(TRUE)
  }
}
