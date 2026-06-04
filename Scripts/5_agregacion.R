# ==============================================================================
# Script 5 — Agregación mensual, anual e histórica.
#
# Lee los archivos *_rellena.csv (o _rellena.csv filtradas por shapefile) y
# genera:
#   - series mensuales : {grupo}_{variable}_{calidad}_{ini}_{fin}_mensual.csv
#   - series anuales   : {grupo}_{variable}_{calidad}_{ini}_{fin}_anual.csv
#   - resumen período  : {grupo}_{variable}_{calidad}_{ini}_{fin}_historico.csv
#   - Excel consolidado opcional con todas las filas de _historico.csv.
#
# Regla de agregación por variable (configurable en config.R):
#   pp   → suma
#   temp → promedio
#   q    → promedio
# ==============================================================================

.parsear_nombre_rellena <- function(ruta) {
  bn <- basename(ruta)
  bn <- sub("_rellena\\.csv$", "", bn, ignore.case = TRUE)
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

#' Método de agregación aplicable a una variable de serie diaria.
.metodo_para_variable_serie <- function(v_serie, metodo_agregacion) {
  # Variable "lógica" (pp/temp/q) derivada de la de serie (pp/t_max/t_min/q)
  var_logica <- switch(v_serie,
                       pp    = "pp",
                       q     = "q",
                       t_max = "temp",
                       t_min = "temp",
                       stop("Variable de serie desconocida: ", v_serie))
  m <- metodo_agregacion[[var_logica]]
  if (is.null(m)) stop("Método de agregación no definido para variable lógica: ", var_logica)
  if (!m %in% c("suma", "promedio")) {
    stop("Método de agregación inválido: ", m, " (usar 'suma' o 'promedio')")
  }
  m
}

#' Aplica el método a un conjunto de columnas agrupado.
.agregar_por <- function(df, grupos_cols, cols_estacion, metodo) {
  fn <- if (metodo == "suma") {
    function(x) sum(x, na.rm = TRUE)
  } else {
    function(x) mean(x, na.rm = TRUE)
  }
  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grupos_cols))) |>
    dplyr::summarise(dplyr::across(dplyr::all_of(cols_estacion), fn),
                     .groups = "drop")
}

#' Agregación mensual de una serie rellena ya cargada en memoria.
agregar_mensual_df <- function(df, metodo) {
  cols <- columnas_estaciones(df)
  agg <- .agregar_por(df, c("year", "month"), cols, metodo)
  agg$fecha <- as.Date(sprintf("%04d-%02d-01", agg$year, agg$month))
  dplyr::relocate(agg, "fecha", .before = "year")
}

#' Agregación anual.
agregar_anual_df <- function(df, metodo) {
  cols <- columnas_estaciones(df)
  agg <- .agregar_por(df, "year", cols, metodo)
  agg$fecha <- as.Date(sprintf("%04d-01-01", agg$year))
  dplyr::relocate(agg, "fecha", .before = "year")
}

#' Una fila por serie: resumen del período completo.
#'   pp : promedio de los acumulados anuales (mm/año).
#'   temp/q: promedio diario del período.
agregar_historico_df <- function(df, v_serie, metodo) {
  cols <- columnas_estaciones(df)
  if (v_serie == "pp") {
    anual <- df |>
      dplyr::group_by(.data$year) |>
      dplyr::summarise(dplyr::across(dplyr::all_of(cols),
                                     ~ sum(., na.rm = TRUE)), .groups = "drop")
    resumen <- anual |>
      dplyr::summarise(dplyr::across(dplyr::all_of(cols),
                                     ~ mean(., na.rm = TRUE)), .groups = "drop")
    estadistico <- "promedio_acumulado_anual"
  } else {
    resumen <- df |>
      dplyr::summarise(dplyr::across(dplyr::all_of(cols),
                                     ~ mean(., na.rm = TRUE)), .groups = "drop")
    estadistico <- "promedio_diario_periodo"
  }
  list(tabla = resumen, estadistico = estadistico)
}

#' Procesa un archivo *_rellena.csv y produce mensual/anual/histórico.
procesar_una_serie_agregacion <- function(ruta_rellena,
                                          dir_mensual,
                                          dir_anual,
                                          dir_historico,
                                          metodo_agregacion,
                                          verbose = TRUE) {
  info <- .parsear_nombre_rellena(ruta_rellena)
  if (is.null(info)) {
    warning("No se pudo parsear: ", basename(ruta_rellena)); return(NULL)
  }

  metodo <- .metodo_para_variable_serie(info$variable, metodo_agregacion)

  df <- leer_csv_robusto(ruta_rellena)
  df <- normalizar_columnas_fecha(df)

  mensual <- agregar_mensual_df(df, metodo)
  anual   <- agregar_anual_df(df, metodo)
  hist_r  <- agregar_historico_df(df, info$variable, metodo)

  ruta_mensual <- file.path(
    dir_mensual, nombre_archivo_estandar(info$grupo, info$variable, info$calidad,
                                         info$ano_inicio, info$ano_fin, sufijo = "_mensual")
  )
  ruta_anual <- file.path(
    dir_anual, nombre_archivo_estandar(info$grupo, info$variable, info$calidad,
                                       info$ano_inicio, info$ano_fin, sufijo = "_anual")
  )
  ruta_hist <- file.path(
    dir_historico, nombre_archivo_estandar(info$grupo, info$variable, info$calidad,
                                           info$ano_inicio, info$ano_fin, sufijo = "_historico")
  )

  escribir_csv_robusto(mensual, ruta_mensual)
  escribir_csv_robusto(anual,   ruta_anual)

  fila_hist <- data.frame(
    archivo_fuente       = basename(ruta_rellena),
    grupo                = info$grupo,
    variable             = info$variable,
    estadistico          = hist_r$estadistico,
    fecha_inicio_periodo = min(df$fecha, na.rm = TRUE),
    fecha_fin_periodo    = max(df$fecha, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
  fila_hist <- dplyr::bind_cols(fila_hist, hist_r$tabla)
  escribir_csv_robusto(fila_hist, ruta_hist)

  if (verbose) {
    message("  ", basename(ruta_rellena), " → mensual / anual / histórico (",
            metodo, ")")
  }

  list(mensual = mensual, anual = anual, historico = fila_hist)
}

#' Ejecutar agregación para todas las series rellenas del proyecto.
#' @export
ejecutar_agregacion <- function(dir_rellenas,
                                dir_mensual,
                                dir_anual,
                                dir_historico,
                                variables_activas,
                                grupos,
                                calidad_por_variable,
                                ano_inicio,
                                ano_fin,
                                metodo_agregacion,
                                excel_consolidado = TRUE,
                                nombre_excel = "resumen_historico_consolidado.xlsx",
                                nombre_hoja = "todas_las_series",
                                verbose = TRUE) {
  for (d in c(dir_mensual, dir_anual, dir_historico)) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }

  mapa_variables <- list(pp = "pp", q = "q", temp = c("t_max", "t_min"))

  tablas_hist <- list()
  for (grupo in grupos) {
    for (var in variables_activas) {
      cal <- calidad_por_variable[[var]]
      if (is.null(cal) || is.na(cal)) next
      for (v_serie in mapa_variables[[var]]) {
        archivo_in <- file.path(
          dir_rellenas,
          nombre_archivo_estandar(grupo, v_serie, cal, ano_inicio, ano_fin,
                                  sufijo = "_rellena")
        )
        if (!file.exists(archivo_in)) {
          if (verbose) message("  (Omitido, no existe): ", basename(archivo_in))
          next
        }
        res <- procesar_una_serie_agregacion(
          ruta_rellena      = archivo_in,
          dir_mensual       = dir_mensual,
          dir_anual         = dir_anual,
          dir_historico     = dir_historico,
          metodo_agregacion = metodo_agregacion,
          verbose           = verbose
        )
        if (!is.null(res)) {
          tablas_hist[[length(tablas_hist) + 1L]] <- res$historico
        }
      }
    }
  }

  if (excel_consolidado && length(tablas_hist) > 0) {
    consolidado <- dplyr::bind_rows(tablas_hist)
    ruta_xlsx <- file.path(dir_historico, nombre_excel)
    hojas <- list()
    hoja_clave <- if (nchar(nombre_hoja) > 31) substr(nombre_hoja, 1, 31) else nombre_hoja
    hojas[[hoja_clave]] <- consolidado
    escribir_xlsx_robusto(hojas, ruta_xlsx)
    if (verbose) {
      message("Excel consolidado (", nrow(consolidado), " filas): ",
              basename(ruta_xlsx))
    }
  }

  invisible(list(mensual = dir_mensual, anual = dir_anual, historico = dir_historico))
}
