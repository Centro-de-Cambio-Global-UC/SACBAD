# 01. Estandarizacion datos SPEI


library(sp)
library(raster)
library(terra)
library(ggplot2)
library(tidyverse)
library(readxl)
library(dplyr)
library(readr)
library(terra)
library(data.table)
library(tidyr)
library(stringr)

ep <- Sys.getenv("ASC_EXTENDED_PATHS", unset = NA_character_)
if (is.na(ep) || !file.exists(ep)) {
  for (cand in c(
    file.path(getwd(), "Scripts", "extended", "extended_paths.R"),
    file.path(getwd(), "..", "extended_paths.R"),
    file.path(getwd(), "..", "..", "extended", "extended_paths.R")
  )) {
    if (file.exists(cand)) { ep <- cand; break }
  }
}
if (!file.exists(ep)) stop("Cannot find Scripts/extended/extended_paths.R")
source(ep)
extended_use_module("ndvi_spei_correlations")

# Datos SPEI (from core pipeline Excel export)
datos <- read_xlsx(extended_timeseries_xlsx())

glimpse(datos)
names(datos)

library(dplyr)

datos_sel <- datos %>% 
  select(
    Year,
    contains("SPEI-12 Hydro avg"),
    contains("SPEI-12 September"),
    contains("SPEI-12 December")
  )

names(datos_sel)

datos_tidied <- datos_sel %>% 
  pivot_longer(
    cols = -Year,
    names_to = "var",
    values_to = "valor"
  ) %>% 
  # 2) Separar "SPEI-12 Hydro avg (CQP)" en:
  #    tipo  = "SPEI-12 Hydro avg"
  #    ID    = "CQP"
  extract(
    col = var,
    into = c("tipo", "ID"),
    regex = "^(.*) \\((.*)\\)$"
  ) %>% 
  # 3) Pasar de largo a ancho para tener una columna por tipo
  mutate(
    tipo = case_when(
      tipo == "SPEI-12 Hydro avg" ~ "SPEI-12 Hydro avg",
      tipo == "SPEI-12 September" ~ "SPEI-12 September",
      tipo == "SPEI-12 December"  ~ "SPEI-12 December",
      TRUE ~ tipo
    )
  ) %>% 
  pivot_wider(
    id_cols = c(ID, Year),
    names_from = tipo,
    values_from = valor
  ) %>% 
  # 4) Renombrar Year a hydro_year
  rename(hydro_year = Year)

names(datos_tidied)

# Crear ID "MQ" cuyos valores sean el promedio simple de LQ y UQ para cada año

datos_MQ <- datos_tidied %>% 
  filter(ID %in% c("LQ", "UQ")) %>%            
  group_by(hydro_year) %>%                    
  summarise(
    ID = "MQ",                                 
    `SPEI-12 Hydro avg` = mean(`SPEI-12 Hydro avg`, na.rm = TRUE),
    `SPEI-12 September` = mean(`SPEI-12 September`,   na.rm = TRUE),
    `SPEI-12 December` = mean(`SPEI-12 December`,   na.rm = TRUE),
    .groups = "drop"
  )

# Unir con la tabla original
datos_SPEI <- datos_tidied %>% 
  bind_rows(datos_MQ) %>% arrange(hydro_year)

# Para las correlaciones, se va a estandarizar nuevamente el SPEI, con media 0 y desviación estándar 1 (estandarización z-score) 
summary(datos_SPEI)

datos_std <- datos_SPEI %>% 
  mutate(
    SPEI12anual_est = as.numeric(scale(`SPEI-12 Hydro avg`)),
    SPEI12sep_est = as.numeric(scale(`SPEI-12 September`)),
    SPEI12dic_est = as.numeric(scale(`SPEI-12 December`))
  )

summary(datos_std)


write_csv(datos_std, "datos_SPEI_2026.csv")
