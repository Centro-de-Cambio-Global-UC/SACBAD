# Copy frozen inputs from Input/ to working directories under Output/

seed_brutas <- function(
    dir_entrada = "Input/series_brutas",
    dir_destino = NULL,
    verbose = TRUE
) {
  root <- Sys.getenv("ASC_REPO_ROOT", getwd())
  if (is.null(dir_destino)) {
    dir_destino <- file.path(root, "Output", "series", "brutas")
  }
  dir.create(dir_destino, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(dir_entrada)) stop("Missing raw series folder: ", dir_entrada)
  archivos <- list.files(dir_entrada, pattern = "\\.csv$", full.names = TRUE)
  if (!length(archivos)) stop("No CSV files in ", dir_entrada)
  for (src in archivos) {
    dest <- file.path(dir_destino, basename(src))
    file.copy(src, dest, overwrite = TRUE)
    if (verbose) message("  raw: ", basename(src))
  }
  invisible(dir_destino)
}

seed_estaciones <- function(
    dir_metadata = "Input/metadata",
    dir_destino = NULL,
    verbose = TRUE
) {
  root <- Sys.getenv("ASC_REPO_ROOT", getwd())
  if (is.null(dir_destino)) {
    dir_destino <- file.path(root, "Output", "estaciones")
  }
  dir.create(dir_destino, recursive = TRUE, showWarnings = FALSE)
  patrones <- c("sacbad_pp_70_.*\\.csv", "sacbad_temp_60_.*\\.csv")
  copiados <- 0L
  for (pat in patrones) {
    hits <- list.files(dir_metadata, pattern = pat, full.names = TRUE)
    for (src in hits) {
      file.copy(src, file.path(dir_destino, basename(src)), overwrite = TRUE)
      copiados <- copiados + 1L
      if (verbose) message("  stations: ", basename(src))
    }
  }
  if (copiados == 0L && verbose) {
    warning("No station lists copied from ", dir_metadata)
  }
  invisible(dir_destino)
}

seed_spei_jv_baseline <- function(
    archivo_baseline = "Input/datos_spei_jv_baseline.csv",
    dir_ndvi = NULL,
    verbose = TRUE
) {
  root <- Sys.getenv("ASC_REPO_ROOT", getwd())
  if (is.null(dir_ndvi)) {
    dir_ndvi <- file.path(root, "Output", "Correlaciones_NDVI")
  }
  dir.create(dir_ndvi, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dir_ndvi, "datos_spei_jv.csv")
  meta <- file.path(root, "Input/metadata/ID_subcuencas.csv")
  if (file.exists(meta)) {
    file.copy(meta, file.path(dir_ndvi, "ID_subcuencas.csv"), overwrite = TRUE)
    if (verbose) message("  NDVI: ID_subcuencas.csv")
  }
  if (!file.exists(archivo_baseline)) {
    if (verbose) message("  SPEI JV: no baseline (CQP step will create rows)")
    return(invisible(FALSE))
  }
  file.copy(archivo_baseline, dest, overwrite = TRUE)
  if (verbose) message("  SPEI JV baseline -> ", dest)
  invisible(TRUE)
}

seed_cqp_brutas <- function(
    dir_entrada = "Input/cqp",
    dir_cqp = NULL,
    verbose = TRUE
) {
  root <- Sys.getenv("ASC_REPO_ROOT", getwd())
  if (is.null(dir_cqp)) {
    dir_cqp <- file.path(root, "Output", "cqp_temp_320048")
  }
  dir.create(dir_cqp, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(dir_entrada)) return(invisible(FALSE))
  for (src in list.files(dir_entrada, pattern = "\\.csv$", full.names = TRUE)) {
    file.copy(src, file.path(dir_cqp, basename(src)), overwrite = TRUE)
    if (verbose) message("  CQP raw: ", basename(src))
  }
  invisible(dir_cqp)
}

seed_all_inputs <- function(verbose = TRUE) {
  if (verbose) message(">>> Seeding frozen inputs (Input/ -> Output/)")
  seed_brutas(verbose = verbose)
  seed_estaciones(verbose = verbose)
  seed_cqp_brutas(verbose = verbose)
  seed_spei_jv_baseline(verbose = verbose)
  invisible(TRUE)
}
