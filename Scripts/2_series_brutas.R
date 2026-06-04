# ==============================================================================
# Script 2 — Descarga de series brutas diarias para las estaciones de un grupo.
#
# Lee el CSV producido por el paso 1:
#     {grupo}_{variable}_{calidad}_{ano_inicio}_{ano_fin}.csv
# y descarga las observaciones diarias para cada estación, en formato ancho.
# Salida:
#     pp   → {grupo}_pp_{calidad}_{ano_inicio}_{ano_fin}_bruta.csv
#     q    → {grupo}_q_{calidad}_{ano_inicio}_{ano_fin}_bruta.csv
#     temp → {grupo}_t_max_{calidad}_{ano_inicio}_{ano_fin}_bruta.csv
#            {grupo}_t_min_{calidad}_{ano_inicio}_{ano_fin}_bruta.csv
# ==============================================================================

#' Descargar y guardar la(s) serie(s) diaria(s) bruta(s) para un grupo × variable.
#'
#' Los códigos nacionales de las estaciones pueden venir de dos fuentes:
#'   1. `codigos` pasado explícitamente (p. ej. desde `get_codigos_grupo()`
#'      cuando la lista proviene de un archivo preseleccionado y el paso 1
#'      del pipeline está omitido).
#'   2. El CSV canónico del paso 1 en `dir_estaciones`, si `codigos = NULL`.
#'
#' Si se pasan `codigos`, se persiste adicionalmente un CSV mínimo de
#' estaciones en `dir_estaciones` para mantener la convención de nombres
#' y permitir que pasos posteriores que dependan del metadata (p. ej. 4.5)
#' puedan resolver la ruta por la vía habitual.
#'
#' @param connection Conexión DBI activa.
#' @param grupo nombre del grupo.
#' @param variable "pp", "temp" o "q".
#' @param codigos (opcional) vector character con códigos nacionales. Si se
#'   provee, se omite la lectura del CSV de estaciones producido por paso 1.
#' @param calidad umbral aplicado en el paso 1 (usado para encontrar el CSV de
#'   estaciones y para nombrar los archivos de salida).
#' @param ano_inicio,ano_fin rango inclusivo.
#' @param dir_estaciones carpeta de los CSV de estaciones.
#' @param dir_series carpeta de salida para las series brutas.
#' @return lista invisible con los data.frames generados.
#' @export
obtener_series_brutas <- function(connection,
                                  grupo,
                                  variable = c("pp", "temp", "q"),
                                  codigos = NULL,
                                  calidad,
                                  ano_inicio,
                                  ano_fin,
                                  dir_estaciones,
                                  dir_series) {
  variable <- match.arg(variable)
  if (!dir.exists(dir_series)) dir.create(dir_series, recursive = TRUE)
  if (!dir.exists(dir_estaciones)) dir.create(dir_estaciones, recursive = TRUE)

  if (!is.null(codigos)) {
    codigos <- unique(trimws(as.character(codigos)))
    codigos <- codigos[!is.na(codigos) & nzchar(codigos)]
    if (length(codigos) == 0) {
      message("  (", grupo, "/", variable,
              "): vector de códigos vacío. Se omite la descarga.")
      return(invisible(list()))
    }
    # Persistir un CSV mínimo de estaciones (convención de nombres del paso 1)
    nombre_est <- nombre_archivo_estandar(grupo, variable, calidad,
                                          ano_inicio, ano_fin)
    ruta_est <- file.path(dir_estaciones, nombre_est)
    if (!file.exists(ruta_est)) {
      df_min <- data.frame(
        codigo_nacional = codigos,
        grupo           = grupo,
        periodo         = paste0(ano_inicio, "-", ano_fin),
        stringsAsFactors = FALSE
      )
      escribir_csv_robusto(df_min, ruta_est)
      message("  → ", length(codigos), " códigos persistidos en ", nombre_est)
    }
  } else {
    ruta_est <- resolver_ruta_estaciones(
      dir_estaciones = dir_estaciones,
      grupo          = grupo,
      variable       = variable,
      calidad        = calidad,
      ano_inicio     = ano_inicio,
      ano_fin        = ano_fin
    )
    if (is.null(ruta_est)) {
      stop("No se encontró el CSV de estaciones para grupo='", grupo,
           "', variable='", variable, "', calidad=", calidad,
           ". Ejecuta antes el paso 1 o pasa 'codigos' explícitamente.")
    }
    est <- leer_csv_robusto(ruta_est)
    if (!"codigo_nacional" %in% names(est) || nrow(est) == 0) {
      message("  (", grupo, "/", variable, "): 0 estaciones en ",
              basename(ruta_est), ". Se omite la descarga.")
      return(invisible(list()))
    }
    codigos <- as.character(est$codigo_nacional)
  }

  descargar_y_guardar <- function(nombre_var_bd) {
    message("  Descargando ", nombre_var_bd, " para ", length(codigos),
            " estaciones (", grupo, ")...")
    obs <- obtener_observaciones(
      conexion           = connection,
      nombre_variable    = nombre_var_bd,
      ano_inicio         = ano_inicio,
      ano_fin            = ano_fin,
      codigos_nacionales = codigos
    )
    if (nrow(obs) == 0) {
      message("    Sin observaciones para ", nombre_var_bd, " en el periodo.")
      return(NULL)
    }
    ancho <- preparar_datos_ancho(obs, nombre_var_bd)
    ruta_out <- file.path(
      dir_series,
      nombre_archivo_estandar(grupo, nombre_var_bd, calidad, ano_inicio, ano_fin,
                              sufijo = "_bruta")
    )
    escribir_csv_robusto(ancho, ruta_out)
    message("    → ", basename(ruta_out), " (", nrow(ancho), " filas, ",
            length(columnas_estaciones(ancho)), " estaciones)")
    ancho
  }

  resultados <- list()
  if (variable == "pp") {
    resultados$pp <- descargar_y_guardar("pp")
  } else if (variable == "q") {
    resultados$q <- descargar_y_guardar("q")
  } else if (variable == "temp") {
    resultados$t_max <- descargar_y_guardar("t_max")
    resultados$t_min <- descargar_y_guardar("t_min")
  }

  invisible(resultados)
}
