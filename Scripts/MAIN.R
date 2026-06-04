# ==============================================================================
# MAIN.R — Orquestador del pipeline de caracterización climática histórica.
#
# Este script es el ÚNICO punto de entrada. La configuración se resuelve
# dinámicamente (no hay que tocar MAIN.R para lanzar un proyecto nuevo):
#
#   Prioridad 1: argumento CLI   →  Rscript MAIN.R --config configs/XYZ.R
#   Prioridad 2: variable de entorno  →  Sys.setenv(ASC_CONFIG = "configs/XYZ.R")
#   Prioridad 3: archivo `config_activo.R` en la raíz (si existe)
#   Prioridad 4: fallback al template `config.R`
#
# Todos los pasos del pipeline están envueltos en guards `pasos_activos$*`
# definidos en el config. Los pasos omitidos se loggean pero no se ejecutan.
#
# Convención de nombres de archivos generados:
#   {grupo}_{variable}_{calidad}_{ano_inicio}_{ano_fin}[_sufijo].csv
#     grupo    → nombre del grupo definido en el config.
#     variable → 'pp', 'temp' o 'q' (archivos de estaciones);
#                'pp', 't_max', 't_min' o 'q' (archivos de series diarias).
#     calidad  → umbral de calidad aplicado (entero).
#     ano_*    → período del análisis (4 dígitos cada uno).
# ==============================================================================

# ------------------------------------------------------------------------------
# 1) Resolver qué archivo de configuración usar
# ------------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
config_flag <- which(args == "--config")

config_file <- if (length(config_flag) > 0 && length(args) >= config_flag + 1) {
  args[config_flag + 1]
} else if (nzchar(Sys.getenv("ASC_CONFIG"))) {
  Sys.getenv("ASC_CONFIG")
} else if (file.exists("Scripts/config_sacbad.R")) {
  "Scripts/config_sacbad.R"
} else {
  "Scripts/config_sacbad.R"
}

if (!file.exists(config_file)) {
  stop("No se encontró el archivo de configuración: ", config_file)
}

message(">>> Usando configuración: ", config_file)
source(config_file)

# ------------------------------------------------------------------------------
# 2) Defaults estructurales del proyecto (backend, scripts, credenciales).
#    Se aplican sólo si el config no los definió. Esto permite que los configs
#    específicos en `configs/` sean mínimos (sólo parámetros del proyecto).
# ------------------------------------------------------------------------------
if (!exists("dir_base")    || !nzchar(dir_base))    dir_base    <- getwd()
if (!exists("dir_scripts") || !nzchar(dir_scripts)) dir_scripts <- file.path(dir_base, "Scripts")
if (!exists("use_database")) use_database <- FALSE

# ------------------------------------------------------------------------------
# 3) Derivar rutas de salida a partir de dir_output_proyecto
#    (aísla outputs por proyecto sin tocar este archivo)
# ------------------------------------------------------------------------------
if (!exists("dir_output_proyecto") || is.null(dir_output_proyecto) ||
    !nzchar(dir_output_proyecto)) {
  dir_output_proyecto <- "Output"
}

dir_output               <- dir_output_proyecto
dir_estaciones           <- file.path(dir_output, "estaciones")
dir_series_raiz          <- file.path(dir_output, "series")
dir_series_brutas        <- file.path(dir_series_raiz, "brutas")
dir_series_depuradas     <- file.path(dir_series_raiz, "depuradas")
dir_series_rellenas      <- file.path(dir_series_raiz, "rellenas")
dir_series_filtradas_shp <- file.path(dir_series_raiz, "filtradas_shapefile")
dir_series_mensual       <- file.path(dir_series_raiz, "mensual")
dir_series_anual         <- file.path(dir_series_raiz, "anual")
dir_series_historico     <- file.path(dir_series_raiz, "historico")

dir_graficos             <- file.path(dir_output, "graficos")
dir_graficos_calidad     <- file.path(dir_graficos, "calidad")
dir_graficos_mapas_shp   <- file.path(dir_graficos, "mapas_shapefile")

dir_indicadores          <- file.path(dir_output, "indicadores")
dir_tendencias_decadales <- file.path(dir_output, "tendencias_decadales")
dir_tendencias           <- file.path(dir_output, "tendencias")
dir_resumen_estaciones   <- file.path(dir_output, "resumen_estaciones")

invisible(lapply(
  list(
    dir_estaciones, dir_series_brutas, dir_series_depuradas, dir_series_rellenas,
    dir_series_filtradas_shp, dir_series_mensual, dir_series_anual,
    dir_series_historico, dir_graficos_calidad, dir_graficos_mapas_shp,
    dir_indicadores, dir_tendencias_decadales,
    dir_tendencias, dir_resumen_estaciones
  ),
  dir.create, recursive = TRUE, showWarnings = FALSE
))

# ------------------------------------------------------------------------------
# 4) Cargar backend y scripts del pipeline
# ------------------------------------------------------------------------------
Sys.setenv(ASC_USE_DB = if (isTRUE(use_database)) "true" else "false")
source(file.path(dir_scripts, "librerias.R"))
source(file.path(dir_scripts, "funciones_utilidad.R"))
if (isTRUE(use_database)) {
  stop("Database mode is not supported in the public supplementary repository.")
}

source(file.path(dir_scripts, "0_calidad_estaciones.R"))
source(file.path(dir_scripts, "1_seleccion_estaciones.R"))
source(file.path(dir_scripts, "2_series_brutas.R"))
source(file.path(dir_scripts, "3_depurado.R"))
source(file.path(dir_scripts, "4_missforest.R"))
source(file.path(dir_scripts, "4.5_filtro_shapefile.R"))
source(file.path(dir_scripts, "5_agregacion.R"))
source(file.path(dir_scripts, "6_indicadores_tendencias.R"))
source(file.path(dir_scripts, "8_resumen_estaciones_division.R"))

# ------------------------------------------------------------------------------
# 5) Defaults de retrocompatibilidad para pasos_activos
#    (si el config es antiguo y no define la lista, se activan todos los pasos
#    clásicos excepto los exploratorios/opcionales).
# ------------------------------------------------------------------------------
if (!exists("pasos_activos") || !is.list(pasos_activos)) {
  pasos_activos <- list()
}
defaults_pasos <- list(
  paso_0_calidad_estaciones     = FALSE,
  paso_1_seleccion              = TRUE,
  paso_2_series_brutas          = TRUE,
  paso_3_depurado               = TRUE,
  paso_4_missforest             = TRUE,
  paso_4_5_filtro_shapefile     = isTRUE(exists("usar_filtro_shapefile") &&
                                           usar_filtro_shapefile),
  paso_5_agregacion_mensual     = TRUE,
  paso_5_1_agregacion_anual     = TRUE,
  paso_5_2_historico            = TRUE,
  paso_6_indicadores_tendencias = FALSE,
  paso_7_resumen_estaciones     = FALSE
)
for (k in names(defaults_pasos)) {
  if (is.null(pasos_activos[[k]])) pasos_activos[[k]] <- defaults_pasos[[k]]
}

# ------------------------------------------------------------------------------
# 6) Helpers de entorno
# ------------------------------------------------------------------------------
grupo_nombres <- function() {
  vapply(grupos_estaciones, function(g) g$nombre, character(1))
}

# Asegurar que cada grupo tenga un 'modo' definido (retrocompat: default 'db').
for (i in seq_along(grupos_estaciones)) {
  if (is.null(grupos_estaciones[[i]]$modo)) {
    grupos_estaciones[[i]]$modo <- "db"
  }
}

necesita_db <- function() {
  any_db <- any(vapply(grupos_estaciones,
                       function(g) identical(g$modo, "db"), logical(1)))
  any_db ||
    isTRUE(pasos_activos$paso_0_calidad_estaciones) ||
    isTRUE(pasos_activos$paso_1_seleccion) ||
    isTRUE(pasos_activos$paso_2_series_brutas)
}

# ------------------------------------------------------------------------------
# 7) Conexión a la base de datos (sólo si algún paso activo la requiere)
# ------------------------------------------------------------------------------
connection <- NULL
if (necesita_db()) {
  connection <- connect_to_db(archivo_credenciales_db)
} else {
  message(">>> Ningún paso activo requiere base de datos; se omite la conexión.")
}

# ==============================================================================
# PASO 0 (opcional) — Análisis exploratorio de calidad de estaciones
# ==============================================================================
if (isTRUE(pasos_activos$paso_0_calidad_estaciones)) {
  message(">>> PASO 0: Calidad exploratoria de estaciones")
  for (var in variables_activas) {
    for (grupo in grupos_estaciones) {
      if (!identical(grupo$modo, "db")) {
        message("  (Grupo ", grupo$nombre, " modo='", grupo$modo,
                "'): paso 0 sólo aplica a grupos 'db'. Se omite.")
        next
      }
      message("[0] Calidad exploratoria · grupo=", grupo$nombre,
              " · variable=", var)
      filtrar_estaciones_grupo(
        connection     = connection,
        grupo          = grupo$nombre,
        filtros        = grupo$filtros,
        variable       = var,
        calidad_minima = 0,
        ano_inicio     = ano_inicio,
        ano_fin        = ano_fin,
        dir_estaciones = dir_estaciones
      )
    }
  }
  generar_graficos_calidad_grupos(
    dir_estaciones = dir_estaciones,
    dir_graficos   = dir_graficos_calidad,
    ano_inicio     = ano_inicio,
    ano_fin        = ano_fin
  )
} else {
  message("--- PASO 0 omitido según config.")
}

# ==============================================================================
# PASO 1 — Selección de estaciones por umbral de calidad y grupo
# ==============================================================================
if (isTRUE(pasos_activos$paso_1_seleccion)) {
  message(">>> PASO 1: Selección de estaciones por calidad")
  for (var in variables_activas) {
    for (grupo in grupos_estaciones) {
      if (!identical(grupo$modo, "db")) {
        message("  (Grupo ", grupo$nombre, " modo='", grupo$modo,
                "'): paso 1 sólo aplica a grupos 'db'. Se omite.")
        next
      }
      message("[1] Selección · grupo=", grupo$nombre, " · variable=", var,
              " · calidad>=", calidad_por_variable[[var]])
      filtrar_estaciones_grupo(
        connection     = connection,
        grupo          = grupo$nombre,
        filtros        = grupo$filtros,
        variable       = var,
        calidad_minima = calidad_por_variable[[var]],
        ano_inicio     = ano_inicio,
        ano_fin        = ano_fin,
        dir_estaciones = dir_estaciones
      )
    }
  }
} else {
  message("--- PASO 1 omitido según config.")
}

# ==============================================================================
# PASO 2 — Descarga de series brutas diarias desde la base de datos
# ==============================================================================
if (isTRUE(pasos_activos$paso_2_series_brutas)) {
  message(">>> PASO 2: Descarga de series brutas")
  for (var in variables_activas) {
    for (grupo in grupos_estaciones) {
      message("[2] Series brutas · grupo=", grupo$nombre,
              " · variable=", var, " · modo=", grupo$modo)
      codigos <- tryCatch(
        get_codigos_grupo(grupo, connection = connection),
        error = function(e) {
          message("  ERROR resolviendo códigos para grupo '", grupo$nombre,
                  "': ", conditionMessage(e))
          character(0)
        }
      )
      if (length(codigos) == 0) {
        message("  (", grupo$nombre, "/", var,
                "): 0 códigos disponibles. Se omite la descarga.")
        next
      }
      obtener_series_brutas(
        connection     = connection,
        grupo          = grupo$nombre,
        variable       = var,
        codigos        = codigos,
        calidad        = calidad_por_variable[[var]],
        ano_inicio     = ano_inicio,
        ano_fin        = ano_fin,
        dir_estaciones = dir_estaciones,
        dir_series     = dir_series_brutas
      )
    }
  }
} else {
  message("--- PASO 2 omitido según config.")
}

# ==============================================================================
# PASO 3 — Depuración de outliers (NA en valores sospechosos)
# ==============================================================================
if (isTRUE(pasos_activos$paso_3_depurado)) {
  message(">>> PASO 3: Depuración de outliers")
  ejecutar_depurado(
    dir_brutas              = dir_series_brutas,
    dir_depurado            = dir_series_depuradas,
    variables_activas       = variables_activas,
    grupos                  = grupo_nombres(),
    calidad_por_variable    = calidad_por_variable,
    ano_inicio              = ano_inicio,
    ano_fin                 = ano_fin,
    usar_limites_fisicos    = depurado_usar_limites_fisicos,
    usar_iqr                = depurado_usar_iqr,
    usar_umbral_estadistico = depurado_usar_umbral_estadistico,
    k_iqr                   = depurado_k_iqr,
    pp_limite_superior_mm   = depurado_pp_limite_superior_mm,
    umbral_pp_media_baja_mm = depurado_pp_media_baja_mm,
    factor_sd               = depurado_factor_sd
  )
} else {
  message("--- PASO 3 omitido según config.")
}

# ==============================================================================
# PASO 4 — Imputación de faltantes con missForest
# ==============================================================================
if (isTRUE(pasos_activos$paso_4_missforest)) {
  message(">>> PASO 4: Rellenado de series con missForest")
  ejecutar_rellenado_missforest(
    dir_depuradas        = dir_series_depuradas,
    dir_rellenas         = dir_series_rellenas,
    variables_activas    = variables_activas,
    grupos               = grupo_nombres(),
    calidad_por_variable = calidad_por_variable,
    ano_inicio           = ano_inicio,
    ano_fin              = ano_fin,
    ntree                = missforest_ntree,
    maxiter              = missforest_maxiter,
    usar_tiempo          = missforest_usar_tiempo
  )
} else {
  message("--- PASO 4 omitido según config.")
}

# ==============================================================================
# PASO 4.5 (opcional) — Filtro espacial por shapefile
# Si está activo, los pasos posteriores usan las series filtradas por shapefile.
# ==============================================================================
dir_series_para_agregar <- dir_series_rellenas
if (isTRUE(pasos_activos$paso_4_5_filtro_shapefile) &&
    isTRUE(usar_filtro_shapefile)) {
  message(">>> PASO 4.5: Filtro espacial por shapefile")
  ejecutar_filtro_shapefile(
    dir_rellenas           = dir_series_rellenas,
    dir_rellenas_filtradas = dir_series_filtradas_shp,
    dir_estaciones         = dir_estaciones,
    dir_shapefiles         = dir_shapefiles,
    dir_mapas              = dir_graficos_mapas_shp,
    grupos                 = grupo_nombres(),
    variables_activas      = variables_activas,
    calidad_por_variable   = calidad_por_variable,
    ano_inicio             = ano_inicio,
    ano_fin                = ano_fin,
    actualizar_estaciones  = TRUE
  )
  dir_series_para_agregar <- dir_series_filtradas_shp
} else {
  message("--- PASO 4.5 omitido según config.")
}

# ==============================================================================
# PASO 5 — Agregación mensual, anual e histórica
# Las tres flags (mensual/anual/historico) se combinan en un único llamado a
# `ejecutar_agregacion()`, que procesa cada nivel individualmente sólo si la
# flag correspondiente está activa.
# ==============================================================================
agregaciones_activas <- c(
  isTRUE(pasos_activos$paso_5_agregacion_mensual),
  isTRUE(pasos_activos$paso_5_1_agregacion_anual),
  isTRUE(pasos_activos$paso_5_2_historico)
)
if (any(agregaciones_activas)) {
  message(">>> PASO 5: Agregación (mensual=",
          pasos_activos$paso_5_agregacion_mensual,
          " · anual=", pasos_activos$paso_5_1_agregacion_anual,
          " · historico=", pasos_activos$paso_5_2_historico, ")")
  ejecutar_agregacion(
    dir_rellenas         = dir_series_para_agregar,
    dir_mensual          = dir_series_mensual,
    dir_anual            = dir_series_anual,
    dir_historico        = dir_series_historico,
    variables_activas    = variables_activas,
    grupos               = grupo_nombres(),
    calidad_por_variable = calidad_por_variable,
    ano_inicio           = ano_inicio,
    ano_fin              = ano_fin,
    metodo_agregacion    = metodo_agregacion,
    excel_consolidado    = TRUE
  )
} else {
  message("--- PASO 5 (agregación) omitido completamente según config.")
}

# ==============================================================================
# PASO 6 — Indicadores climáticos y tendencias decadales
# Consume dir_series_rellenas (o filtradas por shapefile), dir_series_mensual y
# dir_series_anual. No requiere conexión a la DB.
# ==============================================================================
if (isTRUE(pasos_activos$paso_6_indicadores_tendencias)) {
  message(">>> PASO 6: Indicadores climáticos y tendencias decadales")

  # Defaults si el config no trae el bloque específico del paso 6.
  if (!exists("periodo_referencia") || is.null(periodo_referencia)) {
    periodo_referencia <- c(ano_inicio, ano_fin)
  }
  if (!exists("escala_tendencias") || !nzchar(escala_tendencias)) {
    escala_tendencias <- "anual"
  }
  if (!exists("indicadores_activos") || !is.list(indicadores_activos)) {
    indicadores_activos <- list()
  }

  series_procesadas <- preprocesar_series_para_indicadores(
    dir_rellenas         = dir_series_para_agregar,
    dir_mensual          = dir_series_mensual,
    dir_anual            = dir_series_anual,
    grupos_estaciones    = grupos_estaciones,
    variables_activas    = variables_activas,
    calidad_por_variable = calidad_por_variable,
    ano_inicio           = ano_inicio,
    ano_fin              = ano_fin,
    periodo_referencia   = periodo_referencia,
    dir_estaciones       = dir_estaciones
  )

  resultados_indicadores <- calcular_indicadores(
    series_procesadas  = series_procesadas,
    config_indicadores = indicadores_activos,
    variables_activas  = variables_activas,
    dir_salida         = dir_indicadores,
    escala_tendencias  = escala_tendencias
  )

  if (isTRUE(indicadores_activos$tendencias_decadales)) {
    calcular_tendencias_decadales(
      resultados        = resultados_indicadores,
      series_procesadas = series_procesadas,
      indicadores       = indicadores_activos$indicadores_decadales,
      ano_inicio        = ano_inicio,
      ano_fin           = ano_fin,
      dir_salida        = dir_tendencias_decadales
    )
  } else {
    message("--- Tendencias decadales omitidas según config.")
  }
} else {
  message("--- PASO 6 omitido según config.")
}

# ==============================================================================
# PASO 7 — Resumen histórico por estación y división (Excel para informe)
# Requiere paso 5.2 (histórico) y preferiblemente 5.1 (anual) para tendencias.
# ==============================================================================
if (isTRUE(pasos_activos$paso_7_resumen_estaciones)) {
  message(">>> PASO 7: Resumen histórico por estación / división")
  ejecutar_resumen_estaciones_division(
    dir_historico          = dir_series_historico,
    dir_anual              = dir_series_anual,
    dir_tendencias         = dir_tendencias,
    dir_salida             = dir_resumen_estaciones,
    dir_estaciones         = dir_estaciones,
    grupos_estaciones      = grupos_estaciones,
    variables_activas      = variables_activas,
    calidad_por_variable   = calidad_por_variable,
    ano_inicio             = ano_inicio,
    ano_fin                = ano_fin
  )
} else {
  message("--- PASO 7 omitido según config.")
}

# ------------------------------------------------------------------------------
# 8) Cerrar conexión si estaba abierta
# ------------------------------------------------------------------------------
if (!is.null(connection) && DBI::dbIsValid(connection)) {
  DBI::dbDisconnect(connection)
  message("Conexión a la base de datos cerrada.")
}

message("=== Pipeline finalizado correctamente (config: ", config_file, ") ===")
