# CQP: temperature 320048 (Longotoma) -> proxy 320005 (Huaquen) -> SPEI + datos_spei_jv
# Offline only: requires Input/cqp/ (seeded by seed_inputs.R)

repo_root <- Sys.getenv("ASC_REPO_ROOT", unset = getwd())
if (!exists("dir_output_proyecto")) {
  stop("Load config before cqp_temperature.R")
}

COD_PP   <- if (exists("cqp_cod_pp")) cqp_cod_pp else "320005"
COD_TEMP <- if (exists("cqp_cod_temp")) cqp_cod_temp else "320048"
ID_CQP   <- if (exists("cqp_id_subcuenca")) cqp_id_subcuenca else "CQP"
GRUPO    <- "sacbad"
CAL_TEMP <- calidad_por_variable[["temp"]]

dir_scripts <- file.path(repo_root, "Scripts")
dir_output  <- file.path(repo_root, dir_output_proyecto)

dir_series_rellenas  <- file.path(dir_output, "series/rellenas")
dir_series_mensual   <- file.path(dir_output, "series/mensual")
dir_indicadores      <- file.path(dir_output, "indicadores")
dir_cqp              <- file.path(dir_output, "cqp_temp_320048")
dir_entrada_cqp      <- file.path(repo_root, "Input/cqp")

source(file.path(dir_scripts, "librerias.R"))
source(file.path(dir_scripts, "funciones_utilidad.R"))
source(file.path(dir_scripts, "3_depurado.R"))
source(file.path(dir_scripts, "4_missforest.R"))
source(file.path(dir_scripts, "5_agregacion.R"))
source(file.path(dir_scripts, "6_indicadores_tendencias.R"))

dir.create(dir_cqp, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(dir_cqp, "depuradas"), showWarnings = FALSE)
dir.create(file.path(dir_cqp, "rellenas"), showWarnings = FALSE)
dir.create(file.path(dir_cqp, "mensual"), showWarnings = FALSE)

.hydroyear <- function(year, month) {
  ifelse(as.integer(month) >= 4L, as.integer(year), as.integer(year) - 1L)
}

copiar_columna_wide <- function(ruta, cod_origen, cod_destino) {
  if (!file.exists(ruta)) {
    warning("Missing file: ", ruta)
    return(invisible(FALSE))
  }
  df <- leer_csv_robusto(ruta)
  col_orig <- resolver_columna_estacion(df, cod_origen)
  if (is.null(col_orig)) {
    warning("Source column ", cod_origen, " missing in ", basename(ruta))
    return(invisible(FALSE))
  }
  df[[cod_destino]] <- df[[col_orig]]
  escribir_csv_robusto(df, ruta)
  message("  + ", cod_destino, " <- ", cod_origen, " in ", basename(ruta))
  invisible(TRUE)
}

resolver_columna_estacion <- function(df, cod) {
  if (cod %in% names(df)) return(cod)
  hit <- grep(paste0("^", cod, "$"), names(df), value = TRUE)
  if (length(hit)) return(hit[1])
  NULL
}

expandir_wide_a_periodo <- function(ruta, ano_inicio, ano_fin) {
  if (!file.exists(ruta)) return(invisible(FALSE))
  df <- leer_csv_robusto(ruta)
  df$fecha <- as.Date(df$fecha)
  fecha_ini <- as.Date(sprintf("%04d-01-01", ano_inicio))
  fecha_fin <- as.Date(sprintf("%04d-12-31", ano_fin))
  full_dates <- seq.Date(fecha_ini, fecha_fin, by = "day")
  grid <- data.frame(
    fecha = full_dates,
    year  = as.integer(format(full_dates, "%Y")),
    month = as.integer(format(full_dates, "%m")),
    day   = as.integer(format(full_dates, "%d")),
    stringsAsFactors = FALSE
  )
  cols_est <- setdiff(names(df), c("fecha", "year", "month", "day"))
  out <- merge(grid, df, by = c("fecha", "year", "month", "day"), all.x = TRUE)
  out <- out[, c("fecha", "year", "month", "day", cols_est)]
  escribir_csv_robusto(out, ruta)
  message("  grid ", ano_inicio, "-", ano_fin, " (", nrow(out), " days) -> ", basename(ruta))
  invisible(TRUE)
}

fusionar_columna_en_principal <- function(ruta_principal, ruta_aux, cod) {
  if (!file.exists(ruta_aux)) return(invisible(FALSE))
  if (!file.exists(ruta_principal)) {
    warning("Missing main file: ", ruta_principal)
    return(invisible(FALSE))
  }
  main <- leer_csv_robusto(ruta_principal)
  aux  <- leer_csv_robusto(ruta_aux)
  col_aux <- resolver_columna_estacion(aux, cod)
  if (is.null(col_aux)) return(invisible(FALSE))
  main$fecha <- as.Date(main$fecha)
  aux$fecha  <- as.Date(aux$fecha)
  keys <- c("fecha", "year", "month")
  if ("day" %in% names(main) && "day" %in% names(aux)) keys <- c(keys, "day")
  idx <- match(
    do.call(paste, main[, keys, drop = FALSE]),
    do.call(paste, aux[, keys, drop = FALSE])
  )
  main[[cod]] <- aux[[col_aux]][idx]
  escribir_csv_robusto(main, ruta_principal)
  message("  merged ", cod, " into ", basename(ruta_principal))
  invisible(TRUE)
}

message("\n=== CQP: temperature pipeline ", COD_TEMP, " (offline) ===\n")

for (v in c("t_max", "t_min")) {
  nom <- nombre_archivo_estandar(GRUPO, v, CAL_TEMP, ano_inicio, ano_fin, "_bruta")
  src <- file.path(dir_entrada_cqp, nom)
  dest <- file.path(dir_cqp, nom)
  if (!file.exists(src)) {
    stop("Missing CQP raw file: ", src, "\nPlace CSVs in Input/cqp/ (see Input/README.md).")
  }
  file.copy(src, dest, overwrite = TRUE)
  message("  CQP raw: ", nom)
}

for (v in c("t_max", "t_min")) {
  expandir_wide_a_periodo(
    file.path(dir_cqp, nombre_archivo_estandar(GRUPO, v, CAL_TEMP, ano_inicio, ano_fin, "_bruta")),
    ano_inicio,
    ano_fin
  )
}

ejecutar_depurado(
  dir_brutas              = dir_cqp,
  dir_depurado            = file.path(dir_cqp, "depuradas"),
  variables_activas       = "temp",
  grupos                  = GRUPO,
  calidad_por_variable    = calidad_por_variable,
  ano_inicio              = ano_inicio,
  ano_fin                 = ano_fin,
  usar_limites_fisicos    = depurado_usar_limites_fisicos,
  usar_iqr                = depurado_usar_iqr,
  usar_umbral_estadistico = depurado_usar_umbral_estadistico,
  k_iqr                   = depurado_k_iqr,
  pp_limite_superior_mm   = depurado_pp_limite_superior_mm,
  umbral_pp_media_baja_mm = depurado_pp_media_baja_mm,
  factor_sd               = depurado_factor_sd,
  verbose                 = TRUE
)

ejecutar_rellenado_missforest(
  dir_depuradas        = file.path(dir_cqp, "depuradas"),
  dir_rellenas         = file.path(dir_cqp, "rellenas"),
  variables_activas    = "temp",
  grupos               = GRUPO,
  calidad_por_variable = calidad_por_variable,
  ano_inicio           = ano_inicio,
  ano_fin              = ano_fin,
  ntree                = missforest_ntree,
  maxiter              = missforest_maxiter,
  usar_tiempo          = missforest_usar_tiempo,
  verbose              = TRUE
)

ejecutar_agregacion(
  dir_rellenas         = file.path(dir_cqp, "rellenas"),
  dir_mensual          = file.path(dir_cqp, "mensual"),
  dir_anual            = file.path(dir_cqp, "anual"),
  dir_historico        = file.path(dir_cqp, "historico"),
  variables_activas    = "temp",
  grupos               = GRUPO,
  calidad_por_variable = calidad_por_variable,
  ano_inicio           = ano_inicio,
  ano_fin              = ano_fin,
  metodo_agregacion    = metodo_agregacion,
  excel_consolidado    = FALSE
)

message("\n=== CQP: temperature proxy ", COD_TEMP, " -> ", COD_PP, " ===\n")

for (v in c("t_max", "t_min")) {
  for (suf in c("_rellena", "_mensual")) {
    dir_aux <- if (suf == "_rellena") dir_series_rellenas else dir_series_mensual
    ruta_aux <- file.path(
      dir_cqp,
      if (suf == "_rellena") "rellenas" else "mensual",
      nombre_archivo_estandar(GRUPO, v, CAL_TEMP, ano_inicio, ano_fin, sufijo = suf)
    )
    ruta_pri <- file.path(
      dir_aux,
      nombre_archivo_estandar(GRUPO, v, CAL_TEMP, ano_inicio, ano_fin, sufijo = suf)
    )
    fusionar_columna_en_principal(ruta_pri, ruta_aux, COD_TEMP)
    copiar_columna_wide(ruta_pri, COD_TEMP, COD_PP)
  }
}

message("\n=== CQP: SPEI (PP ", COD_PP, " + temperature proxy) ===\n")

meta_pp <- leer_csv_autodetect(
  file.path(repo_root, "Input/metadata/estaciones_sacbad_pp70.csv")
)
lat_cqp <- suppressWarnings(as.numeric(
  meta_pp$Latitud[trimws(as.character(meta_pp$Codigo_nacional)) == COD_PP][1]
))
if (!is.finite(lat_cqp)) lat_cqp <- -32.28417

pp_m <- leer_csv_robusto(file.path(
  dir_series_mensual,
  nombre_archivo_estandar(GRUPO, "pp", calidad_por_variable[["pp"]],
                          ano_inicio, ano_fin, "_mensual")
))
tmax_m <- leer_csv_robusto(file.path(
  dir_series_mensual,
  nombre_archivo_estandar(GRUPO, "t_max", CAL_TEMP, ano_inicio, ano_fin, "_mensual")
))
tmin_m <- leer_csv_robusto(file.path(
  dir_series_mensual,
  nombre_archivo_estandar(GRUPO, "t_min", CAL_TEMP, ano_inicio, ano_fin, "_mensual")
))

cols_meta <- c("fecha", "year", "month")
pp_sub   <- pp_m[, c(cols_meta, COD_PP)]
tmax_sub <- tmax_m[, c(cols_meta, COD_PP)]
tmin_sub <- tmin_m[, c(cols_meta, COD_PP)]

series_cqp <- list(
  sacbad = list(
    pp = list(mensual = pp_sub, diaria = NULL, anual = NULL, anomalias_mensual = NULL),
    t_max = list(mensual = tmax_sub, diaria = NULL, anual = NULL, anomalias_mensual = NULL),
    t_min = list(mensual = tmin_sub, diaria = NULL, anual = NULL, anomalias_mensual = NULL),
    meta = list(
      grupo = GRUPO,
      calidades = c(pp = calidad_por_variable[["pp"]], t_max = CAL_TEMP, t_min = CAL_TEMP),
      ano_inicio = ano_inicio,
      ano_fin = ano_fin,
      periodo_referencia = c(ano_inicio, ano_fin),
      latitudes = stats::setNames(lat_cqp, COD_PP)
    )
  )
)

ind_cfg <- indicadores_activos
ind_cfg$tendencia_mann_kendall <- FALSE
ind_cfg$tendencia_theil_sen <- FALSE
ind_cfg$extremos_precipitacion <- FALSE
ind_cfg$extremos_temperatura <- FALSE
ind_cfg$spi <- FALSE
ind_cfg$spei <- TRUE

res_spei <- calcular_indicadores(
  series_procesadas  = series_cqp,
  config_indicadores = ind_cfg,
  variables_activas  = c("pp", "temp"),
  dir_salida         = dir_cqp,
  escala_tendencias  = "anual"
)

fusionar_spei_wide <- function(escala) {
  etq <- paste0("spei_", escala)
  nuevo <- res_spei$spei$wide_por_escala[[paste0(etq, "__", GRUPO)]]
  if (is.null(nuevo)) return(invisible(NULL))
  ruta <- file.path(
    dir_indicadores,
    nombre_archivo_estandar(GRUPO, etq, CAL_TEMP, ano_inicio, ano_fin)
  )
  if (!file.exists(ruta)) {
    escribir_csv_robusto(nuevo, ruta)
    message("  created ", basename(ruta))
    return(invisible(NULL))
  }
  old <- leer_csv_robusto(ruta)
  old[[COD_PP]] <- nuevo[[COD_PP]]
  escribir_csv_robusto(old, ruta)
  message("  updated column ", COD_PP, " in ", basename(ruta))
}

for (esc in indicadores_activos$spei_escalas %||% c(3, 6, 12)) {
  fusionar_spei_wide(esc)
}

ruta_long_new <- file.path(
  dir_cqp,
  nombre_archivo_estandar(GRUPO, "spei_long", CAL_TEMP, ano_inicio, ano_fin)
)
ruta_long_main <- file.path(
  dir_indicadores,
  nombre_archivo_estandar(GRUPO, "spei_long", CAL_TEMP, ano_inicio, ano_fin)
)
if (file.exists(ruta_long_new) && file.exists(ruta_long_main)) {
  old_l <- leer_csv_robusto(ruta_long_main)
  new_l <- leer_csv_robusto(ruta_long_new)
  old_l <- old_l[old_l$estacion != COD_PP, , drop = FALSE]
  new_l <- new_l[new_l$estacion == COD_PP, , drop = FALSE]
  comb <- rbind(old_l, new_l)
  escribir_csv_robusto(comb, ruta_long_main)
  message("  updated ", basename(ruta_long_main))
}

message("\n=== CQP: datos_spei_jv.csv ===\n")

spei12 <- res_spei$spei$long
spei12 <- spei12[spei12$estacion == COD_PP & spei12$escala == 12L, , drop = FALSE]
spei12$fecha <- as.Date(spei12$fecha)
spei12$year  <- as.integer(format(spei12$fecha, "%Y"))
spei12$month <- as.integer(format(spei12$fecha, "%m"))
spei12$hydro_year <- .hydroyear(spei12$year, spei12$month)

mean_finite <- function(x) {
  x <- as.numeric(x)
  if (!any(is.finite(x))) return(NA_real_)
  mean(x, na.rm = TRUE)
}

hydro_avg <- stats::aggregate(spei ~ hydro_year, spei12, mean_finite)
names(hydro_avg)[2] <- "SPEI-12 Hydro avg"
sep_df <- spei12[spei12$month == 9L, c("hydro_year", "spei")]
names(sep_df)[2] <- "SPEI-12 September"
dec_df <- spei12[spei12$month == 12L, c("hydro_year", "spei")]
names(dec_df)[2] <- "SPEI-12 December"
cal_df <- stats::aggregate(spei ~ year, spei12, mean_finite)
names(cal_df) <- c("hydro_year", "SPEI12anual_est")

tab_cqp <- merge(hydro_avg, sep_df, by = "hydro_year", all = TRUE)
tab_cqp <- merge(tab_cqp, dec_df, by = "hydro_year", all = TRUE)
tab_cqp <- merge(tab_cqp, cal_df, by = "hydro_year", all.x = TRUE)
tab_cqp$SPEI12sep_est <- tab_cqp$`SPEI-12 September`
tab_cqp$SPEI12dic_est <- tab_cqp$`SPEI-12 December`
tab_cqp$ID <- ID_CQP

ruta_jv <- file.path(dir_output, "Correlaciones_NDVI/datos_spei_jv.csv")
dir.create(dirname(ruta_jv), recursive = TRUE, showWarnings = FALSE)
if (file.exists(ruta_jv)) {
  jv <- read.csv(ruta_jv, stringsAsFactors = FALSE, check.names = FALSE)
  jv <- jv[jv$ID != ID_CQP, , drop = FALSE]
} else {
  jv <- data.frame()
}
jv_out <- rbind(
  jv,
  tab_cqp[, c("ID", "hydro_year", "SPEI-12 Hydro avg", "SPEI-12 September",
              "SPEI-12 December", "SPEI12anual_est", "SPEI12sep_est", "SPEI12dic_est")]
)
write.csv(jv_out, ruta_jv, row.names = FALSE, fileEncoding = "UTF-8")
message("  -> ", ruta_jv, " (", sum(jv_out$ID == ID_CQP), " CQP rows)")

mensual_export <- pp_sub
names(mensual_export)[names(mensual_export) == COD_PP] <- "pp"
mensual_export$t_max <- tmax_sub[[COD_PP]]
mensual_export$t_min <- tmin_sub[[COD_PP]]
mensual_export$ID_subcuenca <- ID_CQP
mensual_export$Name_subcuenca <- "Costeras Quilimari-Petorca"
mensual_export$spei_12 <- spei12$spei[match(
  paste(mensual_export$year, mensual_export$month),
  paste(spei12$year, spei12$month)
)]

out_mensual <- file.path(dir_cqp, "CQP_mensual_pp_temp_spei_1988_2024.csv")
write.csv(mensual_export, out_mensual, row.names = FALSE, fileEncoding = "UTF-8")
message("  -> ", out_mensual)

message("\n=== CQP temperature step complete ===")
