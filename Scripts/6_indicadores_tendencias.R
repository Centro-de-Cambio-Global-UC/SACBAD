# ==============================================================================
# Script 6 — Indicadores climáticos y tendencias decadales.
#
# Consume las series ya generadas por los pasos 4 (diarias rellenas), 5
# (mensuales) y 5.1 (anuales) de este mismo pipeline y calcula un set
# configurable de indicadores climáticos, además de resumir tendencias a
# escala decadal.
#
# Estructura interna (tres bloques):
#   A) preprocesar_series_para_indicadores()  — lectura + normalización.
#   B) calcular_indicadores()                 — delegador + sub-funciones.
#   C) calcular_tendencias_decadales()        — agregación por década + MK.
#
# Salidas:
#   <dir_output_proyecto>/indicadores/{grupo}_{indicador}_{calidad}_{ini}_{fin}.csv
#   <dir_output_proyecto>/tendencias_decadales/{grupo}_{indicador}_{calidad}_{ini}_{fin}_decadal.csv
#
# Dependencias opcionales (se instalan/cargan sólo si el indicador está activo):
#   trend (mk.test, sens.slope), SPEI (spi, spei, hargreaves, thornthwaite)
# ==============================================================================

# -----------------------------------------------------------------------------
# Helpers internos
# -----------------------------------------------------------------------------

.mapa_var_serie <- list(
  pp   = "pp",
  q    = "q",
  temp = c("t_max", "t_min")
)

.variables_a_series <- function(variables_activas) {
  unlist(.mapa_var_serie[intersect(variables_activas, names(.mapa_var_serie))],
         use.names = FALSE)
}

.ruta_serie <- function(dir_raiz, grupo, v_serie, calidad, ano_inicio, ano_fin,
                        sufijo) {
  if (is.null(dir_raiz) || !dir.exists(dir_raiz)) return(NA_character_)
  r <- file.path(
    dir_raiz,
    nombre_archivo_estandar(grupo, v_serie, calidad, ano_inicio, ano_fin,
                            sufijo = sufijo)
  )
  if (file.exists(r)) r else NA_character_
}

.cargar_serie_csv <- function(ruta) {
  if (is.na(ruta) || !file.exists(ruta)) return(NULL)
  df <- leer_csv_robusto(ruta)
  df <- tryCatch(normalizar_columnas_fecha(df), error = function(e) df)
  df
}

.decada_de <- function(year) as.integer(year) - (as.integer(year) %% 10L)

#' Resumen robusto del test Mann-Kendall sobre una serie numérica.
#' Devuelve lista con tau, p_value, significativo (<0.05) y dirección.
.mk_summary <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x) < 4 || stats::var(x, na.rm = TRUE) == 0) {
    return(list(tau = NA_real_, p_value = NA_real_,
                significativo = NA, direccion = "indeterminado"))
  }
  res <- tryCatch(trend::mk.test(x),
                  error = function(e) NULL)
  if (is.null(res)) {
    return(list(tau = NA_real_, p_value = NA_real_,
                significativo = NA, direccion = "indeterminado"))
  }
  tau <- unname(res$estimates["tau"])
  p <- unname(res$p.value)
  direccion <- if (is.na(tau)) "indeterminado" else
    if (tau > 0) "creciente" else if (tau < 0) "decreciente" else "sin_cambio"
  list(tau = tau, p_value = p,
       significativo = isTRUE(p < 0.05), direccion = direccion)
}

#' Pendiente Sen (en unidades/tiempo) con intervalo 95%.
.sen_summary <- function(x) {
  x <- as.numeric(x)
  if (sum(is.finite(x)) < 4) {
    return(list(slope = NA_real_, lower = NA_real_, upper = NA_real_))
  }
  res <- tryCatch(trend::sens.slope(x[is.finite(x)]),
                  error = function(e) NULL)
  if (is.null(res)) {
    return(list(slope = NA_real_, lower = NA_real_, upper = NA_real_))
  }
  ci <- res$conf.int
  list(slope = unname(res$estimates),
       lower = if (!is.null(ci)) ci[1] else NA_real_,
       upper = if (!is.null(ci)) ci[2] else NA_real_)
}

#' Intenta resolver latitudes por estación cuando están disponibles,
#' ya sea desde dir_estaciones (metadata canónica) o desde el archivo
#' fuente de un grupo con modo='archivo'. Devuelve vector nombrado
#' codigo_nacional → latitud numérica (o NULL si no hay metadata).
.resolver_latitudes <- function(grupo, dir_estaciones, calidad_por_variable,
                                ano_inicio, ano_fin) {
  posibles <- list()
  for (v in c("pp", "temp", "q")) {
    # R >= 4.x: `v[[\"q\"]]` en vector sin nombre \"q\" lanza error (no devuelve NULL).
    cal <- if (v %in% names(calidad_por_variable)) calidad_por_variable[[v]] else NULL
    if (is.null(cal) || (length(cal) == 1L && is.na(cal))) next
    r <- resolver_ruta_estaciones(
      dir_estaciones = dir_estaciones,
      grupo          = grupo$nombre,
      variable       = v,
      calidad        = cal,
      ano_inicio     = ano_inicio,
      ano_fin        = ano_fin
    )
    if (!is.null(r)) posibles[[length(posibles) + 1L]] <- r
  }
  if (identical(grupo$modo, "archivo") && !is.null(grupo$archivo_fuente) &&
      file.exists(grupo$archivo_fuente)) {
    posibles[[length(posibles) + 1L]] <- grupo$archivo_fuente
  }

  for (ruta in posibles) {
    df <- tryCatch(leer_csv_autodetect(ruta), error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0) next
    nombres_norm <- tolower(trimws(names(df)))
    col_cod <- which(nombres_norm %in% c("codigo_nacional", "codigo", "cod"))
    col_lat <- which(nombres_norm %in% c("latitud", "lat", "latitude"))
    if (length(col_cod) == 0 || length(col_lat) == 0) next
    codigos <- as.character(df[[col_cod[1]]])
    lats <- suppressWarnings(as.numeric(
      gsub(",", ".", as.character(df[[col_lat[1]]]))
    ))
    ok <- !is.na(codigos) & nzchar(codigos) & is.finite(lats)
    if (!any(ok)) next
    out <- lats[ok]
    names(out) <- trimws(codigos[ok])
    return(out)
  }
  NULL
}

# =============================================================================
# BLOQUE A — PREPROCESAMIENTO
# =============================================================================

#' Carga y normaliza todas las series necesarias para el cálculo de
#' indicadores, agrupadas por (grupo, variable de serie).
#'
#' Para cada grupo y cada variable de serie (pp, t_max, t_min, q) busca:
#'   - diaria:  dir_rellenas / {grupo}_{v}_{cal}_{ini}_{fin}_rellena.csv
#'   - mensual: dir_mensual  / {grupo}_{v}_{cal}_{ini}_{fin}_mensual.csv
#'   - anual:   dir_anual    / {grupo}_{v}_{cal}_{ini}_{fin}_anual.csv
#'
#' Calcula además una tabla de anomalías mensuales respecto al período de
#' referencia (media climatológica por mes-calendario dentro de ese período).
#'
#' @param dir_rellenas,dir_mensual,dir_anual rutas raíz de series rellenas /
#'   mensuales / anuales del pipeline (pasos 4/5).
#' @param grupos_estaciones lista de grupos (como en el config).
#' @param variables_activas vector con subconjunto de c("pp","temp","q").
#' @param calidad_por_variable vector nombrado de umbrales de calidad.
#' @param ano_inicio,ano_fin rango inclusivo del análisis.
#' @param periodo_referencia vector c(ref_ini, ref_fin) para anomalías.
#' @param dir_estaciones carpeta de metadata de estaciones (opcional, para lat).
#'
#' @return lista anidada `res[[grupo]][[v_serie]]` con componentes
#'   `diaria`, `mensual`, `anual`, `anomalias_mensual` (data.frames o NULL),
#'   más `res[[grupo]]$meta$latitudes` (vector nombrado) y
#'   `res[[grupo]]$meta$calidades` (vector nombrado v_serie → calidad).
#' @export
preprocesar_series_para_indicadores <- function(dir_rellenas,
                                                dir_mensual,
                                                dir_anual,
                                                grupos_estaciones,
                                                variables_activas,
                                                calidad_por_variable,
                                                ano_inicio,
                                                ano_fin,
                                                periodo_referencia = NULL,
                                                dir_estaciones = NULL,
                                                verbose = TRUE) {
  if (!is.null(periodo_referencia)) {
    stopifnot(length(periodo_referencia) == 2L,
              periodo_referencia[1] <= periodo_referencia[2])
    if (periodo_referencia[1] < ano_inicio ||
        periodo_referencia[2] > ano_fin) {
      warning("periodo_referencia (", periodo_referencia[1], "-",
              periodo_referencia[2], ") excede ano_inicio:ano_fin (",
              ano_inicio, "-", ano_fin, "). Se recortará al rango disponible.")
    }
  }
  ref <- if (is.null(periodo_referencia)) c(ano_inicio, ano_fin) else
    c(max(ano_inicio, periodo_referencia[1]),
      min(ano_fin,    periodo_referencia[2]))

  vars_serie <- .variables_a_series(variables_activas)
  out <- list()

  for (grupo in grupos_estaciones) {
    if (verbose) message("[6/A] Preprocesando grupo: ", grupo$nombre)
    entrada_grupo <- list()
    calidades <- stats::setNames(integer(0), character(0))

    for (v_serie in vars_serie) {
      var_logica <- if (v_serie %in% c("t_max", "t_min")) "temp" else v_serie
      cal <- if (var_logica %in% names(calidad_por_variable))
        calidad_por_variable[[var_logica]] else NULL
      if (is.null(cal) || (length(cal) == 1L && is.na(cal))) next
      calidades[v_serie] <- as.integer(cal)

      r_dia <- .ruta_serie(dir_rellenas, grupo$nombre, v_serie, cal,
                           ano_inicio, ano_fin, sufijo = "_rellena")
      r_men <- .ruta_serie(dir_mensual,  grupo$nombre, v_serie, cal,
                           ano_inicio, ano_fin, sufijo = "_mensual")
      r_anu <- .ruta_serie(dir_anual,    grupo$nombre, v_serie, cal,
                           ano_inicio, ano_fin, sufijo = "_anual")

      diaria  <- .cargar_serie_csv(r_dia)
      mensual <- .cargar_serie_csv(r_men)
      anual   <- .cargar_serie_csv(r_anu)

      # Validación de completitud (sólo advertencia, no bloquea)
      if (!is.null(diaria)) {
        years_presentes <- sort(unique(diaria$year))
        esperados <- seq.int(ano_inicio, ano_fin)
        faltantes <- setdiff(esperados, years_presentes)
        if (length(faltantes) > 0 && verbose) {
          message("  (", grupo$nombre, "/", v_serie,
                  ") años faltantes en diaria: ",
                  paste(faltantes, collapse = ","))
        }
      }

      # Anomalías mensuales vs climatología del período de referencia.
      anom_mensual <- NULL
      if (!is.null(mensual)) {
        cols_est <- columnas_estaciones(mensual)
        if (length(cols_est) > 0) {
          base_ref <- mensual[mensual$year >= ref[1] &
                              mensual$year <= ref[2], , drop = FALSE]
          if (nrow(base_ref) > 0) {
            clim <- stats::aggregate(
              base_ref[, cols_est, drop = FALSE],
              by = list(month = base_ref$month),
              FUN = function(v) mean(v, na.rm = TRUE)
            )
            anom <- mensual
            for (c in cols_est) {
              m_clim <- stats::setNames(clim[[c]], clim$month)
              anom[[c]] <- mensual[[c]] - m_clim[as.character(mensual$month)]
            }
            anom_mensual <- anom
          }
        }
      }

      entrada_grupo[[v_serie]] <- list(
        diaria           = diaria,
        mensual          = mensual,
        anual            = anual,
        anomalias_mensual = anom_mensual
      )
    }

    latitudes <- NULL
    if (!is.null(dir_estaciones)) {
      latitudes <- tryCatch(
        .resolver_latitudes(grupo, dir_estaciones, calidad_por_variable,
                            ano_inicio, ano_fin),
        error = function(e) NULL
      )
      if (!is.null(latitudes) && verbose) {
        message("  (", grupo$nombre, ") latitudes resueltas para ",
                length(latitudes), " estaciones.")
      }
    }

    entrada_grupo$meta <- list(
      grupo             = grupo$nombre,
      calidades         = calidades,
      ano_inicio        = ano_inicio,
      ano_fin           = ano_fin,
      periodo_referencia = ref,
      latitudes         = latitudes
    )
    out[[grupo$nombre]] <- entrada_grupo
  }

  out
}

# =============================================================================
# BLOQUE B — INDICADORES CLIMÁTICOS
# =============================================================================

#' Mann-Kendall por estación sobre la serie temporal configurada.
#' @param series_procesadas salida de `preprocesar_series_para_indicadores()`.
#' @param variables_activas subconjunto de c("pp","temp","q").
#' @param escala "anual" o "mensual" — determina la serie de entrada.
#' @return data.frame long con columnas:
#'   grupo, variable, estacion, n, tau, p_value, significativo,
#'   tendencia_direccion, escala.
#' @export
calcular_mann_kendall <- function(series_procesadas, variables_activas,
                                  escala = c("anual", "mensual")) {
  escala <- match.arg(escala)
  filas <- list()
  for (grupo in names(series_procesadas)) {
    paquete <- series_procesadas[[grupo]]
    vars_serie <- setdiff(names(paquete), "meta")
    for (v_serie in vars_serie) {
      df <- if (escala == "anual") paquete[[v_serie]]$anual
            else                    paquete[[v_serie]]$mensual
      if (is.null(df)) next
      cols_est <- columnas_estaciones(df)
      for (est in cols_est) {
        mk <- .mk_summary(df[[est]])
        filas[[length(filas) + 1L]] <- data.frame(
          grupo                = grupo,
          variable             = v_serie,
          estacion             = est,
          n                    = sum(is.finite(df[[est]])),
          tau                  = mk$tau,
          p_value              = mk$p_value,
          significativo        = mk$significativo,
          tendencia_direccion  = mk$direccion,
          escala               = escala,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(filas) == 0) return(data.frame())
  do.call(rbind, filas)
}

#' Pendiente Theil-Sen por estación, expresada en unidades/década.
#' @export
calcular_theil_sen <- function(series_procesadas, variables_activas,
                               escala = c("anual", "mensual")) {
  escala <- match.arg(escala)
  factor_decada <- if (escala == "anual") 10 else 120  # pasos por década
  filas <- list()
  for (grupo in names(series_procesadas)) {
    paquete <- series_procesadas[[grupo]]
    vars_serie <- setdiff(names(paquete), "meta")
    for (v_serie in vars_serie) {
      df <- if (escala == "anual") paquete[[v_serie]]$anual
            else                    paquete[[v_serie]]$mensual
      if (is.null(df)) next
      cols_est <- columnas_estaciones(df)
      for (est in cols_est) {
        s <- .sen_summary(df[[est]])
        filas[[length(filas) + 1L]] <- data.frame(
          grupo          = grupo,
          variable       = v_serie,
          estacion       = est,
          escala         = escala,
          sen_slope      = s$slope,
          sen_por_decada = s$slope * factor_decada,
          sen_ci_lower   = s$lower,
          sen_ci_upper   = s$upper,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(filas) == 0) return(data.frame())
  do.call(rbind, filas)
}

# -----------------------------------------------------------------------------
# Helpers para extremos (rachas, ventana móvil)
# -----------------------------------------------------------------------------

.max_racha <- function(condicion) {
  # Mayor número de TRUE consecutivos. NA se tratan como FALSE.
  x <- as.logical(condicion)
  x[is.na(x)] <- FALSE
  if (!any(x)) return(0L)
  r <- rle(x)
  max(r$lengths[r$values], 0L)
}

.rolling_sum <- function(x, k) {
  x <- as.numeric(x)
  n <- length(x)
  if (n < k) return(rep(NA_real_, n))
  cs <- cumsum(ifelse(is.na(x), 0, x))
  res <- rep(NA_real_, n)
  for (i in seq.int(k, n)) {
    ini <- i - k + 1L
    res[i] <- cs[i] - if (ini == 1L) 0 else cs[ini - 1L]
  }
  res
}

.spell_count <- function(condicion, min_len = 6L) {
  # Total de días que pertenecen a rachas >= min_len (WSDI/CSDI).
  x <- as.logical(condicion)
  x[is.na(x)] <- FALSE
  if (!any(x)) return(0L)
  r <- rle(x)
  sum(r$lengths[r$values & r$lengths >= min_len])
}

#' Extremos de precipitación por estación-año (ETCCDI adaptados).
#' Indicadores: Rx1day, Rx5day, PRCPTOT, R95p, R99p, CDD, CWD, SDII.
#' Los percentiles se calculan sobre los días húmedos del período de
#' referencia (`meta$periodo_referencia`) por estación.
#' @export
calcular_extremos_pp <- function(series_procesadas) {
  filas <- list()
  for (grupo in names(series_procesadas)) {
    paquete <- series_procesadas[[grupo]]
    pp <- paquete$pp$diaria
    if (is.null(pp)) next
    meta <- paquete$meta
    ref <- meta$periodo_referencia
    cols_est <- columnas_estaciones(pp)

    for (est in cols_est) {
      x_all <- as.numeric(pp[[est]])
      ref_mask <- pp$year >= ref[1] & pp$year <= ref[2]
      x_ref <- x_all[ref_mask & x_all >= 1 & is.finite(x_all)]
      p95 <- if (length(x_ref) >= 30)
        stats::quantile(x_ref, 0.95, na.rm = TRUE, names = FALSE) else NA_real_
      p99 <- if (length(x_ref) >= 30)
        stats::quantile(x_ref, 0.99, na.rm = TRUE, names = FALSE) else NA_real_

      for (yr in sort(unique(pp$year))) {
        idx <- which(pp$year == yr)
        x <- x_all[idx]
        humedo <- x >= 1 & is.finite(x)
        seco   <- x < 1 & is.finite(x)

        prcptot <- sum(x[humedo], na.rm = TRUE)
        sdii <- if (any(humedo)) prcptot / sum(humedo) else NA_real_
        rx1   <- if (all(!is.finite(x))) NA_real_ else max(x, na.rm = TRUE)
        rx5v  <- .rolling_sum(x, 5)
        rx5   <- if (all(!is.finite(rx5v))) NA_real_ else max(rx5v, na.rm = TRUE)
        r95p  <- if (is.na(p95)) NA_real_ else sum(x[is.finite(x) & x > p95])
        r99p  <- if (is.na(p99)) NA_real_ else sum(x[is.finite(x) & x > p99])
        cdd   <- .max_racha(seco)
        cwd   <- .max_racha(humedo)

        filas[[length(filas) + 1L]] <- data.frame(
          grupo = grupo, estacion = est, year = yr,
          Rx1day = rx1, Rx5day = rx5, PRCPTOT = prcptot,
          R95p = r95p, R99p = r99p, CDD = cdd, CWD = cwd, SDII = sdii,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(filas) == 0) return(data.frame())
  do.call(rbind, filas)
}

#' Extremos de temperatura por estación-año.
#' Indicadores: TXx, TNn, TX90p (%), TN10p (%), DTR, WSDI, CSDI.
#' Los percentiles TX90/TN10 se calculan sobre el período de referencia por
#' estación (percentil calendario anual, no por día-del-año para simplicidad).
#' @export
calcular_extremos_temp <- function(series_procesadas) {
  filas <- list()
  for (grupo in names(series_procesadas)) {
    paquete <- series_procesadas[[grupo]]
    tx <- paquete$t_max$diaria
    tn <- paquete$t_min$diaria
    if (is.null(tx) && is.null(tn)) next
    meta <- paquete$meta
    ref <- meta$periodo_referencia

    # Conjunto común de estaciones (cuando ambas disponibles)
    cols_tx <- if (!is.null(tx)) columnas_estaciones(tx) else character(0)
    cols_tn <- if (!is.null(tn)) columnas_estaciones(tn) else character(0)
    cols_comunes <- union(cols_tx, cols_tn)

    for (est in cols_comunes) {
      x_tx <- if (est %in% cols_tx) as.numeric(tx[[est]]) else NULL
      x_tn <- if (est %in% cols_tn) as.numeric(tn[[est]]) else NULL
      years_tx <- if (!is.null(x_tx)) tx$year else NULL
      years_tn <- if (!is.null(x_tn)) tn$year else NULL

      p90 <- if (!is.null(x_tx)) {
        ok <- is.finite(x_tx) & years_tx >= ref[1] & years_tx <= ref[2]
        if (sum(ok) >= 30)
          stats::quantile(x_tx[ok], 0.90, na.rm = TRUE, names = FALSE)
        else NA_real_
      } else NA_real_
      p10 <- if (!is.null(x_tn)) {
        ok <- is.finite(x_tn) & years_tn >= ref[1] & years_tn <= ref[2]
        if (sum(ok) >= 30)
          stats::quantile(x_tn[ok], 0.10, na.rm = TRUE, names = FALSE)
        else NA_real_
      } else NA_real_

      años_unicos <- sort(unique(c(years_tx, years_tn)))
      for (yr in años_unicos) {
        tx_y <- if (!is.null(x_tx)) x_tx[years_tx == yr] else numeric(0)
        tn_y <- if (!is.null(x_tn)) x_tn[years_tn == yr] else numeric(0)

        TXx <- if (length(tx_y) && any(is.finite(tx_y)))
          max(tx_y, na.rm = TRUE) else NA_real_
        TNn <- if (length(tn_y) && any(is.finite(tn_y)))
          min(tn_y, na.rm = TRUE) else NA_real_
        TX90p <- if (!is.na(p90) && length(tx_y)) {
          n_ok <- sum(is.finite(tx_y))
          if (n_ok == 0) NA_real_ else
            100 * sum(is.finite(tx_y) & tx_y > p90) / n_ok
        } else NA_real_
        TN10p <- if (!is.na(p10) && length(tn_y)) {
          n_ok <- sum(is.finite(tn_y))
          if (n_ok == 0) NA_real_ else
            100 * sum(is.finite(tn_y) & tn_y < p10) / n_ok
        } else NA_real_
        DTR <- if (length(tx_y) && length(tn_y) &&
                   length(tx_y) == length(tn_y)) {
          mean(tx_y - tn_y, na.rm = TRUE)
        } else NA_real_
        WSDI <- if (!is.na(p90) && length(tx_y))
          .spell_count(tx_y > p90, min_len = 6L) else NA_integer_
        CSDI <- if (!is.na(p10) && length(tn_y))
          .spell_count(tn_y < p10, min_len = 6L) else NA_integer_

        filas[[length(filas) + 1L]] <- data.frame(
          grupo = grupo, estacion = est, year = yr,
          TXx = TXx, TNn = TNn, TX90p = TX90p, TN10p = TN10p,
          DTR = DTR, WSDI = WSDI, CSDI = CSDI,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(filas) == 0) return(data.frame())
  do.call(rbind, filas)
}

# -----------------------------------------------------------------------------
# SPI / SPEI
# -----------------------------------------------------------------------------

#' Post-proceso de vectores SPI/SPEI tras `SPEI::spi()` / `SPEI::spei()`.
#'
#' El ajuste (p. ej. Gamma / log-logística) y la transformación a índice
#' normal pueden producir **Inf** o **-Inf** cuando la probabilidad acumulada
#' cae exactamente en 0 o 1 (colas muy extremas o problemas numéricos).
#' Eso es matemáticamente coherente pero poco útil en CSV, GIS o regresiones.
#'
#' @param x vector numérico (salida `as.numeric(obj$fitted)`).
#' @param tratar `"cap"` recorta a `[-limite, limite]` (incluye sustituir
#'   `±Inf` por `±limite`); `"na"` pone `NA` en no finitos; `"none"` no altera.
#' @param limite borde absoluto positivo (típico **4**, habitual en tabulaciones
#'   SPI/SPEI).
#' @keywords internal
.sanear_indice_spi_spei <- function(x,
                                    tratar = c("cap", "na", "none"),
                                    limite = 4) {
  tratar <- match.arg(tratar)
  x <- as.numeric(x)
  if (tratar == "none") return(x)
  if (tratar == "na") {
    x[!is.finite(x)] <- NA_real_
    return(x)
  }
  lim <- abs(as.numeric(limite))
  if (!is.finite(lim) || lim <= 0) return(x)
  x[which(x == Inf | x > lim)] <- lim
  x[which(x == -Inf | x < -lim)] <- -lim
  x
}

#' SPI por estación y escala temporal (meses). Requiere serie mensual de pp.
#' @param escalas vector numérico de escalas (en meses). Ej: c(3, 6, 12).
#' @param tratar_no_finitos `"cap"`, `"na"` o `"none"` (ver
#'   `.sanear_indice_spi_spei()`); todo sin datos externos.
#' @param limite_extremos borde para `tratar = "cap"`.
#' @return lista con $long (data.frame long: grupo, estacion, fecha,
#'   escala, spi) y $wide_por_escala (lista nombrada por "spi_<escala>").
#' @export
calcular_spi <- function(series_procesadas, escalas = c(3, 6, 12),
                         tratar_no_finitos = "cap",
                         limite_extremos = 4) {
  cargar_paquete_opcional("SPEI")
  long_rows <- list()
  wide_out <- list()

  tr_spi <- tolower(as.character(tratar_no_finitos %||% "cap"))
  if (!tr_spi %in% c("cap", "na", "none")) tr_spi <- "cap"

  for (grupo in names(series_procesadas)) {
    paquete <- series_procesadas[[grupo]]
    mensual <- paquete$pp$mensual
    if (is.null(mensual)) next
    cols_est <- columnas_estaciones(mensual)
    if (length(cols_est) == 0) next

    mensual <- mensual[order(mensual$year, mensual$month), , drop = FALSE]
    fechas <- as.Date(sprintf("%04d-%02d-01", mensual$year, mensual$month))

    for (esc in escalas) {
      wide_esc <- data.frame(
        fecha = fechas, year = mensual$year, month = mensual$month,
        stringsAsFactors = FALSE
      )
      for (est in cols_est) {
        serie <- stats::ts(mensual[[est]], frequency = 12,
                           start = c(mensual$year[1], mensual$month[1]))
        sp <- tryCatch(
          suppressWarnings(SPEI::spi(serie, scale = as.integer(esc),
                                     na.rm = TRUE)),
          error = function(e) NULL
        )
        vals <- if (is.null(sp)) rep(NA_real_, nrow(mensual))
                else as.numeric(sp$fitted)
        vals <- .sanear_indice_spi_spei(vals, tr_spi, limite_extremos)
        wide_esc[[est]] <- vals
        long_rows[[length(long_rows) + 1L]] <- data.frame(
          grupo = grupo, estacion = est, fecha = fechas,
          escala = as.integer(esc), spi = vals,
          stringsAsFactors = FALSE
        )
      }
      key <- paste0("spi_", esc, "__", grupo)
      wide_out[[key]] <- wide_esc
    }
  }

  list(
    long = if (length(long_rows)) do.call(rbind, long_rows) else data.frame(),
    wide_por_escala = wide_out
  )
}

#' SPEI por estación y escala temporal. Requiere serie mensual de pp Y temp
#' (y latitud por estación para calcular ETP con Hargreaves/Thornthwaite).
#' Si no hay latitudes o temp, retorna lista vacía con warning.
#' @param escalas vector numérico de escalas (meses).
#' @param metodo_etp "hargreaves" o "thornthwaite".
#' @param tratar_no_finitos `"cap"`, `"na"` o `"none"` (igual que en SPI).
#' @param limite_extremos borde para `tratar = "cap"`.
#' @export
calcular_spei <- function(series_procesadas, escalas = c(3, 6, 12),
                          metodo_etp = c("hargreaves", "thornthwaite"),
                          tratar_no_finitos = "cap",
                          limite_extremos = 4) {
  metodo_etp <- match.arg(metodo_etp)
  cargar_paquete_opcional("SPEI")
  long_rows <- list()
  wide_out <- list()

  tr_spei <- tolower(as.character(tratar_no_finitos %||% "cap"))
  if (!tr_spei %in% c("cap", "na", "none")) tr_spei <- "cap"

  for (grupo in names(series_procesadas)) {
    paquete <- series_procesadas[[grupo]]
    mensual_pp  <- paquete$pp$mensual
    mensual_tx  <- paquete$t_max$mensual
    mensual_tn  <- paquete$t_min$mensual
    latitudes   <- paquete$meta$latitudes

    if (is.null(mensual_pp) || is.null(mensual_tx) || is.null(mensual_tn)) {
      warning("SPEI [", grupo,
              "]: requieren mensuales de pp, t_max y t_min. Se omite.")
      next
    }
    if (is.null(latitudes) || length(latitudes) == 0) {
      warning("SPEI [", grupo,
              "]: no se resolvieron latitudes por estación. Se omite.")
      next
    }

    # Alinear los tres data.frames por (year, month)
    key <- paste(mensual_pp$year, mensual_pp$month, sep = "-")
    ktx <- paste(mensual_tx$year, mensual_tx$month, sep = "-")
    ktn <- paste(mensual_tn$year, mensual_tn$month, sep = "-")
    comunes <- Reduce(intersect, list(key, ktx, ktn))
    if (length(comunes) == 0) next
    mensual_pp <- mensual_pp[key %in% comunes, , drop = FALSE]
    mensual_tx <- mensual_tx[ktx %in% comunes, , drop = FALSE]
    mensual_tn <- mensual_tn[ktn %in% comunes, , drop = FALSE]
    mensual_pp <- mensual_pp[order(mensual_pp$year, mensual_pp$month), ]
    mensual_tx <- mensual_tx[order(mensual_tx$year, mensual_tx$month), ]
    mensual_tn <- mensual_tn[order(mensual_tn$year, mensual_tn$month), ]

    fechas <- as.Date(sprintf("%04d-%02d-01",
                              mensual_pp$year, mensual_pp$month))
    cols_est <- intersect(
      intersect(columnas_estaciones(mensual_pp),
                columnas_estaciones(mensual_tx)),
      columnas_estaciones(mensual_tn)
    )
    cols_est <- cols_est[cols_est %in% names(latitudes)]
    if (length(cols_est) == 0) {
      warning("SPEI [", grupo,
              "]: ninguna estación con pp, t_max, t_min y latitud conocida.")
      next
    }

    # Water balance por estación
    wb_list <- list()
    for (est in cols_est) {
      lat <- unname(latitudes[est])
      ts_tx <- stats::ts(mensual_tx[[est]], frequency = 12,
                         start = c(mensual_tx$year[1], mensual_tx$month[1]))
      ts_tn <- stats::ts(mensual_tn[[est]], frequency = 12,
                         start = c(mensual_tn$year[1], mensual_tn$month[1]))
      ts_pp <- stats::ts(mensual_pp[[est]], frequency = 12,
                         start = c(mensual_pp$year[1], mensual_pp$month[1]))
      pet <- tryCatch({
        if (metodo_etp == "hargreaves") {
          SPEI::hargreaves(Tmin = ts_tn, Tmax = ts_tx, lat = lat)
        } else {
          tmed <- (ts_tx + ts_tn) / 2
          SPEI::thornthwaite(Tave = tmed, lat = lat)
        }
      }, error = function(e) NULL)
      if (is.null(pet)) next
      wb_list[[est]] <- ts_pp - pet
    }

    if (length(wb_list) == 0) next

    for (esc in escalas) {
      wide_esc <- data.frame(
        fecha = fechas, year = mensual_pp$year, month = mensual_pp$month,
        stringsAsFactors = FALSE
      )
      for (est in names(wb_list)) {
        sp <- tryCatch(
          suppressWarnings(SPEI::spei(wb_list[[est]], scale = as.integer(esc),
                                      na.rm = TRUE)),
          error = function(e) NULL
        )
        vals <- if (is.null(sp)) rep(NA_real_, length(fechas))
                else as.numeric(sp$fitted)
        vals <- .sanear_indice_spi_spei(vals, tr_spei, limite_extremos)
        wide_esc[[est]] <- vals
        long_rows[[length(long_rows) + 1L]] <- data.frame(
          grupo = grupo, estacion = est, fecha = fechas,
          escala = as.integer(esc), spei = vals,
          stringsAsFactors = FALSE
        )
      }
      wide_out[[paste0("spei_", esc, "__", grupo)]] <- wide_esc
    }
  }

  list(
    long = if (length(long_rows)) do.call(rbind, long_rows) else data.frame(),
    wide_por_escala = wide_out
  )
}

# -----------------------------------------------------------------------------
# Exportación
# -----------------------------------------------------------------------------

#' Exporta la lista de resultados a CSVs siguiendo la convención del proyecto:
#'   {grupo}_{indicador}_{calidad}_{ini}_{fin}.csv
#' @param resultados salida de `calcular_indicadores()`.
#' @param dir_salida carpeta destino.
#' @param series_procesadas pasado para recuperar metadata (calidades, período).
#' @keywords internal
exportar_indicadores <- function(resultados, dir_salida, series_procesadas) {
  if (!dir.exists(dir_salida)) dir.create(dir_salida, recursive = TRUE)

  # Detectar (ini, fin, calidad_por_grupo_y_var) desde meta
  meta_por_grupo <- lapply(series_procesadas, function(x) x$meta)

  .cal_grupo <- function(grupo, variables) {
    cals <- meta_por_grupo[[grupo]]$calidades
    cals <- cals[names(cals) %in% variables]
    if (length(cals) == 0) return(NA_integer_)
    # Elegimos el mínimo como representativo del archivo agregado
    min(cals)
  }

  ini <- meta_por_grupo[[1]]$ano_inicio
  fin <- meta_por_grupo[[1]]$ano_fin

  escribir <- function(df, grupo, etiqueta, cal) {
    if (is.null(df) || nrow(df) == 0) return(invisible(NULL))
    nombre <- nombre_archivo_estandar(grupo, etiqueta, cal, ini, fin)
    escribir_csv_robusto(df, file.path(dir_salida, nombre))
    message("  → ", nombre)
  }

  # Mann-Kendall y Sen: un CSV por grupo (filas separadas por variable)
  if (!is.null(resultados$mk) && nrow(resultados$mk) > 0) {
    for (g in unique(resultados$mk$grupo)) {
      sub <- resultados$mk[resultados$mk$grupo == g, , drop = FALSE]
      cal <- .cal_grupo(g, unique(sub$variable))
      escribir(sub, g, "mann_kendall", cal)
    }
  }
  if (!is.null(resultados$sen) && nrow(resultados$sen) > 0) {
    for (g in unique(resultados$sen$grupo)) {
      sub <- resultados$sen[resultados$sen$grupo == g, , drop = FALSE]
      cal <- .cal_grupo(g, unique(sub$variable))
      escribir(sub, g, "theil_sen", cal)
    }
  }

  if (!is.null(resultados$extremos_pp) && nrow(resultados$extremos_pp) > 0) {
    for (g in unique(resultados$extremos_pp$grupo)) {
      sub <- resultados$extremos_pp[resultados$extremos_pp$grupo == g, ,
                                    drop = FALSE]
      cal <- .cal_grupo(g, "pp")
      escribir(sub, g, "extremos_pp", cal)
    }
  }

  if (!is.null(resultados$extremos_temp) && nrow(resultados$extremos_temp) > 0) {
    for (g in unique(resultados$extremos_temp$grupo)) {
      sub <- resultados$extremos_temp[resultados$extremos_temp$grupo == g, ,
                                      drop = FALSE]
      cal <- .cal_grupo(g, c("t_max", "t_min"))
      escribir(sub, g, "extremos_temp", cal)
    }
  }

  for (idx in c("spi", "spei")) {
    res <- resultados[[idx]]
    if (is.null(res) || length(res) == 0) next
    long_df <- res$long
    if (!is.null(long_df) && nrow(long_df) > 0) {
      for (g in unique(long_df$grupo)) {
        sub <- long_df[long_df$grupo == g, , drop = FALSE]
        cal <- .cal_grupo(g, if (idx == "spi") "pp" else c("pp", "t_max", "t_min"))
        escribir(sub, g, paste0(idx, "_long"), cal)
      }
    }
    # Wide por escala × grupo
    for (nm in names(res$wide_por_escala)) {
      partes <- strsplit(nm, "__", fixed = TRUE)[[1]]
      etq <- partes[1]
      g   <- partes[2]
      cal <- .cal_grupo(g, if (idx == "spi") "pp" else c("pp", "t_max", "t_min"))
      escribir(res$wide_por_escala[[nm]], g, etq, cal)
    }
  }
}

#' Delegador que dispara los indicadores habilitados en `config_indicadores`.
#'
#' @param series_procesadas salida de `preprocesar_series_para_indicadores()`.
#' @param config_indicadores lista (el objeto `indicadores_activos` del config).
#' @param variables_activas vector con c("pp","temp","q") según config global.
#' @param dir_salida carpeta destino para los CSV.
#' @param escala_tendencias "anual" o "mensual" (aplica a MK/Sen).
#' @return lista con los data.frames calculados (mk, sen, extremos_pp,
#'   extremos_temp, spi, spei).
#' @export
calcular_indicadores <- function(series_procesadas,
                                 config_indicadores,
                                 variables_activas,
                                 dir_salida,
                                 escala_tendencias = "anual") {
  resultados <- list()

  if (isTRUE(config_indicadores$tendencia_mann_kendall)) {
    message("[6/B] Mann-Kendall · escala=", escala_tendencias)
    cargar_paquete_opcional("trend")
    resultados$mk <- calcular_mann_kendall(series_procesadas, variables_activas,
                                           escala = escala_tendencias)
  }
  if (isTRUE(config_indicadores$tendencia_theil_sen)) {
    message("[6/B] Theil-Sen · escala=", escala_tendencias)
    cargar_paquete_opcional("trend")
    resultados$sen <- calcular_theil_sen(series_procesadas, variables_activas,
                                         escala = escala_tendencias)
  }
  if (isTRUE(config_indicadores$extremos_precipitacion) &&
      "pp" %in% variables_activas) {
    message("[6/B] Extremos de precipitación")
    resultados$extremos_pp <- calcular_extremos_pp(series_procesadas)
  }
  if (isTRUE(config_indicadores$extremos_temperatura)) {
    if ("temp" %in% variables_activas) {
      message("[6/B] Extremos de temperatura")
      resultados$extremos_temp <- calcular_extremos_temp(series_procesadas)
    } else {
      warning("extremos_temperatura solicitado pero 'temp' no está en ",
              "variables_activas. Se omite.")
    }
  }
  if (isTRUE(config_indicadores$spi) && "pp" %in% variables_activas) {
    escalas <- config_indicadores$spi_escalas %||% c(3, 6, 12)
    spi_nf <- tolower(as.character(config_indicadores$spi_tratar_no_finitos %||%
                                     "cap"))
    if (!spi_nf %in% c("cap", "na", "none")) {
      warning("spi_tratar_no_finitos='", spi_nf, "' inválido; se usa 'cap'.")
      spi_nf <- "cap"
    }
    spi_lim <- as.numeric(config_indicadores$spi_limite_extremos %||% 4)
    message("[6/B] SPI · escalas=", paste(escalas, collapse = ","),
            " · no_finitos=", spi_nf, if (spi_nf == "cap") paste0(" (±", spi_lim, ")") else "")
    resultados$spi <- calcular_spi(
      series_procesadas,
      escalas = escalas,
      tratar_no_finitos = spi_nf,
      limite_extremos = spi_lim
    )
  }
  if (isTRUE(config_indicadores$spei)) {
    if ("temp" %in% variables_activas && "pp" %in% variables_activas) {
      escalas <- config_indicadores$spei_escalas %||% c(3, 6, 12)
      metodo  <- config_indicadores$spei_metodo_etp %||% "hargreaves"
      spei_nf <- tolower(as.character(config_indicadores$spei_tratar_no_finitos %||%
                                        "cap"))
      if (!spei_nf %in% c("cap", "na", "none")) {
        warning("spei_tratar_no_finitos='", spei_nf, "' inválido; se usa 'cap'.")
        spei_nf <- "cap"
      }
      spei_lim <- as.numeric(config_indicadores$spei_limite_extremos %||% 4)
      message("[6/B] SPEI · escalas=", paste(escalas, collapse = ","),
              " · ETP=", metodo,
              " · no_finitos=", spei_nf,
              if (spei_nf == "cap") paste0(" (±", spei_lim, ")") else "")
      resultados$spei <- calcular_spei(
        series_procesadas,
        escalas = escalas,
        metodo_etp = metodo,
        tratar_no_finitos = spei_nf,
        limite_extremos = spei_lim
      )
    } else {
      warning("SPEI requiere 'pp' y 'temp' en variables_activas. Se omite.")
    }
  }

  exportar_indicadores(resultados, dir_salida, series_procesadas)
  invisible(resultados)
}

# =============================================================================
# BLOQUE C — TENDENCIAS DECADALES
# =============================================================================

#' Construye series decadales a partir de los resultados del bloque B.
#' Soporta claves en `indicadores` de tres clases:
#'   - Extremos PP : "Rx1day", "Rx5day", "PRCPTOT", "R95p", "R99p",
#'                    "CDD", "CWD", "SDII"
#'   - Extremos T  : "TXx", "TNn", "TX90p", "TN10p", "DTR", "WSDI", "CSDI"
#'   - SPI/SPEI    : "spi_<N>", "spei_<N>" donde N es escala en meses
#'   - Alias       : "tendencia_anual_pp", "tendencia_anual_temp" (usa series
#'                    anuales disponibles en meta para reconstruir promedios
#'                    decadales crudos).
#'
#' Output por indicador: tabla long con
#'   grupo, estacion, variable, decada, valor_decadal,
#'   cambio_pct_vs_decada_anterior, mk_tau, mk_p_value.
#'
#' @param resultados salida de `calcular_indicadores()`.
#' @param series_procesadas necesario para alias "tendencia_anual_*".
#' @param indicadores vector character con claves a calcular.
#' @param ano_inicio,ano_fin rango del análisis.
#' @param dir_salida carpeta destino.
#' @return lista invisible con un data.frame por indicador.
#' @export
calcular_tendencias_decadales <- function(resultados,
                                          series_procesadas,
                                          indicadores,
                                          ano_inicio,
                                          ano_fin,
                                          dir_salida) {
  if (!dir.exists(dir_salida)) dir.create(dir_salida, recursive = TRUE)

  # Mapas (clave del usuario → (origen, columna_valor, método_decadal))
  cols_extremos_pp   <- c("Rx1day", "Rx5day", "PRCPTOT", "R95p", "R99p",
                          "CDD", "CWD", "SDII")
  cols_extremos_temp <- c("TXx", "TNn", "TX90p", "TN10p", "DTR",
                          "WSDI", "CSDI")

  # Función genérica: de un data.frame long con (grupo, estacion, year, valor)
  # construye resumen decadal + MK sobre los valores decadales.
  resumen_decadal <- function(df_long, metodo = c("mean", "sum")) {
    metodo <- match.arg(metodo)
    if (nrow(df_long) == 0) return(df_long[FALSE, , drop = FALSE])
    df_long$decada <- .decada_de(df_long$year)
    fn <- if (metodo == "sum")
      function(v) sum(v, na.rm = TRUE) else
      function(v) mean(v, na.rm = TRUE)
    agg <- stats::aggregate(
      df_long$valor,
      by = list(grupo = df_long$grupo, estacion = df_long$estacion,
                decada = df_long$decada),
      FUN = fn
    )
    names(agg)[4] <- "valor_decadal"
    agg <- agg[order(agg$grupo, agg$estacion, agg$decada), , drop = FALSE]
    # Cambio % vs década anterior y MK por (grupo, estacion)
    filas <- lapply(split(agg, list(agg$grupo, agg$estacion), drop = TRUE),
                    function(sub) {
      sub$cambio_pct_vs_decada_anterior <- NA_real_
      if (nrow(sub) >= 2) {
        vprev <- c(NA, sub$valor_decadal[-nrow(sub)])
        sub$cambio_pct_vs_decada_anterior <-
          100 * (sub$valor_decadal - vprev) /
          ifelse(is.na(vprev) | vprev == 0, NA_real_, vprev)
      }
      mk <- .mk_summary(sub$valor_decadal)
      sub$mk_tau     <- mk$tau
      sub$mk_p_value <- mk$p_value
      sub
    })
    do.call(rbind, filas)
  }

  out <- list()
  for (ind in indicadores) {

    origen_df <- NULL
    metodo_dec <- "mean"
    variable_label <- ind

    if (ind %in% cols_extremos_pp) {
      if (is.null(resultados$extremos_pp) ||
          !ind %in% names(resultados$extremos_pp)) next
      origen_df <- data.frame(
        grupo    = resultados$extremos_pp$grupo,
        estacion = resultados$extremos_pp$estacion,
        year     = resultados$extremos_pp$year,
        valor    = resultados$extremos_pp[[ind]],
        stringsAsFactors = FALSE
      )
      metodo_dec <- if (ind %in% c("PRCPTOT", "R95p", "R99p")) "mean" else "mean"
      variable_label <- paste0("pp:", ind)

    } else if (ind %in% cols_extremos_temp) {
      if (is.null(resultados$extremos_temp) ||
          !ind %in% names(resultados$extremos_temp)) next
      origen_df <- data.frame(
        grupo    = resultados$extremos_temp$grupo,
        estacion = resultados$extremos_temp$estacion,
        year     = resultados$extremos_temp$year,
        valor    = resultados$extremos_temp[[ind]],
        stringsAsFactors = FALSE
      )
      variable_label <- paste0("temp:", ind)

    } else if (grepl("^spi_[0-9]+$", ind)) {
      esc <- as.integer(sub("^spi_", "", ind))
      if (is.null(resultados$spi) || is.null(resultados$spi$long) ||
          nrow(resultados$spi$long) == 0) next
      sub <- resultados$spi$long[resultados$spi$long$escala == esc, ,
                                  drop = FALSE]
      if (nrow(sub) == 0) next
      origen_df <- data.frame(
        grupo    = sub$grupo,
        estacion = sub$estacion,
        year     = as.integer(format(sub$fecha, "%Y")),
        valor    = sub$spi,
        stringsAsFactors = FALSE
      )
      # SPI anual ≡ promedio de los valores SPI mensuales dentro del año
      # → para decadal promediamos los años.
      origen_df <- stats::aggregate(
        origen_df$valor,
        by = list(grupo = origen_df$grupo, estacion = origen_df$estacion,
                  year = origen_df$year),
        FUN = function(v) mean(v, na.rm = TRUE)
      )
      names(origen_df)[4] <- "valor"
      variable_label <- ind

    } else if (grepl("^spei_[0-9]+$", ind)) {
      esc <- as.integer(sub("^spei_", "", ind))
      if (is.null(resultados$spei) || is.null(resultados$spei$long) ||
          nrow(resultados$spei$long) == 0) next
      sub <- resultados$spei$long[resultados$spei$long$escala == esc, ,
                                    drop = FALSE]
      if (nrow(sub) == 0) next
      origen_df <- data.frame(
        grupo    = sub$grupo,
        estacion = sub$estacion,
        year     = as.integer(format(sub$fecha, "%Y")),
        valor    = sub$spei,
        stringsAsFactors = FALSE
      )
      origen_df <- stats::aggregate(
        origen_df$valor,
        by = list(grupo = origen_df$grupo, estacion = origen_df$estacion,
                  year = origen_df$year),
        FUN = function(v) mean(v, na.rm = TRUE)
      )
      names(origen_df)[4] <- "valor"
      variable_label <- ind

    } else if (ind %in% c("tendencia_anual_pp", "tendencia_anual_temp")) {
      # Reconstrucción desde series anuales del preproceso.
      target_vars <- if (ind == "tendencia_anual_pp") "pp"
                     else c("t_max", "t_min")
      registros <- list()
      for (g in names(series_procesadas)) {
        paquete <- series_procesadas[[g]]
        for (v in intersect(target_vars, setdiff(names(paquete), "meta"))) {
          anu <- paquete[[v]]$anual
          if (is.null(anu)) next
          cols_est <- columnas_estaciones(anu)
          for (est in cols_est) {
            registros[[length(registros) + 1L]] <- data.frame(
              grupo    = g,
              estacion = est,
              year     = anu$year,
              valor    = anu[[est]],
              stringsAsFactors = FALSE
            )
          }
        }
      }
      if (length(registros) == 0) next
      origen_df <- do.call(rbind, registros)
      # Si son dos variables (t_max, t_min), promediamos intra-año intra-estación
      origen_df <- stats::aggregate(
        origen_df$valor,
        by = list(grupo = origen_df$grupo, estacion = origen_df$estacion,
                  year = origen_df$year),
        FUN = function(v) mean(v, na.rm = TRUE)
      )
      names(origen_df)[4] <- "valor"

    } else {
      warning("Indicador decadal desconocido: '", ind, "'. Se omite.")
      next
    }

    resumen <- resumen_decadal(origen_df, metodo = metodo_dec)
    if (nrow(resumen) == 0) next
    resumen$indicador <- ind
    resumen$variable  <- variable_label

    out[[ind]] <- resumen

    # Persistir: {grupo}_{ind}_decadal.csv (se escribe un archivo por grupo)
    for (g in unique(resumen$grupo)) {
      sub <- resumen[resumen$grupo == g, , drop = FALSE]
      cals <- series_procesadas[[g]]$meta$calidades
      cal <- if (length(cals)) min(cals) else NA_integer_
      nombre <- nombre_archivo_estandar(
        g, ind, cal, ano_inicio, ano_fin, sufijo = "_decadal"
      )
      escribir_csv_robusto(sub, file.path(dir_salida, nombre))
      message("  → ", nombre)
    }
  }

  invisible(out)
}
