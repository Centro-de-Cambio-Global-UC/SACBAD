# ==============================================================================
# Script 1 — Selección de estaciones por grupo, variable y calidad mínima.
#
# Para cada (grupo, variable):
#   1) Consulta la tabla `estacion` aplicando los filtros del grupo.
#   2) Calcula la calidad (cobertura) en el periodo indicado.
#   3) Filtra por umbral de calidad mínima.
#   4) Escribe un CSV: {grupo}_{variable}_{calidad}_{ano_inicio}_{ano_fin}.csv
# ==============================================================================

#' Filtrar estaciones por grupo, variable y calidad mínima.
#'
#' @param connection Conexión DBI a la base.
#' @param grupo string, nombre del grupo (ej. "seleccion_estaciones_1").
#' @param filtros list, filtros genéricos sobre columnas de `estacion`.
#' @param variable string: "pp", "temp" o "q".
#' @param calidad_minima numeric, umbral mínimo (%) a exigir.
#' @param ano_inicio,ano_fin rango inclusivo.
#' @param dir_estaciones carpeta donde se guardan los CSV de salida.
#' @return data.frame con estaciones seleccionadas (invisible).
#' @export
filtrar_estaciones_grupo <- function(connection,
                                     grupo,
                                     filtros = list(),
                                     variable = c("pp", "temp", "q"),
                                     calidad_minima = 0,
                                     ano_inicio,
                                     ano_fin,
                                     dir_estaciones) {
  variable <- match.arg(variable)
  if (!dir.exists(dir_estaciones)) dir.create(dir_estaciones, recursive = TRUE)

  filtros_sql <- construir_clausulas_filtros(filtros)

  # Temperatura requiere que ambas subvariables (t_max y t_min) tengan cobertura
  nombres_variables <- switch(
    variable,
    pp   = "pp",
    q    = "q",
    temp = c("t_max", "t_min")
  )

  df <- calcular_metricas_calidad(
    conexion          = connection,
    nombres_variables = nombres_variables,
    ano_inicio        = ano_inicio,
    ano_fin           = ano_fin,
    filtros_sql       = filtros_sql
  )

  if (is.null(df) || nrow(df) == 0) {
    message("  (Grupo ", grupo, " · ", variable, "): 0 estaciones devueltas por la BD.")
    df_filtrado <- data.frame()
  } else {
    col_calidad <- paste0("calidad_", nombres_variables)
    # Todas las calidades de las subvariables deben superar el umbral
    cumple <- Reduce(`&`, lapply(col_calidad, function(c) df[[c]] >= calidad_minima))
    df_filtrado <- df[!is.na(cumple) & cumple, , drop = FALSE]

    # Ordenar por la primera calidad disponible (desc)
    df_filtrado <- df_filtrado[order(-df_filtrado[[col_calidad[1]]]), , drop = FALSE]

    # Columna indicativa del grupo y periodo
    df_filtrado$grupo    <- grupo
    df_filtrado$periodo  <- paste0(ano_inicio, "-", ano_fin)

    # Quitar la columna 'id' interna si existe (no es útil afuera).
    if ("id" %in% names(df_filtrado)) df_filtrado$id <- NULL
  }

  nombre_out <- nombre_archivo_estandar(grupo, variable, calidad_minima, ano_inicio, ano_fin)
  ruta_out <- file.path(dir_estaciones, nombre_out)
  escribir_csv_robusto(df_filtrado, ruta_out)
  message("  → ", nrow(df_filtrado), " estaciones guardadas en ", nombre_out)

  invisible(df_filtrado)
}
