# ==============================================================================
# Script 4 — Imputación de faltantes con missForest (random forest no paramétrico).
#
# Lee CSVs *_depurada.csv (o *_bruta.csv si el paso 3 se omite) y escribe
# *_rellena.csv en dir_rellenas. Si missForest no logra reducir los NA
# (por ejemplo, una sola estación con todo NA), propaga la serie original.
# ==============================================================================

# Parseo de nombre compartido con 3_depurado.R (redefinido por robustez si el
# script se carga aisladamente).
.parsear_nombre_serie_mf <- function(ruta) {
  bn <- basename(ruta)
  bn <- sub("_(bruta|depurada|rellena)\\.csv$", "", bn, ignore.case = TRUE)
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

#' Rellenar una serie (data.frame) con missForest.
#'
#' @param ruta_entrada ruta al CSV de entrada (típicamente *_depurada.csv).
#' @param dir_salida carpeta destino.
#' @param ntree,maxiter parámetros de missForest.
#' @param usar_tiempo TRUE para incluir year/month/day como predictores.
#' @param verbose TRUE para imprimir progreso.
#' @return lista con la ruta de salida y el OOB error.
rellenar_una_serie_missforest <- function(ruta_entrada,
                                          dir_salida,
                                          ntree = 100,
                                          maxiter = 10,
                                          usar_tiempo = TRUE,
                                          verbose = TRUE) {
  cargar_paquete_opcional("missForest")
  if (!dir.exists(dir_salida)) dir.create(dir_salida, recursive = TRUE)

  info <- .parsear_nombre_serie_mf(ruta_entrada)
  if (is.null(info)) {
    warning("No se pudo parsear: ", basename(ruta_entrada))
    return(NULL)
  }

  df <- leer_csv_robusto(ruta_entrada)
  df <- normalizar_columnas_fecha(df)
  cols_est <- columnas_estaciones(df)
  if (length(cols_est) == 0) {
    warning("Sin columnas numéricas de estaciones en ", basename(ruta_entrada))
    return(NULL)
  }

  ruta_salida <- file.path(
    dir_salida,
    nombre_archivo_estandar(info$grupo, info$variable, info$calidad,
                            info$ano_inicio, info$ano_fin, sufijo = "_rellena")
  )

  # Si no hay NA, solo copiar.
  if (!any(is.na(df[, cols_est, drop = FALSE]))) {
    if (verbose) message("  Sin NA en ", basename(ruta_entrada), "; se copia.")
    escribir_csv_robusto(df, ruta_salida)
    return(invisible(list(ruta_salida = ruta_salida, OOBerror = NA_real_)))
  }

  xtab <- if (usar_tiempo && all(c("year", "month", "day") %in% names(df))) {
    df[, c("year", "month", "day", cols_est), drop = FALSE]
  } else {
    df[, cols_est, drop = FALSE]
  }

  res <- tryCatch(
    missForest::missForest(
      xtab, maxiter = maxiter, ntree = ntree,
      verbose = verbose, variablewise = FALSE
    ),
    error = function(e) {
      warning("missForest falló en ", basename(ruta_entrada), ": ",
              conditionMessage(e),
              "\n  Se propaga el archivo sin rellenar.")
      NULL
    }
  )

  if (is.null(res)) {
    escribir_csv_robusto(df, ruta_salida)
    return(invisible(list(ruta_salida = ruta_salida, OOBerror = NA_real_)))
  }

  # Sustituir sólo columnas de estaciones
  if (usar_tiempo && all(c("year", "month", "day") %in% names(df))) {
    df[, cols_est] <- res$ximp[, cols_est, drop = FALSE]
  } else {
    df[, cols_est] <- res$ximp
  }

  escribir_csv_robusto(df, ruta_salida)
  if (verbose && !is.null(res$OOBerror)) {
    message("  OOB error: ", paste(round(res$OOBerror, 4), collapse = ", "),
            " → ", basename(ruta_salida))
  }

  invisible(list(ruta_salida = ruta_salida, OOBerror = res$OOBerror))
}

#' Ejecutar rellenado missForest sobre las series depuradas del proyecto.
#' @export
ejecutar_rellenado_missforest <- function(dir_depuradas,
                                          dir_rellenas,
                                          variables_activas,
                                          grupos,
                                          calidad_por_variable,
                                          ano_inicio,
                                          ano_fin,
                                          ntree = 100,
                                          maxiter = 10,
                                          usar_tiempo = TRUE,
                                          verbose = TRUE) {
  if (!dir.exists(dir_depuradas)) stop("No existe dir_depuradas: ", dir_depuradas)
  if (!dir.exists(dir_rellenas)) dir.create(dir_rellenas, recursive = TRUE)

  mapa_variables <- list(pp = "pp", q = "q", temp = c("t_max", "t_min"))

  for (grupo in grupos) {
    for (var in variables_activas) {
      cal <- calidad_por_variable[[var]]
      if (is.null(cal) || is.na(cal)) next
      for (v_serie in mapa_variables[[var]]) {
        archivo_in <- file.path(
          dir_depuradas,
          nombre_archivo_estandar(grupo, v_serie, cal, ano_inicio, ano_fin,
                                  sufijo = "_depurada")
        )
        if (!file.exists(archivo_in)) {
          # Permitir fallback a *_bruta.csv si el paso 3 no se ejecutó.
          archivo_in <- file.path(
            dir_depuradas,
            nombre_archivo_estandar(grupo, v_serie, cal, ano_inicio, ano_fin,
                                    sufijo = "_bruta")
          )
          if (!file.exists(archivo_in)) {
            if (verbose) message("  (Omitido, no existe): ", basename(archivo_in))
            next
          }
        }
        rellenar_una_serie_missforest(
          ruta_entrada = archivo_in,
          dir_salida   = dir_rellenas,
          ntree        = ntree,
          maxiter      = maxiter,
          usar_tiempo  = usar_tiempo,
          verbose      = verbose
        )
      }
    }
  }

  invisible(dir_rellenas)
}
