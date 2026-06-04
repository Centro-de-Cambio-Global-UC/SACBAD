# =============================================================================
# SACBAD configuration (paper supplementary — no database)
# =============================================================================

use_database <- FALSE
modo_entrada <- "archivo_brutas"
dir_series_brutas_entrada <- "Input/series_brutas"
dir_cqp_brutas_entrada    <- "Input/cqp"

pasos_activos <- list(
  paso_0_calidad_estaciones     = FALSE,
  paso_1_seleccion              = FALSE,
  paso_2_series_brutas          = FALSE,
  paso_3_depurado               = TRUE,
  paso_4_missforest             = TRUE,
  paso_4_5_filtro_shapefile     = FALSE,
  paso_5_agregacion_mensual     = TRUE,
  paso_5_1_agregacion_anual     = TRUE,
  paso_5_2_historico            = TRUE,
  paso_6_indicadores_tendencias = TRUE,
  paso_7_resumen_estaciones     = TRUE
)

ano_inicio <- 1988
ano_fin    <- 2024

variables_activas <- c("pp", "temp")
calidad_por_variable <- c(pp = 70, temp = 60, q = 60)

modo_estaciones <- "archivo"
grupos_estaciones <- list(
  list(
    nombre         = "sacbad",
    modo           = "archivo",
    archivo_fuente = "Input/metadata/estaciones_sacbad_pp70.csv",
    columna_codigo = "Codigo_nacional",
    filtros        = list()
  )
)

dir_output_proyecto <- "Output"

missforest_ntree       <- 100
missforest_maxiter     <- 10
missforest_usar_tiempo <- TRUE

depurado_k_iqr                   <- 1.5
depurado_usar_limites_fisicos    <- TRUE
depurado_usar_iqr                <- TRUE
depurado_usar_umbral_estadistico <- TRUE
depurado_pp_limite_superior_mm   <- 200
depurado_pp_media_baja_mm        <- 100
depurado_factor_sd               <- 10

metodo_agregacion <- list(
  pp   = "suma",
  temp = "promedio",
  q    = "promedio"
)

usar_filtro_shapefile <- FALSE

periodo_referencia <- c(ano_inicio, ano_fin)
escala_tendencias  <- "anual"

indicadores_activos <- list(
  tendencia_mann_kendall = FALSE,
  tendencia_theil_sen    = FALSE,
  extremos_precipitacion = FALSE,
  extremos_temperatura   = FALSE,
  spi                    = TRUE,
  spi_escalas            = c(3, 6, 12),
  spei                   = TRUE,
  spei_escalas           = c(3, 6, 12),
  spei_metodo_etp        = "hargreaves",
  spi_tratar_no_finitos  = "cap",
  spi_limite_extremos    = 4,
  spei_tratar_no_finitos = "cap",
  spei_limite_extremos   = 4,
  tendencias_decadales   = FALSE,
  indicadores_decadales  = character(0)
)

cqp_cod_pp         <- "320005"
cqp_cod_temp       <- "320048"
cqp_id_subcuenca   <- "CQP"
