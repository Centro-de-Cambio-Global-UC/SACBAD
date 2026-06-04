# Shared paths for extended (post-pipeline) analyses — SACBAD supplementary repo

extended_repo_root <- function() {
  root <- Sys.getenv("ASC_REPO_ROOT", unset = NA_character_)
  if (!is.na(root) && nzchar(root) && dir.exists(file.path(root, "Input"))) {
    return(normalizePath(root, winslash = "/"))
  }
  wd <- normalizePath(getwd(), winslash = "/")
  for (up in 0:8) {
    cand <- if (up == 0) wd else normalizePath(file.path(wd, paste(rep("..", up), collapse = "/")), winslash = "/")
    if (dir.exists(file.path(cand, "Input"))) return(cand)
  }
  wd
}

#' Set working directory under Output/extended/<module>/
extended_use_module <- function(module) {
  root <- extended_repo_root()
  out <- file.path(root, "Output", "extended", module)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  setwd(out)
  assign("EXT_REPO_ROOT", root, envir = .GlobalEnv)
  assign("EXT_WORK_DIR", out, envir = .GlobalEnv)
  invisible(out)
}

extended_timeseries_xlsx <- function() {
  root <- extended_repo_root()
  cands <- c(
    file.path(root, "Output", "consolidado_export",
              "sacbad_timeseries_anual_1988_2024.xlsx"),
    file.path(root, "Output", "consolidado_export",
              "sacbad_timeseries_anual_1990_2024.xlsx"),
    file.path(root, "Output", "extended", "ndvi_spei_correlations",
              "sacbad_timeseries_anual_1990_2024.xlsx")
  )
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) {
    stop(
      "Hydroclimatic Excel not found. Run run_all.R first or copy ",
      "sacbad_timeseries_anual_*.xlsx into Output/consolidado_export/."
    )
  }
  hit
}

extended_spei_jv_csv <- function() {
  root <- extended_repo_root()
  cands <- c(
    file.path(root, "Output", "Correlaciones_NDVI", "datos_spei_jv.csv"),
    file.path(root, "Output", "extended", "ndvi_spei_correlations", "datos_spei_jv.csv")
  )
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) {
    stop("datos_spei_jv.csv not found. Run run_all.R or place file under Output/Correlaciones_NDVI/.")
  }
  hit
}

extended_id_subcuencas <- function() {
  root <- extended_repo_root()
  cands <- c(
    file.path(root, "Input", "metadata", "ID_subcuencas.csv"),
    file.path(root, "Output", "Correlaciones_NDVI", "ID_subcuencas.csv"),
    file.path(root, "Output", "extended", "ndvi_spei_correlations", "ID_subcuencas.csv")
  )
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("ID_subcuencas.csv not found.")
  hit
}
