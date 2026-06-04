# 02. CORRELACIONES

# Objetivo, obtener valores de correlacion significativos para todas las subcuencas, 
# entre SPEI-12 anual, septiembre y diciembre y NDVI anual, primavera y verano. 

library(sp)
library(raster)
library(terra)
library(ggplot2)
library(tidyverse)
library(readxl)
library(caret)
library(rasterVis)
library(doParallel)
library(dplyr)
library(readr)
library(terra)
library(data.table)
library(doParallel)

ep <- Sys.getenv("ASC_EXTENDED_PATHS", unset = file.path(getwd(), "..", "extended_paths.R"))
if (!file.exists(ep)) ep <- file.path(getwd(), "Scripts", "extended", "extended_paths.R")
source(ep)
extended_use_module("ndvi_spei_correlations")
# Expect NDVI GeoTIFF stacks and subcuenca shapefile in this working directory
# (see Scripts/extended/README.md).

# Subir serie temporal ----------------------------------------------------
# Subir serie temporal: verano, primavera, anual

rasList <- list.files("./NDVI_verano/", pattern="tif$", full.names=TRUE) 

ndvi <- rast(rasList) 
names(ndvi)

años <- as.character(c(1990:2023))
names(ndvi) <- años  
names(ndvi)

# Valores de las celdas por subcuencas -----------------------------------------
# 10 subcuencas

subcuencas <- vect("./subcuencas_nombres/subcuencas_nombres.shp")
plot(ndvi[[20]])
plot(subcuencas, add = TRUE)

#str(subcuencas)
data_subc <- as.data.frame(subcuencas)

# Cambiar id subcuenca
#data_subc <- data_subc %>% 
#  mutate(ID = 
#           case_when(
#             Nombre == "Costeras Quilimari-Petorca" ~ "CQP", 
#             Nombre == "Rio Petorca Medio" ~ "MP",
#             Nombre == "Rio Ligua Alto (Estero Alicahue)" ~ "UL",
#             Nombre == "Rio Ligua Bajo (entre Estero Los Angeles y Desembocadura)" ~ "LL",
#             Nombre == "Rio Ligua Medio (entre Quebrada La Cerrada y Los Angeles)" ~ "ML",
#             Nombre == "Rio Petorca Alto (hasta despues Junta Rio Sobrante)" ~ "UP",
#             Nombre == "Rio Petorca Bajo (entre Las Palmas y Desembocadura)" ~ "LP",
#             Nombre == "Rio Quilimari entre Cajo Ingienillo y Desembocadura" ~ "LQ",
#             Nombre == "Rio Quilimari entre muro Embalse Culimo y Bajo Cajon Ingienillo" ~ "MQ",
#             Nombre == "Rio Quilimari hasta muro Embalse Culimo" ~ "UQ"
#           )
#  )


#write_csv(data_subc, "ID_subcuencas.csv")

data_subc <- read.csv("ID_subcuencas.csv")

# Extraer valores de ndvi delimitado por las subcuencas

#detectCores()

#cl <- makePSOCKcluster(7)
#registerDoParallel(cl)
#timeStart<- proc.time()

ndvi_subcuencas <- terra::extract(ndvi, subcuencas, fun=NULL, na.rm=FALSE,
                                  cells= TRUE)
#proc.time() - timeStart
#stopCluster(cl)

# Pre proceso con NDVI -------------------------------------------------------
# Esto se repite para cada subcuenca (cada ID)

# Crear columna con datos estandarizados --> NDVI_est

names(ndvi_subcuencas)
head(ndvi_subcuencas)

data <- ndvi_subcuencas %>% filter(ID == 1) %>% as_tibble()
data_subc[10,] # UP - MP - LP - CQP - UL - ML - LL - MQ - LQ - UQ - 
N <- "UQ"

cols_to_scale <- names(data)[2:(length(data)-1)]
cols_to_scale

data_scaled <- data %>%
  mutate(across(.cols = all_of(cols_to_scale),.fns = ~ as.vector(scale(.))))

NDVI <- data_scaled %>% 
  mutate(ID = N) %>%      #          Agregar columna con ID = subcuenca (1 - 10)
  dplyr::select(ID, cell, `1990`:`2023`)

unique(NDVI$ID)
names(NDVI)
head(NDVI)

write_csv(NDVI, paste0("./NDVI_ver_est_csv/NDVI_",N,"ver_est.csv"))

# Objetos constantes
datos_SPEIest <- read_csv("datos_SPEI_2026.csv")
datos_SPEIest <- datos_SPEIest %>% select(ID,hydro_year,SPEI12anual_est,SPEI12sep_est,SPEI12dic_est)
data_subc <- read_csv("ID_subcuencas.csv")
base <- rast("base.tif")
plot(base)

años <- as.character(c(1990:2023))

n_rows <- nrow(base)
n_cols <- ncol(base)
n_cells <- ncell(base) 


# 1. loop NDVI prim con SPEI anual / SPEIsep / SPEIdic  --------------------------------------------

ruta <- "./Correlaciones/NDVI primavera/"

# Correr este loop para los datos de NDVI primavera
# De forma manual se modifica las lineas donde sale "Opciones: ...". Se cambia para hacer las siguientes combinaciones: NDVI primavera - SPEI anual; NDVI primavera - SPEI septiembre; NDVI primavera - SPEI diciembre;  
# Se deben primero crear las carpetas de salida antes de correr el loop


# Objetos constantes
datos_SPEIest <- read_csv2("datos_SPEIest2.csv") # subir SPEI estandarizado
datos_SPEIest <- datos_SPEIest %>% select(ID,hydro_year,SPEI12anual_est,SPEI12sep_est,SPEI12dic_est) %>% arrange(hydro_year)

data_subc <- read_csv("ID_subcuencas.csv")
base <- rast("base.tif")

años <- as.character(c(1990:2023))

n_rows <- nrow(base)
n_cols <- ncol(base)
n_cells <- ncell(base) 


for (i in c(1:10))   
  
  id <- data_subc[i,]$ID
  
  NDVI <- read_csv(paste0("./NDVI_prim_est_csv/NDVI_", id, "prim_est.csv"))
  
  SPEI <- datos_SPEIest %>% filter(ID == id)
  
  SPEI <- SPEI %>% 
    dplyr::select(hydro_year:SPEI12dic_est)
  
  SPEI <- SPEI %>%
    pivot_longer(cols = -hydro_year, names_to = "SPEI", values_to = "value") %>%
    pivot_wider(names_from = hydro_year, values_from = value)
  
  names(NDVI) <- c('ID', 'cell', años)
  
  SPEI12dic_est <- SPEI %>%
    filter(SPEI == "SPEI12dic_est") %>%   # Opciones: SPEI12anual_est / SPEI12sep_est / SPEI12dic_est 
    dplyr::select(-SPEI) %>%
    t() %>%
    as.vector()
  
  #num_cores <- 7 
  #cl <- makeCluster(num_cores)
  #registerDoParallel(cl)
  
  NDVI_subset <- NDVI %>% dplyr::select(ID, cell, '1991':'2022')
  
  calc_correlation <- function(row) {
    ndvi_values <- as.numeric(row[3:34])
    cor_test <- cor.test(ndvi_values, SPEI12dic_est) # Opciones: SPEI12anual_est / SPEI12sep_est / SPEI12dic_est
    c(row[1:2], cor_test$estimate, cor_test$p.value)
  }
  
  results <- foreach(i = 1:nrow(NDVI_subset), .combine = rbind, 
                     .packages = c("stats")) %dopar% {
                       calc_correlation(NDVI_subset[i,])
                     }
  #stopCluster(cl)
  
  results_df <- as.data.frame(results)
  colnames(results_df) <- c("ID", "cell", "correlation", "p_value")
  
  fwrite(results_df, paste0(ruta, "03_NDVIprim_SPEIdic/", id, "_NDVIprim_SPEIdic.csv")) # Opciones: "./01_NDVIprim_SPEIanual/", id, "_NDVIprim_SPEIanual.csv" ó "./02_NDVIprim_SPEIsep/", id, "_NDVIprim_SPEIsep.csv" ó "./03_NDVIprim_SPEIdic/", id, "_NDVIprim_SPEIdic.csv"
  
  datos <- fread(paste0(ruta, "03_NDVIprim_SPEIdic/", id, "_NDVIprim_SPEIdic.csv")) # Opciones: "./01_NDVIprim_SPEIanual/", id, "_NDVIprim_SPEIanual.csv" ó "./02_NDVIprim_SPEIsep/", id, "_NDVIprim_SPEIsep.csv" ó "./03_NDVIprim_SPEIdic/", id, "_NDVIprim_SPEIdic.csv"
  
  #cl <- makeCluster(7)
  #registerDoParallel(cl)
  
  #timeStart <- proc.time()
  
  results <- foreach(i = 1:nrow(datos), .combine = 'rbind', .packages = 'data.table') %dopar% {
    cell_number <- datos$cell[i]
    correlation_value <- datos$correlation[i]
    p_value_value <- datos$p_value[i]
    
    if (cell_number >= 1 && cell_number <= n_cells) {
      row <- ceiling(cell_number / n_cols)
      col <- cell_number - (row - 1) * n_cols
      data.table(row = row, col = col, correlation = correlation_value, p_value = p_value_value)
    } else {
      NULL
    }
  }
  
  #stopCluster(cl)
  #proc.time() - timeStart
  
  correlation_matrix <- matrix(NA, nrow = n_rows, ncol = n_cols)
  pvalue_matrix <- matrix(NA, nrow = n_rows, ncol = n_cols)
  
  for (i in 1:nrow(results)) {
    correlation_matrix[results$row[i], results$col[i]] <- results$correlation[i]
    pvalue_matrix[results$row[i], results$col[i]] <- results$p_value[i]
  }
  
  correlation_layer <- rast(correlation_matrix, extent = ext(base), crs = crs(base))
  pvalue_layer <- rast(pvalue_matrix, extent = ext(base), crs = crs(base))
  
  writeRaster(correlation_layer, paste0(ruta,"03_NDVIprim_SPEIdic/", id, "_NDVIprim_SPEIdic_correlation.tif"), overwrite = TRUE) # Opciones: "./01_NDVIprim_SPEIanual/", id, "_NDVIprim_SPEIanual_correlation.tif" ó "./02_NDVIprim_SPEIsep/", id, "_NDVIprim_SPEIsep_correlation.tif" ó "./03_NDVIprim_SPEIdic/", id, "_NDVIprim_SPEIdic_correlation.tif"
  writeRaster(pvalue_layer, paste0(ruta, "03_NDVIprim_SPEIdic/", id, "_NDVIprim_SPEIdic_pvalue.tif"), overwrite = TRUE) # Opciones: "./01_NDVIprim_SPEIanual/", id, "_NDVIprim_SPEIanual_pvalue.tif" ó "./02_NDVIprim_SPEIsep/", id, "_NDVIprim_SPEIsep_pvalue.tif" ó "./03_NDVIprim_SPEIdic/", id, "_NDVIprim_SPEIdic_pvalue.tif"
  
  cat(id, "CORR Y VALOR P-GUARDADOS\n")
}

# 2. loop NDVI ver con SPEI anual / SPEIsep / SPEIdic  --------------------------------------------

ruta <- "./Correlaciones/NDVI verano/"

# Correr este loop para los datos de NDVI verano
# De forma manual se modifica las lineas donde sale "Opciones: ...". Se cambia para hacer las siguientes combinaciones: NDVI verano - SPEI anual; NDVI verano - SPEI septiembre; NDVI verano - SPEI diciembre;  
# Se deben primero crear las carpetas de salida antes de correr el loop

# Objetos constantes
datos_SPEIest <- read_csv2("datos_SPEIest2.csv") # subir SPEI estandarizado
datos_SPEIest <- datos_SPEIest %>% select(ID,hydro_year,SPEI12anual_est,SPEI12sep_est,SPEI12dic_est) %>% arrange(hydro_year)

data_subc <- read_csv("ID_subcuencas.csv")
base <- rast("base.tif")

años <- as.character(c(1990:2023))

n_rows <- nrow(base)
n_cols <- ncol(base)
n_cells <- ncell(base) 

for (i in c(1:10)) {
  
  id <- data_subc[i,]$ID
  
  NDVI <- read_csv(paste0("./NDVI_ver_est_csv/NDVI_", id, "ver_est.csv"))
  
  SPEI <- datos_SPEIest %>% filter(ID == id)
  
  SPEI <- SPEI %>% 
    dplyr::select(hydro_year:SPEI12dic_est)
  
  SPEI <- SPEI %>%
    pivot_longer(cols = -hydro_year, names_to = "SPEI", values_to = "value") %>%
    pivot_wider(names_from = hydro_year, values_from = value)
  
  names(NDVI) <- c('ID', 'cell', años)
  
  SPEI12anual_est <- SPEI %>%
    filter(SPEI == "SPEI12anual_est") %>%   # Opciones: SPEI12anual_est / SPEI12sep_est / SPEI12dic_est
    dplyr::select(-SPEI) %>%
    t() %>%
    as.vector()
  
  #num_cores <- 7 
  #cl <- makeCluster(num_cores)
  #registerDoParallel(cl)
  
  NDVI_subset <- NDVI %>% dplyr::select(ID, cell, '1991':'2022')
  
  calc_correlation <- function(row) {
    ndvi_values <- as.numeric(row[3:34])
    cor_test <- cor.test(ndvi_values, SPEI12anual_est) # Opciones: SPEI12anual_est / SPEI12sep_est / SPEI12dic_est
    c(row[1:2], cor_test$estimate, cor_test$p.value)
  }
  
  results <- foreach(i = 1:nrow(NDVI_subset), .combine = rbind, 
                     .packages = c("stats")) %dopar% {
                       calc_correlation(NDVI_subset[i,])
                     }
  #stopCluster(cl)
  
  results_df <- as.data.frame(results)
  colnames(results_df) <- c("ID", "cell", "correlation", "p_value")
  
  fwrite(results_df, paste0(ruta, "01_NDVIver_SPEIanual/", id, "_NDVIver_SPEIanual.csv")) # Opciones: "./01_NDVIver_SPEIver/", id, "_NDVIver_SPEIver.csv" ó "./02_NDVIver_SPEIsep/", id, "_NDVIver_SPEIsep.csv" ó "./03_NDVIver_SPEIdic/", id, "_NDVIprim_SPEIdic.csv"
  
  datos <- fread(paste0(ruta, "01_NDVIver_SPEIanual/", id, "_NDVIver_SPEIanual.csv")) # Opciones: "./01_NDVIver_SPEIver/", id, "_NDVIver_SPEIver.csv" ó "./02_NDVIver_SPEIsep/", id, "_NDVIver_SPEIsep.csv" ó "./03_NDVIver_SPEIdic/", id, "_NDVIprim_SPEIdic.csv"
  
  #cl <- makeCluster(7)
  #registerDoParallel(cl)
  
  #timeStart <- proc.time()
  
  results <- foreach(i = 1:nrow(datos), .combine = 'rbind', .packages = 'data.table') %dopar% {
    cell_number <- datos$cell[i]
    correlation_value <- datos$correlation[i]
    p_value_value <- datos$p_value[i]
    
    if (cell_number >= 1 && cell_number <= n_cells) {
      row <- ceiling(cell_number / n_cols)
      col <- cell_number - (row - 1) * n_cols
      data.table(row = row, col = col, correlation = correlation_value, p_value = p_value_value)
    } else {
      NULL
    }
  }
  
  #stopCluster(cl)
  #proc.time() - timeStart
  
  correlation_matrix <- matrix(NA, nrow = n_rows, ncol = n_cols)
  pvalue_matrix <- matrix(NA, nrow = n_rows, ncol = n_cols)
  
  for (i in 1:nrow(results)) {
    correlation_matrix[results$row[i], results$col[i]] <- results$correlation[i]
    pvalue_matrix[results$row[i], results$col[i]] <- results$p_value[i]
  }
  
  correlation_layer <- rast(correlation_matrix, extent = ext(base), crs = crs(base))
  pvalue_layer <- rast(pvalue_matrix, extent = ext(base), crs = crs(base))
  
  writeRaster(correlation_layer, paste0(ruta, "01_NDVIver_SPEIanual/", id, "_NDVIver_SPEIanual_correlation.tif"), overwrite = TRUE) # Opciones: "./01_NDVIver_SPEIanual/", id, "_NDVIver_SPEIanual_correlation.tif" ó "./02_NDVIver_SPEIsep/", id, "_NDVIver_SPEIsep_correlation.tif" ó "./03_NDVIver_SPEIdic/", id, "_NDVIver_SPEIdic_correlation.tif"
  writeRaster(pvalue_layer, paste0(ruta, "01_NDVIver_SPEIanual/", id, "_NDVIver_SPEIanual_pvalue.tif"), overwrite = TRUE) # Opciones: "./01_NDVIver_SPEIanual/", id, "_NDVIver_SPEIanual_pvalue.tif" ó "./02_NDVIver_SPEIsep/", id, "_NDVIver_SPEIsep_pvalue.tif" ó "./03_NDVIver_SPEIdic/", id, "_NDVIver_SPEIdic_pvalue.tif"
  
  cat(id, "CORR Y VALOR P-GUARDADOS\n")
}

# 3. loop NDVI anual con SPEI anual / SPEIsep / SPEIdic  --------------------------------------------

ruta <- "./Correlaciones/NDVI anual/"

# Correr este loop para los datos de NDVI anual
# De forma manual se modifica las lineas donde sale "Opciones: ...". Se cambia para hacer las siguientes combinaciones: NDVI verano - SPEI anual; NDVI verano - SPEI septiembre; NDVI verano - SPEI diciembre;  
# Se deben primero crear las carpetas de salida antes de correr el loop

# Objetos constantes
datos_SPEIest <- read_csv2("datos_SPEIest2.csv") # subir SPEI estandarizado
datos_SPEIest <- datos_SPEIest %>% select(ID,hydro_year,SPEI12anual_est,SPEI12sep_est,SPEI12dic_est) %>% arrange(hydro_year)

data_subc <- read_csv("ID_subcuencas.csv")
base <- rast("base.tif")

años <- as.character(c(1990:2023))

n_rows <- nrow(base)
n_cols <- ncol(base)
n_cells <- ncell(base) 

for (i in c(1:10)) {
  
  id <- data_subc[i,]$ID
  
  NDVI <- read_csv(paste0("./NDVI_anual_est_csv/NDVI_", id, "anual_est.csv"))
  
  SPEI <- datos_SPEIest %>% filter(ID == id)
  
  SPEI <- SPEI %>% 
    dplyr::select(hydro_year:SPEI12dic_est)
  
  SPEI <- SPEI %>%
    pivot_longer(cols = -hydro_year, names_to = "SPEI", values_to = "value") %>%
    pivot_wider(names_from = hydro_year, values_from = value)
  
  names(NDVI) <- c('ID', 'cell', años)
  
  SPEI12dic_est <- SPEI %>%
    filter(SPEI == "SPEI12dic_est") %>%   # Opciones: SPEI12anual_est / SPEI12sep_est / SPEI12dic_est
    dplyr::select(-SPEI) %>%
    t() %>%
    as.vector()
  
  #num_cores <- 7 
  #cl <- makeCluster(num_cores)
  #registerDoParallel(cl)
  
  NDVI_subset <- NDVI %>% dplyr::select(ID, cell, '1991':'2022')
  
  calc_correlation <- function(row) {
    ndvi_values <- as.numeric(row[3:34])
    cor_test <- cor.test(ndvi_values, SPEI12dic_est) # Opciones: SPEI12anual_est / SPEI12sep_est / SPEI12dic_est
    c(row[1:2], cor_test$estimate, cor_test$p.value)
  }
  
  results <- foreach(i = 1:nrow(NDVI_subset), .combine = rbind, 
                     .packages = c("stats")) %dopar% {
                       calc_correlation(NDVI_subset[i,])
                     }
  #stopCluster(cl)
  
  results_df <- as.data.frame(results)
  colnames(results_df) <- c("ID", "cell", "correlation", "p_value")
  
  fwrite(results_df, paste0(ruta, "03_NDVIanual_SPEIdic/", id, "_NDVIprim_SPEIdic.csv")) # Opciones: "./01_NDVIanual_SPEIanual/", id, "_NDVIanual_SPEIanual.csv" ó "./02_NDVIanual_SPEIsep/", id, "_NDVIanual_SPEIsep.csv" ó "./03_NDVIanual_SPEIdic/", id, "_NDVIprim_SPEIdic.csv"
  
  datos <- fread(paste0(ruta, "03_NDVIanual_SPEIdic/", id, "_NDVIprim_SPEIdic.csv")) # Opciones: "./01_NDVIanual_SPEIanual/", id, "_NDVIanual_SPEIanual.csv" ó "./02_NDVIanual_SPEIsep/", id, "_NDVIanual_SPEIsep.csv" ó "./03_NDVIanual_SPEIdic/", id, "_NDVIprim_SPEIdic.csv"
  
  #cl <- makeCluster(7)
  #registerDoParallel(cl)
  
  #timeStart <- proc.time()
  
  results <- foreach(i = 1:nrow(datos), .combine = 'rbind', .packages = 'data.table') %dopar% {
    cell_number <- datos$cell[i]
    correlation_value <- datos$correlation[i]
    p_value_value <- datos$p_value[i]
    
    if (cell_number >= 1 && cell_number <= n_cells) {
      row <- ceiling(cell_number / n_cols)
      col <- cell_number - (row - 1) * n_cols
      data.table(row = row, col = col, correlation = correlation_value, p_value = p_value_value)
    } else {
      NULL
    }
  }
  
 # stopCluster(cl)
 # proc.time() - timeStart
  
  correlation_matrix <- matrix(NA, nrow = n_rows, ncol = n_cols)
  pvalue_matrix <- matrix(NA, nrow = n_rows, ncol = n_cols)
  
  for (i in 1:nrow(results)) {
    correlation_matrix[results$row[i], results$col[i]] <- results$correlation[i]
    pvalue_matrix[results$row[i], results$col[i]] <- results$p_value[i]
  }
  
  correlation_layer <- rast(correlation_matrix, extent = ext(base), crs = crs(base))
  pvalue_layer <- rast(pvalue_matrix, extent = ext(base), crs = crs(base))
  
  writeRaster(correlation_layer, paste0(ruta, "03_NDVIanual_SPEIdic/", id, "_NDVIanual_SPEIdic_correlation.tif"), overwrite = TRUE) # Opciones: "./01_NDVIanual_SPEIanual/", id, "_NDVIanual_SPEIanual_correlation.tif" ó "./02_NDVIanual_SPEIsep/", id, "_NDVIanual_SPEIsep_correlation.tif" ó "./03_NDVIanual_SPEIdic/", id, "_NDVIanual_SPEIdic_correlation.tif"
  writeRaster(pvalue_layer, paste0(ruta, "03_NDVIanual_SPEIdic/", id, "_NDVIanual_SPEIdic_pvalue.tif"), overwrite = TRUE) # Opciones: "./01_NDVIanual_SPEIanual/", id, "_NDVIanual_SPEIanual_pvalue.tif" ó "./02_NDVIanual_SPEIsep/", id, "_NDVIanual_SPEIsep_pvalue.tif" ó "./03_NDVIanual_SPEIdic/", id, "_NDVIanual_SPEIdic_pvalue.tif"
  
  cat(id, "CORR Y VALOR P-GUARDADOS\n")
}


# Rasters -----------------------------------------------------------------

# (second setwd removed — use extended_use_module above)

# Hacer esto con cada correlacion

ruta <- "./Correlaciones/NDVI anual/03_NDVIanual_SPEIdic"
N <- "NDVIanual_SPEIdic"

archivos <- list.files(path = ruta, pattern = "_correlation.tif$", full.names = TRUE)
archivos

lista_rasters <- lapply(archivos, rast)

raster_unido <- do.call(terra::mosaic, lista_rasters)

poligono <- st_read("./subcuencas_nombres/subcuencas_nombres.shp")

poligono <- st_transform(poligono, crs(raster_unido))

raster_recortado <- terra::mask(raster_unido, vect(poligono))

plot(raster_recortado)
plot(poligono, add = TRUE)

writeRaster(raster_recortado, paste0("./Correlaciones/",N,"_correlation.tif"), overwrite=TRUE)
getwd()

# Valores significativos

archivos <- list.files(path = ruta, pattern = "_pvalue.tif$", full.names = TRUE)

lista_rasters <- lapply(archivos, rast)

raster_unido <- do.call(terra::mosaic, lista_rasters)

raster_recortado <- terra::mask(raster_unido, vect(poligono))

plot(raster_recortado)

writeRaster(raster_recortado, paste0("./Correlaciones/",N,"_pvalue.tif"), overwrite=TRUE)
getwd()

# Mascara p value 0.05 

corr <- rast(paste0("./Correlaciones/",N,"_correlation.tif"))
pvalue <- rast(paste0("./Correlaciones/",N,"_pvalue.tif"))
mascara <- pvalue <= 0.05
corr_sign <- terra::mask(corr, mascara, maskvalues = FALSE, updatevalue = NA)
mascara_vegetacion <- rast("mascara_vegetacion.tif")
corr_sign <- resample(corr_sign, mascara_vegetacion)
resultado <- corr_sign
resultado[!is.na(corr_sign) & mascara_vegetacion == 0] <- NA
#resultado[is.na(corr_sign) & mascara_vegetacion == 1] <- 2
plot(resultado)
writeRaster(resultado, paste0("./Correlaciones/",N,"_corr_sign.tif"), overwrite = TRUE)
getwd()

rm(list = ls())

# Estadisticas descriptivas -----------------------------------------------

# Hacer esto con cada correlacion

# NDVI
## N <- "NDVIprim_SPEIsep"
## N <- "NDVIprim_SPEIdic"
## N <- "NDVIprim_SPEIanual"
## N <- "NDVIanual_SPEIanual"
## N <-  "NDVIanual_SPEIdic" 
## N <- "NDVIanual_SPEIsep"
## N <- "NDVIver_SPEIsep"
## N <- "NDVIver_SPEIdic" 
 N <-  "NDVIver_SPEIanual"

raster_correlation <- rast(paste0("./Correlaciones/", N, "_corr_sign.tif"))
plot(raster_correlation)

cuenca <- st_read("./subcuencas_nombres/subcuencas_nombres.shp")
plot(cuenca)
todas_cuencas <- st_read("./Subcuencas_solo_nombres_vect_y_raster/Todas_cuencas.shp")
plot(todas_cuencas)

cuenca <- st_transform(cuenca, crs(raster_correlation))
ref_extent <- ext(raster_correlation)
cuenca <- st_crop(cuenca, ref_extent)

todas_cuencas <- st_transform(todas_cuencas, crs(raster_correlation))
todas_cuencas <- st_crop(todas_cuencas, ref_extent)

raster_agriculture <- rast("./LandCover/raster_agriculture_ext.tif")
raster_forest <- rast("./LandCover/raster_forest_ext.tif")
raster_shrubland <- rast("./LandCover/raster_shrubland_ext.tif")
mascara_vegetacion <- rast("mascara_vegetacion.tif")

plot(raster_shrubland)
plot(cuenca)
plot(todas_cuencas)

subcuencas <- cuenca[3]

### STATS --------------------------------------------------------------------------------------------
# Para cada landcover, calcular la mediana y media de las correlaciones (todas las subcuencas).
# Calcular el porcentaje de pixeles que tienen correlaciones significativas
# Calcular el porcentaje de pixeles que tienen correlaciones significativas positivas
# Calcular el porcentaje de pixeles que tienen correlaciones significativas negativas

# 0. All Vegetation

landcover_mask <- mascara_vegetacion == 1 
plot(landcover_mask)

# NIVEL DE CUENCA
resultados_cuenca <- data.frame()

stats_cuenca <- exactextractr::exact_extract(raster_correlation, todas_cuencas, c("median", "mean"))
cuenca_df <- as.data.frame(stats_cuenca)

num_pixels_landcover_cuenca <- sum(values(landcover_mask) == 1, na.rm = TRUE)
num_pixels_with_data_cuenca <- sum(!is.na(values(raster_correlation)))

cuenca_df$Subbasin <- "ALL"
cuenca_df$Landcover <- "All Vegetation"

cuenca_df$Count_Pixels_landcover <- num_pixels_landcover_cuenca
cuenca_df$Count_Pixels_with_data <- num_pixels_with_data_cuenca
cuenca_df$Percentage_Significant_pixels <- num_pixels_with_data_cuenca*100/num_pixels_landcover_cuenca

vals_corr <- values(raster_correlation)

num_pixels_pos <- sum(vals_corr > 0, na.rm = TRUE)
num_pixels_neg <- sum(vals_corr < 0, na.rm = TRUE)

cuenca_df$Percentage_Positive_Significant_pixels <- num_pixels_pos * 100 / num_pixels_landcover_cuenca
cuenca_df$Percentage_Negative_Significant_pixels <- num_pixels_neg * 100 / num_pixels_landcover_cuenca

resultados_cuenca <- bind_rows(resultados_cuenca, cuenca_df)
print(resultados_cuenca)

# 1. agriculture ----

landcover_mask <- raster_agriculture == 1 
plot(landcover_mask)

masked_correlation <- mask(raster_correlation, landcover_mask, 
                           maskvalues = FALSE, updatevalue = NA)
plot(raster_correlation)
plot(masked_correlation)

writeRaster(masked_correlation,paste0("./Correlaciones/", N, "_agriculture.tif"), overwrite = TRUE)

# NIVEL DE CUENCA

stats_cuenca <- exactextractr::exact_extract(masked_correlation, todas_cuencas, c("median", "mean"))
cuenca_df <- as.data.frame(stats_cuenca)

num_pixels_landcover_cuenca <- sum(values(landcover_mask) == 1, na.rm = TRUE)
num_pixels_with_data_cuenca <- sum(!is.na(values(masked_correlation)))

cuenca_df$Subbasin <- "ALL"
cuenca_df$Landcover <- "agriculture"

cuenca_df$Count_Pixels_landcover <- num_pixels_landcover_cuenca
cuenca_df$Count_Pixels_with_data <- num_pixels_with_data_cuenca
cuenca_df$Percentage_Significant_pixels <- num_pixels_with_data_cuenca*100/num_pixels_landcover_cuenca

vals_corr <- values(masked_correlation)

num_pixels_pos <- sum(vals_corr > 0, na.rm = TRUE)
num_pixels_neg <- sum(vals_corr < 0, na.rm = TRUE)

cuenca_df$Percentage_Positive_Significant_pixels <- num_pixels_pos * 100 / num_pixels_landcover_cuenca
cuenca_df$Percentage_Negative_Significant_pixels <- num_pixels_neg * 100 / num_pixels_landcover_cuenca

resultados_cuenca <- bind_rows(resultados_cuenca, cuenca_df)
print(resultados_cuenca)

rm(masked_correlation)

# 2. forest ----
landcover_mask <- raster_forest == 1 
plot(landcover_mask)

masked_correlation <- mask(raster_correlation, landcover_mask, 
                           maskvalues = FALSE, updatevalue = NA)
plot(raster_correlation)
plot(masked_correlation)

writeRaster(masked_correlation,paste0("./Correlaciones/",N,"_forest.tif"), overwrite = TRUE)

# nivel de cuenca
stats_cuenca <- exactextractr::exact_extract(masked_correlation, todas_cuencas, c("median", "mean"))
cuenca_df <- as.data.frame(stats_cuenca)

num_pixels_landcover_cuenca <- sum(values(landcover_mask) == 1, na.rm = TRUE)
num_pixels_with_data_cuenca <- sum(!is.na(values(masked_correlation)))

cuenca_df$Subbasin <- "ALL"
cuenca_df$Landcover <- "forest"

cuenca_df$Count_Pixels_landcover <- num_pixels_landcover_cuenca
cuenca_df$Count_Pixels_with_data <- num_pixels_with_data_cuenca
cuenca_df$Percentage_Significant_pixels <- num_pixels_with_data_cuenca*100/num_pixels_landcover_cuenca

vals_corr <- values(masked_correlation)

num_pixels_pos <- sum(vals_corr > 0, na.rm = TRUE)
num_pixels_neg <- sum(vals_corr < 0, na.rm = TRUE)

cuenca_df$Percentage_Positive_Significant_pixels <- num_pixels_pos * 100 / num_pixels_landcover_cuenca
cuenca_df$Percentage_Negative_Significant_pixels <- num_pixels_neg * 100 / num_pixels_landcover_cuenca

resultados_cuenca <- bind_rows(resultados_cuenca, cuenca_df)
print(resultados_cuenca)

rm(masked_correlation)



# 3. shrubland -----
landcover_mask <- raster_shrubland == 1 
#plot(landcover_mask)

masked_correlation <- mask(raster_correlation, landcover_mask, 
                           maskvalues = FALSE, updatevalue = NA)
#plot(raster_correlation)
#plot(masked_correlation)

writeRaster(masked_correlation,paste0("./Correlaciones/",N,"_shrubland.tif"), overwrite = TRUE)

# nivel de cuenca
stats_cuenca <- exactextractr::exact_extract(masked_correlation, todas_cuencas, c("median", "mean"))
cuenca_df <- as.data.frame(stats_cuenca)

num_pixels_landcover_cuenca <- sum(values(landcover_mask) == 1, na.rm = TRUE)
num_pixels_with_data_cuenca <- sum(!is.na(values(masked_correlation)))

cuenca_df$Subbasin <- "ALL"
cuenca_df$Landcover <- "shrubland"

cuenca_df$Count_Pixels_landcover <- num_pixels_landcover_cuenca
cuenca_df$Count_Pixels_with_data <- num_pixels_with_data_cuenca
cuenca_df$Percentage_Significant_pixels <- num_pixels_with_data_cuenca*100/num_pixels_landcover_cuenca

vals_corr <- values(masked_correlation)

num_pixels_pos <- sum(vals_corr > 0, na.rm = TRUE)
num_pixels_neg <- sum(vals_corr < 0, na.rm = TRUE)

cuenca_df$Percentage_Positive_Significant_pixels <- num_pixels_pos * 100 / num_pixels_landcover_cuenca
cuenca_df$Percentage_Negative_Significant_pixels <- num_pixels_neg * 100 / num_pixels_landcover_cuenca

stats <- bind_rows(resultados_cuenca, cuenca_df)
print(resultados_cuenca)

rm(masked_correlation)

write.xlsx(stats, paste0("./STATS/stats_",N,".xlsx"))


