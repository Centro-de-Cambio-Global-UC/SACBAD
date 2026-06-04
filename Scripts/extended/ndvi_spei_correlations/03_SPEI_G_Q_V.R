# All anual timeseries (CC1 Version Final > Bases de datos)
# Correlaciones entre SPEI - G - Q - Viirs

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
library(readxl)
library(janitor)

ep <- Sys.getenv("ASC_EXTENDED_PATHS", unset = file.path(getwd(), "..", "extended_paths.R"))
if (!file.exists(ep)) ep <- file.path(getwd(), "Scripts", "extended", "extended_paths.R")
source(ep)
extended_use_module("ndvi_spei_correlations")

# Place colleague Excel exports in Output/extended/ndvi_spei_correlations/ if needed:
path_all_ts <- file.path(EXT_REPO_ROOT, "Output", "extended", "ndvi_spei_correlations",
                         "All_annual_timeseries.xlsx")
if (!file.exists(path_all_ts)) {
  path_all_ts <- file.path(EXT_WORK_DIR, "All_annual timeseries.xlsx")
}
data <- read_excel(path_all_ts)

glimpse(data)

datos <- data %>% select(Year, `Groundwater depth (m .b.t) (UP)`:`Streamflow (m3/s) (UL)`)
glimpse(datos)

spei_path <- file.path(EXT_WORK_DIR, "datos_SPEI_2026.csv")
if (!file.exists(spei_path)) spei_path <- extended_spei_jv_csv()
SPEI <- read_csv(spei_path)
names(SPEI)

datos_sep <- datos %>% 
  pivot_longer(
    cols = -Year,
    names_to = "var",
    values_to = "valor"
  ) %>% 
  extract(
    col = var,
    into = c("tipo", "ID"),
    regex = "^(.*) \\((.*)\\)$"
  ) %>% 
  mutate(
    tipo = case_when(
      tipo == "Groundwater depth (m .b.t)" ~ "G",
      tipo == "Streamflow (m3/s)" ~ "Q",
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

datos_sep
glimpse(datos_sep)

# Reordenar las subcuencas

datos_sep$ID <- factor(datos_sep$ID, levels = c("LQ","UP", "MP", "LP", "UL", "ML", "LL"))
levels(datos_sep$ID)

SPEI$ID <- factor(SPEI$ID, 
                      levels = 
                        c("UQ", "MQ", "LQ", "CQP", "UP", "MP", "LP", "UL", "ML", "LL"))
levels(SPEI$ID)

# Unir IPE, G y Q

names(SPEI)
names(datos_sep)

datos <- left_join(SPEI, datos_sep, 
                   by = c("ID"="ID", "hydro_year" = "hydro_year"))

names(datos)

summary(datos)

datos <- datos %>% mutate(G_est = scale(G)[,1],
                          Q_est = scale(Q)[,1])

summary(datos)

#write_csv2(datos, "SPEI_G_Q_para_analisis.csv")

datos <- read_csv2("SPEI_G_Q_para_analisis.csv")

# Correlacion Q - G - SPEI -------------------------------------------------

# Reordenar las subcuencas

datos <- datos %>% mutate(ID = as.factor(ID))

levels(datos$ID)
datos$ID <- factor(datos$ID, levels = c("UQ", "MQ", "LQ", "CQP", "UP", "MP", "LP", "UL", "ML", "LL"))
levels(datos$ID)

names(datos)

# 1. SPEI anual con G est, todos los años  ----

cor1 <- datos %>%
  group_by(ID) %>%
  summarise(correlacion = cor(SPEI12anual_est, G_est, use = "na.or.complete"))
cor1

write_csv(cor1, "cor1_SPEI_G.csv")

# 2. SPEI anual con Q est, todos los años  ----

cor2 <- datos %>%
  group_by(ID) %>%
  summarise(correlacion = cor(SPEI12anual_est, Q_est, use = "na.or.complete"))
cor2

write_csv(cor2, "cor2__SPEI_Q.csv")

# Viirs -------------------------------------------------------------------

data <- read_excel("resultados_por_subcuencas_anual_hidrologico_VIIRS.xlsx") %>% janitor::clean_names()
names(data)
glimpse(data)

data_viirs <- data %>% 
  pivot_longer(
    cols = -ano_hidrologico,
    names_to = "var",
    values_to = "valor"
  ) %>% 
  extract(
    col = var,
    into = c("tipo", "ID"),
    regex = "^(.*)_(.*)$"
  ) %>% 
  mutate(
    tipo = case_when(
      tipo == "viirs_area_ha_with_positive_radiance" ~ "VIIRS",
      TRUE ~ tipo
    )
  ) %>% 
  pivot_wider(
    id_cols = c(ID, ano_hidrologico),
    names_from = tipo,
    values_from = valor
  ) %>% 
  rename(hydro_year = ano_hidrologico)

head(data_viirs)

data_viirs <- data_viirs %>% mutate(
  ID = case_when(
    ID == "mq" ~ "MQ",
    ID == "uq" ~ "UQ",
    ID == "lq" ~ "LQ",
    ID == "mp" ~ "MP",
    ID == "lp" ~ "LP",
    ID == "cqp" ~ "CQP",
    ID == "up" ~ "UP",
    ID == "ul" ~ "UL",
    ID == "ml" ~ "ML",
    ID == "ll" ~ "LL",
    TRUE ~ ID
  )
)

summary(data_viirs)

data_viirs <- data_viirs %>% mutate(VIIRS_est = scale(VIIRS)[,1])

data_viirs %>% count(ID)

# Reordenar las subcuencas

datos <- left_join(datos, data_viirs, 
                   by = c("ID"="ID",
                          "hydro_year" = "hydro_year"))

names(datos)

#write_csv2(datos, "SPEI_G_Q_v_para_analisis.csv")

datos <- read_csv2("SPEI_G_Q_v_para_analisis.csv")
names(datos)

datos <- datos %>% mutate(ID = as.factor(ID))

levels(datos$ID)
datos$ID <- factor(datos$ID, levels = c("UQ", "MQ", "LQ", "CQP", "UP", "MP", "LP", "UL", "ML", "LL"))
levels(datos$ID)

names(datos)

# 3. SPEI y Viirs, todos los años ----

cor3 <- datos %>%
  group_by(ID) %>%
  summarise(correlacion = cor(SPEI12anual_est, VIIRS_est, use = "na.or.complete"))
cor3

write_csv(cor3, "cor3_SPEI_VIIRS.csv")
