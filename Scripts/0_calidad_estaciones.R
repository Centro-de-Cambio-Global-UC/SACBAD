# ==============================================================================
# Script 0 — Análisis exploratorio de calidad de estaciones.
#
# Lee los CSV generados por el paso 1 (típicamente con umbral 0 para ver todas
# las estaciones disponibles) y genera un gráfico por archivo mostrando cuántas
# estaciones cumplen cada umbral (0..100 %).
#
# Entrada: CSVs en dir_estaciones con nombre
#           {grupo}_{variable}_{calidad}_{ano_inicio}_{ano_fin}.csv
# Salida : PNGs en dir_graficos con nombre
#           calidad_{grupo}_{variable}.png
# ==============================================================================

# -----------------------------------------------------------------------------
# Color por variable (sólo estético; no altera nombres de archivos).
# -----------------------------------------------------------------------------
.colores_variable <- c(
  pp   = "#2E86AB",
  temp = "#7209B7",
  q    = "#D62828"
)

#' Nombre de la columna de calidad que se va a usar para cada variable.
#' Temperatura toma la calidad de t_max por convención (ambas se filtraron igual).
.columna_calidad_por_variable <- function(variable) {
  switch(variable,
         pp   = "calidad_pp",
         temp = "calidad_t_max",
         q    = "calidad_q",
         stop("Variable desconocida: ", variable))
}

#' Parsear el nombre de archivo estándar:
#' {grupo}_{variable}_{calidad}_{ano_inicio}_{ano_fin}.csv
#' @return list(grupo, variable, calidad, ano_inicio, ano_fin) o NULL si no matchea.
.parsear_nombre_csv_estaciones <- function(nombre_archivo) {
  bn <- sub("\\.csv$", "", basename(nombre_archivo), ignore.case = TRUE)
  m <- regmatches(bn, regexec("^(.+)_(pp|temp|q)_([0-9]+)_([0-9]{4})_([0-9]{4})$", bn))[[1]]
  if (length(m) < 6) return(NULL)
  list(
    grupo      = m[2],
    variable   = m[3],
    calidad    = as.integer(m[4]),
    ano_inicio = as.integer(m[5]),
    ano_fin    = as.integer(m[6])
  )
}

#' Genera el gráfico de distribución acumulada de calidad para un CSV.
#'
#' @param archivo_csv ruta al CSV de estaciones.
#' @param columna_calidad nombre de la columna con los % de calidad.
#' @param titulo_variable string descriptivo para el subtítulo del plot.
#' @param archivo_salida ruta PNG de destino.
#' @param color_principal color hex.
#' @param periodo_subtitulo string opcional con el período ("1990-2024").
#' @return ggplot invisible (además escribe PNG).
graficar_distribucion_calidad <- function(archivo_csv,
                                          columna_calidad,
                                          titulo_variable,
                                          archivo_salida,
                                          color_principal = "#2E86AB",
                                          periodo_subtitulo = NULL) {
  df <- readr::read_csv(archivo_csv, show_col_types = FALSE)
  if (!columna_calidad %in% colnames(df)) {
    message("  Columna '", columna_calidad, "' ausente en ", basename(archivo_csv),
            "; se omite gráfico.")
    return(invisible(NULL))
  }
  if (nrow(df) == 0) {
    message("  Archivo vacío: ", basename(archivo_csv))
    return(invisible(NULL))
  }

  umbrales <- seq(0, 100, by = 1)
  n_por_umbral <- vapply(umbrales,
                         function(u) sum(df[[columna_calidad]] >= u, na.rm = TRUE),
                         integer(1))
  df_plot <- data.frame(umbral = umbrales, n_estaciones = n_por_umbral)

  umbrales_ref <- c(50, 60, 70, 80, 90, 95)
  df_ref <- data.frame(
    umbral = umbrales_ref,
    n_est  = vapply(umbrales_ref,
                    function(u) sum(df[[columna_calidad]] >= u, na.rm = TRUE),
                    integer(1))
  )

  p <- ggplot2::ggplot(df_plot, ggplot2::aes(x = .data$umbral, y = .data$n_estaciones)) +
    ggplot2::geom_area(fill = color_principal, alpha = 0.3) +
    ggplot2::geom_line(color = color_principal, linewidth = 1.2) +
    ggplot2::geom_vline(data = df_ref, ggplot2::aes(xintercept = .data$umbral),
                        linetype = "dashed", color = "gray40", alpha = 0.6) +
    ggplot2::labs(
      x = "Umbral de calidad (%)",
      y = "Número de estaciones",
      title = "Distribución acumulada de estaciones por umbral de calidad",
      subtitle = paste0(
        titulo_variable,
        if (!is.null(periodo_subtitulo)) paste0(" (", periodo_subtitulo, ")") else ""
      )
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", hjust = 0.5),
                   plot.subtitle = ggplot2::element_text(hjust = 0.5))

  if (!dir.exists(dirname(archivo_salida))) {
    dir.create(dirname(archivo_salida), recursive = TRUE)
  }
  ggplot2::ggsave(archivo_salida, p, width = 11, height = 6, dpi = 200, bg = "white")
  message("  Gráfico guardado: ", archivo_salida)

  invisible(p)
}

#' Generar gráficos de calidad para todos los CSV del paso 1 con umbral dado.
#'
#' @param dir_estaciones carpeta donde están los CSVs de estaciones.
#' @param dir_graficos carpeta destino de PNGs.
#' @param ano_inicio,ano_fin para filtrar archivos (opcional).
#' @param calidad_umbral_analizada sólo archivos con este umbral se analizan
#'   (por defecto 0, que son los resultados exploratorios).
#' @return lista invisible de gráficos generados.
#' @export
generar_graficos_calidad_grupos <- function(dir_estaciones,
                                            dir_graficos,
                                            ano_inicio = NULL,
                                            ano_fin = NULL,
                                            calidad_umbral_analizada = 0L) {
  if (!dir.exists(dir_estaciones)) {
    message("No existe la carpeta de estaciones: ", dir_estaciones)
    return(invisible(NULL))
  }
  if (!dir.exists(dir_graficos)) dir.create(dir_graficos, recursive = TRUE)

  archivos <- list.files(dir_estaciones, pattern = "\\.csv$", full.names = TRUE)
  resultados <- list()

  for (ruta in archivos) {
    info <- .parsear_nombre_csv_estaciones(ruta)
    if (is.null(info)) next
    if (!is.null(ano_inicio) && info$ano_inicio != ano_inicio) next
    if (!is.null(ano_fin)    && info$ano_fin    != ano_fin)    next
    if (!is.null(calidad_umbral_analizada) &&
        info$calidad != calidad_umbral_analizada) next

    col_calidad <- .columna_calidad_por_variable(info$variable)
    color <- unname(.colores_variable[info$variable])
    nombre_png <- paste0("calidad_", info$grupo, "_", info$variable, ".png")
    ruta_png <- file.path(dir_graficos, nombre_png)

    p <- tryCatch(
      graficar_distribucion_calidad(
        archivo_csv       = ruta,
        columna_calidad   = col_calidad,
        titulo_variable   = paste0(info$grupo, " · variable ", info$variable),
        archivo_salida    = ruta_png,
        color_principal   = color,
        periodo_subtitulo = paste0(info$ano_inicio, "-", info$ano_fin)
      ),
      error = function(e) {
        message("  Error procesando ", basename(ruta), ": ", conditionMessage(e))
        NULL
      }
    )
    resultados[[nombre_png]] <- p
  }

  message("Gráficos de calidad generados en: ", dir_graficos)
  invisible(resultados)
}
