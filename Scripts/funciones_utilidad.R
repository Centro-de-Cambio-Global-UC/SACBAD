# ==============================================================================
# Funciones utilitarias genéricas (sin dependencia de nombres de proyecto).
# Incluye transformaciones de formato largo ↔ ancho, validación de fechas,
# resolución de rutas por convención, y helpers de I/O tolerantes a Windows.
# ==============================================================================

#' Valida un string de fecha en formato YYYY-MM-DD.
#' @param fecha character.
#' @return TRUE si el string es una fecha válida.
check_fecha_valid <- function(fecha) {
  if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", fecha)) return(FALSE)
  f <- tryCatch(as.Date(fecha, format = "%Y-%m-%d"), error = function(e) NA)
  !is.na(f) && format(f, "%Y-%m-%d") == fecha
}

#' Convierte observaciones en formato largo (fecha, codigo_nacional, valor)
#' en formato ancho (fecha, year, month, day, c1, c2, ...), completando fechas
#' faltantes con NA y ordenando cronológicamente.
#'
#' @param dataframe data.frame con columnas fecha, year, month, day,
#'   codigo_nacional y una columna con el valor cuyo nombre es `nombre_variable`.
#' @param nombre_variable character, nombre de la columna de valores.
#' @return data.frame ancho con fecha, year, month, day y una columna por código.
preparar_datos_ancho <- function(dataframe, nombre_variable) {
  if (nrow(dataframe) == 0) {
    return(data.frame(
      fecha = as.Date(character()), year = integer(),
      month = integer(), day = integer()
    ))
  }

  dataframe <- dataframe[, setdiff(names(dataframe), "fecha"), drop = FALSE]
  dataframe$fecha <- as.Date(sprintf("%04d-%02d-%02d",
                                     dataframe$year, dataframe$month, dataframe$day))
  dataframe$year <- NULL
  dataframe$month <- NULL
  dataframe$day <- NULL

  full_dates <- seq.Date(min(dataframe$fecha), max(dataframe$fecha), by = "day")
  combos <- expand.grid(
    fecha = full_dates,
    codigo_nacional = unique(dataframe$codigo_nacional),
    stringsAsFactors = FALSE
  )
  completo <- merge(combos, dataframe, by = c("fecha", "codigo_nacional"), all.x = TRUE)
  completo <- completo[order(completo$codigo_nacional, completo$fecha), ]
  completo$year  <- as.integer(format(completo$fecha, "%Y"))
  completo$month <- as.integer(format(completo$fecha, "%m"))
  completo$day   <- as.integer(format(completo$fecha, "%d"))

  otras <- setdiff(names(completo), c("fecha", "year", "month", "day"))
  completo <- completo[, c("fecha", "year", "month", "day", otras), drop = FALSE]

  ancho <- tidyr::pivot_wider(
    completo,
    names_from = "codigo_nacional",
    values_from = dplyr::all_of(nombre_variable)
  )

  # Asegurar numéricas en columnas de estación
  cols_est <- setdiff(names(ancho), c("fecha", "year", "month", "day"))
  for (c in cols_est) ancho[[c]] <- suppressWarnings(as.numeric(ancho[[c]]))

  as.data.frame(ancho)
}

# -----------------------------------------------------------------------------
# Convención unificada de nombres de archivos.
# Patrón estricto: {grupo}_{variable}_{calidad}_{ano_inicio}_{ano_fin}[{sufijo}].csv
# -----------------------------------------------------------------------------

#' Nombre de archivo estándar.
#' @param grupo string, nombre del grupo (sin espacios).
#' @param variable string, ej. 'pp', 'temp', 'q', 't_max', 't_min'.
#' @param calidad entero, umbral usado.
#' @param ano_inicio,ano_fin enteros.
#' @param sufijo string opcional que se añade antes de '.csv' (ej. '_bruta').
#' @param extension 'csv' (por defecto).
nombre_archivo_estandar <- function(grupo, variable, calidad, ano_inicio, ano_fin,
                                    sufijo = "", extension = "csv") {
  paste0(grupo, "_", variable, "_", calidad, "_", ano_inicio, "_", ano_fin,
         sufijo, ".", extension)
}

#' Ruta completa del CSV de metadata de estaciones para un grupo × variable.
#' Búsqueda tolerante al sufijo (CSV base vs. filtrado por shapefile).
#'
#' @param dir_estaciones carpeta raíz de estaciones.
#' @param grupo nombre del grupo.
#' @param variable 'pp', 'temp' o 'q'.
#' @param calidad entero.
#' @param ano_inicio,ano_fin enteros.
#' @param preferir_filtrado si TRUE, prioriza el CSV con sufijo '_filtrado_shp'.
#' @return ruta existente o NULL si no se encuentra.
resolver_ruta_estaciones <- function(dir_estaciones, grupo, variable,
                                     calidad, ano_inicio, ano_fin,
                                     preferir_filtrado = FALSE) {
  base <- nombre_archivo_estandar(grupo, variable, calidad, ano_inicio, ano_fin)
  filtrado <- nombre_archivo_estandar(grupo, variable, calidad, ano_inicio, ano_fin,
                                      sufijo = "_filtrado_shp")
  orden <- if (preferir_filtrado) c(filtrado, base) else c(base, filtrado)
  for (bn in orden) {
    cand <- file.path(dir_estaciones, bn)
    if (file.exists(cand)) return(cand)
  }
  NULL
}

# -----------------------------------------------------------------------------
# I/O tolerante a rutas largas / OneDrive en Windows.
# Estrategia: escribir primero en tempdir() y luego copiar al destino final.
# -----------------------------------------------------------------------------

#' Escribir un data.frame a CSV UTF-8 de forma robusta.
escribir_csv_robusto <- function(df, ruta_destino) {
  ddir <- dirname(ruta_destino)
  if (!dir.exists(ddir)) dir.create(ddir, recursive = TRUE)
  tmp <- tempfile(pattern = "ascl_", tmpdir = tempdir(), fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  utils::write.csv(df, tmp, row.names = FALSE, fileEncoding = "UTF-8")
  ok <- file.copy(tmp, ruta_destino, overwrite = TRUE)
  if (!ok || !file.exists(ruta_destino)) {
    stop("No se pudo escribir el CSV en: ", ruta_destino)
  }
  invisible(ruta_destino)
}

#' Escribir uno o varios data.frames a un XLSX de forma robusta.
escribir_xlsx_robusto <- function(hojas, ruta_destino) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    stop("Instala 'writexl' para escribir archivos Excel: install.packages('writexl').")
  }
  ddir <- dirname(ruta_destino)
  if (!dir.exists(ddir)) dir.create(ddir, recursive = TRUE)
  tmp <- tempfile(pattern = "ascl_", tmpdir = tempdir(), fileext = ".xlsx")
  on.exit(unlink(tmp), add = TRUE)
  writexl::write_xlsx(hojas, tmp)
  ok <- file.copy(tmp, ruta_destino, overwrite = TRUE)
  if (!ok || !file.exists(ruta_destino)) {
    stop("No se pudo escribir el Excel en: ", ruta_destino)
  }
  invisible(ruta_destino)
}

#' Leer un CSV con manejo básico de errores y reintento con encoding nativo.
leer_csv_robusto <- function(ruta) {
  if (!file.exists(ruta)) {
    stop("No existe el archivo: ", ruta)
  }
  df <- tryCatch(
    utils::read.csv(ruta, stringsAsFactors = FALSE, check.names = FALSE,
                    fileEncoding = "UTF-8"),
    error = function(e) NULL
  )
  if (!is.null(df)) return(df)
  utils::read.csv(ruta, stringsAsFactors = FALSE, check.names = FALSE)
}

# -----------------------------------------------------------------------------
# Normalización de columnas de fecha en series anchas.
# -----------------------------------------------------------------------------

#' Asegura que df tenga columnas fecha/year/month/day en minúsculas.
#' @param df data.frame con al menos fecha o Fecha.
#' @return data.frame con columnas estándar.
normalizar_columnas_fecha <- function(df) {
  renombres <- list(c("Fecha", "fecha"), c("Year", "year"),
                    c("Month", "month"), c("Day", "day"))
  for (par in renombres) {
    if (par[1] %in% names(df) && !(par[2] %in% names(df))) {
      names(df)[names(df) == par[1]] <- par[2]
    }
  }
  if (!"fecha" %in% names(df)) {
    stop("El data.frame debe contener columna 'fecha' o 'Fecha'.")
  }
  df$fecha <- as.Date(df$fecha)
  if (!"year" %in% names(df))  df$year  <- as.integer(format(df$fecha, "%Y"))
  if (!"month" %in% names(df)) df$month <- as.integer(format(df$fecha, "%m"))
  if (!"day" %in% names(df))   df$day   <- as.integer(format(df$fecha, "%d"))
  df
}

#' Devuelve los nombres de columnas que corresponden a estaciones (numéricas,
#' excluyendo fecha/year/month/day).
columnas_estaciones <- function(df) {
  cols_fecha <- intersect(c("fecha", "year", "month", "day"), names(df))
  cand <- setdiff(names(df), cols_fecha)
  cand[vapply(cand, function(c) is.numeric(df[[c]]), logical(1))]
}

# -----------------------------------------------------------------------------
# Lectura robusta de CSVs de estaciones preexistentes
# -----------------------------------------------------------------------------

#' Lee un CSV auto-detectando el separador (',' o ';') mediante sniffing
#' de la primera línea no vacía. Útil para archivos externos que pueden
#' venir con convención europea (sep=';', decimal=',').
#'
#' @param ruta ruta al archivo.
#' @return data.frame.
#' @keywords internal
leer_csv_autodetect <- function(ruta) {
  if (!file.exists(ruta)) {
    stop("No existe el archivo: ", ruta)
  }
  con <- file(ruta, "r", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  primera <- ""
  while (length(primera) && nchar(primera) == 0) {
    primera <- readLines(con, n = 1, warn = FALSE)
    if (length(primera) == 0) break
    primera <- sub("^\ufeff", "", primera)  # quitar BOM
  }
  sep <- if (length(primera) && grepl(";", primera) &&
             (!grepl(",", primera) ||
              lengths(regmatches(primera, gregexpr(";", primera))) >=
              lengths(regmatches(primera, gregexpr(",", primera))))) ";" else ","

  reader <- function(enc) {
    utils::read.table(
      ruta,
      header           = TRUE,
      sep              = sep,
      dec              = if (sep == ";") "," else ".",
      quote            = "\"",
      stringsAsFactors = FALSE,
      check.names      = FALSE,
      fileEncoding     = enc,
      na.strings       = c("", "NA", "NaN")
    )
  }
  df <- tryCatch(reader("UTF-8"), error = function(e) NULL)
  if (is.null(df)) df <- reader("")  # reintento con encoding nativo
  df
}

#' Obtiene el vector de códigos nacionales para un grupo de estaciones,
#' ya sea leyéndolos desde un CSV preexistente o consultándolos en la base
#' de datos según `grupo$modo`.
#'
#' @param grupo Lista con al menos el campo `modo`. Si modo = "archivo"
#'   requiere también `archivo_fuente` y `columna_codigo`. Si modo = "db"
#'   requiere `filtros` (lista) y una `connection` activa.
#' @param connection Conexión DBI activa (sólo usada si `grupo$modo == "db"`).
#' @return Vector `character` con los códigos nacionales únicos, en el orden
#'   original del archivo/consulta, sin NAs.
#' @export
get_codigos_grupo <- function(grupo, connection = NULL) {
  if (is.null(grupo$modo) || !nzchar(grupo$modo)) {
    stop("El grupo '", grupo$nombre %||% "(sin nombre)",
         "' no define el campo 'modo' ('archivo' o 'db').")
  }

  if (grupo$modo == "archivo") {
    if (is.null(grupo$archivo_fuente) || !nzchar(grupo$archivo_fuente)) {
      stop("Grupo '", grupo$nombre, "' con modo='archivo' requiere 'archivo_fuente'.")
    }
    if (!file.exists(grupo$archivo_fuente)) {
      stop("No se encontró el archivo de estaciones preseleccionadas: ",
           grupo$archivo_fuente)
    }
    col <- grupo$columna_codigo
    if (is.null(col) || !nzchar(col)) col <- "codigo_nacional"

    df <- leer_csv_autodetect(grupo$archivo_fuente)

    # Resolver columna de forma tolerante a mayúsculas/minúsculas y espacios.
    nombres_norm <- tolower(trimws(names(df)))
    idx <- match(tolower(trimws(col)), nombres_norm)
    if (is.na(idx)) {
      stop("Columna '", col, "' no encontrada en ", grupo$archivo_fuente,
           ". Columnas disponibles: ", paste(names(df), collapse = ", "))
    }
    codigos <- as.character(df[[idx]])
    codigos <- trimws(codigos)
    codigos <- codigos[!is.na(codigos) & nzchar(codigos)]
    return(unique(codigos))

  } else if (grupo$modo == "db") {
    if (is.null(connection)) {
      stop("Grupo '", grupo$nombre, "' con modo='db' requiere una conexión activa.")
    }
    if (!exists("obtener_codigos_db", mode = "function")) {
      stop("La función 'obtener_codigos_db' no está definida; implementarla en ",
           "backend/queries.R para soportar modo='db' con get_codigos_grupo().")
    }
    codigos <- obtener_codigos_db(connection, grupo$filtros %||% list())
    return(unique(as.character(codigos)))

  } else {
    stop("modo de grupo desconocido: '", grupo$modo,
         "'. Valores válidos: 'archivo' o 'db'.")
  }
}

# Operador auxiliar (null-coalescing) para simplificar defaults.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
