# ==============================================================================
# Script 3 — Depuración de outliers en las series brutas.
#
# Criterios (configurables en config.R):
#   (1) Límites físicos:
#         pp    : [0, pp_limite_superior_mm]
#         t_*   : [-50, 55] °C
#         q     : [0, +inf)
#   (2) IQR: fuera de [Q1 - k*IQR, Q3 + k*IQR]. Si IQR=0, fallback a P99.5.
#   (3) Umbral estadístico (solo pp): media + factor_sd * SD, o 100 mm/día en
#       zonas de media muy baja.
#
# Entrada: archivos *_bruta.csv en dir_brutas.
# Salida : mismos nombres en dir_depurado + resumen_outliers_depurado.csv.
# ==============================================================================

# -----------------------------------------------------------------------------
# Parseo del nombre de archivo estándar con sufijo _bruta
# -----------------------------------------------------------------------------
.parsear_nombre_serie <- function(ruta) {
  bn <- basename(ruta)
  bn <- sub("_(bruta|rellena|depurada)\\.csv$", "", bn, ignore.case = TRUE)
  # variables de series diarias: pp, q, t_max, t_min
  m <- regmatches(
    bn,
    regexec("^(.+)_(pp|q|t_max|t_min)_([0-9]+)_([0-9]{4})_([0-9]{4})$", bn)
  )[[1]]
  if (length(m) < 6) return(NULL)
  list(
    grupo      = m[2],
    variable   = m[3],
    calidad    = as.integer(m[4]),
    ano_inicio = as.integer(m[5]),
    ano_fin    = as.integer(m[6])
  )
}

# -----------------------------------------------------------------------------
# Criterios de depuración
# -----------------------------------------------------------------------------
.aplicar_limites_fisicos <- function(df, cols, variable, pp_limite_superior_mm) {
  n <- setNames(integer(length(cols)), cols)
  for (c in cols) {
    x <- df[[c]]; na_prev <- is.na(x)
    if (variable == "pp") {
      x[x < 0 | x > pp_limite_superior_mm] <- NA
    } else if (variable == "q") {
      x[x < 0] <- NA
    } else if (variable %in% c("t_max", "t_min")) {
      x[x < -50 | x > 55] <- NA
    }
    df[[c]] <- x
    n[c] <- sum(!na_prev & is.na(x))
  }
  list(df = df, n = n)
}

.aplicar_iqr <- function(df, cols, k_iqr) {
  n <- setNames(integer(length(cols)), cols)
  for (c in cols) {
    x <- df[[c]]; na_prev <- is.na(x)
    q1 <- stats::quantile(x, 0.25, na.rm = TRUE)
    q3 <- stats::quantile(x, 0.75, na.rm = TRUE)
    iqr <- q3 - q1
    if (!is.na(iqr) && iqr > 0) {
      x[x < q1 - k_iqr * iqr | x > q3 + k_iqr * iqr] <- NA
    } else {
      p995 <- stats::quantile(x, 0.995, na.rm = TRUE)
      if (!is.na(p995) && p995 > 0) x[x > p995] <- NA
    }
    df[[c]] <- x
    n[c] <- sum(!na_prev & is.na(x))
  }
  list(df = df, n = n)
}

.aplicar_umbral_estadistico <- function(df, cols, variable,
                                        umbral_pp_media_baja_mm, factor_sd) {
  n <- setNames(integer(length(cols)), cols)
  if (variable != "pp") return(list(df = df, n = n))
  for (c in cols) {
    x <- df[[c]]; na_prev <- is.na(x)
    m <- mean(x, na.rm = TRUE); s <- stats::sd(x, na.rm = TRUE)
    if (is.na(m) || length(x[!is.na(x)]) == 0) next
    if (!is.na(m) && m < 2 && m > 0) {
      x[x > umbral_pp_media_baja_mm] <- NA
    } else if (!is.na(s) && s > 0) {
      x[x > m + factor_sd * s] <- NA
    }
    df[[c]] <- x
    n[c] <- sum(!na_prev & is.na(x))
  }
  list(df = df, n = n)
}

# -----------------------------------------------------------------------------
# Depuración de un archivo individual
# -----------------------------------------------------------------------------
depurar_una_serie <- function(ruta_bruta,
                              dir_depurado,
                              usar_limites_fisicos    = TRUE,
                              usar_iqr                = TRUE,
                              usar_umbral_estadistico = TRUE,
                              k_iqr                   = 1.5,
                              pp_limite_superior_mm   = 200,
                              umbral_pp_media_baja_mm = 100,
                              factor_sd               = 10,
                              verbose                 = TRUE) {
  info <- .parsear_nombre_serie(ruta_bruta)
  if (is.null(info)) {
    warning("No se pudo parsear: ", basename(ruta_bruta), ". Se omite.")
    return(NULL)
  }
  if (!dir.exists(dir_depurado)) dir.create(dir_depurado, recursive = TRUE)

  df <- leer_csv_robusto(ruta_bruta)
  df <- normalizar_columnas_fecha(df)
  cols_est <- columnas_estaciones(df)
  if (length(cols_est) == 0) {
    warning("Sin columnas numéricas de estaciones en ", basename(ruta_bruta))
    return(NULL)
  }

  total_celdas <- nrow(df) * length(cols_est)
  na_antes     <- sum(is.na(df[, cols_est, drop = FALSE]))

  n_fis <- n_iqr <- n_est <- setNames(integer(length(cols_est)), cols_est)

  if (usar_limites_fisicos) {
    r <- .aplicar_limites_fisicos(df, cols_est, info$variable, pp_limite_superior_mm)
    df <- r$df; n_fis <- r$n
  }
  if (usar_iqr) {
    r <- .aplicar_iqr(df, cols_est, k_iqr); df <- r$df; n_iqr <- r$n
  }
  if (usar_umbral_estadistico) {
    r <- .aplicar_umbral_estadistico(df, cols_est, info$variable,
                                     umbral_pp_media_baja_mm, factor_sd)
    df <- r$df; n_est <- r$n
  }

  na_despues <- sum(is.na(df[, cols_est, drop = FALSE]))
  n_total    <- sum(n_fis) + sum(n_iqr) + sum(n_est)

  nombre_out <- nombre_archivo_estandar(info$grupo, info$variable, info$calidad,
                                        info$ano_inicio, info$ano_fin,
                                        sufijo = "_depurada")
  ruta_out <- file.path(dir_depurado, nombre_out)
  escribir_csv_robusto(df, ruta_out)

  if (verbose) {
    pct_antes   <- if (total_celdas > 0) round(100 * na_antes   / total_celdas, 2) else NA
    pct_despues <- if (total_celdas > 0) round(100 * na_despues / total_celdas, 2) else NA
    message("  ", basename(ruta_bruta), ": ", n_total, " outliers → NA",
            "  (% NA ", pct_antes, "% → ", pct_despues, "%)")
  }

  resumen <- data.frame(
    archivo  = basename(ruta_bruta),
    grupo    = info$grupo,
    variable = info$variable,
    estacion = cols_est,
    n_limites_fisicos    = as.integer(n_fis),
    n_iqr                = as.integer(n_iqr),
    n_umbral_estadistico = as.integer(n_est),
    n_total              = as.integer(n_fis + n_iqr + n_est),
    stringsAsFactors = FALSE
  )

  list(ruta_salida = ruta_out, resumen = resumen)
}

# -----------------------------------------------------------------------------
# Orquestador: depura todas las series brutas para (grupos × variables_activas).
# -----------------------------------------------------------------------------

#' Ejecutar depuración sobre todas las series brutas del proyecto.
#'
#' @param dir_brutas carpeta con los CSV _bruta.csv.
#' @param dir_depurado carpeta de salida.
#' @param variables_activas vector en {'pp','temp','q'}.
#' @param grupos vector de nombres de grupos.
#' @param calidad_por_variable named vector con umbral usado por variable.
#' @param ano_inicio,ano_fin rango.
#' @param parámetros de depuración: ver config.R.
#' @param guardar_reporte TRUE para escribir `resumen_outliers_depurado.csv`.
#' @export
ejecutar_depurado <- function(dir_brutas,
                              dir_depurado,
                              variables_activas,
                              grupos,
                              calidad_por_variable,
                              ano_inicio,
                              ano_fin,
                              usar_limites_fisicos    = TRUE,
                              usar_iqr                = TRUE,
                              usar_umbral_estadistico = TRUE,
                              k_iqr                   = 1.5,
                              pp_limite_superior_mm   = 200,
                              umbral_pp_media_baja_mm = 100,
                              factor_sd               = 10,
                              guardar_reporte         = TRUE,
                              verbose                 = TRUE) {
  if (!dir.exists(dir_brutas)) stop("No existe dir_brutas: ", dir_brutas)
  if (!dir.exists(dir_depurado)) dir.create(dir_depurado, recursive = TRUE)

  mapa_variables <- list(pp = "pp", q = "q", temp = c("t_max", "t_min"))

  resumenes <- list()
  for (grupo in grupos) {
    for (var in variables_activas) {
      cal <- calidad_por_variable[[var]]
      if (is.null(cal) || is.na(cal)) next
      for (v_serie in mapa_variables[[var]]) {
        archivo_in <- file.path(
          dir_brutas,
          nombre_archivo_estandar(grupo, v_serie, cal, ano_inicio, ano_fin,
                                  sufijo = "_bruta")
        )
        if (!file.exists(archivo_in)) {
          if (verbose) message("  (Omitido, no existe) ", basename(archivo_in))
          next
        }
        res <- depurar_una_serie(
          ruta_bruta              = archivo_in,
          dir_depurado            = dir_depurado,
          usar_limites_fisicos    = usar_limites_fisicos,
          usar_iqr                = usar_iqr,
          usar_umbral_estadistico = usar_umbral_estadistico,
          k_iqr                   = k_iqr,
          pp_limite_superior_mm   = pp_limite_superior_mm,
          umbral_pp_media_baja_mm = umbral_pp_media_baja_mm,
          factor_sd               = factor_sd,
          verbose                 = verbose
        )
        if (!is.null(res)) resumenes[[length(resumenes) + 1L]] <- res$resumen
      }
    }
  }

  if (guardar_reporte && length(resumenes) > 0) {
    resumen_global <- do.call(rbind, resumenes)
    archivo_reporte <- file.path(dir_depurado, "resumen_outliers_depurado.csv")
    escribir_csv_robusto(resumen_global, archivo_reporte)
    if (verbose) {
      message("Reporte global de outliers: ", archivo_reporte,
              " (total filas ", nrow(resumen_global), ")")
    }
  }

  invisible(dir_depurado)
}
