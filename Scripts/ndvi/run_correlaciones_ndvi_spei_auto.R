# Correlaciones NDVI (1991-2022) vs SPEI estandarizado (datos_spei_jv.csv)
# Ejecucion secuencial, avance periodico y checkpoint por subcuenca.
#
# Relanzar tras una caida: vuelva a ejecutar el mismo comando; omite lo ya terminado.
# Forzar recalculo total: Rscript run_correlaciones_ndvi_spei_auto.R --force

suppressPackageStartupMessages({
  library(data.table)
  library(terra)
})

# Working directory: run from Output/Correlaciones_NDVI (set by ndvi_correlations.R)
WORK_DIR <- getwd()

LOG_FILE <- "avance_correlaciones.log"
CHECKPOINT_FILE <- "checkpoint_completados.tsv"
PROGRESS_ROWS <- 10000L
PROGRESS_SECONDS <- 30L

args <- commandArgs(trailingOnly = TRUE)
FORCE_RECALC <- "--force" %in% args
USE_CHECKPOINT <- !FORCE_RECALC

log_msg <- function(...) {
  line <- paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " | ", paste0(..., collapse = ""))
  message(line)
  cat(line, "\n", file = LOG_FILE, append = TRUE)
  flush.console()
}

spei_tag <- function(spei_col) {
  switch(spei_col,
    SPEI12anual_est = "SPEIanual",
    SPEI12sep_est = "SPEIsep",
    SPEI12dic_est = "SPEIdic",
    spei_col
  )
}

output_paths <- function(id, ndvi_label, tag, out_dir) {
  list(
    csv = file.path(out_dir, sprintf("%s_NDVI%s_%s.csv", id, ndvi_label, tag)),
    corr_tif = file.path(out_dir, sprintf("%s_NDVI%s_%s_correlation.tif", id, ndvi_label, tag)),
    pval_tif = file.path(out_dir, sprintf("%s_NDVI%s_%s_pvalue.tif", id, ndvi_label, tag))
  )
}

archivo_valido <- function(path, min_bytes = 1000L) {
  if (!file.exists(path)) return(FALSE)
  sz <- suppressWarnings(file.info(path)$size)
  is.finite(sz) && sz >= min_bytes
}

contar_filas_tabla <- function(path) {
  tryCatch(
    nrow(fread(path, select = "cell", showProgress = FALSE)),
    error = function(e) NA_integer_
  )
}

borrar_salidas <- function(paths) {
  paths <- unique(paths[file.exists(paths)])
  if (length(paths) == 0L) return(0L)
  unlink(paths)
  length(paths)
}

validar_salida_subcuenca <- function(id, ndvi_label, spei_col, out_dir, ndvi_path, base_rast) {
  tag <- spei_tag(spei_col)
  paths <- output_paths(id, ndvi_label, tag, out_dir)
  require_tif <- !is.null(base_rast)
  all_paths <- c(paths$csv, if (require_tif) c(paths$corr_tif, paths$pval_tif) else character())
  existing <- all_paths[file.exists(all_paths)]

  if (length(existing) == 0L) {
    return(list(ok = FALSE, reason = "sin archivos", borrar = character()))
  }
  if (length(existing) < length(all_paths)) {
    return(list(ok = FALSE, reason = "salida incompleta (faltan CSV o TIF)", borrar = existing))
  }

  n_exp <- contar_filas_tabla(ndvi_path)
  n_csv <- contar_filas_tabla(paths$csv)
  if (!is.finite(n_exp) || !is.finite(n_csv) || n_csv != n_exp) {
    return(list(
      ok = FALSE,
      reason = sprintf("CSV con %s filas (esperado %s)", n_csv, n_exp),
      borrar = existing
    ))
  }

  cols_ok <- tryCatch({
    dt <- fread(paths$csv, select = c("cell", "correlation", "p_value"), nrows = 5L, showProgress = FALSE)
    ncol(dt) == 3L
  }, error = function(e) FALSE)
  if (!cols_ok) {
    return(list(ok = FALSE, reason = "CSV corrupto o ilegible", borrar = existing))
  }

  if (require_tif) {
    min_tif <- max(10000L, as.integer(file.info(paths$csv)$size / 20L))
    for (tif in c(paths$corr_tif, paths$pval_tif)) {
      if (!archivo_valido(tif, min_tif)) {
        return(list(ok = FALSE, reason = "TIF demasiado pequeno", borrar = existing))
      }
      ok_r <- tryCatch({
        r <- rast(tif)
        ncell(r) > 0L && nrow(r) == nrow(base_rast) && ncol(r) == ncol(base_rast)
      }, error = function(e) FALSE)
      if (!ok_r) {
        return(list(ok = FALSE, reason = "TIF corrupto o dimension incorrecta", borrar = existing))
      }
    }
  }

  list(ok = TRUE, reason = "ok", borrar = character())
}

registrar_checkpoint <- function(out_dir, id, ndvi_label, spei_col) {
  line <- paste(
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    out_dir, id, ndvi_label, spei_col,
    sep = "\t"
  )
  cat(line, "\n", file = CHECKPOINT_FILE, append = TRUE)
}

find_ndvi_dir <- function(ndvi_label) {
  cands <- c(
    file.path(sprintf("NDVI_%s_est_csv", ndvi_label), sprintf("NDVI_%s_est_csv", ndvi_label)),
    sprintf("NDVI_%s_est_csv", ndvi_label)
  )
  cands[file.exists(cands)][1]
}

get_spei_vector <- function(datos_spei, id, spei_col, years = 1991:2022) {
  sub <- datos_spei[ID == id & hydro_year %in% years]
  if (nrow(sub) == 0) return(NULL)
  setorder(sub, hydro_year)
  v <- sub[[spei_col]]
  if (length(v) != length(years)) return(NULL)
  as.numeric(v)
}

correlacionar_subcuenca <- function(ndvi_path, spei_vec, id, ndvi_label, spei_col,
                                    out_dir, base_rast = NULL) {
  cols_ndvi <- c("ID", "cell", as.character(1991:2022))
  ndvi <- fread(ndvi_path, select = cols_ndvi, showProgress = FALSE)
  n <- nrow(ndvi)
  if (n == 0) {
    log_msg("[SKIP] CSV vacio: ", ndvi_path)
    return(invisible(FALSE))
  }

  tag <- spei_tag(spei_col)
  log_msg("[INICIO] ", id, " NDVI", ndvi_label, " vs ", tag, " | ", n, " celdas")

  res_corr <- rep(NA_real_, n)
  res_pval <- rep(NA_real_, n)
  res_cell <- ndvi$cell

  t0 <- Sys.time()
  last_ping <- t0

  for (i in seq_len(n)) {
    ndvi_values <- as.numeric(ndvi[i, 3:34])
    ok <- is.finite(ndvi_values) & is.finite(spei_vec)
    if (sum(ok) >= 3) {
      ct <- suppressWarnings(cor.test(ndvi_values[ok], spei_vec[ok]))
      res_corr[i] <- unname(ct$estimate)
      res_pval[i] <- ct$p.value
    }

    now <- Sys.time()
    if (i %% PROGRESS_ROWS == 0L ||
        as.numeric(difftime(now, last_ping, units = "secs")) >= PROGRESS_SECONDS) {
      elapsed <- as.numeric(difftime(now, t0, units = "secs"))
      rate <- i / max(elapsed, 1e-6)
      eta_sec <- (n - i) / max(rate, 1e-6)
      log_msg(
        sprintf(
          "[AVANCE] %s %s | fila %s/%s (%.1f%%) | %.0f s | ETA %.1f min",
          id, tag, format(i, big.mark = "."), format(n, big.mark = "."),
          100 * i / n, elapsed, eta_sec / 60
        )
      )
      last_ping <- now
    }
  }

  res_df <- data.frame(
    ID = id,
    cell = as.integer(res_cell),
    correlation = res_corr,
    p_value = res_pval
  )

  paths <- output_paths(id, ndvi_label, tag, out_dir)
  fwrite(res_df, paths$csv)

  # Liberar NDVI y vectores grandes antes de armar matrices raster.
  rm(ndvi, res_corr, res_pval, res_cell)
  gc(verbose = FALSE)

  if (!is.null(base_rast)) {
    n_rows <- nrow(base_rast)
    n_cols <- ncol(base_rast)
    n_cells <- ncell(base_rast)
    corr_mat <- matrix(NA_real_, nrow = n_rows, ncol = n_cols)
    pval_mat <- matrix(NA_real_, nrow = n_rows, ncol = n_cols)

    ok_cells <- res_df$cell >= 1L & res_df$cell <= n_cells & is.finite(res_df$correlation)
    idx <- which(ok_cells)
    for (k in idx) {
      cell_number <- res_df$cell[k]
      row <- ceiling(cell_number / n_cols)
      col <- cell_number - (row - 1L) * n_cols
      corr_mat[row, col] <- res_df$correlation[k]
      pval_mat[row, col] <- res_df$p_value[k]
    }

    corr_r <- rast(corr_mat, extent = ext(base_rast), crs = crs(base_rast))
    pval_r <- rast(pval_mat, extent = ext(base_rast), crs = crs(base_rast))
    writeRaster(corr_r, paths$corr_tif, overwrite = TRUE)
    writeRaster(pval_r, paths$pval_tif, overwrite = TRUE)
    log_msg("[TIF] ", id, " ", tag, " exportado")
  }

  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  log_msg("[OK] ", id, " ", tag, " | ", format(n, big.mark = "."), " celdas | ", round(dt / 60, 1), " min")
  registrar_checkpoint(out_dir, id, ndvi_label, spei_col)
  invisible(TRUE)
}

run_combo <- function(ndvi_label, spei_col, out_dir, ids, base_rast = NULL,
                      use_checkpoint = TRUE, stats = NULL) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ndvi_dir <- find_ndvi_dir(ndvi_label)
  if (is.na(ndvi_dir)) {
    log_msg("[SKIP] Sin carpeta NDVI_", ndvi_label, "_est_csv")
    return(invisible(stats))
  }

  log_msg("=== Combo NDVI", ndvi_label, " vs ", spei_col, " -> ", out_dir, " ===")

  for (id in ids) {
    ndvi_path <- file.path(ndvi_dir, sprintf("NDVI_%s%s_est.csv", id, ndvi_label))
    if (!file.exists(ndvi_path)) {
      log_msg("[SKIP] No existe ", ndvi_path)
      next
    }

    val <- validar_salida_subcuenca(id, ndvi_label, spei_col, out_dir, ndvi_path, base_rast)
    if (!val$ok) {
      if (length(val$borrar) > 0L) {
        n_borr <- borrar_salidas(val$borrar)
        log_msg(
          "[CHECKPOINT] Se elimina salida invalida: ", id, " NDVI", ndvi_label, " ",
          spei_tag(spei_col), " (", val$reason, ", ", n_borr, " archivo(s))"
        )
        stats$limpiadas <- stats$limpiadas + n_borr
      }
    } else if (use_checkpoint) {
      log_msg("[CHECKPOINT] Ya listo, se omite: ", id, " NDVI", ndvi_label, " ", spei_tag(spei_col))
      stats$omitidas <- stats$omitidas + 1L
      next
    }

    spei_vec <- get_spei_vector(datos_spei, id, spei_col)
    if (is.null(spei_vec)) {
      log_msg("[SKIP] SPEI incompleto para ", id)
      next
    }

    correlacionar_subcuenca(
      ndvi_path, spei_vec, id, ndvi_label, spei_col,
      out_dir, base_rast
    )
    stats$calculadas <- stats$calculadas + 1L
  }

  invisible(stats)
}

# -------------------------- MAIN --------------------------
log_msg("\n========== Inicio ejecucion ==========")
if (USE_CHECKPOINT) {
  log_msg("[CHECKPOINT] Activo: reanuda omitiendo salidas validas (CSV+TIF, filas OK)")
  log_msg("[CHECKPOINT] Salidas incompletas/corruptas se borran y recalculan")
  log_msg("[CHECKPOINT] Registro: ", CHECKPOINT_FILE)
} else {
  log_msg("[CHECKPOINT] Desactivado (--force): se recalcula todo")
}

ruta_spei <- "datos_spei_jv.csv"
if (!file.exists(ruta_spei)) {
  stop("Falta ", ruta_spei, ". Generelo antes de correr correlaciones.")
}
datos_spei <- fread(
  ruta_spei,
  select = c("ID", "hydro_year", "SPEI12anual_est", "SPEI12sep_est", "SPEI12dic_est")
)
log_msg("[OK] SPEI: ", ruta_spei, " (", nrow(datos_spei), " filas)")

ids <- fread("ID_subcuencas.csv")$ID
log_msg("[OK] Subcuencas: ", paste(ids, collapse = ", "))

base_path <- c("base.tif", "Base.tif")[file.exists(c("base.tif", "Base.tif"))][1]
base_r <- if (!is.na(base_path)) {
  log_msg("[OK] Raster base: ", base_path)
  rast(base_path)
} else {
  log_msg("[WARN] Sin base.tif: solo se guardaran CSV")
  NULL
}

combos <- list(
  list(ndvi = "prim",  spei = "SPEI12anual_est", out = "resultados/01_NDVIprim_SPEIanual"),
  list(ndvi = "prim",  spei = "SPEI12sep_est",   out = "resultados/02_NDVIprim_SPEIsep"),
  list(ndvi = "prim",  spei = "SPEI12dic_est",   out = "resultados/03_NDVIprim_SPEIdic"),
  list(ndvi = "ver",   spei = "SPEI12anual_est", out = "resultados/01_NDVIver_SPEIanual"),
  list(ndvi = "ver",   spei = "SPEI12sep_est",   out = "resultados/02_NDVIver_SPEIsep"),
  list(ndvi = "ver",   spei = "SPEI12dic_est",   out = "resultados/03_NDVIver_SPEIdic"),
  list(ndvi = "anual", spei = "SPEI12anual_est", out = "resultados/01_NDVIanual_SPEIanual"),
  list(ndvi = "anual", spei = "SPEI12sep_est",   out = "resultados/02_NDVIanual_SPEIsep"),
  list(ndvi = "anual", spei = "SPEI12dic_est",   out = "resultados/03_NDVIanual_SPEIdic")
)

stats <- list(calculadas = 0L, omitidas = 0L, limpiadas = 0L)
all_start <- Sys.time()
for (i_cb in seq_along(combos)) {
  cb <- combos[[i_cb]]
  log_msg("\n--- Combo ", i_cb, "/", length(combos), " ---")
  stats <- run_combo(
    cb$ndvi, cb$spei, cb$out, ids, base_r,
    use_checkpoint = USE_CHECKPOINT, stats = stats
  )
}

zipfile <- "resultados_correlaciones_ndvi_spei.zip"
if (file.exists(zipfile)) file.remove(zipfile)
result_files <- list.files("resultados", recursive = TRUE, full.names = TRUE)
if (length(result_files) > 0) {
  utils::zip(zipfile, files = result_files)
  log_msg("[FIN] ZIP: ", normalizePath(zipfile, winslash = "/"))
} else {
  log_msg("[FIN] Sin archivos en resultados/; ZIP no generado")
}

log_msg(
  "[FIN] Subcuencas calculadas: ", stats$calculadas,
  " | omitidas (checkpoint): ", stats$omitidas,
  " | archivos invalidos eliminados: ", stats$limpiadas,
  " | tiempo: ",
  round(as.numeric(difftime(Sys.time(), all_start, units = "mins")), 1), " min"
)
