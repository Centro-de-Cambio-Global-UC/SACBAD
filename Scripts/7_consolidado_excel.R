# ==============================================================================
# Script auxiliar (NO forma parte del pipeline MAIN.R): Excel consolidado.
#
# Produce sólo 3 libros Excel por grupo, todos en `dir_salida/` (sin subcarpetas):
#
#   1. {grupo}_mensual_{ini}_{fin}.xlsx
#        Hojas: por_estacion, por_subcuenca, historico_est, historico_subc
#
#   2. {grupo}_anual_{ini}_{fin}.xlsx              (formato largo; 4 hojas)
#        Hojas: cal_estacion, cal_subcuenca, hidro_estacion, hidro_subcuenca
#        Agregación mensual → anual:
#          pp           → suma (acumulado anual en mm)
#          t_max, t_min → promedio anual
#          spi_*, spei_*→ promedio anual
#
#   3. {grupo}_timeseries_anual_{ini}_{fin}.xlsx   (formato ancho, hoja única)
#        Hoja "Hydroclimatic": eje Year + columnas por variable × ID_subcuenca
#          "Annual precipitation (mm) (LP)", "Mean maximum temperature (°C) (MP)",
#          "SPI-12 Calendar avg (MP)", "SPI-12 Hydro avg (MP)",
#          "SPI-12 September (MP)",  "SPI-12 December (MP)", …
#          (Hydro avg se alinea hydroyear → Year = año del abril de inicio)
#
# Año hidrológico Chile: 1 abr – 31 mar → hydroyear = año del abril de inicio
# (ene–mar → hydroyear = año civil − 1).
#
# Uso manual desde la raíz del proyecto (tras cargar tu config):
#   source("backend/librerias.R")
#   source("backend/funciones_utilidad.R")
#   source("scripts/7_consolidado_excel.R")
#   ejecutar_consolidado_excel(
#     dir_mensual     = file.path(dir_output_proyecto, "series", "mensual"),
#     dir_anual       = file.path(dir_output_proyecto, "series", "anual"),
#     dir_historico   = file.path(dir_output_proyecto, "series", "historico"),
#     dir_indicadores = file.path(dir_output_proyecto, "indicadores"),
#     grupos_estaciones    = grupos_estaciones,
#     variables_activas    = variables_activas,
#     calidad_por_variable = calidad_por_variable,
#     ano_inicio = ano_inicio, ano_fin = ano_fin,
#     indicadores_activos  = indicadores_activos,
#     dir_salida = file.path(dir_output_proyecto, "consolidado"),
#     archivo_estaciones_subcuenca = NULL, verbose = TRUE
#   )
#
# Requiere: series mensuales (paso 5) y, si aplica, indicadores (paso 6);
# CSV de estaciones con Codigo_nacional, Name_subcuenca, ID_subcuenca (opcional).
# ==============================================================================

#' Media solo sobre valores finitos; NA si no hay ninguno.
#' @keywords internal
.mean_finite <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x) == 0) return(NA_real_)
  mean(x)
}

#' Suma solo sobre valores finitos; NA si no hay ninguno.
#' @keywords internal
.sum_finite <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x) == 0) return(NA_real_)
  sum(x)
}

#' Variables que deben acumularse (suma) al agregar meses → año.
#' Resto (temperatura, SPI, SPEI) usa media.
#' @keywords internal
.vars_anual_suma <- c("pp")

#' Mapa codigo_nacional → Name_subcuenca, ID_subcuenca (CSV grupo o ruta).
#' @keywords internal
.cargar_mapa_subcuenca <- function(grupos_estaciones, archivo_override = NULL) {
  path <- archivo_override
  if (is.null(path) || !nzchar(path)) {
    for (g in grupos_estaciones) {
      af <- g$archivo_fuente
      if (!is.null(af) && nzchar(af) && file.exists(af)) {
        path <- af
        break
      }
    }
  }
  if (is.null(path) || !file.exists(path)) {
    warning("consolidado: sin archivo de estaciones; Name_subcuenca / ID_subcuenca = NA.")
    return(data.frame(
      codigo_nacional = character(0), Name_subcuenca = character(0),
      ID_subcuenca = character(0), stringsAsFactors = FALSE
    ))
  }
  df <- leer_csv_autodetect(path)
  nms <- names(df)
  nms_l <- tolower(trimws(nms))
  icod <- which(nms_l %in% c("codigo_nacional", "codigo"))[1]
  isub <- grep("name_subcuenca|nombre_subcuenca", nms_l, value = FALSE)[1]
  iid <- grep("^id_subcuenca$", nms_l, value = FALSE)[1]
  if (is.na(icod)) {
    warning("consolidado: no se encontró columna de código en ", path)
    return(data.frame(
      codigo_nacional = character(0), Name_subcuenca = character(0),
      ID_subcuenca = character(0), stringsAsFactors = FALSE
    ))
  }
  cod <- trimws(as.character(df[[icod]]))
  subv <- if (!is.na(isub)) trimws(as.character(df[[isub]])) else rep(NA_character_, length(cod))
  idsc <- if (!is.na(iid)) trimws(as.character(df[[iid]])) else rep(NA_character_, length(cod))
  out <- data.frame(
    codigo_nacional = cod,
    Name_subcuenca = subv,
    ID_subcuenca = idsc,
    stringsAsFactors = FALSE
  )
  out[!is.na(out$codigo_nacional) & nzchar(out$codigo_nacional), , drop = FALSE]
}

#' Año hidrológico Chile (abr–mar): etiqueta = año del abril de inicio.
#' @keywords internal
.calcular_hydroyear <- function(year, month) {
  y <- as.integer(year)
  m <- as.integer(month)
  ifelse(m >= 4L, y, y - 1L)
}

#' Añade columna hydroyear a tabla mensual larga (requiere year, month).
#' @keywords internal
.enriquecer_mensual_hydro <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  if (!all(c("year", "month") %in% names(df))) return(df)
  df$hydroyear <- .calcular_hydroyear(df$year, df$month)
  df
}

#' Columnas numéricas a promediar (mensual consolidado).
#' @keywords internal
.columnas_medidas_mensual <- function(df) {
  drop <- c(
    "fecha", "year", "month", "hydroyear",
    "codigo_nacional", "Name_subcuenca", "ID_subcuenca",
    "n_estaciones", "n_meses"
  )
  nms <- setdiff(names(df), drop)
  nms[vapply(nms, function(nm) is.numeric(df[[nm]]), logical(1))]
}

#' Promedio anual desde filas mensuales: por hydroyear o por year calendario.
#' @param por_estacion TRUE: agrupa por codigo_nacional; FALSE: sólo subcuenca.
#' @keywords internal
.promedios_anuales_desde_mensual <- function(df, by_hydro, por_estacion) {
  if (is.null(df) || nrow(df) == 0) return(NULL)
  df <- .enriquecer_mensual_hydro(df)
  med <- .columnas_medidas_mensual(df)
  if (length(med) == 0) return(NULL)
  if (by_hydro) {
    tiempo <- "hydroyear"
    grp <- c(
      if (por_estacion) "codigo_nacional",
      "Name_subcuenca", "ID_subcuenca", tiempo
    )
  } else {
    tiempo <- "year"
    grp <- c(
      if (por_estacion) "codigo_nacional",
      "Name_subcuenca", "ID_subcuenca", tiempo
    )
  }
  grp <- intersect(grp, names(df))
  grp <- grp[nzchar(grp)]
  if (!tiempo %in% grp) return(NULL)

  # Precipitación: acumulado anual (suma). Resto (temp, SPI, SPEI, ...): media.
  cols_suma <- intersect(.vars_anual_suma, med)
  cols_media <- setdiff(med, cols_suma)
  out <- df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grp))) |>
    dplyr::summarise(
      n_meses = dplyr::n(),
      dplyr::across(dplyr::all_of(cols_suma), .sum_finite),
      dplyr::across(dplyr::all_of(cols_media), .mean_finite),
      .groups = "drop"
    )
  out |> dplyr::mutate(dplyr::across(dplyr::any_of(med), ~ ifelse(is.nan(.x), NA, .x)))
}

#' Etiqueta de columna tipo "All_annual timeseries.xlsx" (sin el sufijo ID).
#' Vectorizado para usar en dplyr::mutate().
#' @keywords internal
.etiqueta_variable_anual <- function(var) {
  v <- as.character(var)
  out <- rep(NA_character_, length(v))
  out[v == "pp"] <- "Annual precipitation (mm)"
  out[v == "t_max"] <- "Mean maximum temperature (\u00B0C)"
  out[v == "t_min"] <- "Mean minimum temperature (\u00B0C)"
  is_spi <- grepl("^spi_[0-9]+$", v)
  out[is_spi] <- paste0("SPI-", sub("^spi_", "", v[is_spi]))
  is_spei <- grepl("^spei_[0-9]+$", v)
  out[is_spei] <- paste0("SPEI-", sub("^spei_", "", v[is_spei]))
  miss <- is.na(out)
  out[miss] <- v[miss]
  out
}


#' SPI/SPEI en formato largo por variante de agregación anual.
#' Variantes:
#'   - "cal_avg"   : promedio del año calendario
#'   - "hydro_avg" : promedio del año hidrológico (abr–mar)
#'   - "sep"       : valor observado en el mes de septiembre
#'   - "dec"       : valor observado en el mes de diciembre
#' @param para_master etiquetas únicas ("Calendar avg"/"Hydro avg") para poder
#'   combinar las 4 variantes en un mismo libro sin colisión de columnas.
#' @keywords internal
.spi_spei_long_variante <- function(df, variante, para_master = FALSE) {
  nms <- names(df)
  spi_cols <- grep("^spi_[0-9]+$", nms, value = TRUE)
  spei_cols <- grep("^spei_[0-9]+$", nms, value = TRUE)
  idx_cols <- c(spi_cols, spei_cols)
  if (length(idx_cols) == 0L) return(NULL)

  etiq_simple <- function(var) {
    v <- as.character(var)
    out <- rep(NA_character_, length(v))
    is_spi <- grepl("^spi_[0-9]+$", v)
    out[is_spi] <- paste0("SPI-", sub("^spi_", "", v[is_spi]))
    is_spei <- grepl("^spei_[0-9]+$", v)
    out[is_spei] <- paste0("SPEI-", sub("^spei_", "", v[is_spei]))
    out
  }

  tc <- if (identical(variante, "hydro_avg")) "hydroyear" else "year"
  if (!tc %in% names(df)) return(NULL)

  if (variante %in% c("sep", "dec")) {
    mes_n <- if (identical(variante, "sep")) 9L else 12L
    sub_df <- df[as.integer(df$month) == mes_n, , drop = FALSE]
    if (nrow(sub_df) == 0L) return(NULL)
    ag <- sub_df |>
      dplyr::group_by(.data[[tc]], .data$.id_sc) |>
      dplyr::summarise(
        dplyr::across(dplyr::all_of(idx_cols), .mean_finite),
        .groups = "drop"
      )
  } else {
    ag <- df |>
      dplyr::group_by(.data[[tc]], .data$.id_sc) |>
      dplyr::summarise(
        dplyr::across(dplyr::all_of(idx_cols), .mean_finite),
        .groups = "drop"
      )
  }

  sufijo <- switch(
    variante,
    cal_avg   = if (isTRUE(para_master)) " Calendar avg" else "",
    hydro_avg = if (isTRUE(para_master)) " Hydro avg" else "",
    sep       = " September",
    dec       = " December"
  )

  ag |>
    tidyr::pivot_longer(
      cols = tidyr::all_of(idx_cols),
      names_to = "var",
      values_to = "val"
    ) |>
    dplyr::mutate(
      stem = paste0(etiq_simple(.data$var), sufijo),
      colname = paste0(.data$stem, " (", .data$.id_sc, ")"),
      tiempo = .data[[tc]]
    ) |>
    dplyr::select("tiempo", "colname", "val")
}

#' Clima en formato largo anual.
#' pp = acumulado anual (suma); t_max / t_min = media anual.
#' @param etiqueta_pp opcional; si NULL usa `.etiqueta_variable_anual()`.
#' @keywords internal
.clima_long_anual <- function(df, tiempo_col, clim_vars, etiqueta_pp = NULL) {
  if (length(clim_vars) == 0L) return(NULL)
  if (!tiempo_col %in% names(df)) return(NULL)
  cols_suma <- intersect(.vars_anual_suma, clim_vars)
  cols_media <- setdiff(clim_vars, cols_suma)
  df |>
    dplyr::group_by(.data[[tiempo_col]], .data$.id_sc) |>
    dplyr::summarise(
      dplyr::across(dplyr::all_of(cols_suma), .sum_finite),
      dplyr::across(dplyr::all_of(cols_media), .mean_finite),
      .groups = "drop"
    ) |>
    tidyr::pivot_longer(
      cols = tidyr::all_of(clim_vars),
      names_to = "var",
      values_to = "val"
    ) |>
    dplyr::mutate(
      colname = dplyr::if_else(
        .data$var == "pp" & !is.null(etiqueta_pp),
        paste0(etiqueta_pp, " (", .data$.id_sc, ")"),
        paste0(.etiqueta_variable_anual(.data$var), " (", .data$.id_sc, ")")
      ),
      tiempo = .data[[tiempo_col]]
    ) |>
    dplyr::select("tiempo", "colname", "val")
}


#' Archivo maestro all_annual_timeseries con las 4 variantes SPI/SPEI combinadas.
#' Eje Year: año calendario para pp calendario, temp y SPI/SPEI "Calendar avg".
#' pp hidrológica: acumulado abr–mar; columna Year = hydroyear (año del abril).
#' SPI/SPEI aparecen 4 veces por escala×ID:
#'   " Calendar avg", " Hydro avg", " September", " December".
#' @keywords internal
.wide_all_annual_maestro <- function(mensual_sub) {
  if (is.null(mensual_sub) || nrow(mensual_sub) == 0) return(NULL)
  df <- mensual_sub
  df <- .enriquecer_mensual_hydro(df)
  if (!all(c("month", "year", "ID_subcuenca") %in% names(df))) return(NULL)

  df$.id_sc <- trimws(as.character(df$ID_subcuenca))
  df <- df[!is.na(df$.id_sc) & nzchar(df$.id_sc), , drop = FALSE]
  if (nrow(df) == 0) return(NULL)

  .ids <- sort(unique(df$.id_sc))
  nms <- names(df)
  spi_cols <- grep("^spi_[0-9]+$", nms, value = TRUE)
  spei_cols <- grep("^spei_[0-9]+$", nms, value = TRUE)
  clim_vars <- intersect(c("pp", "t_max", "t_min"), nms)

  partes <- list()
  if ("pp" %in% clim_vars) {
    cl_cal_pp <- .clima_long_anual(
      df, "year", "pp",
      etiqueta_pp = "Annual precipitation calendar (mm)"
    )
    if (!is.null(cl_cal_pp)) partes[[length(partes) + 1L]] <- cl_cal_pp
    cl_hy_pp <- .clima_long_anual(
      df, "hydroyear", "pp",
      etiqueta_pp = "Annual precipitation hydro (mm)"
    )
    if (!is.null(cl_hy_pp)) partes[[length(partes) + 1L]] <- cl_hy_pp
    clim_vars <- setdiff(clim_vars, "pp")
  }
  if (length(clim_vars) > 0L) {
    cl <- .clima_long_anual(df, "year", clim_vars)
    if (!is.null(cl)) partes[[length(partes) + 1L]] <- cl
  }
  for (variante in c("cal_avg", "hydro_avg", "sep", "dec")) {
    sp <- .spi_spei_long_variante(df, variante, para_master = TRUE)
    if (!is.null(sp)) partes[[length(partes) + 1L]] <- sp
  }
  if (length(partes) == 0L) return(NULL)

  long_all <- dplyr::bind_rows(partes) |>
    dplyr::group_by(.data$tiempo, .data$colname) |>
    dplyr::summarise(val = .mean_finite(.data$val), .groups = "drop")

  wide <- long_all |>
    tidyr::pivot_wider(
      names_from = "colname", values_from = "val", values_fill = NA
    )

  primera <- "Year"
  names(wide)[names(wide) == "tiempo"] <- primera

  ord <- character(0)
  labs_clim <- c(
    pp_cal = "Annual precipitation calendar (mm)",
    pp_hy  = "Annual precipitation hydro (mm)",
    t_max  = "Mean maximum temperature (\u00B0C)",
    t_min  = "Mean minimum temperature (\u00B0C)"
  )
  if ("pp" %in% intersect(c("pp", "t_max", "t_min"), nms)) {
    for (id in .ids) ord <- c(ord, paste0(labs_clim[["pp_cal"]], " (", id, ")"))
    for (id in .ids) ord <- c(ord, paste0(labs_clim[["pp_hy"]], " (", id, ")"))
  }
  for (v in intersect(c("t_max", "t_min"), clim_vars)) {
    lab <- unname(labs_clim[[v]])
    for (id in .ids) ord <- c(ord, paste0(lab, " (", id, ")"))
  }
  suf_por_var <- c(
    cal_avg = " Calendar avg", hydro_avg = " Hydro avg",
    sep = " September", dec = " December"
  )
  for (variante in c("cal_avg", "hydro_avg", "sep", "dec")) {
    sfj <- unname(suf_por_var[[variante]])
    for (sc in c(3L, 6L, 12L)) {
      sp <- paste0("spi_", sc)
      se <- paste0("spei_", sc)
      if (sp %in% spi_cols) {
        stem <- paste0("SPI-", sc, sfj)
        for (id in .ids) ord <- c(ord, paste0(stem, " (", id, ")"))
      }
      if (se %in% spei_cols) {
        stem <- paste0("SPEI-", sc, sfj)
        for (id in .ids) ord <- c(ord, paste0(stem, " (", id, ")"))
      }
    }
  }
  rest <- ord[ord %in% names(wide)]
  extra <- setdiff(names(wide), c(primera, rest))
  wide <- wide[, c(primera, rest, extra), drop = FALSE]
  wide
}

#' @keywords internal
.pivot_estaciones_largo <- function(df, nombre_medida) {
  if (is.null(df) || nrow(df) == 0) return(NULL)
  df <- df
  df$fecha <- as.Date(df$fecha)
  meta <- intersect(c("fecha", "year", "month"), names(df))
  if (length(meta) == 0) return(NULL)
  tidyr::pivot_longer(
    df,
    -tidyr::all_of(meta),
    names_to = "codigo_nacional",
    values_to = nombre_medida,
    values_drop_na = FALSE
  )
}

#' Localiza el CSV *_{spi|spei}_long_*.csv más reciente del grupo.
#' @keywords internal
.buscar_indicador_long <- function(dir_indicadores, grupo, tipo) {
  if (!dir.exists(dir_indicadores)) return(NA_character_)
  patt <- sprintf("^%s_%s_long_.*\\.csv$", grupo, tipo)
  files <- sort(list.files(dir_indicadores, pattern = patt, full.names = TRUE),
                decreasing = TRUE)
  if (length(files) == 0) NA_character_ else files[1]
}

#' @keywords internal
.cargar_spi_spei_ancho <- function(dir_indicadores, grupo, usar_spi, usar_spei) {
  out <- NULL
  if (isTRUE(usar_spi)) {
    r <- .buscar_indicador_long(dir_indicadores, grupo, "spi")
    if (!is.na(r) && file.exists(r)) {
      d <- leer_csv_robusto(r)
      d$fecha <- as.Date(d$fecha)
      if ("grupo" %in% names(d)) {
        d <- d[!is.na(d$grupo) & d$grupo == grupo, , drop = FALSE]
      }
      d$codigo_nacional <- trimws(as.character(d$estacion))
      d <- d[, c("codigo_nacional", "fecha", "escala", "spi"), drop = FALSE]
      w <- tidyr::pivot_wider(
        d,
        id_cols = c("codigo_nacional", "fecha"),
        names_from = "escala",
        values_from = "spi",
        names_prefix = "spi_"
      )
      out <- w
    }
  }
  if (isTRUE(usar_spei)) {
    r <- .buscar_indicador_long(dir_indicadores, grupo, "spei")
    if (!is.na(r) && file.exists(r)) {
      d <- leer_csv_robusto(r)
      d$fecha <- as.Date(d$fecha)
      if ("grupo" %in% names(d)) {
        d <- d[!is.na(d$grupo) & d$grupo == grupo, , drop = FALSE]
      }
      d$codigo_nacional <- trimws(as.character(d$estacion))
      d <- d[, c("codigo_nacional", "fecha", "escala", "spei"), drop = FALSE]
      w <- tidyr::pivot_wider(
        d,
        id_cols = c("codigo_nacional", "fecha"),
        names_from = "escala",
        values_from = "spei",
        names_prefix = "spei_"
      )
      if (is.null(out)) {
        out <- w
      } else {
        out <- dplyr::full_join(out, w, by = c("codigo_nacional", "fecha"))
      }
    }
  }
  out
}

#' @keywords internal
.unir_mensual <- function(dir_mensual, grupo, variables_activas,
                          calidad_por_variable, ano_inicio, ano_fin,
                          dir_indicadores, indicadores_activos) {
  mapa <- list(pp = "pp", temp = c("t_max", "t_min"))
  partes <- list()
  for (v in variables_activas) {
    cal <- calidad_por_variable[[v]]
    if (is.null(cal) || length(cal) == 0 || is.na(cal)) next
    for (serie in mapa[[v]]) {
      fn <- nombre_archivo_estandar(grupo, serie, cal, ano_inicio, ano_fin,
                                    sufijo = "_mensual")
      path <- file.path(dir_mensual, fn)
      if (!file.exists(path)) next
      raw <- leer_csv_robusto(path)
      raw <- tryCatch(normalizar_columnas_fecha(raw), error = function(e) raw)
      ln <- .pivot_estaciones_largo(raw, serie)
      if (!is.null(ln)) partes[[length(partes) + 1L]] <- ln
    }
  }
  join_mensual <- function(a, b) {
    k <- intersect(
      c("fecha", "year", "month", "codigo_nacional"),
      intersect(names(a), names(b))
    )
    if (length(k) == 0) return(a)
    dplyr::full_join(a, b, by = k)
  }
  m <- if (length(partes) == 0) NULL else Reduce(join_mensual, partes)
  usar_spi <- isTRUE(indicadores_activos$spi)
  usar_spei <- isTRUE(indicadores_activos$spei)
  ind <- .cargar_spi_spei_ancho(dir_indicadores, grupo, usar_spi, usar_spei)
  if (!is.null(ind)) {
    if (is.null(m)) {
      m <- ind
      if (!"year" %in% names(m)) m$year <- as.integer(format(m$fecha, "%Y"))
      if (!"month" %in% names(m)) m$month <- as.integer(format(m$fecha, "%m"))
    } else {
      m <- dplyr::full_join(m, ind, by = c("codigo_nacional", "fecha"))
    }
  }
  if (is.null(m)) return(NULL)
  dplyr::arrange(m, .data$codigo_nacional, .data$fecha)
}

#' @keywords internal
.historico_a_largo <- function(dir_historico, grupo, variables_activas,
                               calidad_por_variable, ano_inicio, ano_fin) {
  mapa <- list(pp = "pp", temp = c("t_max", "t_min"))
  filas <- list()
  for (v in variables_activas) {
    cal <- calidad_por_variable[[v]]
    if (is.null(cal) || length(cal) == 0 || is.na(cal)) next
    for (serie in mapa[[v]]) {
      fn <- nombre_archivo_estandar(grupo, serie, cal, ano_inicio, ano_fin,
                                    sufijo = "_historico")
      path <- file.path(dir_historico, fn)
      if (!file.exists(path)) next
      raw <- leer_csv_robusto(path)
      meta <- c(
        "archivo_fuente", "grupo", "variable", "estadistico",
        "fecha_inicio_periodo", "fecha_fin_periodo"
      )
      meta <- intersect(meta, names(raw))
      est_cols <- setdiff(names(raw), meta)
      if (length(est_cols) == 0) next
      raw$fecha_inicio_periodo <- as.Date(raw$fecha_inicio_periodo)
      raw$fecha_fin_periodo <- as.Date(raw$fecha_fin_periodo)
      ln <- tidyr::pivot_longer(
        raw,
        tidyr::all_of(est_cols),
        names_to = "codigo_nacional",
        values_to = "valor",
        values_drop_na = FALSE
      )
      filas[[length(filas) + 1L]] <- ln
    }
  }
  if (length(filas) == 0) return(NULL)
  dplyr::bind_rows(filas)
}

#' @keywords internal
.agregar_subcuenca_mensual <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  df <- .enriquecer_mensual_hydro(df)
  sc <- trimws(as.character(df$Name_subcuenca))
  df <- df[!is.na(sc) & nzchar(sc), , drop = FALSE]
  if (nrow(df) == 0) return(df)
  idx <- c("Name_subcuenca", "fecha", "year", "month", "hydroyear")
  idx <- intersect(idx, names(df))
  med <- setdiff(names(df), c(idx, "codigo_nacional", "ID_subcuenca"))
  if (length(med) == 0) return(df[0, , drop = FALSE])
  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(idx))) |>
    dplyr::summarise(
      n_estaciones = dplyr::n_distinct(.data$codigo_nacional),
      ID_subcuenca = {
        u <- unique(stats::na.omit(as.character(.data$ID_subcuenca)))
        u <- u[nzchar(u)]
        if (length(u)) u[[1]] else NA_character_
      },
      dplyr::across(dplyr::all_of(med), .mean_finite),
      .groups = "drop"
    ) |>
    dplyr::mutate(dplyr::across(dplyr::all_of(med), ~ ifelse(is.nan(.x), NA, .x)))
}

#' @keywords internal
.agregar_subcuenca_historico <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  sc <- trimws(as.character(df$Name_subcuenca))
  df <- df[!is.na(sc) & nzchar(sc), , drop = FALSE]
  if (nrow(df) == 0) return(df)
  idx <- c(
    "Name_subcuenca", "ID_subcuenca", "variable", "estadistico",
    "fecha_inicio_periodo", "fecha_fin_periodo"
  )
  idx <- intersect(idx, names(df))
  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(idx))) |>
    dplyr::summarise(
      n_estaciones = dplyr::n_distinct(.data$codigo_nacional),
      valor = .mean_finite(.data$valor),
      .groups = "drop"
    )
}

#' Genera un inventario mínimo de 3 libros Excel por grupo, todos en `dir_salida/`:
#'
#'   1. `{grupo}_mensual_{ini}_{fin}.xlsx`
#'        - Hoja `por_estacion`    : series mensuales por estación (todas las vars
#'                                   disponibles: pp, t_max, t_min, spi_*, spei_*)
#'        - Hoja `por_subcuenca`   : agregación mensual por Name_subcuenca
#'        - Hoja `historico_est`   : estadísticas históricas por estación (si hay)
#'        - Hoja `historico_subc`  : estadísticas históricas por subcuenca (si hay)
#'
#'   2. `{grupo}_anual_{ini}_{fin}.xlsx`  (agregaciones anuales — formato largo)
#'        - Hoja `cal_estacion`    : anual por año calendario, por estación
#'        - Hoja `cal_subcuenca`   : anual por año calendario, por subcuenca
#'        - Hoja `hidro_estacion`  : anual por año hidrológico, por estación
#'        - Hoja `hidro_subcuenca` : anual por año hidrológico, por subcuenca
#'        Regla por variable: pp = suma; t_max, t_min, spi_*, spei_* = media.
#'
#'   3. `{grupo}_timeseries_anual_{ini}_{fin}.xlsx`  (formato ancho estilo
#'      `All_annual timeseries.xlsx`)
#'        - Hoja `Hydroclimatic`   : 1ª col Year (calendario), resto
#'          "Etiqueta (ID_subcuenca)". Incluye pp/temp anuales y SPI/SPEI en
#'          cuatro variantes por escala × ID:
#'            "… Calendar avg", "… Hydro avg", "… September", "… December".
#'          Para "Hydro avg" se alinea hydroyear → Year (año del abril de inicio).
#'
#' @param archivo_estaciones_subcuenca ruta opcional al CSV con
#'   `Codigo_nacional` y `Name_subcuenca` / `ID_subcuenca` (si NULL, se usa
#'   `archivo_fuente` del primer grupo con archivo existente).
#' @export
ejecutar_consolidado_excel <- function(dir_mensual,
                                       dir_anual,
                                       dir_historico,
                                       dir_indicadores,
                                       grupos_estaciones,
                                       variables_activas,
                                       calidad_por_variable,
                                       ano_inicio,
                                       ano_fin,
                                       indicadores_activos,
                                       dir_salida,
                                       archivo_estaciones_subcuenca = NULL,
                                       verbose = TRUE) {
  if (!dir.exists(dir_salida)) dir.create(dir_salida, recursive = TRUE)
  if (!is.list(indicadores_activos)) indicadores_activos <- list()

  mapa_sub <- .cargar_mapa_subcuenca(grupos_estaciones, archivo_estaciones_subcuenca)

  adjuntar_sub <- function(df) {
    if (is.null(df) || nrow(df) == 0) return(df)
    dplyr::left_join(df, mapa_sub, by = "codigo_nacional")
  }

  for (grupo in vapply(grupos_estaciones, function(g) g$nombre, character(1))) {
    mensual <- .unir_mensual(
      dir_mensual, grupo, variables_activas, calidad_por_variable,
      ano_inicio, ano_fin, dir_indicadores, indicadores_activos
    )
    histo <- .historico_a_largo(
      dir_historico, grupo, variables_activas, calidad_por_variable,
      ano_inicio, ano_fin
    )

    mensual_e <- adjuntar_sub(mensual)
    if (!is.null(mensual_e) && nrow(mensual_e) > 0) {
      mensual_e <- .enriquecer_mensual_hydro(mensual_e)
    }
    histo_e <- adjuntar_sub(histo)

    if ((is.null(mensual_e) || nrow(mensual_e) == 0) &&
        (is.null(histo_e) || nrow(histo_e) == 0)) {
      if (verbose) {
        message("consolidado [", grupo, "]: sin datos (revise rutas / pasos previos).")
      }
      next
    }

    suf <- sprintf("%s_%s", ano_inicio, ano_fin)
    nm_mensual  <- paste0(grupo, "_mensual_", suf, ".xlsx")
    nm_anual    <- paste0(grupo, "_anual_", suf, ".xlsx")
    nm_timesrs  <- paste0(grupo, "_timeseries_anual_", suf, ".xlsx")

    # --- 1) Mensual ---------------------------------------------------------
    mensual_sub <- if (!is.null(mensual_e) && nrow(mensual_e) > 0) {
      .agregar_subcuenca_mensual(mensual_e)
    } else NULL

    hojas_mensual <- list()
    if (!is.null(mensual_e) && nrow(mensual_e) > 0) {
      hojas_mensual[["por_estacion"]] <- mensual_e
    }
    if (!is.null(mensual_sub) && nrow(mensual_sub) > 0) {
      hojas_mensual[["por_subcuenca"]] <- mensual_sub
    }
    if (!is.null(histo_e) && nrow(histo_e) > 0) {
      hojas_mensual[["historico_est"]] <- histo_e
      hs <- .agregar_subcuenca_historico(histo_e)
      if (!is.null(hs) && nrow(hs) > 0) hojas_mensual[["historico_subc"]] <- hs
    }
    if (length(hojas_mensual) > 0) {
      escribir_xlsx_robusto(hojas_mensual, file.path(dir_salida, nm_mensual))
      if (verbose) message("consolidado → ", nm_mensual)
    }

    # --- 2) Anual (long, 4 hojas) -------------------------------------------
    if (!is.null(mensual_e) && nrow(mensual_e) > 0) {
      hojas_anual <- list(
        cal_estacion    = .promedios_anuales_desde_mensual(
          mensual_e, by_hydro = FALSE, por_estacion = TRUE),
        hidro_estacion  = .promedios_anuales_desde_mensual(
          mensual_e, by_hydro = TRUE,  por_estacion = TRUE)
      )
      if (!is.null(mensual_sub) && nrow(mensual_sub) > 0) {
        hojas_anual[["cal_subcuenca"]] <- .promedios_anuales_desde_mensual(
          mensual_sub, by_hydro = FALSE, por_estacion = FALSE)
        hojas_anual[["hidro_subcuenca"]] <- .promedios_anuales_desde_mensual(
          mensual_sub, by_hydro = TRUE,  por_estacion = FALSE)
      }
      hojas_anual <- Filter(function(x) !is.null(x) && nrow(x) > 0, hojas_anual)
      hojas_anual <- hojas_anual[c(
        "cal_estacion", "cal_subcuenca", "hidro_estacion", "hidro_subcuenca"
      )]
      hojas_anual <- hojas_anual[!vapply(hojas_anual, is.null, logical(1))]
      if (length(hojas_anual) > 0) {
        escribir_xlsx_robusto(hojas_anual, file.path(dir_salida, nm_anual))
        if (verbose) message("consolidado → ", nm_anual)
      }
    }

    # --- 3) Timeseries anual (maestro ancho) --------------------------------
    if (!is.null(mensual_sub) && nrow(mensual_sub) > 0) {
      wm <- .wide_all_annual_maestro(mensual_sub)
      if (!is.null(wm) && nrow(wm) > 0) {
        escribir_xlsx_robusto(
          list(Hydroclimatic = wm),
          file.path(dir_salida, nm_timesrs)
        )
        if (verbose) message("consolidado → ", nm_timesrs)
      }
    }
  }

  invisible(dir_salida)
}
